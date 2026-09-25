import Foundation
import GRDB
import Testing
@testable import Aureus

@Suite("Stage 8 Portfolio Terminal")
struct PortfolioTerminalTests {
    private let date = try! CivilDate(canonical: "2026-01-15")
    private let instant = UTCInstant(millisecondsSince1970: 1_768_435_200_000)

    @Test("Single Buy creates an independent FIFO lot with fee")
    func singleBuy() throws {
        let context = try Context()
        let buy = try context.trade(.buy, quantity: "10", price: "12", fee: "1")
        let result = try PortfolioFIFOEngine.replay([buy])
        let expectedQuantity = try AssetQuantity(decimal: 10)
        let expectedBasis = try Money(decimal: 121, currency: .cny)
        #expect(result.lots.count == 1)
        #expect(result.lots[0].remainingQuantity == expectedQuantity)
        #expect(result.lots[0].remainingOriginalBasis == expectedBasis)
        #expect(result.realized.isEmpty)
    }

    @Test("Multiple FIFO lots and partial Sell preserve basis residual")
    func fifoPartialAndMultipleLots() throws {
        let context = try Context()
        let first = try context.trade(.buy, quantity: "10", price: "10", fee: "1", milliseconds: 0)
        let second = try context.trade(.buy, quantity: "10", price: "20", fee: "2", milliseconds: 1)
        let sell = try context.trade(.sell, quantity: "15", price: "30", fee: "3", milliseconds: 2)
        let result = try PortfolioFIFOEngine.replay([second, sell, first])
        let expectedQuantity = try AssetQuantity(decimal: 5)
        #expect(result.lots[0].remainingQuantity.coefficient == 0)
        #expect(result.lots[0].remainingOriginalBasis.minorUnits == 0)
        #expect(result.lots[1].remainingQuantity == expectedQuantity)
        #expect(result.lots[1].remainingOriginalBasis.minorUnits == 10_100)
        #expect(result.realized[0].disposedOriginalBasis.minorUnits == 20_200)
        #expect(result.realized[0].originalPnL.minorUnits == 24_500)
    }

    @Test("Opening Lot and Manual Split adjust quantity without P and L")
    func openingLotAndSplit() throws {
        let context = try Context()
        let opening = try context.opening(quantity: "3", cost: "90")
        let split = try PortfolioActivity(
            id: UUID(), portfolioID: context.portfolioID, securityLinkID: context.linkID,
            civilDate: date, recordedAt: UTCInstant(millisecondsSince1970: instant.millisecondsSince1970 + 1),
            exchangeTimeZoneIdentifier: "UTC",
            payload: .manualSplit(from: try Ratio(decimal: 1), to: try Ratio(decimal: 2))
        )
        let result = try PortfolioFIFOEngine.replay([opening, split])
        let expectedQuantity = try AssetQuantity(decimal: 6)
        let expectedBasis = try Money(decimal: 90, currency: .cny)
        #expect(result.lots[0].remainingQuantity == expectedQuantity)
        #expect(result.lots[0].remainingOriginalBasis == expectedBasis)
        #expect(result.realized.isEmpty)
    }

