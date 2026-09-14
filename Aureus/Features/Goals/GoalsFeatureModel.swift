import Foundation
import Observation

enum GoalsTerminalState: String, Equatable, Sendable {
    case idle
    case loading
    case ready
    case calculating
    case failed
}

enum GoalsSessionInputError: Error, Equatable, Sendable {
    case monthlyContributionRequired
    case invalidMonthlyContribution
    case expectedAnnualReturnRequired
    case invalidExpectedAnnualReturn
    case annualSpendingRequired
    case invalidAnnualSpending
    case withdrawalRateRequired
    case invalidWithdrawalRate
    case invalidSavingStartDate
    case invalidSavingEndDate
    case invalidAsOfDate
    case invalidSavingRateRange

    var message: String {
        switch self {
        case .monthlyContributionRequired:
            "Enter a monthly contribution in CNY."
        case .invalidMonthlyContribution:
            "Monthly contribution must be a canonical amount greater than or equal to zero."
        case .expectedAnnualReturnRequired:
            "Enter an expected annual return percentage."
        case .invalidExpectedAnnualReturn:
            "Expected annual return must be a canonical percentage greater than -100%."
        case .annualSpendingRequired:
            "Enter annual spending in CNY."
        case .invalidAnnualSpending:
            "Annual spending must be a canonical amount greater than zero."
        case .withdrawalRateRequired:
            "Enter a withdrawal-rate percentage; no rate is preselected."
        case .invalidWithdrawalRate:
            "Withdrawal rate must be a canonical percentage greater than 0% and no more than 100%."
        case .invalidSavingStartDate:
            "Saving Rate start date must use canonical YYYY-MM-DD format."
        case .invalidSavingEndDate:
            "Saving Rate end date must use canonical YYYY-MM-DD format."
        case .invalidAsOfDate:
            "As-of date must use canonical YYYY-MM-DD format."
        case .invalidSavingRateRange:
            "Saving Rate start date must not be later than the end date."
        }
    }
}

struct GoalsSessionDraft: Equatable, Sendable {
    var monthlyContribution = ""
    var expectedAnnualReturnPercent = ""
    var annualSpending = ""
    var withdrawalRatePercent = ""
    var savingRateStartDate: String
    var savingRateEndDate: String
    var asOfDate: String

    init(date: CivilDate) {
        savingRateStartDate = date.description
        savingRateEndDate = date.description
        asOfDate = date.description
    }
}

struct GoalTrajectoryPresentationPoint: Identifiable, Equatable, Sendable {
    let monthIndex: Int
    let projectedValueCNY: Money

    var id: Int { monthIndex }
}

struct GoalsCalculationReport: Equatable, Sendable {
    let goal: Goal
    let currentNetWorthCNY: Money
    let progress: GoalProgressResult
    let trajectory: GoalTrajectoryResult
    let fireScenario: FIREScenario
    let savingRate: SavingRateReport
    let monthlyContributionCNY: Money
    let expectedAnnualReturn: Ratio
    let annualSpendingCNY: Money
    let withdrawalRate: Ratio
    let savingRateRange: SavingRateRange
    let asOfDate: CivilDate
    let presentationTrajectory: [GoalTrajectoryPresentationPoint]
}

/// Local-only Stage 10 model. It never calculates until `calculate()` is
/// called explicitly and keeps all planning assumptions in this View session.
@MainActor
@Observable
final class GoalsFeatureModel {
    static let localOnlyDisclosure =
        "Goals use permanent local Goals, Wealth, and Ledger records. Planning assumptions are session-only and no Provider, Market Cache, Credential, or Keychain data is read."

    private(set) var state: GoalsTerminalState = .idle
    private(set) var goals: [Goal] = []
    var selectedGoalID: UUID? {
        didSet {
            if oldValue != selectedGoalID { invalidateForInputOrSourceChange() }
        }
    }
    private(set) var currentNetWorthCNY = Money(minorUnits: 0, currency: .cny)
    private(set) var report: GoalsCalculationReport?
    private(set) var errorMessage: String?
    private(set) var inputError: GoalsSessionInputError?
    private(set) var inputErrorMessage: String?
    private(set) var calculationCount = 0

    var sessionDraft: GoalsSessionDraft {
        didSet {
            guard oldValue != sessionDraft else { return }
            inputError = nil
            inputErrorMessage = nil
            invalidateForInputOrSourceChange()
        }
    }

