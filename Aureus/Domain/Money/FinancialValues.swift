import Foundation

enum FinancialValueError: Error, Equatable, Sendable {
    case unsupportedCurrency(String)
    case currencyMismatch(expected: CurrencyCode, actual: CurrencyCode)
    case directionMismatch
    case nonPositiveRate
    case negativePrice
    case overflow
    case invalidScale
    case invalidDecimal
}

enum CurrencyCode: String, CaseIterable, Codable, Sendable {
    case cny = "CNY"
    case usd = "USD"

    init(validating code: String) throws {
        guard let currency = CurrencyCode(rawValue: code.uppercased()) else {
            throw FinancialValueError.unsupportedCurrency(code)
        }
        self = currency
    }
}

enum FixedPointMath {
    static let canonicalLocale = Locale(identifier: "en_US_POSIX")

    static func decimal(coefficient: Int64, scale: Int) -> Decimal {
        precondition(scale >= 0)
        let value = Decimal(string: String(coefficient), locale: canonicalLocale)!
        return value / powerOfTen(scale)
    }

    static func coefficient(from decimal: Decimal, scale: Int) throws -> Int64 {
        guard scale >= 0 else { throw FinancialValueError.invalidScale }

        var scaled = decimal * powerOfTen(scale)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .bankers)

        let number = NSDecimalNumber(decimal: rounded)
        guard number != .notANumber else { throw FinancialValueError.invalidDecimal }
        let minimum = NSDecimalNumber(value: Int64.min)
        let maximum = NSDecimalNumber(value: Int64.max)
        guard number.compare(minimum) != .orderedAscending,
              number.compare(maximum) != .orderedDescending else {
            throw FinancialValueError.overflow
        }
        return number.int64Value
    }

    static func parseCanonical(_ text: String) throws -> Decimal {
        guard let value = Decimal(string: text, locale: canonicalLocale) else {
            throw FinancialValueError.invalidDecimal
        }
        return value
    }

    private static func powerOfTen(_ exponent: Int) -> Decimal {
        var result = Decimal(1)
        for _ in 0..<exponent {
            result *= Decimal(10)
        }
        return result
    }
}

struct Money: Codable, Equatable, Sendable {
    static let scale = 2

    let minorUnits: Int64
    let currency: CurrencyCode

    init(minorUnits: Int64, currency: CurrencyCode) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    init(decimal: Decimal, currency: CurrencyCode) throws {
        self.minorUnits = try FixedPointMath.coefficient(from: decimal, scale: Self.scale)
        self.currency = currency
    }

    var decimal: Decimal {
        FixedPointMath.decimal(coefficient: minorUnits, scale: Self.scale)
    }

    func adding(_ other: Money) throws -> Money {
        guard currency == other.currency else {
            throw FinancialValueError.currencyMismatch(expected: currency, actual: other.currency)
        }
        let result = minorUnits.addingReportingOverflow(other.minorUnits)
        guard !result.overflow else { throw FinancialValueError.overflow }
        return Money(minorUnits: result.partialValue, currency: currency)
    }

    func subtracting(_ other: Money) throws -> Money {
        guard currency == other.currency else {
            throw FinancialValueError.currencyMismatch(expected: currency, actual: other.currency)
        }
        let result = minorUnits.subtractingReportingOverflow(other.minorUnits)
        guard !result.overflow else { throw FinancialValueError.overflow }
        return Money(minorUnits: result.partialValue, currency: currency)
    }
}

struct AssetQuantity: Codable, Equatable, Sendable {
    static let scale = 8

    let coefficient: Int64

    init(coefficient: Int64) {
        self.coefficient = coefficient
    }

    init(decimal: Decimal) throws {
        self.coefficient = try FixedPointMath.coefficient(from: decimal, scale: Self.scale)
    }

    var decimal: Decimal {
        FixedPointMath.decimal(coefficient: coefficient, scale: Self.scale)
    }
}

struct MarketPrice: Codable, Equatable, Sendable {
    static let scale = 8

    let coefficient: Int64
    let quoteCurrency: CurrencyCode

