import Foundation

enum MarketIndicatorError: Error, Equatable, Sendable {
    case invalidPeriod
    case unorderedInput
    case duplicateSessionDate
    case invalidBar
    case arithmeticFailure
}

enum MarketIndicatorKind: String, CaseIterable, Codable, Equatable, Sendable {
    case sma20
    case sma50
    case ema12
    case ema26
    case rsi14
    case macd
    case bollinger20
}

struct MarketIndicatorProvenance: Codable, Equatable, Sendable {
    let kind: MarketIndicatorKind
    let parameters: [String: Int]
    let sourceInterval: MarketInterval
    let adjustment: MarketAdjustment
}

struct MarketIndicatorPoint: Codable, Equatable, Sendable {
    let sessionDate: CivilDate
    let value: Decimal
}

struct MarketMACDPoint: Codable, Equatable, Sendable {
    let sessionDate: CivilDate
    let macd: Decimal
    let signal: Decimal?
    let histogram: Decimal?
}

struct MarketBollingerPoint: Codable, Equatable, Sendable {
    let sessionDate: CivilDate
    let middle: Decimal
    let upper: Decimal
    let lower: Decimal
}

struct MarketIndicatorSnapshot: Codable, Equatable, Sendable {
    let provenance: [MarketIndicatorProvenance]
    let sma20: [MarketIndicatorPoint]
    let sma50: [MarketIndicatorPoint]
    let ema12: [MarketIndicatorPoint]
    let ema26: [MarketIndicatorPoint]
    let rsi14: [MarketIndicatorPoint]
    let macd: [MarketMACDPoint]
    let bollinger20: [MarketBollingerPoint]
}

enum MarketIndicatorCalculator {
    static func calculate(
        bars: [MarketOHLCVBar],
        interval: MarketInterval,
        adjustment: MarketAdjustment
    ) throws -> MarketIndicatorSnapshot {
        let closes = try validatedCloses(bars)
        return MarketIndicatorSnapshot(
            provenance: [
                .init(kind: .sma20, parameters: ["period": 20], sourceInterval: interval, adjustment: adjustment),
                .init(kind: .sma50, parameters: ["period": 50], sourceInterval: interval, adjustment: adjustment),
                .init(kind: .ema12, parameters: ["period": 12], sourceInterval: interval, adjustment: adjustment),
                .init(kind: .ema26, parameters: ["period": 26], sourceInterval: interval, adjustment: adjustment),
                .init(kind: .rsi14, parameters: ["period": 14], sourceInterval: interval, adjustment: adjustment),
                .init(kind: .macd, parameters: ["fast": 12, "slow": 26, "signal": 9], sourceInterval: interval, adjustment: adjustment),
                .init(kind: .bollinger20, parameters: ["period": 20, "multiplier": 2, "population": 1], sourceInterval: interval, adjustment: adjustment)
            ],
            sma20: try sma(closes, period: 20),
            sma50: try sma(closes, period: 50),
            ema12: try ema(closes, period: 12),
            ema26: try ema(closes, period: 26),
            rsi14: try rsi(closes, period: 14),
            macd: try macd(closes, fast: 12, slow: 26, signal: 9),
            bollinger20: try bollinger(closes, period: 20, multiplier: 2)
        )
    }

    static func sma(_ values: [(CivilDate, Decimal)], period: Int) throws -> [MarketIndicatorPoint] {
        guard period > 0 else { throw MarketIndicatorError.invalidPeriod }
        guard values.count >= period else { return [] }
        var result: [MarketIndicatorPoint] = []
        result.reserveCapacity(values.count - period + 1)
        for index in (period - 1)..<values.count {
            var sum = Decimal.zero
            for offset in (index - period + 1)...index {
                sum = try add(sum, values[offset].1)
            }
            result.append(.init(sessionDate: values[index].0, value: try divide(sum, Decimal(period))))
        }
        return result
    }

    static func ema(_ values: [(CivilDate, Decimal)], period: Int) throws -> [MarketIndicatorPoint] {
        guard period > 0 else { throw MarketIndicatorError.invalidPeriod }
        guard values.count >= period else { return [] }
        let seedValues = Array(values.prefix(period))
        guard let seed = try sma(seedValues, period: period).last?.value else { return [] }
        let alpha = try divide(Decimal(2), Decimal(period + 1))
        var current = seed
        var result = [MarketIndicatorPoint(sessionDate: values[period - 1].0, value: seed)]
        if values.count == period { return result }
        for index in period..<values.count {
            let delta = try subtract(values[index].1, current)
            current = try add(current, multiply(alpha, delta))
            result.append(.init(sessionDate: values[index].0, value: current))
        }
        return result
    }