    var monthlyContributionCNY = Money(minorUnits: 0, currency: .cny) {
        didSet { if oldValue != monthlyContributionCNY { invalidateForInputOrSourceChange() } }
    }
    var expectedAnnualReturn = Ratio(coefficient: 0) {
        didSet { if oldValue != expectedAnnualReturn { invalidateForInputOrSourceChange() } }
    }
    var annualSpendingCNY = Money(minorUnits: 0, currency: .cny) {
        didSet { if oldValue != annualSpendingCNY { invalidateForInputOrSourceChange() } }
    }
    var withdrawalRate = Ratio(coefficient: 0) {
        didSet { if oldValue != withdrawalRate { invalidateForInputOrSourceChange() } }
    }
    var savingRateRange: SavingRateRange {
        didSet { if oldValue != savingRateRange { invalidateForInputOrSourceChange() } }
    }
    var asOfDate: CivilDate {
        didSet { if oldValue != asOfDate { invalidateForInputOrSourceChange() } }
    }

    private let store: WealthStore
    private var wealthContainers: [WealthContainer] = []
    private var ledgerEntries: [LedgerEntry] = []
    private var calculationTask: Task<Void, Never>?
    private var generation = UUID()
    private var hasLoaded = false
    private var isApplyingSourceUpdate = false
    private var isApplyingSessionInput = false

    init(store: WealthStore, asOfDate: CivilDate) {
        self.store = store
        self.asOfDate = asOfDate
        self.savingRateRange = try! SavingRateRange(start: asOfDate, end: asOfDate)
        self.sessionDraft = GoalsSessionDraft(date: asOfDate)
    }

    convenience init(store: WealthStore, clock: any Clock) {
        self.init(store: store, asOfDate: Self.civilDate(from: clock.now()))
    }

    var selectedGoal: Goal? {
        goals.first { $0.id == selectedGoalID }
    }

    func load() async {
        calculationTask?.cancel()
        generation = UUID()
        report = nil
        state = .loading
        errorMessage = nil
        do {
            async let loadedGoals = store.fetchGoals()
            async let loadedWealth = store.fetchWealthContainers()
            async let loadedLedger = store.fetchLedgerEntries()
            let sourceGoals = try await loadedGoals
            let sourceWealth = try await loadedWealth
            let sourceLedger = try await loadedLedger
            let summary = try WealthValuation.aggregate(sourceWealth)

            isApplyingSourceUpdate = true
            goals = sourceGoals
            wealthContainers = sourceWealth
            ledgerEntries = sourceLedger
            currentNetWorthCNY = summary.netWorthCNY
            selectedGoalID = selectedGoalID.flatMap { selected in
                sourceGoals.contains { $0.id == selected } ? selected : nil
            } ?? sourceGoals.first?.id
            isApplyingSourceUpdate = false
            hasLoaded = true
            state = .ready
        } catch {
            isApplyingSourceUpdate = false
            state = .failed
            errorMessage = "Local Goals, Wealth, or Ledger records could not be loaded. Previously confirmed permanent records were not replaced."
        }
    }

    func createGoal(_ goal: Goal) async {
        do {
            try await store.createGoal(goal)
            await reloadAfterMutation(selecting: goal.id)
        } catch {
            state = .failed
            errorMessage = "Goal creation failed without changing confirmed permanent records."
        }
    }

    func updateGoal(_ goal: Goal) async {
        do {
            try await store.updateGoal(goal)
            await reloadAfterMutation(selecting: goal.id)
        } catch {
            state = .failed
            errorMessage = "Goal update failed without replacing confirmed permanent records."
        }
    }

    func deleteGoal(id: UUID, confirmed: Bool) async {
        guard confirmed else { return }
        do {
            try await store.deleteGoal(id: id)
            await reloadAfterMutation(selecting: selectedGoalID == id ? nil : selectedGoalID)
        } catch {
            state = .failed
            errorMessage = "Goal deletion failed. Confirmed permanent records remain available."
        }
    }

