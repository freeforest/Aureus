import Foundation

enum PortfolioAnalyticsError: Error, Equatable, Sendable {
    case noPortfolio
    case noCompleteSnapshots
    case insufficientSnapshots
    case duplicateSnapshotDate
    case invalidDateOrder
    case nonpositiveStartingNAV
    case invalidNAV
    case incompleteSnapshotsExcluded
    case missingValuationBoundary
    case irregularDailySeries
    case insufficientRiskObservations
    case zeroVolatility
    case invalidRiskFreeRate
    case noPositiveCashFlow
    case noNegativeCashFlow
    case nonConventionalCashFlows
    case noXIRRRoot
    case multipleXIRRRoots
    case rootDidNotConverge
    case overflow
    case underflow
    case lossOfPrecision
    case divisionByZero
    case invalidScale
    case invalidRoot
    case invalidExponent
    case cancelled
    case staleGeneration
    case unexpectedLocalFailure
}

enum PortfolioAnalyticsRange: String, CaseIterable, Codable, Identifiable, Sendable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case yearToDate = "YTD"
    case oneYear = "1Y"
    case threeYears = "3Y"
    case fiveYears = "5Y"
    case maximum = "MAX"

    var id: String { rawValue }

    func lowerBound(endingAt end: CivilDate) throws -> CivilDate? {
        switch self {
        case .maximum:
            return nil
        case .yearToDate:
            return try CivilDate(year: end.year, month: 1, day: 1)
        case .oneMonth:
            return try AnalyticsCivilCalendar.adding(months: -1, to: end)
        case .threeMonths:
            return try AnalyticsCivilCalendar.adding(months: -3, to: end)
        case .oneYear:
            return try AnalyticsCivilCalendar.adding(years: -1, to: end)
        case .threeYears:
            return try AnalyticsCivilCalendar.adding(years: -3, to: end)
        case .fiveYears:
            return try AnalyticsCivilCalendar.adding(years: -5, to: end)
        }
    }
}

enum AnalyticsMetric<Value: Equatable & Sendable>: Equatable, Sendable {
    case available(Value)
    case unavailable(PortfolioAnalyticsError)
}

struct PortfolioAnalyticsInput: Equatable, Sendable {
    let portfolio: PortfolioRecord
    let activities: [PortfolioActivity]
    let snapshots: [PortfolioNAVSnapshot]
    let range: PortfolioAnalyticsRange
    let annualRiskFreeRate: Decimal
}

struct AnalyticsCapitalFlow: Equatable, Sendable {
    enum Direction: String, Equatable, Sendable {
        case contribution
        case withdrawal
    }

    let activityID: UUID
    let date: CivilDate
    let direction: Direction
    let amountCNY: Money

    var signedPortfolioAmount: Money {
        switch direction {
        case .contribution:
            amountCNY
        case .withdrawal:
            Money(minorUnits: -amountCNY.minorUnits, currency: .cny)
        }
    }
}

struct AnalyticsSubperiodReturn: Equatable, Sendable {
    let startDate: CivilDate
    let endDate: CivilDate
    let startingNAV: Money
    let endingNAV: Money
    let portfolioCashFlow: Money
    let returnDecimal: Decimal
}

struct AnalyticsIndexPoint: Equatable, Sendable {
    let date: CivilDate
    let value: Decimal
}

struct AnalyticsDrawdownPoint: Equatable, Sendable {
    let date: CivilDate
    let signedDrawdown: Decimal
}

struct AnalyticsMaximumDrawdown: Equatable, Sendable {
    let magnitude: Decimal
    let peakDate: CivilDate
    let troughDate: CivilDate
    let recoveryDate: CivilDate?
}

enum AnalyticsCoverageKind: String, Equatable, Sendable {
    case completeCalendarPeriod
    case partialObservedPeriod
}

struct ObservedMonthlyTWR: Equatable, Sendable, Identifiable {
    var id: String { String(format: "%04d-%02d", year, month) }
    let year: Int
    let month: Int
    let returnDecimal: Decimal
    let firstCoveredDate: CivilDate
    let lastCoveredDate: CivilDate
    let subperiodCount: Int
    let coverage: AnalyticsCoverageKind
}

struct ObservedAnnualTWR: Equatable, Sendable, Identifiable {
    var id: Int { year }
    let year: Int
    let returnDecimal: Decimal
    let firstCoveredDate: CivilDate
    let lastCoveredDate: CivilDate
    let subperiodCount: Int
    let coverage: AnalyticsCoverageKind
}

struct AnalyticsXIRRCashFlow: Equatable, Sendable {
    let date: CivilDate
    let investorAmountCNY: Money
}

struct PortfolioAnalyticsCoverage: Equatable, Sendable {
    let requestedRange: PortfolioAnalyticsRange
    let firstDate: CivilDate
    let lastDate: CivilDate
    let completeSnapshotsUsed: Int
    let incompleteSnapshotsExcluded: Int
    let capitalFlowCount: Int
    let flowValuationBoundariesComplete: Bool
    let dailySeriesIsRegular: Bool
}

