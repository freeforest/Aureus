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

    @Test("Fresh and v1 through v5 databases migrate to active v6 without REAL authority")
    func migrationForward() async throws {
        for start in [nil, DatabaseMigrations.permanentV1, DatabaseMigrations.permanentV2,
                      DatabaseMigrations.permanentV3, DatabaseMigrations.permanentV4,
                      DatabaseMigrations.permanentV5] {
            let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
            let url = root.appendingPathComponent("portfolio-\(start ?? "fresh").sqlite")
            if let start {
                let queue = try DatabaseQueueFactory.open(at: url)
                try DatabaseMigrations.permanentMigrator().migrate(queue, upTo: start)
            }
            let store = try WealthStore(databaseURL: url)
            #expect(try await store.schemaVersion() == 6)
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
