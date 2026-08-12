import Foundation
import Testing
@testable import Aureus

private actor FXRecordingTransport: HTTPTransport {
    private var response: HTTPTransportResponse
    private var urls: [String] = []

    init(body: String, status: Int = 200) {
        response = HTTPTransportResponse(
            data: Data(body.utf8),
            statusCode: status,
            headers: [:]
        )
    }

    func data(for request: URLRequest) -> HTTPTransportResponse {
        urls.append(request.url?.absoluteString ?? "")
        return response
    }

    func requestedURLs() -> [String] { urls }
}

private actor OfflineFXProvider: FXRateProvider {
    nonisolated let descriptor = ProviderDescriptor(
        identifier: "synthetic.offline.fx",
        displayName: "Synthetic Offline FX",
        kind: .synthetic
    )
    private var calls = 0

    func rate(source: CurrencyCode, target: CurrencyCode, on date: CivilDate) throws -> ExchangeRate {
        calls += 1
        throw ProviderBoundaryError.offline
    }

    func callCount() -> Int { calls }
}

private actor IncrementalMarketProvider: MarketDataProvider {
    nonisolated let descriptor = ProviderDescriptor(
        identifier: "synthetic.incremental.market",
        displayName: "Synthetic Incremental Market",
        kind: .synthetic
    )
    let clock: any Clock

    init(clock: any Clock) {
        self.clock = clock
    }

    func capabilities() -> MarketProviderCapabilities {
        MarketProviderCapabilities(
            provider: descriptor,
            entitlement: .basic,
            observedPlanName: "Synthetic",
            markets: [],
            supportsSearch: true,
            supportsHistoricalPrices: true,
            supportsCorporateActions: true,
            observedAt: clock.now()
        )
    }

    func search(query: String) -> [MarketInstrument] { [] }

    func latestQuote(for instrument: MarketInstrument) throws -> MarketQuote {
        throw ProviderBoundaryError.missing
    }

    func historicalBars(_ request: MarketHistoryRequest) throws -> MarketHistoryPage {
        let currency = request.instrument.currency
        let first = try MarketOHLCVBar(
            sessionDate: try CivilDate(canonical: "2026-01-14"),
            openedAt: nil,
            open: MarketQuotePrice(coefficient: 20_000_000_000, quoteCurrency: currency),
            high: MarketQuotePrice(coefficient: 22_000_000_000, quoteCurrency: currency),
            low: MarketQuotePrice(coefficient: 19_000_000_000, quoteCurrency: currency),
            close: MarketQuotePrice(coefficient: 21_000_000_000, quoteCurrency: currency),
            volume: AssetQuantity(coefficient: 2_000_000_000),
            adjustment: request.adjustment,
            providerIdentifier: descriptor.identifier,
            fetchedAt: clock.now(),
            freshness: .endOfDay
        )
        let second = try MarketOHLCVBar(
            sessionDate: try CivilDate(canonical: "2026-01-15"),
            openedAt: nil,
            open: MarketQuotePrice(coefficient: 21_000_000_000, quoteCurrency: currency),
            high: MarketQuotePrice(coefficient: 23_000_000_000, quoteCurrency: currency),
            low: MarketQuotePrice(coefficient: 20_000_000_000, quoteCurrency: currency),
            close: MarketQuotePrice(coefficient: 22_000_000_000, quoteCurrency: currency),
            volume: AssetQuantity(coefficient: 3_000_000_000),
            adjustment: request.adjustment,
            providerIdentifier: descriptor.identifier,
            fetchedAt: clock.now(),
            freshness: .endOfDay
        )
        return MarketHistoryPage(
            instrument: request.instrument,
            bars: [first, second],
            nextEndDate: nil,
            sourceRevision: "synthetic-v2",
            providerIdentifier: descriptor.identifier
        )
    }

    func corporateActions(
        for instrument: MarketInstrument,
        from startDate: CivilDate?,
        through endDate: CivilDate?
    ) -> [MarketCorporateAction] { [] }
}