struct PortfolioAnalyticsReport: Equatable, Sendable {
    let portfolioID: UUID
    let capitalFlows: [AnalyticsCapitalFlow]
    let startingNAV: Money
    let endingNAV: Money
    let contributions: Money
    let withdrawals: Money
    let cashFlowAdjustedPnL: Money
    let cashFlowAdjustedTotalReturn: Decimal
    let timeWeightedReturn: Decimal
    let cagr: AnalyticsMetric<Decimal>
    let xirr: AnalyticsMetric<Decimal>
    let annualizedVolatility: AnalyticsMetric<Decimal>
    let sharpeRatio: AnalyticsMetric<Decimal>
    let maximumDrawdown: AnalyticsMaximumDrawdown
    let subperiodReturns: [AnalyticsSubperiodReturn]
    let wealthIndex: [AnalyticsIndexPoint]
    let drawdownSeries: [AnalyticsDrawdownPoint]
    let monthlyReturns: [ObservedMonthlyTWR]
    let annualReturns: [ObservedAnnualTWR]
    let xirrCashFlows: [AnalyticsXIRRCashFlow]
    let coverage: PortfolioAnalyticsCoverage
}

enum PortfolioAnalyticsCalculator {
    /// Recalculates Stage 9 analytics from complete local Portfolio NAV snapshots and
    /// Portfolio activities. Portfolio cash flows use Portfolio signs (Opening Lot and
    /// Buy positive, Sell negative, Manual Split zero), civil-date range semantics are
    /// `(start, end]`, annualization uses 365 actual Gregorian days, missing valuations
    /// are never filled, and all authoritative arithmetic uses checked Decimal scale 16.
    static func calculate(_ input: PortfolioAnalyticsInput) throws -> PortfolioAnalyticsReport {
        try Task.checkCancellation()
        guard input.annualRiskFreeRate > -1 else {
            throw PortfolioAnalyticsError.invalidRiskFreeRate
        }

        let incompleteCount = input.snapshots.filter { !$0.isComplete }.count
        let complete = input.snapshots.filter(\.isComplete).sorted {
            ($0.civilDate, $0.createdAt.millisecondsSince1970, $0.id.uuidString) <
                ($1.civilDate, $1.createdAt.millisecondsSince1970, $1.id.uuidString)
        }
        guard !complete.isEmpty else { throw PortfolioAnalyticsError.noCompleteSnapshots }
        for pair in zip(complete, complete.dropFirst()) where pair.0.civilDate == pair.1.civilDate {
            throw PortfolioAnalyticsError.duplicateSnapshotDate
        }
        guard let absoluteEnd = complete.last else { throw PortfolioAnalyticsError.noCompleteSnapshots }
        let lowerBound = try input.range.lowerBound(endingAt: absoluteEnd.civilDate)
        let selected = complete.filter { snapshot in
            lowerBound.map { snapshot.civilDate >= $0 } ?? true
        }
        guard selected.count >= 2 else { throw PortfolioAnalyticsError.insufficientSnapshots }
        guard let first = selected.first, let last = selected.last,
              first.civilDate < last.civilDate else {
            throw PortfolioAnalyticsError.invalidDateOrder
        }
        guard first.totalCNY.currency == .cny, last.totalCNY.currency == .cny,
              first.totalCNY.minorUnits > 0 else {
            throw PortfolioAnalyticsError.nonpositiveStartingNAV
        }
        guard selected.allSatisfy({ $0.portfolioID == input.portfolio.id && $0.totalCNY.minorUnits >= 0 }) else {
            throw PortfolioAnalyticsError.invalidNAV
        }

        let flows = try capitalFlows(
            from: input.activities,
            portfolioID: input.portfolio.id,
            after: first.civilDate,
            through: last.civilDate
        )
        let snapshotDates = Set(selected.map(\.civilDate))
        guard flows.allSatisfy({ snapshotDates.contains($0.date) }) else {
            throw PortfolioAnalyticsError.missingValuationBoundary
        }
        let flowsByDate = try aggregatePortfolioFlows(flows)
        let contributions = try sumAmounts(flows.filter { $0.direction == .contribution }.map(\.amountCNY))
        let withdrawals = try sumAmounts(flows.filter { $0.direction == .withdrawal }.map(\.amountCNY))
        let netFlow = try contributions.subtracting(withdrawals)
        let pnl = try last.totalCNY.subtracting(first.totalCNY).subtracting(netFlow)
        let simpleReturn = try AnalyticsDecimalMath.divide(pnl.decimal, first.totalCNY.decimal)

        let twr = try timeWeightedSeries(snapshots: selected, flowsByDate: flowsByDate)
        let twrFactor = try AnalyticsDecimalMath.add(1, twr.totalReturn)
        let daySpan = try AnalyticsCivilCalendar.dayDistance(from: first.civilDate, to: last.civilDate)
        let cagr: AnalyticsMetric<Decimal>
        if twrFactor > 0, daySpan > 0 {
            do {
                let dailyFactor = try AnalyticsDecimalMath.positiveNthRoot(twrFactor, degree: daySpan)
                cagr = .available(try AnalyticsDecimalMath.subtract(
                    try AnalyticsDecimalMath.integerPower(dailyFactor, exponent: 365),
                    1
                ))
            } catch let error as PortfolioAnalyticsError {
                cagr = .unavailable(error)
            }
        } else {
            cagr = .unavailable(.invalidRoot)
        }

        let investorFlows = try xirrCashFlows(
            startingNAV: first.totalCNY,
            endingNAV: last.totalCNY,
            startDate: first.civilDate,
            endDate: last.civilDate,
            portfolioFlows: flows
        )
        let xirr: AnalyticsMetric<Decimal>
        do {
            xirr = .available(try solveXIRR(investorFlows))
        } catch let error as PortfolioAnalyticsError {
            xirr = .unavailable(error)
        }

        let risk = riskMetrics(
            subperiods: twr.subperiods,
            annualRiskFreeRate: input.annualRiskFreeRate
        )
        let drawdown = try drawdown(from: twr.wealthIndex)
        let monthly = try observedMonthlyReturns(twr.subperiods)
        let annual = try observedAnnualReturns(twr.subperiods)

        return PortfolioAnalyticsReport(
            portfolioID: input.portfolio.id,
            capitalFlows: flows,
            startingNAV: first.totalCNY,
            endingNAV: last.totalCNY,
            contributions: contributions,
            withdrawals: withdrawals,
            cashFlowAdjustedPnL: pnl,
            cashFlowAdjustedTotalReturn: simpleReturn,
            timeWeightedReturn: twr.totalReturn,
            cagr: cagr,
            xirr: xirr,
            annualizedVolatility: risk.volatility,
            sharpeRatio: risk.sharpe,
            maximumDrawdown: drawdown.summary,
            subperiodReturns: twr.subperiods,
            wealthIndex: twr.wealthIndex,
            drawdownSeries: drawdown.series,
            monthlyReturns: monthly,
            annualReturns: annual,
            xirrCashFlows: investorFlows,
            coverage: PortfolioAnalyticsCoverage(
                requestedRange: input.range,
                firstDate: first.civilDate,
                lastDate: last.civilDate,
                completeSnapshotsUsed: selected.count,
                incompleteSnapshotsExcluded: incompleteCount,
                capitalFlowCount: flows.count,
                flowValuationBoundariesComplete: true,
                dailySeriesIsRegular: risk.isRegular
            )
        )
    }

