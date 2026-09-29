import Foundation
import GRDB
import Testing
@testable import Aureus

@Suite("Synthetic environment isolation")
struct EnvironmentIsolationIntegrationTests {
    @Test("Published 1.0.0 schema-six synthetic wealth survives consistent backup, migration and Dev restore")
    func releasedSchemaSixCompatibility() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let devPaths = RuntimePaths.development(
            applicationSupportDirectory: root.appendingPathComponent("Support"),
            cachesDirectory: root.appendingPathComponent("Caches")
        )
        let legacyURL = root.appendingPathComponent("Legacy/aureus.sqlite")
        let legacy = try DatabaseQueueFactory.open(at: legacyURL)
        try DatabaseMigrations.permanentMigrator().migrate(legacy, upTo: DatabaseMigrations.permanentV6)
        try await legacy.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id, name, kind, currency_code)
                VALUES ('00000000-0000-4000-8000-000000000011', 'Synthetic Legacy Account', 'other', 'USD')
                """)
            try db.execute(sql: """
                INSERT INTO asset_containers
                    (id, account_id, name, kind, primary_currency_code, created_date, updated_date)
                VALUES
                    ('00000000-0000-4000-8000-000000000012',
                     '00000000-0000-4000-8000-000000000011',
                     'Synthetic Legacy Cash', 'bankCash', 'USD', '2025-01-15', '2025-01-15')
                """)
            try db.execute(sql: """
                INSERT INTO wealth_records
                    (container_id, record_kind, original_minor, original_currency_code,
                     converted_cny_minor, fx_coefficient, fx_source_currency_code,
                     fx_target_currency_code, fx_source, fx_reference_date,
                     fx_recorded_at_ms, fx_is_manual, fx_is_stale)
                VALUES
                    ('00000000-0000-4000-8000-000000000012', 'bankCash', 10000, 'USD',
                     72500, 72500000000, 'USD', 'CNY', 'manual:synthetic', '2025-01-15',
                     1736899200000, 1, 0)
                """)
        }
        let original = try environmentLegacyFacts(legacy)
        #expect(original == ["00000000-0000-4000-8000-000000000012|00000000-0000-4000-8000-000000000011|bankCash|USD|10000|72500|72500000000|USD|CNY|manual:synthetic|2025-01-15|1736899200000|1|0"])
        #expect(try PermanentDatabaseValidation.inspect(legacy, expectedSchemaVersion: 6,
            requireCurrentApplicationSchema: false).schemaVersion == 6)

        let backup = try PermanentBackupService.create(from: legacy,
            in: devPaths.internalBackupDirectoryURL, appVersion: "synthetic-1.0.0",
            createdAt: UTCInstant(millisecondsSince1970: 1_736_899_200_000),
            generationID: UUID(uuidString: "00000000-0000-4000-8000-000000000013")!)
        #expect(backup.manifest.backupFormatVersion == 1 && backup.manifest.schemaVersion == 6)
        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: backup.directoryURL.path))
            == Set(["aureus.sqlite", "manifest.json"]))
        #expect(try PermanentBackupService.validateGeneration(backup.directoryURL,
            in: devPaths.internalBackupDirectoryURL) == backup)
        var readonly = Configuration()
        readonly.readonly = true
        let backupQueue = try DatabaseQueue(
            path: backup.directoryURL.appendingPathComponent("aureus.sqlite").path,
            configuration: readonly)
        #expect(try environmentLegacyFacts(backupQueue) == original)
        try backupQueue.close()
        try legacy.close()

        let safetyRoot = root.appendingPathComponent("LegacySafety/Backups", isDirectory: true)
        let migrated = try WealthStore(databaseURL: legacyURL,
            migrationSafetyConfiguration: PermanentMigrationSafetyConfiguration(
                backupRoot: safetyRoot, appVersion: "synthetic-current",
                createdAt: { UTCInstant(millisecondsSince1970: 1_736_899_210_000) },
                generationID: { UUID(uuidString: "00000000-0000-4000-8000-000000000014")! }))
        #expect(try await migrated.schemaVersion() == 10)
        #expect(try await environmentLegacyFacts(migrated.queue) == original)
        let safety = try #require(PermanentBackupService.inventory(in: safetyRoot).validGenerations.first)
        #expect(safety.manifest.schemaVersion == 6)

        let dev = try WealthStore(databaseURL: devPaths.permanentDatabaseURL)
        try await dev.insertIsolationSentinel(id: "synthetic-before-restore", name: "Synthetic Before Restore")
        let restored = try await dev.restorePermanentBackup(backup.directoryURL,
            in: devPaths.internalBackupDirectoryURL, appVersion: "synthetic-current",
            createdAt: UTCInstant(millisecondsSince1970: 1_736_899_220_000))
        #expect(restored.candidateSchemaVersion == 6 && restored.finalSchemaVersion == 10)
        #expect(restored.migrationRan)
        #expect(try await environmentLegacyFacts(dev.queue) == original)
        #expect(try await dev.schemaVersion() == 10)
        #expect(try PermanentBackupService.validateGeneration(backup.directoryURL,
            in: devPaths.internalBackupDirectoryURL) == backup)
    }

    @Test("Three permanent roots and cache roots reopen without mixing; Dev backup restores only Dev")
    func storesAndLifecycle() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let caches = root.appendingPathComponent("Caches", isDirectory: true)
        let productionPaths = RuntimePaths.production(applicationSupportDirectory: support,
            cachesDirectory: caches)
        let devPaths = RuntimePaths.development(applicationSupportDirectory: support,
            cachesDirectory: caches)
        let testRoot = root.appendingPathComponent("Test/00000000-0000-4000-8000-000000000001")
        let testPaths = RuntimePaths.temporary(root: testRoot)
        try productionPaths.validateSelected(for: .production)
        try devPaths.validateSelected(for: .development)
        try testPaths.validateSelected(for: .temporary)

        let production = try WealthStore(databaseURL: productionPaths.permanentDatabaseURL)
        let development = try WealthStore(databaseURL: devPaths.permanentDatabaseURL)
        let temporary = try WealthStore(databaseURL: testPaths.permanentDatabaseURL)
        try await production.insertIsolationSentinel(id: "synthetic-production", name: "Synthetic Production")
        try await development.insertIsolationSentinel(id: "synthetic-development", name: "Synthetic Development")
        try await temporary.insertIsolationSentinel(id: "synthetic-temporary", name: "Synthetic Temporary")

        #expect(try await WealthStore(databaseURL: productionPaths.permanentDatabaseURL)
            .isolationSentinels() == ["Synthetic Production"])
        #expect(try await WealthStore(databaseURL: devPaths.permanentDatabaseURL)
            .isolationSentinels() == ["Synthetic Development"])
        #expect(try await WealthStore(databaseURL: testPaths.permanentDatabaseURL)
            .isolationSentinels() == ["Synthetic Temporary"])

        let generation = try await development.createPermanentBackup(
            in: devPaths.internalBackupDirectoryURL,
            appVersion: "synthetic-environment-test",
            createdAt: UTCInstant(millisecondsSince1970: 1_768_435_200_000)
        )
        #expect(generation.manifest.schemaVersion == 10)
        try await development.insertIsolationSentinel(id: "synthetic-later", name: "Synthetic Later")
        _ = try await development.restorePermanentBackup(
            generation.directoryURL,
            in: devPaths.internalBackupDirectoryURL,
            appVersion: "synthetic-environment-test",
            createdAt: UTCInstant(millisecondsSince1970: 1_768_435_201_000)
        )
        #expect(try await development.isolationSentinels() == ["Synthetic Development"])
        #expect(try await production.isolationSentinels() == ["Synthetic Production"])
        #expect(try await temporary.isolationSentinels() == ["Synthetic Temporary"])

        let productionCache = try MarketCacheStore(databaseURL: productionPaths.marketCacheDatabaseURL)
        let devCache = try MarketCacheStore(databaseURL: devPaths.marketCacheDatabaseURL)
        #expect(try await productionCache.schemaVersion() == 2)
        try await devCache.reset()
        #expect(try await productionCache.schemaVersion() == 2)
        #expect(try await development.schemaVersion() == 10)
    }

    @MainActor
    @Test("Identical preference keys in two synthetic suites remain independent")
    func preferences() throws {
        let prefix = "com.aureus.wealthterminal.tests.environment.\(UUID().uuidString)"
        let productionSuite = prefix + ".production"
        let developmentSuite = prefix + ".development"
        let productionDefaults = try #require(UserDefaults(suiteName: productionSuite))
        let developmentDefaults = try #require(UserDefaults(suiteName: developmentSuite))
        defer {
            productionDefaults.removePersistentDomain(forName: productionSuite)
            developmentDefaults.removePersistentDomain(forName: developmentSuite)
        }
        let production = try GeneralPreferencesStore(suiteName: productionSuite)
        let development = try GeneralPreferencesStore(suiteName: developmentSuite)
        production.setNewWealthCurrency(.cny)
        development.setNewWealthCurrency(.usd)
        #expect(try GeneralPreferencesStore(suiteName: productionSuite).load().newWealthCurrency == .cny)
        #expect(try GeneralPreferencesStore(suiteName: developmentSuite).load().newWealthCurrency == .usd)
        development.setGroupWealthAmounts(false)
        #expect(try GeneralPreferencesStore(suiteName: productionSuite).load().groupWealthAmounts)
        developmentDefaults.removeObject(forKey: GeneralPreferencesStore.storageKey)
        #expect(try GeneralPreferencesStore(suiteName: productionSuite).load().newWealthCurrency == .cny)
    }

    @Test("Identical credential descriptor uses two exact synthetic Keychain services")
    func credentials() async throws {
        let prefix = "com.aureus.wealthterminal.tests.environment.\(UUID().uuidString)"
        let descriptor = CredentialDescriptor(providerIdentifier: "synthetic-environment",
            accountIdentifier: "synthetic-account")
        let production = KeychainCredentialStore(service: prefix + ".production")
        let development = KeychainCredentialStore(service: prefix + ".development")
        do {
            try await production.store(Data("synthetic-production".utf8), for: descriptor)
            try await development.store(Data("synthetic-development".utf8), for: descriptor)
            #expect(try await production.credential(for: descriptor) == Data("synthetic-production".utf8))
            #expect(try await development.credential(for: descriptor) == Data("synthetic-development".utf8))
            try await development.deleteCredential(for: descriptor)
            #expect(try await production.credential(for: descriptor) == Data("synthetic-production".utf8))
            try await production.deleteCredential(for: descriptor)
        } catch {
            try? await development.deleteCredential(for: descriptor)
            try? await production.deleteCredential(for: descriptor)
            throw error
        }
    }
}

private func environmentLegacyFacts(_ queue: DatabaseQueue) throws -> [String] {
    try queue.read { db in
        try String.fetchAll(db, sql: """
            SELECT a.id || '|' || a.account_id || '|' || a.kind || '|' || a.primary_currency_code
                || '|' || w.original_minor || '|' || w.converted_cny_minor
                || '|' || w.fx_coefficient || '|' || w.fx_source_currency_code
                || '|' || w.fx_target_currency_code || '|' || w.fx_source
                || '|' || w.fx_reference_date || '|' || w.fx_recorded_at_ms
                || '|' || w.fx_is_manual || '|' || w.fx_is_stale
            FROM asset_containers a JOIN wealth_records w ON w.container_id = a.id
            ORDER BY a.id
            """)
    }
}
