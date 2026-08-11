import Foundation
import GRDB
import Testing
@testable import Aureus

private enum SyntheticMigrationFailure: Error {
    case intentional
}

@Suite("Persistence foundations")
struct PersistenceTests {
    @Test("Fresh permanent and cache migrations are independent")
    func freshMigrations() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let permanentURL = root.appendingPathComponent("permanent/aureus.sqlite")
        let cacheURL = root.appendingPathComponent("cache/market-cache.sqlite")
        let wealth = try WealthStore(databaseURL: permanentURL)
        let cache = try MarketCacheStore(databaseURL: cacheURL)

        #expect(permanentURL != cacheURL)
        #expect(try await wealth.schemaVersion() == 1)
        #expect(try await cache.schemaVersion() == 1)
        #expect(try await wealth.foreignKeysEnabled())
        #expect(try await cache.foreignKeysEnabled())
    }

    @Test("Stores reopen and migrations are idempotent")
    func reopenAndIdempotence() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let permanentURL = root.appendingPathComponent("permanent/aureus.sqlite")
        let first = try WealthStore(databaseURL: permanentURL)
        try await first.seedSyntheticFoundation()
        try await first.migrate()
        let firstCounts = try await first.foundationTableCounts()

        let reopened = try WealthStore(databaseURL: permanentURL)
        try await reopened.migrate()
        #expect(try await reopened.schemaVersion() == 1)
        #expect(try await reopened.foundationTableCounts() == firstCounts)
    }

    @Test("Foreign keys reject invalid relationships")
    func foreignKeyEnforcement() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(
            databaseURL: root.appendingPathComponent("permanent/aureus.sqlite")
        )
        #expect(try await store.foreignKeyEnforcementRejectsInvalidAsset())
    }

    @Test("Failed migration rolls back its own writes")
    func failedMigrationRollback() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = try DatabaseQueueFactory.open(
            at: root.appendingPathComponent("rollback/test.sqlite")
        )
        var migrator = DatabaseMigrator()
        migrator.registerMigration("rollback_v1") { db in
            try db.execute(sql: "CREATE TABLE rollback_probe (value TEXT NOT NULL)")
            try db.execute(sql: "INSERT INTO rollback_probe (value) VALUES ('committed-v1')")
        }
        migrator.registerMigration("rollback_v2_failure") { db in
            try db.execute(sql: "INSERT INTO rollback_probe (value) VALUES ('must-rollback')")
            throw SyntheticMigrationFailure.intentional
        }

        var failureObserved = false
        do {
            try migrator.migrate(queue)
        } catch SyntheticMigrationFailure.intentional {
            failureObserved = true
        }
        let values = try queue.read { db in
            try String.fetchAll(db, sql: "SELECT value FROM rollback_probe ORDER BY rowid")
        }
        #expect(failureObserved)
        #expect(values == ["committed-v1"])
    }

    @Test("Foundation entity graph seeds only synthetic relationships")
    func coreRelationshipSmokeTest() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(
            databaseURL: root.appendingPathComponent("permanent/aureus.sqlite")
        )
        try await store.seedSyntheticFoundation()
        let counts = try await store.foundationTableCounts()
        #expect(counts.values.allSatisfy { $0 > 0 })
        #expect(counts["snapshot_valuations"] == 1)
        #expect(counts["market_instrument_references"] == 1)
    }

    @Test("Authoritative financial columns store SQLite INTEGER values")
    func integerFinancialStorage() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(
            databaseURL: root.appendingPathComponent("permanent/aureus.sqlite")
        )
        try await store.seedSyntheticFoundation()
        let types = try await store.financialStorageClasses()
        #expect(types.count == 4)
        #expect(types.values.allSatisfy { $0 == "integer" })
    }
}

@Suite("Launch configuration isolation")
struct LaunchConfigurationTests {
    @Test("Demo mode always uses isolated temporary stores")
    func demoAlwaysUsesTemporaryStores() {
        let demo = LaunchConfiguration.current(arguments: ["Aureus", "--aureus-demo"])
        #expect(demo.dataMode == .syntheticDemo)
        #expect(demo.usesTemporaryStores)
        #expect(demo.temporaryRoot != nil)

        let normal = LaunchConfiguration.current(arguments: ["Aureus"])
        #expect(normal.dataMode == .empty)
        #expect(!normal.usesTemporaryStores)
        #expect(normal.temporaryRoot == nil)
    }
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AureusTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