    /// Maps one stored Portfolio activity to a CNY Portfolio-perspective capital flow,
    /// preserving its recorded FX provenance and civil date. Manual Split has no flow.
    static func capitalFlow(for activity: PortfolioActivity) throws -> AnalyticsCapitalFlow? {
        switch activity.payload {
        case let .openingLot(_, _, fx, _), let .buy(_, _, _, fx):
            guard fx.convertedCNY.minorUnits >= 0 else { throw PortfolioAnalyticsError.invalidNAV }
            return AnalyticsCapitalFlow(
                activityID: activity.id,
                date: activity.civilDate,
                direction: .contribution,
                amountCNY: fx.convertedCNY
            )
        case let .sell(_, _, _, fx):
            guard fx.convertedCNY.minorUnits >= 0 else { throw PortfolioAnalyticsError.invalidNAV }
            return AnalyticsCapitalFlow(
                activityID: activity.id,
                date: activity.civilDate,
                direction: .withdrawal,
                amountCNY: fx.convertedCNY
            )
        case .manualSplit:
            return nil
        }
    }

    /// Solves a conventional investor-perspective daily-rate XIRR using integer civil-day
    /// offsets and bounded Decimal bracketing/bisection, then annualizes on a 365-day basis.
    /// Same-date flows are aggregated; nonconventional signs and non-unique roots are typed.
    static func solveXIRR(
        _ cashFlows: [AnalyticsXIRRCashFlow],
        enforceConventionalTopology: Bool = true
    ) throws -> Decimal {
        let aggregated = try aggregateInvestorFlows(cashFlows)
        guard aggregated.count >= 2,
              let first = aggregated.first,
              let last = aggregated.last,
              first.date < last.date else {
            throw PortfolioAnalyticsError.invalidDateOrder
        }
        let nonzero = aggregated.filter { $0.investorAmountCNY.minorUnits != 0 }
        guard nonzero.contains(where: { $0.investorAmountCNY.minorUnits > 0 }) else {
            throw PortfolioAnalyticsError.noPositiveCashFlow
        }
        guard nonzero.contains(where: { $0.investorAmountCNY.minorUnits < 0 }) else {
            throw PortfolioAnalyticsError.noNegativeCashFlow
        }
        let transitions = zip(nonzero, nonzero.dropFirst()).filter {
            ($0.0.investorAmountCNY.minorUnits < 0) != ($0.1.investorAmountCNY.minorUnits < 0)
        }.count
        if enforceConventionalTopology {
            guard nonzero.first!.investorAmountCNY.minorUnits < 0,
                  nonzero.last!.investorAmountCNY.minorUnits > 0,
                  transitions == 1 else {
                throw PortfolioAnalyticsError.nonConventionalCashFlows
            }
        }

        let candidateTexts = [
            "-0.100000000000", "-0.050000000000", "-0.020000000000",
            "-0.010000000000", "-0.005000000000", "-0.001000000000",
            "-0.000100000000", "0", "0.000100000000", "0.001000000000",
            "0.005000000000", "0.010000000000", "0.020000000000",
            "0.050000000000", "0.100000000000", "0.200000000000",
            "0.500000000000"
        ]
        let candidates = try candidateTexts.map(FixedPointMath.parseCanonical)
        var samples: [(rate: Decimal, npv: Decimal)] = []
        for candidate in candidates {
            do {
                samples.append((candidate, try xirrNPV(cashFlows: aggregated, dailyRate: candidate)))
            } catch PortfolioAnalyticsError.overflow {
                continue
            } catch PortfolioAnalyticsError.underflow {
                continue
            }
        }
        let exact = samples.filter { $0.npv == 0 }
        guard exact.count <= 1 else { throw PortfolioAnalyticsError.multipleXIRRRoots }
        let brackets = zip(samples, samples.dropFirst()).filter { pair in
            (pair.0.npv < 0 && pair.1.npv > 0) || (pair.0.npv > 0 && pair.1.npv < 0)
        }
        if let exact = exact.first, brackets.isEmpty {
            return try annualizeDailyRate(exact.rate)
        }
        guard !brackets.isEmpty else { throw PortfolioAnalyticsError.noXIRRRoot }
        guard brackets.count == 1 else { throw PortfolioAnalyticsError.multipleXIRRRoots }
        var low = brackets[0].0.rate
        var high = brackets[0].1.rate
        var lowNPV = brackets[0].0.npv
        let rateTolerance = try FixedPointMath.parseCanonical("0.000000000001")
        let npvTolerance = try FixedPointMath.parseCanonical("0.01")

        for _ in 0..<256 {
            try Task.checkCancellation()
            let midpoint = try AnalyticsDecimalMath.divide(try AnalyticsDecimalMath.add(low, high), 2)
            let midNPV = try xirrNPV(cashFlows: aggregated, dailyRate: midpoint)
            let width = try AnalyticsDecimalMath.absolute(try AnalyticsDecimalMath.subtract(high, low))
            let absoluteNPV = try AnalyticsDecimalMath.absolute(midNPV)
            if midNPV == 0 || (width <= rateTolerance && absoluteNPV <= npvTolerance) {
                return try annualizeDailyRate(midpoint)
            }
            if (lowNPV < 0 && midNPV > 0) || (lowNPV > 0 && midNPV < 0) {
                high = midpoint
            } else {
                low = midpoint
                lowNPV = midNPV
            }
        }
        throw PortfolioAnalyticsError.rootDidNotConverge
    }

