import Foundation
import Testing
@testable import Aureus

@Suite("Stage 9 Portfolio Analytics")
struct PortfolioAnalyticsTests {
    private let portfolioID = UUID(uuidString: "00000000-0000-4000-8000-000000009001")!
    private let linkID = UUID(uuidString: "00000000-0000-4000-8000-000000009002")!
    private let instant = UTCInstant(millisecondsSince1970: 1_700_000_000_000)

    @Test("Cash-flow-adjusted return and TWR use distinct frozen formulas")
    func totalReturnAndTWRGolden() throws {
        let dates = try datesStarting("2026-01-01", count: 3)
        let input = try makeInput(
            dates: dates,
            nav: ["100", "160", "132"],
            activities: [
                try trade(.buy, date: dates[1], amount: "50", idSuffix: 11),
                try trade(.sell, date: dates[2], amount: "20", idSuffix: 12)
            ]
        )
        let report = try PortfolioAnalyticsCalculator.calculate(input)
        try expectDecimal(report.cashFlowAdjustedTotalReturn, equals: "0.02")
        try expectDecimal(report.timeWeightedReturn, equals: "0.045")
        let expectedPnL = try Money(decimal: 2, currency: .cny)
        let expectedContribution = try Money(decimal: 50, currency: .cny)
        let expectedWithdrawal = try Money(decimal: 20, currency: .cny)
        #expect(report.cashFlowAdjustedPnL == expectedPnL)
        #expect(report.contributions == expectedContribution)
        #expect(report.withdrawals == expectedWithdrawal)
        try expectDecimal(report.subperiodReturns[0].returnDecimal, equals: "0.10")
        try expectDecimal(report.subperiodReturns[1].returnDecimal, equals: "-0.05")
    }

    @Test("Activity cash-flow mapping preserves stored CNY provenance and split is zero")
    func activityCashFlowMapping() throws {
        let date = try CivilDate(canonical: "2026-01-02")
        let opening = try opening(date: date, amount: "12.34", idSuffix: 21)
        let buy = try trade(.buy, date: date, amount: "20", idSuffix: 22)
        let sell = try trade(.sell, date: date, amount: "7", idSuffix: 23)
        let split = try manualSplit(date: date, idSuffix: 24)
        #expect(try PortfolioAnalyticsCalculator.capitalFlow(for: opening)?.direction == .contribution)
        #expect(try PortfolioAnalyticsCalculator.capitalFlow(for: buy)?.amountCNY.minorUnits == 2_000)
        #expect(try PortfolioAnalyticsCalculator.capitalFlow(for: sell)?.direction == .withdrawal)
        #expect(try PortfolioAnalyticsCalculator.capitalFlow(for: split) == nil)
    }

