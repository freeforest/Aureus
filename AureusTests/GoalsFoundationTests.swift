import Foundation
import GRDB
import Testing
@testable import Aureus

@Suite("Stage 10 Goal planning")
struct GoalPlanningTests {
    @Test("Goal validation trims names and preserves CNY, USD, and optional dates")
    func goalValidationAndCurrencies() throws {
        let date = try CivilDate(canonical: "2035-12-31")
        let cny = try Goal(
            name: "  Synthetic Home  ",
            target: Money(minorUnits: 50_000_000, currency: .cny),
            targetDate: date
        )
        let usd = try Goal(
            name: "Synthetic USD Education",
            target: Money(minorUnits: 25_000_00, currency: .usd)
        )
        #expect(cny.name == "Synthetic Home")
        #expect(cny.target.currency == .cny)
        #expect(cny.targetDate == date)
        #expect(usd.target.currency == .usd)
        #expect(usd.targetDate == nil)
        #expect(throws: GoalValidationError.emptyName) {
            _ = try Goal(name: " \n ", target: Money(minorUnits: 1, currency: .cny))
        }
        #expect(throws: GoalValidationError.nonPositiveTarget) {
            _ = try Goal(name: "Synthetic Invalid", target: Money(minorUnits: 0, currency: .cny))
        }
        #expect(throws: GoalValidationError.nonPositiveTarget) {
            _ = try Goal(name: "Synthetic Invalid", target: Money(minorUnits: -1, currency: .usd))
        }
    }

    @Test("Goal Codable decode cannot bypass validation")
    func goalCodableValidation() throws {
        let invalidName = Data("""
            {"id":"00000000-0000-4000-8000-000000010001","name":"   ","target":{"minorUnits":100,"currency":"CNY"},"targetDate":null}
            """.utf8)
        let invalidTarget = Data("""
            {"id":"00000000-0000-4000-8000-000000010002","name":"Synthetic Invalid","target":{"minorUnits":-100,"currency":"USD"},"targetDate":null}
            """.utf8)
        #expect(throws: GoalValidationError.emptyName) {
            _ = try JSONDecoder().decode(Goal.self, from: invalidName)
        }
        #expect(throws: GoalValidationError.nonPositiveTarget) {
            _ = try JSONDecoder().decode(Goal.self, from: invalidTarget)
        }

        let original = try Goal(
            id: deterministicGoalUUID(3),
            name: "Synthetic Round Trip",
            target: Money(minorUnits: 123_456, currency: .usd),
            targetDate: try CivilDate(canonical: "2040-06-15")
        )
        #expect(try JSONDecoder().decode(Goal.self, from: JSONEncoder().encode(original)) == original)
    }

    @Test("Compound planning zero-rate and positive-rate cases are hand verifiable")
    func compoundGoldenCases() throws {
        let zero = try GoalPlanning.compound(CompoundPlanningInput(
            initialCapitalCNY: cny("100.00"),
            monthlyContributionCNY: cny("10.00"),
            expectedAnnualReturn: ratio("0"),
            months: 12
        ))
        #expect(zero.futureValueCNY == cny("220.00"))
        #expect(zero.totalContributionsCNY == cny("120.00"))
        #expect(zero.assumptionGrowthCNY == cny("0"))

        let positive = try GoalPlanning.compound(CompoundPlanningInput(
            initialCapitalCNY: cny("100.00"),
            monthlyContributionCNY: cny("10.00"),
            expectedAnnualReturn: ratio("0.12"),
            months: 12
        ))
        #expect(positive.futureValueCNY == cny("239.51"))
        #expect(positive.initialCapitalCNY == cny("100.00"))
        #expect(positive.totalContributionsCNY == cny("120.00"))
        #expect(positive.assumptionGrowthCNY == cny("19.51"))
        #expect(positive.annualReturn == ratio("0.12"))
    }

    @Test("Compound planning supports negative valid return, zero months, and banker rounding")
    func compoundBoundaries() throws {
        let negative = try GoalPlanning.compound(CompoundPlanningInput(
            initialCapitalCNY: cny("100.00"),
            monthlyContributionCNY: cny("10.00"),
            expectedAnnualReturn: ratio("-0.12"),
            months: 12
        ))
        let zeroRate = try GoalPlanning.compound(CompoundPlanningInput(
            initialCapitalCNY: cny("100.00"),
            monthlyContributionCNY: cny("10.00"),
            expectedAnnualReturn: ratio("0"),
            months: 12
        ))
        #expect(negative.futureValueCNY.minorUnits < zeroRate.futureValueCNY.minorUnits)

        let zeroMonths = try GoalPlanning.compound(CompoundPlanningInput(
            initialCapitalCNY: cny("-25.00"),
            monthlyContributionCNY: cny("50.00"),
            expectedAnnualReturn: ratio("0.25"),
            months: 0
        ))
        #expect(zeroMonths.futureValueCNY == cny("-25.00"))
        #expect(zeroMonths.totalContributionsCNY == cny("0"))

        let tie = try GoalPlanning.compound(CompoundPlanningInput(
            initialCapitalCNY: cny("1.00"),
            monthlyContributionCNY: cny("0"),
            expectedAnnualReturn: ratio("0.06"),
            months: 1
        ))
        #expect(tie.futureValueCNY == cny("1.00"))
    }

    @Test("Compound planning rejects invalid inputs and overflow")
    func compoundFailures() throws {
        let base = CompoundPlanningInput(
            initialCapitalCNY: cny("1"),
            monthlyContributionCNY: cny("0"),
            expectedAnnualReturn: ratio("0"),
            months: 1
        )
        #expect(throws: GoalPlanningError.invalidAnnualReturn) {
            _ = try GoalPlanning.compound(CompoundPlanningInput(
                initialCapitalCNY: base.initialCapitalCNY,
                monthlyContributionCNY: base.monthlyContributionCNY,
                expectedAnnualReturn: ratio("-1"),
                months: 1
            ))
        }
        for months in [-1, 1_201] {
            #expect(throws: GoalPlanningError.invalidMonthCount) {
                _ = try GoalPlanning.compound(CompoundPlanningInput(
                    initialCapitalCNY: base.initialCapitalCNY,
                    monthlyContributionCNY: base.monthlyContributionCNY,
                    expectedAnnualReturn: base.expectedAnnualReturn,
                    months: months
                ))
            }
        }
        #expect(throws: GoalPlanningError.negativeMonthlyContribution) {
            _ = try GoalPlanning.compound(CompoundPlanningInput(
                initialCapitalCNY: base.initialCapitalCNY,
                monthlyContributionCNY: cny("-0.01"),
                expectedAnnualReturn: base.expectedAnnualReturn,
                months: 1
            ))
        }
        #expect(throws: (any Error).self) {
            _ = try GoalPlanning.compound(CompoundPlanningInput(
                initialCapitalCNY: Money(minorUnits: .max, currency: .cny),
                monthlyContributionCNY: cny("0"),
                expectedAnnualReturn: ratio("1"),
                months: 1_200
            ))
        }
    }

    @Test("Compound planning is deterministic and monotonic for nonnegative inputs")
    func compoundDeterminismAndMonotonicity() throws {
        let input = CompoundPlanningInput(
            initialCapitalCNY: cny("1000"),
            monthlyContributionCNY: cny("100"),
            expectedAnnualReturn: ratio("0.05"),
            months: 120
        )
        let first = try GoalPlanning.compound(input)
        #expect(try GoalPlanning.compound(input) == first)
        let higherContribution = try GoalPlanning.compound(CompoundPlanningInput(
            initialCapitalCNY: input.initialCapitalCNY,
            monthlyContributionCNY: cny("101"),
            expectedAnnualReturn: input.expectedAnnualReturn,
            months: input.months
        ))
        let higherReturn = try GoalPlanning.compound(CompoundPlanningInput(
            initialCapitalCNY: input.initialCapitalCNY,
            monthlyContributionCNY: input.monthlyContributionCNY,
            expectedAnnualReturn: ratio("0.06"),
            months: input.months
        ))
        #expect(higherContribution.futureValueCNY.minorUnits > first.futureValueCNY.minorUnits)
        #expect(higherReturn.futureValueCNY.minorUnits > first.futureValueCNY.minorUnits)
    }

    @Test("Goal progress preserves negative and over-one ratios without clamping")
    func goalProgress() throws {
        let goal = try Goal(name: "Synthetic Target", target: cny("100"))
        let below = try availableProgress(GoalPlanning.progress(goal: goal, currentNetWorthCNY: cny("40")))
        #expect(below.progress == ratio("0.4"))
        #expect(below.remainingCNY == cny("60"))
        let exact = try availableProgress(GoalPlanning.progress(goal: goal, currentNetWorthCNY: cny("100")))
        #expect(exact.progress == ratio("1"))
        #expect(exact.remainingCNY == cny("0"))
        let above = try availableProgress(GoalPlanning.progress(goal: goal, currentNetWorthCNY: cny("125")))
        #expect(above.progress == ratio("1.25"))
        #expect(above.remainingCNY == cny("0"))
        let negative = try availableProgress(GoalPlanning.progress(goal: goal, currentNetWorthCNY: cny("-25")))
        #expect(negative.progress == ratio("-0.25"))
        #expect(negative.remainingCNY == cny("125"))
    }

    @Test("USD and target-date trajectory states remain typed and bounded")
    func trajectoryStates() throws {
        let asOf = try CivilDate(canonical: "2026-01-31")
        let usd = try Goal(name: "Synthetic USD", target: usd("1000"))
        #expect(
            try GoalPlanning.progress(goal: usd, currentNetWorthCNY: cny("100"))
                == .unavailable(.targetCurrencyUnsupportedForCNYProgress)
        )
        #expect(
            try GoalPlanning.targetDateTrajectory(
                goal: usd,
                currentNetWorthCNY: cny("100"),
                monthlyContributionCNY: cny("10"),
                expectedAnnualReturn: ratio("0"),
                asOf: asOf
            ) == .unavailable(.targetCurrencyUnsupportedForCNYProgress)
        )

        let missing = try Goal(name: "Synthetic Missing", target: cny("1000"))
        #expect(
            try GoalPlanning.targetDateTrajectory(
                goal: missing,
                currentNetWorthCNY: cny("100"),
                monthlyContributionCNY: cny("10"),
                expectedAnnualReturn: ratio("0"),
                asOf: asOf
            ) == .unavailable(.missingTargetDate)
        )
        let stale = try Goal(
            name: "Synthetic Stale",
            target: cny("1000"),
            targetDate: try CivilDate(canonical: "2026-01-01")
        )
        #expect(
            try GoalPlanning.targetDateTrajectory(
                goal: stale,
                currentNetWorthCNY: cny("100"),
                monthlyContributionCNY: cny("10"),
                expectedAnnualReturn: ratio("0"),
                asOf: asOf
            ) == .unavailable(.targetDateNotFuture)
        )
        let reached = try Goal(
            name: "Synthetic Reached",
            target: cny("100"),
            targetDate: try CivilDate(canonical: "2030-01-01")
        )
        #expect(
            try GoalPlanning.targetDateTrajectory(
                goal: reached,
                currentNetWorthCNY: cny("100"),
                monthlyContributionCNY: cny("10"),
                expectedAnnualReturn: ratio("0"),
                asOf: asOf
            ) == .unavailable(.alreadyReached)
        )
    }

    @Test("Target-date scenario uses civil month buckets and 1200-month bounded reach")
    func targetDateBoundedReach() throws {
        let goal = try Goal(
            name: "Synthetic Century Goal",
            target: cny("1000"),
            targetDate: try CivilDate(canonical: "2126-01-15")
        )
        let result = try GoalPlanning.targetDateTrajectory(
            goal: goal,
            currentNetWorthCNY: cny("0"),
            monthlyContributionCNY: cny("1"),
            expectedAnnualReturn: ratio("0"),
            asOf: try CivilDate(canonical: "2026-01-31")
        )
        guard case let .available(trajectory) = result else {
            Issue.record("Expected available bounded trajectory")
            return
        }
        #expect(trajectory.targetMonthCount == 1_200)
        #expect(trajectory.targetDateScenario.futureValueCNY == cny("1200"))
        #expect(trajectory.estimatedReach == .reached(months: 1_000, projectedValueCNY: cny("1000")))
    }

    @Test("FIRE scenario has exact arithmetic, explicit assumptions, and no hidden rate")
    func fireGoldenAndAssumptions() throws {
        let input = FIREScenarioInput(
            annualSpendingCNY: cny("40000"),
            withdrawalRate: ratio("0.04"),
            currentNetWorthCNY: cny("250000"),
            monthlyContributionCNY: cny("1000"),
            expectedAnnualReturn: ratio("0")
        )
        let scenario = try GoalPlanning.fireScenario(input)
        #expect(scenario.fireNumberCNY == cny("1000000"))
        #expect(scenario.progress == ratio("0.25"))
        #expect(scenario.withdrawalRate == input.withdrawalRate)
        #expect(scenario.annualSpendingCNY == input.annualSpendingCNY)

        let different = try GoalPlanning.fireScenario(FIREScenarioInput(
            annualSpendingCNY: input.annualSpendingCNY,
            withdrawalRate: ratio("0.05"),
            currentNetWorthCNY: input.currentNetWorthCNY,
            monthlyContributionCNY: input.monthlyContributionCNY,
            expectedAnnualReturn: input.expectedAnnualReturn
        ))
        #expect(different.fireNumberCNY == cny("800000"))
        #expect(different.withdrawalRate == ratio("0.05"))
    }

    @Test("FIRE validation and bounded reach are typed")
    func fireBoundaries() throws {
        func input(spending: String = "1200", rate: String = "0.1", current: String = "0", contribution: String = "1000") -> FIREScenarioInput {
            FIREScenarioInput(
                annualSpendingCNY: cny(spending),
                withdrawalRate: ratio(rate),
                currentNetWorthCNY: cny(current),
                monthlyContributionCNY: cny(contribution),
                expectedAnnualReturn: ratio("0")
            )
        }
        #expect(throws: GoalPlanningError.invalidAnnualSpending) {
            _ = try GoalPlanning.fireScenario(input(spending: "0"))
        }
        for invalid in ["0", "-0.01", "1.01"] {
            #expect(throws: GoalPlanningError.invalidWithdrawalRate) {
                _ = try GoalPlanning.fireScenario(input(rate: invalid))
            }
        }
        let reached = try GoalPlanning.fireScenario(input(current: "12000"))
        #expect(reached.estimatedReach == .alreadyReached)
        let bounded = try GoalPlanning.fireScenario(input())
        #expect(bounded.estimatedReach == .reached(months: 12, projectedValueCNY: cny("12000")))
        let unavailable = try GoalPlanning.fireScenario(input(contribution: "0"))
        #expect(unavailable.estimatedReach == .unavailable(.notReachedWithinMaximumMonths))
    }

    @Test("Saving Rate uses ordinary CNY provenance and preserves negative results")
    func savingRateGoldenAndNegative() throws {
        let january = try CivilDate(canonical: "2026-01-15")
        let range = try SavingRateRange(
            start: try CivilDate(canonical: "2026-01-01"),
            end: try CivilDate(canonical: "2026-01-31")
        )
        let positive = try GoalPlanning.savingRate(entries: [
            try ledgerEntry(kind: .income, date: january, convertedCNYMinor: 1_000_000, suffix: 1),
            try ledgerEntry(kind: .expense, date: january, convertedCNYMinor: 400_000, suffix: 2)
        ], range: range)
        #expect(positive.ordinaryIncomeCNY == cny("10000"))
        #expect(positive.ordinaryExpenseCNY == cny("4000"))
        #expect(positive.ordinarySavingsCNY == cny("6000"))
        #expect(positive.aggregateRate == .available(ratio("0.6")))
        #expect(positive.observedMonths.count == 1)

        let negative = try GoalPlanning.savingRate(entries: [
            try ledgerEntry(kind: .income, date: january, convertedCNYMinor: 100_000, suffix: 3),
            try ledgerEntry(kind: .expense, date: january, convertedCNYMinor: 250_000, suffix: 4)
        ], range: range)
        #expect(negative.ordinarySavingsCNY == cny("-1500"))
        #expect(negative.aggregateRate == .available(ratio("-1.5")))
    }

    @Test("Saving Rate keeps expense-only and empty ranges typed without zero fill")
    func savingRateUnavailableAndObservedMonths() throws {
        let range = try SavingRateRange(
            start: try CivilDate(canonical: "2026-01-01"),
            end: try CivilDate(canonical: "2026-03-31")
        )
        let report = try GoalPlanning.savingRate(entries: [
            try ledgerEntry(kind: .expense, date: CivilDate(canonical: "2026-01-10"), convertedCNYMinor: 500, suffix: 10),
            try ledgerEntry(kind: .income, date: CivilDate(canonical: "2026-03-10"), convertedCNYMinor: 1_000, suffix: 11)
        ], range: range)
        #expect(report.observedMonths.map(\.period) == [
            GoalPlanningMonth(try CivilDate(canonical: "2026-01-01")),
            GoalPlanningMonth(try CivilDate(canonical: "2026-03-01"))
        ])
        #expect(report.observedMonths[0].savingRate == .unavailable(.nonPositiveIncome))
        #expect(report.observedMonths.count == 2)

        let empty = try GoalPlanning.savingRate(entries: [], range: range)
        #expect(empty.observedMonths.isEmpty)
        #expect(empty.aggregateRate == .unavailable(.nonPositiveIncome))
        #expect(empty.ordinarySavingsCNY == cny("0"))
        #expect(throws: GoalPlanningError.invalidDateRange) {
            _ = try SavingRateRange(
                start: try CivilDate(canonical: "2026-02-01"),
                end: try CivilDate(canonical: "2026-01-31")
            )
        }
    }

    @Test("Transfers and investment flows are excluded and stored USD conversion is reused")
    func savingRateExclusionsAndUSDProvenance() throws {
        let date = try CivilDate(canonical: "2026-02-15")
        let range = try SavingRateRange(start: date, end: date)
        var entries: [LedgerEntry] = [
            try usdLedgerEntry(kind: .income, date: date, originalUSDCents: 1_000, rate: "7", suffix: 20),
            try ledgerEntry(kind: .expense, date: date, convertedCNYMinor: 2_000, suffix: 21)
        ]
        for (index, kind) in [TransactionKind.buy, .sell, .dividend, .interest, .fee].enumerated() {
            entries.append(try ledgerEntry(kind: kind, date: date, convertedCNYMinor: 99_999, suffix: 30 + index))
        }
        entries.append(try transferEntry(date: date, suffix: 40))
        let original = entries
        let report = try GoalPlanning.savingRate(entries: entries, range: range)
        #expect(entries == original)
        #expect(report.includedEntryCount == 2)
        #expect(report.ordinaryIncomeCNY == cny("70"))
        #expect(report.ordinaryExpenseCNY == cny("20"))
        #expect(report.ordinarySavingsCNY == cny("50"))
        #expect(report.aggregateRate == .available(ratio("0.7142857143")))
        #expect(SavingRateReport.disclosure.contains("transfers"))
    }

    @Test("Release Goals workload remains deterministic and bounded")
    func releaseWorkload() throws {
        let started = ContinuousClock.now
        let compoundInputs = (0..<1_000).map { index in
            CompoundPlanningInput(
                initialCapitalCNY: cny("10000"),
                monthlyContributionCNY: cny(String(100 + index % 10)),
                expectedAnnualReturn: ratio("0.05"),
                months: index % 1_201
            )
        }
        let compoundOutputs = try compoundInputs.map(GoalPlanning.compound)
        let repeatedOutputs = try compoundInputs.map(GoalPlanning.compound)
        #expect(compoundOutputs == repeatedOutputs)

        let entries = try performanceLedgerEntries(count: 10_000)
        let immutableEntries = entries
        let range = try SavingRateRange(
            start: try CivilDate(canonical: "2020-01-01"),
            end: try CivilDate(canonical: "2029-12-31")
        )
        let saving = try GoalPlanning.savingRate(entries: entries, range: range)
        #expect(entries == immutableEntries)
        #expect(saving.observedMonths.count == 120)

        let centuryGoal = try Goal(
            name: "Synthetic Performance Reach",
            target: cny("1200"),
            targetDate: try CivilDate(canonical: "2126-01-01")
        )
        let trajectory = try GoalPlanning.targetDateTrajectory(
            goal: centuryGoal,
            currentNetWorthCNY: cny("0"),
            monthlyContributionCNY: cny("1"),
            expectedAnnualReturn: ratio("0"),
            asOf: try CivilDate(canonical: "2026-01-31")
        )
        let fire = try GoalPlanning.fireScenario(FIREScenarioInput(
            annualSpendingCNY: cny("120"),
            withdrawalRate: ratio("0.1"),
            currentNetWorthCNY: cny("0"),
            monthlyContributionCNY: cny("1"),
            expectedAnnualReturn: ratio("0")
        ))
        guard case let .available(availableTrajectory) = trajectory else {
            Issue.record("Expected performance trajectory")
            return
        }
        #expect(availableTrajectory.estimatedReach == .reached(months: 1_200, projectedValueCNY: cny("1200")))
        #expect(fire.estimatedReach == .reached(months: 1_200, projectedValueCNY: cny("1200")))

        let elapsed = milliseconds(started.duration(to: .now))
        print("STAGE10_GOALS_PERF compounds=1000 ledger_entries=10000 observed_months=\(saving.observedMonths.count) reach_horizon=1200 elapsed_ms=\(elapsed) provider_requests=0 persistence_writes=0")
        #expect(elapsed < 10_000)
    }
}