    private struct TWRResult {
        let totalReturn: Decimal
        let subperiods: [AnalyticsSubperiodReturn]
        let wealthIndex: [AnalyticsIndexPoint]
    }

    private struct RiskResult {
        let volatility: AnalyticsMetric<Decimal>
        let sharpe: AnalyticsMetric<Decimal>
        let isRegular: Bool
    }

    private static func capitalFlows(
        from activities: [PortfolioActivity],
        portfolioID: UUID,
        after start: CivilDate,
        through end: CivilDate
    ) throws -> [AnalyticsCapitalFlow] {
        var result: [AnalyticsCapitalFlow] = []
        for activity in activities where activity.portfolioID == portfolioID && activity.civilDate > start && activity.civilDate <= end {
            if let flow = try capitalFlow(for: activity), flow.amountCNY.minorUnits != 0 {
                result.append(flow)
            }
        }
        return result.sorted {
            ($0.date, $0.activityID.uuidString) < ($1.date, $1.activityID.uuidString)
        }
    }

    private static func aggregatePortfolioFlows(_ flows: [AnalyticsCapitalFlow]) throws -> [CivilDate: Money] {
        var result: [CivilDate: Money] = [:]
        for flow in flows {
            result[flow.date] = try (result[flow.date] ?? Money(minorUnits: 0, currency: .cny))
                .adding(flow.signedPortfolioAmount)
        }
        return result
    }

    private static func sumAmounts(_ values: [Money]) throws -> Money {
        try values.reduce(Money(minorUnits: 0, currency: .cny)) { try $0.adding($1) }
    }