    @Test("Oversell and invalid values are rejected")
    func validationAndOversell() throws {
        let context = try Context()
        let buy = try context.trade(.buy, quantity: "1", price: "10", fee: "0")
        let sell = try context.trade(.sell, quantity: "2", price: "10", fee: "0", milliseconds: 1)
        #expect(throws: PortfolioDomainError.oversell) { try PortfolioFIFOEngine.replay([buy, sell]) }
        #expect(throws: PortfolioDomainError.nonPositiveQuantity) {
            _ = try context.trade(.buy, quantity: "0", price: "10", fee: "0")
        }
    }

    @Test("Same-day ordering uses recorded instant then UUID")
    func stableOrder() throws {
        let context = try Context()
        let buy = try context.trade(.buy, quantity: "1", price: "10", fee: "0", milliseconds: 0)
        let sell = try context.trade(.sell, quantity: "1", price: "12", fee: "0", milliseconds: 1)
        #expect(try PortfolioFIFOEngine.replay([sell, buy]).realized.count == 1)
    }

    @Test("CNY identity and USD manual FX preserve acquisition and sale provenance")
    func fxProvenance() throws {
        let cny = try PortfolioFXProvenance(
            original: Money(minorUnits: 100, currency: .cny), rate: .cnyIdentity,
            source: "identity", referenceDate: date, recordedAt: instant,
            isManual: false, isStale: false
        )
        #expect(cny.convertedCNY.minorUnits == 100)
        let rate = try FXRate(decimal: Decimal(string: "7.25")!, sourceCurrency: .usd, targetCurrency: .cny)
        let usd = try PortfolioFXProvenance(
            original: Money(minorUnits: 10_00, currency: .usd), rate: rate,
            source: "manual.synthetic", referenceDate: date, recordedAt: instant,
            isManual: true, isStale: true
        )
        #expect(usd.convertedCNY.minorUnits == 7_250)
        #expect(usd.isStale)
    }

    @Test("Checked arithmetic rejects division by zero and overflowing Money")
    func checkedArithmetic() throws {
        #expect(throws: PortfolioDomainError.divisionByZero) { try PortfolioCheckedMath.divide(1, 0) }
        #expect(throws: FinancialValueError.overflow) {
            _ = try Money(minorUnits: .max, currency: .cny).adding(Money(minorUnits: 1, currency: .cny))
        }
    }

    @Test("Fresh and v1 through v8 databases migrate to active v9 without REAL authority")
    func migrationForward() async throws {
        for (index, start) in [nil, DatabaseMigrations.permanentV1, DatabaseMigrations.permanentV2,
                               DatabaseMigrations.permanentV3, DatabaseMigrations.permanentV4,
                               DatabaseMigrations.permanentV5, DatabaseMigrations.permanentV6, DatabaseMigrations.permanentV7,
                               DatabaseMigrations.permanentV8].enumerated() {
            let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
            let url = root.appendingPathComponent("portfolio-\(start ?? "fresh").sqlite")
            if let start {
                let queue = try DatabaseQueueFactory.open(at: url)
                try DatabaseMigrations.permanentMigrator().migrate(queue, upTo: start)
            }
            let paths = RuntimePaths.temporary(root: root)
            let store = try WealthStore(
                databaseURL: url,
                migrationSafetyConfiguration: PermanentMigrationSafetyConfiguration(
                    backupRoot: paths.internalBackupDirectoryURL,
                    appVersion: "portfolio-migration-test",
                    createdAt: { UTCInstant(millisecondsSince1970: 1_768_435_200_000) },
                    generationID: {
                        UUID(uuidString: String(
                            format: "00000000-0000-4000-8000-%012d",
                            index + 1
                        ))!
                    }
                )
            )
            #expect(try await store.schemaVersion() == 9)
            let queue = try DatabaseQueueFactory.open(at: url)
            let realColumns = try await queue.read { db in
                try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM pragma_table_info('portfolio_activities')
                    WHERE lower(type) = 'real'
                    """) ?? 0
            }
            #expect(realColumns == 0)
        }
    }

    @Test("CRUD, reopen, edit/delete rollback, and Wealth delete isolation")
    func persistenceLifecycle() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("aureus.sqlite")
        let store = try WealthStore(databaseURL: url)
        let wealth = try SyntheticWealthSeeder.records()[2]
        try await store.createWealthContainer(wealth)
        let context = try Context()
        let portfolio = try PortfolioRecord(id: context.portfolioID, name: "Synthetic Test", createdAt: instant, updatedAt: instant, sortOrder: 0)
        try await store.createPortfolio(portfolio)
        let link = try PortfolioSecurityLink(id: context.linkID, portfolioID: context.portfolioID, wealthContainerID: wealth.id, symbol: "SYNX", rawMIC: "XSYN", currency: .usd, assetKind: .stock, sortOrder: 0)
        try await store.linkPortfolioSecurity(link)
        let usdContext = try Context(portfolioID: context.portfolioID, linkID: context.linkID, currency: .usd)
        let buy = try usdContext.trade(.buy, quantity: "2", price: "10", fee: "0")
        let sell = try usdContext.trade(.sell, quantity: "1", price: "12", fee: "0", milliseconds: 1)
        try await store.createPortfolioActivity(buy)
        try await store.createPortfolioActivity(sell)
        await #expect(throws: PortfolioPersistenceError.invalidHistoricalMutation) {
            try await store.deletePortfolioActivity(id: buy.id)
        }
        #expect(try await store.fetchPortfolioActivities(portfolioID: context.portfolioID).count == 2)
        let impact = try await store.deletionImpact(for: wealth.id)
        #expect(impact.linkedPortfolioSecurityCount == 1)
        await #expect(throws: WealthPersistenceError.protectedPermanentDependents) {
            _ = try await store.deleteWealthContainer(id: wealth.id)
        }
        let reopened = try WealthStore(databaseURL: url)
        #expect(try await reopened.fetchPortfolios() == [portfolio])
        try await reopened.deletePortfolio(id: portfolio.id)
        #expect(try await reopened.fetchWealthContainer(id: wealth.id) != nil)
    }

    @Test("Confirmed delete survives alert presentation dismissal")
    @MainActor
    func confirmedDeleteSurvivesPresentationDismissal() async throws {
        let fixture = try await makeDeleteLifecycleFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sentinelsBefore = try await fixture.store.isolationSentinels()

        fixture.model.requestDeleteSelected()
        let capturedID = try #require(fixture.model.pendingPortfolioDeletion?.id)
        #expect(capturedID == fixture.first.id)
        fixture.model.cancelDelete()
        #expect(fixture.model.pendingPortfolioDeletion == nil)

        await fixture.model.confirmDelete(id: capturedID)

        #expect(try await fixture.store.fetchPortfolios() == [fixture.second])
        #expect(fixture.model.portfolios == [fixture.second])
        #expect(fixture.model.selectedPortfolioID == fixture.second.id)
        #expect(try await fixture.store.isolationSentinels() == sentinelsBefore)
        let requests = await fixture.provider.requestCounts()
        #expect(requests.search == 0 && requests.history == 0)
    }

    @Test("Cancelled delete issues no Store mutation")
    @MainActor
    func cancelledDeleteDoesNotMutateStore() async throws {
        let fixture = try await makeDeleteLifecycleFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sentinelsBefore = try await fixture.store.isolationSentinels()

        fixture.model.requestDeleteSelected()
        #expect(fixture.model.pendingPortfolioDeletion?.id == fixture.first.id)
        fixture.model.cancelDelete()

        #expect(fixture.model.pendingPortfolioDeletion == nil)
        #expect(try await fixture.store.fetchPortfolios() == [fixture.first, fixture.second])
        #expect(try await fixture.store.isolationSentinels() == sentinelsBefore)
        let requests = await fixture.provider.requestCounts()
        #expect(requests.search == 0 && requests.history == 0)
    }

    @Test("Captured delete identity remains authoritative after selection changes")
    @MainActor
    func capturedDeleteIdentitySurvivesSelectionChange() async throws {
        let fixture = try await makeDeleteLifecycleFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sentinelsBefore = try await fixture.store.isolationSentinels()

        fixture.model.requestDeleteSelected()
        let capturedID = try #require(fixture.model.pendingPortfolioDeletion?.id)
        await fixture.model.select(fixture.second.id)
        #expect(fixture.model.selectedPortfolioID == fixture.second.id)

        await fixture.model.confirmDelete(id: capturedID)

        #expect(try await fixture.store.fetchPortfolios() == [fixture.second])
        #expect(fixture.model.selectedPortfolioID == fixture.second.id)
        #expect(try await fixture.store.isolationSentinels() == sentinelsBefore)
        let requests = await fixture.provider.requestCounts()
        #expect(requests.search == 0 && requests.history == 0)
    }

    @Test("Delete failure is finite and preserves every Portfolio")
    @MainActor
    func deleteFailureIsIsolated() async throws {
        let fixture = try await makeDeleteLifecycleFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sentinelsBefore = try await fixture.store.isolationSentinels()
        let faultQueue = try DatabaseQueueFactory.open(at: fixture.databaseURL)
        try await faultQueue.write { db in
            try db.execute(sql: """
                CREATE TRIGGER synthetic_reject_portfolio_delete
                BEFORE DELETE ON portfolio_definitions
                BEGIN
                    SELECT RAISE(ABORT, 'synthetic delete rejection');
                END
                """)
        }

        fixture.model.requestDeleteSelected()
        let capturedID = try #require(fixture.model.pendingPortfolioDeletion?.id)
        await fixture.model.confirmDelete(id: capturedID)

        try await faultQueue.write { db in
            try db.execute(sql: "DROP TRIGGER synthetic_reject_portfolio_delete")
        }
        #expect(try await fixture.store.fetchPortfolios() == [fixture.first, fixture.second])
        #expect(fixture.model.portfolios == [fixture.first, fixture.second])
        #expect(fixture.model.selectedPortfolioID == fixture.first.id)
        #expect(fixture.model.pendingPortfolioDeletion == nil)
        #expect(fixture.model.errorMessage == "Portfolio delete failed. Wealth, Ledger, and Snapshots were not altered.")
        #expect(try await fixture.store.isolationSentinels() == sentinelsBefore)
        let requests = await fixture.provider.requestCounts()
        #expect(requests.search == 0 && requests.history == 0)
    }

    @Test("Same-date complete NAV snapshot is atomically replaced")
    func snapshotReplacement() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("aureus.sqlite"))
        let context = try Context()
        let portfolio = try PortfolioRecord(id: context.portfolioID, name: "Synthetic", createdAt: instant, updatedAt: instant, sortOrder: 0)
        try await store.createPortfolio(portfolio)
        let first = PortfolioNAVSnapshot(id: UUID(), portfolioID: portfolio.id, civilDate: date, createdAt: instant,
            totalCNY: Money(minorUnits: 0, currency: .cny), isComplete: true, items: [])
        try await store.replacePortfolioNAVSnapshot(first)
        let second = PortfolioNAVSnapshot(id: UUID(), portfolioID: portfolio.id, civilDate: date,
            createdAt: UTCInstant(millisecondsSince1970: instant.millisecondsSince1970 + 1),
            totalCNY: Money(minorUnits: 0, currency: .cny), isComplete: true, items: [])
        try await store.replacePortfolioNAVSnapshot(second)
        let values = try await store.fetchPortfolioNAVSnapshots(portfolioID: portfolio.id)
        #expect(values.count == 1)
        #expect(values[0].id == second.id)
    }

    @Test("Identifier-only benchmark preference serializes no Provider value")
    func preferences() async throws {
        let store = PortfolioPreferencesStore(suiteName: nil, memoryOnly: true)
        let id = UUID()
        let value = try PortfolioBenchmarkPreference(symbol: " aapl ", rawMIC: " xngs ", range: .oneYear)
        try await store.save(value, for: id)
        #expect(try await store.preference(for: id) == value)
        let encoded = String(data: try JSONEncoder().encode(value), encoding: .utf8)!
        #expect(!encoded.contains("close"))
        #expect(!encoded.contains("freshness"))
        #expect(!encoded.contains("description"))
    }

    @Test("Benchmark uses exact overlap and base 100")
    func benchmark() throws {
        let context = try Context()
        let dates = [try CivilDate(canonical: "2026-01-01"), try CivilDate(canonical: "2026-01-02")]
        let snapshots = dates.enumerated().map { index, date in
            PortfolioNAVSnapshot(id: UUID(), portfolioID: context.portfolioID, civilDate: date, createdAt: instant,
                totalCNY: Money(minorUnits: Int64(10_000 + index * 1_000), currency: .cny), isComplete: true, items: [])
        }
        let instrument = MarketInstrument(id: UUID(), symbol: "SYNB", mic: "XSYN", currency: .cny, displayName: "Synthetic")
        let bars = try dates.enumerated().map { index, date in
            try MarketOHLCVBar(sessionDate: date, openedAt: instant,
                open: .init(decimal: Decimal(100 + index * 20), quoteCurrency: .cny),
                high: .init(decimal: Decimal(100 + index * 20), quoteCurrency: .cny),
                low: .init(decimal: Decimal(100 + index * 20), quoteCurrency: .cny),
                close: .init(decimal: Decimal(100 + index * 20), quoteCurrency: .cny),
                volume: nil, adjustment: .all, providerIdentifier: "synthetic", fetchedAt: instant, freshness: .unknown)
        }
        _ = instrument
        let result = try PortfolioBenchmarkComparison.indexed100(snapshots: snapshots, benchmark: bars)
        #expect(result.count == 2)
        #expect(result[0].portfolioIndex == 100)
        #expect(result[1].benchmarkIndex == 120)
    }

    @Test("Ten thousand activities replay deterministically")
    func performanceReplay() throws {
        let context = try Context()
        let activities = try (0..<10_000).map { index in
            try context.trade(.buy, quantity: "1", price: "1", fee: "0", milliseconds: Int64(index))
        }
        let start = ContinuousClock.now
        let first = try PortfolioFIFOEngine.replay(activities)
        let elapsed = start.duration(to: .now)
        let second = try PortfolioFIFOEngine.replay(activities)
        #expect(first == second)
        #expect(first.lots.count == 10_000)
        #expect(elapsed < .seconds(10))
    }

    @Test("Provider policy remains stable while Benchmark disclosure changes independently")
    @MainActor
    func disclosureSemantics() async throws {
        let successful = try await makeFeatureModel(scenario: .success, withBenchmarkSnapshots: true)
        defer { try? FileManager.default.removeItem(at: successful.root) }
        await successful.model.start()
        let policy = successful.model.providerPolicyDisclosure
        #expect(policy.contains("No Provider request"))
        #expect(successful.model.benchmarkDisclosure == PortfolioFeatureModel.benchmarkNotLoadedDisclosure)
        await successful.model.saveBenchmark(symbol: "SYN-CNY", rawMIC: "XSYN", range: .maximum)
        successful.model.loadSessionBenchmark()
        try await waitForBenchmarkTerminal(successful.model)
        #expect(successful.model.state == .benchmarkReady)
        #expect(successful.model.benchmarkDisclosure.contains("Indexed comparison"))
        #expect(successful.model.providerPolicyDisclosure == policy)
        await successful.model.clearSessionBenchmark()
        #expect(successful.model.benchmarkDisclosure == PortfolioFeatureModel.benchmarkNotLoadedDisclosure)
        #expect(successful.model.providerPolicyDisclosure == policy)

        for scenario in [SyntheticProviderScenario.unsupported, .offline] {
            let candidate = try await makeFeatureModel(scenario: scenario, withBenchmarkSnapshots: false)
            defer { try? FileManager.default.removeItem(at: candidate.root) }
            await candidate.model.start()
            await candidate.model.saveBenchmark(symbol: "SYN-CNY", rawMIC: "XSYN", range: .maximum)
            candidate.model.loadSessionBenchmark()
            try await waitForBenchmarkTerminal(candidate.model)
            #expect(candidate.model.providerPolicyDisclosure == policy)
            if scenario == .unsupported {
                #expect(candidate.model.state == .benchmarkDenied)
                #expect(candidate.model.benchmarkDisclosure == "Benchmark requires current entitlement.")
            } else {
                #expect(candidate.model.state == .benchmarkOffline)
                #expect(candidate.model.benchmarkDisclosure == "Benchmark unavailable offline.")
                #expect(candidate.model.benchmarkComparison.isEmpty)
            }
            #expect(candidate.model.providerPolicyDisclosure == policy)
        }
    }

    @Test("Typed Benchmark failures preserve finite disclosure and Provider policy",
          arguments: [ProviderBoundaryError.missing, .offline, .timeout])
    @MainActor
    func benchmarkFailureMapping(error: ProviderBoundaryError) async throws {
        let fixture = try await makeFeatureModel(scenario: .success, withBenchmarkSnapshots: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let policy = fixture.model.providerPolicyDisclosure
        #expect(fixture.model.benchmarkComparison.isEmpty)

        fixture.model.applyBenchmarkFailure(error)

        switch error {
        case .missing:
            #expect(fixture.model.state == .benchmarkMissing)
            #expect(fixture.model.benchmarkDisclosure == "Benchmark session data not loaded.")
        case .offline:
            #expect(fixture.model.state == .benchmarkOffline)
            #expect(fixture.model.benchmarkDisclosure == "Benchmark unavailable offline.")
        case .timeout:
            #expect(fixture.model.state == .benchmarkTimeout)
            #expect(fixture.model.benchmarkDisclosure == "Benchmark request timed out. Session data was not loaded.")
        default:
            Issue.record("Unexpected Benchmark mapping test argument")
        }
        #expect(fixture.model.providerPolicyDisclosure == policy)
        #expect(fixture.model.benchmarkComparison.isEmpty)
    }

    @Test("One grouped summary pass preserves 100 holding semantics and deterministic order")
    func groupedHoldingSummaries() async throws {
        let fixture = try await makeHundredHoldingFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let warmup = try await fixture.store.portfolioHoldingSummaries(portfolioID: fixture.portfolioID)
        #expect(warmup.count == 100)
        #expect(warmup.map(\.link.sortOrder) == Array(0..<100))
        #expect(warmup.filter { $0.reconciliation == .matched }.count == 50)
        #expect(warmup.filter { $0.reconciliation == .quantityMismatch }.count == 50)
        #expect(warmup.contains { $0.link.currency == .cny })
        #expect(warmup.contains { $0.link.currency == .usd })
        #expect(warmup.allSatisfy { $0.realizedCNYPnL.minorUnits != 0 })

        var samples: [Double] = []
        for _ in 0..<7 {
            let started = ContinuousClock.now
            let values = try await fixture.store.portfolioHoldingSummaries(portfolioID: fixture.portfolioID)
            samples.append(milliseconds(started.duration(to: .now)))
            #expect(values == warmup)
            #expect(try checkedNAV(values).minorUnits > 0)
            #expect(try allocationInputs(values).assetKindTotal == checkedNAV(values))
            #expect(try allocationInputs(values).currencyTotal == checkedNAV(values))
            #expect(heatmapInputs(values).count == 100)
        }
        let reopened = try WealthStore(databaseURL: fixture.databaseURL)
        #expect(try await reopened.portfolioHoldingSummaries(portfolioID: fixture.portfolioID) == warmup)
        printPerformance("100-holdings-summary-allocation-heatmap", samples: samples, warmups: 1)
    }

    @Test("Stage 8A full-size synthetic performance workloads")
    func stage8APerformanceWorkloads() throws {
        let context = try Context()
        let history = try (0..<10_000).map { index in
            try context.trade(.buy, quantity: "1", price: "1", fee: "0", milliseconds: Int64(index))
        }
        _ = try PortfolioFIFOEngine.replay(history)
        var replaySamples: [Double] = []
        for _ in 0..<5 {
            let started = ContinuousClock.now
            let result = try PortfolioFIFOEngine.replay(history)
            replaySamples.append(milliseconds(started.duration(to: .now)))
            #expect(result.lots.count == 10_000)
        }
        printPerformance("10000-replay", samples: replaySamples, warmups: 1)
        #expect(replaySamples.allSatisfy { $0 < 10_000 })

        let appendedBuy = try context.trade(.buy, quantity: "2", price: "2", fee: "1", milliseconds: 10_001)
        let buyStart = ContinuousClock.now
        let buyResult = try PortfolioFIFOEngine.replay(history + [appendedBuy])
        let buyElapsed = milliseconds(buyStart.duration(to: .now))
        #expect(buyResult.lots.count == 10_001)
        #expect(try buyResult.quantity(for: context.linkID).decimal == Decimal(10_002))
        printPerformance("10000-plus-buy-full-replay", samples: [buyElapsed], warmups: 0)

        let appendedSell = try context.trade(.sell, quantity: "1", price: "3", fee: "1", milliseconds: 10_001)
        let sellStart = ContinuousClock.now
        let sellResult = try PortfolioFIFOEngine.replay(history + [appendedSell])
        let sellElapsed = milliseconds(sellStart.duration(to: .now))
        #expect(sellResult.realized.count == 1)
        #expect(try sellResult.quantity(for: context.linkID).decimal == Decimal(9_999))
        #expect(sellResult.realized[0].originalPnL.minorUnits == 100)
        printPerformance("10000-plus-sell-full-replay", samples: [sellElapsed], warmups: 0)

        let snapshots = try makeFiveThousandSnapshots(portfolioID: context.portfolioID)
        let benchmark = try makeBenchmarkBars(for: snapshots.map(\.civilDate))
        let snapshotStart = ContinuousClock.now
        let sorted = snapshots.sorted { $0.civilDate < $1.civilDate }
        let chartValues = sorted.map { NSDecimalNumber(decimal: $0.totalCNY.decimal).doubleValue }
        let accessibleRows = sorted.map { "\($0.civilDate.description)|CNY \($0.totalCNY.minorUnits)|Complete" }
        let comparison = try PortfolioBenchmarkComparison.indexed100(snapshots: sorted, benchmark: benchmark)
        let snapshotElapsed = milliseconds(snapshotStart.duration(to: .now))
        #expect(sorted.count == 5_000)
        #expect(chartValues.count == 5_000 && chartValues.allSatisfy(\.isFinite))
        #expect(accessibleRows.count == 5_000)
        #expect(comparison.count == 5_000)
        printPerformance("5000-snapshot-chart-table-overlap", samples: [snapshotElapsed], warmups: 0)
    }

    @Test("One hundred Portfolio selections remain isolated and make no Provider request")
    @MainActor
    func repeatedPortfolioSwitching() async throws {
        let fixture = try await makeSwitchingFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await fixture.model.start()
        let started = ContinuousClock.now
        for index in 0..<100 {
            await fixture.model.select(fixture.portfolioIDs[index % fixture.portfolioIDs.count])
        }
        let elapsed = milliseconds(started.duration(to: .now))
        #expect(fixture.model.selectedPortfolioID == fixture.portfolioIDs[9])
        #expect(fixture.model.holdings.count == 1)
        #expect(fixture.model.snapshots.count == 1)
        #expect(fixture.model.providerPolicyDisclosure == PortfolioFeatureModel.stableProviderPolicyDisclosure)
        let requests = await fixture.provider.requestCounts()
        #expect(requests.search == 0 && requests.history == 0)
        printPerformance("10-portfolios-100-selection-reloads", samples: [elapsed], warmups: 0)
    }

    @MainActor
    private func makeFeatureModel(
        scenario: SyntheticProviderScenario,
        withBenchmarkSnapshots: Bool
    ) async throws -> (model: PortfolioFeatureModel, root: URL) {
        let root = try temporaryDirectory()
        let databaseURL = root.appendingPathComponent("permanent.sqlite")
        let store = try WealthStore(databaseURL: databaseURL)
        let portfolio = try PortfolioRecord(name: "Synthetic Disclosure", createdAt: instant, updatedAt: instant, sortOrder: 0)
        try await store.createPortfolio(portfolio)
        let wealth = try makeSecurityWealth(index: 0, currency: .cny, wealthQuantity: 10)
        try await store.createWealthContainer(wealth)
        let link = try PortfolioSecurityLink(
            portfolioID: portfolio.id, wealthContainerID: wealth.id, symbol: "S000", rawMIC: "XSYN",
            currency: .cny, assetKind: .stock, sortOrder: 0
        )
        try await store.linkPortfolioSecurity(link)
        let context = try Context(portfolioID: portfolio.id, linkID: link.id, currency: .cny)
        try await store.createPortfolioActivity(context.opening(quantity: "10", cost: "100"))
        if withBenchmarkSnapshots {
            let holding = try await store.portfolioHoldingSummaries(portfolioID: portfolio.id)[0]
            for value in ["2025-11-27", "2025-11-28"] {
                let item = PortfolioNAVSnapshotItem(
                    id: UUID(), securityLinkID: link.id, quantity: holding.portfolioQuantity,
                    manualMark: holding.manualMark, originalMarketValue: holding.marketValue,
                    fx: holding.wealthFX, convertedCNYValue: holding.marketValueCNY,
                    remainingCNYBasis: holding.remainingCNYBasis, reconciliation: holding.reconciliation
                )
                try await store.replacePortfolioNAVSnapshot(PortfolioNAVSnapshot(
                    id: UUID(), portfolioID: portfolio.id, civilDate: try CivilDate(canonical: value),
                    createdAt: instant, totalCNY: holding.marketValueCNY, isComplete: true, items: [item]
                ))
            }
        }
        let fixed = FixedClock(instant: try utcInstant("2025-11-28"))
        let session = TransientMarketSessionStore()
        let cache = try MarketCacheStore(databaseURL: root.appendingPathComponent("market.sqlite"))
        let service = MarketDataService(
            marketProvider: SyntheticMarketDataProvider(scenario: scenario, clock: fixed),
            fxProvider: SyntheticFXRateProvider(clock: fixed), cache: cache, sessionStore: session, clock: fixed
        )
        return (PortfolioFeatureModel(
            store: store, marketDataService: service, marketSessionStore: session,
            preferences: PortfolioPreferencesStore(suiteName: nil, memoryOnly: true),
            clock: fixed, mode: .syntheticDemo
        ), root)
    }

    @MainActor
    private func makeDeleteLifecycleFixture() async throws -> (
        root: URL,
        databaseURL: URL,
        store: WealthStore,
        model: PortfolioFeatureModel,
        provider: Stage8ANoRequestMarketProvider,
        first: PortfolioRecord,
        second: PortfolioRecord
    ) {
        let root = try temporaryDirectory()
        let databaseURL = root.appendingPathComponent("permanent.sqlite")
        let store = try WealthStore(databaseURL: databaseURL)
        let first = try PortfolioRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000008001")!,
            name: "Synthetic Portfolio A",
            createdAt: instant,
            updatedAt: instant,
            sortOrder: 0
        )
        let secondInstant = UTCInstant(millisecondsSince1970: instant.millisecondsSince1970 + 1)
        let second = try PortfolioRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000008002")!,
            name: "Synthetic Portfolio B",
            createdAt: secondInstant,
            updatedAt: secondInstant,
            sortOrder: 1
        )
        try await store.createPortfolio(first)
        try await store.createPortfolio(second)
        try await store.insertIsolationSentinel(
            id: "00000000-0000-4000-8000-000000008099",
            name: "Synthetic Unrelated Permanent Sentinel"
        )

        let provider = Stage8ANoRequestMarketProvider(now: instant)
        let clock = FixedClock(instant: instant)
        let session = TransientMarketSessionStore()
        let service = MarketDataService(
            marketProvider: provider,
            fxProvider: SyntheticFXRateProvider(clock: clock),
            cache: try MarketCacheStore(databaseURL: root.appendingPathComponent("market.sqlite")),
            sessionStore: session,
            clock: clock
        )
        let model = PortfolioFeatureModel(
            store: store,
            marketDataService: service,
            marketSessionStore: session,
            preferences: PortfolioPreferencesStore(suiteName: nil, memoryOnly: true),
            clock: clock,
            mode: .syntheticDemo
        )
        await model.start()
        await model.select(first.id)
        return (root, databaseURL, store, model, provider, first, second)
    }

    @MainActor
    private func waitForBenchmarkTerminal(_ model: PortfolioFeatureModel) async throws {
        for _ in 0..<100 where model.state == .loadingBenchmark {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.state != .loadingBenchmark)
    }

    private func makeHundredHoldingFixture() async throws -> (
        root: URL, databaseURL: URL, store: WealthStore, portfolioID: UUID
    ) {
        let root = try temporaryDirectory()
        let databaseURL = root.appendingPathComponent("permanent.sqlite")
        let store = try WealthStore(databaseURL: databaseURL)
        let portfolio = try PortfolioRecord(name: "Synthetic 100 Holdings", createdAt: instant, updatedAt: instant, sortOrder: 0)
        try await store.createPortfolio(portfolio)
        for index in 0..<100 {
            let currency: CurrencyCode = index.isMultiple(of: 2) ? .cny : .usd
            let wealthQuantity = index.isMultiple(of: 2) ? Decimal(8) : Decimal(7)
            let wealth = try makeSecurityWealth(index: index, currency: currency, wealthQuantity: wealthQuantity)
            try await store.createWealthContainer(wealth)
            let link = try PortfolioSecurityLink(
                portfolioID: portfolio.id, wealthContainerID: wealth.id,
                symbol: String(format: "S%03d", index), rawMIC: "XSYN", currency: currency,
                assetKind: wealth.container.kind, sortOrder: index
            )
            try await store.linkPortfolioSecurity(link)
            let context = try Context(portfolioID: portfolio.id, linkID: link.id, currency: currency)
            try await store.createPortfolioActivity(context.opening(quantity: "10", cost: "100"))
            try await store.createPortfolioActivity(context.trade(.sell, quantity: "1", price: "15", fee: "1", milliseconds: 1))
            try await store.createPortfolioActivity(context.trade(.sell, quantity: "1", price: "16", fee: "1", milliseconds: 2))
        }
        return (root, databaseURL, store, portfolio.id)
    }

    private func makeSecurityWealth(index: Int, currency: CurrencyCode, wealthQuantity: Decimal) throws -> WealthContainer {
        let quantity = try AssetQuantity(decimal: wealthQuantity)
        let price = try MarketPrice(decimal: 20, quoteCurrency: currency)
        let details = WealthRecordDetails.security(
            ticker: String(format: "S%03d", index), mic: "XSYN", quantity: quantity, manualPrice: price
        )
        let original = try details.currentValue()
        let manualFX: ManualFXInput? = currency == .usd
            ? try ManualFXInput(
                rate: FXRate(decimal: Decimal(string: "7.125")!, sourceCurrency: .usd, targetCurrency: .cny),
                source: "manual.synthetic.stage8a", referenceDate: date, recordedAt: instant, isStale: false
            )
            : nil
        let valuation = try WealthValuation.valuation(
            original: original, manualFX: manualFX, identityDate: date, recordedAt: instant
        )
        let id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!
        let kinds: [AssetContainerKind] = [.stock, .etf, .fund]
        return try WealthContainer(
            container: AssetContainer(
                id: id, accountID: nil, name: "Synthetic Security \(index)", kind: kinds[index % kinds.count],
                institution: "Synthetic Broker", primaryCurrency: currency,
                notes: "Synthetic Stage 8A performance fixture", createdDate: date, updatedDate: date
            ),
            details: details,
            valuation: valuation
        )
    }

    private func checkedNAV(_ holdings: [PortfolioHoldingSummary]) throws -> Money {
        try holdings.map(\.marketValueCNY).reduce(Money(minorUnits: 0, currency: .cny)) { try $0.adding($1) }
    }

    private func allocationInputs(_ holdings: [PortfolioHoldingSummary]) throws -> (
        assetKindTotal: Money, currencyTotal: Money
    ) {
        var assetTotal = Money(minorUnits: 0, currency: .cny)
        for kind in [AssetContainerKind.stock, .etf, .fund] {
            let subtotal = try holdings.filter { $0.link.assetKind == kind }.map(\.marketValueCNY)
                .reduce(Money(minorUnits: 0, currency: .cny)) { try $0.adding($1) }
            assetTotal = try assetTotal.adding(subtotal)
        }
        var currencyTotal = Money(minorUnits: 0, currency: .cny)
        for currency in CurrencyCode.allCases {
            let subtotal = try holdings.filter { $0.link.currency == currency }.map(\.marketValueCNY)
                .reduce(Money(minorUnits: 0, currency: .cny)) { try $0.adding($1) }
            currencyTotal = try currencyTotal.adding(subtotal)
        }
        return (assetTotal, currencyTotal)
    }

    private func heatmapInputs(_ holdings: [PortfolioHoldingSummary]) -> [String] {
        holdings.map { "\($0.link.stableIdentity)|\($0.unrealizedCNYPnL.minorUnits.signum())" }
    }

    private func makeFiveThousandSnapshots(portfolioID: UUID) throws -> [PortfolioNAVSnapshot] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2010, month: 1, day: 1))!
        return try (0..<5_000).map { index in
            let day = calendar.date(byAdding: .day, value: index, to: start)!
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            return PortfolioNAVSnapshot(
                id: UUID(), portfolioID: portfolioID,
                civilDate: try CivilDate(year: parts.year!, month: parts.month!, day: parts.day!),
                createdAt: instant, totalCNY: Money(minorUnits: Int64(10_000 + index), currency: .cny),
                isComplete: true, items: []
            )
        }
    }

    private func makeBenchmarkBars(for dates: [CivilDate]) throws -> [MarketOHLCVBar] {
        try dates.enumerated().map { index, day in
            let price = try MarketQuotePrice(decimal: Decimal(100 + index), quoteCurrency: .cny)
            return try MarketOHLCVBar(
                sessionDate: day, openedAt: nil, open: price, high: price, low: price, close: price,
                volume: nil, adjustment: .all, providerIdentifier: "synthetic.stage8a",
                fetchedAt: instant, freshness: .unknown
            )
        }
    }

    @MainActor
    private func makeSwitchingFixture() async throws -> (
        root: URL, model: PortfolioFeatureModel, provider: Stage8ANoRequestMarketProvider, portfolioIDs: [UUID]
    ) {
        let root = try temporaryDirectory()
        let store = try WealthStore(databaseURL: root.appendingPathComponent("permanent.sqlite"))
        var ids: [UUID] = []
        for index in 0..<10 {
            let portfolio = try PortfolioRecord(name: "Synthetic Switch \(index)", createdAt: instant, updatedAt: instant, sortOrder: index)
            try await store.createPortfolio(portfolio)
            ids.append(portfolio.id)
            let wealth = try makeSecurityWealth(index: index, currency: .cny, wealthQuantity: 1)
            try await store.createWealthContainer(wealth)
            let link = try PortfolioSecurityLink(
                portfolioID: portfolio.id, wealthContainerID: wealth.id,
                symbol: String(format: "S%03d", index), rawMIC: "XSYN", currency: .cny,
                assetKind: wealth.container.kind, sortOrder: 0
            )
            try await store.linkPortfolioSecurity(link)
            let context = try Context(portfolioID: portfolio.id, linkID: link.id, currency: .cny)
            try await store.createPortfolioActivity(context.opening(quantity: "1", cost: "10"))
            let holding = try await store.portfolioHoldingSummaries(portfolioID: portfolio.id)[0]
            let item = PortfolioNAVSnapshotItem(
                id: UUID(), securityLinkID: link.id, quantity: holding.portfolioQuantity,
                manualMark: holding.manualMark, originalMarketValue: holding.marketValue,
                fx: holding.wealthFX, convertedCNYValue: holding.marketValueCNY,
                remainingCNYBasis: holding.remainingCNYBasis, reconciliation: holding.reconciliation
            )
            try await store.replacePortfolioNAVSnapshot(PortfolioNAVSnapshot(
                id: UUID(), portfolioID: portfolio.id, civilDate: date, createdAt: instant,
                totalCNY: holding.marketValueCNY, isComplete: true, items: [item]
            ))
        }
        let provider = Stage8ANoRequestMarketProvider(now: instant)
        let clock = FixedClock(instant: instant)
        let session = TransientMarketSessionStore()
        let service = MarketDataService(
            marketProvider: provider, fxProvider: SyntheticFXRateProvider(clock: clock),
            cache: try MarketCacheStore(databaseURL: root.appendingPathComponent("market.sqlite")),
            sessionStore: session, clock: clock
        )
        return (root, PortfolioFeatureModel(
            store: store, marketDataService: service, marketSessionStore: session,
            preferences: PortfolioPreferencesStore(suiteName: nil, memoryOnly: true),
            clock: clock, mode: .syntheticDemo
        ), provider, ids)
    }

    private func utcInstant(_ canonical: String) throws -> UTCInstant {
        let civil = try CivilDate(canonical: canonical)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return UTCInstant(date: calendar.date(from: DateComponents(year: civil.year, month: civil.month, day: civil.day))!)
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1_000_000_000_000_000
    }

    private func printPerformance(_ name: String, samples: [Double], warmups: Int) {
        let sorted = samples.sorted()
        let elapsed = samples.reduce(0, +)
        let p50 = sorted[sorted.count / 2]
        let p95: String
        if sorted.count >= 5 {
            p95 = String(format: "%.3f", sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.up)) - 1)])
        } else {
            p95 = "NOT AVAILABLE"
        }
        print(String(format: "STAGE8A_PERF %@ warmup=%d iterations=%d elapsed_ms=%.3f p50_ms=%.3f p95_ms=%@", name, warmups, samples.count, elapsed, p50, p95))
    }

    private struct Context {
        let portfolioID: UUID
        let linkID: UUID
        let currency: CurrencyCode
        let rate: FXRate

        init(portfolioID: UUID = UUID(), linkID: UUID = UUID(), currency: CurrencyCode = .cny) throws {
            self.portfolioID = portfolioID; self.linkID = linkID; self.currency = currency
            rate = currency == .cny ? .cnyIdentity : try FXRate(decimal: Decimal(string: "7.125")!, sourceCurrency: .usd, targetCurrency: .cny)
        }

        func opening(quantity: String, cost: String) throws -> PortfolioActivity {
            let money = try Money(decimal: Decimal(string: cost)!, currency: currency)
            let fx = try PortfolioFXProvenance(original: money, rate: rate, source: currency == .cny ? "identity" : "manual.synthetic", referenceDate: try CivilDate(canonical: "2026-01-15"), recordedAt: UTCInstant(millisecondsSince1970: 1_768_435_200_000), isManual: currency == .usd, isStale: false)
            return try PortfolioActivity(portfolioID: portfolioID, securityLinkID: linkID,
                civilDate: try CivilDate(canonical: "2026-01-15"), recordedAt: UTCInstant(millisecondsSince1970: 1_768_435_200_000), exchangeTimeZoneIdentifier: "UTC",
                payload: .openingLot(quantity: try AssetQuantity(decimal: Decimal(string: quantity)!), totalCost: money, fx: fx, note: "Synthetic"))
        }

        func trade(_ kind: PortfolioActivity.Kind, quantity: String, price: String, fee: String, milliseconds: Int64 = 0) throws -> PortfolioActivity {
            let q = try AssetQuantity(decimal: Decimal(string: quantity)!)
            let p = try MarketPrice(decimal: Decimal(string: price)!, quoteCurrency: currency)
            let f = try Money(decimal: Decimal(string: fee)!, currency: currency)
            let gross = try PortfolioCheckedMath.moneyProduct(quantity: q, price: p)
            let total = kind == .buy ? try gross.adding(f) : try gross.subtracting(f)
            let fx = try PortfolioFXProvenance(original: total, rate: rate, source: currency == .cny ? "identity" : "manual.synthetic", referenceDate: try CivilDate(canonical: "2026-01-15"), recordedAt: UTCInstant(millisecondsSince1970: 1_768_435_200_000 + milliseconds), isManual: currency == .usd, isStale: false)
            return try PortfolioActivity(portfolioID: portfolioID, securityLinkID: linkID,
                civilDate: try CivilDate(canonical: "2026-01-15"), recordedAt: UTCInstant(millisecondsSince1970: 1_768_435_200_000 + milliseconds), exchangeTimeZoneIdentifier: "UTC",
                payload: kind == .buy ? .buy(quantity: q, unitPrice: p, fee: f, fx: fx) : .sell(quantity: q, unitPrice: p, fee: f, fx: fx))
        }
    }
}

private actor Stage8ANoRequestMarketProvider: MarketDataProvider {
    nonisolated let descriptor = ProviderDescriptor(
        identifier: "synthetic.stage8a.no-request",
        displayName: "Synthetic Stage 8A No-request Provider",
        kind: .synthetic
    )
    private let now: UTCInstant
    private var searchRequests = 0
    private var historyRequests = 0

    init(now: UTCInstant) { self.now = now }

    func capabilities() -> MarketProviderCapabilities {
        MarketProviderCapabilities(
            provider: descriptor, entitlement: .unknown, observedPlanName: nil,
            markets: [], supportsSearch: false, supportsHistoricalPrices: false,
            supportsCorporateActions: false, endpointCapabilities: [], observedAt: now
        )
    }

    func search(query: String) async throws -> [MarketInstrument] {
        searchRequests += 1
        throw ProviderBoundaryError.missing
    }

    func latestQuote(for instrument: MarketInstrument) async throws -> MarketQuote {
        throw ProviderBoundaryError.missing
    }

    func historicalBars(_ request: MarketHistoryRequest) async throws -> MarketHistoryPage {
        historyRequests += 1
        throw ProviderBoundaryError.missing
    }

    func corporateActions(
        for instrument: MarketInstrument,
        from startDate: CivilDate?,
        through endDate: CivilDate?
    ) async throws -> [MarketCorporateAction] {
        throw ProviderBoundaryError.missing
    }

    func requestCounts() -> (search: Int, history: Int) {
        (searchRequests, historyRequests)
    }
}