@Suite("Stage 10 Goal persistence")
struct GoalPersistenceTests {
    @Test("Goal CRUD, CNY and USD round-trip, reopen, and deterministic sorting")
    func crudReopenAndSorting() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("permanent/aureus.sqlite")
        let store = try WealthStore(databaseURL: url)
        let late = try Goal(
            id: deterministicGoalUUID(100),
            name: "beta",
            target: cny("500"),
            targetDate: try CivilDate(canonical: "2035-01-01")
        )
        let earlyB = try Goal(
            id: deterministicGoalUUID(102),
            name: "zeta",
            target: usd("100"),
            targetDate: try CivilDate(canonical: "2030-01-01")
        )
        let earlyA = try Goal(
            id: deterministicGoalUUID(101),
            name: "Alpha",
            target: cny("200"),
            targetDate: try CivilDate(canonical: "2030-01-01")
        )
        let undated = try Goal(
            id: deterministicGoalUUID(103),
            name: "Gamma",
            target: usd("300")
        )
        for goal in [late, earlyB, earlyA, undated] { try await store.createGoal(goal) }
        #expect(try await store.fetchGoals().map(\.id) == [earlyA.id, earlyB.id, late.id, undated.id])
        #expect(try await store.fetchGoal(id: earlyB.id) == earlyB)