    func calculate() {
        calculationTask?.cancel()
        guard hasLoaded, let goal = selectedGoal else {
            report = nil
            state = .failed
            errorMessage = "Select a local Goal before calculating."
            return
        }

        let operationGeneration = UUID()
        generation = operationGeneration
        report = nil
        errorMessage = nil
        inputError = nil
        inputErrorMessage = nil
        state = .calculating

        let currentNetWorth = currentNetWorthCNY
        let wealth = wealthContainers
        let ledger = ledgerEntries
        let contribution = monthlyContributionCNY
        let annualReturn = expectedAnnualReturn
        let spending = annualSpendingCNY
        let rate = withdrawalRate
        let range = savingRateRange
        let asOf = asOfDate

        calculationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let calculated = try await Task.detached(priority: .userInitiated) {
                    let progress = try GoalPlanning.progress(
                        goal: goal,
                        wealthContainers: wealth
                    )
                    let trajectory = try GoalPlanning.targetDateTrajectory(
                        goal: goal,
                        currentNetWorthCNY: currentNetWorth,
                        monthlyContributionCNY: contribution,
                        expectedAnnualReturn: annualReturn,
                        asOf: asOf
                    )
                    let fire = try GoalPlanning.fireScenario(FIREScenarioInput(
                        annualSpendingCNY: spending,
                        withdrawalRate: rate,
                        currentNetWorthCNY: currentNetWorth,
                        monthlyContributionCNY: contribution,
                        expectedAnnualReturn: annualReturn
                    ))
                    let saving = try GoalPlanning.savingRate(entries: ledger, range: range)
                    let presentationTrajectory = try GoalsPresentationTrajectory.make(
                        trajectory: trajectory,
                        currentNetWorthCNY: currentNetWorth,
                        monthlyContributionCNY: contribution,
                        expectedAnnualReturn: annualReturn
                    )
                    return GoalsCalculationReport(
                        goal: goal,
                        currentNetWorthCNY: currentNetWorth,
                        progress: progress,
                        trajectory: trajectory,
                        fireScenario: fire,
                        savingRate: saving,
                        monthlyContributionCNY: contribution,
                        expectedAnnualReturn: annualReturn,
                        annualSpendingCNY: spending,
                        withdrawalRate: rate,
                        savingRateRange: range,
                        asOfDate: asOf,
                        presentationTrajectory: presentationTrajectory
                    )
                }.value
                try Task.checkCancellation()
                guard self.generation == operationGeneration,
                      self.selectedGoalID == goal.id,
                      self.currentNetWorthCNY == currentNetWorth,
                      self.monthlyContributionCNY == contribution,
                      self.expectedAnnualReturn == annualReturn,
                      self.annualSpendingCNY == spending,
                      self.withdrawalRate == rate,
                      self.savingRateRange == range,
                      self.asOfDate == asOf else {
                    return
                }
                self.report = calculated
                self.calculationCount += 1
                self.state = .ready
            } catch is CancellationError {
                guard self.generation == operationGeneration else { return }
                self.report = nil
                self.state = .ready
            } catch {
                guard self.generation == operationGeneration else { return }
                self.report = nil
                self.state = .failed
                self.errorMessage = "Goal planning inputs could not produce an authoritative local result."
            }
        }
    }

    func cancelCalculation() {
        calculationTask?.cancel()
        generation = UUID()
        report = nil
        state = hasLoaded ? .ready : .idle
        errorMessage = nil
        inputError = nil
        inputErrorMessage = nil
    }

    @discardableResult
    func applySessionDraft() -> Bool {
        do {
            let contribution = try Self.money(
                sessionDraft.monthlyContribution,
                required: .monthlyContributionRequired,
                invalid: .invalidMonthlyContribution
            )
            guard contribution.minorUnits >= 0 else {
                throw GoalsSessionInputError.invalidMonthlyContribution
            }

            let expectedPercent = try Self.decimal(
                sessionDraft.expectedAnnualReturnPercent,
                required: .expectedAnnualReturnRequired,
                invalid: .invalidExpectedAnnualReturn
            )
            guard expectedPercent > -100 else {
                throw GoalsSessionInputError.invalidExpectedAnnualReturn
            }
            let expectedReturn: Ratio
            do { expectedReturn = try Ratio(decimal: expectedPercent / Decimal(100)) }
            catch { throw GoalsSessionInputError.invalidExpectedAnnualReturn }

            let spending = try Self.money(
                sessionDraft.annualSpending,
                required: .annualSpendingRequired,
                invalid: .invalidAnnualSpending
            )
            guard spending.minorUnits > 0 else {
                throw GoalsSessionInputError.invalidAnnualSpending
            }

            let withdrawalPercent = try Self.decimal(
                sessionDraft.withdrawalRatePercent,
                required: .withdrawalRateRequired,
                invalid: .invalidWithdrawalRate
            )
            guard withdrawalPercent > 0, withdrawalPercent <= 100 else {
                throw GoalsSessionInputError.invalidWithdrawalRate
            }
            let rate: Ratio
            do { rate = try Ratio(decimal: withdrawalPercent / Decimal(100)) }
            catch { throw GoalsSessionInputError.invalidWithdrawalRate }

            let start = try Self.date(
                sessionDraft.savingRateStartDate,
                error: .invalidSavingStartDate
            )
            let end = try Self.date(
                sessionDraft.savingRateEndDate,
                error: .invalidSavingEndDate
            )
            let asOf = try Self.date(sessionDraft.asOfDate, error: .invalidAsOfDate)
            let range: SavingRateRange
            do { range = try SavingRateRange(start: start, end: end) }
            catch { throw GoalsSessionInputError.invalidSavingRateRange }

            isApplyingSessionInput = true
            monthlyContributionCNY = contribution
            expectedAnnualReturn = expectedReturn
            annualSpendingCNY = spending
            withdrawalRate = rate
            savingRateRange = range
            asOfDate = asOf
            isApplyingSessionInput = false
            inputError = nil
            inputErrorMessage = nil
            invalidateForInputOrSourceChange()
            return true
        } catch let error as GoalsSessionInputError {
            isApplyingSessionInput = false
            calculationTask?.cancel()
            generation = UUID()
            report = nil
            errorMessage = nil
            inputError = error
            inputErrorMessage = error.message
            state = hasLoaded ? .ready : .idle
            return false
        } catch {
            isApplyingSessionInput = false
            calculationTask?.cancel()
            generation = UUID()
            report = nil
            errorMessage = nil
            inputError = nil
            inputErrorMessage = "Planning assumptions could not be parsed without changing confirmed inputs."
            state = hasLoaded ? .ready : .idle
            return false
        }
    }

    private func reloadAfterMutation(selecting id: UUID?) async {
        selectedGoalID = id
        await load()
        if goals.contains(where: { $0.id == id }) {
            isApplyingSourceUpdate = true
            selectedGoalID = id
            isApplyingSourceUpdate = false
        }
    }

    private func invalidateForInputOrSourceChange() {
        guard !isApplyingSourceUpdate, !isApplyingSessionInput else { return }
        calculationTask?.cancel()
        generation = UUID()
        report = nil
        errorMessage = nil
        state = hasLoaded ? .ready : .idle
    }

    private static func money(
        _ text: String,
        required: GoalsSessionInputError,
        invalid: GoalsSessionInputError
    ) throws -> Money {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw required }
        do {
            return try Money(
                decimal: FixedPointMath.parseCanonical(normalized),
                currency: .cny
            )
        } catch {
            throw invalid
        }
    }

    private static func decimal(
        _ text: String,
        required: GoalsSessionInputError,
        invalid: GoalsSessionInputError
    ) throws -> Decimal {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw required }
        do { return try FixedPointMath.parseCanonical(normalized) }
        catch { throw invalid }
    }

    private static func date(
        _ text: String,
        error inputError: GoalsSessionInputError
    ) throws -> CivilDate {
        do { return try CivilDate(canonical: text) }
        catch { throw inputError }
    }

    private static func civilDate(from instant: UTCInstant) -> CivilDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: instant.date)
        return try! CivilDate(
            year: components.year!,
            month: components.month!,
            day: components.day!
        )
    }
}

private enum GoalsPresentationTrajectory {
    static func make(
        trajectory: GoalTrajectoryResult,
        currentNetWorthCNY: Money,
        monthlyContributionCNY: Money,
        expectedAnnualReturn: Ratio
    ) throws -> [GoalTrajectoryPresentationPoint] {
        guard case let .available(available) = trajectory else { return [] }
        var points: [GoalTrajectoryPresentationPoint] = []
        points.reserveCapacity(available.targetMonthCount + 1)
        for month in 0...available.targetMonthCount {
            try Task.checkCancellation()
            let scenario = try GoalPlanning.compound(CompoundPlanningInput(
                initialCapitalCNY: currentNetWorthCNY,
                monthlyContributionCNY: monthlyContributionCNY,
                expectedAnnualReturn: expectedAnnualReturn,
                months: month
            ))
            points.append(GoalTrajectoryPresentationPoint(
                monthIndex: month,
                projectedValueCNY: scenario.futureValueCNY
            ))
        }
        return points
    }
}
