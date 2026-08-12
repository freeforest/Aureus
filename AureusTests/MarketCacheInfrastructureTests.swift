import CryptoKit
import Foundation
import GRDB
import Testing
@testable import Aureus

enum CacheIsolationOperation: String, CaseIterable, Sendable {
    case automaticTTL
    case highWater
    case lru
    case removeExpired
    case providerPurge
    case credentialDelete
    case disconnect
    case confirmedTermination
    case capacityChange
    case reset
}

@Suite("Stage 6 bounded Market Cache")
struct MarketCacheInfrastructureTests {
    private let now = UTCInstant(millisecondsSince1970: 1_768_435_200_000)

    @Test("Typed TTLs, retention, production bounds, and watermarks are frozen")
    func typedPolicy() throws {
        let minute: Int64 = 60_000
        let hour = 60 * minute
        let day = 24 * hour

        #expect(MarketCacheDataType.latestQuote.timeToLiveMilliseconds == 15 * minute)
        #expect(MarketCacheDataType.marketStatus.timeToLiveMilliseconds == 15 * minute)
        #expect(MarketCacheDataType.symbolSearch.timeToLiveMilliseconds == 7 * day)
        #expect(MarketCacheDataType.symbolMetadata.timeToLiveMilliseconds == 7 * day)
        #expect(MarketCacheDataType.eodRecent.timeToLiveMilliseconds == 12 * hour)
        #expect(MarketCacheDataType.eodHistorical.timeToLiveMilliseconds == 30 * day)
        #expect(MarketCacheDataType.intraday.timeToLiveMilliseconds == 15 * minute)
        #expect(MarketCacheDataType.intraday.maximumRetentionMilliseconds == 30 * day)
        #expect(MarketCacheDataType.derivedHeatmap.timeToLiveMilliseconds == 15 * minute)
        #expect(MarketCacheDataType.derivedIndicator.timeToLiveMilliseconds == 24 * hour)
        #expect(MarketCacheDataType.fxRate.timeToLiveMilliseconds == 24 * hour)

        let policy = CachePolicyConfiguration.default
        #expect(policy.maximumBytes == 512 * CachePolicyConfiguration.mebibyte)
        #expect(CachePolicyConfiguration.minimumMaximumBytes == 128 * CachePolicyConfiguration.mebibyte)
        #expect(CachePolicyConfiguration.maximumMaximumBytes == 4 * CachePolicyConfiguration.gibibyte)
        #expect(policy.highWaterBasisPoints == 9_000)
        #expect(policy.cleanupTargetBasisPoints == 8_000)
    }

    @Test("Cache v1 migrates append-only to v2, preserves legacy rows, reopens, and is idempotent")
    func cacheMigration() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("cache/market-cache.sqlite")
        let queue = try DatabaseQueueFactory.open(at: url)
        let migrator = DatabaseMigrations.cacheMigrator()
        try migrator.migrate(queue, upTo: DatabaseMigrations.cacheV1)
        try await queue.write { db in
            try db.execute(sql: """
                INSERT INTO cached_instruments (
                    id, symbol, mic, currency_code, display_name, provider_identifier,
                    fetched_at_ms, expires_at_ms, last_accessed_at_ms, byte_size
                ) VALUES (
                    'synthetic-v1-cache', 'SYN', 'XSYN', 'CNY', 'Synthetic Legacy Cache',
                    'synthetic.legacy', 1, 9999999999999, 1, 64
                )
                """)
        }
        try migrator.migrate(queue)
        try migrator.migrate(queue)

