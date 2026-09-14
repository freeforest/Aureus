import Foundation

enum GoalPlanningError: Error, Equatable, Sendable {
    case currencyMustBeCNY
    case negativeMonthlyContribution
    case invalidAnnualReturn
    case invalidMonthCount
    case invalidAnnualSpending
    case invalidWithdrawalRate
    case invalidDateRange
    case overflow
    case underflow
    case invalidDecimal
    case divisionByZero
}

enum GoalPlanningUnavailableReason: Error, Equatable, Sendable {
    case targetCurrencyUnsupportedForCNYProgress
    case missingTargetDate
    case targetDateNotFuture
    case alreadyReached
    case notReachedWithinMaximumMonths
    case nonPositiveIncome
}

struct CompoundPlanningInput: Equatable, Sendable {
    let initialCapitalCNY: Money
    let monthlyContributionCNY: Money
    let expectedAnnualReturn: Ratio
    let months: Int
}

struct CompoundPlanningResult: Equatable, Sendable {
    let futureValueCNY: Money
    let initialCapitalCNY: Money
    let totalContributionsCNY: Money
    let assumptionGrowthCNY: Money
    let months: Int
    let annualReturn: Ratio

    static let disclosure =
        "Assumption-based scenario using a nominal annual return and month-end contributions; it is not a prediction, guarantee, or recommendation."
}

struct GoalProgress: Equatable, Sendable {
    let currentNetWorthCNY: Money
    let targetCNY: Money
    let progress: Ratio
    let remainingCNY: Money
}

enum GoalProgressResult: Equatable, Sendable {
    case available(GoalProgress)
    case unavailable(GoalPlanningUnavailableReason)
}

enum GoalReachEstimate: Equatable, Sendable {
    case alreadyReached
    case reached(months: Int, projectedValueCNY: Money)
    case unavailable(GoalPlanningUnavailableReason)
}

struct GoalTrajectory: Equatable, Sendable {
    let targetDate: CivilDate
    let targetMonthCount: Int
    let targetDateScenario: CompoundPlanningResult
    let estimatedReach: GoalReachEstimate
}

enum GoalTrajectoryResult: Equatable, Sendable {
    case available(GoalTrajectory)
    case unavailable(GoalPlanningUnavailableReason)
}

struct FIREScenarioInput: Equatable, Sendable {
    let annualSpendingCNY: Money
    let withdrawalRate: Ratio
    let currentNetWorthCNY: Money
    let monthlyContributionCNY: Money
    let expectedAnnualReturn: Ratio
    let maximumMonths: Int

    init(
        annualSpendingCNY: Money,
        withdrawalRate: Ratio,
        currentNetWorthCNY: Money,
        monthlyContributionCNY: Money,
        expectedAnnualReturn: Ratio,
        maximumMonths: Int = 1_200
    ) {
        self.annualSpendingCNY = annualSpendingCNY
        self.withdrawalRate = withdrawalRate
        self.currentNetWorthCNY = currentNetWorthCNY
        self.monthlyContributionCNY = monthlyContributionCNY
        self.expectedAnnualReturn = expectedAnnualReturn
        self.maximumMonths = maximumMonths
    }
}

struct FIREScenario: Equatable, Sendable {
    let fireNumberCNY: Money
    let progress: Ratio
    let estimatedReach: GoalReachEstimate
    let annualSpendingCNY: Money
    let withdrawalRate: Ratio
    let currentNetWorthCNY: Money
    let monthlyContributionCNY: Money
    let expectedAnnualReturn: Ratio
    let maximumMonths: Int

    static let disclosure =
        "User-supplied FIRE arithmetic assumptions only; no withdrawal rate is safe, recommended, guaranteed, or preselected."
}

struct SavingRateRange: Equatable, Sendable {
    let start: CivilDate
    let end: CivilDate

    init(start: CivilDate, end: CivilDate) throws {
        guard start <= end else { throw GoalPlanningError.invalidDateRange }
        self.start = start
        self.end = end
    }
}

struct GoalPlanningMonth: Hashable, Comparable, Equatable, Sendable {
    let year: Int
    let month: Int