    private static func timeWeightedSeries(
        snapshots: [PortfolioNAVSnapshot],
        flowsByDate: [CivilDate: Money]
    ) throws -> TWRResult {
        guard let first = snapshots.first else { throw PortfolioAnalyticsError.insufficientSnapshots }
        var factor: Decimal = 1
        var subperiods: [AnalyticsSubperiodReturn] = []
        var index = [AnalyticsIndexPoint(date: first.civilDate, value: 100)]

        for offset in 1..<snapshots.count {
            try Task.checkCancellation()
            let previous = snapshots[offset - 1]
            let current = snapshots[offset]
            guard previous.civilDate < current.civilDate else { throw PortfolioAnalyticsError.invalidDateOrder }
            guard previous.totalCNY.minorUnits > 0 else { throw PortfolioAnalyticsError.nonpositiveStartingNAV }
            let flow = flowsByDate[current.civilDate] ?? Money(minorUnits: 0, currency: .cny)
            let adjustedEnding = try current.totalCNY.subtracting(flow)
            guard adjustedEnding.minorUnits >= 0 else { throw PortfolioAnalyticsError.invalidNAV }
            let subperiodFactor = try AnalyticsDecimalMath.divide(adjustedEnding.decimal, previous.totalCNY.decimal)
            let subperiodReturn = try AnalyticsDecimalMath.subtract(subperiodFactor, 1)
            factor = try AnalyticsDecimalMath.multiply(factor, subperiodFactor)
            subperiods.append(AnalyticsSubperiodReturn(
                startDate: previous.civilDate,
                endDate: current.civilDate,
                startingNAV: previous.totalCNY,
                endingNAV: current.totalCNY,
                portfolioCashFlow: flow,
                returnDecimal: subperiodReturn
            ))
            index.append(AnalyticsIndexPoint(
                date: current.civilDate,
                value: try AnalyticsDecimalMath.multiply(100, factor)
            ))
        }
        return TWRResult(
            totalReturn: try AnalyticsDecimalMath.subtract(factor, 1),
            subperiods: subperiods,
            wealthIndex: index
        )
    }

    private static func riskMetrics(
        subperiods: [AnalyticsSubperiodReturn],
        annualRiskFreeRate: Decimal
    ) -> RiskResult {
        guard subperiods.count >= 2 else {
            return RiskResult(
                volatility: .unavailable(.insufficientRiskObservations),
                sharpe: .unavailable(.insufficientRiskObservations),
                isRegular: false
            )
        }
        do {
            let regular = try subperiods.allSatisfy {
                try AnalyticsCivilCalendar.dayDistance(from: $0.startDate, to: $0.endDate) == 1
            }
            guard regular else {
                return RiskResult(
                    volatility: .unavailable(.irregularDailySeries),
                    sharpe: .unavailable(.irregularDailySeries),
                    isRegular: false
                )
            }
            let values = subperiods.map(\.returnDecimal)
            let mean = try AnalyticsDecimalMath.divide(
                try values.reduce(Decimal.zero, AnalyticsDecimalMath.add),
                Decimal(values.count)
            )
            var squared: Decimal = 0
            for value in values {
                let deviation = try AnalyticsDecimalMath.subtract(value, mean)
                squared = try AnalyticsDecimalMath.add(
                    squared,
                    try AnalyticsDecimalMath.multiply(deviation, deviation)
                )
            }
            let variance = try AnalyticsDecimalMath.divide(squared, Decimal(values.count - 1))
            let dailyDeviation = try AnalyticsDecimalMath.squareRoot(variance)
            let sqrt365 = try AnalyticsDecimalMath.squareRoot(365)
            let annualized = try AnalyticsDecimalMath.multiply(dailyDeviation, sqrt365)
            let volatility: AnalyticsMetric<Decimal> = .available(annualized)
            guard dailyDeviation != 0 else {
                return RiskResult(volatility: volatility, sharpe: .unavailable(.zeroVolatility), isRegular: true)
            }
            let annualFactor = try AnalyticsDecimalMath.add(1, annualRiskFreeRate)
            guard annualFactor > 0 else {
                return RiskResult(volatility: volatility, sharpe: .unavailable(.invalidRiskFreeRate), isRegular: true)
            }
            let dailyRiskFree = try AnalyticsDecimalMath.subtract(
                try AnalyticsDecimalMath.positiveNthRoot(annualFactor, degree: 365),
                1
            )
            let meanExcess = try AnalyticsDecimalMath.subtract(mean, dailyRiskFree)
            let sharpe = try AnalyticsDecimalMath.multiply(
                try AnalyticsDecimalMath.divide(meanExcess, dailyDeviation),
                sqrt365
            )
            return RiskResult(volatility: volatility, sharpe: .available(sharpe), isRegular: true)
        } catch let error as PortfolioAnalyticsError {
            return RiskResult(volatility: .unavailable(error), sharpe: .unavailable(error), isRegular: false)
        } catch {
            return RiskResult(
                volatility: .unavailable(.unexpectedLocalFailure),
                sharpe: .unavailable(.unexpectedLocalFailure),
                isRegular: false
            )
        }
    }