        let updated = try Goal(
            id: late.id,
            name: "Synthetic Updated",
            target: usd("750.25"),
            targetDate: try CivilDate(canonical: "2032-06-15")
        )
        try await store.updateGoal(updated)
        let reopened = try WealthStore(databaseURL: url)
        #expect(try await reopened.fetchGoal(id: updated.id) == updated)
        #expect(try await reopened.fetchGoal(id: earlyA.id)?.target.currency == .cny)
        #expect(try await reopened.fetchGoal(id: undated.id)?.target.currency == .usd)
        try await reopened.deleteGoal(id: earlyB.id)
        #expect(try await reopened.fetchGoal(id: earlyB.id) == nil)
    }

    @Test("Goal not-found mutations are typed and leave confirmed records unchanged")
    func notFoundAndRollback() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("aureus.sqlite"))
        let existing = try Goal(
            id: deterministicGoalUUID(110),
            name: "Synthetic Existing",
            target: cny("100")
        )
        try await store.createGoal(existing)
        let missing = try Goal(
            id: deterministicGoalUUID(111),
            name: "Synthetic Missing",
            target: cny("200")
        )
        await #expect(throws: GoalPersistenceError.goalNotFound) {
            try await store.updateGoal(missing)
        }
        await #expect(throws: GoalPersistenceError.goalNotFound) {
            try await store.deleteGoal(id: missing.id)
        }
        #expect(try await store.fetchGoals() == [existing])
    }

    @Test("Invalid persisted Goal rows are typed corruption")
    func corruptRowDetection() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("aureus.sqlite"))
        let queue = await store.queue
        try await queue.write { db in
            try db.execute(
                sql: "INSERT INTO goals (id, name, target_minor, currency_code, target_date) VALUES (?, '   ', -1, 'CNY', NULL)",
                arguments: [deterministicGoalUUID(120).uuidString]
            )
        }
        await #expect(throws: GoalPersistenceError.corruptRecord) {
            _ = try await store.fetchGoals()
        }
    }

    @Test("Goal schema remains permanent version 8 with INTEGER authority and no REAL column")
    func schemaBoundary() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("aureus.sqlite"))
        #expect(try await store.schemaVersion() == 8)
        let queue = await store.queue
        let declarations = try await queue.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(goals)").map { row -> (String, String) in
                (row["name"], row["type"])
            }
        }
        #expect(Dictionary(uniqueKeysWithValues: declarations)["target_minor"] == "INTEGER")
        #expect(declarations.allSatisfy { $0.1.uppercased() != "REAL" })
        let goalTables = try await queue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE '%goal%' ORDER BY name"
            )
        }
        #expect(goalTables == ["goals"])
    }
}

