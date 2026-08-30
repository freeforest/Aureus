import Foundation
import Testing
@testable import Aureus

@Suite("Stage 10 Goals Terminal")
struct GoalsTerminalTests {
    @Test("Session draft applies atomically with Decimal percentage authority")
    @MainActor
    func atomicSessionDraft() async throws {
        let fixture = try await terminalFixture()
        let model = fixture.model
        #expect(model.sessionDraft.monthlyContribution.isEmpty)
        #expect(model.sessionDraft.expectedAnnualReturnPercent.isEmpty)
        #expect(model.sessionDraft.annualSpending.isEmpty)
        #expect(model.sessionDraft.withdrawalRatePercent.isEmpty)
        #expect(model.sessionDraft.asOfDate == "2026-01-15")

        model.sessionDraft = terminalDraft()
        #expect(model.applySessionDraft())
        #expect(model.monthlyContributionCNY == terminalCNY("2000.25"))
        #expect(model.expectedAnnualReturn == terminalRatio("0.055"))
        #expect(model.annualSpendingCNY == terminalCNY("120000"))
        #expect(model.withdrawalRate == terminalRatio("0.035"))
        let expectedStart = try CivilDate(canonical: "2026-01-01")
        let expectedEnd = try CivilDate(canonical: "2026-01-31")
        let expectedAsOf = try CivilDate(canonical: "2026-01-15")
        #expect(model.savingRateRange.start == expectedStart)
        #expect(model.savingRateRange.end == expectedEnd)
        #expect(model.asOfDate == expectedAsOf)
        #expect(model.report == nil)
        #expect(model.calculationCount == 0)
    }

    @Test("Invalid session field leaves every confirmed input unchanged")
    @MainActor
    func invalidDraftHasNoPartialApplication() async throws {
        let fixture = try await terminalFixture()
        let model = fixture.model
        model.sessionDraft = terminalDraft()
        #expect(model.applySessionDraft())
        let confirmed = (
            model.monthlyContributionCNY,
            model.expectedAnnualReturn,
            model.annualSpendingCNY,
            model.withdrawalRate,
            model.savingRateRange,
            model.asOfDate
        )

        var invalid = terminalDraft()
        invalid.monthlyContribution = "9999"
        invalid.withdrawalRatePercent = "101"
        model.sessionDraft = invalid
        #expect(!model.applySessionDraft())
        #expect(model.inputError == .invalidWithdrawalRate)
        #expect(model.monthlyContributionCNY == confirmed.0)
        #expect(model.expectedAnnualReturn == confirmed.1)
        #expect(model.annualSpendingCNY == confirmed.2)
        #expect(model.withdrawalRate == confirmed.3)
        #expect(model.savingRateRange == confirmed.4)
        #expect(model.asOfDate == confirmed.5)
    }

    @Test("Withdrawal rate and annual return bounds are typed without a hidden 4 percent default")
    @MainActor
    func boundedRatesAndNoDefault() async throws {
        let fixture = try await terminalFixture()
        let model = fixture.model
        #expect(model.sessionDraft.withdrawalRatePercent.isEmpty)
        #expect(model.withdrawalRate == Ratio(coefficient: 0))

        for value in ["0", "-1", "100.01"] {
            var draft = terminalDraft()
            draft.withdrawalRatePercent = value
            model.sessionDraft = draft
            #expect(!model.applySessionDraft())
            #expect(model.inputError == .invalidWithdrawalRate)
        }
        for value in ["-100", "-101"] {
            var draft = terminalDraft()
            draft.expectedAnnualReturnPercent = value
            model.sessionDraft = draft
            #expect(!model.applySessionDraft())
            #expect(model.inputError == .invalidExpectedAnnualReturn)
        }
    }

    @Test("Canonical dates and inclusive Saving Rate range fail with finite typed states")
    @MainActor
    func dateValidation() async throws {
        let fixture = try await terminalFixture()
        let model = fixture.model
        var draft = terminalDraft()
        draft.savingRateStartDate = "2026-1-01"
        model.sessionDraft = draft
        #expect(!model.applySessionDraft())
        #expect(model.inputError == .invalidSavingStartDate)

        draft = terminalDraft()
        draft.savingRateEndDate = "2026-02-30"
        model.sessionDraft = draft
        #expect(!model.applySessionDraft())
        #expect(model.inputError == .invalidSavingEndDate)

        draft = terminalDraft()
        draft.asOfDate = "not-a-date"
        model.sessionDraft = draft
        #expect(!model.applySessionDraft())
        #expect(model.inputError == .invalidAsOfDate)

        draft = terminalDraft()
        draft.savingRateStartDate = "2026-02-01"
        draft.savingRateEndDate = "2026-01-01"
        model.sessionDraft = draft
        #expect(!model.applySessionDraft())
        #expect(model.inputError == .invalidSavingRateRange)
    }

