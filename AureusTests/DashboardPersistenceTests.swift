import CryptoKit
import Foundation
import GRDB
import Testing
@testable import Aureus

@Suite("Stage 5 Dashboard persistence")
struct DashboardPersistenceTests {
    @Test("Fresh v5 migration and every prior-version upgrade reach latest", arguments: [
        DatabaseMigrations.permanentV1,
        DatabaseMigrations.permanentV2,
        DatabaseMigrations.permanentV3,
        DatabaseMigrations.permanentV4
    ])
    func upgradeFromEveryPriorVersion(_ version: String) throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = try DatabaseQueueFactory.open(at: root.appendingPathComponent("upgrade/aureus.sqlite"))
        let migrator = DatabaseMigrations.permanentMigrator()
        try migrator.migrate(queue, upTo: version)
        try migrator.migrate(queue)
        let schemaVersion = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT version FROM schema_metadata WHERE store_kind = 'permanent'")
        }
        #expect(schemaVersion == 5)
        #expect(try queue.read { db in try db.tableExists("snapshot_items") })
        try migrator.migrate(queue)
        #expect(try queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM grdb_migrations") } == 5)
    }

    @Test("Legacy foundation Snapshot and valuation are preserved but remain incomplete")
    func legacyPreservation() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = try DatabaseQueueFactory.open(at: root.appendingPathComponent("legacy/aureus.sqlite"))
        let migrator = DatabaseMigrations.permanentMigrator()
        try migrator.migrate(queue, upTo: DatabaseMigrations.permanentV1)
        let legacyID = "00000000-0000-4000-8000-000000000309"
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO snapshots (id, civil_date, created_at_ms, total_cny_minor) VALUES (?, '2026-01-15', 1768435200000, 71250)",
                arguments: [legacyID]
            )
            try db.execute(sql: """
                INSERT INTO snapshot_valuations (
                    id, snapshot_id, source_amount_minor, source_currency_code,
                    fx_coefficient, fx_source_currency_code, fx_target_currency_code,
                    converted_cny_minor, provider_identifier, reference_date,
                    fetched_at_ms, is_stale
                ) VALUES (
                    '00000000-0000-4000-8000-000000000310', ?, 10000, 'USD',
                    71250000000, 'USD', 'CNY', 71250, 'synthetic.stage2.fx',
                    '2026-01-15', 1768435200000, 0
                )
                """, arguments: [legacyID])
        }
        let before = try queue.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM snapshots") ?? 0,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM snapshot_valuations") ?? 0
            )
        }
        try migrator.migrate(queue)
        let after = try queue.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM snapshots") ?? 0,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM snapshot_valuations") ?? 0,
                try Int.fetchOne(db, sql: "SELECT is_complete FROM snapshots WHERE id = ?", arguments: [legacyID]),
                try String.fetchOne(db, sql: "SELECT capture_status FROM snapshots WHERE id = ?", arguments: [legacyID]),
                try Int.fetchOne(db, sql: "SELECT total_cny_minor FROM snapshots WHERE id = ?", arguments: [legacyID])
            )
        }
        #expect(before.0 == after.0)
        #expect(before.1 == after.1)
        #expect(after.2 == 0)
        #expect(after.3 == "legacyIncomplete")
        #expect(after.4 == 71_250)
        #expect(try queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM snapshot_items") } == 0)
    }

    @Test("Complete capture round-trips totals, Items, and USD FX using INTEGER storage")
    func captureRoundTrip() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("permanent/aureus.sqlite"))
        try await store.seedSyntheticWealth()
        let date = try CivilDate(canonical: "2026-01-15")
        let captured = try #require(
            try await store.ensureDashboardSnapshot(for: date, createdAt: SyntheticWealthSeeder.demoInstant)
        )
        let reopened = try WealthStore(databaseURL: store.databaseURL)
        let fetched = try #require(try await reopened.fetchDashboardSnapshots().first)
        #expect(fetched == captured)
        #expect(fetched.items.count == 7)
        let usd = try #require(fetched.items.first { $0.originalValue.currency == .usd })
        #expect(usd.rate.sourceCurrency == .usd)
        #expect(usd.rate.targetCurrency == .cny)
        #expect(usd.isManualFX)
        #expect(usd.fxReferenceDate == date)
        #expect(try await reopened.dashboardSnapshotStorageClasses() == ["integer"])
        #expect(try await reopened.schemaVersion() == 5)
    }

    @Test("Empty Wealth Store creates no fabricated zero Snapshot")
    func emptyStoreNoSnapshot() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("permanent/aureus.sqlite"))
        let result = try await store.ensureDashboardSnapshot(
            for: CivilDate(canonical: "2026-01-15"),
            createdAt: SyntheticWealthSeeder.demoInstant
        )
        #expect(result == nil)
        #expect(try await store.completeDashboardSnapshotCount() == 0)
    }

    @Test("Same-day refresh atomically replaces Items while retaining one complete Header")
    func sameDayRefresh() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("permanent/aureus.sqlite"))
        let original = try SyntheticWealthSeeder.records()[0]
        try await store.createWealthContainer(original)
        let date = try CivilDate(canonical: "2026-01-15")
        let before = try #require(try await store.ensureDashboardSnapshot(for: date, createdAt: SyntheticWealthSeeder.demoInstant))
        let updated = try updatedCash(original, minorUnits: original.originalValue.minorUnits + 50_000, name: "Synthetic CNY Cash Edited")
        try await store.updateWealthContainer(updated)
        let after = try await store.refreshDashboardSnapshot(
            for: date,
            createdAt: UTCInstant(millisecondsSince1970: SyntheticWealthSeeder.demoInstant.millisecondsSince1970 + 1_000)
        )
        #expect(before.id == after.id)
        #expect(after.items.first?.containerName == "Synthetic CNY Cash Edited")
        #expect(after.summary.totalAssetsCNY.minorUnits == before.summary.totalAssetsCNY.minorUnits + 50_000)
        #expect(try await store.completeDashboardSnapshotCount(on: date) == 1)
        #expect(try await store.fetchWealthContainer(id: original.id) == updated)
    }

    @Test("Failed same-day refresh rolls back Header and every prior Item")
    func refreshRollback() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("permanent/aureus.sqlite")
        let store = try WealthStore(databaseURL: url)
        try await store.seedSyntheticWealth()
        let date = try CivilDate(canonical: "2026-01-15")
        let before = try #require(try await store.ensureDashboardSnapshot(for: date, createdAt: SyntheticWealthSeeder.demoInstant))
        let probe = try DatabaseQueueFactory.open(at: url)
        try await probe.write { db in
            try db.execute(sql: """
                CREATE TRIGGER synthetic_snapshot_refresh_failure
                BEFORE INSERT ON snapshot_items
                WHEN NEW.container_name = 'Synthetic CNY Cash Lab'
                BEGIN
                    SELECT RAISE(ABORT, 'synthetic snapshot failure');
                END
                """)
        }
        var failed = false
        do {
            _ = try await store.refreshDashboardSnapshot(
                for: date,
                createdAt: UTCInstant(millisecondsSince1970: before.createdAt.millisecondsSince1970 + 5_000)
            )
        } catch {
            failed = true
        }
        #expect(failed)
        let after = try #require(try await store.fetchDashboardSnapshots().first)
        #expect(after == before)
        #expect(try await store.completeDashboardSnapshotCount(on: date) == 1)
    }

    @Test("Historical Snapshot is immutable after current edit and survives Snapshot-only Container deletion")
    func historicalImmutability() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("permanent/aureus.sqlite"))
        let original = try SyntheticWealthSeeder.records()[5]
        try await store.createWealthContainer(original)
        let date = try CivilDate(canonical: "2025-12-31")
        let snapshot = try #require(try await store.ensureDashboardSnapshot(for: date, createdAt: SyntheticWealthSeeder.demoInstant))
        let updated = try updatedOtherAsset(original, minorUnits: original.originalValue.minorUnits + 100_000)
        try await store.updateWealthContainer(updated)
        #expect(try await store.fetchDashboardSnapshots().first == snapshot)
        _ = try await store.deleteWealthContainer(id: original.id)
        #expect(try await store.fetchWealthContainer(id: original.id) == nil)
        let afterDelete = try #require(try await store.fetchDashboardSnapshots().first)
        #expect(afterDelete == snapshot)
        #expect(afterDelete.items.first?.containerID == original.id)
    }

    @Test("Snapshot range query is ordered and excludes out-of-range complete history")
    func rangeQuery() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("permanent/aureus.sqlite"))
        try await store.seedSyntheticWealth()
        try await SyntheticDashboardSeeder.seed(in: store)
        let values = try await store.fetchDashboardSnapshots(
            from: CivilDate(canonical: "2025-12-01"),
            through: CivilDate(canonical: "2026-01-12")
        )
        #expect(values.map(\.civilDate.description) == ["2025-12-31", "2026-01-05", "2026-01-12"])
    }

    @Test("v5 migration failure rolls back the table rebuild and preserves v4 rows")
    func v5MigrationRollback() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = try DatabaseQueueFactory.open(at: root.appendingPathComponent("rollback/aureus.sqlite"))
        let migrator = DatabaseMigrations.permanentMigrator()
        try migrator.migrate(queue, upTo: DatabaseMigrations.permanentV4)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO snapshots (id, civil_date, created_at_ms, total_cny_minor) VALUES ('synthetic-v4-snapshot', '2026-01-01', 1, 123)")
            try db.execute(sql: "CREATE TABLE snapshot_items (synthetic_probe TEXT)")
        }
        var failed = false
        do { try migrator.migrate(queue) } catch { failed = true }
        #expect(failed)
        let evidence = try queue.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT version FROM schema_metadata WHERE store_kind = 'permanent'"),
                try Int.fetchOne(db, sql: "SELECT total_cny_minor FROM snapshots WHERE id = 'synthetic-v4-snapshot'"),
                try db.columns(in: "snapshots").map(\.name)
            )
        }
        #expect(evidence.0 == 4)
        #expect(evidence.1 == 123)
        #expect(!evidence.2.contains("capture_schema"))
    }

    @Test("Cache Reset cannot mutate Snapshot, Wealth, Ledger, URL, hash, or schema")
    func cacheIsolation() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let permanentURL = root.appendingPathComponent("permanent/aureus.sqlite")
        let cacheURL = root.appendingPathComponent("cache/market-cache.sqlite")
        let store = try WealthStore(databaseURL: permanentURL)
        let cache = try MarketCacheStore(databaseURL: cacheURL)
        try await store.seedSyntheticWealth()
        try await SyntheticLedgerSeeder.seed(in: store)
        _ = try await store.ensureDashboardSnapshot(
            for: CivilDate(canonical: "2026-01-15"),
            createdAt: SyntheticWealthSeeder.demoInstant
        )
        try await cache.seedSyntheticCache()
        try await store.checkpoint()
        let hashBefore = try fileHash(permanentURL)
        let snapshotBefore = try await store.dashboardSnapshotSentinel()
        let wealthBefore = try await store.stage3WealthRecordCount()
        let ledgerBefore = try await store.ledgerTransactionCount()
        let schemaBefore = try await store.schemaVersion()

        try await cache.reset()

        #expect(try await cache.cachedRowCount() == 0)
        #expect(try fileHash(permanentURL) == hashBefore)
        let snapshotAfter = try await store.dashboardSnapshotSentinel()
        #expect(snapshotAfter.complete == snapshotBefore.complete)
        #expect(snapshotAfter.items == snapshotBefore.items)
        #expect(snapshotAfter.legacy == snapshotBefore.legacy)
        #expect(try await store.stage3WealthRecordCount() == wealthBefore)
        #expect(try await store.ledgerTransactionCount() == ledgerBefore)
        #expect(try await store.schemaVersion() == schemaBefore)
        #expect(store.databaseURL == permanentURL)
    }

    private func updatedCash(_ original: WealthContainer, minorUnits: Int64, name: String) throws -> WealthContainer {
        let money = Money(minorUnits: minorUnits, currency: .cny)
        return try WealthContainer(
            container: AssetContainer(
                id: original.id,
                accountID: original.container.accountID,
                name: name,
                kind: .bankCash,
                institution: original.container.institution,
                primaryCurrency: .cny,
                notes: original.container.notes,
                createdDate: original.container.createdDate,
                updatedDate: try CivilDate(canonical: "2026-01-16")
            ),
            details: .bankCash(balance: money, interestRate: nil),
            valuation: try FXValuation(
                original: money,
                rate: .cnyIdentity,
                referenceDate: try CivilDate(canonical: "2026-01-16"),
                fetchedAt: UTCInstant(millisecondsSince1970: SyntheticWealthSeeder.demoInstant.millisecondsSince1970 + 1_000),
                providerIdentifier: "identity",
                isManualOverride: false,
                isStale: false
            )
        )
    }

    private func updatedOtherAsset(_ original: WealthContainer, minorUnits: Int64) throws -> WealthContainer {
        let money = Money(minorUnits: minorUnits, currency: .cny)
        return try WealthContainer(
            container: AssetContainer(
                id: original.id,
                accountID: nil,
                name: "Synthetic Workshop Asset Renamed",
                kind: .otherAsset,
                institution: nil,
                primaryCurrency: .cny,
                notes: "Synthetic edit after capture",
                createdDate: original.container.createdDate,
                updatedDate: try CivilDate(canonical: "2026-01-16")
            ),
            details: .otherAsset(categoryDescription: "Synthetic equipment edited", currentValue: money),
            valuation: try FXValuation(
                original: money,
                rate: .cnyIdentity,
                referenceDate: try CivilDate(canonical: "2026-01-16"),
                fetchedAt: UTCInstant(millisecondsSince1970: SyntheticWealthSeeder.demoInstant.millisecondsSince1970 + 1_000),
                providerIdentifier: "identity",
                isManualOverride: false,
                isStale: false
            )
        )
    }

    private func fileHash(_ url: URL) throws -> [UInt8] {
        Array(SHA256.hash(data: try Data(contentsOf: url)))
    }
}