@Suite("Stage 10 Goals Feature Model")
struct GoalsFeatureModelTests {
    @Test("Load never calculates and explicit Calculate publishes one report")
    @MainActor
    func explicitCalculationOnly() async throws {
        let fixture = try await featureFixture()
        await fixture.model.load()
        #expect(fixture.model.state == .ready)
        #expect(fixture.model.report == nil)
        #expect(fixture.model.calculationCount == 0)
        configure(fixture.model)
        #expect(fixture.model.report == nil)
        fixture.model.calculate()
        #expect(await waitForGoalsTerminal(fixture.model))
        #expect(fixture.model.state == .ready)
        #expect(fixture.model.report?.goal.id == fixture.goal.id)
        #expect(fixture.model.calculationCount == 1)
    }

    @Test("Goal, input, and source changes invalidate old reports")
    @MainActor
    func invalidationLifecycle() async throws {
        let fixture = try await featureFixture()
        await fixture.model.load()
        configure(fixture.model)
        fixture.model.calculate()
        #expect(await waitForGoalsTerminal(fixture.model))
        #expect(fixture.model.report != nil)
        fixture.model.monthlyContributionCNY = cny("321")
        #expect(fixture.model.report == nil)
        #expect(fixture.model.state == .ready)
        #expect(fixture.model.calculationCount == 1)

        let second = try Goal(
            id: deterministicGoalUUID(202),
            name: "Synthetic Second Feature Goal",
            target: cny("900000"),
            targetDate: try CivilDate(canonical: "2040-01-01")
        )
        await fixture.model.createGoal(second)
        #expect(fixture.model.selectedGoalID == second.id)
        #expect(fixture.model.report == nil)
        #expect(try await fixture.store.fetchGoal(id: second.id) == second)
    }