    private static func drawdown(
        from wealthIndex: [AnalyticsIndexPoint]
    ) throws -> (series: [AnalyticsDrawdownPoint], summary: AnalyticsMaximumDrawdown) {
        guard let first = wealthIndex.first, first.value > 0 else { throw PortfolioAnalyticsError.invalidNAV }
        var runningPeak = first.value
        var runningPeakDate = first.date
        var maximumMagnitude: Decimal = 0
        var maximumPeakDate = first.date
        var troughDate = first.date
        var series: [AnalyticsDrawdownPoint] = []

        for point in wealthIndex {
            if point.value > runningPeak {
                runningPeak = point.value
                runningPeakDate = point.date
            }
            let signed = try AnalyticsDecimalMath.subtract(
                try AnalyticsDecimalMath.divide(point.value, runningPeak),
                1
            )
            series.append(AnalyticsDrawdownPoint(date: point.date, signedDrawdown: signed))
            let magnitude = try AnalyticsDecimalMath.absolute(signed)
            if magnitude > maximumMagnitude {
                maximumMagnitude = magnitude
                maximumPeakDate = runningPeakDate
                troughDate = point.date
            }
        }
        let peakValue = wealthIndex.first(where: { $0.date == maximumPeakDate })!.value
        let recovery = wealthIndex.first(where: { $0.date > troughDate && $0.value >= peakValue })?.date
        return (
            series,
            AnalyticsMaximumDrawdown(
                magnitude: maximumMagnitude,
                peakDate: maximumPeakDate,
                troughDate: troughDate,
                recoveryDate: recovery
            )
        )
    }

    private struct MonthKey: Hashable, Comparable {
        let year: Int
        let month: Int
        static func < (lhs: MonthKey, rhs: MonthKey) -> Bool { (lhs.year, lhs.month) < (rhs.year, rhs.month) }
    }

    private static func observedMonthlyReturns(_ subperiods: [AnalyticsSubperiodReturn]) throws -> [ObservedMonthlyTWR] {
        let grouped = Dictionary(grouping: subperiods) { MonthKey(year: $0.endDate.year, month: $0.endDate.month) }
        return try grouped.keys.sorted().map { key in
            let values = grouped[key]!.sorted { $0.endDate < $1.endDate }
            let chained = try chain(values.map(\.returnDecimal))
            let first = values.first!.endDate
            let last = values.last!.endDate
            let days = try AnalyticsCivilCalendar.daysInMonth(year: key.year, month: key.month)
            let complete = first.day == 1 && last.day == days && values.count == days
            return ObservedMonthlyTWR(
                year: key.year,
                month: key.month,
                returnDecimal: chained,
                firstCoveredDate: first,
                lastCoveredDate: last,
                subperiodCount: values.count,
                coverage: complete ? .completeCalendarPeriod : .partialObservedPeriod
            )
        }
    }

    private static func observedAnnualReturns(_ subperiods: [AnalyticsSubperiodReturn]) throws -> [ObservedAnnualTWR] {
        let grouped = Dictionary(grouping: subperiods) { $0.endDate.year }
        return try grouped.keys.sorted().map { year in
            let values = grouped[year]!.sorted { $0.endDate < $1.endDate }
            let chained = try chain(values.map(\.returnDecimal))
            let first = values.first!.endDate
            let last = values.last!.endDate
            let days = try AnalyticsCivilCalendar.daysInYear(year)
            let complete = first.month == 1 && first.day == 1 && last.month == 12 && last.day == 31 && values.count == days
            return ObservedAnnualTWR(
                year: year,
                returnDecimal: chained,
                firstCoveredDate: first,
                lastCoveredDate: last,
                subperiodCount: values.count,
                coverage: complete ? .completeCalendarPeriod : .partialObservedPeriod
            )
        }
    }

    private static func chain(_ returns: [Decimal]) throws -> Decimal {
        var factor: Decimal = 1
        for value in returns {
            factor = try AnalyticsDecimalMath.multiply(factor, try AnalyticsDecimalMath.add(1, value))
        }
        return try AnalyticsDecimalMath.subtract(factor, 1)
    }

    private static func xirrCashFlows(
        startingNAV: Money,
        endingNAV: Money,
        startDate: CivilDate,
        endDate: CivilDate,
        portfolioFlows: [AnalyticsCapitalFlow]
    ) throws -> [AnalyticsXIRRCashFlow] {
        var values = [AnalyticsXIRRCashFlow(
            date: startDate,
            investorAmountCNY: try negate(startingNAV)
        )]
        values.append(contentsOf: try portfolioFlows.map { flow in
            AnalyticsXIRRCashFlow(
                date: flow.date,
                investorAmountCNY: flow.direction == .contribution
                    ? try negate(flow.amountCNY)
                    : flow.amountCNY
            )
        })
        values.append(AnalyticsXIRRCashFlow(date: endDate, investorAmountCNY: endingNAV))
        return try aggregateInvestorFlows(values)
    }

    private static func negate(_ money: Money) throws -> Money {
        let result = Int64.zero.subtractingReportingOverflow(money.minorUnits)
        guard !result.overflow else { throw PortfolioAnalyticsError.overflow }
        return Money(minorUnits: result.partialValue, currency: money.currency)
    }

