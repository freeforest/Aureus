import Foundation

enum PortfolioDomainError: Error, Equatable, Sendable {
    case emptyName
    case invalidIdentifier
    case invalidMIC
    case unsupportedSecurity
    case duplicateSecurity
    case invalidActivity
    case nonPositiveQuantity
    case negativeFee
    case currencyMismatch
    case fxMismatch
    case oversell
    case divisionByZero
    case arithmeticOverflow
    case lossOfPrecision
    case missingWealthMark
    case insufficientBenchmarkOverlap
}

struct PortfolioRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    let baseCurrency: CurrencyCode
    let createdAt: UTCInstant
    var updatedAt: UTCInstant
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        baseCurrency: CurrencyCode = .cny,
        createdAt: UTCInstant,
        updatedAt: UTCInstant,
        sortOrder: Int
    ) throws {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw PortfolioDomainError.emptyName }
        guard baseCurrency == .cny else { throw PortfolioDomainError.currencyMismatch }
        self.id = id
        self.name = normalized
        self.baseCurrency = baseCurrency
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
    }
}

struct PortfolioSecurityLink: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let portfolioID: UUID
    let wealthContainerID: UUID
    let symbol: String
    let rawMIC: String
    let currency: CurrencyCode
    let assetKind: AssetContainerKind
    let sortOrder: Int

    init(
        id: UUID = UUID(),
        portfolioID: UUID,
        wealthContainerID: UUID,
        symbol: String,
        rawMIC: String,
        currency: CurrencyCode,
        assetKind: AssetContainerKind,
        sortOrder: Int
    ) throws {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedMIC = rawMIC.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedSymbol.isEmpty else { throw PortfolioDomainError.invalidIdentifier }
        guard normalizedMIC.count == 4,
              normalizedMIC.unicodeScalars.allSatisfy({ scalar in
                  scalar.isASCII && ((65...90).contains(Int(scalar.value)) || (48...57).contains(Int(scalar.value)))
              }) else { throw PortfolioDomainError.invalidMIC }
        guard assetKind.isManualSecurity else { throw PortfolioDomainError.unsupportedSecurity }
        self.id = id
        self.portfolioID = portfolioID
        self.wealthContainerID = wealthContainerID
        self.symbol = normalizedSymbol
        self.rawMIC = normalizedMIC
        self.currency = currency
        self.assetKind = assetKind
        self.sortOrder = sortOrder
    }

    var stableIdentity: String { "\(symbol)|\(rawMIC)" }
}

struct PortfolioFXProvenance: Codable, Equatable, Sendable {
    let original: Money
    let rate: FXRate
    let convertedCNY: Money
    let source: String
    let referenceDate: CivilDate
    let recordedAt: UTCInstant
    let isManual: Bool
    let isStale: Bool

    init(
        original: Money,
        rate: FXRate,
        source: String,
        referenceDate: CivilDate,
        recordedAt: UTCInstant,
        isManual: Bool,
        isStale: Bool
    ) throws {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSource.isEmpty else { throw PortfolioDomainError.fxMismatch }
        guard rate.sourceCurrency == original.currency, rate.targetCurrency == .cny else {
            throw PortfolioDomainError.fxMismatch
        }
        if original.currency == .cny {
            guard rate == .cnyIdentity, !isManual, normalizedSource == "identity" else {
                throw PortfolioDomainError.fxMismatch
            }
        }
        self.original = original
        self.rate = rate
        self.convertedCNY = try rate.convert(original)
        self.source = normalizedSource
        self.referenceDate = referenceDate
        self.recordedAt = recordedAt
        self.isManual = isManual
        self.isStale = isStale
    }
}

enum PortfolioActivityPayload: Equatable, Sendable {
    case openingLot(quantity: AssetQuantity, totalCost: Money, fx: PortfolioFXProvenance, note: String?)
    case buy(quantity: AssetQuantity, unitPrice: MarketPrice, fee: Money, fx: PortfolioFXProvenance)
    case sell(quantity: AssetQuantity, unitPrice: MarketPrice, fee: Money, fx: PortfolioFXProvenance)
    case manualSplit(from: Ratio, to: Ratio)
}