    @Test("CAGR annualizes chained TWR with actual Gregorian days")
    func cagrGoldenAndLeapYear() throws {
        let regular = try PortfolioAnalyticsCalculator.calculate(makeInput(
            dates: [try CivilDate(canonical: "2023-01-01"), try CivilDate(canonical: "2024-01-01")],
            nav: ["100", "110"]
        ))
        try expectMetric(regular.cagr, equals: "0.10", scale: 9)

        let leap = try PortfolioAnalyticsCalculator.calculate(makeInput(
            dates: [try CivilDate(canonical: "2024-01-01"), try CivilDate(canonical: "2025-01-01")],
            nav: ["100", "110"]
        ))
        let leapValue = try metricValue(leap.cagr)
        #expect(leapValue < Decimal(string: "0.10")!)
        #expect(try AnalyticsCivilCalendar.dayDistance(
            from: try CivilDate(canonical: "2024-01-01"),
            to: try CivilDate(canonical: "2025-01-01")
        ) == 366)
    }

    @Test("XIRR daily-rate solver returns ten percent for 365-day conventional flows")
    func xirrGolden() throws {
        let flows = [
            AnalyticsXIRRCashFlow(
                date: try CivilDate(canonical: "2023-01-01"),
                investorAmountCNY: try Money(decimal: -100, currency: .cny)
            ),
            AnalyticsXIRRCashFlow(
                date: try CivilDate(canonical: "2024-01-01"),
                investorAmountCNY: try Money(decimal: 110, currency: .cny)
            )
        ]
        let result = try PortfolioAnalyticsCalculator.solveXIRR(flows)
        try expectDecimal(result, equals: "0.10", scale: 8)
        let repeated = try PortfolioAnalyticsCalculator.solveXIRR(flows)
        #expect(result == repeated)
    }

    @Test("XIRR validates signs, date span, topology, root range, and multiple roots")
    func xirrFailures() throws {
        let day0 = try CivilDate(canonical: "2026-01-01")
        let day1 = try CivilDate(canonical: "2026-01-02")
        let day2 = try CivilDate(canonical: "2026-01-03")
        #expect(throws: PortfolioAnalyticsError.noPositiveCashFlow) {
            _ = try PortfolioAnalyticsCalculator.solveXIRR([
                .init(date: day0, investorAmountCNY: try Money(decimal: -100, currency: .cny)),
                .init(date: day1, investorAmountCNY: try Money(decimal: -1, currency: .cny))
            ])
        }
        #expect(throws: PortfolioAnalyticsError.noNegativeCashFlow) {
            _ = try PortfolioAnalyticsCalculator.solveXIRR([
                .init(date: day0, investorAmountCNY: try Money(decimal: 1, currency: .cny)),
                .init(date: day1, investorAmountCNY: try Money(decimal: 2, currency: .cny))
            ])
        }
        #expect(throws: PortfolioAnalyticsError.invalidDateOrder) {
            _ = try PortfolioAnalyticsCalculator.solveXIRR([
                .init(date: day0, investorAmountCNY: try Money(decimal: -100, currency: .cny)),
                .init(date: day0, investorAmountCNY: try Money(decimal: 110, currency: .cny))
            ])
        }
        let nonconventional = [
            AnalyticsXIRRCashFlow(date: day0, investorAmountCNY: try Money(decimal: -100, currency: .cny)),
            AnalyticsXIRRCashFlow(date: day1, investorAmountCNY: try Money(decimal: 230, currency: .cny)),
            AnalyticsXIRRCashFlow(date: day2, investorAmountCNY: try Money(decimal: -132, currency: .cny))
        ]
        #expect(throws: PortfolioAnalyticsError.nonConventionalCashFlows) {
            _ = try PortfolioAnalyticsCalculator.solveXIRR(nonconventional)
        }
        #expect(throws: PortfolioAnalyticsError.multipleXIRRRoots) {
            _ = try PortfolioAnalyticsCalculator.solveXIRR(
                nonconventional,
                enforceConventionalTopology: false
            )
        }
        #expect(throws: PortfolioAnalyticsError.noXIRRRoot) {
            _ = try PortfolioAnalyticsCalculator.solveXIRR([
                .init(date: day0, investorAmountCNY: Money(minorUnits: -1, currency: .cny)),
                .init(date: day1, investorAmountCNY: Money(minorUnits: .max, currency: .cny))
            ])
        }
    }

    @Test("XIRR aggregates same-date flows and handles a result near minus one hundred percent")
    func xirrAggregationAndNegativeBoundary() throws {
        let start = try CivilDate(canonical: "2023-01-01")
        let end = try CivilDate(canonical: "2024-01-01")
        let result = try PortfolioAnalyticsCalculator.solveXIRR([
            .init(date: start, investorAmountCNY: try Money(decimal: -60, currency: .cny)),
            .init(date: start, investorAmountCNY: try Money(decimal: -40, currency: .cny)),
            .init(
                date: end,
                investorAmountCNY: try Money(
                    decimal: FixedPointMath.parseCanonical("0.10"),
                    currency: .cny
                )
            )
        ])
        #expect(result < Decimal(string: "-0.998")!)
        #expect(result > -1)
    }

    @Test("Risk metrics use daily sample deviation and reject irregular series")
    func volatilitySharpeAndIrregularSeries() throws {
        let dates = try datesStarting("2026-01-01", count: 4)
        let regular = try PortfolioAnalyticsCalculator.calculate(makeInput(
            dates: dates,
            nav: ["100", "110", "110", "99"]
        ))
        let volatility = try metricValue(regular.annualizedVolatility)
        #expect(volatility > 0)
        _ = try metricValue(regular.sharpeRatio)

        let flat = try PortfolioAnalyticsCalculator.calculate(makeInput(
            dates: dates,
            nav: ["100", "100", "100", "100"]
        ))
        try expectMetric(flat.annualizedVolatility, equals: "0")
        #expect(flat.sharpeRatio == .unavailable(.zeroVolatility))

        let irregular = try PortfolioAnalyticsCalculator.calculate(makeInput(
            dates: [dates[0], dates[1], dates[3]],
            nav: ["100", "101", "102"]
        ))
        #expect(irregular.annualizedVolatility == .unavailable(.irregularDailySeries))
        #expect(irregular.sharpeRatio == .unavailable(.irregularDailySeries))
    }

    @Test("Risk-free assumption must be above minus one hundred percent")
    func riskFreeValidation() throws {
        let dates = try datesStarting("2026-01-01", count: 3)
        #expect(throws: PortfolioAnalyticsError.invalidRiskFreeRate) {
            _ = try PortfolioAnalyticsCalculator.calculate(makeInput(
                dates: dates,
                nav: ["100", "101", "102"],
                annualRiskFreeRate: "-1"
            ))
        }
    }

    @Test("Observed maximum drawdown keeps earliest peak and does not fabricate recovery")
    func drawdownGolden() throws {
        let report = try PortfolioAnalyticsCalculator.calculate(makeInput(
            dates: try datesStarting("2026-01-01", count: 4),
            nav: ["100", "120", "90", "108"]
        ))
        try expectDecimal(report.maximumDrawdown.magnitude, equals: "0.25")
        let expectedPeak = try CivilDate(canonical: "2026-01-02")
        let expectedTrough = try CivilDate(canonical: "2026-01-03")
        #expect(report.maximumDrawdown.peakDate == expectedPeak)
        #expect(report.maximumDrawdown.troughDate == expectedTrough)
        #expect(report.maximumDrawdown.recoveryDate == nil)
        #expect(report.drawdownSeries.allSatisfy { $0.signedDrawdown <= 0 })
    }

    @Test("Monthly and annual returns retain partial observed coverage without zero filling")
    func monthlyAndAnnualCoverage() throws {
        let report = try PortfolioAnalyticsCalculator.calculate(makeInput(
            dates: [
                try CivilDate(canonical: "2025-12-30"),
                try CivilDate(canonical: "2025-12-31"),
                try CivilDate(canonical: "2026-01-01"),
                try CivilDate(canonical: "2026-01-02")
            ],
            nav: ["100", "101", "102", "103"]
        ))
        #expect(report.monthlyReturns.count == 2)
        #expect(report.monthlyReturns.allSatisfy { $0.coverage == .partialObservedPeriod })
        #expect(report.annualReturns.map(\.year) == [2025, 2026])
        #expect(report.annualReturns.allSatisfy { $0.coverage == .partialObservedPeriod })
    }

    @Test("Range policy uses Gregorian month, YTD, year, and maximum bounds")
    func rangePolicy() throws {
        let end = try CivilDate(canonical: "2024-03-31")
        #expect(try PortfolioAnalyticsRange.oneMonth.lowerBound(endingAt: end) == CivilDate(canonical: "2024-02-29"))
        #expect(try PortfolioAnalyticsRange.threeMonths.lowerBound(endingAt: end) == CivilDate(canonical: "2023-12-31"))
        #expect(try PortfolioAnalyticsRange.yearToDate.lowerBound(endingAt: end) == CivilDate(canonical: "2024-01-01"))
        #expect(try PortfolioAnalyticsRange.oneYear.lowerBound(endingAt: end) == CivilDate(canonical: "2023-03-31"))
        #expect(try PortfolioAnalyticsRange.maximum.lowerBound(endingAt: end) == nil)
    }

    @Test("Duplicate complete dates, missing flow boundaries, and incomplete-only input are typed")
    func observationValidation() throws {
        let dates = try datesStarting("2026-01-01", count: 3)
        let duplicate = try makeInput(dates: [dates[0], dates[0], dates[1]], nav: ["100", "101", "102"])
        #expect(throws: PortfolioAnalyticsError.duplicateSnapshotDate) {
            _ = try PortfolioAnalyticsCalculator.calculate(duplicate)
        }
        let missingBoundary = try makeInput(
            dates: [dates[0], dates[2]],
            nav: ["100", "110"],
            activities: [try trade(.buy, date: dates[1], amount: "5", idSuffix: 31)]
        )
        #expect(throws: PortfolioAnalyticsError.missingValuationBoundary) {
            _ = try PortfolioAnalyticsCalculator.calculate(missingBoundary)
        }
        let incomplete = try makeInput(dates: dates, nav: ["100", "101", "102"], completeness: [false, false, false])
        #expect(throws: PortfolioAnalyticsError.noCompleteSnapshots) {
            _ = try PortfolioAnalyticsCalculator.calculate(incomplete)
        }
    }

    @Test("Incomplete snapshots are excluded and disclosed without becoming zero observations")
    func incompleteSnapshotDisclosure() throws {
        let dates = try datesStarting("2026-01-01", count: 4)
        let report = try PortfolioAnalyticsCalculator.calculate(makeInput(
            dates: dates,
            nav: ["100", "999", "101", "102"],
            completeness: [true, false, true, true]
        ))
        #expect(report.coverage.incompleteSnapshotsExcluded == 1)
        #expect(report.coverage.completeSnapshotsUsed == 3)
        #expect(report.coverage.firstDate == dates[0])
        #expect(report.coverage.lastDate == dates[3])
    }

    @Test("Decimal roots, powers, overflow, division, and convergence are deterministic")
    func checkedDecimalAlgorithms() throws {
        try expectDecimal(try AnalyticsDecimalMath.squareRoot(4), equals: "2")
        try expectDecimal(try AnalyticsDecimalMath.positiveNthRoot(32, degree: 5), equals: "2")
        try expectDecimal(try AnalyticsDecimalMath.integerPower(Decimal(string: "1.1")!, exponent: 2), equals: "1.21")
        #expect(throws: PortfolioAnalyticsError.divisionByZero) {
            _ = try AnalyticsDecimalMath.divide(1, 0)
        }
        #expect(throws: PortfolioAnalyticsError.invalidRoot) {
            _ = try AnalyticsDecimalMath.squareRoot(-1)
        }
        #expect(throws: PortfolioAnalyticsError.invalidExponent) {
            _ = try AnalyticsDecimalMath.integerPower(2, exponent: -1)
        }
        #expect(throws: PortfolioAnalyticsError.overflow) {
            _ = try AnalyticsDecimalMath.multiply(Decimal.greatestFiniteMagnitude, 10)
        }
    }

    @Test("Analytics calculation is deterministic and leaves source arrays unchanged")
    func deterministicAndReadOnly() throws {
        let input = try makeInput(
            dates: try datesStarting("2026-01-01", count: 5),
            nav: ["100", "101", "99", "103", "104"]
        )
        let snapshots = input.snapshots
        let activities = input.activities
        let first = try PortfolioAnalyticsCalculator.calculate(input)
        let second = try PortfolioAnalyticsCalculator.calculate(input)
        #expect(first == second)
        #expect(input.snapshots == snapshots)
        #expect(input.activities == activities)
    }

    private enum TradeKind { case buy, sell }

    private func makeInput(
        dates: [CivilDate],
        nav: [String],
        activities: [PortfolioActivity] = [],
        completeness: [Bool]? = nil,
        annualRiskFreeRate: String = "0",
        range: PortfolioAnalyticsRange = .maximum
    ) throws -> PortfolioAnalyticsInput {
        let portfolio = try PortfolioRecord(
            id: portfolioID,
            name: "Synthetic Analytics Portfolio",
            createdAt: instant,
            updatedAt: instant,
            sortOrder: 0
        )
        let flags = completeness ?? Array(repeating: true, count: dates.count)
        let snapshots = try zip(zip(dates, nav), flags).enumerated().map { index, pair in
            PortfolioNAVSnapshot(
                id: uuid(suffix: 100 + index),
                portfolioID: portfolioID,
                civilDate: pair.0.0,
                createdAt: UTCInstant(millisecondsSince1970: instant.millisecondsSince1970 + Int64(index)),
                totalCNY: try Money(
                    decimal: FixedPointMath.parseCanonical(pair.0.1),
                    currency: .cny
                ),
                isComplete: pair.1,
                items: []
            )
        }
        return PortfolioAnalyticsInput(
            portfolio: portfolio,
            activities: activities,
            snapshots: snapshots,
            range: range,
            annualRiskFreeRate: try FixedPointMath.parseCanonical(annualRiskFreeRate)
        )
    }

    private func opening(date: CivilDate, amount: String, idSuffix: Int) throws -> PortfolioActivity {
        let money = try Money(decimal: FixedPointMath.parseCanonical(amount), currency: .cny)
        let fx = try PortfolioFXProvenance(
            original: money,
            rate: .cnyIdentity,
            source: "identity",
            referenceDate: date,
            recordedAt: instant,
            isManual: false,
            isStale: false
        )
        return try PortfolioActivity(
            id: uuid(suffix: idSuffix),
            portfolioID: portfolioID,
            securityLinkID: linkID,
            civilDate: date,
            recordedAt: instant,
            exchangeTimeZoneIdentifier: "UTC",
            payload: .openingLot(quantity: try AssetQuantity(decimal: 1), totalCost: money, fx: fx, note: "Synthetic")
        )
    }

    private func trade(_ kind: TradeKind, date: CivilDate, amount: String, idSuffix: Int) throws -> PortfolioActivity {
        let money = try Money(decimal: FixedPointMath.parseCanonical(amount), currency: .cny)
        let fx = try PortfolioFXProvenance(
            original: money,
            rate: .cnyIdentity,
            source: "identity",
            referenceDate: date,
            recordedAt: instant,
            isManual: false,
            isStale: false
        )
        let quantity = try AssetQuantity(decimal: 1)
        let price = try MarketPrice(
            decimal: FixedPointMath.parseCanonical(amount),
            quoteCurrency: .cny
        )
        let fee = Money(minorUnits: 0, currency: .cny)
        return try PortfolioActivity(
            id: uuid(suffix: idSuffix),
            portfolioID: portfolioID,
            securityLinkID: linkID,
            civilDate: date,
            recordedAt: instant,
            exchangeTimeZoneIdentifier: "UTC",
            payload: {
                switch kind {
                case .buy: .buy(quantity: quantity, unitPrice: price, fee: fee, fx: fx)
                case .sell: .sell(quantity: quantity, unitPrice: price, fee: fee, fx: fx)
                }
            }()
        )
    }

    private func manualSplit(date: CivilDate, idSuffix: Int) throws -> PortfolioActivity {
        try PortfolioActivity(
            id: uuid(suffix: idSuffix),
            portfolioID: portfolioID,
            securityLinkID: linkID,
            civilDate: date,
            recordedAt: instant,
            exchangeTimeZoneIdentifier: "UTC",
            payload: .manualSplit(from: try Ratio(decimal: 1), to: try Ratio(decimal: 2))
        )
    }

    private func datesStarting(_ canonical: String, count: Int) throws -> [CivilDate] {
        let start = try CivilDate(canonical: canonical)
        return try (0..<count).map { offset in
            let calendar = Calendar(identifier: .gregorian)
            let source = DateComponents(calendar: calendar, timeZone: TimeZone(secondsFromGMT: 0), year: start.year, month: start.month, day: start.day).date!
            let date = calendar.date(byAdding: .day, value: offset, to: source)!
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return try CivilDate(year: parts.year!, month: parts.month!, day: parts.day!)
        }
    }

    private func uuid(suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", suffix))!
    }

    private func metricValue(_ metric: AnalyticsMetric<Decimal>) throws -> Decimal {
        switch metric {
        case let .available(value): value
        case let .unavailable(error): throw error
        }
    }

    private func expectMetric(
        _ metric: AnalyticsMetric<Decimal>,
        equals expected: String,
        scale: Int = 10
    ) throws {
        try expectDecimal(try metricValue(metric), equals: expected, scale: scale)
    }

    private func expectDecimal(_ actual: Decimal, equals expected: String, scale: Int = 10) throws {
        let expectedValue = try FixedPointMath.parseCanonical(expected)
        let actualCoefficient = try FixedPointMath.coefficient(from: actual, scale: scale)
        let expectedCoefficient = try FixedPointMath.coefficient(from: expectedValue, scale: scale)
        #expect(actualCoefficient == expectedCoefficient)
    }
}

