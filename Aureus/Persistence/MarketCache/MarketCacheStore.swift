import Foundation
import GRDB

struct MarketCacheEntry: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let providerIdentifier: String
    let logicalKey: String
    let dataType: MarketCacheDataType
    let payload: Data
    let byteSize: Int64
    let createdAt: UTCInstant
    let fetchedAt: UTCInstant
    let expiresAt: UTCInstant
    let lastAccessedAt: UTCInstant
    let sourceRevision: String?
    let entitlementContext: String
    let freshness: MarketFreshness
    let deletionPolicy: CacheDeletionPolicy

    init(
        id: String = UUID().uuidString,
        providerIdentifier: String,
        logicalKey: String,
        dataType: MarketCacheDataType,
        payload: Data,
        fetchedAt: UTCInstant,
        expiresAt: UTCInstant? = nil,
        sourceRevision: String? = nil,
        entitlementContext: String,
        freshness: MarketFreshness,
        deletionPolicy: CacheDeletionPolicy = .recoverable
    ) throws {
        guard !providerIdentifier.isEmpty, !logicalKey.isEmpty, !payload.isEmpty else {
            throw CachePolicyError.invalidEntry
        }
        let ttlEnd = fetchedAt.millisecondsSince1970.addingReportingOverflow(
            dataType.timeToLiveMilliseconds
        )
        guard !ttlEnd.overflow else { throw CachePolicyError.overflow }
        let effectiveExpiry = min(
            expiresAt?.millisecondsSince1970 ?? ttlEnd.partialValue,
            ttlEnd.partialValue
        )
        guard effectiveExpiry > fetchedAt.millisecondsSince1970 else {
            throw CachePolicyError.invalidEntry
        }
        self.id = id
        self.providerIdentifier = providerIdentifier
        self.logicalKey = logicalKey
        self.dataType = dataType
        self.payload = payload
        byteSize = Int64(payload.count)
        createdAt = fetchedAt
        self.fetchedAt = fetchedAt
        self.expiresAt = UTCInstant(millisecondsSince1970: effectiveExpiry)
        lastAccessedAt = fetchedAt
        self.sourceRevision = sourceRevision
        self.entitlementContext = entitlementContext
        self.freshness = freshness
        self.deletionPolicy = deletionPolicy
    }

    fileprivate init(
        id: String,
        providerIdentifier: String,
        logicalKey: String,
        dataType: MarketCacheDataType,
        payload: Data,
        byteSize: Int64,
        createdAt: UTCInstant,
        fetchedAt: UTCInstant,
        expiresAt: UTCInstant,
        lastAccessedAt: UTCInstant,
        sourceRevision: String?,
        entitlementContext: String,
        freshness: MarketFreshness,
        deletionPolicy: CacheDeletionPolicy
    ) throws {
        guard !providerIdentifier.isEmpty,
              !logicalKey.isEmpty,
              !payload.isEmpty,
              byteSize == Int64(payload.count),
              createdAt <= fetchedAt,
              fetchedAt < expiresAt,
              lastAccessedAt >= createdAt else {
            throw CachePolicyError.invalidEntry
        }
        self.id = id
        self.providerIdentifier = providerIdentifier
        self.logicalKey = logicalKey
        self.dataType = dataType
        self.payload = payload
        self.byteSize = byteSize
        self.createdAt = createdAt
        self.fetchedAt = fetchedAt
        self.expiresAt = expiresAt
        self.lastAccessedAt = lastAccessedAt
        self.sourceRevision = sourceRevision
        self.entitlementContext = entitlementContext
        self.freshness = freshness
        self.deletionPolicy = deletionPolicy
    }
}

enum MarketCacheLookup: Equatable, Sendable {
    case fresh(MarketCacheEntry)
    case stale(MarketCacheEntry)
    case missing
}

struct MarketCacheProviderUsage: Equatable, Identifiable, Sendable {
    var id: String { providerIdentifier }
    let providerIdentifier: String
    let bytes: Int64
    let entryCount: Int
}