@Suite("Stage 6 Keychain and Frankfurter boundaries")
struct KeychainAndFXInfrastructureTests {
    private let now = UTCInstant(millisecondsSince1970: 1_768_435_200_000)

    @Test("Native Keychain supports synthetic save, read, rotation, and delete")
    func nativeKeychainLifecycle() async throws {
        let descriptor = CredentialDescriptor(
            providerIdentifier: "synthetic.stage6.keychain",
            accountIdentifier: UUID().uuidString
        )
        let store = KeychainCredentialStore(
            service: "com.aureus.wealthterminal.tests.\(UUID().uuidString)"
        )
        let first = Data("synthetic-key-one".utf8)
        let rotated = Data("synthetic-key-two".utf8)

        try await store.deleteCredential(for: descriptor)
        #expect(try await store.credential(for: descriptor) == nil)
        try await store.store(first, for: descriptor)
        #expect(try await store.credential(for: descriptor) == first)
        try await store.store(rotated, for: descriptor)
        #expect(try await store.credential(for: descriptor) == rotated)
        try await store.deleteCredential(for: descriptor)
        #expect(try await store.credential(for: descriptor) == nil)
    }

    @Test("Credential coordinator validates presence and purges only provider cache on delete")
    func credentialCoordinatorLifecycle() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = FixedClock(instant: now)
        let cache = try MarketCacheStore(databaseURL: root.appendingPathComponent("cache.sqlite"))
        let credentials = InMemoryCredentialStore()
        let provider = SyntheticMarketDataProvider(scenario: .success, clock: clock)
        let coordinator = ProviderCredentialCoordinator(
            credentialStore: credentials,
            provider: provider,
            cache: cache,
            clock: clock
        )

