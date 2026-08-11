import Foundation
import GRDB

actor MarketCacheStore {
    nonisolated let databaseURL: URL
    nonisolated let policy: CachePolicyConfiguration

    private var queue: DatabaseQueue
    private let migrator: DatabaseMigrator

    init(databaseURL: URL, policy: CachePolicyConfiguration = .default) throws {
        self.databaseURL = databaseURL
        self.policy = policy
        self.queue = try DatabaseQueueFactory.open(at: databaseURL)
        self.migrator = DatabaseMigrations.cacheMigrator()
        try migrator.migrate(queue)
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

    func cachedRowCount() throws -> Int {
        try queue.read { db in
            let instruments = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cached_instruments") ?? 0
            let prices = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cached_prices") ?? 0
            return instruments + prices
        }
    }

    func reset() throws {
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
}
