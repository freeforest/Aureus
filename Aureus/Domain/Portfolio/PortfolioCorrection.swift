import CryptoKit
import Foundation

enum PortfolioCorrectionError: Error, Equatable, Sendable {
    case staleDraft, operationConflict, invalidRequest, invalidHistory, maintenanceUnavailable
}

struct PortfolioActivityEditToken: Codable, Equatable, Sendable {
    let targetID: UUID
    let stateDigest: String
    let latestHistoryID: UUID?
    let storeID: UUID
    let epoch: UUID
}

struct PortfolioActivityEditContext: Sendable {
    let activity: PortfolioActivity
    let link: PortfolioSecurityLink
    let token: PortfolioActivityEditToken
}

struct PortfolioCorrectionRequest: Sendable {
    let candidate: PortfolioActivity
    let expected: PortfolioActivityEditToken
    let operationID: UUID
    let reason: String
    let occurredAt: UTCInstant
}

enum PortfolioCorrectionCurrentState: String, Sendable {
    case unchanged, changed, deleted
}

enum PortfolioCorrectionResult: Sendable {
    case applied(PortfolioCorrectionHistory)
    case alreadyApplied(PortfolioCorrectionHistory, PortfolioCorrectionCurrentState)
    case noChange, minorUpdate
}

// A historical financial projection, never an alternative live FIFO or NAV authority.
struct PortfolioCorrectionProjection: Codable, Equatable, Sendable {
    enum Details: Codable, Equatable, Sendable {
        case openingLot(quantity: AssetQuantity, totalCost: Money, fx: PortfolioFXProvenance, note: String?)
        case buy(quantity: AssetQuantity, unitPrice: MarketPrice, fee: Money, fx: PortfolioFXProvenance)
        case sell(quantity: AssetQuantity, unitPrice: MarketPrice, fee: Money, fx: PortfolioFXProvenance)
        case manualSplit(from: Ratio, to: Ratio)

        init(_ payload: PortfolioActivityPayload) {
            switch payload {
            case let .openingLot(q, c, fx, note): self = .openingLot(quantity: q, totalCost: c, fx: fx, note: note)
            case let .buy(q, p, fee, fx): self = .buy(quantity: q, unitPrice: p, fee: fee, fx: fx)
            case let .sell(q, p, fee, fx): self = .sell(quantity: q, unitPrice: p, fee: fee, fx: fx)
            case let .manualSplit(a, b): self = .manualSplit(from: a, to: b)
            }
        }

        var domain: PortfolioActivityPayload {
            switch self {
            case let .openingLot(q, c, fx, note): .openingLot(quantity: q, totalCost: c, fx: fx, note: note)
            case let .buy(q, p, fee, fx): .buy(quantity: q, unitPrice: p, fee: fee, fx: fx)
            case let .sell(q, p, fee, fx): .sell(quantity: q, unitPrice: p, fee: fee, fx: fx)
            case let .manualSplit(a, b): .manualSplit(from: a, to: b)
            }
        }

        var important: Self {
            if case let .openingLot(q, c, fx, _) = self {
                return .openingLot(quantity: q, totalCost: c, fx: fx, note: nil)
            }
            return self
        }

        func validate() throws {
            switch self {
            case let .openingLot(_, cost, fx, _):
                try Self.validateFX(fx)
                guard cost == fx.original else { throw PortfolioCorrectionError.invalidHistory }
            case let .buy(_, price, _, fx), let .sell(_, price, _, fx):
                _ = try MarketPrice(coefficient: price.coefficient, quoteCurrency: price.quoteCurrency)
                try Self.validateFX(fx)
            case .manualSplit: break
            }
        }

        private static func validateFX(_ fx: PortfolioFXProvenance) throws {
            let date = try CivilDate(canonical: fx.referenceDate.description)
            let rate = try FXRate(coefficient: fx.rate.coefficient,
                sourceCurrency: fx.rate.sourceCurrency, targetCurrency: fx.rate.targetCurrency)
            let rebuilt = try PortfolioFXProvenance(original: fx.original, rate: rate,
                source: fx.source, referenceDate: date, recordedAt: fx.recordedAt,
                isManual: fx.isManual, isStale: fx.isStale)
            guard rebuilt == fx, !fx.source.contains("\0"), fx.original.minorUnits >= 0,
                  fx.convertedCNY.minorUnits >= 0 else { throw PortfolioCorrectionError.invalidHistory }
        }
    }

    let id: UUID
    let portfolioID: UUID
    let securityLinkID: UUID
    let civilDate: CivilDate
    let recordedAt: UTCInstant
    let exchangeTimeZoneIdentifier: String
    let ledgerEntryID: UUID?
    let details: Details
    let link: PortfolioSecurityLink

    init(_ activity: PortfolioActivity, link: PortfolioSecurityLink) {
        id = activity.id; portfolioID = activity.portfolioID
        securityLinkID = activity.securityLinkID; civilDate = activity.civilDate
        recordedAt = activity.recordedAt; exchangeTimeZoneIdentifier = activity.exchangeTimeZoneIdentifier
        ledgerEntryID = activity.ledgerEntryID; details = .init(activity.payload)
        self.link = link
    }

    func hasSameImportantValues(as other: Self) -> Bool {
        id == other.id && portfolioID == other.portfolioID
            && securityLinkID == other.securityLinkID && civilDate == other.civilDate
            && recordedAt == other.recordedAt
            && exchangeTimeZoneIdentifier == other.exchangeTimeZoneIdentifier
            && ledgerEntryID == other.ledgerEntryID && details.important == other.details.important
            && link == other.link
    }

