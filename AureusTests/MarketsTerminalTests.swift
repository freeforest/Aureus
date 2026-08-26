import Foundation
import Testing
@testable import Aureus

@Suite("Stage 7 Markets Terminal")
struct MarketsTerminalTests {
    @Test("SMA and EMA use Decimal windows, seed, and recursion")
    func movingAverages() throws {
        let values = try decimalValues(["1", "2", "3", "4", "5"])
        let sma = try MarketIndicatorCalculator.sma(values, period: 3)
        let ema = try MarketIndicatorCalculator.ema(values, period: 3)
        let expected = try ["2", "3", "4"].map(FixedPointMath.parseCanonical)
        #expect(sma.map(\.value) == expected)
        #expect(ema.map(\.value) == expected)
        #expect(try MarketIndicatorCalculator.sma(values, period: 6).isEmpty)
        #expect(try MarketIndicatorCalculator.ema(values, period: 6).isEmpty)
    }

    @Test("RSI Wilder smoothing handles rising falling and flat without nonfinite values")
    func rsiGoldenVectors() throws {
        let rising = try decimalValues((1...20).map(String.init))
        let falling = try decimalValues((1...20).reversed().map(String.init))
        let flat = try decimalValues(Array(repeating: "7", count: 20))
        #expect(try MarketIndicatorCalculator.rsi(rising, period: 14).last?.value == 100)
        #expect(try MarketIndicatorCalculator.rsi(falling, period: 14).last?.value == 0)
        #expect(try MarketIndicatorCalculator.rsi(flat, period: 14).last?.value == 50)
    }

    @Test("MACD aligns dates and produces signal only after nine MACD points")
    func macdAlignment() throws {
        let values = try decimalValues((1...60).map(String.init))
        let result = try MarketIndicatorCalculator.macd(values, fast: 12, slow: 26, signal: 9)
        #expect(result.first?.sessionDate == values[25].0)
        #expect(result.prefix(8).allSatisfy { $0.signal == nil && $0.histogram == nil })
        #expect(result[8].signal != nil)
        #expect(result[8].histogram != nil)
    }

    @Test("Bollinger uses population deviation")
    func bollingerPopulationDeviation() throws {
        let values = try decimalValues(["1", "2", "3", "4", "5"])
        let point = try #require(MarketIndicatorCalculator.bollinger(values, period: 5, multiplier: 2).first)
        #expect(point.middle == 3)
        let upper = try FixedPointMath.coefficient(from: point.upper, scale: 6)
        let lower = try FixedPointMath.coefficient(from: point.lower, scale: 6)
        #expect(upper == 5_828_427)
        #expect(lower == 171_573)
    }