struct PortfolioActivity: Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case openingLot
        case buy
        case sell
        case manualSplit
    }

    let id: UUID
    let portfolioID: UUID
    let securityLinkID: UUID
    let civilDate: CivilDate
    let recordedAt: UTCInstant
    let exchangeTimeZoneIdentifier: String
    let ledgerEntryID: UUID?
    let payload: PortfolioActivityPayload

    init(
        id: UUID = UUID(),
        portfolioID: UUID,
        securityLinkID: UUID,
        civilDate: CivilDate,
        recordedAt: UTCInstant,
        exchangeTimeZoneIdentifier: String,
        ledgerEntryID: UUID? = nil,
        payload: PortfolioActivityPayload
    ) throws {
        guard TimeZone(identifier: exchangeTimeZoneIdentifier) != nil else {
            throw PortfolioDomainError.invalidActivity
        }
        try Self.validate(payload)
        self.id = id
        self.portfolioID = portfolioID
        self.securityLinkID = securityLinkID
        self.civilDate = civilDate
        self.recordedAt = recordedAt
        self.exchangeTimeZoneIdentifier = exchangeTimeZoneIdentifier
        self.ledgerEntryID = ledgerEntryID
        self.payload = payload
    }

    var kind: Kind {
        switch payload {
        case .openingLot: .openingLot
        case .buy: .buy
        case .sell: .sell
        case .manualSplit: .manualSplit
        }
    }

    private static func validate(_ payload: PortfolioActivityPayload) throws {
        switch payload {
        case let .openingLot(quantity, totalCost, fx, note):
            guard quantity.coefficient > 0, totalCost.minorUnits >= 0 else {
                throw PortfolioDomainError.nonPositiveQuantity
            }
            guard fx.original == totalCost else { throw PortfolioDomainError.fxMismatch }
            if let note, note.count > 500 { throw PortfolioDomainError.invalidActivity }
        case let .buy(quantity, unitPrice, fee, fx):
            try validateTrade(quantity: quantity, unitPrice: unitPrice, fee: fee, fx: fx, isSell: false)
        case let .sell(quantity, unitPrice, fee, fx):
            try validateTrade(quantity: quantity, unitPrice: unitPrice, fee: fee, fx: fx, isSell: true)
        case let .manualSplit(from, to):
            guard from.coefficient > 0, to.coefficient > 0 else {
                throw PortfolioDomainError.nonPositiveQuantity
            }
        }
    }

    private static func validateTrade(
        quantity: AssetQuantity,
        unitPrice: MarketPrice,
        fee: Money,
        fx: PortfolioFXProvenance,
        isSell: Bool
    ) throws {
        guard quantity.coefficient > 0 else { throw PortfolioDomainError.nonPositiveQuantity }
        guard fee.minorUnits >= 0 else { throw PortfolioDomainError.negativeFee }
        guard unitPrice.quoteCurrency == fee.currency, fx.original.currency == fee.currency else {
            throw PortfolioDomainError.currencyMismatch
        }
        let gross = try PortfolioCheckedMath.moneyProduct(quantity: quantity, price: unitPrice)
        let expected = isSell ? try gross.subtracting(fee) : try gross.adding(fee)
        guard expected.minorUnits >= 0, expected == fx.original else {
            throw PortfolioDomainError.fxMismatch
        }
    }
}

struct PortfolioLot: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceActivityID: UUID
    let securityLinkID: UUID
    var remainingQuantity: AssetQuantity
    var remainingOriginalBasis: Money
    var remainingCNYBasis: Money
}

struct PortfolioRealizedResult: Equatable, Sendable {
    let activityID: UUID
    let originalPnL: Money
    let cnyPnL: Money
    let disposedOriginalBasis: Money
    let disposedCNYBasis: Money
}

struct PortfolioReplayResult: Equatable, Sendable {
    let lots: [PortfolioLot]
    let realized: [PortfolioRealizedResult]

    func quantity(for securityLinkID: UUID) throws -> AssetQuantity {
        let coefficients = lots.filter { $0.securityLinkID == securityLinkID }.map(\.remainingQuantity.coefficient)
        let total = try coefficients.reduce(Int64(0)) { partial, value in
            let result = partial.addingReportingOverflow(value)
            guard !result.overflow else { throw PortfolioDomainError.arithmeticOverflow }
            return result.partialValue
        }
        return AssetQuantity(coefficient: total)
    }
}