    init(coefficient: Int64, quoteCurrency: CurrencyCode) throws {
        guard coefficient >= 0 else { throw FinancialValueError.negativePrice }
        self.coefficient = coefficient
        self.quoteCurrency = quoteCurrency
    }

    init(decimal: Decimal, quoteCurrency: CurrencyCode) throws {
        let coefficient = try FixedPointMath.coefficient(from: decimal, scale: Self.scale)
        try self.init(coefficient: coefficient, quoteCurrency: quoteCurrency)
    }

    var decimal: Decimal {
        FixedPointMath.decimal(coefficient: coefficient, scale: Self.scale)
    }
}

struct FXRate: Codable, Equatable, Sendable {
    static let scale = 10

    let coefficient: Int64
    let sourceCurrency: CurrencyCode
    let targetCurrency: CurrencyCode

    init(coefficient: Int64, sourceCurrency: CurrencyCode, targetCurrency: CurrencyCode) throws {
        guard coefficient > 0 else { throw FinancialValueError.nonPositiveRate }
        self.coefficient = coefficient
        self.sourceCurrency = sourceCurrency
        self.targetCurrency = targetCurrency
    }

    init(decimal: Decimal, sourceCurrency: CurrencyCode, targetCurrency: CurrencyCode) throws {
        let coefficient = try FixedPointMath.coefficient(from: decimal, scale: Self.scale)
        try self.init(
            coefficient: coefficient,
            sourceCurrency: sourceCurrency,
            targetCurrency: targetCurrency
        )
    }

    static let cnyIdentity = try! FXRate(
        coefficient: 10_000_000_000,
        sourceCurrency: .cny,
        targetCurrency: .cny
    )

    var decimal: Decimal {
        FixedPointMath.decimal(coefficient: coefficient, scale: Self.scale)
    }

    func convert(_ money: Money) throws -> Money {
        guard money.currency == sourceCurrency else {
            throw FinancialValueError.currencyMismatch(expected: sourceCurrency, actual: money.currency)
        }
        guard targetCurrency == .cny else { throw FinancialValueError.directionMismatch }
        return try Money(decimal: money.decimal * decimal, currency: targetCurrency)
    }
}

struct Percentage: Codable, Equatable, Sendable {
    static let scale = 10

    let coefficient: Int64

    init(coefficient: Int64) {
        self.coefficient = coefficient
    }

    init(decimal: Decimal) throws {
        self.coefficient = try FixedPointMath.coefficient(from: decimal, scale: Self.scale)
    }

    var decimal: Decimal {
        FixedPointMath.decimal(coefficient: coefficient, scale: Self.scale)
    }
}

struct Ratio: Codable, Equatable, Sendable {
    static let scale = 10

    let coefficient: Int64

    init(coefficient: Int64) {
        self.coefficient = coefficient
    }

    init(decimal: Decimal) throws {
        self.coefficient = try FixedPointMath.coefficient(from: decimal, scale: Self.scale)
    }

    var decimal: Decimal {
        FixedPointMath.decimal(coefficient: coefficient, scale: Self.scale)
    }
}

struct FXValuation: Codable, Equatable, Sendable {
    let original: Money
    let rate: FXRate
    let convertedCNY: Money
    let referenceDate: CivilDate
    let fetchedAt: UTCInstant
    let providerIdentifier: String
    let isManualOverride: Bool
    let isStale: Bool

    init(
        original: Money,
        rate: FXRate,
        referenceDate: CivilDate,
        fetchedAt: UTCInstant,
        providerIdentifier: String,
        isManualOverride: Bool = false,
        isStale: Bool
    ) throws {
        guard rate.targetCurrency == .cny else { throw FinancialValueError.directionMismatch }
        self.original = original
        self.rate = rate
        self.convertedCNY = try rate.convert(original)
        self.referenceDate = referenceDate
        self.fetchedAt = fetchedAt
        self.providerIdentifier = providerIdentifier
        self.isManualOverride = isManualOverride
        self.isStale = isStale
    }
}