    @Test("Draft mutation clears a report and never calculates automatically")
    @MainActor
    func explicitCalculateAndDraftInvalidation() async throws {
        let fixture = try await terminalFixture(seedSources: true)
        let model = fixture.model
        await model.load()
        model.sessionDraft = terminalDraft()
        #expect(model.applySessionDraft())
        #expect(model.report == nil)
        #expect(model.calculationCount == 0)
        model.calculate()
        #expect(await waitForTerminalModel(model))
        #expect(model.report != nil)
        #expect(model.calculationCount == 1)
        var changed = model.sessionDraft
        changed.monthlyContribution = "2100"
        model.sessionDraft = changed
        #expect(model.report == nil)
        #expect(model.state == .ready)
        #expect(model.calculationCount == 1)
    }

    @Test("Presentation trajectory is bounded and ends at the Foundation target-date result")
    @MainActor
    func boundedPresentationTrajectory() async throws {
        let fixture = try await maximumTrajectoryFixture(currency: .cny)
        let model = fixture.model
        await model.load()
        model.sessionDraft = maximumTrajectoryDraft()
        #expect(model.applySessionDraft())
        model.calculate()
        #expect(await waitForTerminalModel(model, attempts: 1_000))
        let report = try #require(model.report)
        #expect(report.presentationTrajectory.count == 1_201)
        #expect(report.presentationTrajectory.first?.monthIndex == 0)
        #expect(report.presentationTrajectory.last?.monthIndex == 1_200)
        guard case let .available(trajectory) = report.trajectory else {
            Issue.record("Expected available CNY trajectory")
            return
        }
        #expect(report.presentationTrajectory.last?.projectedValueCNY == trajectory.targetDateScenario.futureValueCNY)
    }

    @Test("USD Goal keeps original currency and publishes typed unavailable projection")
    @MainActor
    func usdProjectionUnavailable() async throws {
        let fixture = try await maximumTrajectoryFixture(currency: .usd)
        let model = fixture.model
        await model.load()
        model.sessionDraft = maximumTrajectoryDraft()
        #expect(model.applySessionDraft())
        model.calculate()
        #expect(await waitForTerminalModel(model))
        let report = try #require(model.report)
        #expect(report.goal.target.currency == .usd)
        #expect(report.progress == .unavailable(.targetCurrencyUnsupportedForCNYProgress))
        #expect(report.trajectory == .unavailable(.targetCurrencyUnsupportedForCNYProgress))
        #expect(report.presentationTrajectory.isEmpty)
    }

    @Test("Synthetic Goals seeding is idempotent and preserves CNY and USD")
    func syntheticSeeder() async throws {
        let root = try terminalTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("permanent/aureus.sqlite"))
        try await SyntheticGoalsSeeder.seed(in: store)
        try await SyntheticGoalsSeeder.seed(in: store)
        let goals = try await store.fetchGoals()
        #expect(goals.count == 2)
        #expect(try await store.fetchGoal(id: SyntheticGoalsSeeder.freedomGoalID)?.target.currency == .cny)
        #expect(try await store.fetchGoal(id: SyntheticGoalsSeeder.educationGoalID)?.target.currency == .usd)
        #expect(try await store.fetchGoal(id: SyntheticGoalsSeeder.freedomGoalID)?.target.minorUnits == 50_000_000)
        #expect(try await store.fetchGoal(id: SyntheticGoalsSeeder.educationGoalID)?.target.minorUnits == 10_000_000)
    }

    @Test("A new FeatureModel does not inherit assumptions or report")
    @MainActor
    func sessionDoesNotPersist() async throws {
        let fixture = try await terminalFixture(seedSources: true)
        await fixture.model.load()
        fixture.model.sessionDraft = terminalDraft()
        #expect(fixture.model.applySessionDraft())
        fixture.model.calculate()
        #expect(await waitForTerminalModel(fixture.model))
        #expect(fixture.model.report != nil)

        let replacement = GoalsFeatureModel(store: fixture.store, clock: terminalClock)
        await replacement.load()
        #expect(replacement.sessionDraft.monthlyContribution.isEmpty)
        #expect(replacement.sessionDraft.expectedAnnualReturnPercent.isEmpty)
        #expect(replacement.sessionDraft.annualSpending.isEmpty)
        #expect(replacement.sessionDraft.withdrawalRatePercent.isEmpty)
        #expect(replacement.report == nil)
        #expect(replacement.calculationCount == 0)
    }

    @Test("Maximum presentation workload is finite, deterministic, and read-only")
    @MainActor
    func presentationPerformance() async throws {
        let fixture = try await maximumTrajectoryFixture(currency: .cny)
        let model = fixture.model
        await model.load()
        model.sessionDraft = maximumTrajectoryDraft()
        #expect(model.applySessionDraft())
        let confirmedGoals = try await fixture.store.fetchGoals()
        let clock = ContinuousClock()
        let start = clock.now
        model.calculate()
        #expect(await waitForTerminalModel(model, attempts: 1_000))
        let first = try #require(model.report)
        model.calculate()
        #expect(await waitForTerminalModel(model, attempts: 1_000))
        let second = try #require(model.report)
        let duration = start.duration(to: clock.now)
        #expect(first == second)
        #expect(first.presentationTrajectory.count == 1_201)
        #expect(try await fixture.store.fetchGoals() == confirmedGoals)
        #expect(duration < .seconds(10))
    }
}

