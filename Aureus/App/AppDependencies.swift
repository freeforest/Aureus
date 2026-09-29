import Foundation

struct PermanentMigrationSafetyInputs: Sendable {
    let appVersion: String
    let createdAt: @Sendable () -> UTCInstant
    let generationID: @Sendable () -> UUID
}

struct AppDependencies: Sendable {
    let runtimeEnvironment: RuntimeEnvironment
    let runtimePaths: RuntimePaths
    let wealthStore: WealthStore
    let marketCacheStore: MarketCacheStore
    let marketSessionStore: TransientMarketSessionStore
    let marketDataProvider: any MarketDataProvider
    let fxRateProvider: any FXRateProvider
    let marketDataService: MarketDataService
    let marketPreferencesStore: MarketPreferencesStore
    let generalPreferencesStore: GeneralPreferencesStore
    let portfolioPreferencesStore: PortfolioPreferencesStore
    let credentialStore: any CredentialStore
    let credentialCoordinator: ProviderCredentialCoordinator
    let credentialStoragePolicy: ProductionCredentialStorage
    let clock: any Clock
    let internalBackupDirectoryURL: URL
    let permanentBackupExportConfiguration: PermanentBackupExportConfiguration
    let permanentExternalRestoreConfiguration: PermanentExternalRestoreConfiguration
    let appVersion: String
    let dataLifecycleGenerationID: @Sendable () -> UUID
    let diagnostics: DataLifecycleDiagnostics

    static func isolatedMarketFailureScenario(
        for configuration: LaunchConfiguration
    ) -> SyntheticMarketFailureScenario? {
        guard configuration.dataMode == .syntheticDemo,
              configuration.usesTemporaryStores,
              configuration.temporaryRoot != nil else { return nil }
        return configuration.marketFailureScenario
    }

    static func isolatedMarketStaleAudit(for configuration: LaunchConfiguration) -> Bool {
        configuration.dataMode == .syntheticDemo
            && configuration.usesTemporaryStores
            && configuration.temporaryRoot != nil
            && configuration.marketStaleAuditEnabled
            && configuration.marketFailureScenario == nil
            && !configuration.settingsCacheAuditEnabled
    }

