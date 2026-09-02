import Foundation
import GRDB

actor WealthStore {
    nonisolated let databaseURL: URL

    var queue: DatabaseQueue
    let migrator: DatabaseMigrator
    var maintenanceState: PermanentRestoreMaintenanceState = .ready

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

    func createWealthContainer(_ record: WealthContainer) throws {
        try queue.write { db in
            try AssetContainerPersistenceRow(container: record.container).insert(db)
            try WealthRecordPersistenceRow(record: record).insert(db)
        }
    }

    func fetchWealthContainers() throws -> [WealthContainer] {
        try queue.read { db in
            let containerRows = try AssetContainerPersistenceRow.fetchAll(
                db,
                sql: """
                    SELECT asset_containers.*
                    FROM asset_containers
                    INNER JOIN wealth_records
                        ON wealth_records.container_id = asset_containers.id
                    ORDER BY updated_date DESC, name COLLATE NOCASE, asset_containers.id
                    """
            )
            let recordRows = try WealthRecordPersistenceRow.fetchAll(db)
            let recordsByContainer = Dictionary(
                uniqueKeysWithValues: recordRows.map { ($0.containerID, $0) }
            )
            return try containerRows.map { containerRow in
                guard let recordRow = recordsByContainer[containerRow.id] else {
                    throw WealthPersistenceError.corruptRecord
                }
                return try recordRow.domain(container: containerRow.domain())
            }
        }
    }

    func fetchWealthContainer(id: UUID) throws -> WealthContainer? {
        try fetchWealthContainers().first { $0.id == id }
    }

    func updateWealthContainer(_ record: WealthContainer) throws {
        try queue.write { db in
            let exists = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM wealth_records WHERE container_id = ?",
                arguments: [record.id.uuidString]
            ) ?? 0
            guard exists == 1 else { throw WealthPersistenceError.containerNotFound }
            try AssetContainerPersistenceRow(container: record.container).update(db)
            try WealthRecordPersistenceRow(record: record).update(db)
        }
    }

    func deletionImpact(for id: UUID) throws -> ContainerDeletionImpact {
        try queue.read { db in
            try Self.deletionImpact(in: db, containerID: id.uuidString)
        }
    }

    @discardableResult
    func deleteWealthContainer(id: UUID) throws -> ContainerDeletionImpact {
        try queue.write { db in
            let impact = try Self.deletionImpact(in: db, containerID: id.uuidString)
            guard !impact.hasProtectedPermanentDependents else {
                throw WealthPersistenceError.protectedPermanentDependents
            }
            guard impact.wealthRecordCount == 1 else {
                throw WealthPersistenceError.containerNotFound
            }
            try db.execute(
                sql: "DELETE FROM asset_containers WHERE id = ?",
                arguments: [id.uuidString]
            )
            guard db.changesCount == 1 else { throw WealthPersistenceError.containerNotFound }
            return impact
        }
    }

    private static func deletionImpact(
        in db: Database,
        containerID: String
    ) throws -> ContainerDeletionImpact {
        let arguments: StatementArguments = [containerID]
        return ContainerDeletionImpact(
            wealthRecordCount: try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM wealth_records WHERE container_id = ?",
                arguments: arguments
            ) ?? 0,
            linkedAssetCount: try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM assets WHERE container_id = ?",
                arguments: arguments
            ) ?? 0,
            linkedInsurancePolicyCount: try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM insurance_policies
                    INNER JOIN assets ON assets.id = insurance_policies.asset_id
                    WHERE assets.container_id = ?
                    """,
                arguments: arguments
            ) ?? 0,
            linkedLedgerPostingCount: try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM ledger_postings WHERE container_id = ?",
                arguments: arguments
            ) ?? 0,
            linkedPortfolioSecurityCount: try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM portfolio_security_links WHERE wealth_container_id = ?",
                arguments: arguments
            ) ?? 0
        )
    }

    func wealthSummary() throws -> WealthSummary {
        try WealthValuation.aggregate(fetchWealthContainers())
    }

    func stage3WealthRecordCount() throws -> Int {
        try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM wealth_records") ?? 0
        }
    }

    func seedSyntheticWealth() throws {
        let records = try SyntheticWealthSeeder.records()
        try queue.write { db in
            for record in records {
                let exists = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM wealth_records WHERE container_id = ?",
                    arguments: [record.id.uuidString]
                ) ?? 0
                if exists == 0 {
                    try AssetContainerPersistenceRow(container: record.container).insert(db)
                    try WealthRecordPersistenceRow(record: record).insert(db)
                }
            }
        }
    }
}