    private static func aggregateInvestorFlows(_ values: [AnalyticsXIRRCashFlow]) throws -> [AnalyticsXIRRCashFlow] {
        var grouped: [CivilDate: Money] = [:]
        for value in values {
            guard value.investorAmountCNY.currency == .cny else { throw PortfolioAnalyticsError.invalidNAV }
            grouped[value.date] = try (grouped[value.date] ?? Money(minorUnits: 0, currency: .cny))
                .adding(value.investorAmountCNY)
        }
        return grouped.keys.sorted().map { AnalyticsXIRRCashFlow(date: $0, investorAmountCNY: grouped[$0]!) }
    }

    private static func xirrNPV(cashFlows: [AnalyticsXIRRCashFlow], dailyRate: Decimal) throws -> Decimal {
        let base = try AnalyticsDecimalMath.add(1, dailyRate)
        guard base > 0, let start = cashFlows.first?.date else { throw PortfolioAnalyticsError.invalidRoot }
        var npv: Decimal = 0
        var discount: Decimal = 1
        var previousDate = start
        for flow in cashFlows {
            let dayDelta = try AnalyticsCivilCalendar.dayDistance(from: previousDate, to: flow.date)
            guard dayDelta >= 0 else { throw PortfolioAnalyticsError.invalidDateOrder }
            if dayDelta > 0 {
                discount = try AnalyticsDecimalMath.roundedMultiply(
                    discount,
                    try AnalyticsDecimalMath.roundedIntegerPower(base, exponent: dayDelta)
                )
            }
            let present = try AnalyticsDecimalMath.roundedDivide(flow.investorAmountCNY.decimal, discount)
            npv = try AnalyticsDecimalMath.roundedAdd(npv, present)
            previousDate = flow.date
        }
        return npv
    }

    private static func annualizeDailyRate(_ dailyRate: Decimal) throws -> Decimal {
        try AnalyticsDecimalMath.subtract(
            try AnalyticsDecimalMath.integerPower(try AnalyticsDecimalMath.add(1, dailyRate), exponent: 365),
            1
        )
    }
}

enum AnalyticsDecimalMath {
    static let workingScale = 16
    private static let convergenceTolerance = try! FixedPointMath.parseCanonical("0.0000000000000001")

    static func add(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var left = lhs, right = rhs, result = Decimal()
        try check(NSDecimalAdd(&result, &left, &right, .bankers))
        return try normalized(result)
    }

    static func subtract(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var left = lhs, right = rhs, result = Decimal()
        try check(NSDecimalSubtract(&result, &left, &right, .bankers))
        return try normalized(result)
    }

    static func multiply(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var left = lhs, right = rhs, result = Decimal()
        try check(NSDecimalMultiply(&result, &left, &right, .bankers))
        let normalizedResult = try normalized(result)
        if lhs != 0, rhs != 0, normalizedResult == 0 {
            throw PortfolioAnalyticsError.underflow
        }
        return normalizedResult
    }

    static func divide(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        guard rhs != 0 else { throw PortfolioAnalyticsError.divisionByZero }
        var left = lhs, right = rhs, result = Decimal()
        try check(NSDecimalDivide(&result, &left, &right, .bankers))
        return try normalized(result)
    }

    /// Explicit banker-rounded arithmetic for the bounded XIRR iteration. A
    /// Decimal exactness notification is accepted only at the documented
    /// working-scale boundary; overflow, underflow, and divide-by-zero remain
    /// typed failures, and a non-zero product that rounds to zero is rejected.
    static func roundedAdd(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var left = lhs, right = rhs, result = Decimal()
        try checkAllowingExplicitRounding(NSDecimalAdd(&result, &left, &right, .bankers))
        return try normalized(result)
    }

    static func roundedMultiply(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var left = lhs, right = rhs, result = Decimal()
        try checkAllowingExplicitRounding(NSDecimalMultiply(&result, &left, &right, .bankers))
        let normalizedResult = try normalized(result)
        if lhs != 0, rhs != 0, normalizedResult == 0 {
            throw PortfolioAnalyticsError.underflow
        }
        return normalizedResult
    }

    static func roundedDivide(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        guard rhs != 0 else { throw PortfolioAnalyticsError.divisionByZero }
        var left = lhs, right = rhs, result = Decimal()
        try checkAllowingExplicitRounding(NSDecimalDivide(&result, &left, &right, .bankers))
        let normalizedResult = try normalized(result)
        if lhs != 0, normalizedResult == 0 {
            throw PortfolioAnalyticsError.underflow
        }
        return normalizedResult
    }

    static func absolute(_ value: Decimal) throws -> Decimal {
        value < 0 ? try subtract(0, value) : value
    }