    @Test("Indicator input rejects duplicate and unordered dates")
    func indicatorInputOrdering() throws {
        let bars = try syntheticBars(count: 3)
        let duplicate = [bars[0], bars[0]]
        let unordered = [bars[1], bars[0]]
        #expect(throws: MarketIndicatorError.duplicateSessionDate) {
            _ = try MarketIndicatorCalculator.calculate(bars: duplicate, interval: .oneDay, adjustment: .all)
        }
        #expect(throws: MarketIndicatorError.unorderedInput) {
            _ = try MarketIndicatorCalculator.calculate(bars: unordered, interval: .oneDay, adjustment: .all)
        }
    }

    @Test("Indicator arithmetic failure is typed")
    func indicatorOverflow() throws {
        let date1 = try CivilDate(year: 2025, month: 1, day: 1)
        let date2 = try CivilDate(year: 2025, month: 1, day: 2)
        let values = [(date1, Decimal.greatestFiniteMagnitude), (date2, Decimal.greatestFiniteMagnitude)]
        #expect(throws: MarketIndicatorError.arithmeticFailure) {
            _ = try MarketIndicatorCalculator.sma(values, period: 2)
        }
    }

    @Test("Ten thousand daily bars calculate deterministically")
    func tenThousandBars() throws {
        let bars = try syntheticBars(count: 10_000)
        let first = try MarketIndicatorCalculator.calculate(bars: bars, interval: .oneDay, adjustment: .all)
        let second = try MarketIndicatorCalculator.calculate(bars: bars, interval: .oneDay, adjustment: .all)
        #expect(first == second)
        #expect(first.sma20.count == 9_981)
        #expect(first.ema26.count == 9_975)
        #expect(first.rsi14.count == 9_986)
        #expect(first.bollinger20.count == 9_981)
    }

    @Test("Watchlist normalization identity duplicate limit and reorder are deterministic")
    func watchlistIdentities() throws {
        let normalized = try MarketWatchlistIdentity(symbol: " aapl ", mic: " xngs ")
        #expect(normalized.symbol == "AAPL")
        #expect(normalized.mic == "XNGS")
        #expect(normalized.id == "AAPL|XNGS")
        #expect(throws: MarketPreferenceError.invalidIdentifier) {
            _ = try MarketWatchlistIdentity(symbol: "AAPL", mic: "US")
        }
        #expect(throws: MarketPreferenceError.invalidIdentifier) {
            _ = try MarketWatchlistIdentity(symbol: "AAPL", mic: "XN💰S")
        }
    }

    @Test("Preferences persist only approved identifiers and UI choices")
    func preferencePersistenceAndIsolation() async throws {
        let suite = "Aureus.Stage7.\(UUID().uuidString)"
        let store = MarketPreferencesStore(suiteName: suite)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let identity = try MarketWatchlistIdentity(symbol: "AAPL", mic: "XNGS")
        let snapshot = MarketPreferencesSnapshot(
            version: 1,
            watchlist: [identity],
            selectedRange: .threeMonths,
            enabledIndicators: [.rsi14, .macd],
            showsAccessibleTable: true
        )
        try await store.save(snapshot)
        #expect(try await store.load() == snapshot)
        let data = try #require(UserDefaults(suiteName: suite)?.data(forKey: MarketPreferencesStore.storageKey))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("AAPL"))
        #expect(text.contains("XNGS"))
        #expect(!text.localizedCaseInsensitiveContains("provider"))
        #expect(!text.localizedCaseInsensitiveContains("price"))
        #expect(!text.localizedCaseInsensitiveContains("description"))
        #expect(!text.localizedCaseInsensitiveContains("freshness"))

        let isolated = MarketPreferencesStore(suiteName: nil, memoryOnly: true)
        #expect(try await isolated.load() == .empty)
    }

    @Test("Preferences reject duplicates and more than one hundred identifiers")
    func preferenceLimits() async throws {
        let store = MarketPreferencesStore(suiteName: nil, memoryOnly: true)
        let identity = try MarketWatchlistIdentity(symbol: "AAPL", mic: "XNGS")
        await #expect(throws: MarketPreferenceError.persistenceFailure) {
            try await store.save(.init(version: 1, watchlist: [identity, identity], selectedRange: .oneYear, enabledIndicators: [], showsAccessibleTable: false))
        }
        let items = try (0...100).map { index in
            try MarketWatchlistIdentity(symbol: "S\(index)", mic: "XNGS")
        }
        await #expect(throws: MarketPreferenceError.persistenceFailure) {
            try await store.save(.init(version: 1, watchlist: items, selectedRange: .oneYear, enabledIndicators: [], showsAccessibleTable: false))
        }
    }

    @Test("Chart bridge round trips finite typed data and rejects oversize")
    func chartBridgeSchema() throws {
        let bars = try syntheticBars(count: 100)
        let indicators = try MarketIndicatorCalculator.calculate(bars: bars, interval: .oneDay, adjustment: .all)
        let payload = try MarketChartPayload(
            configuration: chartConfiguration(),
            bars: bars,
            indicators: indicators,
            enabledIndicators: Set(MarketIndicatorKind.allCases)
        )
        let data = try JSONEncoder().encode(payload)
        #expect(try JSONDecoder().decode(MarketChartPayload.self, from: data) == payload)
        #expect(payload.candles.count == 100)
        #expect(payload.lines.contains { $0.identifier == "macd-histogram" })
        #expect(throws: MarketChartBridgeError.oversizedPayload) {
            _ = try MarketChartPayload(configuration: chartConfiguration(), bars: syntheticBars(count: 10_001), indicators: indicators, enabledIndicators: [])
        }
    }

    @Test("Ten thousand bars encode within bridge bound")
    func tenThousandBridge() throws {
        let bars = try syntheticBars(count: 10_000)
        let indicators = try MarketIndicatorCalculator.calculate(bars: bars, interval: .oneDay, adjustment: .all)
        let payload = try MarketChartPayload(configuration: chartConfiguration(), bars: bars, indicators: indicators, enabledIndicators: [.sma20, .macd])
        let data = try JSONEncoder().encode(payload)
        #expect(!data.isEmpty)
        #expect(payload.candles.count == 10_000)
    }

    @Test("Inbound chart messages reject unversioned and free-form data")
    func inboundMessages() throws {
        #expect(try MarketChartInboundMessage.decode(["version": 1, "type": "ready"]) == .ready)
        #expect(throws: MarketChartBridgeError.invalidMessage) {
            _ = try MarketChartInboundMessage.decode(["version": 2, "type": "ready"])
        }
        #expect(throws: MarketChartBridgeError.invalidMessage) {
            _ = try MarketChartInboundMessage.decode(["version": 1, "type": "rendererError", "category": "raw server error"])
        }
    }

    @Test("Repeated visible-range and indicator bridge changes remain deterministic")
    func repeatedBridgeChanges() throws {
        let bars = try syntheticBars(count: 250)
        let indicators = try MarketIndicatorCalculator.calculate(
            bars: bars,
            interval: .oneDay,
            adjustment: .all
        )
        for index in 0..<1_000 {
            let start = try civilDate(offset: index % 100).description
            let end = try civilDate(offset: (index % 100) + 20).description
            #expect(
                try MarketChartInboundMessage.decode([
                    "version": 1,
                    "type": "visibleRange",
                    "start": start,
                    "end": end
                ]) == .visibleRange(start: start, end: end)
            )
            let enabled: Set<MarketIndicatorKind> = index.isMultiple(of: 2)
                ? [.sma20, .ema12, .bollinger20]
                : [.rsi14, .macd]
            let payload = try MarketChartPayload(
                configuration: chartConfiguration(),
                bars: bars,
                indicators: indicators,
                enabledIndicators: enabled
            )
            #expect(payload.candles.count == 250)
        }
    }

    @Test("Bundled chart assets are exact local 5.2.0 with restrictive CSP")
    func localChartAssets() throws {
        let root = try #require(Bundle.main.url(forResource: "5.2.0", withExtension: nil, subdirectory: "ThirdParty/LightweightCharts"))
        let names = ["lightweight-charts.standalone.production.js", "LICENSE", "NOTICE", "PROVENANCE.md", "market-chart.html", "aureus-market-chart.js"]
        for name in names { #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path)) }
        let html = try String(contentsOf: root.appendingPathComponent("market-chart.html"), encoding: .utf8)
        let integration = try String(contentsOf: root.appendingPathComponent("aureus-market-chart.js"), encoding: .utf8)
        #expect(html.contains("connect-src 'none'"))
        #expect(!html.contains("https://"))
        #expect(!html.contains("http://"))
        #expect(!integration.contains("fetch("))
        #expect(!integration.contains("XMLHttpRequest"))
    }

    @Test("Markets model makes no automatic request and exposes four honest cards")
    @MainActor
    func noAutomaticRequest() async throws {
        let provider = CountingMarketProvider(clock: FixedClock(instant: .init(millisecondsSince1970: 1_700_000_000_000)))
        let dependencies = try await makeMarketDependencies(provider: provider)
        let model = MarketsFeatureModel(
            marketDataService: dependencies.service,
            marketProvider: provider,
            sessionStore: dependencies.session,
            preferences: MarketPreferencesStore(suiteName: nil, memoryOnly: true),
            clock: FixedClock(instant: .init(millisecondsSince1970: 1_700_000_000_000)),
            mode: .local
        )
        await model.start()
        #expect(await provider.searchCount == 0)
        #expect(await provider.historyCount == 0)
        #expect(model.capabilityCards.count == 4)
        #expect(model.capabilityCards[0].detail.contains("XNGS"))
        #expect(model.capabilityCards.dropFirst().allSatisfy { $0.status == "Not Verified" })
    }

    @Test("Explicit Search and daily refresh preserve raw MIC and use Session Store")
    @MainActor
    func explicitSessionFlow() async throws {
        let clock = FixedClock(instant: .init(millisecondsSince1970: 1_700_000_000_000))
        let provider = CountingMarketProvider(clock: clock)
        let dependencies = try await makeMarketDependencies(provider: provider)
        let model = MarketsFeatureModel(
            marketDataService: dependencies.service,
            marketProvider: provider,
            sessionStore: dependencies.session,
            preferences: MarketPreferencesStore(suiteName: nil, memoryOnly: true),
            clock: clock,
            mode: .local
        )
        await model.start()
        model.query = "AAPL"
        model.submitSearch()
        try await Task.sleep(for: .milliseconds(400))
        let instrument = try #require(model.searchResults.first)
        #expect(instrument.mic == "XNGS")
        model.select(instrument)
        model.refreshSelectedHistory()
        try await Task.sleep(for: .milliseconds(200))
        #expect(await provider.searchCount == 1)
        #expect(await provider.historyCount == 1)
        #expect(model.historyPage?.instrument.mic == "XNGS")
        #expect(model.historyPage?.bars.count == 80)
        #expect((await dependencies.session.statistics()).entryCount == 2)
        await model.clearSession()
        #expect((await dependencies.session.statistics()).entryCount == 0)
        #expect(model.state == .sessionCleared)
    }

    @Test("Search query generation cancels obsolete UI result")
    @MainActor
    func searchGeneration() async throws {
        let clock = FixedClock(instant: .init(millisecondsSince1970: 1_700_000_000_000))
        let provider = CountingMarketProvider(clock: clock)
        let dependencies = try await makeMarketDependencies(provider: provider)
        let model = MarketsFeatureModel(
            marketDataService: dependencies.service,
            marketProvider: provider,
            sessionStore: dependencies.session,
            preferences: MarketPreferencesStore(suiteName: nil, memoryOnly: true),
            clock: clock,
            mode: .local
        )
        await model.start()
        model.query = "OLD"
        model.submitSearch()
        model.query = "AAPL"
        model.submitSearch()
        try await Task.sleep(for: .milliseconds(500))
        #expect(await provider.searchCount == 1)
        #expect(model.searchResults.first?.symbol == "AAPL")
    }

    @Test("Daily ranges stay daily and one day is Latest Daily Bar")
    func dailyRangeSemantics() {
        #expect(MarketRange.oneDay.outputSize == 1)
        #expect(MarketRange.oneDay.dailyDisclosure == "Latest Daily Bar")
        #expect(MarketRange.maximum.outputSize == 5_000)
        #expect(MarketInterval.oneDay.isIntraday == false)
    }

    private func decimalValues(_ strings: [String]) throws -> [(CivilDate, Decimal)] {
        try strings.enumerated().map { index, value in
            (try civilDate(offset: index), try FixedPointMath.parseCanonical(value))
        }
    }

    private func chartConfiguration() -> MarketChartConfiguration {
        .init(schemaVersion: 1, provider: "synthetic.stage7", symbol: "AAPL", rawMIC: "XNGS", freshness: "unknown", selectedRange: "1Y", darkAppearance: false)
    }

    private func syntheticBars(count: Int) throws -> [MarketOHLCVBar] {
        try (0..<count).map { index in
            let close = Int64(10_000_000_000 + index * 1_000_000)
            return try MarketOHLCVBar(
                sessionDate: civilDate(offset: index),
                openedAt: nil,
                open: MarketQuotePrice(coefficient: close - 100_000, quoteCurrency: .usd),
                high: MarketQuotePrice(coefficient: close + 200_000, quoteCurrency: .usd),
                low: MarketQuotePrice(coefficient: close - 200_000, quoteCurrency: .usd),
                close: MarketQuotePrice(coefficient: close, quoteCurrency: .usd),
                volume: AssetQuantity(coefficient: Int64(100_000_000 + index)),
                adjustment: .all,
                providerIdentifier: "synthetic.stage7",
                fetchedAt: .init(millisecondsSince1970: 1_700_000_000_000),
                freshness: .unknown
            )
        }
    }

    private func civilDate(offset: Int) throws -> CivilDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1))!
        let date = calendar.date(byAdding: .day, value: offset, to: start)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return try CivilDate(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    private func makeMarketDependencies(provider: CountingMarketProvider) async throws -> (service: MarketDataService, session: TransientMarketSessionStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Aureus-Stage7-Unit-\(UUID().uuidString)", isDirectory: true)
        let cache = try MarketCacheStore(databaseURL: root.appendingPathComponent("market.sqlite"))
        let session = TransientMarketSessionStore()
        let clock = FixedClock(instant: .init(millisecondsSince1970: 1_700_000_000_000))
        let service = MarketDataService(
            marketProvider: provider,
            fxProvider: SyntheticFXRateProvider(clock: clock),
            cache: cache,
            sessionStore: session,
            clock: clock
        )
        return (service, session)
    }
}

