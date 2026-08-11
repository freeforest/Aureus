import Foundation

struct AppDependencies: Sendable {
    let wealthStore: WealthStore
    let marketCacheStore: MarketCacheStore
    let marketDataProvider: any MarketDataProvider
    let fxRateProvider: any FXRateProvider
    let credentialStoragePolicy: ProductionCredentialStorage

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

        if configuration.dataMode == .syntheticDemo {
            try await wealthStore.seedSyntheticFoundation()
            try await marketCacheStore.seedSyntheticCache()
        }

        return AppDependencies(
            wealthStore: wealthStore,
            marketCacheStore: marketCacheStore,
            marketDataProvider: SyntheticMarketDataProvider(scenario: .success, clock: fixedClock),
            fxRateProvider: SyntheticFXRateProvider(clock: fixedClock),
            credentialStoragePolicy: ProductionCredentialPolicy.storage
        )
    }
}
