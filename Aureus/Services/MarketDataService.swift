import Foundation

enum TransientMarketSessionDataType: String, CaseIterable, Sendable {
    case search
    case quote
    case historical
    case split
    case dividend

    var timeToLiveMilliseconds: Int64 {
        switch self {
        case .search: 7 * 24 * 60 * 60 * 1_000
        case .quote: 15 * 60 * 1_000
        case .historical: 12 * 60 * 60 * 1_000
        case .split, .dividend: 24 * 60 * 60 * 1_000
        }
    }
}

enum TransientMarketSessionPayload: Equatable, Sendable {
    case search([MarketInstrument])
    case quote(MarketQuote)
    case historical(MarketHistoryPage)
    case splits([MarketCorporateAction])
    case dividends([MarketCorporateAction])

    var dataType: TransientMarketSessionDataType {
        switch self {
        case .search: .search
        case .quote: .quote
        case .historical: .historical
        case .splits: .split
        case .dividends: .dividend
        }
    }
}

struct TransientMarketSessionValue: Equatable, Sendable {
    let payload: TransientMarketSessionPayload
    let fetchedAt: UTCInstant
    let expiresAt: UTCInstant
}

enum TransientMarketSessionLookup: Equatable, Sendable {
    case fresh(TransientMarketSessionValue)
    case stale(TransientMarketSessionValue)
    case missing
}

enum TransientMarketSessionStoreResult: Equatable, Sendable {
    case stored
    case ignoredStaleGeneration
    case notStoredOversize
}

enum TransientMarketSessionStoreError: Error, Equatable, Sendable {
    case invalidCapacity
    case accountingOverflow
    case invalidPayloadType
}

struct TransientMarketSessionStatistics: Equatable, Sendable {
    let entryCount: Int
    let accountedBytes: Int64
    let maximumBytes: Int64
}

struct TransientMarketSessionClearResult: Equatable, Sendable {
    let removedEntries: Int
    let removedBytes: Int64
}

