import CryptoKit
import Foundation

enum WealthCorrectionError: Error, Equatable, Sendable {
    case staleDraft, operationConflict, invalidRequest, invalidHistory, maintenanceUnavailable
}

struct WealthEditToken: Codable, Equatable, Sendable {
    let targetID: UUID
    let stateDigest: String
    let latestHistoryID: UUID?
    let storeID: UUID
    let epoch: UUID
}

struct WealthEditContext: Sendable {
    let record: WealthContainer
    let token: WealthEditToken
}

enum WealthFXIntent: String, Codable, Sendable {
    case preserve
    case newInput
}

struct WealthCorrectionRequest: Sendable {
    let candidate: WealthContainer
    let expected: WealthEditToken
    let operationID: UUID
    let reason: String
    let occurredAt: UTCInstant
    let fxIntent: WealthFXIntent
}

struct WealthCurrentValuationRequest: Sendable {
    let candidate: WealthContainer
    let expected: WealthEditToken
    let occurredAt: UTCInstant
    let fxIntent: WealthFXIntent
}

enum WealthCorrectionCurrentState: String, Sendable {
    case unchanged, changed, deleted
}

enum WealthCorrectionResult: Sendable {
    case applied(WealthCorrectionHistory)
    case alreadyApplied(WealthCorrectionHistory, WealthCorrectionCurrentState)
    case noChange
    case minorUpdate
}

enum WealthCurrentValuationResult: Equatable, Sendable {
    case noChange, updated
}

// A bounded, typed historical snapshot. Names, notes, and current aggregate totals are not authority here.
struct WealthCorrectionProjection: Codable, Equatable, Sendable {
    enum Details: Codable, Equatable, Sendable {
        case bankCash(balance: Money, interestRate: Percentage?)
        case security(ticker: String, mic: String?, quantity: AssetQuantity, manualPrice: MarketPrice)
        case insurance(company: String, productName: String, premium: Money,
                       paymentFrequency: InsurancePaymentFrequency, coverage: Money,
                       currentCashValue: Money, startDate: CivilDate, maturityDate: CivilDate?)
        case otherAsset(categoryDescription: String, currentValue: Money)
        case liability(outstandingBalance: Money, interestRate: Percentage?)

        init(_ value: WealthRecordDetails) {
            switch value {
            case let .bankCash(balance, rate): self = .bankCash(balance: balance, interestRate: rate)
            case let .security(ticker, mic, quantity, price): self = .security(ticker: ticker, mic: mic, quantity: quantity, manualPrice: price)
            case let .insurance(company, name, premium, frequency, coverage, value, start, maturity):
                self = .insurance(company: company, productName: name, premium: premium,
                    paymentFrequency: frequency, coverage: coverage, currentCashValue: value,
                    startDate: start, maturityDate: maturity)
            case let .otherAsset(description, value): self = .otherAsset(categoryDescription: description, currentValue: value)
            case let .liability(balance, rate): self = .liability(outstandingBalance: balance, interestRate: rate)
            }
        }

        var domain: WealthRecordDetails {
            switch self {
            case let .bankCash(balance, rate): .bankCash(balance: balance, interestRate: rate)
            case let .security(ticker, mic, quantity, price): .security(ticker: ticker, mic: mic, quantity: quantity, manualPrice: price)
            case let .insurance(company, name, premium, frequency, coverage, value, start, maturity):
                .insurance(company: company, productName: name, premium: premium,
                    paymentFrequency: frequency, coverage: coverage, currentCashValue: value,
                    startDate: start, maturityDate: maturity)
            case let .otherAsset(description, value): .otherAsset(categoryDescription: description, currentValue: value)
            case let .liability(balance, rate): .liability(outstandingBalance: balance, interestRate: rate)
            }
        }

        func permitsCurrentValuationChange(to next: Self) -> Bool {
            switch (self, next) {
            case let (.bankCash(_, a), .bankCash(_, b)), let (.liability(_, a), .liability(_, b)):
                return a == b
            case let (.security(a, b, c, _), .security(d, e, f, _)):
                return a == d && b == e && c == f
            case let (.insurance(a, b, c, d, e, _, f, g), .insurance(h, i, j, k, l, _, m, n)):
                return a == h && b == i && c == j && d == k && e == l && f == m && g == n
            case let (.otherAsset(a, _), .otherAsset(b, _)):
                return a == b
            default: return false
            }
        }
    }

    let id: UUID
    let accountID: UUID?
    let kind: AssetContainerKind
    let institution: String?
    let primaryCurrency: CurrencyCode
    let createdDate: CivilDate
    let details: Details
    let valuation: FXValuation

    init(_ record: WealthContainer) {
        let c = record.container
        id = c.id; accountID = c.accountID; kind = c.kind; institution = c.institution
        primaryCurrency = c.primaryCurrency; createdDate = c.createdDate
        details = Details(record.details); valuation = record.valuation
    }

    func hasSameImportantValues(as other: Self) -> Bool {
        id == other.id && accountID == other.accountID && kind == other.kind
            && institution == other.institution && primaryCurrency == other.primaryCurrency
            && createdDate == other.createdDate && details == other.details
            && valuation.original == other.valuation.original
            && valuation.rate == other.valuation.rate
            && valuation.convertedCNY == other.valuation.convertedCNY
            && valuation.referenceDate == other.valuation.referenceDate
            && valuation.providerIdentifier == other.valuation.providerIdentifier
            && valuation.isManualOverride == other.valuation.isManualOverride
            && valuation.isStale == other.valuation.isStale
    }

