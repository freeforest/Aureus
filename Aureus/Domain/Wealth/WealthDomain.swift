import Foundation

enum WealthDomainError: Error, Equatable, Sendable {
    case emptyName
    case invalidKindDetails
    case negativeValue
    case negativeQuantity
    case invalidInterestRate
    case missingManualFX
    case invalidManualFXSource
    case valuationMismatch
    case invalidInsuranceDates
    case invalidMIC
    case invalidTicker
}

enum InsurancePaymentFrequency: String, CaseIterable, Codable, Equatable, Sendable {
    case monthly
    case quarterly
    case semiAnnual
    case annual
    case single

    var title: String {
        switch self {
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .semiAnnual: "Semi-annual"
        case .annual: "Annual"
        case .single: "Single premium"
        }
    }
}

struct ManualFXInput: Codable, Equatable, Sendable {
    let rate: FXRate
    let source: String
    let referenceDate: CivilDate
    let recordedAt: UTCInstant
    let isStale: Bool

    init(
        rate: FXRate,
        source: String = "manual",
        referenceDate: CivilDate,
        recordedAt: UTCInstant,
        isStale: Bool
    ) throws {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              source.localizedCaseInsensitiveContains("manual") else {
            throw WealthDomainError.invalidManualFXSource
        }
        self.rate = rate
        self.source = source
        self.referenceDate = referenceDate
        self.recordedAt = recordedAt
        self.isStale = isStale
    }
}

enum WealthRecordDetails: Equatable, Sendable {
    case bankCash(balance: Money, interestRate: Percentage?)
    case security(
        ticker: String,
        mic: String?,
        quantity: AssetQuantity,
        manualPrice: MarketPrice
    )
    case insurance(
        company: String,
        productName: String,
        premium: Money,
        paymentFrequency: InsurancePaymentFrequency,
        coverage: Money,
        currentCashValue: Money,
        startDate: CivilDate,
        maturityDate: CivilDate?
    )
    case otherAsset(categoryDescription: String, currentValue: Money)
    case liability(outstandingBalance: Money, interestRate: Percentage?)

    func currentValue() throws -> Money {
        switch self {
        case let .bankCash(balance, _): return balance
        case let .security(_, _, quantity, manualPrice):
            return try WealthValuation.marketValue(quantity: quantity, price: manualPrice)
        case let .insurance(_, _, _, _, _, currentCashValue, _, _): return currentCashValue
        case let .otherAsset(_, currentValue): return currentValue
        case let .liability(outstandingBalance, _): return outstandingBalance
        }
    }
}

struct WealthContainer: Identifiable, Equatable, Sendable {
    var id: UUID { container.id }

    let container: AssetContainer
    let details: WealthRecordDetails
    let valuation: FXValuation
    let originalValue: Money

    init(
        container: AssetContainer,
        details: WealthRecordDetails,
        valuation: FXValuation
    ) throws {
        guard !container.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WealthDomainError.emptyName
        }
        try Self.validate(container: container, details: details)
        let currentValue = try details.currentValue()
        guard currentValue.minorUnits >= 0 else { throw WealthDomainError.negativeValue }
        guard currentValue.currency == container.primaryCurrency,
              valuation.original == currentValue,
              valuation.convertedCNY.currency == .cny,
              valuation.convertedCNY.minorUnits >= 0 else {
            throw WealthDomainError.valuationMismatch
        }
        self.container = container
        self.details = details
        self.valuation = valuation
        self.originalValue = currentValue
    }

    var convertedCNYValue: Money { valuation.convertedCNY }
    var isLiability: Bool { container.kind == .liability }

    private static func validate(container: AssetContainer, details: WealthRecordDetails) throws {
        switch (container.kind, details) {
        case let (.bankCash, .bankCash(_, interestRate)),
             let (.liability, .liability(_, interestRate)):
            if let interestRate, interestRate.coefficient < 0 {
                throw WealthDomainError.invalidInterestRate
            }
        case let (.stock, .security(ticker, mic, quantity, _)),
             let (.etf, .security(ticker, mic, quantity, _)),
             let (.fund, .security(ticker, mic, quantity, _)):
            guard !ticker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WealthDomainError.invalidTicker
            }
            guard quantity.coefficient >= 0 else { throw WealthDomainError.negativeQuantity }
            if let mic {
                let normalized = mic.uppercased()
                guard normalized.count == 4,
                      normalized.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
                    throw WealthDomainError.invalidMIC
                }
            }
        case let (.insurance, .insurance(company, productName, premium, _, coverage, _, start, maturity)):
            guard !company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  premium.minorUnits >= 0,
                  coverage.minorUnits >= 0,
                  premium.currency == container.primaryCurrency,
                  coverage.currency == container.primaryCurrency else {
                throw WealthDomainError.invalidKindDetails
            }
            if let maturity, maturity < start {
                throw WealthDomainError.invalidInsuranceDates
            }
        case let (.otherAsset, .otherAsset(description, _)):
            guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WealthDomainError.invalidKindDetails
            }
        default:
            throw WealthDomainError.invalidKindDetails
        }
    }
}