    @Test("Old generation cannot overwrite an input mutation")
    @MainActor
    func staleGenerationIsolation() async throws {
        let fixture = try await featureFixture()
        await fixture.model.load()
        configure(fixture.model)
        fixture.model.calculate()
        fixture.model.expectedAnnualReturn = ratio("0.07")
        try await Task.sleep(for: .milliseconds(50))
        #expect(fixture.model.report == nil)
        #expect(fixture.model.state == .ready)
        #expect(fixture.model.calculationCount == 0)
    }

    @Test("FeatureModel CRUD persists and requires explicit delete confirmation")
    @MainActor
    func crudAndConfirmedDelete() async throws {
        let fixture = try await featureFixture()
        await fixture.model.load()
        let created = try Goal(
            id: deterministicGoalUUID(203),
            name: "Synthetic CRUD Goal",
            target: usd("10000")
        )
        await fixture.model.createGoal(created)
        #expect(try await fixture.store.fetchGoal(id: created.id) == created)
        let updated = try Goal(
            id: created.id,
            name: "Synthetic CRUD Updated",
            target: usd("12500"),
            targetDate: try CivilDate(canonical: "2042-02-02")
        )
        await fixture.model.updateGoal(updated)
        #expect(try await fixture.store.fetchGoal(id: updated.id) == updated)
        await fixture.model.deleteGoal(id: updated.id, confirmed: false)
        #expect(try await fixture.store.fetchGoal(id: updated.id) == updated)
        await fixture.model.deleteGoal(id: updated.id, confirmed: true)
        #expect(try await fixture.store.fetchGoal(id: updated.id) == nil)
        #expect(fixture.model.report == nil)
    }

