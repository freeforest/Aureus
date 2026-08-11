import Foundation
import GRDB

actor WealthStore {
    nonisolated let databaseURL: URL

    private let queue: DatabaseQueue
    private let migrator: DatabaseMigrator

    init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        self.queue = try DatabaseQueueFactory.open(at: databaseURL)
        self.migrator = DatabaseMigrations.permanentMigrator()
        try migrator.migrate(queue)
    }

    func migrate() throws {
        try migrator.migrate(queue)
    }

    func schemaVersion() throws -> Int {
        try queue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT version FROM schema_metadata WHERE store_kind = 'permanent'"
            ) ?? 0
        }
    }

    func foreignKeysEnabled() throws -> Bool {
        try queue.read { db in
            try Int.fetchOne(db, sql: "PRAGMA foreign_keys") == 1
        }
    }

    func seedSyntheticFoundation() throws {
        try queue.write { db in
            try SyntheticFoundationSeeder.seedPermanent(db)
        }
    }

    func foundationTableCounts() throws -> [String: Int] {
        let tables = [
            "accounts", "asset_containers", "assets", "wealth_transactions", "holdings",
            "trades", "snapshots", "snapshot_valuations", "market_instrument_references",
            "portfolios", "goals", "insurance_policies", "categories", "tags"
        ]
        return try queue.read { db in
            var result: [String: Int] = [:]
            for table in tables {
                result[table] = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
            }
            return result
        }
    }

    func insertIsolationSentinel(id: String, name: String) throws {
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO accounts (id, name, kind, currency_code) VALUES (?, ?, 'other', 'CNY')",
                arguments: [id, name]
            )
        }
    }

    func isolationSentinels() throws -> [String] {
        try queue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM accounts WHERE kind = 'other' ORDER BY id"
            )
        }
    }

    func foreignKeyEnforcementRejectsInvalidAsset() throws -> Bool {
        queue.writeWithoutTransaction { db in
            do {
                try db.execute(sql: """
                    INSERT INTO assets (id, container_id, name, currency_code, instrument_reference_id)
                    VALUES ('00000000-0000-4000-8000-000000009999', 'missing-container', 'Synthetic Invalid Asset', 'CNY', NULL)
                    """)
                return false
            } catch {
                return true
            }
        }
    }

    func financialStorageClasses() throws -> [String: String] {
        try queue.read { db in
            [
                "transaction.amount": try String.fetchOne(
                    db,
                    sql: "SELECT typeof(amount_minor) FROM wealth_transactions LIMIT 1"
                ) ?? "missing",
                "holding.quantity": try String.fetchOne(
                    db,
                    sql: "SELECT typeof(quantity_coefficient) FROM holdings LIMIT 1"
                ) ?? "missing",
                "trade.price": try String.fetchOne(
                    db,
                    sql: "SELECT typeof(price_coefficient) FROM trades LIMIT 1"
                ) ?? "missing",
                "snapshot.fx": try String.fetchOne(
                    db,
                    sql: "SELECT typeof(fx_coefficient) FROM snapshot_valuations LIMIT 1"
                ) ?? "missing"
            ]
        }
    }

    func checkpoint() throws {
        try queue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }
}