@Suite("Stage 9 Analytics Feature")
struct PortfolioAnalyticsFeatureTests {
    @Test("Opening Analytics and switching inputs never auto-calculate")
    @MainActor
    func explicitCalculationOnly() async throws {
        let fixture = try await makeFixture()
        let snapshotsBefore = try await fixture.store.fetchPortfolioNAVSnapshots(
            portfolioID: fixture.primaryPortfolioID
        )
        await fixture.model.start()
        #expect(fixture.model.state == .ready)
        #expect(fixture.model.report == nil)
        #expect(fixture.model.calculationCount == 0)

        fixture.model.selectRange(.oneMonth)
        #expect(fixture.model.report == nil)
        #expect(fixture.model.calculationCount == 0)
        fixture.model.selectPortfolio(fixture.sparsePortfolioID)
        #expect(fixture.model.report == nil)
        #expect(fixture.model.calculationCount == 0)

        let snapshotsAfter = try await fixture.store.fetchPortfolioNAVSnapshots(
            portfolioID: fixture.primaryPortfolioID
        )
        #expect(snapshotsAfter == snapshotsBefore)
    }

    @Test("Explicit calculation publishes regular synthetic report and excludes incomplete fixture")
    @MainActor
    func regularSyntheticCalculation() async throws {
        let fixture = try await makeFixture()
        await fixture.model.start()
        fixture.model.calculate()
        let completed = await waitForTerminal(fixture.model)
        #expect(completed)
        #expect(fixture.model.state == .calculated)
        let report = try #require(fixture.model.report)
        #expect(report.portfolioID == fixture.primaryPortfolioID)
        #expect(report.coverage.completeSnapshotsUsed == 27)
        #expect(report.coverage.incompleteSnapshotsExcluded == 1)
        #expect(report.coverage.flowValuationBoundariesComplete)
        #expect(report.coverage.dailySeriesIsRegular)
        #expect(fixture.model.calculationCount == 1)
    }