actor TransientMarketSessionStore {
    static let defaultMaximumBytes: Int64 = 64 * 1_048_576

    private struct Key: Hashable, Comparable, Sendable {
        let providerIdentifier: String
        let logicalKey: String
        let dataType: TransientMarketSessionDataType

        static func < (lhs: Key, rhs: Key) -> Bool {
            (lhs.providerIdentifier, lhs.logicalKey, lhs.dataType.rawValue) <
                (rhs.providerIdentifier, rhs.logicalKey, rhs.dataType.rawValue)
        }
    }

    private struct Entry: Sendable {
        let value: TransientMarketSessionValue
        let accountedBytes: Int64
        var lastAccessedAt: UTCInstant
        var accessOrdinal: UInt64
    }

    private var entries: [Key: Entry] = [:]
    private var providerGenerations: [String: UUID] = [:]
    private var maximumBytes: Int64
    private var currentBytes: Int64 = 0
    private var nextAccessOrdinal: UInt64 = 0

    init(maximumBytes: Int64 = TransientMarketSessionStore.defaultMaximumBytes) {
        precondition(maximumBytes > 0, "Transient session capacity must be positive")
        self.maximumBytes = maximumBytes
    }

    func generation(for providerIdentifier: String) -> UUID {
        if let existing = providerGenerations[providerIdentifier] { return existing }
        let created = UUID()
        providerGenerations[providerIdentifier] = created
        return created
    }

    func lookup(
        providerIdentifier: String,
        logicalKey: String,
        dataType: TransientMarketSessionDataType,
        now: UTCInstant
    ) throws -> TransientMarketSessionLookup {
        let key = Key(
            providerIdentifier: providerIdentifier,
            logicalKey: logicalKey,
            dataType: dataType
        )
        guard var entry = entries[key] else { return .missing }
        entry.lastAccessedAt = now
        entry.accessOrdinal = try advanceAccessOrdinal()
        entries[key] = entry
        return entry.value.expiresAt > now ? .fresh(entry.value) : .stale(entry.value)
    }

    func isCurrent(generation: UUID, providerIdentifier: String) -> Bool {
        generation == self.generation(for: providerIdentifier)
    }

    @discardableResult
    func store(
        providerIdentifier: String,
        logicalKey: String,
        payload: TransientMarketSessionPayload,
        fetchedAt: UTCInstant,
        generation: UUID
    ) throws -> TransientMarketSessionStoreResult {
        guard payload.dataType == expectedDataType(for: payload) else {
            throw TransientMarketSessionStoreError.invalidPayloadType
        }
        guard generation == self.generation(for: providerIdentifier) else {
            return .ignoredStaleGeneration
        }
        let key = Key(
            providerIdentifier: providerIdentifier,
            logicalKey: logicalKey,
            dataType: payload.dataType
        )
        let accountedBytes = try Self.accountedBytes(for: key, payload: payload)
        guard accountedBytes <= maximumBytes else { return .notStoredOversize }
        let expiry = fetchedAt.millisecondsSince1970.addingReportingOverflow(
            payload.dataType.timeToLiveMilliseconds
        )
        guard !expiry.overflow else {
            throw TransientMarketSessionStoreError.accountingOverflow
        }

        var candidate = entries
        var candidateBytes = currentBytes
        if let replaced = candidate.removeValue(forKey: key) {
            candidateBytes = try Self.subtract(candidateBytes, replaced.accountedBytes)
        }
        candidateBytes = try Self.add(candidateBytes, accountedBytes)
        candidate[key] = Entry(
            value: TransientMarketSessionValue(
                payload: payload,
                fetchedAt: fetchedAt,
                expiresAt: UTCInstant(millisecondsSince1970: expiry.partialValue)
            ),
            accountedBytes: accountedBytes,
            lastAccessedAt: fetchedAt,
            accessOrdinal: try advanceAccessOrdinal()
        )
        try Self.evict(
            entries: &candidate,
            currentBytes: &candidateBytes,
            maximumBytes: maximumBytes
        )
        entries = candidate
        currentBytes = candidateBytes
        return .stored
    }

    func updateMaximumBytes(_ value: Int64) throws -> TransientMarketSessionClearResult {
        guard value > 0 else { throw TransientMarketSessionStoreError.invalidCapacity }
        var candidate = entries
        var candidateBytes = currentBytes
        let beforeCount = candidate.count
        let beforeBytes = candidateBytes
        try Self.evict(entries: &candidate, currentBytes: &candidateBytes, maximumBytes: value)
        entries = candidate
        currentBytes = candidateBytes
        maximumBytes = value
        return TransientMarketSessionClearResult(
            removedEntries: beforeCount - candidate.count,
            removedBytes: try Self.subtract(beforeBytes, candidateBytes)
        )
    }

    func clear(providerIdentifier: String) throws -> TransientMarketSessionClearResult {
        let matching = entries.filter { $0.key.providerIdentifier == providerIdentifier }
        var removedBytes: Int64 = 0
        for (key, entry) in matching {
            removedBytes = try Self.add(removedBytes, entry.accountedBytes)
            entries.removeValue(forKey: key)
        }
        currentBytes = try Self.subtract(currentBytes, removedBytes)
        providerGenerations[providerIdentifier] = UUID()
        return TransientMarketSessionClearResult(
            removedEntries: matching.count,
            removedBytes: removedBytes
        )
    }

    func clearAll() -> TransientMarketSessionClearResult {
        let result = TransientMarketSessionClearResult(
            removedEntries: entries.count,
            removedBytes: currentBytes
        )
        entries.removeAll(keepingCapacity: true)
        currentBytes = 0
        let providers = Array(providerGenerations.keys)
        for provider in providers {
            providerGenerations[provider] = UUID()
        }
        return result
    }

    func statistics() -> TransientMarketSessionStatistics {
        TransientMarketSessionStatistics(
            entryCount: entries.count,
            accountedBytes: currentBytes,
            maximumBytes: maximumBytes
        )
    }

    private func advanceAccessOrdinal() throws -> UInt64 {
        let next = nextAccessOrdinal.addingReportingOverflow(1)
        guard !next.overflow else { throw TransientMarketSessionStoreError.accountingOverflow }
        nextAccessOrdinal = next.partialValue
        return next.partialValue
    }

    private func expectedDataType(
        for payload: TransientMarketSessionPayload
    ) -> TransientMarketSessionDataType {
        payload.dataType
    }

    private static func evict(
        entries: inout [Key: Entry],
        currentBytes: inout Int64,
        maximumBytes: Int64
    ) throws {
        while currentBytes > maximumBytes, let oldest = entries.min(by: { lhs, rhs in
            let left = lhs.value
            let right = rhs.value
            if left.lastAccessedAt != right.lastAccessedAt {
                return left.lastAccessedAt < right.lastAccessedAt
            }
            if left.accessOrdinal != right.accessOrdinal {
                return left.accessOrdinal < right.accessOrdinal
            }
            return lhs.key < rhs.key
        }) {
            entries.removeValue(forKey: oldest.key)
            currentBytes = try subtract(currentBytes, oldest.value.accountedBytes)
        }
    }

    /// Logical bytes are a conservative, deterministic sum of typed business
    /// fields plus fixed metadata overhead. They intentionally do not claim to
    /// measure Swift heap allocation and are never serialized or persisted.
    private static func accountedBytes(
        for key: Key,
        payload: TransientMarketSessionPayload
    ) throws -> Int64 {
        var total: Int64 = 96
        try addString(key.providerIdentifier, to: &total)
        try addString(key.logicalKey, to: &total)
        try addString(key.dataType.rawValue, to: &total)
        switch payload {
        case .search(let instruments):
            for instrument in instruments { try add(instrument, to: &total) }
        case .quote(let quote):
            try add(quote.instrument, to: &total)
            total = try add(total, 56)
            try addString(quote.providerIdentifier, to: &total)
        case .historical(let page):
            try add(page.instrument, to: &total)
            try addString(page.providerIdentifier, to: &total)
            if let revision = page.sourceRevision { try addString(revision, to: &total) }
            total = try add(total, 16)
            for bar in page.bars {
                total = try add(total, 96)
                try addString(bar.providerIdentifier, to: &total)
            }
        case .splits(let actions), .dividends(let actions):
            for action in actions {
                try add(action.instrument, to: &total)
                try addString(action.id, to: &total)
                try addString(action.providerIdentifier, to: &total)
                total = try add(total, 64)
            }
        }
        return total
    }

    private static func add(_ instrument: MarketInstrument, to total: inout Int64) throws {
        total = try add(total, 16)
        try addString(instrument.symbol, to: &total)
        try addString(instrument.mic, to: &total)
        try addString(instrument.currency.rawValue, to: &total)
        try addString(instrument.displayName, to: &total)
    }

    private static func addString(_ value: String, to total: inout Int64) throws {
        guard let count = Int64(exactly: value.utf8.count) else {
            throw TransientMarketSessionStoreError.accountingOverflow
        }
        total = try add(total, count)
    }

    private static func add(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw TransientMarketSessionStoreError.accountingOverflow }
        return result.partialValue
    }

    private static func subtract(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let result = lhs.subtractingReportingOverflow(rhs)
        guard !result.overflow, result.partialValue >= 0 else {
            throw TransientMarketSessionStoreError.accountingOverflow
        }
        return result.partialValue
    }
}