    @Test("Delete failure is finite and preserves confirmed permanent records")
    @MainActor
    func finiteDeleteFailure() async throws {
        let fixture = try await featureFixture()
        await fixture.model.load()
        let confirmed = fixture.model.goals
        await fixture.model.deleteGoal(id: deterministicGoalUUID(999), confirmed: true)
        #expect(fixture.model.state == .failed)
        #expect(fixture.model.goals == confirmed)
        #expect(try await fixture.store.fetchGoal(id: fixture.goal.id) == fixture.goal)
        #expect(fixture.model.errorMessage != nil)
    }

    @Test("Goals FeatureModel has no Provider, Cache, or Keychain dependency")
    @MainActor
    func localDependencyBoundary() async throws {
        let fixture = try await featureFixture()
        await fixture.model.load()
        #expect(GoalsFeatureModel.localOnlyDisclosure.contains("no Provider"))
        #expect(GoalsFeatureModel.localOnlyDisclosure.contains("Market Cache"))
        #expect(GoalsFeatureModel.localOnlyDisclosure.contains("Keychain"))
        #expect(fixture.model.calculationCount == 0)
    }
}

private func cny(_ text: String) -> Money {
    try! Money(decimal: FixedPointMath.parseCanonical(text), currency: .cny)
}

private func usd(_ text: String) -> Money {
    try! Money(decimal: FixedPointMath.parseCanonical(text), currency: .usd)
}