    static func integerPower(_ value: Decimal, exponent: Int) throws -> Decimal {
        guard exponent >= 0 else { throw PortfolioAnalyticsError.invalidExponent }
        if exponent == 0 { return 1 }
        var base = try normalized(value)
        var remaining = exponent
        var result: Decimal = 1
        while remaining > 0 {
            if remaining.isMultiple(of: 2) == false {
                result = try multiply(result, base)
            }
            remaining /= 2
            if remaining > 0 {
                base = try multiply(base, base)
            }
        }
        return result
    }

    static func roundedIntegerPower(_ value: Decimal, exponent: Int) throws -> Decimal {
        guard exponent >= 0 else { throw PortfolioAnalyticsError.invalidExponent }
        if exponent == 0 { return 1 }
        var base = try normalized(value)
        var remaining = exponent
        var result: Decimal = 1
        while remaining > 0 {
            if remaining.isMultiple(of: 2) == false {
                result = try roundedMultiply(result, base)
            }
            remaining /= 2
            if remaining > 0 {
                base = try roundedMultiply(base, base)
            }
        }
        return result
    }

    static func squareRoot(_ value: Decimal) throws -> Decimal {
        try positiveNthRoot(value, degree: 2)
    }

    static func positiveNthRoot(_ value: Decimal, degree: Int) throws -> Decimal {
        guard degree > 0 else { throw PortfolioAnalyticsError.invalidExponent }
        guard value >= 0 else { throw PortfolioAnalyticsError.invalidRoot }
        if value == 0 || value == 1 || degree == 1 { return value }
        var low = value < 1 ? value : 1
        var high = value < 1 ? 1 : value
        for _ in 0..<256 {
            try Task.checkCancellation()
            let midpoint = try divide(try add(low, high), 2)
            let width = try absolute(try subtract(high, low))
            if width <= convergenceTolerance { return midpoint }
            do {
                let powered = try integerPower(midpoint, exponent: degree)
                if powered == value { return midpoint }
                if powered < value { low = midpoint } else { high = midpoint }
            } catch PortfolioAnalyticsError.overflow {
                high = midpoint
            }
        }
        throw PortfolioAnalyticsError.rootDidNotConverge
    }

    private static func normalized(_ value: Decimal) throws -> Decimal {
        let number = NSDecimalNumber(decimal: value)
        guard number != .notANumber else { throw PortfolioAnalyticsError.lossOfPrecision }
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, workingScale, .bankers)
        return result
    }

    private static func check(_ error: Decimal.CalculationError) throws {
        switch error {
        case .noError:
            return
        case .lossOfPrecision:
            throw PortfolioAnalyticsError.lossOfPrecision
        case .underflow:
            throw PortfolioAnalyticsError.underflow
        case .overflow:
            throw PortfolioAnalyticsError.overflow
        case .divideByZero:
            throw PortfolioAnalyticsError.divisionByZero
        @unknown default:
            throw PortfolioAnalyticsError.unexpectedLocalFailure
        }
    }

    private static func checkAllowingExplicitRounding(_ error: Decimal.CalculationError) throws {
        switch error {
        case .noError, .lossOfPrecision:
            return
        case .underflow:
            throw PortfolioAnalyticsError.underflow
        case .overflow:
            throw PortfolioAnalyticsError.overflow
        case .divideByZero:
            throw PortfolioAnalyticsError.divisionByZero
        @unknown default:
            throw PortfolioAnalyticsError.unexpectedLocalFailure
        }
    }
}

enum AnalyticsCivilCalendar {
    static func dayDistance(from start: CivilDate, to end: CivilDate) throws -> Int {
        let calendar = utcGregorian()
        guard let startDate = date(from: start, calendar: calendar),
              let endDate = date(from: end, calendar: calendar),
              let days = calendar.dateComponents([.day], from: startDate, to: endDate).day else {
            throw PortfolioAnalyticsError.invalidDateOrder
        }
        return days
    }

    static func adding(months: Int, to date: CivilDate) throws -> CivilDate {
        try adding(DateComponents(month: months), to: date)
    }

    static func adding(years: Int, to date: CivilDate) throws -> CivilDate {
        try adding(DateComponents(year: years), to: date)
    }

    static func daysInMonth(year: Int, month: Int) throws -> Int {
        let calendar = utcGregorian()
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            throw PortfolioAnalyticsError.invalidDateOrder
        }
        return range.count
    }

    static func daysInYear(_ year: Int) throws -> Int {
        try dayDistance(
            from: CivilDate(year: year, month: 1, day: 1),
            to: CivilDate(year: year + 1, month: 1, day: 1)
        )
    }

    private static func adding(_ components: DateComponents, to civilDate: CivilDate) throws -> CivilDate {
        let calendar = utcGregorian()
        guard let source = date(from: civilDate, calendar: calendar),
              let result = calendar.date(byAdding: components, to: source) else {
            throw PortfolioAnalyticsError.invalidDateOrder
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: result)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            throw PortfolioAnalyticsError.invalidDateOrder
        }
        return try CivilDate(year: year, month: month, day: day)
    }

    private static func utcGregorian() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func date(from value: CivilDate, calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: value.year, month: value.month, day: value.day))
    }
}