        let state = try await queue.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT version FROM schema_metadata") ?? 0,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cached_instruments") ?? 0,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='market_cache_entries'") ?? 0
            )
        }
        #expect(state.0 == 2)
        #expect(state.1 == 1)
        #expect(state.2 == 1)

        let reopened = try MarketCacheStore(databaseURL: url)
        #expect(try await reopened.schemaVersion() == 2)
        #expect(try await reopened.cachedRowCount() == 1)
    }

    @Test("Legacy v1 cache participates in high-water cleanup and cannot block a current write")
    func legacyCapacityGovernance() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheURL = root.appendingPathComponent("cache/market-cache.sqlite")
        let wealth = try WealthStore(
            databaseURL: root.appendingPathComponent("permanent/aureus.sqlite")
        )
        try await wealth.insertIsolationSentinel(
            id: "00000000-0000-4000-8000-0000000065A0",
            name: "Synthetic Legacy Cache Isolation Sentinel"
        )
        try await wealth.seedSyntheticWealth()
        try await SyntheticLedgerSeeder.seed(in: wealth)
        try await SyntheticDashboardSeeder.seed(in: wealth)
        try await wealth.checkpoint()
        let permanentBefore = try await permanentState(store: wealth)

        let queue = try DatabaseQueueFactory.open(at: cacheURL)
        let migrator = DatabaseMigrations.cacheMigrator()
        try migrator.migrate(queue, upTo: DatabaseMigrations.cacheV1)
        try await queue.write { db in
            for index in 1...2 {
                try db.execute(sql: """
                    INSERT INTO cached_instruments (
                        id, symbol, mic, currency_code, display_name, provider_identifier,
                        fetched_at_ms, expires_at_ms, last_accessed_at_ms, byte_size
                    ) VALUES (?, ?, 'XSYN', 'CNY', ?, 'synthetic.legacy', 1, 9999999999999, ?, 200)
                    """, arguments: [
                        "legacy-instrument-\(index)", "SYN\(index)",
                        "Synthetic Legacy \(index)", index
                    ])
                try db.execute(sql: """
                    INSERT INTO cached_prices (
                        id, instrument_id, session_date, open_coefficient, high_coefficient,
                        low_coefficient, close_coefficient, volume_coefficient,
                        quote_currency_code, provider_identifier, fetched_at_ms,
                        expires_at_ms, last_accessed_at_ms, byte_size
                    ) VALUES (?, ?, ?, 1, 1, 1, 1, 1, 'CNY', 'synthetic.legacy', 1, 9999999999999, ?, ?)
                    """, arguments: [
                        "legacy-price-\(index)", "legacy-instrument-\(index)",
                        "2026-01-1\(index)", index, index == 1 ? 400 : 200
                    ])
            }
        }
        try queue.close()

        let cache = try MarketCacheStore(
            databaseURL: cacheURL,
            policy: try .testing(maximumBytes: 1_000)
        )
        let cleanup = try await cache.performAutomaticCleanup(reason: .launch, now: now)
        #expect(cleanup.remainingBytes <= 800)
        #expect(cleanup.removedEntries == 2)
        try await cache.store(
            makeEntry(key: "current-after-legacy-cleanup", payloadSize: 100),
            authorization: .authorized
        )
        #expect(try await cache.statistics().currentBytes <= 800)

        let inspection = try DatabaseQueueFactory.open(at: cacheURL)
        let legacyState = try await inspection.read { db in
            (
                try String.fetchAll(
                    db,
                    sql: "SELECT id FROM cached_instruments ORDER BY id"
                ),
                try String.fetchAll(db, sql: "SELECT id FROM cached_prices ORDER BY id"),
                try Int.fetchOne(
                    db,
                    sql: "PRAGMA foreign_key_check"
                )
            )
        }
        #expect(legacyState.0 == ["legacy-instrument-2"])
        #expect(legacyState.1 == ["legacy-price-2"])
        #expect(legacyState.2 == nil)

        try await wealth.checkpoint()
        let permanentAfter = try await permanentState(store: wealth)
        #expect(permanentBefore.url == permanentAfter.url)
        #expect(permanentBefore.hash == permanentAfter.hash)
        #expect(permanentBefore.schemaVersion == permanentAfter.schemaVersion)
        #expect(permanentBefore.sentinels == permanentAfter.sentinels)
        #expect(permanentBefore.wealth == permanentAfter.wealth)
        #expect(permanentBefore.ledger == permanentAfter.ledger)
        #expect(permanentBefore.snapshots == permanentAfter.snapshots)
    }

    @Test("Failed cache migration rolls back its partial write")
    func cacheMigrationRollback() throws {
        enum SyntheticFailure: Error { case injected }
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("cache/market-cache.sqlite")
        let queue = try DatabaseQueueFactory.open(at: url)
        try DatabaseMigrations.cacheMigrator().migrate(queue)
        var failing = DatabaseMigrator()
        failing.registerMigration("synthetic_cache_failure") { db in
            try db.execute(
                sql: "INSERT INTO cache_metadata(key, text_value) VALUES ('partial', 'synthetic')"
            )
            throw SyntheticFailure.injected
        }
        #expect(throws: SyntheticFailure.injected) { try failing.migrate(queue) }
        #expect(try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cache_metadata WHERE key='partial'")
        } == 0)
    }

    @Test("Fresh, stale, offline-eligible, and missing cache states are explicit")
    func freshnessStates() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try MarketCacheStore(databaseURL: root.appendingPathComponent("cache.sqlite"))
        let entry = try makeEntry(key: "freshness", type: .latestQuote, payloadSize: 64)
        try await cache.store(entry, authorization: .authorized)

        #expect(try await cache.lookup(
            providerIdentifier: "synthetic.provider", logicalKey: "freshness",
            dataType: .latestQuote, now: now, allowStale: false
        ) == .fresh(entry))
        let expiredNow = UTCInstant(millisecondsSince1970: entry.expiresAt.millisecondsSince1970 + 1)
        #expect(try await cache.lookup(
            providerIdentifier: "synthetic.provider", logicalKey: "freshness",
            dataType: .latestQuote, now: expiredNow, allowStale: true
        ) == .stale(entry))
        #expect(try await cache.lookup(
            providerIdentifier: "synthetic.provider", logicalKey: "freshness",
            dataType: .latestQuote, now: expiredNow, allowStale: false
        ) == .missing)
        #expect(try await cache.lookup(
            providerIdentifier: "synthetic.provider", logicalKey: "absent",
            dataType: .latestQuote, now: now, allowStale: true
        ) == .missing)
        let unknown = try makeEntry(
            key: "unknown-freshness", type: .latestQuote, freshness: .unknown
        )
        try await cache.store(unknown, authorization: .authorized)
        #expect(try await cache.lookup(
            providerIdentifier: "synthetic.provider", logicalKey: "unknown-freshness",
            dataType: .latestQuote, now: now, allowStale: false
        ) == .fresh(unknown))
    }

    @Test("Unverified retention rejects persistent Twelve data without replacing old cache")
    func retentionAndFailedWritePreservation() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let policy = try CachePolicyConfiguration.testing(maximumBytes: 1_000)
        let cache = try MarketCacheStore(
            databaseURL: root.appendingPathComponent("cache.sqlite"),
            policy: policy
        )
        let old = try makeEntry(key: "same", payloadSize: 100)
        try await cache.store(old, authorization: .authorized)
        let replacement = try makeEntry(key: "same", payloadSize: 900)

        await #expect(throws: CachePolicyError.persistentRetentionUnverified) {
            try await cache.store(replacement, authorization: .unverified)
        }
        await #expect(throws: CachePolicyError.capacityCannotBeSatisfied) {
            try await cache.store(replacement, authorization: .authorized)
        }
        #expect(try await cache.lookup(
            providerIdentifier: "synthetic.provider", logicalKey: "same",
            dataType: .eodHistorical, now: now, allowStale: false
        ) == .fresh(old))
    }

    @Test("High-water cleanup follows typed priority before recoverable OHLCV")
    func cleanupPriority() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try MarketCacheStore(
            databaseURL: root.appendingPathComponent("cache.sqlite"),
            policy: try .testing(maximumBytes: 1_000)
        )
        try await cache.store(makeEntry(key: "history", type: .eodHistorical, payloadSize: 300), authorization: .authorized)
        try await cache.store(makeEntry(key: "derived", type: .derivedIndicator, payloadSize: 300), authorization: .authorized)
        try await cache.store(makeEntry(key: "quote", type: .latestQuote, payloadSize: 300), authorization: .authorized)
        try await cache.store(makeEntry(key: "new", type: .eodHistorical, payloadSize: 100), authorization: .authorized)

        #expect(try await cache.lookup(
            providerIdentifier: "synthetic.provider", logicalKey: "derived",
            dataType: .derivedIndicator, now: now, allowStale: true
        ) == .missing)
        #expect(try await cache.lookup(
            providerIdentifier: "synthetic.provider", logicalKey: "history",
            dataType: .eodHistorical, now: now, allowStale: true
        ) != .missing)
        #expect(try await cache.statistics().currentBytes <= 800)
        #expect(try await cache.statistics().lastCleanupResult?.contains("highWater") == true)
    }

    @Test("LRU metadata protects a recently accessed peer")
    func lru() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try MarketCacheStore(
            databaseURL: root.appendingPathComponent("cache.sqlite"),
            policy: try .testing(maximumBytes: 1_000)
        )
        let old = UTCInstant(millisecondsSince1970: now.millisecondsSince1970 - 10_000)
        try await cache.store(makeEntry(key: "a", fetchedAt: old, payloadSize: 300), authorization: .authorized)
        try await cache.store(makeEntry(key: "b", fetchedAt: old, payloadSize: 300), authorization: .authorized)
        try await cache.store(makeEntry(key: "c", fetchedAt: old, payloadSize: 300), authorization: .authorized)
        _ = try await cache.lookup(
            providerIdentifier: "synthetic.provider", logicalKey: "a",
            dataType: .eodHistorical, now: now, allowStale: true
        )
        try await cache.store(makeEntry(key: "d", payloadSize: 100), authorization: .authorized)

        #expect(try await cache.lookup(
            providerIdentifier: "synthetic.provider", logicalKey: "a",
            dataType: .eodHistorical, now: now, allowStale: true
        ) != .missing)
        let peerB = try await cache.lookup(
            providerIdentifier: "synthetic.provider", logicalKey: "b",
            dataType: .eodHistorical, now: now, allowStale: true
        )
        let peerC = try await cache.lookup(
            providerIdentifier: "synthetic.provider", logicalKey: "c",
            dataType: .eodHistorical, now: now, allowStale: true
        )
        let peerStates = [peerB, peerC]
        #expect(peerStates.filter { $0 == .missing }.count == 1)
    }

    @Test("Provider purge is scoped and reset rebuilds only cache v2")
    func providerPurgeAndReset() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try MarketCacheStore(databaseURL: root.appendingPathComponent("cache.sqlite"))
        try await cache.store(makeEntry(provider: "twelve-data", key: "a"), authorization: .authorized)
        try await cache.store(makeEntry(provider: "frankfurter.ecb", key: "b"), authorization: .authorized)
        _ = try await cache.purge(providerIdentifier: "twelve-data", reason: .disconnect, now: now)

        #expect(try await cache.lookup(
            providerIdentifier: "twelve-data", logicalKey: "a",
            dataType: .eodHistorical, now: now, allowStale: true
        ) == .missing)
        #expect(try await cache.lookup(
            providerIdentifier: "frankfurter.ecb", logicalKey: "b",
            dataType: .eodHistorical, now: now, allowStale: true
        ) != .missing)
        try await cache.reset()
        #expect(try await cache.schemaVersion() == 2)
        #expect(try await cache.cachedRowCount() == 0)
    }

    @Test("Launch, periodic, and background cleanup use independent matching due metadata")
    func cleanupScheduleBookkeeping() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try MarketCacheStore(databaseURL: root.appendingPathComponent("cache.sqlite"))

        #expect(try await cache.automaticCleanupIsDue(reason: .launch, now: now))
        #expect(try await cache.automaticCleanupIsDue(reason: .periodic, now: now))
        #expect(try await cache.automaticCleanupIsDue(reason: .background, now: now))

        _ = try await cache.performAutomaticCleanup(reason: .background, now: now)
        #expect(try await cache.automaticCleanupIsDue(reason: .background, now: now) == false)
        #expect(try await cache.automaticCleanupIsDue(reason: .periodic, now: now))
        #expect(try await cache.automaticCleanupIsDue(reason: .launch, now: now))

        _ = try await cache.removeExpired(now: now)
        #expect(try await cache.automaticCleanupIsDue(reason: .periodic, now: now))
        let sixHoursLater = UTCInstant(
            millisecondsSince1970: now.millisecondsSince1970 + 6 * 60 * 60 * 1_000
        )
        #expect(try await cache.automaticCleanupIsDue(
            reason: .background,
            now: sixHoursLater
        ))
    }

    @Test("Capacity reduction atomically converges mixed legacy and current cache and persists")
    func capacityReductionMixedCache() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("cache.sqlite")
        let initial = try CachePolicyConfiguration.testing(maximumBytes: 2_000)
        let cache = try MarketCacheStore(databaseURL: url, policy: initial)
        let expiredFetch = UTCInstant(
            millisecondsSince1970: now.millisecondsSince1970
                - MarketCacheDataType.derivedIndicator.timeToLiveMilliseconds - 1
        )
        try await cache.store(
            makeEntry(key: "expired-derived", type: .derivedIndicator, fetchedAt: expiredFetch, payloadSize: 200),
            authorization: .authorized
        )
        try await cache.store(
            makeEntry(key: "fresh-quote", type: .latestQuote, payloadSize: 200),
            authorization: .authorized
        )
        try await cache.store(
            makeEntry(key: "fresh-history", payloadSize: 300),
            authorization: .authorized
        )
        let inspection = try DatabaseQueueFactory.open(at: url)
        try await inspection.write { db in
            try db.execute(sql: """
                INSERT INTO cached_instruments (
                    id, symbol, mic, currency_code, display_name, provider_identifier,
                    fetched_at_ms, expires_at_ms, last_accessed_at_ms, byte_size
                ) VALUES ('legacy-capacity-instrument', 'SYN-CAP', 'XSYN', 'CNY',
                    'Synthetic Capacity Legacy', 'synthetic.legacy', ?, ?, ?, 200)
                """, arguments: [
                    now.millisecondsSince1970,
                    now.millisecondsSince1970 + 1_000_000,
                    now.millisecondsSince1970
                ])
            try db.execute(sql: """
                INSERT INTO cached_prices (
                    id, instrument_id, session_date, open_coefficient, high_coefficient,
                    low_coefficient, close_coefficient, volume_coefficient,
                    quote_currency_code, provider_identifier, fetched_at_ms,
                    expires_at_ms, last_accessed_at_ms, byte_size
                ) VALUES ('legacy-capacity-price', 'legacy-capacity-instrument', '2026-01-14',
                    1, 1, 1, 1, 1, 'CNY', 'synthetic.legacy', ?, ?, ?, 300)
                """, arguments: [
                    now.millisecondsSince1970 - 2_000,
                    now.millisecondsSince1970 - 1,
                    now.millisecondsSince1970 - 2_000
                ])
        }
        try inspection.close()

        #expect(try await cache.automaticCleanupIsDue(reason: .periodic, now: now))
        #expect(try await cache.automaticCleanupIsDue(reason: .background, now: now))
        let result = try await cache.updateMaximumBytes(1_000, now: now)
        #expect(result.reason == .capacityChange)
        #expect(result.removedEntries == 2)
        #expect(result.removedBytes == 500)
        #expect(result.remainingBytes <= 800)
        #expect(try await cache.automaticCleanupIsDue(reason: .periodic, now: now))
        #expect(try await cache.automaticCleanupIsDue(reason: .background, now: now))
        #expect(try await cache.lookup(
            providerIdentifier: "synthetic.provider", logicalKey: "expired-derived",
            dataType: .derivedIndicator, now: now, allowStale: true
        ) == .missing)

        let post = try DatabaseQueueFactory.open(at: url)
        let legacyCounts = try await post.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cached_instruments") ?? -1,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cached_prices") ?? -1
            )
        }
        try post.close()
        #expect(legacyCounts == (1, 0))
        #expect(try await cache.statistics().lastCleanupResult?.contains("capacityChange") == true)

        let reopened = try MarketCacheStore(databaseURL: url, policy: initial)
        #expect(try await reopened.statistics().maximumBytes == 1_000)
        #expect(try await reopened.statistics().currentBytes <= 800)
    }

    @Test("Capacity reduction uses expired then priority then LRU order")
    func capacityReductionOrdering() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try MarketCacheStore(
            databaseURL: root.appendingPathComponent("cache.sqlite"),
            policy: try .testing(maximumBytes: 2_000)
        )
        let expiredHistory = UTCInstant(
            millisecondsSince1970: now.millisecondsSince1970
                - MarketCacheDataType.eodHistorical.timeToLiveMilliseconds - 1
        )
        let oldQuote = UTCInstant(millisecondsSince1970: now.millisecondsSince1970 - 300_000)
        try await cache.store(makeEntry(key: "expired-history", fetchedAt: expiredHistory, payloadSize: 100), authorization: .authorized)
        try await cache.store(makeEntry(key: "derived", type: .derivedIndicator, payloadSize: 100), authorization: .authorized)
        try await cache.store(makeEntry(key: "old-quote", type: .latestQuote, fetchedAt: oldQuote, payloadSize: 100), authorization: .authorized)
        try await cache.store(makeEntry(key: "new-quote", type: .latestQuote, payloadSize: 400), authorization: .authorized)
        try await cache.store(makeEntry(key: "history", payloadSize: 400), authorization: .authorized)

        let result = try await cache.updateMaximumBytes(1_000, now: now)
        #expect(result.removedEntries == 3)
        #expect(result.remainingBytes == 800)
        for (key, type) in [
            ("expired-history", MarketCacheDataType.eodHistorical),
            ("derived", .derivedIndicator),
            ("old-quote", .latestQuote)
        ] {
            #expect(try await cache.lookup(
                providerIdentifier: "synthetic.provider", logicalKey: key,
                dataType: type, now: now, allowStale: true
            ) == .missing)
        }
        #expect(try await cache.lookup(
            providerIdentifier: "synthetic.provider", logicalKey: "new-quote",
            dataType: .latestQuote, now: now, allowStale: true
        ) != .missing)
        #expect(try await cache.lookup(
            providerIdentifier: "synthetic.provider", logicalKey: "history",
            dataType: .eodHistorical, now: now, allowStale: true
        ) != .missing)
    }

    @Test("Capacity change failure rolls configuration and cache rows back")
    func capacityReductionRollback() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("cache.sqlite")
        let cache = try MarketCacheStore(
            databaseURL: url,
            policy: try .testing(maximumBytes: 2_000)
        )
        try await cache.store(makeEntry(key: "rollback-a", payloadSize: 600), authorization: .authorized)
        try await cache.store(makeEntry(key: "rollback-b", payloadSize: 600), authorization: .authorized)
        let before = try await cache.statistics()
        let inspection = try DatabaseQueueFactory.open(at: url)
        try await inspection.write { db in
            try db.execute(sql: """
                CREATE TRIGGER synthetic_capacity_delete_failure
                BEFORE DELETE ON market_cache_entries
                BEGIN
                    SELECT RAISE(ABORT, 'synthetic capacity delete failure');
                END
                """)
        }
        try inspection.close()

        await #expect(throws: (any Error).self) {
            _ = try await cache.updateMaximumBytes(1_000, now: now)
        }
        let after = try await cache.statistics()
        #expect(after.maximumBytes == before.maximumBytes)
        #expect(after.currentBytes == before.currentBytes)
        #expect(after.entryCount == before.entryCount)
        #expect(after.lastCleanupResult == before.lastCleanupResult)
    }

    @Test(
        "Every automatic, manual, provider, credential, termination, and reset path preserves Permanent Store",
        arguments: CacheIsolationOperation.allCases
    )
    func allCleanupPathsArePermanentlyIsolated(operation: CacheIsolationOperation) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let wealth = try WealthStore(databaseURL: root.appendingPathComponent("permanent/aureus.sqlite"))
        let cache = try MarketCacheStore(
            databaseURL: root.appendingPathComponent("cache/market-cache.sqlite"),
            policy: try .testing(maximumBytes: 1_000)
        )
        try await wealth.insertIsolationSentinel(
            id: "00000000-0000-4000-8000-000000006500",
            name: "Synthetic Stage 6 Permanent Sentinel"
        )
        try await wealth.seedSyntheticWealth()
        try await SyntheticLedgerSeeder.seed(in: wealth)
        try await SyntheticDashboardSeeder.seed(in: wealth)
        try await wealth.checkpoint()

        let before = try await permanentState(store: wealth)
        try await execute(operation, cache: cache)
        let after = try await permanentState(store: wealth)

        #expect(before.url == after.url)
        #expect(before.hash == after.hash)
        #expect(before.schemaVersion == after.schemaVersion)
        #expect(before.sentinels == after.sentinels)
        #expect(before.wealth == after.wealth)
        #expect(before.ledger == after.ledger)
        #expect(before.snapshots == after.snapshots)
        #expect(before.snapshotSentinel.complete == after.snapshotSentinel.complete)
        #expect(before.snapshotSentinel.items == after.snapshotSentinel.items)
        #expect(before.snapshotSentinel.legacy == after.snapshotSentinel.legacy)
        #expect(after.snapshots.flatMap(\.items).contains { $0.fxSource == "manual.synthetic.stage3" })
    }

    private func execute(
        _ operation: CacheIsolationOperation,
        cache: MarketCacheStore
    ) async throws {
        let expiredFetch = UTCInstant(
            millisecondsSince1970: now.millisecondsSince1970
                - MarketCacheDataType.latestQuote.timeToLiveMilliseconds - 1
        )
        switch operation {
        case .automaticTTL:
            try await cache.store(
                makeEntry(key: "expired-auto", type: .latestQuote, fetchedAt: expiredFetch),
                authorization: .authorized
            )
            _ = try await cache.performAutomaticCleanup(reason: .periodic, now: now)
        case .highWater:
            try await cache.store(makeEntry(key: "derived", type: .derivedIndicator, payloadSize: 400), authorization: .authorized)
            try await cache.store(makeEntry(key: "quote", type: .latestQuote, payloadSize: 400), authorization: .authorized)
            try await cache.store(makeEntry(key: "trigger", payloadSize: 200), authorization: .authorized)
        case .lru:
            let old = UTCInstant(millisecondsSince1970: now.millisecondsSince1970 - 10_000)
            try await cache.store(makeEntry(key: "old", fetchedAt: old, payloadSize: 400), authorization: .authorized)
            try await cache.store(makeEntry(key: "newer", payloadSize: 400), authorization: .authorized)
            try await cache.store(makeEntry(key: "trigger", payloadSize: 200), authorization: .authorized)
        case .removeExpired:
            try await cache.store(
                makeEntry(key: "expired-manual", type: .latestQuote, fetchedAt: expiredFetch),
                authorization: .authorized
            )
            _ = try await cache.removeExpired(now: now)
        case .providerPurge:
            try await cache.store(makeEntry(provider: "twelve-data", key: "provider"), authorization: .authorized)
            _ = try await cache.purge(providerIdentifier: "twelve-data", reason: .disconnect, now: now)
        case .credentialDelete, .disconnect, .confirmedTermination:
            let credentials = InMemoryCredentialStore()
            try await credentials.store(
                Data("synthetic-stage6-credential".utf8),
                for: TwelveDataClient.credentialDescriptor
            )
            let provider = SyntheticMarketDataProvider(
                scenario: .success,
                clock: FixedClock(instant: now)
            )
            try await cache.store(
                makeEntry(provider: provider.descriptor.identifier, key: "credential"),
                authorization: .authorized
            )
            let coordinator = ProviderCredentialCoordinator(
                credentialStore: credentials,
                provider: provider,
                cache: cache,
                clock: FixedClock(instant: now)
            )
            switch operation {
            case .credentialDelete: _ = try await coordinator.deleteCredential()
            case .disconnect: _ = try await coordinator.disconnect()
            case .confirmedTermination: _ = try await coordinator.confirmedTermination()
            default: break
            }
        case .capacityChange:
            try await cache.store(makeEntry(key: "capacity-a", payloadSize: 350), authorization: .authorized)
            try await cache.store(makeEntry(key: "capacity-b", payloadSize: 350), authorization: .authorized)
            _ = try await cache.updateMaximumBytes(500, now: now)
        case .reset:
            try await cache.store(makeEntry(key: "reset"), authorization: .authorized)
            try await cache.reset()
        }
    }

    private func makeEntry(
        provider: String = "synthetic.provider",
        key: String,
        type: MarketCacheDataType = .eodHistorical,
        fetchedAt: UTCInstant? = nil,
        payloadSize: Int = 64,
        freshness: MarketFreshness = .endOfDay
    ) throws -> MarketCacheEntry {
        try MarketCacheEntry(
            providerIdentifier: provider,
            logicalKey: key,
            dataType: type,
            payload: Data(repeating: 0x53, count: payloadSize),
            fetchedAt: fetchedAt ?? now,
            entitlementContext: "synthetic-test",
            freshness: freshness
        )
    }

    private func permanentState(store: WealthStore) async throws -> (
        url: URL,
        hash: [UInt8],
        schemaVersion: Int,
        sentinels: [String],
        wealth: [WealthContainer],
        ledger: [LedgerEntry],
        snapshots: [DashboardSnapshot],
        snapshotSentinel: (complete: Int, items: Int, legacy: Int)
    ) {
        (
            store.databaseURL,
            Array(SHA256.hash(data: try Data(contentsOf: store.databaseURL))),
            try await store.schemaVersion(),
            try await store.isolationSentinels(),
            try await store.fetchWealthContainers(),
            try await store.fetchLedgerEntries(),
            try await store.fetchDashboardSnapshots(),
            try await store.dashboardSnapshotSentinel()
        )
    }
}