    static func make(
        configuration: LaunchConfiguration,
        migrationSafetyInputs: PermanentMigrationSafetyInputs? = nil
    ) async throws -> AppDependencies {
        let environment = try configuration.resolvedEnvironment()
        let paths: RuntimePaths
        switch environment {
        case .temporary:
            guard let temporaryRoot = configuration.temporaryRoot else {
                throw RuntimeEnvironmentError.invalidLaunchConfiguration
            }
            paths = .temporary(root: temporaryRoot)
        case .production:
            paths = try .production()
        case .development:
            paths = try .development()
        }
        try paths.validateSelected(for: environment)

        let generalPreferencesStore: GeneralPreferencesStore
        let marketPreferencesStore: MarketPreferencesStore
        let portfolioPreferencesStore: PortfolioPreferencesStore
        switch environment {
        case .temporary:
            generalPreferencesStore = await MainActor.run { GeneralPreferencesStore() }
            marketPreferencesStore = MarketPreferencesStore(suiteName: nil, memoryOnly: true)
            portfolioPreferencesStore = PortfolioPreferencesStore(suiteName: nil, memoryOnly: true)
        case .production:
            generalPreferencesStore = await MainActor.run { .production() }
            marketPreferencesStore = MarketPreferencesStore(suiteName: nil)
            portfolioPreferencesStore = PortfolioPreferencesStore(suiteName: nil, memoryOnly: false)
        case .development:
            guard let suiteName = environment.preferenceSuiteName else {
                throw RuntimeEnvironmentError.invalidPreferenceSuite
            }
            generalPreferencesStore = try await MainActor.run {
                try GeneralPreferencesStore(suiteName: suiteName)
            }
            marketPreferencesStore = try MarketPreferencesStore(requiredSuiteName: suiteName)
            portfolioPreferencesStore = try PortfolioPreferencesStore(requiredSuiteName: suiteName)
        }

        let fixedClock = FixedClock(
            instant: UTCInstant(millisecondsSince1970: 1_768_435_200_000)
        )
        let clock: any Clock = configuration.usesTemporaryStores ? fixedClock : SystemClock()
        let safetyInputs = migrationSafetyInputs ?? PermanentMigrationSafetyInputs(
            appVersion: normalizedAppVersion(),
            createdAt: { clock.now() },
            generationID: { UUID() }
        )
        let diagnostics: DataLifecycleDiagnostics = configuration.usesTemporaryStores ? .disabled : .osLog
        let wealthStore = try WealthStore(
            databaseURL: paths.permanentDatabaseURL,
            migrationSafetyConfiguration: PermanentMigrationSafetyConfiguration(
                backupRoot: paths.internalBackupDirectoryURL,
                appVersion: safetyInputs.appVersion,
                createdAt: safetyInputs.createdAt,
                generationID: safetyInputs.generationID
            ),
            diagnostics: diagnostics
        )
        let permanentBackupExportConfiguration = PermanentBackupExportConfiguration(
            internalBackupRootURL: paths.internalBackupDirectoryURL,
            permanentDatabaseURL: paths.permanentDatabaseURL,
            marketCacheDatabaseURL: paths.marketCacheDatabaseURL,
            additionalProtectedDestinationRoots: []
        )
        let permanentExternalRestoreConfiguration = PermanentExternalRestoreConfiguration(
            internalBackupRootURL: paths.internalBackupDirectoryURL,
            permanentDatabaseURL: paths.permanentDatabaseURL,
            marketCacheDatabaseURL: paths.marketCacheDatabaseURL,
            additionalProtectedSourceRoots: []
        )
        let marketCacheStore = try MarketCacheStore(databaseURL: paths.marketCacheDatabaseURL)
        let marketSessionStore = TransientMarketSessionStore()
        if configuration.dataMode == .syntheticDemo {
            try await wealthStore.seedSyntheticWealth()
            try await SyntheticLedgerSeeder.seed(in: wealthStore)
            try await SyntheticDashboardSeeder.seed(in: wealthStore)
            try await wealthStore.seedSyntheticPortfolio()
            try await SyntheticAnalyticsSeeder.seed(in: wealthStore)
            try await SyntheticGoalsSeeder.seed(in: wealthStore)
        }

        let credentialStore: any CredentialStore
        let marketDataProvider: any MarketDataProvider
        let fxRateProvider: any FXRateProvider
        if environment == .temporary {
            credentialStore = InMemoryCredentialStore()
            marketDataProvider = SyntheticMarketDataProvider(
                scenario: .success, clock: clock,
                failureScenario: isolatedMarketStaleAudit(for: configuration)
                    ? .historyOffline : isolatedMarketFailureScenario(for: configuration)
            )
            fxRateProvider = SyntheticFXRateProvider(clock: clock)
        } else {
            guard let service = environment.keychainService else {
                throw RuntimeEnvironmentError.invalidLaunchConfiguration
            }
            let keychain = KeychainCredentialStore(service: service)
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
        }

        let marketDataService = MarketDataService(
            marketProvider: marketDataProvider,
            fxProvider: fxRateProvider,
            cache: marketCacheStore,
            sessionStore: marketSessionStore,
            clock: clock
        )
        let credentialCoordinator = ProviderCredentialCoordinator(
            credentialStore: credentialStore,
            provider: marketDataProvider,
            cache: marketCacheStore,
            sessionStore: marketSessionStore,
            clock: clock
        )

        if try await marketCacheStore.automaticCleanupIsDue(reason: .launch, now: clock.now()) {
            _ = try await marketCacheStore.performAutomaticCleanup(reason: .launch, now: clock.now())
        }
        _ = try await marketCacheStore.purge(
            providerIdentifier: TwelveDataClient.credentialDescriptor.providerIdentifier,
            reason: .sessionOnlyPolicy,
            now: clock.now()
        )

        if configuration.settingsCacheAuditEnabled,
           configuration.usesTemporaryStores,
           configuration.temporaryRoot != nil,
           configuration.dataMode == .syntheticDemo {
            try await marketCacheStore.seedSyntheticCache()
        }

        if isolatedMarketStaleAudit(for: configuration) {
            // Seed once through the ordinary typed history service. The live graph remains offline
            // for History, and Clear Session cannot call this initialization-only path again.
            let seedClock = FixedClock(instant: UTCInstant(millisecondsSince1970:
                clock.now().millisecondsSince1970
                    - TransientMarketSessionDataType.historical.timeToLiveMilliseconds - 1))
            let seedProvider = SyntheticMarketDataProvider(scenario: .success, clock: seedClock)
            let instruments = try await seedProvider.search(query: "SYN")
            guard let instrument = instruments.first(where: { $0.symbol == "SYN-CNY" && $0.mic == "XSYN" }) else {
                throw ProviderBoundaryError.missing
            }
            let window = try MarketRangeRequestPolicy.window(for: .oneYear, now: clock.now())
            let request = try MarketHistoryRequest(instrument: instrument, interval: .oneDay,
                adjustment: .all, startDate: window.startDate, endDate: window.endDate,
                outputSize: window.outputSizeUpperBound)
            let seedService = MarketDataService(marketProvider: seedProvider,
                fxProvider: SyntheticFXRateProvider(clock: seedClock), cache: marketCacheStore,
                sessionStore: marketSessionStore, clock: seedClock)
            _ = try await seedService.historicalBars(request)
        }

        return AppDependencies(
            runtimeEnvironment: environment,
            runtimePaths: paths,
            wealthStore: wealthStore,
            marketCacheStore: marketCacheStore,
            marketSessionStore: marketSessionStore,
            marketDataProvider: marketDataProvider,
            fxRateProvider: fxRateProvider,
            marketDataService: marketDataService,
            marketPreferencesStore: marketPreferencesStore,
            generalPreferencesStore: generalPreferencesStore,
            portfolioPreferencesStore: portfolioPreferencesStore,
            credentialStore: credentialStore,
            credentialCoordinator: credentialCoordinator,
            credentialStoragePolicy: ProductionCredentialPolicy.storage,
            clock: clock,
            internalBackupDirectoryURL: paths.internalBackupDirectoryURL,
            permanentBackupExportConfiguration: permanentBackupExportConfiguration,
            permanentExternalRestoreConfiguration: permanentExternalRestoreConfiguration,
            appVersion: safetyInputs.appVersion,
            dataLifecycleGenerationID: safetyInputs.generationID,
            diagnostics: diagnostics
        )
    }

    private static func normalizedAppVersion() -> String {
        let raw = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        let normalized = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? "0.1" : normalized
    }
}