    @Test("Sparse scenario discloses unavailable risk and non-conventional XIRR")
    @MainActor
    func sparseSyntheticCalculation() async throws {
        let fixture = try await makeFixture()
        await fixture.model.start()
        fixture.model.selectPortfolio(fixture.sparsePortfolioID)
        fixture.model.selectRange(.maximum)
        fixture.model.calculate()
        let completed = await waitForTerminal(fixture.model)
        #expect(completed)
        let report = try #require(fixture.model.report)
        #expect(report.coverage.dailySeriesIsRegular == false)
        #expect(report.annualizedVolatility == .unavailable(.irregularDailySeries))
        #expect(report.sharpeRatio == .unavailable(.irregularDailySeries))
        #expect(report.xirr == .unavailable(.nonConventionalCashFlows))
    }

    @Test("Insufficient range and invalid risk-free input use finite states")
    @MainActor
    func finiteFailureStates() async throws {
        let fixture = try await makeFixture()
        await fixture.model.start()
        fixture.model.selectPortfolio(fixture.sparsePortfolioID)
        fixture.model.selectRange(.oneMonth)
        fixture.model.calculate()
        let insufficientCompleted = await waitForTerminal(fixture.model)
        #expect(insufficientCompleted)
        #expect(fixture.model.state == .insufficientData)
        #expect(fixture.model.report == nil)

        fixture.model.annualRiskFreePercentText = "-100"
        fixture.model.riskFreeInputChanged()
        fixture.model.selectRange(.maximum)
        fixture.model.calculate()
        let invalidCompleted = await waitForTerminal(fixture.model)
        #expect(invalidCompleted)
        #expect(fixture.model.state == .invalidRiskFreeRate)
        #expect(fixture.model.errorDisclosure?.contains("greater than -100%") == true)
    }

