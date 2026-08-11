import Foundation
import GRDB
import Testing
@testable import Aureus

@Suite("Stage 3 wealth persistence")
struct WealthPersistenceTests {
    @Test("All seven container kinds support transactional CRUD and reopen")
    func allKindsCRUD() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("permanent/aureus.sqlite")
        let store = try WealthStore(databaseURL: url)

        for original in try SyntheticWealthSeeder.records() {
            try await store.createWealthContainer(original)
            #expect(try await store.fetchWealthContainer(id: original.id) == original)
            let updated = try WealthContainer(
                container: AssetContainer(
                    id: original.id,
                    accountID: original.container.accountID,
                    name: original.container.name + " Edited",
                    kind: original.container.kind,
                    institution: original.container.institution,
                    primaryCurrency: original.container.primaryCurrency,
                    notes: "Synthetic edit",
                    createdDate: original.container.createdDate,
                    updatedDate: try CivilDate(canonical: "2026-08-11")
                ),
                details: original.details,
                valuation: original.valuation
            )
            try await store.updateWealthContainer(updated)
            let reopened = try WealthStore(databaseURL: url)
            #expect(try await reopened.fetchWealthContainer(id: original.id) == updated)
            #expect(try await reopened.deletionImpact(for: original.id).associatedValuationRecords == 1)
            _ = try await reopened.deleteWealthContainer(id: original.id)
            #expect(try await reopened.fetchWealthContainer(id: original.id) == nil)
        }
        #expect(try await store.stage3WealthRecordCount() == 0)
    }

    @Test("Delete cascades only selected valuation and preserves unrelated permanent rows")
    func atomicDeleteBoundary() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(
            databaseURL: root.appendingPathComponent("permanent/aureus.sqlite")
        )
        let records = try SyntheticWealthSeeder.records()
        for record in records { try await store.createWealthContainer(record) }
        try await store.insertIsolationSentinel(
            id: "00000000-0000-4000-8000-000000000777",
            name: "Synthetic Unrelated Permanent Row"
        )

        let selected = records[2]
        let impact = try await store.deleteWealthContainer(id: selected.id)
        #expect(impact.associatedValuationRecords == 1)
        #expect(try await store.fetchWealthContainer(id: selected.id) == nil)
        #expect(try await store.stage3WealthRecordCount() == records.count - 1)
        #expect(try await store.isolationSentinels() == ["Synthetic Unrelated Permanent Row"])
    }

    @Test("Append-only v1 to v2 migration preserves legacy rows")
    func v1ToV2PreservesData() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = try DatabaseQueueFactory.open(
            at: root.appendingPathComponent("migration/aureus.sqlite")
        )
        let migrator = DatabaseMigrations.permanentMigrator()
        try migrator.migrate(queue, upTo: DatabaseMigrations.permanentV1)
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id, name, kind, currency_code)
                VALUES ('legacy-account', 'Synthetic Legacy Account', 'other', 'USD')
                """)
            try db.execute(sql: """
                INSERT INTO asset_containers (id, account_id, name, kind)
                VALUES ('legacy-container', 'legacy-account', 'Synthetic Legacy Cash', 'cash')
                """)
        }

        try migrator.migrate(queue)
        let result = try queue.read { db in
            (
                try String.fetchOne(db, sql: "SELECT name FROM accounts WHERE id = 'legacy-account'"),
                try Row.fetchOne(db, sql: """
                    SELECT name, kind, primary_currency_code
                    FROM asset_containers WHERE id = 'legacy-container'
                    """),
                try Int.fetchOne(db, sql: "SELECT version FROM schema_metadata WHERE store_kind = 'permanent'")
            )
        }
        #expect(result.0 == "Synthetic Legacy Account")
        #expect(result.1?["name"] as String? == "Synthetic Legacy Cash")
        #expect(result.1?["kind"] as String? == AssetContainerKind.bankCash.rawValue)
        #expect(result.1?["primary_currency_code"] as String? == CurrencyCode.usd.rawValue)
        #expect(result.2 == 2)
    }

    @Test("Stage 3 migration failure rolls back every v2 schema write")
    func v2Rollback() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = try DatabaseQueueFactory.open(
            at: root.appendingPathComponent("rollback/aureus.sqlite")
        )
        let migrator = DatabaseMigrations.permanentMigrator()
        try migrator.migrate(queue, upTo: DatabaseMigrations.permanentV1)
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO asset_containers (id, account_id, name, kind)
                VALUES ('bad-container', NULL, 'Synthetic Invalid Legacy Kind', 'unknown-kind')
                """)
        }

        #expect(throws: WealthMigrationError.unsupportedLegacyContainerKind) {
            try migrator.migrate(queue)
        }
        let state = try queue.read { db in
            let columns = try String.fetchAll(
                db,
                sql: "SELECT name FROM pragma_table_info('asset_containers') ORDER BY cid"
            )
            let wealthTableCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'wealth_records'"
            ) ?? 0
            let legacyKind = try String.fetchOne(
                db,
                sql: "SELECT kind FROM asset_containers WHERE id = 'bad-container'"
            )
            let version = try Int.fetchOne(
                db,
                sql: "SELECT version FROM schema_metadata WHERE store_kind = 'permanent'"
            )
            return (columns, wealthTableCount, legacyKind, version)
        }
        #expect(state.0 == ["id", "account_id", "name", "kind"])
        #expect(state.1 == 0)
        #expect(state.2 == "unknown-kind")
        #expect(state.3 == 1)
    }

    @Test("Stage 3 schema enforces FK, CHECK, and INTEGER financial storage")
    func constraintsAndStorage() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("permanent/aureus.sqlite")
        let store = try WealthStore(databaseURL: url)
        let record = try SyntheticWealthSeeder.records()[0]
        try await store.createWealthContainer(record)
        try await store.checkpoint()

        let queue = try DatabaseQueueFactory.open(at: url)
        let types = try queue.read { db in
            try Row.fetchOne(db, sql: """
                SELECT typeof(original_minor) AS original_type,
                       typeof(converted_cny_minor) AS converted_type,
                       typeof(fx_coefficient) AS fx_type
                FROM wealth_records LIMIT 1
                """)
        }
        #expect(types?["original_type"] as String? == "integer")
        #expect(types?["converted_type"] as String? == "integer")
        #expect(types?["fx_type"] as String? == "integer")

        var foreignKeyRejected = false
        do {
            try await queue.write { db in
                try db.execute(sql: """
                    INSERT INTO wealth_records (
                        container_id, record_kind, original_minor, original_currency_code,
                        converted_cny_minor, fx_coefficient, fx_source_currency_code,
                        fx_target_currency_code, fx_source, fx_reference_date,
                        fx_recorded_at_ms, fx_is_manual, fx_is_stale
                    ) VALUES (
                        'missing-container', 'bankCash', 1, 'CNY', 1, 10000000000,
                        'CNY', 'CNY', 'identity', '2026-08-11', 0, 0, 0
                    )
                    """)
            }
        } catch { foreignKeyRejected = true }
        #expect(foreignKeyRejected)

        var checkRejected = false
        do {
            try await queue.write { db in
                try db.execute(
                    sql: "UPDATE wealth_records SET original_minor = -1 WHERE container_id = ?",
                    arguments: [record.id.uuidString]
                )
            }
        } catch { checkRejected = true }
        #expect(checkRejected)
    }

    @Test("Synthetic seeding is idempotent and confined to its injected store")
    func syntheticSeedIsolation() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let demo = try WealthStore(databaseURL: root.appendingPathComponent("demo/aureus.sqlite"))
        let ordinary = try WealthStore(databaseURL: root.appendingPathComponent("ordinary/aureus.sqlite"))
        try await demo.seedSyntheticWealth()
        try await demo.seedSyntheticWealth()
        #expect(try await demo.stage3WealthRecordCount() == 7)
        #expect(try await ordinary.stage3WealthRecordCount() == 0)
        #expect(try await demo.wealthSummary().netWorthCNY.minorUnits == 15_067_206)
        #expect(try await ordinary.wealthSummary() == .zero)
    }
}