    func validate() throws {
        guard !(institution?.contains("\0") ?? false) else { throw WealthCorrectionError.invalidHistory }
        _ = try CivilDate(canonical: createdDate.description)
        _ = try CivilDate(canonical: valuation.referenceDate.description)
        let rebuiltRate = try FXRate(coefficient: valuation.rate.coefficient,
            sourceCurrency: valuation.rate.sourceCurrency, targetCurrency: valuation.rate.targetCurrency)
        let rebuilt = try FXValuation(original: valuation.original, rate: rebuiltRate,
            referenceDate: valuation.referenceDate, fetchedAt: valuation.fetchedAt,
            providerIdentifier: valuation.providerIdentifier,
            isManualOverride: valuation.isManualOverride, isStale: valuation.isStale)
        guard rebuilt == valuation, !valuation.providerIdentifier.isEmpty,
              !valuation.providerIdentifier.contains("\0"),
              valuation.original.minorUnits >= 0, valuation.convertedCNY.minorUnits >= 0 else {
            throw WealthCorrectionError.invalidHistory
        }
        switch valuation.original.currency {
        case .cny:
            guard valuation.rate == .cnyIdentity,
                  valuation.convertedCNY == valuation.original,
                  valuation.providerIdentifier == "identity",
                  !valuation.isManualOverride else {
                throw WealthCorrectionError.invalidHistory
            }
        case .usd:
            guard valuation.rate.sourceCurrency == .usd,
                  valuation.rate.targetCurrency == .cny,
                  valuation.isManualOverride,
                  valuation.providerIdentifier.localizedCaseInsensitiveContains("manual") else {
                throw WealthCorrectionError.invalidHistory
            }
        }
        switch details {
        case let .security(_, _, _, price):
            _ = try MarketPrice(coefficient: price.coefficient, quoteCurrency: price.quoteCurrency)
        case let .insurance(_, _, _, _, _, _, start, maturity):
            _ = try CivilDate(canonical: start.description)
            if let maturity { _ = try CivilDate(canonical: maturity.description) }
        default: break
        }
        let container = AssetContainer(id: id, accountID: accountID, name: "Historical projection",
            kind: kind, institution: institution, primaryCurrency: primaryCurrency,
            notes: nil, createdDate: createdDate, updatedDate: createdDate)
        _ = try WealthContainer(container: container, details: details.domain, valuation: valuation)
    }
}

struct WealthDeletionContext: Codable, Equatable, Sendable {
    struct Link: Codable, Equatable, Sendable {
        let documentID: UUID
        let linkID: UUID
        let createdAt: UTCInstant
        let meaning: String
    }
    let origin: String
    let links: [Link]
}

struct WealthHistoryPayload: Codable, Equatable, Sendable {
    let version: Int
    let before: WealthCorrectionProjection
    let after: WealthCorrectionProjection?
    let deletion: WealthDeletionContext?

    func validate(kind: String) throws {
        guard version == 1 else { throw WealthCorrectionError.invalidHistory }
        try before.validate()
        switch kind {
        case "correction":
            guard let after, deletion == nil, after.id == before.id,
                  after.createdDate == before.createdDate,
                  !before.hasSameImportantValues(as: after) else { throw WealthCorrectionError.invalidHistory }
            try after.validate()
        case "deletionContext":
            guard after == nil, let deletion, deletion.origin == "existingDeleteAPI",
                  deletion.links.map(\.linkID.uuidString) == deletion.links.map(\.linkID.uuidString).sorted(),
                  Set(deletion.links.map(\.linkID)).count == deletion.links.count,
                  deletion.links.allSatisfy({ !$0.meaning.contains("\0") }) else {
                throw WealthCorrectionError.invalidHistory
            }
        default: throw WealthCorrectionError.invalidHistory
        }
    }
}

struct WealthCorrectionHistory: Equatable, Sendable {
    let sequence: Int64
    let id: UUID
    let operationID: UUID
    let targetID: UUID
    let kind: String
    let occurredAt: UTCInstant
    let reason: String?
    let payload: WealthHistoryPayload
}

enum WealthCorrectionEncoding {
    static func data<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    static func digest<T: Encodable>(_ value: T) throws -> String {
        SHA256.hash(data: try data(value)).map { String(format: "%02x", $0) }.joined()
    }
    static func reason(_ value: String) throws -> String {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty, result.count <= 500, !result.contains("\0") else {
            throw WealthCorrectionError.invalidRequest
        }
        return result
    }
    struct Candidate: Encodable {
        let container: AssetContainer
        let details: WealthCorrectionProjection.Details
        let valuation: FXValuation
        init(_ value: WealthContainer) {
            container = value.container; details = .init(value.details); valuation = value.valuation
        }
    }
    struct Request: Encodable {
        let candidate: Candidate
        let expected: WealthEditToken
        let reason: String
        let occurredAt: UTCInstant
        let fxIntent: WealthFXIntent
    }
}