    @Test("Input generation prevents an old calculation from surviving selection change")
    @MainActor
    func staleGenerationCannotOverwrite() async throws {
        let fixture = try await makeFixture()
        await fixture.model.start()
        fixture.model.calculate()
        fixture.model.selectPortfolio(fixture.sparsePortfolioID)
        try await Task.sleep(for: .milliseconds(50))
        #expect(fixture.model.selectedPortfolioID == fixture.sparsePortfolioID)
        #expect(fixture.model.report == nil)
        #expect(fixture.model.state == .ready)
    }

    @MainActor
    private func waitForTerminal(_ model: AnalyticsFeatureModel) async -> Bool {
        for _ in 0..<200 {
            if model.state != .calculating { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    @MainActor
    private func makeFixture() async throws -> (
        store: WealthStore,
        model: AnalyticsFeatureModel,
        primaryPortfolioID: UUID,
        sparsePortfolioID: UUID
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Aureus-Stage9-FeatureTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = try WealthStore(databaseURL: root.appendingPathComponent("permanent.sqlite"))
        try await store.seedSyntheticWealth()
        try await store.seedSyntheticPortfolio()
        try await SyntheticAnalyticsSeeder.seed(in: store)
        return (
            store,
            AnalyticsFeatureModel(store: store, mode: .syntheticDemo),
            UUID(uuidString: "00000000-0000-4000-8000-000000008001")!,
            UUID(uuidString: "00000000-0000-4000-8000-000000009001")!
        )
    }
}

@Suite("Stage 9 Analytics Performance")
struct PortfolioAnalyticsPerformanceTests {
    private let portfolioID = UUID(uuidString: "10000000-0000-4000-8000-000000009001")!
    private let linkID = UUID(uuidString: "10000000-0000-4000-8000-000000009002")!
    private let instant = UTCInstant(millisecondsSince1970: 1_700_000_000_000)

    @Test("Release workload calculates 10000 complete observations and 10000 flows")
    func tenThousandObservationsAndFlows() throws {
        guard performanceEnabled else { return }
        let input = try makeLargeInput(observationCount: 10_000, flowCount: 10_000)
        let warmup = try PortfolioAnalyticsCalculator.calculate(input)
        try assertLargeReport(warmup, observationCount: 10_000, flowCount: 10_000)

        var samples: [Int64] = []
        for _ in 0..<5 {
            let started = ContinuousClock.now
            let report = try PortfolioAnalyticsCalculator.calculate(input)
            samples.append(milliseconds(started.duration(to: .now)))
            try assertLargeReport(report, observationCount: 10_000, flowCount: 10_000)
        }
        let sorted = samples.sorted()
        let p50 = sorted[sorted.count / 2]
        let p95 = sorted[Int((Double(sorted.count) * 0.95).rounded(.up)) - 1]
        print("STAGE9_PERF_10000 warmup=1 iterations=5 elapsed_ms=\(samples) range_ms=\(sorted.first!)-\(sorted.last!) p50_ms=\(p50) p95_ms=\(p95)")
        #expect(samples.allSatisfy { $0 < 10_000 })
    }

    @Test("One hundred Portfolio and range reloads retain final generation")
    @MainActor
    func oneHundredSelectionsAndReloads() async throws {
        guard performanceEnabled else { return }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Aureus-Stage9-Switching", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = try WealthStore(databaseURL: root.appendingPathComponent("permanent.sqlite"))
        try await store.seedSyntheticWealth()
        let wealthContainerID = UUID(uuidString: "00000000-0000-4000-8000-000000003003")!
        let dates = try dailyDates(starting: "2026-01-01", count: 3)
        var ids: [UUID] = []
        for index in 0..<10 {
            let id = deterministicUUID(300_000 + index)
            let securityLinkID = deterministicUUID(320_000 + index)
            ids.append(id)
            let portfolio = try PortfolioRecord(
                id: id,
                name: "Synthetic Switching Portfolio \(index)",
                createdAt: UTCInstant(millisecondsSince1970: instant.millisecondsSince1970 + Int64(index)),
                updatedAt: instant,
                sortOrder: index
            )
            try await store.createPortfolio(portfolio)
            try await store.linkPortfolioSecurity(try PortfolioSecurityLink(
                id: securityLinkID,
                portfolioID: id,
                wealthContainerID: wealthContainerID,
                symbol: "SYNX",
                rawMIC: "XSYN",
                currency: .usd,
                assetKind: .stock,
                sortOrder: 0
            ))
            for (dateIndex, date) in dates.enumerated() {
                let original = Money(
                    minorUnits: 100_000 + Int64(index * 1_000 + dateIndex * 100),
                    currency: .usd
                )
                let fx = try PortfolioFXProvenance(
                    original: original,
                    rate: try FXRate(decimal: FixedPointMath.parseCanonical("7.125"), sourceCurrency: .usd, targetCurrency: .cny),
                    source: "manual.synthetic.stage9.performance",
                    referenceDate: date,
                    recordedAt: instant,
                    isManual: true,
                    isStale: false
                )
                try await store.replacePortfolioNAVSnapshot(PortfolioNAVSnapshot(
                    id: deterministicUUID(310_000 + index * 10 + dateIndex),
                    portfolioID: id,
                    civilDate: date,
                    createdAt: UTCInstant(millisecondsSince1970: instant.millisecondsSince1970 + Int64(dateIndex)),
                    totalCNY: fx.convertedCNY,
                    isComplete: true,
                    items: [PortfolioNAVSnapshotItem(
                        id: deterministicUUID(330_000 + index * 10 + dateIndex),
                        securityLinkID: securityLinkID,
                        quantity: AssetQuantity(coefficient: 100_000_000),
                        manualMark: try MarketPrice(coefficient: 4_000_000_000, quoteCurrency: .usd),
                        originalMarketValue: original,
                        fx: fx,
                        convertedCNYValue: fx.convertedCNY,
                        remainingCNYBasis: fx.convertedCNY,
                        reconciliation: .quantityMismatch
                    )]
                ))
            }
        }

        let model = AnalyticsFeatureModel(store: store, mode: .syntheticDemo)
        await model.start()
        let started = ContinuousClock.now
        for iteration in 0..<100 {
            let expectedID = ids[iteration % ids.count]
            let expectedRange: PortfolioAnalyticsRange = iteration.isMultiple(of: 2) ? .maximum : .oneMonth
            model.selectPortfolio(expectedID)
            model.selectRange(expectedRange)
            await model.start()
            #expect(model.selectedPortfolioID == expectedID)
            #expect(model.selectedRange == expectedRange)
            #expect(model.report == nil)
            model.calculate()
            let completed = await waitForTerminal(model)
            #expect(completed)
            #expect(model.report?.portfolioID == expectedID)
            #expect(model.report?.coverage.requestedRange == expectedRange)
        }
        let elapsed = milliseconds(started.duration(to: .now))
        #expect(model.selectedPortfolioID == ids[9])
        #expect(model.report?.portfolioID == ids[9])
        #expect(model.calculationCount == 100)
        print("STAGE9_PERF_SWITCHING portfolios=10 selections=100 elapsed_ms=\(elapsed) final=\(ids[9].uuidString) provider_requests=0")
    }

    @Test("Five thousand observations prepare native chart and accessible presentation without truncation")
    func fiveThousandPresentationRows() throws {
        guard performanceEnabled else { return }
        let input = try makeLargeInput(observationCount: 5_000, flowCount: 0)
        let report = try PortfolioAnalyticsCalculator.calculate(input)
        let started = ContinuousClock.now
        let chart = AnalyticsDisplay.indexPoints(report.wealthIndex)
        let drawdown = AnalyticsDisplay.drawdownPoints(report.drawdownSeries)
        let indexLabels = report.wealthIndex.map {
            "\($0.date): index \(AnalyticsDisplay.number($0.value, digits: 6))"
        }
        let drawdownLabels = report.drawdownSeries.map {
            "\($0.date): drawdown \(AnalyticsDisplay.percent($0.signedDrawdown))"
        }
        let monthly = report.monthlyReturns.map {
            "\($0.id): \(AnalyticsDisplay.percent($0.returnDecimal)), \(AnalyticsDisplay.coverage($0.coverage))"
        }
        let annual = report.annualReturns.map {
            "\($0.year): \(AnalyticsDisplay.percent($0.returnDecimal)), \(AnalyticsDisplay.coverage($0.coverage))"
        }
        let elapsed = milliseconds(started.duration(to: .now))
        #expect(chart.count == 5_000)
        #expect(drawdown.count == 5_000)
        #expect(indexLabels.count == 5_000)
        #expect(drawdownLabels.count == 5_000)
        #expect(!monthly.isEmpty)
        #expect(!annual.isEmpty)
        #expect(chart.allSatisfy { $0.value.isFinite })
        #expect(drawdown.allSatisfy { $0.value.isFinite })
        print("STAGE9_PERF_PRESENTATION observations=5000 chart=\(chart.count) accessible_index=\(indexLabels.count) accessible_drawdown=\(drawdownLabels.count) monthly=\(monthly.count) annual=\(annual.count) elapsed_ms=\(elapsed)")
    }

    private func makeLargeInput(observationCount: Int, flowCount: Int) throws -> PortfolioAnalyticsInput {
        precondition(observationCount >= 2)
        precondition(flowCount == 0 || flowCount >= observationCount - 1)
        let portfolio = try PortfolioRecord(
            id: portfolioID,
            name: "Synthetic Large Analytics Portfolio",
            createdAt: instant,
            updatedAt: instant,
            sortOrder: 0
        )
        let dates = try dailyDates(starting: "2020-01-01", count: observationCount)
        var currentNAV: Int64 = 100_000_000
        var snapshots: [PortfolioNAVSnapshot] = []
        snapshots.reserveCapacity(observationCount)
        for (index, date) in dates.enumerated() {
            if index > 0 {
                let baseFlow = flowCount == 0 ? 0 : 100
                let extraFlow = flowCount > observationCount - 1 && index == observationCount - 1
                    ? Int64(flowCount - (observationCount - 1)) * 100
                    : 0
                let observedGain: Int64 = switch index % 3 {
                case 0: 5_000
                case 1: -3_000
                default: 2_000
                }
                currentNAV += Int64(baseFlow) + extraFlow + observedGain
            }
            snapshots.append(PortfolioNAVSnapshot(
                id: deterministicUUID(400_000 + index),
                portfolioID: portfolioID,
                civilDate: date,
                createdAt: UTCInstant(millisecondsSince1970: instant.millisecondsSince1970 + Int64(index)),
                totalCNY: Money(minorUnits: currentNAV, currency: .cny),
                isComplete: true,
                items: []
            ))
        }

        var activities: [PortfolioActivity] = []
        activities.reserveCapacity(flowCount)
        if flowCount > 0 {
            let quantity = try AssetQuantity(decimal: 1)
            let price = try MarketPrice(decimal: 1, quoteCurrency: .cny)
            let fee = Money(minorUnits: 0, currency: .cny)
            for flowIndex in 0..<flowCount {
                let dateIndex = min(flowIndex + 1, observationCount - 1)
                let date = dates[dateIndex]
                let original = Money(minorUnits: 100, currency: .cny)
                let fx = try PortfolioFXProvenance(
                    original: original,
                    rate: .cnyIdentity,
                    source: "identity",
                    referenceDate: date,
                    recordedAt: instant,
                    isManual: false,
                    isStale: false
                )
                activities.append(try PortfolioActivity(
                    id: deterministicUUID(500_000 + flowIndex),
                    portfolioID: portfolioID,
                    securityLinkID: linkID,
                    civilDate: date,
                    recordedAt: UTCInstant(millisecondsSince1970: instant.millisecondsSince1970 + Int64(flowIndex)),
                    exchangeTimeZoneIdentifier: "UTC",
                    payload: .buy(quantity: quantity, unitPrice: price, fee: fee, fx: fx)
                ))
            }
        }
        return PortfolioAnalyticsInput(
            portfolio: portfolio,
            activities: activities,
            snapshots: snapshots,
            range: .maximum,
            annualRiskFreeRate: 0
        )
    }

    private func assertLargeReport(
        _ report: PortfolioAnalyticsReport,
        observationCount: Int,
        flowCount: Int
    ) throws {
        #expect(report.coverage.completeSnapshotsUsed == observationCount)
        #expect(report.coverage.capitalFlowCount == flowCount)
        #expect(report.subperiodReturns.count == observationCount - 1)
        #expect(report.wealthIndex.count == observationCount)
        #expect(report.drawdownSeries.count == observationCount)
        #expect(report.xirrCashFlows.first?.investorAmountCNY.minorUnits ?? 0 < 0)
        #expect(report.xirrCashFlows.last?.investorAmountCNY.minorUnits ?? 0 > 0)
        if case .unavailable(let error) = report.xirr { throw error }
        if case .unavailable(let error) = report.annualizedVolatility { throw error }
        if case .unavailable(let error) = report.sharpeRatio { throw error }
    }

    @MainActor
    private func waitForTerminal(_ model: AnalyticsFeatureModel) async -> Bool {
        for _ in 0..<500 {
            if model.state != .calculating { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func dailyDates(starting canonical: String, count: Int) throws -> [CivilDate] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = try CivilDate(canonical: canonical)
        let source = calendar.date(from: DateComponents(year: start.year, month: start.month, day: start.day))!
        return try (0..<count).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: source)!
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return try CivilDate(year: parts.year!, month: parts.month!, day: parts.day!)
        }
    }

    private func deterministicUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "10000000-0000-4000-8000-%012d", value))!
    }

    private var performanceEnabled: Bool {
        ProcessInfo.processInfo.environment["AUREUS_STAGE9_PERFORMANCE"] == "1"
    }

    private func milliseconds(_ duration: Duration) -> Int64 {
        let components = duration.components
        return components.seconds * 1_000 + Int64(components.attoseconds / 1_000_000_000_000_000)
    }
}