enum PortfolioFIFOEngine {
    static func replay(_ activities: [PortfolioActivity]) throws -> PortfolioReplayResult {
        let ordered = activities.sorted {
            ($0.civilDate, $0.recordedAt.millisecondsSince1970, $0.id.uuidString) <
                ($1.civilDate, $1.recordedAt.millisecondsSince1970, $1.id.uuidString)
        }
        var lots: [PortfolioLot] = []
        var realized: [PortfolioRealizedResult] = []

        for activity in ordered {
            switch activity.payload {
            case let .openingLot(quantity, totalCost, fx, _):
                lots.append(.init(
                    id: activity.id,
                    sourceActivityID: activity.id,
                    securityLinkID: activity.securityLinkID,
                    remainingQuantity: quantity,
                    remainingOriginalBasis: totalCost,
                    remainingCNYBasis: fx.convertedCNY
                ))
            case let .buy(quantity, _, _, fx):
                lots.append(.init(
                    id: activity.id,
                    sourceActivityID: activity.id,
                    securityLinkID: activity.securityLinkID,
                    remainingQuantity: quantity,
                    remainingOriginalBasis: fx.original,
                    remainingCNYBasis: fx.convertedCNY
                ))
            case let .sell(quantity, _, _, fx):
                var needed = quantity.coefficient
                var disposedOriginal = Money(minorUnits: 0, currency: fx.original.currency)
                var disposedCNY = Money(minorUnits: 0, currency: .cny)
                for index in lots.indices where needed > 0 && lots[index].securityLinkID == activity.securityLinkID {
                    let available = lots[index].remainingQuantity.coefficient
                    guard available > 0 else { continue }
                    let taking = min(available, needed)
                    let originalPart = try PortfolioCheckedMath.proportionalMoney(
                        lots[index].remainingOriginalBasis,
                        numerator: taking,
                        denominator: available
                    )
                    let cnyPart = try PortfolioCheckedMath.proportionalMoney(
                        lots[index].remainingCNYBasis,
                        numerator: taking,
                        denominator: available
                    )
                    lots[index].remainingQuantity = AssetQuantity(coefficient: available - taking)
                    lots[index].remainingOriginalBasis = try lots[index].remainingOriginalBasis.subtracting(originalPart)
                    lots[index].remainingCNYBasis = try lots[index].remainingCNYBasis.subtracting(cnyPart)
                    disposedOriginal = try disposedOriginal.adding(originalPart)
                    disposedCNY = try disposedCNY.adding(cnyPart)
                    needed -= taking
                }
                guard needed == 0 else { throw PortfolioDomainError.oversell }
                realized.append(.init(
                    activityID: activity.id,
                    originalPnL: try fx.original.subtracting(disposedOriginal),
                    cnyPnL: try fx.convertedCNY.subtracting(disposedCNY),
                    disposedOriginalBasis: disposedOriginal,
                    disposedCNYBasis: disposedCNY
                ))
            case let .manualSplit(from, to):
                for index in lots.indices where lots[index].securityLinkID == activity.securityLinkID {
                    let adjusted = try PortfolioCheckedMath.ratioQuantity(
                        lots[index].remainingQuantity,
                        numerator: to.coefficient,
                        denominator: from.coefficient
                    )
                    lots[index].remainingQuantity = adjusted
                }
            }
        }
        return PortfolioReplayResult(lots: lots, realized: realized)
    }
}

enum PortfolioCheckedMath {
    static func moneyProduct(quantity: AssetQuantity, price: MarketPrice) throws -> Money {
        try Money(decimal: try multiply(quantity.decimal, price.decimal), currency: price.quoteCurrency)
    }

    static func proportionalMoney(_ money: Money, numerator: Int64, denominator: Int64) throws -> Money {
        guard denominator > 0, numerator >= 0 else { throw PortfolioDomainError.divisionByZero }
        if numerator == denominator { return money }
        let ratio = try divide(Decimal(numerator), Decimal(denominator))
        return try Money(decimal: try multiply(money.decimal, ratio), currency: money.currency)
    }

    static func ratioQuantity(_ quantity: AssetQuantity, numerator: Int64, denominator: Int64) throws -> AssetQuantity {
        guard numerator > 0, denominator > 0 else { throw PortfolioDomainError.divisionByZero }
        return try AssetQuantity(decimal: try divide(try multiply(quantity.decimal, Decimal(numerator)), Decimal(denominator)))
    }

    static func add(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var left = lhs, right = rhs, result = Decimal()
        guard NSDecimalAdd(&result, &left, &right, .bankers) == .noError else {
            throw PortfolioDomainError.arithmeticOverflow
        }
        return result
    }

    static func subtract(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var left = lhs, right = rhs, result = Decimal()
        guard NSDecimalSubtract(&result, &left, &right, .bankers) == .noError else {
            throw PortfolioDomainError.arithmeticOverflow
        }
        return result
    }

    static func multiply(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var left = lhs, right = rhs, result = Decimal()
        guard NSDecimalMultiply(&result, &left, &right, .bankers) == .noError else {
            throw PortfolioDomainError.arithmeticOverflow
        }
        return result
    }

