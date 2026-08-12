import Foundation

actor MarketDataService {
    private let marketProvider: any MarketDataProvider
    private let fxProvider: any FXRateProvider
    private let cache: MarketCacheStore
    private let clock: any Clock
    private let marketCacheAuthorization: ProviderCacheAuthorization

    init(
        marketProvider: any MarketDataProvider,
        fxProvider: any FXRateProvider,
        cache: MarketCacheStore,
        clock: any Clock,
        marketCacheAuthorization: ProviderCacheAuthorization
    ) {
        self.marketProvider = marketProvider
        self.fxProvider = fxProvider
        self.cache = cache
        self.clock = clock
        self.marketCacheAuthorization = marketCacheAuthorization
    }

    func search(query: String) async throws -> [MarketInstrument] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let key = "search|\(normalized)"
        if case let .fresh(entry) = try await cache.lookup(
            providerIdentifier: marketProvider.descriptor.identifier,
            logicalKey: key,
            dataType: .symbolSearch,
            now: clock.now(),
            allowStale: false
        ) {
            return try decode([MarketInstrument].self, entry.payload)
        }
        do {
            let instruments = try await marketProvider.search(query: query)
            try await storeValidated(
                instruments,
                provider: marketProvider.descriptor.identifier,
                key: key,
                type: .symbolSearch,
                entitlement: "observed-at-request",
                freshness: .unknown,
                authorization: marketCacheAuthorization
            )
            return instruments
        } catch let error as ProviderBoundaryError
            where error == .offline || error == .timeout {
            if case let .stale(entry) = try await cache.lookup(
                providerIdentifier: marketProvider.descriptor.identifier,
                logicalKey: key,
                dataType: .symbolSearch,
                now: clock.now(),
                allowStale: true
            ) {
                return try decode([MarketInstrument].self, entry.payload)
            }
            throw ProviderBoundaryError.missing
        }
    }

    func latestQuote(for instrument: MarketInstrument) async throws -> MarketQuote {
        let key = "quote|\(instrument.symbol)|\(instrument.mic)"
        if case let .fresh(entry) = try await cache.lookup(
            providerIdentifier: marketProvider.descriptor.identifier,
            logicalKey: key,
            dataType: .latestQuote,
            now: clock.now(),
            allowStale: false
        ) {
            return try decode(MarketQuote.self, entry.payload)
        }
        do {
            let quote = try await marketProvider.latestQuote(for: instrument)
            try await storeValidated(
                quote,
                provider: marketProvider.descriptor.identifier,
                key: key,
                type: .latestQuote,
                entitlement: "observed-at-request",
                freshness: quote.freshness,
                authorization: marketCacheAuthorization
            )
            return quote
        } catch let error as ProviderBoundaryError
            where error == .offline || error == .timeout {
            if case let .stale(entry) = try await cache.lookup(
                providerIdentifier: marketProvider.descriptor.identifier,
                logicalKey: key,
                dataType: .latestQuote,
                now: clock.now(),
                allowStale: true
            ) {
                let cached = try decode(MarketQuote.self, entry.payload)
                return MarketQuote(
                    instrument: cached.instrument,
                    price: cached.price,
                    observedAt: cached.observedAt,
                    fetchedAt: cached.fetchedAt,
                    providerIdentifier: cached.providerIdentifier,
                    quality: .offline,
                    freshness: .stale
                )
            }
            throw ProviderBoundaryError.missing
        }
    }

    func historicalBars(_ request: MarketHistoryRequest) async throws -> MarketHistoryPage {
        let key = historyKey(request)
        let cacheType = historyDataType(for: request)
        let cached = try await cache.lookup(
            providerIdentifier: marketProvider.descriptor.identifier,
            logicalKey: key,
            dataType: cacheType,
            now: clock.now(),
            allowStale: true
        )
        if case let .fresh(entry) = cached {
            return try decode(MarketHistoryPage.self, entry.payload)
        }
        do {
            let incrementalRequest: MarketHistoryRequest
            var existing: MarketHistoryPage?
            if case let .stale(entry) = cached,
               let page = try? decode(MarketHistoryPage.self, entry.payload),
               let last = page.bars.last?.sessionDate {
                existing = page
                incrementalRequest = try MarketHistoryRequest(
                    instrument: request.instrument,
                    interval: request.interval,
                    adjustment: request.adjustment,
                    startDate: last,
                    endDate: request.endDate,
                    outputSize: request.outputSize
                )
            } else {
                existing = nil
                incrementalRequest = request
            }
            let fetched = try await marketProvider.historicalBars(incrementalRequest)
            let merged = merge(existing: existing, fetched: fetched)
            try await storeValidated(
                merged,
                provider: marketProvider.descriptor.identifier,
                key: key,
                type: cacheType,
                entitlement: "observed-at-request",
                freshness: request.interval.isIntraday ? .delayed : .endOfDay,
                authorization: marketCacheAuthorization
            )
            return merged
        } catch let error as ProviderBoundaryError
            where error == .offline || error == .timeout {
            if case let .stale(entry) = cached {
                let page = try decode(MarketHistoryPage.self, entry.payload)
                return MarketHistoryPage(
                    instrument: page.instrument,
                    bars: page.bars.map { bar in
                        (try? MarketOHLCVBar(
                            sessionDate: bar.sessionDate,
                            openedAt: bar.openedAt,
                            open: bar.open,
                            high: bar.high,
                            low: bar.low,
                            close: bar.close,
                            volume: bar.volume,
                            adjustment: bar.adjustment,
                            providerIdentifier: bar.providerIdentifier,
                            fetchedAt: bar.fetchedAt,
                            freshness: .stale
                        )) ?? bar
                    },
                    nextEndDate: page.nextEndDate,
                    sourceRevision: page.sourceRevision,
                    providerIdentifier: page.providerIdentifier
                )
            }
            throw ProviderBoundaryError.missing
        }
    }

    func corporateActions(
        for instrument: MarketInstrument,
        from startDate: CivilDate?,
        through endDate: CivilDate?
    ) async throws -> [MarketCorporateAction] {
        let key = "actions|\(instrument.symbol)|\(instrument.mic)|\(startDate?.description ?? "")|\(endDate?.description ?? "")"
        if case let .fresh(entry) = try await cache.lookup(
            providerIdentifier: marketProvider.descriptor.identifier,
            logicalKey: key,
            dataType: .corporateAction,
            now: clock.now(),
            allowStale: false
        ) {
            return try decode([MarketCorporateAction].self, entry.payload)
        }
        do {
            let actions = try await marketProvider.corporateActions(
                for: instrument,
                from: startDate,
                through: endDate
            )
            try await storeValidated(
                actions,
                provider: marketProvider.descriptor.identifier,
                key: key,
                type: .corporateAction,
                entitlement: "observed-at-request",
                freshness: .endOfDay,
                authorization: marketCacheAuthorization
            )
            return actions
        } catch let error as ProviderBoundaryError
            where error == .offline || error == .timeout {
            if case let .stale(entry) = try await cache.lookup(
                providerIdentifier: marketProvider.descriptor.identifier,
                logicalKey: key,
                dataType: .corporateAction,
                now: clock.now(),
                allowStale: true
            ) {
                return try decode([MarketCorporateAction].self, entry.payload)
            }
            throw ProviderBoundaryError.missing
        }
    }

    func referenceRate(
        source: CurrencyCode,
        target: CurrencyCode,
        on date: CivilDate
    ) async throws -> ExchangeRate {
        let key = "fx|\(source.rawValue)|\(target.rawValue)|\(date)"
        if case let .fresh(entry) = try await cache.lookup(
            providerIdentifier: fxProvider.descriptor.identifier,
            logicalKey: key,
            dataType: .fxRate,
            now: clock.now(),
            allowStale: false
        ) {
            return try decode(ExchangeRate.self, entry.payload)
        }
        do {
            let rate = try await fxProvider.rate(source: source, target: target, on: date)
            try await storeValidated(
                rate,
                provider: fxProvider.descriptor.identifier,
                key: key,
                type: .fxRate,
                entitlement: "public-ecb-reference",
                freshness: .endOfDay,
                authorization: .authorized
            )
            return rate
        } catch let error as ProviderBoundaryError
            where error == .offline || error == .timeout {
            if case let .stale(entry) = try await cache.lookup(
                providerIdentifier: fxProvider.descriptor.identifier,
                logicalKey: key,
                dataType: .fxRate,
                now: clock.now(),
                allowStale: true
            ) {
                let cached = try decode(ExchangeRate.self, entry.payload)
                return ExchangeRate(
                    id: cached.id,
                    rate: cached.rate,
                    referenceDate: cached.referenceDate,
                    fetchedAt: cached.fetchedAt,
                    providerIdentifier: cached.providerIdentifier,
                    provenance: cached.provenance,
                    freshness: .stale
                )
            }
            throw ProviderBoundaryError.missing
        }
    }

    private func storeValidated<T: Encodable>(
        _ value: T,
        provider: String,
        key: String,
        type: MarketCacheDataType,
        entitlement: String,
        freshness: MarketFreshness,
        authorization: ProviderCacheAuthorization
    ) async throws {
        let payload = try JSONEncoder().encode(value)
        let entry = try MarketCacheEntry(
            providerIdentifier: provider,
            logicalKey: key,
            dataType: type,
            payload: payload,
            fetchedAt: clock.now(),
            entitlementContext: entitlement,
            freshness: freshness
        )
        do {
            try await cache.store(entry, authorization: authorization)
        } catch CachePolicyError.persistentRetentionUnverified {
            // The validated result remains usable in memory for this call, but current
            // public terms do not authorize a guessed persistent retention duration.
        } catch CachePolicyError.capacityCannotBeSatisfied {
            // A bounded cache must never turn a validated network result into an App
            // failure or gain access to permanent data to make space.
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw ProviderBoundaryError.invalidPayload }
    }

    private func historyKey(_ request: MarketHistoryRequest) -> String {
        [
            "history", request.instrument.symbol, request.instrument.mic,
            request.interval.rawValue, request.adjustment.rawValue,
            request.startDate?.description ?? "", request.endDate?.description ?? ""
        ].joined(separator: "|")
    }

    private func historyDataType(for request: MarketHistoryRequest) -> MarketCacheDataType {
        guard !request.interval.isIntraday else { return .intraday }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let cutoffDate = calendar.date(byAdding: .day, value: -30, to: clock.now().date) else {
            return .eodHistorical
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: cutoffDate)
        guard let year = parts.year,
              let month = parts.month,
              let day = parts.day,
              let cutoff = try? CivilDate(year: year, month: month, day: day) else {
            return .eodHistorical
        }
        return (request.endDate ?? request.startDate).map { $0 >= cutoff } == true
            ? .eodRecent
            : .eodHistorical
    }

    private func merge(
        existing: MarketHistoryPage?,
        fetched: MarketHistoryPage
    ) -> MarketHistoryPage {
        guard let existing else { return fetched }
        var byDate = Dictionary(uniqueKeysWithValues: existing.bars.map { ($0.sessionDate, $0) })
        for bar in fetched.bars { byDate[bar.sessionDate] = bar }
        return MarketHistoryPage(
            instrument: fetched.instrument,
            bars: byDate.values.sorted { $0.sessionDate < $1.sessionDate },
            nextEndDate: fetched.nextEndDate,
            sourceRevision: fetched.sourceRevision ?? existing.sourceRevision,
            providerIdentifier: fetched.providerIdentifier
        )
    }
}