actor MarketDataService {
    private let marketProvider: any MarketDataProvider
    private let fxProvider: any FXRateProvider
    private let cache: MarketCacheStore
    private let sessionStore: TransientMarketSessionStore
    private let clock: any Clock

    init(
        marketProvider: any MarketDataProvider,
        fxProvider: any FXRateProvider,
        cache: MarketCacheStore,
        sessionStore: TransientMarketSessionStore,
        clock: any Clock
    ) {
        self.marketProvider = marketProvider
        self.fxProvider = fxProvider
        self.cache = cache
        self.sessionStore = sessionStore
        self.clock = clock
    }

    func search(query: String) async throws -> [MarketInstrument] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let key = "search|\(normalized)"
        let providerIdentifier = marketProvider.descriptor.identifier
        let generation = await sessionStore.generation(for: providerIdentifier)
        let cached = try await sessionStore.lookup(
            providerIdentifier: marketProvider.descriptor.identifier,
            logicalKey: key,
            dataType: .search,
            now: clock.now()
        )
        if case let .fresh(value) = cached,
           case let .search(instruments) = value.payload {
            try await requireCurrent(generation, providerIdentifier: providerIdentifier)
            return instruments
        }
        do {
            let instruments = try await marketProvider.search(query: query)
            let result = try await sessionStore.store(
                providerIdentifier: providerIdentifier,
                logicalKey: key,
                payload: .search(instruments),
                fetchedAt: clock.now(),
                generation: generation
            )
            try await requireCurrentStoreResult(
                result,
                generation: generation,
                providerIdentifier: providerIdentifier
            )
            return instruments
        } catch let error as ProviderBoundaryError {
            if Self.isConfirmedEntitlementLoss(error) {
                await clearAfterConfirmedEntitlementLoss(providerIdentifier: providerIdentifier)
                throw error
            }
            if Self.allowsStaleFallback(error) {
                if case let .stale(value) = cached,
                   case let .search(instruments) = value.payload {
                    try await requireCurrent(generation, providerIdentifier: providerIdentifier)
                    return instruments
                }
                throw error
            }
            throw error
        }
    }

    func latestQuote(for instrument: MarketInstrument) async throws -> MarketQuote {
        let key = "quote|\(instrument.symbol)|\(instrument.mic)"
        let providerIdentifier = marketProvider.descriptor.identifier
        let generation = await sessionStore.generation(for: providerIdentifier)
        let cached = try await sessionStore.lookup(
            providerIdentifier: providerIdentifier,
            logicalKey: key,
            dataType: .quote,
            now: clock.now()
        )
        if case let .fresh(value) = cached,
           case let .quote(quote) = value.payload {
            try await requireCurrent(generation, providerIdentifier: providerIdentifier)
            return quote
        }
        do {
            let quote = try await marketProvider.latestQuote(for: instrument)
            let result = try await sessionStore.store(
                providerIdentifier: providerIdentifier,
                logicalKey: key,
                payload: .quote(quote),
                fetchedAt: clock.now(),
                generation: generation
            )
            try await requireCurrentStoreResult(
                result,
                generation: generation,
                providerIdentifier: providerIdentifier
            )
            return quote
        } catch let error as ProviderBoundaryError {
            if Self.isConfirmedEntitlementLoss(error) {
                await clearAfterConfirmedEntitlementLoss(providerIdentifier: providerIdentifier)
                throw error
            }
            if Self.allowsStaleFallback(error) {
                if case let .stale(value) = cached,
                   case let .quote(cachedQuote) = value.payload {
                    try await requireCurrent(generation, providerIdentifier: providerIdentifier)
                    return MarketQuote(
                        instrument: cachedQuote.instrument,
                        price: cachedQuote.price,
                        observedAt: cachedQuote.observedAt,
                        fetchedAt: cachedQuote.fetchedAt,
                        providerIdentifier: cachedQuote.providerIdentifier,
                        quality: .offline,
                        freshness: .stale
                    )
                }
                throw error
            }
            throw error
        }
    }

    func historicalBars(_ request: MarketHistoryRequest) async throws -> MarketHistoryPage {
        let key = historyKey(request)
        let providerIdentifier = marketProvider.descriptor.identifier
        let generation = await sessionStore.generation(for: providerIdentifier)
        let cached = try await sessionStore.lookup(
            providerIdentifier: providerIdentifier,
            logicalKey: key,
            dataType: .historical,
            now: clock.now()
        )
        if case let .fresh(value) = cached,
           case let .historical(page) = value.payload {
            try await requireCurrent(generation, providerIdentifier: providerIdentifier)
            return page
        }
        do {
            let incrementalRequest: MarketHistoryRequest
            var existing: MarketHistoryPage?
            if case let .stale(value) = cached,
               case let .historical(page) = value.payload,
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
            let result = try await sessionStore.store(
                providerIdentifier: providerIdentifier,
                logicalKey: key,
                payload: .historical(merged),
                fetchedAt: clock.now(),
                generation: generation
            )
            try await requireCurrentStoreResult(
                result,
                generation: generation,
                providerIdentifier: providerIdentifier
            )
            return merged
        } catch let error as ProviderBoundaryError {
            if Self.isConfirmedEntitlementLoss(error) {
                await clearAfterConfirmedEntitlementLoss(providerIdentifier: providerIdentifier)
                throw error
            }
            if Self.allowsStaleFallback(error) {
                if case let .stale(value) = cached,
                   case let .historical(page) = value.payload {
                    try await requireCurrent(generation, providerIdentifier: providerIdentifier)
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
                throw error
            }
            throw error
        }
    }

    func corporateActions(
        for instrument: MarketInstrument,
        from startDate: CivilDate?,
        through endDate: CivilDate?
    ) async throws -> [MarketCorporateAction] {
        let key = "actions|\(instrument.symbol)|\(instrument.mic)|\(startDate?.description ?? "")|\(endDate?.description ?? "")"
        let providerIdentifier = marketProvider.descriptor.identifier
        let generation = await sessionStore.generation(for: providerIdentifier)
        let splitLookup = try await sessionStore.lookup(
            providerIdentifier: providerIdentifier,
            logicalKey: key,
            dataType: .split,
            now: clock.now()
        )
        let dividendLookup = try await sessionStore.lookup(
            providerIdentifier: providerIdentifier,
            logicalKey: key,
            dataType: .dividend,
            now: clock.now()
        )
        if case let .fresh(splitValue) = splitLookup,
           case let .splits(splits) = splitValue.payload,
           case let .fresh(dividendValue) = dividendLookup,
           case let .dividends(dividends) = dividendValue.payload {
            try await requireCurrent(generation, providerIdentifier: providerIdentifier)
            return Self.sortedActions(splits + dividends)
        }
        do {
            let actions = try await marketProvider.corporateActions(
                for: instrument,
                from: startDate,
                through: endDate
            )
            let splitResult = try await sessionStore.store(
                providerIdentifier: providerIdentifier,
                logicalKey: key,
                payload: .splits(actions.filter { $0.kind == .split }),
                fetchedAt: clock.now(),
                generation: generation
            )
            let dividendResult = try await sessionStore.store(
                providerIdentifier: providerIdentifier,
                logicalKey: key,
                payload: .dividends(actions.filter { $0.kind == .dividend }),
                fetchedAt: clock.now(),
                generation: generation
            )
            try await requireCurrentStoreResult(
                splitResult,
                generation: generation,
                providerIdentifier: providerIdentifier
            )
            try await requireCurrentStoreResult(
                dividendResult,
                generation: generation,
                providerIdentifier: providerIdentifier
            )
            return Self.sortedActions(actions)
        } catch let error as ProviderBoundaryError {
            if Self.isConfirmedEntitlementLoss(error) {
                await clearAfterConfirmedEntitlementLoss(providerIdentifier: providerIdentifier)
                throw error
            }
            if Self.allowsStaleFallback(error) {
                guard let splits = Self.splits(from: splitLookup),
                      let dividends = Self.dividends(from: dividendLookup) else {
                    throw error
                }
                try await requireCurrent(generation, providerIdentifier: providerIdentifier)
                return Self.sortedActions(splits + dividends)
            }
            throw error
        }
    }

    @discardableResult
    func clearSessionMarketData() async throws -> TransientMarketSessionClearResult {
        try await sessionStore.clear(providerIdentifier: marketProvider.descriptor.identifier)
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

    private func requireCurrent(
        _ generation: UUID,
        providerIdentifier: String
    ) async throws {
        guard await sessionStore.isCurrent(
            generation: generation,
            providerIdentifier: providerIdentifier
        ) else {
            throw ProviderBoundaryError.cancelled
        }
    }

    private func requireCurrentStoreResult(
        _ result: TransientMarketSessionStoreResult,
        generation: UUID,
        providerIdentifier: String
    ) async throws {
        guard result != .ignoredStaleGeneration else {
            throw ProviderBoundaryError.cancelled
        }
        try await requireCurrent(generation, providerIdentifier: providerIdentifier)
    }

    private func clearAfterConfirmedEntitlementLoss(providerIdentifier: String) async {
        do {
            _ = try await sessionStore.clear(providerIdentifier: providerIdentifier)
        } catch {
            // Preserve the Provider's original typed error while ensuring no
            // session value survives an internal accounting invariant failure.
            _ = await sessionStore.clearAll()
        }
    }

    private static func isConfirmedEntitlementLoss(_ error: ProviderBoundaryError) -> Bool {
        switch error {
        case .invalidOrExpired, .unsupportedEntitlement,
             .unsupportedMarket, .upgradeRequired:
            true
        default:
            false
        }
    }

    private static func allowsStaleFallback(_ error: ProviderBoundaryError) -> Bool {
        error == .offline || error == .timeout
    }

    private static func splits(
        from lookup: TransientMarketSessionLookup
    ) -> [MarketCorporateAction]? {
        switch lookup {
        case .fresh(let value), .stale(let value):
            guard case let .splits(actions) = value.payload else { return nil }
            return actions
        case .missing:
            return nil
        }
    }

    private static func dividends(
        from lookup: TransientMarketSessionLookup
    ) -> [MarketCorporateAction]? {
        switch lookup {
        case .fresh(let value), .stale(let value):
            guard case let .dividends(actions) = value.payload else { return nil }
            return actions
        case .missing:
            return nil
        }
    }

    private func historyKey(_ request: MarketHistoryRequest) -> String {
        [
            "history", request.instrument.symbol, request.instrument.mic,
            request.interval.rawValue, request.adjustment.rawValue,
            request.startDate?.description ?? "", request.endDate?.description ?? ""
        ].joined(separator: "|")
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

    private static func sortedActions(
        _ actions: [MarketCorporateAction]
    ) -> [MarketCorporateAction] {
        actions.sorted {
            ($0.effectiveDate, $0.kind.rawValue, $0.id) <
                ($1.effectiveDate, $1.kind.rawValue, $1.id)
        }
    }
}

actor ProviderCredentialCoordinator {
    private let credentialStore: any CredentialStore
    private let provider: any MarketDataProvider
    private let cache: MarketCacheStore
    private let sessionStore: TransientMarketSessionStore
    private let clock: any Clock

    init(
        credentialStore: any CredentialStore,
        provider: any MarketDataProvider,
        cache: MarketCacheStore,
        sessionStore: TransientMarketSessionStore = TransientMarketSessionStore(),
        clock: any Clock
    ) {
        self.credentialStore = credentialStore
        self.provider = provider
        self.cache = cache
        self.sessionStore = sessionStore
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
        let current = try await credentialStore.credential(
            for: TwelveDataClient.credentialDescriptor
        )
        guard current != data else { return }
        try await provider.prepareForCredentialChange()
        _ = try await sessionStore.clear(providerIdentifier: provider.descriptor.identifier)
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
        try await provider.disconnect()
        _ = try await sessionStore.clear(providerIdentifier: provider.descriptor.identifier)
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