private let terminalClock = FixedClock(
    instant: UTCInstant(millisecondsSince1970: 1_768_435_200_000)
)

@MainActor
private func terminalFixture(
    seedSources: Bool = false
) async throws -> (root: URL, store: WealthStore, model: GoalsFeatureModel) {
    let root = try terminalTemporaryDirectory()
    let store = try WealthStore(databaseURL: root.appendingPathComponent("permanent/aureus.sqlite"))
    if seedSources {
        try await store.seedSyntheticWealth()
        try await SyntheticLedgerSeeder.seed(in: store)
    }
    try await store.createGoal(try Goal(
        id: UUID(uuidString: "91000000-0000-4000-8000-000000000001")!,
        name: "Synthetic Terminal Goal",
        target: terminalCNY("500000"),
        targetDate: try CivilDate(canonical: "2035-12-31")
    ))
    return (root, store, GoalsFeatureModel(store: store, clock: terminalClock))
}

@MainActor
private func maximumTrajectoryFixture(
    currency: CurrencyCode
) async throws -> (root: URL, store: WealthStore, model: GoalsFeatureModel) {
    let root = try terminalTemporaryDirectory()
    let store = try WealthStore(databaseURL: root.appendingPathComponent("permanent/aureus.sqlite"))
    try await store.createGoal(try Goal(
        id: UUID(uuidString: "91000000-0000-4000-8000-000000000002")!,
        name: "Synthetic Maximum Trajectory",
        target: Money(minorUnits: 50_000_000, currency: currency),
        targetDate: try CivilDate(canonical: "2126-01-31")
    ))
    return (root, store, GoalsFeatureModel(store: store, clock: terminalClock))
}

private func terminalDraft() -> GoalsSessionDraft {
    var draft = GoalsSessionDraft(date: try! CivilDate(canonical: "2026-01-15"))
    draft.monthlyContribution = "2000.25"
    draft.expectedAnnualReturnPercent = "5.5"
    draft.annualSpending = "120000"
    draft.withdrawalRatePercent = "3.5"
    draft.savingRateStartDate = "2026-01-01"
    draft.savingRateEndDate = "2026-01-31"
    draft.asOfDate = "2026-01-15"
    return draft
}

private func maximumTrajectoryDraft() -> GoalsSessionDraft {
    var draft = terminalDraft()
    draft.monthlyContribution = "1000"
    draft.expectedAnnualReturnPercent = "0"
    draft.annualSpending = "12000"
    draft.withdrawalRatePercent = "5"
    return draft
}

private func terminalCNY(_ text: String) -> Money {
    try! Money(decimal: FixedPointMath.parseCanonical(text), currency: .cny)
}

private func terminalRatio(_ text: String) -> Ratio {
    try! Ratio(decimal: FixedPointMath.parseCanonical(text))
}

private func terminalTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("AureusGoalsTerminalTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@MainActor
private func waitForTerminalModel(
    _ model: GoalsFeatureModel,
    attempts: Int = 500
) async -> Bool {
    for _ in 0..<attempts {
        if model.state != .calculating { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}