private actor CountingMarketProvider: MarketDataProvider {
    nonisolated let descriptor = ProviderDescriptor(identifier: "synthetic.stage7.counting", displayName: "Synthetic Stage 7", kind: .synthetic)
    private(set) var searchCount = 0
    private(set) var historyCount = 0
    let clock: any Clock

    init(clock: any Clock) { self.clock = clock }

    func capabilities() -> MarketProviderCapabilities {
        MarketProviderCapabilities(provider: descriptor, entitlement: .basic, observedPlanName: "Synthetic", markets: [], supportsSearch: true, supportsHistoricalPrices: true, supportsCorporateActions: false, endpointCapabilities: [], observedAt: clock.now())
    }

    func search(query: String) async throws -> [MarketInstrument] {
        searchCount += 1
        return [MarketInstrument(id: UUID(uuidString: "00000000-0000-4000-8000-000000000777")!, symbol: query.uppercased(), mic: "XNGS", currency: .usd, displayName: "Synthetic Instrument")]
    }

    func latestQuote(for instrument: MarketInstrument) async throws -> MarketQuote { throw ProviderBoundaryError.unsupportedEntitlement }

    func historicalBars(_ request: MarketHistoryRequest) async throws -> MarketHistoryPage {
        historyCount += 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let bars = try (0..<80).map { index in
            let date = calendar.date(byAdding: .day, value: index, to: start)!
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            let close = Int64(10_000_000_000 + index * 2_000_000)
            return try MarketOHLCVBar(
                sessionDate: CivilDate(year: parts.year!, month: parts.month!, day: parts.day!), openedAt: nil,
                open: MarketQuotePrice(coefficient: close - 100_000, quoteCurrency: .usd),
                high: MarketQuotePrice(coefficient: close + 200_000, quoteCurrency: .usd),
                low: MarketQuotePrice(coefficient: close - 200_000, quoteCurrency: .usd),
                close: MarketQuotePrice(coefficient: close, quoteCurrency: .usd),
                volume: AssetQuantity(coefficient: 100_000_000 + Int64(index)), adjustment: request.adjustment,
                providerIdentifier: descriptor.identifier, fetchedAt: clock.now(), freshness: .unknown
            )
        }
        return MarketHistoryPage(instrument: request.instrument, bars: bars, nextEndDate: nil, sourceRevision: "synthetic", providerIdentifier: descriptor.identifier)
    }

    func corporateActions(for instrument: MarketInstrument, from startDate: CivilDate?, through endDate: CivilDate?) async throws -> [MarketCorporateAction] {
        throw ProviderBoundaryError.unsupportedEntitlement
    }
}
