import Foundation
import GRDB
import Testing
@testable import Aureus

@MainActor
@Suite("General Settings preferences and local cache status")
struct GeneralSettingsTests {
    private let now = UTCInstant(millisecondsSince1970: 1_768_435_200_000)

    @Test("Oldest entry uses fixed UTC and preserves nil and epoch zero")
    func oldestEntryDisplay() {
        #expect(SettingsFeatureModel.oldestEntryLabel(for: nil) == "Oldest cache entry: None")
        #expect(SettingsFeatureModel.oldestEntryLabel(for: UTCInstant(millisecondsSince1970: 0))
            == "Oldest cache entry: 1970-01-01 00:00:00.000 UTC")
        #expect(SettingsFeatureModel.oldestEntryLabel(for: now)
            == "Oldest cache entry: 2026-01-15 00:00:00.000 UTC")
    }

    @Test("Cache audit requires all three explicit arguments", arguments: Array(0...7))
    func cacheAuditArguments(mask: Int) {
        let flags = ["--aureus-ui-testing", "--aureus-demo", "--aureus-settings-cache-audit"]
        let arguments = flags.enumerated().compactMap { index, flag in
            mask & (1 << index) != 0 ? flag : nil
        }
        let configuration = LaunchConfiguration.current(arguments: arguments)
        #expect(configuration.settingsCacheAuditEnabled == (mask == 7))
        #expect(configuration.usesTemporaryStores == (mask & 3 != 0))
        #expect((configuration.temporaryRoot != nil) == (mask & 3 != 0))
        #expect(configuration.dataMode == (mask & 2 != 0 ? .syntheticDemo : .local))
    }

    @Test("Opt-in isolated cache audit seeds legacy metadata, capacity and reset preserve Permanent")
    func cacheAuditGraph() async throws {
        let configuration = LaunchConfiguration.current(arguments: [
            "--aureus-ui-testing", "--aureus-demo", "--aureus-settings-cache-audit"
        ])
        let root = try #require(configuration.temporaryRoot)
        defer { try? FileManager.default.removeItem(at: root) }
        let graph = try await AppDependencies.make(configuration: configuration)
        try await graph.wealthStore.insertIsolationSentinel(id: "cache-audit", name: "Synthetic Cache Audit Sentinel")
        let records = try await graph.wealthStore.fetchWealthContainers()
        let settings = model(graph)
        await settings.load()
        let initial = try #require(settings.cacheStatistics)
        #expect(initial.entryCount == 2 && initial.currentBytes == 768)
        #expect(initial.maximumBytes == 512 * CachePolicyConfiguration.mebibyte)
        #expect(initial.percentageBasisPoints == 0)
        #expect(initial.oldestEntry == now)
        #expect(initial.lastCleanupAt == now)
        #expect(initial.lastCleanupResult == "sessionOnlyPolicy: removed 0 recoverable entries")
        #expect(initial.providerBreakdown == [MarketCacheProviderUsage(
            providerIdentifier: "synthetic.stage2.market", bytes: 768, entryCount: 2)])
        #expect(settings.persistentFreshness.snapshot?.state == "Legacy only")
        #expect(settings.persistentFreshness.snapshot?.legacyCount == 2)
        #expect(settings.persistentFreshness.snapshot?.classifiedCount == 0)
        settings.selectedMaximumMiB = 256
        await settings.applyMaximum()
        let reduced = try #require(settings.cacheStatistics)
        #expect(reduced.maximumBytes == 256 * CachePolicyConfiguration.mebibyte)
        #expect(reduced.currentBytes == initial.currentBytes && reduced.entryCount == initial.entryCount)
        #expect(reduced.oldestEntry == initial.oldestEntry && reduced.providerBreakdown == initial.providerBreakdown)
        #expect(reduced.lastCleanupResult == "capacityChange: removed 0 recoverable entries")
        #expect(try await graph.wealthStore.isolationSentinels() == ["Synthetic Cache Audit Sentinel"])
        #expect(try await graph.wealthStore.fetchWealthContainers() == records)
        await settings.resetCache()
        let reset = try #require(settings.cacheStatistics)
        #expect(reset.maximumBytes == 512 * CachePolicyConfiguration.mebibyte)
        #expect(reset.currentBytes == 0 && reset.entryCount == 0 && reset.percentageBasisPoints == 0)
        #expect(reset.oldestEntry == nil && reset.providerBreakdown.isEmpty)
        #expect(reset.lastCleanupAt == nil && reset.lastCleanupResult == nil)
        let returned = model(graph)
        await returned.load()
        #expect(returned.cacheStatistics == reset)
        #expect(returned.persistentFreshness.snapshot?.state == "Empty")
        #expect(settings.errorMessage == nil && returned.errorMessage == nil)
        #expect(try await graph.wealthStore.isolationSentinels() == ["Synthetic Cache Audit Sentinel"])
        #expect(try await graph.wealthStore.fetchWealthContainers() == records)

        let ordinaryRoot = try directory()
        defer { try? FileManager.default.removeItem(at: ordinaryRoot) }
        let ordinaryConfiguration = LaunchConfiguration(dataMode: .syntheticDemo,
            usesTemporaryStores: true, temporaryRoot: ordinaryRoot)
        #expect(!ordinaryConfiguration.settingsCacheAuditEnabled)
        let ordinary = try await AppDependencies.make(configuration: ordinaryConfiguration)
        #expect(try await ordinary.marketCacheStore.statistics().entryCount == 0)
        #expect(try await ordinary.marketCacheStore.statistics().oldestEntry == nil)
    }

    @Test("Preferences save both fields, reopen, and isolate random domains and memory")
    func preferencePersistence() throws {
        let suite = "Aureus-GeneralSettings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = try GeneralPreferencesStore(suiteName: suite)
        #expect(store.load() == .defaults)
        #expect(defaults.object(forKey: GeneralPreferencesStore.storageKey) == nil)
        store.setNewWealthCurrency(.usd)
        store.setGroupWealthAmounts(false)
        let reopened = try GeneralPreferencesStore(suiteName: suite)
        #expect(reopened.load().newWealthCurrency == .usd)
        #expect(!reopened.load().groupWealthAmounts)
        reopened.setGroupWealthAmounts(true)
        #expect(try GeneralPreferencesStore(suiteName: suite).load().newWealthCurrency == .usd)
        reopened.setNewWealthCurrency(.cny)
        #expect(try GeneralPreferencesStore(suiteName: suite).load().groupWealthAmounts)
        let raw = try #require(defaults.data(forKey: GeneralPreferencesStore.storageKey))
        let fields = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        #expect(Set(fields.keys) == ["version", "newWealthCurrency", "groupWealthAmounts"])
        let memory = GeneralPreferencesStore()
        memory.setNewWealthCurrency(.usd)
        memory.setGroupWealthAmounts(false)
        #expect(defaults.data(forKey: GeneralPreferencesStore.storageKey) == raw)
        #expect(GeneralPreferencesStore().load() == .defaults)
        #expect(throws: GeneralPreferencesError.invalidSuite) { _ = try GeneralPreferencesStore(suiteName: " ") }
    }

    @Test("Invalid persisted data falls back without writing; valid fields survive updates",
          arguments: ["{\"version\":1}",
                      "{\"version\":1,\"newWealthCurrency\":\"EUR\",\"groupWealthAmounts\":false}",
                      "{\"version\":1,\"newWealthCurrency\":\"USD\"}",
                      "{\"version\":99,\"newWealthCurrency\":\"USD\",\"groupWealthAmounts\":false}",
                      "broken", "{\"version\":1,\"groupWealthAmounts\":\"invalid\"}"])
    func preferenceFallback(raw: String) throws {
        let suite = "Aureus-GeneralSettings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = Data(raw.utf8)
        defaults.set(data, forKey: GeneralPreferencesStore.storageKey)
        let store = try GeneralPreferencesStore(suiteName: suite)
        let expectedCurrency: CurrencyCode = raw == "{\"version\":1,\"newWealthCurrency\":\"USD\"}" ? .usd : .cny
        let expectedGrouping = !raw.contains("EUR")
        #expect(store.load().newWealthCurrency == expectedCurrency)
        #expect(store.load().groupWealthAmounts == expectedGrouping)
        #expect(defaults.data(forKey: GeneralPreferencesStore.storageKey) == data)
        store.setNewWealthCurrency(.usd)
        #expect(store.load().groupWealthAmounts == expectedGrouping)
        #expect(try GeneralPreferencesStore(suiteName: suite).load() == store.load())
    }

    @Test("Same graph Settings preferences affect new drafts, not open drafts or stored facts")
    func wealthConsumption() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let graph = try await AppDependencies.make(configuration: LaunchConfiguration(
            dataMode: .syntheticDemo, usesTemporaryStores: true, temporaryRoot: root))
        let otherRoot = try directory()
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        let other = try await AppDependencies.make(configuration: LaunchConfiguration(
            dataMode: .local, usesTemporaryStores: true, temporaryRoot: otherRoot))
        let before = try await graph.wealthStore.fetchWealthContainers()
        let csv = LedgerCSV.export(try await graph.wealthStore.fetchLedgerEntries())
        let settings = model(graph)
        let wealth = WealthFeatureModel(store: graph.wealthStore, clock: graph.clock,
            generalPreferences: graph.generalPreferencesStore)
        await settings.load()
        await wealth.loadIfNeeded()
        let summary = wealth.summary
        wealth.beginAdd()
        #expect(wealth.editor?.initialDraft.currency == .cny)
        let opened = try #require(wealth.editor)
        settings.newWealthCurrency = .usd
        settings.groupWealthAmounts = false
        #expect(wealth.editor == opened)
        #expect(wealth.editor?.initialDraft.currency == .cny)
        wealth.editor = nil
        wealth.beginAdd()
        var draft = try #require(wealth.editor?.initialDraft)
        #expect(draft.currency == .usd)
        draft.name = "Synthetic Preference Draft"
        draft.amount = "1234.56"
        #expect(throws: WealthEditorError.invalidFX) {
            _ = try draft.makeRecord(existing: nil, today: CivilDate(canonical: "2026-01-15"), now: now)
        }
        draft.fxRate = "7"
        let usd = try draft.makeRecord(existing: nil, today: CivilDate(canonical: "2026-01-15"), now: now)
        #expect(usd.originalValue == Money(minorUnits: 123456, currency: .usd))
        #expect(usd.convertedCNYValue == Money(minorUnits: 864192, currency: .cny))
        draft.currency = .cny
        #expect(try draft.makeRecord(existing: nil, today: CivilDate(canonical: "2026-01-15"), now: now)
            .convertedCNYValue == Money(minorUnits: 123456, currency: .cny))
        for record in before {
            wealth.selection = record.id
            wealth.beginEdit()
            #expect(wealth.editor?.initialDraft == WealthEditorDraft(existing: record))
            #expect(wealth.editor?.initialDraft.currency == record.container.primaryCurrency)
        }
        #expect(!wealth.generalPreferences.snapshot.groupWealthAmounts)
        #expect(model(graph).newWealthCurrency == .usd)
        #expect(other.generalPreferencesStore.load() == .defaults)
        await wealth.reload()
        #expect(wealth.records == before)
        #expect(wealth.summary == summary)
        #expect(LedgerCSV.export(try await graph.wealthStore.fetchLedgerEntries()) == csv)
    }

    @Test("Wealth display grouping is local, two-place, Decimal-based and locale aware",
          arguments: [Int64(0), -123456, 123456789012345])
    func moneyDisplay(minor: Int64) {
        let money = Money(minorUnits: minor, currency: .usd)
        let us = Locale(identifier: "en_US"), de = Locale(identifier: "de_DE")
        let expectedUS: String
        let expectedDE: String
        switch minor {
        case 0: expectedUS = "0.00"; expectedDE = "0,00"
        case -123456: expectedUS = "-1,234.56"; expectedDE = "-1.234,56"
        default: expectedUS = "1,234,567,890,123.45"; expectedDE = "1.234.567.890.123,45"
        }
        #expect(WealthDisplay.money(money, grouping: true, locale: us) == "USD " + expectedUS)
        #expect(WealthDisplay.money(money, grouping: false, locale: us) == "USD " + expectedUS.replacingOccurrences(of: ",", with: ""))
        #expect(WealthDisplay.money(money, grouping: true, locale: de) == "USD " + expectedDE)
        #expect(WealthDisplay.money(money, grouping: false, locale: de) == "USD " + expectedDE.replacingOccurrences(of: ".", with: ""))
        #expect(WealthDisplay.money(money) == "USD " + expectedUS)
        #expect(WealthDisplay.money(Money(minorUnits: minor, currency: .cny), grouping: true, locale: us) == "CNY " + expectedUS)
        #expect(money.minorUnits == minor)
        #expect(WealthDisplay.number(Decimal(string: "1.12345678")!, fractionDigits: 8) == "1.12345678")
        #expect(NSDecimalNumber(decimal: money.decimal).stringValue.contains(",") == false)
    }

    @Test("TTL snapshots use each store's exact before/equal/after lookup boundary", arguments: [-1, 0, 1])
    func expiryBoundary(offset: Int) async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try MarketCacheStore(databaseURL: root.appendingPathComponent("cache.sqlite"))
        let entry = try diskEntry(key: "boundary", expires: now)
        try await cache.store(entry, authorization: .authorized)
        let session = TransientMarketSessionStore()
        let generation = await session.generation(for: "synthetic")
        try await session.store(providerIdentifier: "synthetic", logicalKey: "boundary", payload: .search([]),
            fetchedAt: UTCInstant(millisecondsSince1970: now.millisecondsSince1970 - TransientMarketSessionDataType.search.timeToLiveMilliseconds), generation: generation)
        let instant = UTCInstant(millisecondsSince1970: now.millisecondsSince1970 + Int64(offset))
        let disk = try await cache.freshnessSnapshot(now: instant)
        let memory = await session.freshnessSnapshot(now: instant)
        #expect(disk.observedAt == instant && memory.observedAt == instant)
        #expect(disk.freshCount == (offset <= 0 ? 1 : 0))
        #expect(memory.freshCount == (offset < 0 ? 1 : 0))
        #expect(disk.expiredCount == 1 - disk.freshCount)
        #expect(memory.expiredCount == 1 - memory.freshCount)
        let lookup = try await cache.lookup(providerIdentifier: entry.providerIdentifier,
            logicalKey: entry.logicalKey, dataType: entry.dataType, now: instant, allowStale: true)
        #expect(lookup == (offset <= 0 ? .fresh(entry) : .stale(entry)))
        let memoryLookup = try await session.lookup(providerIdentifier: "synthetic", logicalKey: "boundary", dataType: .search, now: instant)
        switch memoryLookup {
        case .fresh: #expect(offset < 0)
        case .stale: #expect(offset >= 0)
        case .missing: Issue.record("Expected an existing session entry")
        }
    }

    @Test("Disk metadata counts include both legacy tables without decoding or mutating rows")
    func diskMetadataReadOnly() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try MarketCacheStore(databaseURL: root.appendingPathComponent("cache.sqlite"))
        #expect(try await cache.freshnessSnapshot(now: now).state == "Empty")
        try await cache.seedSyntheticCache()
        #expect(try await cache.freshnessSnapshot(now: now).legacyCount == 2)
        #expect(try await cache.freshnessSnapshot(now: now).state == "Legacy only")
        let fresh = try diskEntry(key: "fresh", expires: UTCInstant(millisecondsSince1970: now.millisecondsSince1970 + 1))
        try await cache.store(fresh, authorization: .authorized)
        try await cache.store(diskEntry(key: "expired", expires: UTCInstant(millisecondsSince1970: now.millisecondsSince1970 - 1)), authorization: .authorized)
        // Leave an access pending, then observe that snapshot does not flush it.
        _ = try await cache.lookup(providerIdentifier: fresh.providerIdentifier, logicalKey: fresh.logicalKey,
            dataType: fresh.dataType, now: now, allowStale: true)
        let queue = try DatabaseQueueFactory.open(at: cache.databaseURL)
        // Even an opaque payload is counted from metadata, without decoding it.
        try await queue.write { db in try db.execute(sql: "UPDATE market_cache_entries SET payload = X'FF'") }
        let before = try await databaseState(queue)
        let value = try await cache.freshnessSnapshot(now: now)
        #expect(value.freshCount == 1 && value.expiredCount == 1 && value.legacyCount == 2)
        #expect(value.totalCount == 4 && value.classifiedCount == 2 && value.state == "Mixed TTL")
        #expect(try await databaseState(queue) == before)
        #expect(value.totalCount == (try await cache.cachedRowCount()))
        let label = CacheFreshnessStatus.available(value).label(for: "Disk")
        #expect(label.contains("4 total entries; 2 TTL-classified; 1 within TTL; 1 expired; 2 legacy."))
        #expect(label.contains("Legacy entries do not establish Twelve Data V1 offline availability."))
        #expect(label.contains("Expired entries require existing stale disclosure and fallback rules."))
        try queue.close()
    }

    @Test("Session snapshot preserves generation, payload counts and LRU eviction order")
    func sessionReadOnly() async throws {
        let session = TransientMarketSessionStore()
        let generation = await session.generation(for: "synthetic")
        #expect(await session.freshnessSnapshot(now: now).state == "Empty")
        for key in ["a", "b"] {
            try await session.store(providerIdentifier: "synthetic", logicalKey: key, payload: .search([]), fetchedAt: now, generation: generation)
        }
        let before = await session.statistics()
        let far = UTCInstant(millisecondsSince1970: now.millisecondsSince1970 + TransientMarketSessionDataType.search.timeToLiveMilliseconds)
        #expect(await session.freshnessSnapshot(now: far).state == "Expired")
        #expect(await session.statistics() == before)
        #expect(await session.generation(for: "synthetic") == generation)
        _ = try await session.updateMaximumBytes(before.accountedBytes / 2)
        #expect(try await session.lookup(providerIdentifier: "synthetic", logicalKey: "a", dataType: .search, now: now) == .missing)
        guard case let .fresh(value) = try await session.lookup(providerIdentifier: "synthetic", logicalKey: "b", dataType: .search, now: now) else {
            Issue.record("Snapshot must not change LRU order"); return
        }
        #expect(value.payload == .search([]) && value.fetchedAt == now)
    }

    @Test("Settings refresh, Clear, Remove and Reset use local snapshots and preserve Permanent sentinel")
    func statusLifecycle() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let graph = try await AppDependencies.make(configuration: LaunchConfiguration(dataMode: .local, usesTemporaryStores: true, temporaryRoot: root))
        try await graph.wealthStore.insertIsolationSentinel(id: UUID().uuidString, name: "Synthetic General Settings Sentinel")
        let model = model(graph)
        #expect(model.sessionFreshness == .notLoaded && model.persistentFreshness == .notLoaded)
        await model.load()
        #expect(model.sessionFreshness.snapshot?.totalCount == 0)
        let provider = graph.marketDataProvider.descriptor.identifier
        try await graph.marketSessionStore.store(providerIdentifier: provider, logicalKey: "status", payload: .search([]), fetchedAt: now, generation: await graph.marketSessionStore.generation(for: provider))
        try await graph.marketCacheStore.store(diskEntry(key: "expire", expires: now), authorization: .authorized)
        await model.refreshCacheStatus()
        #expect(model.sessionFreshness.snapshot?.freshCount == 1)
        #expect(model.persistentFreshness.snapshot?.freshCount == 1)
        await model.clearSessionMarketData()
        #expect(model.sessionFreshness.snapshot?.totalCount == 0)
        await model.removeExpired()
        #expect(model.persistentFreshness.snapshot?.totalCount == 0)
        await model.resetCache()
        #expect(model.cacheStatistics?.lastCleanupAt == nil)
        let reopened = self.model(graph)
        await reopened.load()
        #expect(reopened.persistentFreshness.snapshot?.totalCount == 0)
        #expect(reopened.cacheStatistics?.lastCleanupAt == nil)
        #expect(try await graph.wealthStore.isolationSentinels() == ["Synthetic General Settings Sentinel"])
        #expect(model.errorMessage == nil && reopened.errorMessage == nil)
    }

    @Test("Explicit metadata refresh never calls Provider and replaces stale success with unavailable")
    func unavailableAndNoProvider() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try MarketCacheStore(databaseURL: root.appendingPathComponent("cache.sqlite"))
        let session = TransientMarketSessionStore()
        let clock = FixedClock(instant: now)
        let provider = GeneralSettingsCountingProvider(clock: clock)
        let service = MarketDataService(marketProvider: provider, fxProvider: SyntheticFXRateProvider(clock: clock), cache: cache, sessionStore: session, clock: clock)
        let coordinator = ProviderCredentialCoordinator(credentialStore: InMemoryCredentialStore(), provider: provider, cache: cache, sessionStore: session, clock: clock)
        let model = SettingsFeatureModel(provider: provider, marketDataService: service, credentialCoordinator: coordinator, cache: cache, sessionStore: session, clock: clock)
        await model.refreshCacheStatus()
        #expect(await provider.callCount() == 0)
        #expect(model.persistentFreshness.snapshot?.totalCount == 0)
        let queue = try DatabaseQueueFactory.open(at: cache.databaseURL)
        try await queue.write { db in try db.execute(sql: "DROP TABLE market_cache_entries") }
        await model.refreshCacheStatus()
        #expect(model.persistentFreshness == .unavailable)
        #expect(model.persistentFreshness.snapshot == nil)
        #expect(model.persistentFreshness.label(for: "Disk") == "Disk: Unavailable. Local cache status could not be read.")
        #expect(CacheFreshnessStatus.notLoaded.label(for: "Disk") == "Disk: Not loaded. Local cache status has not been read.")
        #expect(await provider.callCount() == 0)
        try queue.close()
    }

    @Test("Only completed manual cache workflows emit finite diagnostics")
    func manualCacheDiagnostics() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let graph = try await AppDependencies.make(configuration: LaunchConfiguration(dataMode: .local, usesTemporaryStores: true, temporaryRoot: root))
        #expect(!graph.diagnostics.isEnabled)
        #expect(!(await graph.wealthStore.diagnostics.isEnabled))
        try await graph.wealthStore.insertIsolationSentinel(id: "diagnostic-sentinel", name: "Synthetic Private Account")
        let sink = RecordingDataLifecycleSink()
        let model = model(graph, diagnostics: sink.diagnostics)
        await model.load()
        await model.refreshCacheStatus()
        #expect(sink.events.isEmpty)
        await model.removeExpired()
        await model.clearSessionMarketData()
        await model.resetCache()
        model.selectedMaximumMiB = 256
        await model.applyMaximum()
        #expect(model.errorMessage == nil)
        #expect(sink.events == [
            .init(operation: .settingsRemoveExpiredWorkflow, outcome: .succeeded, errorCategory: .none),
            .init(operation: .settingsClearSessionWorkflow, outcome: .succeeded, errorCategory: .none),
            .init(operation: .settingsResetCacheWorkflow, outcome: .succeeded, errorCategory: .none),
            .init(operation: .settingsApplyMaximumWorkflow, outcome: .succeeded, errorCategory: .none)
        ])
        model.selectedMaximumMiB = Int.max
        await model.applyMaximum()
        #expect(model.errorMessage != nil)
        #expect(sink.events.count == 5)
        #expect(sink.events.last == .init(operation: .settingsApplyMaximumWorkflow, outcome: .failed, errorCategory: .cachePolicy))
        #expect(try await graph.marketCacheStore.statistics().maximumBytes == 256 * CachePolicyConfiguration.mebibyte)
        #expect(try await graph.wealthStore.isolationSentinels() == ["Synthetic Private Account"])
    }

    private func model(_ graph: AppDependencies, diagnostics: DataLifecycleDiagnostics = .disabled) -> SettingsFeatureModel {
        SettingsFeatureModel(provider: graph.marketDataProvider, marketDataService: graph.marketDataService,
            credentialCoordinator: graph.credentialCoordinator, cache: graph.marketCacheStore,
            sessionStore: graph.marketSessionStore, clock: graph.clock, generalPreferences: graph.generalPreferencesStore,
            diagnostics: diagnostics)
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Aureus-GeneralSettings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func diskEntry(key: String, expires: UTCInstant) throws -> MarketCacheEntry {
        try MarketCacheEntry(providerIdentifier: "synthetic.settings", logicalKey: key, dataType: .fxRate,
            payload: Data("synthetic".utf8), fetchedAt: UTCInstant(millisecondsSince1970: now.millisecondsSince1970 - 1000),
            expiresAt: expires, entitlementContext: "synthetic", freshness: .unknown)
    }

    private func databaseState(_ queue: DatabaseQueue) async throws -> [String] {
        try await queue.read { db in
            try String.fetchAll(db, sql: "SELECT id || ':' || last_accessed_at_ms || ':' || hex(payload) FROM market_cache_entries ORDER BY id")
            + String.fetchAll(db, sql: "SELECT key || ':' || COALESCE(integer_value, '') || ':' || COALESCE(text_value, '') FROM cache_metadata ORDER BY key")
        }
    }
}

private actor GeneralSettingsCountingProvider: MarketDataProvider {
    nonisolated let descriptor = ProviderDescriptor(identifier: "synthetic.settings.counted", displayName: "Synthetic", kind: .synthetic)
    private let clock: any Clock
    private var calls = 0
    init(clock: any Clock) { self.clock = clock }
    func callCount() -> Int { calls }
    func capabilities() async -> MarketProviderCapabilities {
        calls += 1
        return await SyntheticMarketDataProvider(scenario: .success, clock: clock).capabilities()
    }
    func validateCredential() throws -> ProviderUsageObservation { calls += 1; throw ProviderBoundaryError.missingCredential }
    func search(query: String) throws -> [MarketInstrument] { calls += 1; throw ProviderBoundaryError.missing }
    func latestQuote(for instrument: MarketInstrument) throws -> MarketQuote { calls += 1; throw ProviderBoundaryError.missing }
    func historicalBars(_ request: MarketHistoryRequest) throws -> MarketHistoryPage { calls += 1; throw ProviderBoundaryError.missing }
    func corporateActions(for instrument: MarketInstrument, from startDate: CivilDate?, through endDate: CivilDate?) throws -> [MarketCorporateAction] { calls += 1; throw ProviderBoundaryError.missing }
}