    init(_ date: CivilDate) {
        year = date.year
        month = date.month
    }

    static func < (lhs: GoalPlanningMonth, rhs: GoalPlanningMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

enum SavingRateValue: Equatable, Sendable {
    case available(Ratio)
    case unavailable(GoalPlanningUnavailableReason)
}

struct MonthlySavingRate: Equatable, Sendable {
    let period: GoalPlanningMonth
    let ordinaryIncomeCNY: Money
    let ordinaryExpenseCNY: Money
    let ordinarySavingsCNY: Money
    let savingRate: SavingRateValue
}

struct SavingRateReport: Equatable, Sendable {
    let range: SavingRateRange
    let ordinaryIncomeCNY: Money
    let ordinaryExpenseCNY: Money
    let ordinarySavingsCNY: Money
    let aggregateRate: SavingRateValue
    let observedMonths: [MonthlySavingRate]
    let includedEntryCount: Int

    static let disclosure =
        "Saving Rate includes ordinary income and expense only; transfers, buys, sells, dividends, interest, and fees are excluded. Stored converted-CNY provenance is reused without recalculating FX."
}

enum GoalPlanning {
    static let maximumReachMonths = 1_200

    static func compound(_ input: CompoundPlanningInput) throws -> CompoundPlanningResult {
        try validateCNY(input.initialCapitalCNY)
        try validateCNY(input.monthlyContributionCNY)
        guard input.monthlyContributionCNY.minorUnits >= 0 else {
            throw GoalPlanningError.negativeMonthlyContribution
        }
        try validateAnnualReturn(input.expectedAnnualReturn)
        guard (0...maximumReachMonths).contains(input.months) else {
            throw GoalPlanningError.invalidMonthCount
        }

        let initial = input.initialCapitalCNY.decimal
        let contribution = input.monthlyContributionCNY.decimal
        let annualRate = input.expectedAnnualReturn.decimal
        let monthlyRate = try GoalDecimalMath.divide(annualRate, 12)
        let contributionCount = Decimal(input.months)
        let totalContributions = try GoalDecimalMath.multiply(contribution, contributionCount)
        let futureValue: Decimal

        if monthlyRate == 0 {
            futureValue = try GoalDecimalMath.add(initial, totalContributions)
        } else {
            let factor = try GoalDecimalMath.integerPower(
                try GoalDecimalMath.add(1, monthlyRate),
                exponent: input.months
            )
            let initialFuture = try GoalDecimalMath.multiply(initial, factor)
            let annuityFactor = try GoalDecimalMath.divide(
                try GoalDecimalMath.subtract(factor, 1),
                monthlyRate
            )
            futureValue = try GoalDecimalMath.add(
                initialFuture,
                try GoalDecimalMath.multiply(contribution, annuityFactor)
            )
        }

        let growth = try GoalDecimalMath.subtract(
            try GoalDecimalMath.subtract(futureValue, initial),
            totalContributions
        )
        return CompoundPlanningResult(
            futureValueCNY: try GoalDecimalMath.money(futureValue),
            initialCapitalCNY: input.initialCapitalCNY,
            totalContributionsCNY: try GoalDecimalMath.money(totalContributions),
            assumptionGrowthCNY: try GoalDecimalMath.money(growth),
            months: input.months,
            annualReturn: input.expectedAnnualReturn
        )
    }

    static func progress(
        goal: Goal,
        wealthContainers: [WealthContainer]
    ) throws -> GoalProgressResult {
        let summary = try WealthValuation.aggregate(wealthContainers)
        return try progress(goal: goal, currentNetWorthCNY: summary.netWorthCNY)
    }

    static func progress(goal: Goal, currentNetWorthCNY: Money) throws -> GoalProgressResult {
        guard goal.target.currency == .cny else {
            return .unavailable(.targetCurrencyUnsupportedForCNYProgress)
        }
        try validateCNY(currentNetWorthCNY)
        let progress = try GoalDecimalMath.ratio(
            try GoalDecimalMath.divide(currentNetWorthCNY.decimal, goal.target.decimal)
        )
        let remainingDecimal = max(
            try GoalDecimalMath.subtract(goal.target.decimal, currentNetWorthCNY.decimal),
            0
        )
        return .available(GoalProgress(
            currentNetWorthCNY: currentNetWorthCNY,
            targetCNY: goal.target,
            progress: progress,
            remainingCNY: try GoalDecimalMath.money(remainingDecimal)
        ))
    }

    static func targetDateTrajectory(
        goal: Goal,
        currentNetWorthCNY: Money,
        monthlyContributionCNY: Money,
        expectedAnnualReturn: Ratio,
        asOf: CivilDate
    ) throws -> GoalTrajectoryResult {
        guard goal.target.currency == .cny else {
            return .unavailable(.targetCurrencyUnsupportedForCNYProgress)
        }
        try validateCNY(currentNetWorthCNY)
        if currentNetWorthCNY.minorUnits >= goal.target.minorUnits {
            return .unavailable(.alreadyReached)
        }
        guard let targetDate = goal.targetDate else {
            return .unavailable(.missingTargetDate)
        }
        let months = (targetDate.year - asOf.year) * 12 + targetDate.month - asOf.month
        guard months > 0 else { return .unavailable(.targetDateNotFuture) }
        guard months <= maximumReachMonths else {
            return .unavailable(.notReachedWithinMaximumMonths)
        }
        let scenario = try compound(CompoundPlanningInput(
            initialCapitalCNY: currentNetWorthCNY,
            monthlyContributionCNY: monthlyContributionCNY,
            expectedAnnualReturn: expectedAnnualReturn,
            months: months
        ))
        let reach = try estimatedReach(
            currentNetWorthCNY: currentNetWorthCNY,
            targetCNY: goal.target,
            monthlyContributionCNY: monthlyContributionCNY,
            expectedAnnualReturn: expectedAnnualReturn,
            maximumMonths: maximumReachMonths
        )
        return .available(GoalTrajectory(
            targetDate: targetDate,
            targetMonthCount: months,
            targetDateScenario: scenario,
            estimatedReach: reach
        ))
    }

    static func fireScenario(_ input: FIREScenarioInput) throws -> FIREScenario {
        try validateCNY(input.annualSpendingCNY)
        try validateCNY(input.currentNetWorthCNY)
        try validateCNY(input.monthlyContributionCNY)
        guard input.annualSpendingCNY.minorUnits > 0 else {
            throw GoalPlanningError.invalidAnnualSpending
        }
        guard input.monthlyContributionCNY.minorUnits >= 0 else {
            throw GoalPlanningError.negativeMonthlyContribution
        }
        let withdrawal = input.withdrawalRate.decimal
        guard withdrawal > 0, withdrawal <= 1 else {
            throw GoalPlanningError.invalidWithdrawalRate
        }
        try validateAnnualReturn(input.expectedAnnualReturn)
        guard (1...maximumReachMonths).contains(input.maximumMonths) else {
            throw GoalPlanningError.invalidMonthCount
        }

        let fireNumber = try GoalDecimalMath.money(
            try GoalDecimalMath.divide(input.annualSpendingCNY.decimal, withdrawal)
        )
        let progress = try GoalDecimalMath.ratio(
            try GoalDecimalMath.divide(input.currentNetWorthCNY.decimal, fireNumber.decimal)
        )
        let reach = try estimatedReach(
            currentNetWorthCNY: input.currentNetWorthCNY,
            targetCNY: fireNumber,
            monthlyContributionCNY: input.monthlyContributionCNY,
            expectedAnnualReturn: input.expectedAnnualReturn,
            maximumMonths: input.maximumMonths
        )
        return FIREScenario(
            fireNumberCNY: fireNumber,
            progress: progress,
            estimatedReach: reach,
            annualSpendingCNY: input.annualSpendingCNY,
            withdrawalRate: input.withdrawalRate,
            currentNetWorthCNY: input.currentNetWorthCNY,
            monthlyContributionCNY: input.monthlyContributionCNY,
            expectedAnnualReturn: input.expectedAnnualReturn,
            maximumMonths: input.maximumMonths
        )
    }

    static func savingRate(
        entries: [LedgerEntry],
        range: SavingRateRange
    ) throws -> SavingRateReport {
        var months: [GoalPlanningMonth: SavingAccumulator] = [:]
        var includedEntryCount = 0

        for entry in entries where entry.civilDate >= range.start && entry.civilDate <= range.end {
            let amount: Money
            switch entry.kind {
            case .income, .expense:
                guard let primary = entry.primaryPosting else {
                    throw GoalPlanningError.invalidDecimal
                }
                amount = primary.valuation.convertedCNY
            case .transfer, .buy, .sell, .dividend, .interest, .fee:
                continue
            }
            try validateCNY(amount)
            let period = GoalPlanningMonth(entry.civilDate)
            var accumulator = months[period] ?? .zero
            if entry.kind == .income {
                accumulator.income = try checkedAdd(accumulator.income, amount)
            } else {
                accumulator.expense = try checkedAdd(accumulator.expense, amount)
            }
            accumulator.entryCount += 1
            includedEntryCount += 1
            months[period] = accumulator
        }

        var totalIncome = Money(minorUnits: 0, currency: .cny)
        var totalExpense = Money(minorUnits: 0, currency: .cny)
        let observed = try months.keys.sorted().map { period in
            let values = months[period]!
            totalIncome = try checkedAdd(totalIncome, values.income)
            totalExpense = try checkedAdd(totalExpense, values.expense)
            let savings = try checkedSubtract(values.income, values.expense)
            return MonthlySavingRate(
                period: period,
                ordinaryIncomeCNY: values.income,
                ordinaryExpenseCNY: values.expense,
                ordinarySavingsCNY: savings,
                savingRate: try savingRateValue(income: values.income, savings: savings)
            )
        }
        let totalSavings = try checkedSubtract(totalIncome, totalExpense)
        return SavingRateReport(
            range: range,
            ordinaryIncomeCNY: totalIncome,
            ordinaryExpenseCNY: totalExpense,
            ordinarySavingsCNY: totalSavings,
            aggregateRate: try savingRateValue(income: totalIncome, savings: totalSavings),
            observedMonths: observed,
            includedEntryCount: includedEntryCount
        )
    }

    private struct SavingAccumulator {
        var income: Money
        var expense: Money
        var entryCount: Int

        static let zero = SavingAccumulator(
            income: Money(minorUnits: 0, currency: .cny),
            expense: Money(minorUnits: 0, currency: .cny),
            entryCount: 0
        )
    }

    private static func estimatedReach(
        currentNetWorthCNY: Money,
        targetCNY: Money,
        monthlyContributionCNY: Money,
        expectedAnnualReturn: Ratio,
        maximumMonths: Int
    ) throws -> GoalReachEstimate {
        try validateCNY(currentNetWorthCNY)
        try validateCNY(targetCNY)
        try validateCNY(monthlyContributionCNY)
        guard monthlyContributionCNY.minorUnits >= 0 else {
            throw GoalPlanningError.negativeMonthlyContribution
        }
        try validateAnnualReturn(expectedAnnualReturn)
        guard (1...maximumReachMonths).contains(maximumMonths) else {
            throw GoalPlanningError.invalidMonthCount
        }
        if currentNetWorthCNY.minorUnits >= targetCNY.minorUnits {
            return .alreadyReached
        }

        let monthlyRate = try GoalDecimalMath.divide(expectedAnnualReturn.decimal, 12)
        let monthlyFactor = try GoalDecimalMath.add(1, monthlyRate)
        var balance = currentNetWorthCNY.decimal
        for month in 1...maximumMonths {
            balance = try GoalDecimalMath.add(
                try GoalDecimalMath.multiply(balance, monthlyFactor),
                monthlyContributionCNY.decimal
            )
            if balance >= targetCNY.decimal {
                return .reached(
                    months: month,
                    projectedValueCNY: try GoalDecimalMath.money(balance)
                )
            }
        }
        return .unavailable(.notReachedWithinMaximumMonths)
    }

    private static func savingRateValue(
        income: Money,
        savings: Money
    ) throws -> SavingRateValue {
        guard income.minorUnits > 0 else { return .unavailable(.nonPositiveIncome) }
        return .available(try GoalDecimalMath.ratio(
            try GoalDecimalMath.divide(savings.decimal, income.decimal)
        ))
    }

    private static func validateCNY(_ money: Money) throws {
        guard money.currency == .cny else { throw GoalPlanningError.currencyMustBeCNY }
    }

    private static func validateAnnualReturn(_ rate: Ratio) throws {
        guard rate.decimal > -1 else { throw GoalPlanningError.invalidAnnualReturn }
    }

    private static func checkedAdd(_ lhs: Money, _ rhs: Money) throws -> Money {
        do { return try lhs.adding(rhs) }
        catch { throw GoalPlanningError.overflow }
    }

    private static func checkedSubtract(_ lhs: Money, _ rhs: Money) throws -> Money {
        do { return try lhs.subtracting(rhs) }
        catch { throw GoalPlanningError.overflow }
    }
}

private enum GoalDecimalMath {
    private static let workingScale: Int = 16

    static func add(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var left = lhs, right = rhs, result = Decimal()
        try checkAllowingWorkingScaleRounding(NSDecimalAdd(&result, &left, &right, .bankers))
        return try normalized(result)
    }

    static func subtract(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var left = lhs, right = rhs, result = Decimal()
        try checkAllowingWorkingScaleRounding(NSDecimalSubtract(&result, &left, &right, .bankers))
        return try normalized(result)
    }

    static func multiply(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var left = lhs, right = rhs, result = Decimal()
        try checkAllowingWorkingScaleRounding(NSDecimalMultiply(&result, &left, &right, .bankers))
        let normalizedResult = try normalized(result)
        if lhs != 0, rhs != 0, normalizedResult == 0 { throw GoalPlanningError.underflow }
        return normalizedResult
    }

    static func divide(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        guard rhs != 0 else { throw GoalPlanningError.divisionByZero }
        var left = lhs, right = rhs, result = Decimal()
        try checkAllowingWorkingScaleRounding(NSDecimalDivide(&result, &left, &right, .bankers))
        let normalizedResult = try normalized(result)
        if lhs != 0, normalizedResult == 0 { throw GoalPlanningError.underflow }
        return normalizedResult
    }

    static func integerPower(_ value: Decimal, exponent: Int) throws -> Decimal {
        guard exponent >= 0 else { throw GoalPlanningError.invalidMonthCount }
        if exponent == 0 { return 1 }
        var base = try normalized(value)
        var remaining = exponent
        var result: Decimal = 1
        while remaining > 0 {
            if !remaining.isMultiple(of: 2) {
                result = try multiply(result, base)
            }
            remaining /= 2
            if remaining > 0 { base = try multiply(base, base) }
        }
        return result
    }

    static func money(_ value: Decimal) throws -> Money {
        do { return try Money(decimal: value, currency: .cny) }
        catch FinancialValueError.overflow { throw GoalPlanningError.overflow }
        catch { throw GoalPlanningError.invalidDecimal }
    }

    static func ratio(_ value: Decimal) throws -> Ratio {
        do { return try Ratio(decimal: value) }
        catch FinancialValueError.overflow { throw GoalPlanningError.overflow }
        catch { throw GoalPlanningError.invalidDecimal }
    }

    private static func normalized(_ value: Decimal) throws -> Decimal {
        guard NSDecimalNumber(decimal: value) != .notANumber else {
            throw GoalPlanningError.invalidDecimal
        }
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, workingScale, .bankers)
        return result
    }

    private static func checkAllowingWorkingScaleRounding(
        _ error: Decimal.CalculationError
    ) throws {
        switch error {
        case .noError, .lossOfPrecision:
            return
        case .underflow:
            throw GoalPlanningError.underflow
        case .overflow:
            throw GoalPlanningError.overflow
        case .divideByZero:
            throw GoalPlanningError.divisionByZero
        @unknown default:
            throw GoalPlanningError.invalidDecimal
        }
    }
}
