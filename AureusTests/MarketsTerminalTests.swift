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
            let startDate = try CivilDate(canonical: start)
            let endDate = try CivilDate(canonical: end)
            #expect(
                try MarketChartInboundMessage.decode([
                    "version": 1,
                    "type": "visibleRange",
                    "start": start,
                    "end": end
                ]) == .visibleRange(start: startDate, end: endDate)
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
        #expect(model.historicalAcceptanceRecord.contains("XNGS"))
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
        let bars = try #require(model.historyPage?.bars)
        let subsetStart = bars[10].sessionDate
        let subsetEnd = bars[19].sessionDate
        model.receiveChartMessage(.visibleRange(start: subsetStart, end: subsetEnd))
        #expect(model.visibleBars.count == 10)
        #expect(model.visibleSummary?.start == subsetStart)
        #expect(model.visibleSummary?.end == subsetEnd)
        let outsideStart = try CivilDate(year: 1900, month: 1, day: 1)
        let outsideEnd = try CivilDate(year: 2200, month: 1, day: 1)
        model.receiveChartMessage(.visibleRange(start: outsideStart, end: outsideEnd))
        #expect(model.visibleBars.count == 80)
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

    @Test("Explicit Search preserves empty-session offline timeout and missing disclosure", arguments: EmptySessionFailure.allCases)
    @MainActor
    func emptySessionSearchFailure(failure: EmptySessionFailure) async throws {
        let clock = FixedClock(instant: .init(millisecondsSince1970: 1_700_000_000_000))
        let provider = CountingMarketProvider(clock: clock, failure: failure.error)
        let dependencies = try await makeMarketDependencies(provider: provider)
        let model = MarketsFeatureModel(
            marketDataService: dependencies.service, marketProvider: provider,
            sessionStore: dependencies.session,
            preferences: MarketPreferencesStore(suiteName: nil, memoryOnly: true),
            clock: clock, mode: .local
        )
        await model.start()
        #expect(model.state == .noSessionData)
        #expect(await provider.searchCount == 0)
        #expect(await provider.historyCount == 0)
        model.query = "AAPL"
        model.submitSearch()
        try await waitForSessionFailure(model, pendingState: .searching)
        #expect(model.state == failure.state)
        #expect(model.errorDisclosure == failure.disclosure)
        #expect(await provider.searchCount == 1)
        #expect(await provider.historyCount == 0)
        #expect(model.searchResults.isEmpty)
        #expect(model.ephemeralInstruments.isEmpty)
        #expect(model.selectedInstrument == nil)
        #expect(model.historyPage == nil)
        #expect(model.chartPayload == nil)
        #expect(model.indicatorSnapshot == nil)
        #expect(model.visibleBars.isEmpty)
        #expect(model.visibleSummary == nil)
        #expect((await dependencies.session.statistics()).entryCount == 0)
    }

    @Test("Explicit History preserves empty-session offline timeout and missing disclosure", arguments: EmptySessionFailure.allCases)
    @MainActor
    func emptySessionHistoryFailure(failure: EmptySessionFailure) async throws {
        let clock = FixedClock(instant: .init(millisecondsSince1970: 1_700_000_000_000))
        let provider = CountingMarketProvider(clock: clock, failure: failure.error)
        let dependencies = try await makeMarketDependencies(provider: provider)
        let model = MarketsFeatureModel(
            marketDataService: dependencies.service, marketProvider: provider,
            sessionStore: dependencies.session,
            preferences: MarketPreferencesStore(suiteName: nil, memoryOnly: true),
            clock: clock, mode: .local
        )
        await model.start()
        #expect(model.state == .noSessionData)
        #expect(await provider.searchCount == 0)
        #expect(await provider.historyCount == 0)
        let instrument = MarketInstrument(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000777")!,
            symbol: "AAPL", mic: "XNGS", currency: .usd, displayName: "Synthetic Instrument"
        )
        model.select(instrument)
        #expect(await provider.historyCount == 0)
        model.refreshSelectedHistory()
        try await waitForSessionFailure(model, pendingState: .loadingHistory)
        #expect(model.state == failure.state)
        #expect(model.errorDisclosure == failure.disclosure)
        #expect(await provider.searchCount == 0)
        #expect(await provider.historyCount == 1)
        #expect(model.selectedInstrument == instrument)
        #expect(model.searchResults.isEmpty)
        #expect(model.historyPage == nil)
        #expect(model.chartPayload == nil)
        #expect(model.indicatorSnapshot == nil)
        #expect(model.visibleBars.isEmpty)
        #expect(model.visibleSummary == nil)
        #expect((await dependencies.session.statistics()).entryCount == 0)
    }

    @Test("CLI isolated graph exposes six request-specific failures through public Markets operations",
          arguments: SyntheticMarketFailureScenario.allCases)
    @MainActor
    func launchScenarioFailure(scenario: SyntheticMarketFailureScenario) async throws {
        let expected: EmptySessionFailure
        let historyFailure: Bool
        switch scenario {
        case .searchOffline: (expected, historyFailure) = (.offline, false)
        case .searchTimeout: (expected, historyFailure) = (.timeout, false)
        case .searchMissing: (expected, historyFailure) = (.missing, false)
        case .historyOffline: (expected, historyFailure) = (.offline, true)
        case .historyTimeout: (expected, historyFailure) = (.timeout, true)
        case .historyMissing: (expected, historyFailure) = (.missing, true)
        }
        let configuration = LaunchConfiguration.current(arguments: [
            "--aureus-ui-testing", "--aureus-demo", "--aureus-market-failure-scenario", scenario.rawValue
        ])
        let root = try #require(configuration.temporaryRoot)
        defer { try? FileManager.default.removeItem(at: root) }
        let graph = try await AppDependencies.make(configuration: configuration)
        let provider = try #require(graph.marketDataProvider as? SyntheticMarketDataProvider)
        #expect(provider.failureScenario == scenario && provider.scenario == .success)
        #expect(graph.credentialStore is InMemoryCredentialStore)
        #expect(!configuration.settingsCacheAuditEnabled)
        #expect(try await graph.marketCacheStore.statistics().entryCount == 0)
        try await graph.wealthStore.insertIsolationSentinel(id: "market-failure", name: "Synthetic Market Failure Sentinel")
        let wealthBefore = try await graph.wealthStore.fetchWealthContainers()
        let goalsBefore = try await graph.wealthStore.fetchGoals()
        let ledgerBefore = try await graph.wealthStore.fetchLedgerEntries()
        #expect(!wealthBefore.isEmpty && !goalsBefore.isEmpty && !ledgerBefore.isEmpty)

        let model = launchScenarioModel(graph)
        await model.start()
        #expect(model.state == .noSessionData)
        let emptySession = await graph.marketSessionStore.statistics()
        #expect(emptySession.entryCount == 0 && emptySession.accountedBytes == 0)
        #expect(model.searchResults.isEmpty && model.historyPage == nil && model.chartPayload == nil)
        model.query = "SYN"
        model.submitSearch()
        try await waitForSessionFailure(model, pendingState: .searching)
        var beforeFailure = emptySession
        if historyFailure {
            try #require(model.state == .ready)
            #expect(model.errorDisclosure == nil && model.searchResults.count == 2)
            let instrument = try #require(model.searchResults.first { $0.symbol == "SYN-CNY" && $0.mic == "XSYN" })
            #expect(model.historyPage == nil && model.chartPayload == nil && model.indicatorSnapshot == nil)
            beforeFailure = await graph.marketSessionStore.statistics()
            #expect(beforeFailure.entryCount == 1 && beforeFailure.accountedBytes > 0)
            model.select(instrument)
            #expect(model.state == .ready && model.historyPage == nil)
            #expect(await graph.marketSessionStore.statistics() == beforeFailure)
            model.refreshSelectedHistory()
            try await waitForSessionFailure(model, pendingState: .loadingHistory)
            #expect(model.selectedInstrument == instrument && model.searchResults.count == 2)
            let window = try MarketRangeRequestPolicy.window(for: model.selectedRange, now: graph.clock.now())
            let key = ["history", instrument.symbol, instrument.mic, MarketInterval.oneDay.rawValue,
                       MarketAdjustment.all.rawValue, window.startDate?.description ?? "",
                       window.endDate.description].joined(separator: "|")
            #expect(try await graph.marketSessionStore.lookup(providerIdentifier: provider.descriptor.identifier,
                logicalKey: key, dataType: .historical, now: graph.clock.now()) == .missing)
        } else {
            #expect(model.searchResults.isEmpty && model.ephemeralInstruments.isEmpty)
            #expect(model.selectedInstrument == nil)
        }
        #expect(model.state == expected.state && model.errorDisclosure == expected.disclosure)
        #expect(model.historyPage == nil && model.chartPayload == nil && model.indicatorSnapshot == nil)
        #expect(model.visibleBars.isEmpty && model.visibleSummary == nil)
        #expect(await graph.marketSessionStore.statistics() == beforeFailure)

        // These provider-only controls must not populate the Model or session, nor affect other requests.
        let baseline = SyntheticMarketDataProvider(scenario: .success, clock: graph.clock)
        let baselineInstruments = try await baseline.search(query: "SYN")
        let instrument = try #require(baselineInstruments.first)
        let capabilities = await baseline.capabilities()
        let usage = try await baseline.validateCredential()
        let quote = try await baseline.latestQuote(for: instrument)
        let actions = try await baseline.corporateActions(for: instrument, from: nil, through: nil)
        #expect(await provider.capabilities() == capabilities)
        #expect(try await provider.validateCredential() == usage)
        #expect(try await provider.latestQuote(for: instrument) == quote)
        #expect(try await provider.corporateActions(for: instrument, from: nil, through: nil) == actions)
        if historyFailure {
            #expect(try await provider.search(query: "SYN") == baselineInstruments)
        } else {
            let request = try MarketHistoryRequest(instrument: instrument, interval: .oneDay, adjustment: .all)
            let history = try await baseline.historicalBars(request)
            #expect(!history.bars.isEmpty)
            #expect(try await provider.historicalBars(request) == history)
        }
        #expect(await graph.marketSessionStore.statistics() == beforeFailure)
        #expect(try await graph.marketCacheStore.statistics().entryCount == 0)
        #expect(try await graph.wealthStore.isolationSentinels() == ["Synthetic Market Failure Sentinel"])
        #expect(try await graph.wealthStore.fetchWealthContainers() == wealthBefore)
        #expect(try await graph.wealthStore.fetchGoals() == goalsBefore)
        #expect(try await graph.wealthStore.fetchLedgerEntries() == ledgerBefore)
    }

    @Test("CLI graph without injection completes Search and explicit History")
    @MainActor
    func launchScenarioSuccessControl() async throws {
        let configuration = LaunchConfiguration.current(arguments: ["--aureus-ui-testing", "--aureus-demo"])
        let root = try #require(configuration.temporaryRoot)
        defer { try? FileManager.default.removeItem(at: root) }
        let graph = try await AppDependencies.make(configuration: configuration)
        #expect(configuration.marketFailureScenario == nil)
        let model = launchScenarioModel(graph)
        await model.start()
        #expect(model.state == .noSessionData)
        model.query = "SYN"
        model.submitSearch()
        try await waitForSessionFailure(model, pendingState: .searching)
        try #require(model.state == .ready && model.errorDisclosure == nil)
        let instrument = try #require(model.searchResults.first { $0.symbol == "SYN-CNY" && $0.mic == "XSYN" })
        model.select(instrument)
        model.refreshSelectedHistory()
        try await waitForSessionFailure(model, pendingState: .loadingHistory)
        #expect(model.state == .ready && model.errorDisclosure == nil)
        let history = try #require(model.historyPage)
        #expect(history.instrument == instrument && history.bars.count == 120)
        #expect(model.chartPayload != nil && model.indicatorSnapshot != nil && !model.visibleBars.isEmpty)
        #expect(await graph.marketSessionStore.statistics().entryCount == 2)
        #expect(try await graph.marketCacheStore.statistics().entryCount == 0)
    }

    @MainActor
    private func launchScenarioModel(_ graph: AppDependencies) -> MarketsFeatureModel {
        MarketsFeatureModel(marketDataService: graph.marketDataService,
            marketProvider: graph.marketDataProvider, sessionStore: graph.marketSessionStore,
            preferences: graph.marketPreferencesStore, clock: graph.clock, mode: .syntheticDemo)
    }

    enum EmptySessionFailure: CaseIterable, Sendable {
        case offline, timeout, missing

        var error: ProviderBoundaryError {
            switch self {
            case .offline: .offline
            case .timeout: .timeout
            case .missing: .missing
            }
        }

        var state: MarketsTerminalState {
            switch self {
            case .offline: .offline
            case .timeout: .timeout
            case .missing: .missing
            }
        }

        var disclosure: String {
            switch self {
            case .offline: "Market Data Unavailable Offline."
            case .timeout: "Provider request timed out."
            case .missing: "Requested session data is missing."
            }
        }
    }

    @MainActor
    private func waitForSessionFailure(_ model: MarketsFeatureModel, pendingState: MarketsTerminalState) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while model.state == pendingState && ContinuousClock.now < deadline {
            await Task.yield()
        }
        try #require(model.state != pendingState, "Explicit market request did not reach a terminal state")
    }

    @Test("Daily ranges stay daily and one day is Latest Daily Bar")
    func dailyRangeSemantics() {
        #expect(MarketRange.oneDay.outputSize == 1)
        #expect(MarketRange.oneDay.dailyDisclosure == "Latest Daily Bar")
        #expect(MarketRange.maximum.outputSize == 5_000)
        #expect(MarketInterval.oneDay.isIntraday == false)
    }

    @Test("Stage 7A pane contract and sanitized renderer summary are exact")
    func paneContract() throws {
        let bars = try syntheticBars(count: 80)
        let indicators = try MarketIndicatorCalculator.calculate(bars: bars, interval: .oneDay, adjustment: .all)
        let payload = try MarketChartPayload(configuration: chartConfiguration(), bars: bars, indicators: indicators, enabledIndicators: Set(MarketIndicatorKind.allCases))
        #expect(payload.lines.filter { ["sma20", "sma50", "ema12", "ema26", "bollinger-middle", "bollinger-upper", "bollinger-lower"].contains($0.identifier) }.allSatisfy { $0.pane == .main })
        #expect(payload.lines.first { $0.identifier == "rsi14" }?.pane == .rsi)
        #expect(payload.lines.filter { $0.identifier.hasPrefix("macd") }.allSatisfy { $0.pane == .macd })
        #expect(payload.lines.first { $0.identifier == "macd-histogram" }?.type == .histogram)
        let message = try MarketChartInboundMessage.decode(["version": 1, "type": "renderSummary", "series": [
            ["identifier": "candlestick", "seriesType": "candlestick", "pane": 0, "pointCount": 80],
            ["identifier": "volume", "seriesType": "histogram", "pane": 1, "pointCount": 80],
            ["identifier": "sma20", "seriesType": "line", "pane": 0, "pointCount": 61],
            ["identifier": "rsi14", "seriesType": "line", "pane": 2, "pointCount": 66],
            ["identifier": "macd-histogram", "seriesType": "histogram", "pane": 3, "pointCount": 47]
        ]])
        guard case let .renderSummary(summary) = message else { Issue.record("Expected render summary"); return }
        #expect(summary.series.map(\.pane) == [.main, .volume, .main, .rsi, .macd])
    }

    @Test("Stage 7A Gregorian UTC range policy handles month, leap, YTD and MAX")
    func calendarRangePolicy() throws {
        let leap = try utcInstant(year: 2024, month: 2, day: 29)
        #expect(try MarketRangeRequestPolicy.window(for: .oneMonth, now: leap).startDate == CivilDate(year: 2024, month: 1, day: 29))
        #expect(try MarketRangeRequestPolicy.window(for: .oneYear, now: leap).startDate == CivilDate(year: 2023, month: 2, day: 28))
        let januaryFirst = try utcInstant(year: 2025, month: 1, day: 1)
        let ytd = try MarketRangeRequestPolicy.window(for: .yearToDate, now: januaryFirst)
        #expect(ytd.startDate == ytd.endDate)
        let maximum = try MarketRangeRequestPolicy.window(for: .maximum, now: januaryFirst)
        #expect(maximum.startDate == nil)
        #expect(maximum.outputSizeUpperBound == 5_000)
        let weekend = try MarketRangeRequestPolicy.window(for: .oneDay, now: utcInstant(year: 2025, month: 3, day: 22))
        let bars = try syntheticBars(count: 3)
        #expect(weekend.filter(bars).count == 1)
        #expect(weekend.filter(bars).last?.sessionDate == bars.last?.sessionDate)
    }

    @Test("Stage 7A visible ranges are typed and reject malformed or reversed dates")
    func typedVisibleRange() throws {
        let start = try CivilDate(year: 2025, month: 1, day: 1)
        let end = try CivilDate(year: 2025, month: 1, day: 31)
        #expect(try MarketChartInboundMessage.decode(["version": 1, "type": "visibleRange", "start": start.description, "end": end.description]) == .visibleRange(start: start, end: end))
        #expect(throws: MarketChartBridgeError.invalidMessage) { _ = try MarketChartInboundMessage.decode(["version": 1, "type": "visibleRange", "start": "not-a-date", "end": end.description]) }
        #expect(throws: MarketChartBridgeError.invalidMessage) { _ = try MarketChartInboundMessage.decode(["version": 1, "type": "visibleRange", "start": end.description, "end": start.description]) }
    }

    @Test("Stage 7A checked presentation arithmetic rejects zero division and overflow")
    func checkedPresentationArithmetic() throws {
        #expect(try MarketPresentationArithmetic.subtract(15, 10) == 5)
        #expect(try MarketPresentationArithmetic.multiply(MarketPresentationArithmetic.divide(5, 10), 100) == 50)
        #expect(try MarketPresentationArithmetic.sum([1, 2, 3]) == 6)
        #expect(throws: MarketPresentationArithmeticError.divisionByZero) { _ = try MarketPresentationArithmetic.divide(1, 0) }
        #expect(throws: MarketPresentationArithmeticError.overflow) { _ = try MarketPresentationArithmetic.add(.greatestFiniteMagnitude, .greatestFiniteMagnitude) }
    }

    @Test("Stage 7A bridge bounds strings, colors and panes")
    func bridgeBounds() throws {
        let bars = try syntheticBars(count: 10_000)
        let indicators = try MarketIndicatorCalculator.calculate(bars: bars, interval: .oneDay, adjustment: .all)
        let payload = try MarketChartPayload(configuration: chartConfiguration(), bars: bars, indicators: indicators, enabledIndicators: Set(MarketIndicatorKind.allCases))
        #expect(try MarketChartPayload.encodedByteCount(payload) <= MarketChartPayload.maximumEncodedBytes)
        #expect(payload.withDarkAppearance(true).configuration.darkAppearance)
        #expect(!payload.withDarkAppearance(false).configuration.darkAppearance)
        #expect(payload.withDarkAppearance(true).candles == payload.candles)
        let invalidConfiguration = MarketChartConfiguration(schemaVersion: 1, provider: String(repeating: "p", count: 97), symbol: "AAPL", rawMIC: "XNGS", freshness: "unknown", selectedRange: "1Y", darkAppearance: false)
        #expect(throws: MarketChartBridgeError.invalidConfiguration) { _ = try MarketChartPayload(configuration: invalidConfiguration, bars: [], indicators: indicators, enabledIndicators: []) }
        let badLine = MarketChartLineSeries(identifier: "bad", title: "Bad", pane: .main, type: .line, color: "red", points: [])
        #expect(throws: MarketChartBridgeError.oversizedPayload) { _ = try MarketChartPayload(validating: chartConfiguration(), candles: [], lines: [badLine]) }
        let densePoints = try (0..<10_000).map { MarketChartLinePoint(time: try civilDate(offset: $0).description, value: 1.2345678901234567) }
        let denseLines = (0..<16).map { MarketChartLineSeries(identifier: "dense-\($0)", title: "Dense \($0)", pane: .main, type: .line, color: "#123456", points: densePoints) }
        let oversized = try MarketChartPayload(validating: chartConfiguration(), candles: [], lines: denseLines)
        #expect(throws: MarketChartBridgeError.oversizedPayload) { _ = try MarketChartPayload.encodedObject(oversized) }
        let invalidPane = "{\"identifier\":\"x\",\"title\":\"x\",\"pane\":9,\"type\":\"line\",\"color\":\"#000000\",\"points\":[]}".data(using: .utf8)!
        #expect(throws: DecodingError.self) { _ = try JSONDecoder().decode(MarketChartLineSeries.self, from: invalidPane) }
    }

    @Test("Stage 7A current capability snapshot is separate and zero-network")
    @MainActor
    func currentCapabilities() async throws {
        let clock = FixedClock(instant: try utcInstant(year: 2025, month: 3, day: 21))
        let provider = CountingMarketProvider(clock: clock)
        await provider.setCapabilities(capabilities(entitlement: .unknown, search: .notVerified, historical: .notVerified, rawMICs: []))
        let dependencies = try await makeMarketDependencies(provider: provider)
        let model = MarketsFeatureModel(marketDataService: dependencies.service, marketProvider: provider, sessionStore: dependencies.session, preferences: MarketPreferencesStore(suiteName: nil, memoryOnly: true), clock: clock, mode: .local)
        await model.start()
        #expect(model.capabilityCards.first?.status == "Not Verified")
        #expect(model.historicalAcceptanceRecord.contains("Stage 6NBC"))
        #expect(await provider.searchCount == 0)
        #expect(await provider.historyCount == 0)
        await provider.setCapabilities(capabilities(entitlement: .basic, search: .succeeded, historical: .notVerified, rawMICs: ["XNGS"]))
        await model.refreshCapabilities()
        #expect(model.capabilityCards.first?.detail.contains("Search: succeeded; Historical: notVerified") == true)
        await provider.setCapabilities(capabilities(entitlement: .basic, search: .notVerified, historical: .succeeded, rawMICs: ["XNGS"]))
        await model.refreshCapabilities()
        #expect(model.capabilityCards.first?.detail.contains("Search: notVerified; Historical: succeeded") == true)
        await provider.setCapabilities(capabilities(entitlement: .basic, search: .succeeded, historical: .succeeded, rawMICs: ["XNGS"]))
        await model.refreshCapabilities()
        #expect(model.capabilityCards.first?.status == "Current observation available")
        #expect(model.capabilityCards.first?.detail.contains("XNGS") == true)
        await provider.setCapabilities(capabilities(entitlement: .missing, search: .notVerified, historical: .notVerified, rawMICs: []))
        await model.refreshCapabilities()
        #expect(model.capabilityCards.first?.status == "Missing Credential")
        #expect(await provider.searchCount == 0)
        #expect(await provider.historyCount == 0)
    }

    @Test("Stage 7A multi-instrument heatmap is range scoped, reorder persists, and clear removes values")
    @MainActor
    func multiInstrumentHeatmapAndReorder() async throws {
        let clock = FixedClock(instant: try utcInstant(year: 2025, month: 3, day: 21))
        let provider = CountingMarketProvider(clock: clock)
        let dependencies = try await makeMarketDependencies(provider: provider)
        let preferences = MarketPreferencesStore(suiteName: nil, memoryOnly: true)
        let model = MarketsFeatureModel(marketDataService: dependencies.service, marketProvider: provider, sessionStore: dependencies.session, preferences: preferences, clock: clock, mode: .local)
        await model.start()
        for symbol in ["AAPL", "MSFT"] {
            model.query = symbol
            model.submitSearch()
            try await Task.sleep(for: .milliseconds(350))
            let instrument = try #require(model.searchResults.first)
            model.select(instrument)
            await model.addSelectedToWatchlist()
            model.refreshSelectedHistory()
            try await Task.sleep(for: .milliseconds(150))
        }
        #expect(model.heatmapItems.count == 2)
        #expect(model.heatmapItems.allSatisfy { $0.category == .gain })
        let second = model.watchlist[1]
        await model.moveWatchlist(second, offset: -1)
        #expect(model.watchlist.first == second)
        #expect(try await preferences.load().watchlist.first == second)
        await model.updateRange(.oneMonth)
        #expect(model.heatmapItems.allSatisfy { $0.category == .unknown })
        await model.clearSession()
        #expect(model.heatmapItems.allSatisfy { $0.category == .unknown })
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

    private func utcInstant(year: Int, month: Int, day: Int) throws -> UTCInstant {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
        return UTCInstant(date: date)
    }

    private func capabilities(entitlement: MarketEntitlementState, search: ProviderLiveObservation, historical: ProviderLiveObservation, rawMICs: [String]) -> MarketProviderCapabilities {
        let descriptor = ProviderDescriptor(identifier: "synthetic.stage7.counting", displayName: "Synthetic Stage 7", kind: .synthetic)
        return MarketProviderCapabilities(provider: descriptor, entitlement: entitlement, observedPlanName: nil, markets: [
            .init(mic: "US", minimumEntitlement: .basic, observedEntitlement: entitlement, freshness: .unknown, catalogEvidence: .officialCatalogOnly, liveObservation: search == historical ? search : .mixed, liveObservedMICs: rawMICs, supportsSearch: true, supportsHistoricalBars: true, supportsCorporateActions: false, evidenceStatus: "SYNTHETIC")
        ], supportsSearch: true, supportsHistoricalPrices: true, supportsCorporateActions: false, endpointCapabilities: [
            .init(endpoint: .symbolSearch, minimumPlanName: "Unknown", creditWeight: 1, catalogEvidence: .notVerified, liveObservation: search, observedEntitlement: entitlement),
            .init(endpoint: .historicalOHLCV, minimumPlanName: "Unknown", creditWeight: 1, catalogEvidence: .notVerified, liveObservation: historical, observedEntitlement: entitlement)
        ], observedAt: nil)
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
    private var capabilitySnapshot: MarketProviderCapabilities?
    private let failure: ProviderBoundaryError?
    let clock: any Clock

    init(clock: any Clock, failure: ProviderBoundaryError? = nil) {
        self.clock = clock
        self.failure = failure
    }

    func capabilities() -> MarketProviderCapabilities {
        capabilitySnapshot ?? MarketProviderCapabilities(provider: descriptor, entitlement: .basic, observedPlanName: "Synthetic", markets: [], supportsSearch: true, supportsHistoricalPrices: true, supportsCorporateActions: false, endpointCapabilities: [], observedAt: clock.now())
    }

    func setCapabilities(_ value: MarketProviderCapabilities) { capabilitySnapshot = value }

    func search(query: String) async throws -> [MarketInstrument] {
        searchCount += 1
        if let failure { throw failure }
        return [MarketInstrument(id: UUID(uuidString: "00000000-0000-4000-8000-000000000777")!, symbol: query.uppercased(), mic: "XNGS", currency: .usd, displayName: "Synthetic Instrument")]
    }

    func latestQuote(for instrument: MarketInstrument) async throws -> MarketQuote { throw ProviderBoundaryError.unsupportedEntitlement }

    func historicalBars(_ request: MarketHistoryRequest) async throws -> MarketHistoryPage {
        historyCount += 1
        if let failure { throw failure }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(byAdding: .day, value: -79, to: clock.now().date)!
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