    static func rsi(_ values: [(CivilDate, Decimal)], period: Int) throws -> [MarketIndicatorPoint] {
        guard period > 0 else { throw MarketIndicatorError.invalidPeriod }
        guard values.count > period else { return [] }
        var gains = Decimal.zero
        var losses = Decimal.zero
        for index in 1...period {
            let delta = try subtract(values[index].1, values[index - 1].1)
            if delta > 0 { gains = try add(gains, delta) }
            if delta < 0 { losses = try add(losses, -delta) }
        }
        var averageGain = try divide(gains, Decimal(period))
        var averageLoss = try divide(losses, Decimal(period))
        var result = [MarketIndicatorPoint(sessionDate: values[period].0, value: try rsiValue(gain: averageGain, loss: averageLoss))]
        if values.count == period + 1 { return result }
        let smoothing = Decimal(period - 1)
        for index in (period + 1)..<values.count {
            let delta = try subtract(values[index].1, values[index - 1].1)
            let gain = delta > 0 ? delta : .zero
            let loss = delta < 0 ? -delta : .zero
            averageGain = try divide(add(multiply(averageGain, smoothing), gain), Decimal(period))
            averageLoss = try divide(add(multiply(averageLoss, smoothing), loss), Decimal(period))
            result.append(.init(sessionDate: values[index].0, value: try rsiValue(gain: averageGain, loss: averageLoss)))
        }
        return result
    }

    static func macd(
        _ values: [(CivilDate, Decimal)],
        fast: Int,
        slow: Int,
        signal: Int
    ) throws -> [MarketMACDPoint] {
        guard fast > 0, slow > fast, signal > 0 else { throw MarketIndicatorError.invalidPeriod }
        let fastValues = Dictionary(uniqueKeysWithValues: try ema(values, period: fast).map { ($0.sessionDate, $0.value) })
        let slowSeries = try ema(values, period: slow)
        var base: [(CivilDate, Decimal)] = []
        for slowPoint in slowSeries {
            guard let fastValue = fastValues[slowPoint.sessionDate] else { continue }
            base.append((slowPoint.sessionDate, try subtract(fastValue, slowPoint.value)))
        }
        let signalValues = Dictionary(uniqueKeysWithValues: try ema(base, period: signal).map { ($0.sessionDate, $0.value) })
        return try base.map { date, macdValue in
            let signalValue = signalValues[date]
            return MarketMACDPoint(
                sessionDate: date,
                macd: macdValue,
                signal: signalValue,
                histogram: try signalValue.map { try subtract(macdValue, $0) }
            )
        }
    }

    static func bollinger(
        _ values: [(CivilDate, Decimal)],
        period: Int,
        multiplier: Int
    ) throws -> [MarketBollingerPoint] {
        guard period > 0, multiplier >= 0 else { throw MarketIndicatorError.invalidPeriod }
        guard values.count >= period else { return [] }
        var result: [MarketBollingerPoint] = []
        for index in (period - 1)..<values.count {
            let window = values[(index - period + 1)...index].map(\.1)
            var sum = Decimal.zero
            for value in window { sum = try add(sum, value) }
            let mean = try divide(sum, Decimal(period))
            var squaredSum = Decimal.zero
            for value in window {
                let delta = try subtract(value, mean)
                squaredSum = try add(squaredSum, multiply(delta, delta))
            }
            let variance = try divide(squaredSum, Decimal(period))
            let deviation = try squareRoot(variance)
            let width = try multiply(deviation, Decimal(multiplier))
            result.append(.init(
                sessionDate: values[index].0,
                middle: mean,
                upper: try add(mean, width),
                lower: try subtract(mean, width)
            ))
        }
        return result
    }

    private static func validatedCloses(_ bars: [MarketOHLCVBar]) throws -> [(CivilDate, Decimal)] {
        var previous: CivilDate?
        var result: [(CivilDate, Decimal)] = []
        result.reserveCapacity(bars.count)
        for bar in bars {
            if let previous {
                if bar.sessionDate == previous { throw MarketIndicatorError.duplicateSessionDate }
                if bar.sessionDate < previous { throw MarketIndicatorError.unorderedInput }
            }
            guard bar.open.coefficient >= 0,
                  bar.high.coefficient >= max(bar.open.coefficient, bar.close.coefficient),
                  bar.low.coefficient <= min(bar.open.coefficient, bar.close.coefficient),
                  bar.volume?.coefficient ?? 0 >= 0 else {
                throw MarketIndicatorError.invalidBar
            }
            result.append((bar.sessionDate, bar.close.decimal))
            previous = bar.sessionDate
        }
        return result
    }

