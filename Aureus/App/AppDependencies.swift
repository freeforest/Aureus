import Foundation

struct AppDependencies: Sendable {
    let wealthStore: WealthStore
    let marketCacheStore: MarketCacheStore
    let marketDataProvider: any MarketDataProvider
    let fxRateProvider: any FXRateProvider
    let marketDataService: MarketDataService
    let credentialStore: any CredentialStore
    let credentialCoordinator: ProviderCredentialCoordinator
    let credentialStoragePolicy: ProductionCredentialStorage
    let clock: any Clock

    static func make(configuration: LaunchConfiguration) async throws -> AppDependencies {
        let paths: RuntimePaths
        if let temporaryRoot = configuration.temporaryRoot {
            paths = .temporary(root: temporaryRoot)
        } else {
            paths = try .production()
        }

        let wealthStore = try WealthStore(databaseURL: paths.permanentDatabaseURL)
        let marketCacheStore = try MarketCacheStore(databaseURL: paths.marketCacheDatabaseURL)
        let fixedClock = FixedClock(
            instant: UTCInstant(millisecondsSince1970: 1_768_435_200_000)
        )
        let clock: any Clock = configuration.usesTemporaryStores ? fixedClock : SystemClock()

        if configuration.dataMode == .syntheticDemo {
            try await wealthStore.seedSyntheticWealth()
            try await SyntheticLedgerSeeder.seed(in: wealthStore)
            try await SyntheticDashboardSeeder.seed(in: wealthStore)
        }

        let credentialStore: any CredentialStore
        let marketDataProvider: any MarketDataProvider
        let fxRateProvider: any FXRateProvider
        let cacheAuthorization: ProviderCacheAuthorization
        if configuration.usesTemporaryStores {
            credentialStore = InMemoryCredentialStore()
            marketDataProvider = SyntheticMarketDataProvider(scenario: .success, clock: clock)
            fxRateProvider = SyntheticFXRateProvider(clock: clock)
            cacheAuthorization = .authorized
        } else {
            let keychain = KeychainCredentialStore()
            let marketSleeper = TaskProviderSleeper()
            let marketGate = ProviderRequestGate(
                maximumConcurrentRequests: 2,
                minuteLimit: 8,
                dailyLimit: 800,
                clock: clock,
                sleeper: marketSleeper
            )
            credentialStore = keychain
            marketDataProvider = TwelveDataClient(
                credentialStore: keychain,
                transport: URLSessionTransport(),
                gate: marketGate,
                clock: clock,
                sleeper: marketSleeper
            )
            fxRateProvider = FrankfurterFXRateProvider(
                transport: URLSessionTransport(),
                gate: ProviderRequestGate(
                    maximumConcurrentRequests: 2,
                    minuteLimit: .max,
                    dailyLimit: nil,
                    clock: clock,
                    sleeper: marketSleeper
                ),
                clock: clock,
                sleeper: marketSleeper
            )
            // Current public Twelve Data terms do not disclose a safe typed
            // retention duration. Network results remain usable for the call,
            // but persistent Twelve Data cache writes stay disabled.
            cacheAuthorization = .unverified
        }

        let marketDataService = MarketDataService(
            marketProvider: marketDataProvider,
            fxProvider: fxRateProvider,
            cache: marketCacheStore,
            clock: clock,
            marketCacheAuthorization: cacheAuthorization
        )
        let credentialCoordinator = ProviderCredentialCoordinator(
            credentialStore: credentialStore,
            provider: marketDataProvider,
            cache: marketCacheStore,
            clock: clock
        )

        if try await marketCacheStore.automaticCleanupIsDue(reason: .launch, now: clock.now()) {
            _ = try await marketCacheStore.performAutomaticCleanup(reason: .launch, now: clock.now())
        }

        return AppDependencies(
            wealthStore: wealthStore,
            marketCacheStore: marketCacheStore,
            marketDataProvider: marketDataProvider,
            fxRateProvider: fxRateProvider,
            marketDataService: marketDataService,
            credentialStore: credentialStore,
            credentialCoordinator: credentialCoordinator,
            credentialStoragePolicy: ProductionCredentialPolicy.storage,
            clock: clock
        )
    }
}