    func validate() throws {
        _ = try CivilDate(canonical: civilDate.description)
        let checkedLink = try PortfolioSecurityLink(id: link.id, portfolioID: link.portfolioID,
            wealthContainerID: link.wealthContainerID, symbol: link.symbol, rawMIC: link.rawMIC,
            currency: link.currency, assetKind: link.assetKind, sortOrder: link.sortOrder)
        guard checkedLink == link, link.id == securityLinkID, link.portfolioID == portfolioID else {
            throw PortfolioCorrectionError.invalidHistory
        }
        try details.validate()
        let rebuilt = try PortfolioActivity(id: id, portfolioID: portfolioID,
            securityLinkID: securityLinkID, civilDate: civilDate, recordedAt: recordedAt,
            exchangeTimeZoneIdentifier: exchangeTimeZoneIdentifier,
            ledgerEntryID: ledgerEntryID, payload: details.domain)
        guard Details(rebuilt.payload) == details else { throw PortfolioCorrectionError.invalidHistory }
        switch details {
        case let .openingLot(_, _, fx, _), let .buy(_, _, _, fx), let .sell(_, _, _, fx):
            guard fx.original.currency == link.currency else { throw PortfolioCorrectionError.invalidHistory }
        case .manualSplit: break
        }
    }
}

struct PortfolioDeletionContext: Codable, Equatable, Sendable {
    struct EvidenceLink: Codable, Equatable, Sendable {
        let documentID: UUID
        let linkID: UUID
        let createdAt: UTCInstant
        let meaning: String
    }
    let origin: String
    let evidenceLinks: [EvidenceLink]
    let ledgerEntryID: UUID?
}

struct PortfolioHistoryPayload: Codable, Equatable, Sendable {
    let version: Int
    let before: PortfolioCorrectionProjection
    let after: PortfolioCorrectionProjection?
    let deletion: PortfolioDeletionContext?

    func validate(kind: String) throws {
        guard version == 1 else { throw PortfolioCorrectionError.invalidHistory }
        try before.validate()
        switch kind {
        case "correction":
            guard let after, deletion == nil, after.id == before.id,
                  after.portfolioID == before.portfolioID,
                  !before.hasSameImportantValues(as: after) else {
                throw PortfolioCorrectionError.invalidHistory
            }
            try after.validate()
        case "deletionContext":
            guard after == nil, let deletion,
                  ["existingDeleteActivityAPI", "existingUnlinkSecurityAPI", "existingDeletePortfolioAPI"]
                    .contains(deletion.origin),
                  deletion.ledgerEntryID == before.ledgerEntryID,
                  deletion.evidenceLinks.map(\.linkID.uuidString)
                    == deletion.evidenceLinks.map(\.linkID.uuidString).sorted(),
                  Set(deletion.evidenceLinks.map(\.linkID)).count == deletion.evidenceLinks.count,
                  deletion.evidenceLinks.allSatisfy({ !$0.meaning.contains("\0") }) else {
                throw PortfolioCorrectionError.invalidHistory
            }
        case "ledgerDetachContext":
            guard let after, let deletion, deletion.origin == "existingDeleteLedgerAPI",
                  deletion.evidenceLinks.isEmpty,
                  deletion.ledgerEntryID != nil,
                  before.ledgerEntryID == deletion.ledgerEntryID,
                  after.ledgerEntryID == nil,
                  after.id == before.id, after.portfolioID == before.portfolioID else {
                throw PortfolioCorrectionError.invalidHistory
            }
            try after.validate()
            let expected = PortfolioCorrectionProjection(
                try PortfolioActivity(id: before.id, portfolioID: before.portfolioID,
                    securityLinkID: before.securityLinkID, civilDate: before.civilDate,
                    recordedAt: before.recordedAt,
                    exchangeTimeZoneIdentifier: before.exchangeTimeZoneIdentifier,
                    ledgerEntryID: nil, payload: before.details.domain), link: before.link)
            guard expected == after else { throw PortfolioCorrectionError.invalidHistory }
        default: throw PortfolioCorrectionError.invalidHistory
        }
    }
}

struct PortfolioCorrectionHistory: Equatable, Sendable {
    let sequence: Int64
    let id: UUID
    let operationID: UUID
    let targetID: UUID
    let kind: String
    let occurredAt: UTCInstant
    let reason: String?
    let payload: PortfolioHistoryPayload
}

enum PortfolioCorrectionEncoding {
    static func data<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    static func digest<T: Encodable>(_ value: T) throws -> String {
        SHA256.hash(data: try data(value)).map { String(format: "%02x", $0) }.joined()
    }
    static func reason(_ raw: String) throws -> String {
        let reason = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty, reason.count <= 500, !reason.contains("\0") else {
            throw PortfolioCorrectionError.invalidRequest
        }
        return reason
    }
    struct Candidate: Encodable {
        let id: UUID
        let portfolioID: UUID
        let securityLinkID: UUID
        let civilDate: CivilDate
        let recordedAt: UTCInstant
        let exchangeTimeZoneIdentifier: String
        let ledgerEntryID: UUID?
        let details: PortfolioCorrectionProjection.Details

        init(_ activity: PortfolioActivity) {
            id = activity.id; portfolioID = activity.portfolioID
            securityLinkID = activity.securityLinkID; civilDate = activity.civilDate
            recordedAt = activity.recordedAt
            exchangeTimeZoneIdentifier = activity.exchangeTimeZoneIdentifier
            ledgerEntryID = activity.ledgerEntryID
            details = .init(activity.payload)
        }
    }
    struct Request: Encodable {
        let candidate: Candidate
        let expected: PortfolioActivityEditToken
        let operationID: UUID
        let reason: String
        let occurredAt: UTCInstant
    }
}
