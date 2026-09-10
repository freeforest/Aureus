import Foundation

struct PermanentMigrationSafetyInputs: Sendable {
    let appVersion: String
    let createdAt: @Sendable () -> UTCInstant
    let generationID: @Sendable () -> UUID
}

struct AppDependencies: Sendable {
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

    static func make(
        configuration: LaunchConfiguration,
        migrationSafetyInputs: PermanentMigrationSafetyInputs? = nil
    ) async throws -> AppDependencies {
        let paths: RuntimePaths
        if let temporaryRoot = configuration.temporaryRoot {
            paths = .temporary(root: temporaryRoot)
        } else {
            paths = try .production()
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
        let generalPreferencesStore = await MainActor.run {
            configuration.usesTemporaryStores ? GeneralPreferencesStore() : .production()
        }
        let marketPreferencesStore = MarketPreferencesStore(
            suiteName: nil,
            memoryOnly: configuration.usesTemporaryStores
        )
        let portfolioPreferencesStore = PortfolioPreferencesStore(
            suiteName: nil,
            memoryOnly: configuration.usesTemporaryStores
        )

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
        if configuration.usesTemporaryStores {
            credentialStore = InMemoryCredentialStore()
            marketDataProvider = SyntheticMarketDataProvider(scenario: .success, clock: clock)
            fxRateProvider = SyntheticFXRateProvider(clock: clock)
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

        return AppDependencies(
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