struct WealthSummary: Codable, Equatable, Sendable {
    let totalAssetsCNY: Money
    let totalLiabilitiesCNY: Money
    let netWorthCNY: Money

    static let zero = WealthSummary(
        totalAssetsCNY: Money(minorUnits: 0, currency: .cny),
        totalLiabilitiesCNY: Money(minorUnits: 0, currency: .cny),
        netWorthCNY: Money(minorUnits: 0, currency: .cny)
    )
}

enum WealthValuation {
    static func marketValue(quantity: AssetQuantity, price: MarketPrice) throws -> Money {
        guard quantity.coefficient >= 0 else { throw WealthDomainError.negativeQuantity }
        return try Money(
            decimal: quantity.decimal * price.decimal,
            currency: price.quoteCurrency
        )
    }

    static func valuation(
        original: Money,
        manualFX: ManualFXInput?,
        identityDate: CivilDate,
        recordedAt: UTCInstant
    ) throws -> FXValuation {
        guard original.minorUnits >= 0 else { throw WealthDomainError.negativeValue }
        switch original.currency {
        case .cny:
            return try FXValuation(
                original: original,
                rate: .cnyIdentity,
                referenceDate: identityDate,
                fetchedAt: recordedAt,
                providerIdentifier: "identity",
                isManualOverride: false,
                isStale: false
            )
        case .usd:
            guard let manualFX else { throw WealthDomainError.missingManualFX }
            guard manualFX.rate.sourceCurrency == .usd,
                  manualFX.rate.targetCurrency == .cny else {
                throw FinancialValueError.directionMismatch
            }
            return try FXValuation(
                original: original,
                rate: manualFX.rate,
                referenceDate: manualFX.referenceDate,
                fetchedAt: manualFX.recordedAt,
                providerIdentifier: manualFX.source,
                isManualOverride: true,
                isStale: manualFX.isStale
            )
        }
    }

    static func aggregate(_ records: [WealthContainer]) throws -> WealthSummary {
        var assets = Money(minorUnits: 0, currency: .cny)
        var liabilities = Money(minorUnits: 0, currency: .cny)
        for record in records {
            if record.isLiability {
                liabilities = try liabilities.adding(record.convertedCNYValue)
            } else {
                assets = try assets.adding(record.convertedCNYValue)
            }
        }
        return WealthSummary(
            totalAssetsCNY: assets,
            totalLiabilitiesCNY: liabilities,
            netWorthCNY: try assets.subtracting(liabilities)
        )
    }
}

struct ContainerDeletionImpact: Equatable, Sendable {
    let wealthRecordCount: Int
    let linkedAssetCount: Int
    let linkedInsurancePolicyCount: Int

    var hasProtectedPermanentDependents: Bool {
        linkedAssetCount > 0 || linkedInsurancePolicyCount > 0
    }
}