actor ProviderCredentialCoordinator {
    private let credentialStore: any CredentialStore
    private let provider: any MarketDataProvider
    private let cache: MarketCacheStore
    private let clock: any Clock

    init(
        credentialStore: any CredentialStore,
        provider: any MarketDataProvider,
        cache: MarketCacheStore,
        clock: any Clock
    ) {
        self.credentialStore = credentialStore
        self.provider = provider
        self.cache = cache
        self.clock = clock
    }

    func isConfigured() async throws -> Bool {
        try await credentialStore.credential(for: TwelveDataClient.credentialDescriptor) != nil
    }

    func save(_ value: String) async throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8, let data = trimmed.data(using: .utf8) else {
            throw CredentialStoreError.invalidCredential
        }
        try await credentialStore.store(data, for: TwelveDataClient.credentialDescriptor)
        await provider.credentialDidChange()
    }

    func validate() async throws -> ProviderUsageObservation {
        guard try await isConfigured() else {
            throw ProviderBoundaryError.missingCredential
        }
        return try await provider.validateCredential()
    }

    @discardableResult
    func disconnect() async throws -> CacheCleanupResult {
        try await revoke(reason: .disconnect)
    }

    @discardableResult
    func deleteCredential() async throws -> CacheCleanupResult {
        try await revoke(reason: .credentialDeleted)
    }

    private func revoke(reason: CacheCleanupReason) async throws -> CacheCleanupResult {
        await provider.disconnect()
        let cleanup = try await cache.purge(
            providerIdentifier: provider.descriptor.identifier,
            reason: reason,
            now: clock.now()
        )
        try await credentialStore.deleteCredential(for: TwelveDataClient.credentialDescriptor)
        return cleanup
    }

    @discardableResult
    func confirmedTermination() async throws -> CacheCleanupResult {
        try await revoke(reason: .confirmedTermination)
    }
}