    private static func rsiValue(gain: Decimal, loss: Decimal) throws -> Decimal {
        if gain == 0, loss == 0 { return Decimal(50) }
        if loss == 0 { return Decimal(100) }
        let ratio = try divide(gain, loss)
        return try subtract(Decimal(100), divide(Decimal(100), add(Decimal(1), ratio)))
    }

    private static func add(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var lhs = lhs
        var rhs = rhs
        var result = Decimal()
        guard acceptable(NSDecimalAdd(&result, &lhs, &rhs, .bankers)) else { throw MarketIndicatorError.arithmeticFailure }
        return result
    }

    private static func subtract(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var lhs = lhs
        var rhs = rhs
        var result = Decimal()
        guard acceptable(NSDecimalSubtract(&result, &lhs, &rhs, .bankers)) else { throw MarketIndicatorError.arithmeticFailure }
        return result
    }

    private static func multiply(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var lhs = lhs
        var rhs = rhs
        var result = Decimal()
        guard acceptable(NSDecimalMultiply(&result, &lhs, &rhs, .bankers)) else { throw MarketIndicatorError.arithmeticFailure }
        return result
    }

    private static func divide(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        guard rhs != 0 else { throw MarketIndicatorError.arithmeticFailure }
        var lhs = lhs
        var rhs = rhs
        var result = Decimal()
        guard acceptable(NSDecimalDivide(&result, &lhs, &rhs, .bankers)) else { throw MarketIndicatorError.arithmeticFailure }
        return result
    }

    private static func acceptable(_ status: Decimal.CalculationError) -> Bool {
        status == .noError || status == .lossOfPrecision
    }

    private static func squareRoot(_ value: Decimal) throws -> Decimal {
        guard value >= 0 else { throw MarketIndicatorError.arithmeticFailure }
        if value == 0 { return 0 }
        var estimate = value >= 1 ? value : 1
        for _ in 0..<48 {
            let next = try divide(add(estimate, divide(value, estimate)), Decimal(2))
            if next == estimate { break }
            estimate = next
        }
        return estimate
    }
}

enum MarketPresentationArithmeticError: Error, Equatable, Sendable {
    case overflow
    case underflow
    case divisionByZero
    case lossOfPrecision
    case invalidDecimal
}

enum MarketPresentationArithmetic {
    static func add(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        try calculate(lhs, rhs, NSDecimalAdd)
    }

    static func subtract(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        try calculate(lhs, rhs, NSDecimalSubtract)
    }

    static func multiply(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        try calculate(lhs, rhs, NSDecimalMultiply)
    }

    static func divide(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        guard rhs != 0 else { throw MarketPresentationArithmeticError.divisionByZero }
        return try calculate(lhs, rhs, NSDecimalDivide)
    }

    static func magnitude(_ value: Decimal) throws -> Decimal {
        value < 0 ? try multiply(value, -1) : value
    }

    static func sum(_ values: [Decimal]) throws -> Decimal {
        try values.reduce(into: Decimal.zero) { partial, value in
            partial = try add(partial, value)
        }
    }

    private static func calculate(
        _ lhs: Decimal,
        _ rhs: Decimal,
        _ operation: (UnsafeMutablePointer<Decimal>, UnsafePointer<Decimal>, UnsafePointer<Decimal>, Decimal.RoundingMode) -> Decimal.CalculationError
    ) throws -> Decimal {
        guard lhs.isFinite, rhs.isFinite else { throw MarketPresentationArithmeticError.invalidDecimal }
        var lhs = lhs
        var rhs = rhs
        var result = Decimal()
        switch operation(&result, &lhs, &rhs, .bankers) {
        case .noError: return result
        case .lossOfPrecision: throw MarketPresentationArithmeticError.lossOfPrecision
        case .overflow: throw MarketPresentationArithmeticError.overflow
        case .underflow: throw MarketPresentationArithmeticError.underflow
        case .divideByZero: throw MarketPresentationArithmeticError.divisionByZero
        @unknown default: throw MarketPresentationArithmeticError.invalidDecimal
        }
    }
}

private extension Decimal {
    var isFinite: Bool { NSDecimalNumber(decimal: self) != .notANumber }
}