private func ratio(_ text: String) -> Ratio {
    try! Ratio(decimal: FixedPointMath.parseCanonical(text))
}

private func deterministicGoalUUID(_ suffix: Int) -> UUID {
    UUID(uuidString: String(format: "90000000-0000-4000-8000-%012d", suffix))!
}

private func availableProgress(_ result: GoalProgressResult) throws -> GoalProgress {
    guard case let .available(progress) = result else {
        throw GoalPlanningUnavailableReason.targetCurrencyUnsupportedForCNYProgress
    }
    return progress
}

private func ledgerEntry(
    kind: TransactionKind,
    date: CivilDate,
    convertedCNYMinor: Int64,
    suffix: Int
) throws -> LedgerEntry {
    let valuation = try FXValuation(
        original: Money(minorUnits: convertedCNYMinor, currency: .cny),
        rate: .cnyIdentity,
        referenceDate: date,
        fetchedAt: UTCInstant(millisecondsSince1970: 1_800_000_000_000 + Int64(suffix)),
        providerIdentifier: "identity",
        isStale: false
    )
    return try LedgerEntry(
        id: deterministicGoalUUID(10_000 + suffix),
        kind: kind,
        civilDate: date,
        recordedAt: UTCInstant(millisecondsSince1970: 1_800_000_000_000 + Int64(suffix)),
        description: "Synthetic Goal Ledger \(suffix)",
        postings: [try LedgerPosting(
            id: deterministicGoalUUID(20_000 + suffix),
            role: .primary,
            containerID: deterministicGoalUUID(30_000),
            valuation: valuation
        )]
    )
}