    static func divide(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        guard rhs != 0 else { throw PortfolioDomainError.divisionByZero }
        var left = lhs, right = rhs, result = Decimal()
        guard NSDecimalDivide(&result, &left, &right, .bankers) == .noError else {
            throw PortfolioDomainError.arithmeticOverflow
        }
        return result
    }
}

struct PortfolioHoldingSummary: Identifiable, Equatable, Sendable {
    enum Reconciliation: String, Codable, Sendable { case matched, quantityMismatch }
    var id: UUID { link.id }
    let link: PortfolioSecurityLink
    let portfolioQuantity: AssetQuantity
    let wealthQuantity: AssetQuantity
    let reconciliation: Reconciliation
    let remainingOriginalBasis: Money
    let remainingCNYBasis: Money
    let realizedOriginalPnL: Money
    let realizedCNYPnL: Money
    let manualMark: MarketPrice
    let marketValue: Money
    let marketValueCNY: Money
    let unrealizedOriginalPnL: Money
    let unrealizedCNYPnL: Money
    let weight: Percentage?
    let wealthFX: PortfolioFXProvenance
    let wealthUpdatedDate: CivilDate

    func averageRemainingCost() throws -> MarketPrice? {
        guard portfolioQuantity.coefficient > 0 else { return nil }
        return try MarketPrice(
            decimal: PortfolioCheckedMath.divide(
                remainingOriginalBasis.decimal,
                portfolioQuantity.decimal
            ),
            quoteCurrency: link.currency
        )
    }

    func unrealizedPercentage() throws -> Percentage? {
        guard remainingOriginalBasis.minorUnits != 0 else { return nil }
        return try Percentage(decimal: PortfolioCheckedMath.divide(
            unrealizedOriginalPnL.decimal,
            remainingOriginalBasis.decimal
        ))
    }
}

struct PortfolioNAVSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let portfolioID: UUID
    let civilDate: CivilDate
    let createdAt: UTCInstant
    let totalCNY: Money
    let isComplete: Bool
    let items: [PortfolioNAVSnapshotItem]
}

struct PortfolioNAVSnapshotItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let securityLinkID: UUID
    let quantity: AssetQuantity
    let manualMark: MarketPrice
    let originalMarketValue: Money
    let fx: PortfolioFXProvenance
    let convertedCNYValue: Money
    let remainingCNYBasis: Money
    let reconciliation: PortfolioHoldingSummary.Reconciliation
}

struct PortfolioBenchmarkPreference: Codable, Equatable, Sendable {
    let symbol: String
    let rawMIC: String
    let range: MarketRange

    init(symbol: String, rawMIC: String, range: MarketRange) throws {
        let identity = try MarketWatchlistIdentity(symbol: symbol, mic: rawMIC)
        self.symbol = identity.symbol
        self.rawMIC = identity.mic
        self.range = range
    }
}

struct PortfolioIndexedPoint: Equatable, Sendable {
    let date: CivilDate
    let portfolioIndex: Decimal
    let benchmarkIndex: Decimal
}

enum PortfolioBenchmarkComparison {
    static func indexed100(
        snapshots: [PortfolioNAVSnapshot],
        benchmark: [MarketOHLCVBar]
    ) throws -> [PortfolioIndexedPoint] {
        let snapshotByDate = Dictionary(uniqueKeysWithValues: snapshots.filter(\.isComplete).map { ($0.civilDate, $0.totalCNY.decimal) })
        let benchmarkByDate = Dictionary(uniqueKeysWithValues: benchmark.map { ($0.sessionDate, $0.close.decimal) })
        let dates = Set(snapshotByDate.keys).intersection(benchmarkByDate.keys).sorted()
        guard dates.count >= 2, let first = dates.first,
              let portfolioBase = snapshotByDate[first], portfolioBase > 0,
              let benchmarkBase = benchmarkByDate[first], benchmarkBase > 0 else {
            throw PortfolioDomainError.insufficientBenchmarkOverlap
        }
        return try dates.map { date in
            PortfolioIndexedPoint(
                date: date,
                portfolioIndex: try PortfolioCheckedMath.multiply(try PortfolioCheckedMath.divide(snapshotByDate[date]!, portfolioBase), 100),
                benchmarkIndex: try PortfolioCheckedMath.multiply(try PortfolioCheckedMath.divide(benchmarkByDate[date]!, benchmarkBase), 100)
            )
        }
    }
}
