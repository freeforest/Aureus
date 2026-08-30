import Foundation
import Observation

enum GoalsTerminalState: String, Equatable, Sendable {
    case idle
    case loading
    case ready
    case calculating
    case failed
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
}

/// Local-only Stage 10 foundation model. It is intentionally not wired into
/// AppShell and never calculates until `calculate()` is called explicitly.
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
    private(set) var calculationCount = 0

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

    init(store: WealthStore, asOfDate: CivilDate) {
        self.store = store
        self.asOfDate = asOfDate
        self.savingRateRange = try! SavingRateRange(start: asOfDate, end: asOfDate)
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
                        asOfDate: asOf
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
        guard !isApplyingSourceUpdate else { return }
        calculationTask?.cancel()
        generation = UUID()
        report = nil
        errorMessage = nil
        state = hasLoaded ? .ready : .idle
    }
}