struct MarketCacheStatistics: Equatable, Sendable {
    let currentBytes: Int64
    let maximumBytes: Int64
    let entryCount: Int
    let oldestEntry: UTCInstant?
    let lastCleanupAt: UTCInstant?
    let lastCleanupResult: String?
    let providerBreakdown: [MarketCacheProviderUsage]

    var percentageBasisPoints: Int64 {
        guard maximumBytes > 0 else { return 0 }
        return min(10_000, currentBytes * 10_000 / maximumBytes)
    }
}

enum CacheCleanupReason: String, Sendable {
    case launch
    case periodic
    case background
    case capacityChange
    case highWater
    case removeExpired
    case disconnect
    case credentialDeleted
    case confirmedTermination
    case sessionOnlyPolicy
    case manualReset
}

struct CacheCleanupResult: Equatable, Sendable {
    let reason: CacheCleanupReason
    let removedEntries: Int
    let removedBytes: Int64
    let remainingBytes: Int64
    let completedAt: UTCInstant
}

actor MarketCacheStore {
    nonisolated let databaseURL: URL
    nonisolated let policy: CachePolicyConfiguration

    private var queue: DatabaseQueue
    private let migrator: DatabaseMigrator
    private var effectivePolicy: CachePolicyConfiguration
    private var pendingAccesses: [String: UTCInstant] = [:]
    private let accessFlushThreshold = 32

    init(databaseURL: URL, policy: CachePolicyConfiguration = .default) throws {
        self.databaseURL = databaseURL
        self.policy = policy
        effectivePolicy = policy
        queue = try DatabaseQueueFactory.open(at: databaseURL)
        migrator = DatabaseMigrations.cacheMigrator()
        try migrator.migrate(queue)
        if let storedMaximum = try queue.read({ db in
            try Int64.fetchOne(
                db,
                sql: "SELECT integer_value FROM cache_metadata WHERE key = 'configured_maximum_bytes'"
            )
        }) {
            effectivePolicy = try Self.policy(maximumBytes: storedMaximum, basedOn: policy)
        }
    }

    func migrate() throws {
        try migrator.migrate(queue)
    }

    func schemaVersion() throws -> Int {
        try queue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT version FROM schema_metadata WHERE store_kind = 'market_cache'"
            ) ?? 0
        }
    }

    func foreignKeysEnabled() throws -> Bool {
        try queue.read { db in
            try Int.fetchOne(db, sql: "PRAGMA foreign_keys") == 1
        }
    }

    func seedSyntheticCache() throws {
        try queue.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO cached_instruments (
                    id, symbol, mic, currency_code, display_name, provider_identifier,
                    fetched_at_ms, expires_at_ms, last_accessed_at_ms, byte_size
                ) VALUES (
                    '00000000-0000-4000-8000-000000000401', 'SYN-CACHE', 'XSYN', 'CNY',
                    'Synthetic Cache Instrument', 'synthetic.stage2.market',
                    1768435200000, 1768521600000, 1768435200000, 256
                )
                """)
            try db.execute(sql: """
                INSERT OR REPLACE INTO cached_prices (
                    id, instrument_id, session_date, open_coefficient, high_coefficient,
                    low_coefficient, close_coefficient, volume_coefficient,
                    quote_currency_code, provider_identifier, fetched_at_ms,
                    expires_at_ms, last_accessed_at_ms, byte_size
                ) VALUES (
                    '00000000-0000-4000-8000-000000000402',
                    '00000000-0000-4000-8000-000000000401', '2026-01-15',
                    10000000000, 11000000000, 9000000000, 10500000000, 12300000000,
                    'CNY', 'synthetic.stage2.market', 1768435200000,
                    1768521600000, 1768435200000, 512
                )
                """)
        }
    }

    func store(
        _ entry: MarketCacheEntry,
        authorization: ProviderCacheAuthorization
    ) throws {
        guard authorization == .authorized else {
            throw CachePolicyError.persistentRetentionUnverified
        }
        guard entry.byteSize <= effectivePolicy.cleanupTargetBytes else {
            throw CachePolicyError.capacityCannotBeSatisfied
        }
        try flushAccessTimes()
        try queue.write { db in
            let existingBytes = try Int64.fetchOne(
                db,
                sql: """
                    SELECT byte_size FROM market_cache_entries
                    WHERE provider_identifier = ? AND logical_key = ? AND data_type = ?
                    """,
                arguments: [entry.providerIdentifier, entry.logicalKey, entry.dataType.rawValue]
            ) ?? 0
            let current = try currentBytes(in: db)
            let projected = current - existingBytes + entry.byteSize
            if projected > effectivePolicy.highWaterBytes {
                let cleanup = try cleanupForWrite(
                    in: db,
                    now: entry.fetchedAt,
                    projectedBytes: projected,
                    excludingID: entry.id
                )
                if cleanup.removedEntries > 0 {
                    try record(
                        CacheCleanupResult(
                            reason: .highWater,
                            removedEntries: cleanup.removedEntries,
                            removedBytes: cleanup.removedBytes,
                            remainingBytes: try currentBytes(in: db),
                            completedAt: entry.fetchedAt
                        ),
                        in: db
                    )
                }
            }
            let finalCurrent = try currentBytes(in: db) - existingBytes + entry.byteSize
            guard finalCurrent <= effectivePolicy.highWaterBytes else {
                throw CachePolicyError.capacityCannotBeSatisfied
            }
            try insert(entry, in: db)
        }
    }

    func lookup(
        providerIdentifier: String,
        logicalKey: String,
        dataType: MarketCacheDataType,
        now: UTCInstant,
        allowStale: Bool
    ) throws -> MarketCacheLookup {
        let row = try queue.read { db in
            try Row.fetchOne(
                db,
                sql: """
                    SELECT * FROM market_cache_entries
                    WHERE provider_identifier = ? AND logical_key = ? AND data_type = ?
                    """,
                arguments: [providerIdentifier, logicalKey, dataType.rawValue]
            )
        }
        guard let row else { return .missing }
        let entry = try decodeEntry(row)
        pendingAccesses[entry.id] = now
        if pendingAccesses.count >= accessFlushThreshold { try flushAccessTimes() }
        if entry.expiresAt >= now { return .fresh(entry) }
        return allowStale ? .stale(entry) : .missing
    }

    func flushAccessTimes() throws {
        guard !pendingAccesses.isEmpty else { return }
        let accesses = pendingAccesses
        try queue.write { db in
            for (id, instant) in accesses {
                try db.execute(
                    sql: "UPDATE market_cache_entries SET last_accessed_at_ms = ? WHERE id = ?",
                    arguments: [instant.millisecondsSince1970, id]
                )
            }
        }
        pendingAccesses.removeAll(keepingCapacity: true)
    }

    func removeExpired(now: UTCInstant) throws -> CacheCleanupResult {
        try flushAccessTimes()
        return try queue.write { db in
            let before = try currentBytes(in: db)
            let beforeCount = try cacheRowCount(in: db)
            for row in try cleanupRows(in: db)
                where row.expiresAt <= now.millisecondsSince1970 {
                try delete(row, in: db)
            }
            let after = try currentBytes(in: db)
            let afterCount = try cacheRowCount(in: db)
            let result = CacheCleanupResult(
                reason: .removeExpired,
                removedEntries: max(0, beforeCount - afterCount),
                removedBytes: max(0, before - after),
                remainingBytes: after,
                completedAt: now
            )
            try record(result, in: db)
            return result
        }
    }

    func performAutomaticCleanup(
        reason: CacheCleanupReason,
        now: UTCInstant
    ) throws -> CacheCleanupResult {
        try flushAccessTimes()
        return try queue.write { db in
            let before = try currentBytes(in: db)
            let beforeCount = try cacheRowCount(in: db)
            let rows = try cleanupRows(in: db)
            for row in orderedCleanupRows(rows, now: now) {
                let isExpired = row.expiresAt <= now.millisecondsSince1970
                let isAboveTarget = try currentBytes(in: db) > effectivePolicy.cleanupTargetBytes
                if isExpired || isAboveTarget {
                    try delete(row, in: db)
                }
            }
            let after = try currentBytes(in: db)
            let afterCount = try cacheRowCount(in: db)
            let result = CacheCleanupResult(
                reason: reason,
                removedEntries: max(0, beforeCount - afterCount),
                removedBytes: max(0, before - after),
                remainingBytes: after,
                completedAt: now
            )
            try record(result, in: db)
            return result
        }
    }

    func automaticCleanupIsDue(reason: CacheCleanupReason, now: UTCInstant) throws -> Bool {
        guard let schedule = Self.cleanupSchedule(for: reason) else { return false }
        let last = try queue.read { db in
            try Int64.fetchOne(
                db,
                sql: "SELECT integer_value FROM cache_metadata WHERE key = ?",
                arguments: [schedule.key]
            )
        }
        guard let last else { return true }
        return now.millisecondsSince1970 - last >= schedule.interval
    }

    func purge(providerIdentifier: String, reason: CacheCleanupReason, now: UTCInstant) throws -> CacheCleanupResult {
        precondition(
            reason == .disconnect || reason == .credentialDeleted ||
                reason == .confirmedTermination || reason == .sessionOnlyPolicy
        )
        try flushAccessTimes()
        return try queue.write { db in
            let before = try currentBytes(in: db)
            let beforeCount = try cacheRowCount(in: db)
            try db.execute(
                sql: "DELETE FROM market_cache_entries WHERE provider_identifier = ?",
                arguments: [providerIdentifier]
            )
            try db.execute(
                sql: "DELETE FROM cached_prices WHERE provider_identifier = ?",
                arguments: [providerIdentifier]
            )
            try db.execute(
                sql: "DELETE FROM cached_instruments WHERE provider_identifier = ?",
                arguments: [providerIdentifier]
            )
            let after = try currentBytes(in: db)
            let afterCount = try cacheRowCount(in: db)
            let result = CacheCleanupResult(
                reason: reason,
                removedEntries: max(0, beforeCount - afterCount),
                removedBytes: max(0, before - after),
                remainingBytes: after,
                completedAt: now
            )
            try record(result, in: db)
            return result
        }
    }

    func statistics() throws -> MarketCacheStatistics {
        try flushAccessTimes()
        return try queue.read { db in
            let current = try currentBytes(in: db)
            let count = try cacheRowCount(in: db)
            let oldest = try Int64.fetchOne(
                db,
                sql: """
                    SELECT MIN(value) FROM (
                        SELECT created_at_ms AS value FROM market_cache_entries
                        UNION ALL SELECT fetched_at_ms FROM cached_instruments
                        UNION ALL SELECT fetched_at_ms FROM cached_prices
                    )
                    """
            ).map(UTCInstant.init(millisecondsSince1970:))
            let cleanupAt = try Int64.fetchOne(
                db,
                sql: "SELECT integer_value FROM cache_metadata WHERE key = 'last_cleanup_ms'"
            ).map(UTCInstant.init(millisecondsSince1970:))
            let result = try String.fetchOne(
                db,
                sql: "SELECT text_value FROM cache_metadata WHERE key = 'last_cleanup_result'"
            )
            let providerRows = try Row.fetchAll(db, sql: """
                SELECT provider_identifier, SUM(byte_size) AS bytes, COUNT(*) AS entry_count
                FROM (
                    SELECT provider_identifier, byte_size FROM market_cache_entries
                    UNION ALL SELECT provider_identifier, byte_size FROM cached_instruments
                    UNION ALL SELECT provider_identifier, byte_size FROM cached_prices
                )
                GROUP BY provider_identifier
                ORDER BY provider_identifier
                """)
            let providers = providerRows.map { row in
                MarketCacheProviderUsage(
                    providerIdentifier: row["provider_identifier"],
                    bytes: row["bytes"],
                    entryCount: row["entry_count"]
                )
            }
            return MarketCacheStatistics(
                currentBytes: current,
                maximumBytes: effectivePolicy.maximumBytes,
                entryCount: count,
                oldestEntry: oldest,
                lastCleanupAt: cleanupAt,
                lastCleanupResult: result,
                providerBreakdown: providers
            )
        }
    }

    func cachedRowCount() throws -> Int {
        try queue.read { db in try cacheRowCount(in: db) }
    }

    @discardableResult
    func updateMaximumBytes(
        _ maximumBytes: Int64,
        now: UTCInstant
    ) throws -> CacheCleanupResult {
        let updated = try Self.policy(maximumBytes: maximumBytes, basedOn: policy)
        let accesses = pendingAccesses
        let result = try queue.write { db in
            try applyAccesses(accesses, in: db)
            let before = try currentBytes(in: db)
            let beforeCount = try cacheRowCount(in: db)
            if before > updated.highWaterBytes {
                for row in orderedCleanupRows(try cleanupRows(in: db), now: now) {
                    if try currentBytes(in: db) <= updated.cleanupTargetBytes { break }
                    try delete(row, in: db)
                }
                guard try currentBytes(in: db) <= updated.cleanupTargetBytes else {
                    throw CachePolicyError.capacityCannotBeSatisfied
                }
            }
            try db.execute(sql: """
                INSERT INTO cache_metadata(key, integer_value, text_value)
                VALUES ('configured_maximum_bytes', ?, NULL)
                ON CONFLICT(key) DO UPDATE SET integer_value = excluded.integer_value
                """, arguments: [maximumBytes])
            let after = try currentBytes(in: db)
            let afterCount = try cacheRowCount(in: db)
            let result = CacheCleanupResult(
                reason: .capacityChange,
                removedEntries: max(0, beforeCount - afterCount),
                removedBytes: max(0, before - after),
                remainingBytes: after,
                completedAt: now
            )
            try record(result, in: db)
            return result
        }
        pendingAccesses.removeAll(keepingCapacity: true)
        effectivePolicy = updated
        return result
    }

    func reset() throws {
        pendingAccesses.removeAll()
        effectivePolicy = policy
        try queue.close()
        let fileManager = FileManager.default
        let ownedPaths = [
            databaseURL.path,
            databaseURL.path + "-wal",
            databaseURL.path + "-shm",
            databaseURL.path + "-journal"
        ]
        for path in ownedPaths where fileManager.fileExists(atPath: path) {
            try fileManager.removeItem(atPath: path)
        }
        queue = try DatabaseQueueFactory.open(at: databaseURL)
        try migrator.migrate(queue)
    }

    private func insert(_ entry: MarketCacheEntry, in db: Database) throws {
        try db.execute(sql: """
            INSERT INTO market_cache_entries (
                id, provider_identifier, logical_key, data_type, payload, payload_format,
                byte_size, created_at_ms, fetched_at_ms, expires_at_ms,
                last_accessed_at_ms, source_revision, entitlement_context, freshness,
                deletion_policy
            ) VALUES (?, ?, ?, ?, ?, 'validated-domain-json-v1', ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(provider_identifier, logical_key, data_type) DO UPDATE SET
                id = excluded.id,
                payload = excluded.payload,
                byte_size = excluded.byte_size,
                created_at_ms = excluded.created_at_ms,
                fetched_at_ms = excluded.fetched_at_ms,
                expires_at_ms = excluded.expires_at_ms,
                last_accessed_at_ms = excluded.last_accessed_at_ms,
                source_revision = excluded.source_revision,
                entitlement_context = excluded.entitlement_context,
                freshness = excluded.freshness,
                deletion_policy = excluded.deletion_policy
            """, arguments: [
                entry.id, entry.providerIdentifier, entry.logicalKey, entry.dataType.rawValue,
                entry.payload, entry.byteSize, entry.createdAt.millisecondsSince1970,
                entry.fetchedAt.millisecondsSince1970, entry.expiresAt.millisecondsSince1970,
                entry.lastAccessedAt.millisecondsSince1970, entry.sourceRevision,
                entry.entitlementContext, entry.freshness.rawValue,
                entry.deletionPolicy.rawValue
            ])
    }

    private func applyAccesses(
        _ accesses: [String: UTCInstant],
        in db: Database
    ) throws {
        for (id, instant) in accesses {
            try db.execute(
                sql: "UPDATE market_cache_entries SET last_accessed_at_ms = ? WHERE id = ?",
                arguments: [instant.millisecondsSince1970, id]
            )
        }
    }

    private func decodeEntry(_ row: Row) throws -> MarketCacheEntry {
        guard let dataType = MarketCacheDataType(rawValue: row["data_type"]),
              let freshness = MarketFreshness(rawValue: row["freshness"]),
              let deletionPolicy = CacheDeletionPolicy(rawValue: row["deletion_policy"]) else {
            throw CachePolicyError.invalidEntry
        }
        return try MarketCacheEntry(
            id: row["id"],
            providerIdentifier: row["provider_identifier"],
            logicalKey: row["logical_key"],
            dataType: dataType,
            payload: row["payload"],
            byteSize: row["byte_size"],
            createdAt: UTCInstant(millisecondsSince1970: row["created_at_ms"]),
            fetchedAt: UTCInstant(millisecondsSince1970: row["fetched_at_ms"]),
            expiresAt: UTCInstant(millisecondsSince1970: row["expires_at_ms"]),
            lastAccessedAt: UTCInstant(millisecondsSince1970: row["last_accessed_at_ms"]),
            sourceRevision: row["source_revision"],
            entitlementContext: row["entitlement_context"],
            freshness: freshness,
            deletionPolicy: deletionPolicy
        )
    }

    private enum CleanupSource {
        case current
        case legacyPrice
        case legacyInstrument
    }

    private struct CleanupRow {
        let id: String
        let source: CleanupSource
        let dataType: MarketCacheDataType
        let byteSize: Int64
        let expiresAt: Int64
        let lastAccessedAt: Int64
    }

    private func cleanupRows(in db: Database) throws -> [CleanupRow] {
        let current: [CleanupRow] = try Row.fetchAll(db, sql: """
            SELECT id, data_type, byte_size, expires_at_ms, last_accessed_at_ms
            FROM market_cache_entries
            """).compactMap { (row: Row) -> CleanupRow? in
                guard let type = MarketCacheDataType(rawValue: row["data_type"]) else { return nil }
                return CleanupRow(
                    id: row["id"],
                    source: .current,
                    dataType: type,
                    byteSize: row["byte_size"],
                    expiresAt: row["expires_at_ms"],
                    lastAccessedAt: row["last_accessed_at_ms"]
                )
            }
        let legacyPrices = try Row.fetchAll(db, sql: """
            SELECT id, byte_size, expires_at_ms, last_accessed_at_ms
            FROM cached_prices
            """).map { row in
                CleanupRow(
                    id: row["id"],
                    source: .legacyPrice,
                    dataType: .eodHistorical,
                    byteSize: row["byte_size"],
                    expiresAt: row["expires_at_ms"],
                    lastAccessedAt: row["last_accessed_at_ms"]
                )
            }
        let legacyInstruments = try Row.fetchAll(db, sql: """
            SELECT id, byte_size, expires_at_ms, last_accessed_at_ms
            FROM cached_instruments
            """).map { row in
                CleanupRow(
                    id: row["id"],
                    source: .legacyInstrument,
                    dataType: .symbolMetadata,
                    byteSize: row["byte_size"],
                    expiresAt: row["expires_at_ms"],
                    lastAccessedAt: row["last_accessed_at_ms"]
                )
            }
        return current + legacyPrices + legacyInstruments
    }

    private func orderedCleanupRows(_ rows: [CleanupRow], now: UTCInstant) -> [CleanupRow] {
        rows.sorted { lhs, rhs in
            let leftExpired = lhs.expiresAt <= now.millisecondsSince1970
            let rightExpired = rhs.expiresAt <= now.millisecondsSince1970
            if leftExpired != rightExpired { return leftExpired && !rightExpired }
            if lhs.dataType.cleanupPriority != rhs.dataType.cleanupPriority {
                return lhs.dataType.cleanupPriority < rhs.dataType.cleanupPriority
            }
            return (lhs.lastAccessedAt, lhs.id) < (rhs.lastAccessedAt, rhs.id)
        }
    }

    private func cleanupForWrite(
        in db: Database,
        now: UTCInstant,
        projectedBytes: Int64,
        excludingID: String
    ) throws -> (removedEntries: Int, removedBytes: Int64) {
        let beforeBytes = try currentBytes(in: db)
        let beforeCount = try cacheRowCount(in: db)
        let ordered = orderedCleanupRows(try cleanupRows(in: db), now: now)
            .filter { $0.id != excludingID }
        var after = projectedBytes
        var selected: [CleanupRow] = []
        for row in ordered where after > effectivePolicy.cleanupTargetBytes {
            selected.append(row)
            after -= row.byteSize
        }
        guard after <= effectivePolicy.cleanupTargetBytes else {
            throw CachePolicyError.capacityCannotBeSatisfied
        }
        for row in selected {
            try delete(row, in: db)
        }
        let remainingBytes = try currentBytes(in: db)
        let remainingCount = try cacheRowCount(in: db)
        return (
            max(0, beforeCount - remainingCount),
            max(0, beforeBytes - remainingBytes)
        )
    }

    private func currentBytes(in db: Database) throws -> Int64 {
        let v2 = try Int64.fetchOne(
            db,
            sql: "SELECT COALESCE(SUM(byte_size), 0) FROM market_cache_entries"
        ) ?? 0
        let instruments = try Int64.fetchOne(
            db,
            sql: "SELECT COALESCE(SUM(byte_size), 0) FROM cached_instruments"
        ) ?? 0
        let prices = try Int64.fetchOne(
            db,
            sql: "SELECT COALESCE(SUM(byte_size), 0) FROM cached_prices"
        ) ?? 0
        let first = v2.addingReportingOverflow(instruments)
        let second = first.partialValue.addingReportingOverflow(prices)
        guard !first.overflow, !second.overflow else { throw CachePolicyError.overflow }
        return second.partialValue
    }

    private func delete(_ row: CleanupRow, in db: Database) throws {
        let table: String
        switch row.source {
        case .current: table = "market_cache_entries"
        case .legacyPrice: table = "cached_prices"
        case .legacyInstrument: table = "cached_instruments"
        }
        try db.execute(sql: "DELETE FROM \(table) WHERE id = ?", arguments: [row.id])
    }

    private func cacheRowCount(in db: Database) throws -> Int {
        let instruments = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM cached_instruments"
        ) ?? 0
        let prices = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cached_prices") ?? 0
        let entries = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM market_cache_entries"
        ) ?? 0
        return instruments + prices + entries
    }

    private func record(_ result: CacheCleanupResult, in db: Database) throws {
        if let schedule = Self.cleanupSchedule(for: result.reason) {
            try db.execute(sql: """
                INSERT INTO cache_metadata(key, integer_value, text_value)
                VALUES (?, ?, NULL)
                ON CONFLICT(key) DO UPDATE SET integer_value = excluded.integer_value
                """, arguments: [schedule.key, result.completedAt.millisecondsSince1970])
        }
        try db.execute(sql: """
            INSERT INTO cache_metadata(key, integer_value, text_value)
            VALUES ('last_cleanup_ms', ?, NULL)
            ON CONFLICT(key) DO UPDATE SET integer_value = excluded.integer_value
            """, arguments: [result.completedAt.millisecondsSince1970])
        try db.execute(sql: """
            INSERT INTO cache_metadata(key, integer_value, text_value)
            VALUES ('last_cleanup_result', NULL, ?)
            ON CONFLICT(key) DO UPDATE SET text_value = excluded.text_value
            """, arguments: [
                "\(result.reason.rawValue): removed \(result.removedEntries) recoverable entries"
            ])
    }

    private static func cleanupSchedule(
        for reason: CacheCleanupReason
    ) -> (key: String, interval: Int64)? {
        switch reason {
        case .launch:
            ("last_launch_cleanup_ms", 24 * 60 * 60 * 1_000)
        case .periodic:
            ("last_periodic_cleanup_ms", 6 * 60 * 60 * 1_000)
        case .background:
            ("last_background_cleanup_ms", 6 * 60 * 60 * 1_000)
        default:
            nil
        }
    }

    private static func policy(
        maximumBytes: Int64,
        basedOn base: CachePolicyConfiguration
    ) throws -> CachePolicyConfiguration {
        if base.maximumBytes < CachePolicyConfiguration.minimumMaximumBytes {
            return try .testing(maximumBytes: maximumBytes)
        }
        return try CachePolicyConfiguration(
            maximumBytes: maximumBytes,
            highWaterBasisPoints: base.highWaterBasisPoints,
            cleanupTargetBasisPoints: base.cleanupTargetBasisPoints
        )
    }
}