private func usdLedgerEntry(
    kind: TransactionKind,
    date: CivilDate,
    originalUSDCents: Int64,
    rate: String,
    suffix: Int
) throws -> LedgerEntry {
    let valuation = try FXValuation(
        original: Money(minorUnits: originalUSDCents, currency: .usd),
        rate: FXRate(
            decimal: FixedPointMath.parseCanonical(rate),
            sourceCurrency: .usd,
            targetCurrency: .cny
        ),
        referenceDate: date,
        fetchedAt: UTCInstant(millisecondsSince1970: 1_800_000_000_000 + Int64(suffix)),
        providerIdentifier: "manual.synthetic.stage10.tests",
        isManualOverride: true,
        isStale: false
    )
    return try LedgerEntry(
        id: deterministicGoalUUID(40_000 + suffix),
        kind: kind,
        civilDate: date,
        recordedAt: UTCInstant(millisecondsSince1970: 1_800_000_000_000 + Int64(suffix)),
        description: "Synthetic Goal USD Ledger \(suffix)",
        postings: [try LedgerPosting(
            id: deterministicGoalUUID(50_000 + suffix),
            role: .primary,
            containerID: deterministicGoalUUID(30_000),
            valuation: valuation
        )]
    )
}

private func transferEntry(date: CivilDate, suffix: Int) throws -> LedgerEntry {
    let instant = UTCInstant(millisecondsSince1970: 1_800_000_000_000 + Int64(suffix))
    let valuation = try FXValuation(
        original: cny("100"),
        rate: .cnyIdentity,
        referenceDate: date,
        fetchedAt: instant,
        providerIdentifier: "identity",
        isStale: false
    )
    return try LedgerEntry(
        id: deterministicGoalUUID(60_000 + suffix),
        kind: .transfer,
        civilDate: date,
        recordedAt: instant,
        description: "Synthetic Goal Transfer",
        postings: [
            try LedgerPosting(
                id: deterministicGoalUUID(61_000 + suffix),
                role: .transferSource,
                containerID: deterministicGoalUUID(31_000),
                valuation: valuation
            ),
            try LedgerPosting(
                id: deterministicGoalUUID(62_000 + suffix),
                role: .transferTarget,
                containerID: deterministicGoalUUID(32_000),
                valuation: valuation
            )
        ]
    )
}

private func performanceLedgerEntries(count: Int) throws -> [LedgerEntry] {
    try (0..<count).map { index in
        let period = index % 120
        let date = try CivilDate(
            year: 2020 + period / 12,
            month: period % 12 + 1,
            day: index % 27 + 1
        )
        return try ledgerEntry(
            kind: index.isMultiple(of: 2) ? .income : .expense,
            date: date,
            convertedCNYMinor: index.isMultiple(of: 2) ? 10_000 : 4_000,
            suffix: 100_000 + index
        )
    }
}

private func milliseconds(_ duration: Duration) -> Int64 {
    let components = duration.components
    return components.seconds * 1_000
        + Int64(components.attoseconds / 1_000_000_000_000_000)
}

@MainActor
private func featureFixture() async throws -> (
    root: URL,
    store: WealthStore,
    model: GoalsFeatureModel,
    goal: Goal
) {
    let root = try temporaryDirectory()
    let store = try WealthStore(databaseURL: root.appendingPathComponent("permanent/aureus.sqlite"))
    try await store.seedSyntheticWealth()
    try await SyntheticLedgerSeeder.seed(in: store)
    let goal = try Goal(
        id: deterministicGoalUUID(201),
        name: "Synthetic Feature Goal",
        target: cny("1000000"),
        targetDate: try CivilDate(canonical: "2035-08-30")
    )
    try await store.createGoal(goal)
    let asOf = try CivilDate(canonical: "2026-08-30")
    return (root, store, GoalsFeatureModel(store: store, asOfDate: asOf), goal)
}

@MainActor
private func configure(_ model: GoalsFeatureModel) {
    model.monthlyContributionCNY = cny("2000")
    model.expectedAnnualReturn = ratio("0.05")
    model.annualSpendingCNY = cny("120000")
    model.withdrawalRate = ratio("0.04")
    model.savingRateRange = try! SavingRateRange(
        start: try! CivilDate(canonical: "2025-01-01"),
        end: try! CivilDate(canonical: "2026-12-31")
    )
}

@MainActor
private func waitForGoalsTerminal(_ model: GoalsFeatureModel) async -> Bool {
    for _ in 0..<500 {
        if model.state != .calculating { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}