        await #expect(throws: ProviderBoundaryError.missingCredential) {
            _ = try await coordinator.validate()
        }
        await #expect(throws: CredentialStoreError.invalidCredential) {
            try await coordinator.save("short")
        }
        try await coordinator.save("synthetic-stage6-credential")
        #expect(try await coordinator.isConfigured())
        #expect(try await coordinator.validate().entitlement == .basic)

        let providerEntry = try cacheEntry(
            provider: provider.descriptor.identifier,
            key: "provider"
        )
        let unrelated = try cacheEntry(provider: "frankfurter.ecb", key: "fx")
        try await cache.store(providerEntry, authorization: .authorized)
        try await cache.store(unrelated, authorization: .authorized)
        _ = try await coordinator.deleteCredential()

        #expect(!(try await coordinator.isConfigured()))
        #expect(try await cache.lookup(
            providerIdentifier: provider.descriptor.identifier,
            logicalKey: "provider", dataType: .fxRate, now: now, allowStale: true
        ) == .missing)
        #expect(try await cache.lookup(
            providerIdentifier: "frankfurter.ecb",
            logicalKey: "fx", dataType: .fxRate, now: now, allowStale: true
        ) != .missing)
    }

    @Test("Injected credential failure remains typed and does not create cache state")
    func keychainFailureBoundary() async throws {
        let store = InMemoryCredentialStore()
        await store.setInjectedError(.injectedFailure)
        await #expect(throws: CredentialStoreError.injectedFailure) {
            try await store.store(
                Data("synthetic-credential".utf8),
                for: TwelveDataClient.credentialDescriptor
            )
        }
    }

    @Test("Frankfurter requests ECB-filtered v2 reference rates and derives USD to CNY")
    func frankfurterECBReference() async throws {
        let body = #"[{"date":"2026-01-16","base":"EUR","quote":"USD","rate":"1.2"},{"date":"2026-01-16","base":"EUR","quote":"CNY","rate":"7.2"}]"#
        let transport = FXRecordingTransport(body: body)
        let sleeper = RecordingProviderSleeperForFX()
        let provider = FrankfurterFXRateProvider(
            transport: transport,
            gate: ProviderRequestGate(
                maximumConcurrentRequests: 2,
                minuteLimit: 100,
                dailyLimit: nil,
                clock: FixedClock(instant: now),
                sleeper: sleeper
            ),
            clock: FixedClock(instant: now),
            sleeper: sleeper,
            jitter: ZeroRetryJitterSource(),
            baseURL: URL(string: "https://synthetic-fx.invalid")!
        )

        let rate = try await provider.rate(
            source: .usd,
            target: .cny,
            on: try CivilDate(canonical: "2026-01-18")
        )
        let urls = await transport.requestedURLs()

        #expect(rate.rate.coefficient == 60_000_000_000)
        #expect(rate.rate.sourceCurrency == .usd)
        #expect(rate.rate.targetCurrency == .cny)
        let expectedReferenceDate = try CivilDate(canonical: "2026-01-16")
        #expect(rate.referenceDate == expectedReferenceDate)
        #expect(rate.provenance == .derivedCrossRate)
        #expect(rate.freshness == .endOfDay)
        #expect(urls.count == 1)
        #expect(urls[0].contains("/v2/rates"))
        #expect(urls[0].contains("providers=ECB"))
        #expect(urls[0].contains("quotes=USD,CNY") || urls[0].contains("quotes=USD%2CCNY"))
    }

    @Test("CNY identity uses no HTTP request and invalid FX payload is rejected")
    func fxIdentityAndInvalidPayload() async throws {
        let transport = FXRecordingTransport(body: "[]")
        let sleeper = RecordingProviderSleeperForFX()
        let provider = FrankfurterFXRateProvider(
            transport: transport,
            gate: ProviderRequestGate(clock: FixedClock(instant: now), sleeper: sleeper),
            clock: FixedClock(instant: now),
            sleeper: sleeper,
            jitter: ZeroRetryJitterSource(),
            baseURL: URL(string: "https://synthetic-fx.invalid")!
        )
        let date = try CivilDate(canonical: "2026-01-15")
        let identity = try await provider.rate(source: .cny, target: .cny, on: date)
        #expect(identity.rate == .cnyIdentity)
        #expect(identity.provenance == .identity)
        #expect(await transport.requestedURLs().isEmpty)

        await #expect(throws: ProviderBoundaryError.invalidPayload) {
            _ = try await provider.rate(source: .usd, target: .cny, on: date)
        }
    }

    @Test("FX cache returns explicit stale provenance offline and an offline miss is missing")
    func fxStaleOffline() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try MarketCacheStore(databaseURL: root.appendingPathComponent("cache.sqlite"))
        let fx = OfflineFXProvider()
        let date = try CivilDate(canonical: "2026-01-15")
        let cached = ExchangeRate(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000006701")!,
            rate: try FXRate(
                coefficient: 71_250_000_000,
                sourceCurrency: .usd,
                targetCurrency: .cny
            ),
            referenceDate: date,
            fetchedAt: UTCInstant(millisecondsSince1970: now.millisecondsSince1970 - 90_000_000),
            providerIdentifier: fx.descriptor.identifier,
            provenance: .derivedCrossRate,
            freshness: .endOfDay
        )
        let payload = try JSONEncoder().encode(cached)
        let entry = try MarketCacheEntry(
            providerIdentifier: fx.descriptor.identifier,
            logicalKey: "fx|USD|CNY|2026-01-15",
            dataType: .fxRate,
            payload: payload,
            fetchedAt: cached.fetchedAt,
            entitlementContext: "public-ecb-reference",
            freshness: .endOfDay
        )
        try await cache.store(entry, authorization: .authorized)
        let service = MarketDataService(
            marketProvider: SyntheticMarketDataProvider(
                scenario: .success,
                clock: FixedClock(instant: now)
            ),
            fxProvider: fx,
            cache: cache,
            clock: FixedClock(instant: now),
            marketCacheAuthorization: .authorized
        )

        let stale = try await service.referenceRate(source: .usd, target: .cny, on: date)
        #expect(stale.rate == cached.rate)
        #expect(stale.freshness == .stale)

        await #expect(throws: ProviderBoundaryError.missing) {
            _ = try await service.referenceRate(
                source: .usd,
                target: .cny,
                on: try CivilDate(canonical: "2026-01-14")
            )
        }
    }

    @Test("Stale historical cache is incrementally merged without duplicate session dates")
    func incrementalOHLCVRefresh() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = FixedClock(instant: now)
        let cache = try MarketCacheStore(databaseURL: root.appendingPathComponent("cache.sqlite"))
        let provider = IncrementalMarketProvider(clock: clock)
        let instrument = MarketInstrument(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000006702")!,
            symbol: "SYN",
            mic: "XNAS",
            currency: .usd,
            displayName: "Synthetic Incremental Instrument"
        )
        let request = try MarketHistoryRequest(
            instrument: instrument,
            interval: .oneDay,
            adjustment: .all,
            startDate: try CivilDate(canonical: "2026-01-01"),
            endDate: try CivilDate(canonical: "2026-01-15")
        )
        let oldBar = try MarketOHLCVBar(
            sessionDate: try CivilDate(canonical: "2026-01-14"),
            openedAt: nil,
            open: MarketQuotePrice(coefficient: 10_000_000_000, quoteCurrency: .usd),
            high: MarketQuotePrice(coefficient: 12_000_000_000, quoteCurrency: .usd),
            low: MarketQuotePrice(coefficient: 9_000_000_000, quoteCurrency: .usd),
            close: MarketQuotePrice(coefficient: 11_000_000_000, quoteCurrency: .usd),
            volume: AssetQuantity(coefficient: 1_000_000_000),
            adjustment: .all,
            providerIdentifier: provider.descriptor.identifier,
            fetchedAt: UTCInstant(millisecondsSince1970: now.millisecondsSince1970 - 50_000_000),
            freshness: .endOfDay
        )
        let oldPage = MarketHistoryPage(
            instrument: instrument,
            bars: [oldBar],
            nextEndDate: nil,
            sourceRevision: "synthetic-v1",
            providerIdentifier: provider.descriptor.identifier
        )
        let entry = try MarketCacheEntry(
            providerIdentifier: provider.descriptor.identifier,
            logicalKey: "history|SYN|XNAS|1day|all|2026-01-01|2026-01-15",
            dataType: .eodRecent,
            payload: try JSONEncoder().encode(oldPage),
            fetchedAt: oldBar.fetchedAt,
            entitlementContext: "synthetic-test",
            freshness: .endOfDay
        )
        try await cache.store(entry, authorization: .authorized)
        let service = MarketDataService(
            marketProvider: provider,
            fxProvider: SyntheticFXRateProvider(clock: clock),
            cache: cache,
            clock: clock,
            marketCacheAuthorization: .authorized
        )

        let merged = try await service.historicalBars(request)
        #expect(merged.bars.map(\.sessionDate) == [
            try CivilDate(canonical: "2026-01-14"),
            try CivilDate(canonical: "2026-01-15")
        ])
        #expect(merged.bars[0].close.coefficient == 21_000_000_000)
        #expect(merged.sourceRevision == "synthetic-v2")
    }

    private func cacheEntry(provider: String, key: String) throws -> MarketCacheEntry {
        try MarketCacheEntry(
            providerIdentifier: provider,
            logicalKey: key,
            dataType: .fxRate,
            payload: Data("synthetic-cache-value".utf8),
            fetchedAt: now,
            entitlementContext: "synthetic-test",
            freshness: .endOfDay
        )
    }
}

private actor RecordingProviderSleeperForFX: ProviderSleeper {
    func sleep(milliseconds: Int64) throws { try Task.checkCancellation() }
}
