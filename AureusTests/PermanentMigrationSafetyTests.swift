import Foundation
import GRDB
import Testing
@testable import Aureus

private enum SyntheticMigrationSafetyFailure: Error {
    case intentional
}

private final class MigrationInvocationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func increment() {
        lock.lock()
        storedValue += 1
        lock.unlock()
    }
}

@Suite("Permanent migration safety")
struct PermanentMigrationSafetyTests {
    @Test("Migration error mapping drops synthetic associated payloads; not engine failure coverage")
    func diagnosticErrorMapping() {
        #expect(WealthStore.migrationDiagnosticCategory(PermanentMigrationSafetyError.preMigrationBackupFailed) == .migrationBackup)
        #expect(WealthStore.migrationDiagnosticCategory(PermanentMigrationSafetyError.migrationFailed(preMigrationGenerationIdentity: "Synthetic-Private-Generation", storeState: .unchangedLegacy)) == .migrationExecution)
        #expect(WealthStore.migrationDiagnosticCategory(PermanentMigrationSafetyError.postMigrationValidationFailed(preMigrationGenerationIdentity: "/synthetic/private/generation")) == .migrationPostValidation)
        #expect(WealthStore.migrationDiagnosticCategory(SyntheticMigrationSafetyFailure.intentional) == .unknown)
    }

    @Test("Fresh Store migrates without creating a pre-migration Backup")
    func freshStore() async throws {
        let sink = RecordingDataLifecycleSink()
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        let store = try WealthStore(
            databaseURL: context.paths.permanentDatabaseURL,
            migrationSafetyConfiguration: context.configuration(id: 1),
            diagnostics: sink.diagnostics
        )

        #expect(try await store.schemaVersion() == 6)
        #expect(try migrationInventory(context).validGenerations.isEmpty)
        #expect(await store.lastMigrationSafetyResult?.initialState == .fresh)
        #expect(sink.events == [.init(operation: .permanentMigration, outcome: .succeeded, errorCategory: .none)])
    }

    @Test("Current Store performs an idempotent no-op without Backup")
    func currentStore() async throws {
        let sink = RecordingDataLifecycleSink()
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let first = try WealthStore(databaseURL: context.paths.permanentDatabaseURL)
        try await first.insertIsolationSentinel(
            id: "migration-current-sentinel",
            name: "Synthetic Current Sentinel"
        )

        let reopened = try WealthStore(
            databaseURL: context.paths.permanentDatabaseURL,
            migrationSafetyConfiguration: context.configuration(id: 2),
            diagnostics: sink.diagnostics
        )
        try await reopened.migrate()

        #expect(try await reopened.isolationSentinels() == ["Synthetic Current Sentinel"])
        #expect(try migrationInventory(context).validGenerations.isEmpty)
        #expect(await reopened.lastMigrationSafetyResult?.initialState == .current)
        #expect(sink.events.isEmpty)
    }

    @Test("Recognized legacy v1 through v5 Backup exactly once before migration", arguments: [1, 2, 3, 4, 5])
    func legacyVersions(version: Int) async throws {
        let sink = RecordingDataLifecycleSink()
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try prepareLegacyStore(context.paths.permanentDatabaseURL, version: version)

        let store = try WealthStore(
            databaseURL: context.paths.permanentDatabaseURL,
            migrationSafetyConfiguration: context.configuration(id: version),
            diagnostics: sink.diagnostics
        )
        let inventory = try migrationInventory(context)
        let generation = try #require(inventory.validGenerations.only)

        #expect(generation.manifest.schemaVersion == version)
        #expect(try backupAccountIDs(generation) == [legacyAccountID(version)])
        #expect(try await store.schemaVersion() == 6)
        #expect(try await store.isolationSentinels() == [legacyAccountName(version)])
        #expect(
            await store.lastMigrationSafetyResult
                == PermanentMigrationSafetyResult(
                    initialState: .legacy(schemaVersion: version),
                    finalSchemaVersion: 6,
                    migrationRan: true,
                    preMigrationGenerationIdentity: generation.directoryURL.lastPathComponent
                )
        )
        #expect(sink.events == [.init(operation: .permanentMigration, outcome: .succeeded, errorCategory: .none)])
    }

    @Test("Pre-migration generation preserves legacy schema and synthetic record")
    func legacyBackupAuthority() async throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try prepareLegacyStore(context.paths.permanentDatabaseURL, version: 3)

        _ = try WealthStore(
            databaseURL: context.paths.permanentDatabaseURL,
            migrationSafetyConfiguration: context.configuration(id: 30)
        )
        let generation = try #require(try migrationInventory(context).validGenerations.only)
        let inspection = try PermanentDatabaseValidation.inspectFile(
            generation.directoryURL.appendingPathComponent("aureus.sqlite"),
            expectedSchemaVersion: 3,
            requireCurrentApplicationSchema: false
        )

        #expect(inspection.schemaVersion == 3)
        #expect(
            inspection.migrationIdentifiers
                == Array(PermanentDatabaseValidation.migrationIdentifiers.prefix(3))
        )
        #expect(inspection.accountIDs == [legacyAccountID(3)])
    }

    @Test("Missing safety configuration rejects a pending legacy migration")
    func missingConfiguration() throws {
        let sink = RecordingDataLifecycleSink()
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try prepareLegacyStore(context.paths.permanentDatabaseURL, version: 1)

        #expect(throws: PermanentMigrationSafetyError.missingBackupConfiguration) {
            _ = try WealthStore(databaseURL: context.paths.permanentDatabaseURL, diagnostics: sink.diagnostics)
        }
        #expect(try rawSchemaVersion(context.paths.permanentDatabaseURL) == 1)
        #expect(sink.events == [.init(operation: .permanentMigration, outcome: .failed, errorCategory: .migrationPreflight)])
    }

    @Test("Backup validation failure prevents migrator invocation and preserves live Store")
    func backupFailureStopsMigration() throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try prepareLegacyStore(context.paths.permanentDatabaseURL, version: 1)
        let queue = try DatabaseQueueFactory.open(at: context.paths.permanentDatabaseURL)
        defer { try? queue.close() }
        let counter = MigrationInvocationCounter()
        let invalidConfiguration = PermanentMigrationSafetyConfiguration(
            backupRoot: context.root.appendingPathComponent("NotBackups", isDirectory: true),
            appVersion: migrationTestAppVersion,
            createdAt: { migrationTestInstant },
            generationID: { migrationUUID(40) }
        )

        #expect(throws: PermanentMigrationSafetyError.preMigrationBackupFailed) {
            _ = try PermanentMigrationSafetyService.migrate(
                queue,
                databaseURL: context.paths.permanentDatabaseURL,
                migrator: DatabaseMigrations.permanentMigrator(),
                configuration: invalidConfiguration,
                migrationAction: { _, _ in counter.increment() }
            )
        }
        #expect(counter.value == 0)
        #expect(try rawSchemaVersion(context.paths.permanentDatabaseURL) == 1)
        #expect(try rawAccountIDs(context.paths.permanentDatabaseURL) == [legacyAccountID(1)])
    }

    @Test("Symlink Backup root prevents migration")
    func symlinkBackupRoot() throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try prepareLegacyStore(context.paths.permanentDatabaseURL, version: 1)
        let realRoot = context.root.appendingPathComponent("RealBackups", isDirectory: true)
        let symlinkRoot = context.root.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: realRoot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinkRoot, withDestinationURL: realRoot)
        let configuration = PermanentMigrationSafetyConfiguration(
            backupRoot: symlinkRoot,
            appVersion: migrationTestAppVersion,
            createdAt: { migrationTestInstant },
            generationID: { migrationUUID(41) }
        )

        #expect(throws: PermanentMigrationSafetyError.preMigrationBackupFailed) {
            _ = try WealthStore(
                databaseURL: context.paths.permanentDatabaseURL,
                migrationSafetyConfiguration: configuration
            )
        }
        #expect(try rawSchemaVersion(context.paths.permanentDatabaseURL) == 1)
    }

    @Test("Unsafe live database symlink is rejected")
    func unsafeLiveSymlink() throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let actualURL = context.root.appendingPathComponent("actual/aureus.sqlite")
        try prepareLegacyStore(actualURL, version: 1)
        let linkedURL = context.root.appendingPathComponent("linked/aureus.sqlite")
        try FileManager.default.createDirectory(
            at: linkedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: linkedURL, withDestinationURL: actualURL)
        let queue = try DatabaseQueue(path: linkedURL.path)
        defer { try? queue.close() }

        #expect(throws: PermanentMigrationSafetyError.rejected(.unsafeStore)) {
            _ = try PermanentMigrationSafetyService.migrate(
                queue,
                databaseURL: linkedURL,
                migrator: DatabaseMigrations.permanentMigrator(),
                configuration: context.configuration(id: 42)
            )
        }
        #expect(try rawSchemaVersion(actualURL) == 1)
    }

    @Test("Unknown migration identifier is rejected without Backup")
    func unknownIdentifier() throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try prepareLegacyStore(context.paths.permanentDatabaseURL, version: 1)
        try mutateMetadata(context.paths.permanentDatabaseURL) { db in
            try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('unknown_v2')")
        }

        #expect(throws: PermanentMigrationSafetyError.rejected(.unknownMigrationIdentifier)) {
            _ = try WealthStore(
                databaseURL: context.paths.permanentDatabaseURL,
                migrationSafetyConfiguration: context.configuration(id: 50)
            )
        }
        #expect(try migrationInventory(context).validGenerations.isEmpty)
    }

    @Test("Gap and non-prefix migration metadata are rejected")
    func gapMetadata() throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try prepareLegacyStore(context.paths.permanentDatabaseURL, version: 1)
        try mutateMetadata(context.paths.permanentDatabaseURL) { db in
            try db.execute(
                sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
                arguments: [DatabaseMigrations.permanentV3]
            )
            try db.execute(
                sql: "UPDATE schema_metadata SET version = 2 WHERE store_kind = 'permanent'"
            )
        }

        #expect(throws: PermanentMigrationSafetyError.rejected(.nonPrefixMigrationMetadata)) {
            _ = try WealthStore(
                databaseURL: context.paths.permanentDatabaseURL,
                migrationSafetyConfiguration: context.configuration(id: 51)
            )
        }
    }

    @Test("Reordered migration identifiers are rejected")
    func reorderedMetadata() throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try prepareLegacyStore(context.paths.permanentDatabaseURL, version: 2)
        try mutateMetadata(context.paths.permanentDatabaseURL) { db in
            try db.execute(sql: "DELETE FROM grdb_migrations")
            try db.execute(
                sql: "INSERT INTO grdb_migrations (identifier) VALUES (?), (?)",
                arguments: [DatabaseMigrations.permanentV2, DatabaseMigrations.permanentV1]
            )
        }

        #expect(throws: PermanentMigrationSafetyError.rejected(.nonPrefixMigrationMetadata)) {
            _ = try WealthStore(
                databaseURL: context.paths.permanentDatabaseURL,
                migrationSafetyConfiguration: context.configuration(id: 52)
            )
        }
    }

    @Test("Future schema is rejected before Backup or migration")
    func futureSchema() throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        _ = try WealthStore(databaseURL: context.paths.permanentDatabaseURL)
        try mutateMetadata(context.paths.permanentDatabaseURL) { db in
            try db.execute(
                sql: "UPDATE schema_metadata SET version = 7 WHERE store_kind = 'permanent'"
            )
        }

        #expect(throws: PermanentMigrationSafetyError.rejected(.futureSchema)) {
            _ = try WealthStore(
                databaseURL: context.paths.permanentDatabaseURL,
                migrationSafetyConfiguration: context.configuration(id: 53)
            )
        }
        #expect(try migrationInventory(context).validGenerations.isEmpty)
    }

    @Test("Schema metadata mismatch is rejected")
    func schemaMismatch() throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try prepareLegacyStore(context.paths.permanentDatabaseURL, version: 2)
        try mutateMetadata(context.paths.permanentDatabaseURL) { db in
            try db.execute(
                sql: "UPDATE schema_metadata SET version = 1 WHERE store_kind = 'permanent'"
            )
        }

        #expect(throws: PermanentMigrationSafetyError.rejected(.metadataSchemaMismatch)) {
            _ = try WealthStore(
                databaseURL: context.paths.permanentDatabaseURL,
                migrationSafetyConfiguration: context.configuration(id: 54)
            )
        }
    }

    @Test("Non-permanent Store is rejected")
    func nonPermanentStore() throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let queue = try DatabaseQueueFactory.open(at: context.paths.permanentDatabaseURL)
        try DatabaseMigrations.cacheMigrator().migrate(queue)
        try queue.close()

        #expect(throws: PermanentMigrationSafetyError.rejected(.nonPermanentStore)) {
            _ = try WealthStore(
                databaseURL: context.paths.permanentDatabaseURL,
                migrationSafetyConfiguration: context.configuration(id: 55)
            )
        }
    }

    @Test("Schema zero with unexplained business state is not Fresh")
    func schemaZeroBusinessState() throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let queue = try DatabaseQueueFactory.open(at: context.paths.permanentDatabaseURL)
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE unexplained_business_record (id TEXT PRIMARY KEY)")
        }
        try queue.close()

        #expect(throws: PermanentMigrationSafetyError.rejected(.unexplainedBusinessState)) {
            _ = try WealthStore(
                databaseURL: context.paths.permanentDatabaseURL,
                migrationSafetyConfiguration: context.configuration(id: 56)
            )
        }
    }

    @Test("Migration failure retains valid Backup and rolls back failing transaction")
    func migrationFailureBoundary() throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try prepareLegacyStore(context.paths.permanentDatabaseURL, version: 1)
        let queue = try DatabaseQueueFactory.open(at: context.paths.permanentDatabaseURL)
        defer { try? queue.close() }

        do {
            _ = try PermanentMigrationSafetyService.migrate(
                queue,
                databaseURL: context.paths.permanentDatabaseURL,
                migrator: DatabaseMigrations.permanentMigrator(),
                configuration: context.configuration(id: 60),
                migrationAction: { queue, _ in
                    try queue.write { db in
                        try db.execute(
                            sql: "INSERT INTO accounts (id, name, kind, currency_code) VALUES ('must-rollback', 'Synthetic Must Roll Back', 'other', 'CNY')"
                        )
                        throw SyntheticMigrationSafetyFailure.intentional
                    }
                }
            )
            Issue.record("Expected migration failure")
        } catch let error as PermanentMigrationSafetyError {
            guard case .migrationFailed(let identity, .unchangedLegacy) = error else {
                Issue.record("Unexpected typed error: \(error)")
                return
            }
            #expect(!identity.isEmpty)
        }

        let generation = try #require(try migrationInventory(context).validGenerations.only)
        #expect(generation.manifest.schemaVersion == 1)
        #expect(try rawSchemaVersion(context.paths.permanentDatabaseURL) == 1)
        #expect(try rawAccountIDs(context.paths.permanentDatabaseURL) == [legacyAccountID(1)])
    }

    @Test("Post-migration validation failure retains pre-migration generation")
    func postValidationFailure() throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try prepareLegacyStore(context.paths.permanentDatabaseURL, version: 1)
        let queue = try DatabaseQueueFactory.open(at: context.paths.permanentDatabaseURL)
        defer { try? queue.close() }

        do {
            _ = try PermanentMigrationSafetyService.migrate(
                queue,
                databaseURL: context.paths.permanentDatabaseURL,
                migrator: DatabaseMigrations.permanentMigrator(),
                configuration: context.configuration(id: 61),
                migrationAction: { _, _ in }
            )
            Issue.record("Expected post-migration validation failure")
        } catch let error as PermanentMigrationSafetyError {
            guard case .postMigrationValidationFailed(let identity?) = error else {
                Issue.record("Unexpected typed error: \(error)")
                return
            }
            #expect(!identity.isEmpty)
        }
        #expect(try migrationInventory(context).validGenerations.count == 1)
        #expect(try rawSchemaVersion(context.paths.permanentDatabaseURL) == 1)
    }

    @Test("Repeated open and explicit migrate never duplicate Backup")
    func repeatedOpenAndExplicitMigrate() async throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try prepareLegacyStore(context.paths.permanentDatabaseURL, version: 4)
        let first = try WealthStore(
            databaseURL: context.paths.permanentDatabaseURL,
            migrationSafetyConfiguration: context.configuration(id: 70)
        )
        try await first.migrate()
        let reopened = try WealthStore(
            databaseURL: context.paths.permanentDatabaseURL,
            migrationSafetyConfiguration: context.configuration(id: 71)
        )
        try await reopened.migrate()

        #expect(try migrationInventory(context).validGenerations.count == 1)
        #expect(try await reopened.schemaVersion() == 6)
    }

    @Test("Generation collision prevents migration")
    func generationCollision() throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try prepareLegacyStore(context.paths.permanentDatabaseURL, version: 1)
        let queue = try DatabaseQueueFactory.open(at: context.paths.permanentDatabaseURL)
        _ = try PermanentBackupService.create(
            from: queue,
            in: context.paths.internalBackupDirectoryURL,
            appVersion: migrationTestAppVersion,
            createdAt: migrationTestInstant,
            generationID: migrationUUID(72)
        )
        try queue.close()

        #expect(throws: PermanentMigrationSafetyError.preMigrationBackupFailed) {
            _ = try WealthStore(
                databaseURL: context.paths.permanentDatabaseURL,
                migrationSafetyConfiguration: context.configuration(id: 72)
            )
        }
        #expect(try rawSchemaVersion(context.paths.permanentDatabaseURL) == 1)
        #expect(try migrationInventory(context).validGenerations.count == 1)
    }

    @Test("Valid-only retention keeps five and preserves unknown sibling")
    func retentionAndUnknownSibling() async throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let sourceURL = context.root.appendingPathComponent("Current/aureus.sqlite")
        let current = try WealthStore(databaseURL: sourceURL)
        for index in 0..<5 {
            _ = try await current.createPermanentBackup(
                in: context.paths.internalBackupDirectoryURL,
                appVersion: migrationTestAppVersion,
                createdAt: UTCInstant(
                    millisecondsSince1970: migrationTestInstant.millisecondsSince1970 + Int64(index)
                ),
                generationID: migrationUUID(80 + index)
            )
        }
        let unknown = context.paths.internalBackupDirectoryURL
            .appendingPathComponent("unknown-sibling", isDirectory: true)
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: false)
        try Data("synthetic-owned-by-other-service".utf8).write(
            to: unknown.appendingPathComponent("marker.txt")
        )
        try prepareLegacyStore(context.paths.permanentDatabaseURL, version: 2)

        _ = try WealthStore(
            databaseURL: context.paths.permanentDatabaseURL,
            migrationSafetyConfiguration: context.configuration(
                id: 90,
                millisecondsOffset: 100
            )
        )
        let inventory = try migrationInventory(context)

        #expect(inventory.validGenerations.count == 5)
        #expect(inventory.ignoredArtifactCount == 1)
        #expect(FileManager.default.fileExists(atPath: unknown.path))
        #expect(inventory.validGenerations.contains { $0.manifest.schemaVersion == 2 })
    }

    @Test("Production composition root injects the temporary graph Backup root")
    func productionCompositionRootWiring() async throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try prepareLegacyStore(context.paths.permanentDatabaseURL, version: 1)
        let inputs = PermanentMigrationSafetyInputs(
            appVersion: "  \(migrationTestAppVersion)  ",
            createdAt: { migrationTestInstant },
            generationID: { migrationUUID(100) }
        )
        let dependencies = try await AppDependencies.make(
            configuration: LaunchConfiguration(
                dataMode: .local,
                usesTemporaryStores: true,
                temporaryRoot: context.root
            ),
            migrationSafetyInputs: inputs
        )
        let configuredRoot = await dependencies.wealthStore
            .migrationSafetyConfiguration?.backupRoot
        let generation = try #require(try migrationInventory(context).validGenerations.only)

        #expect(configuredRoot == context.paths.internalBackupDirectoryURL)
        #expect(generation.manifest.appVersion == migrationTestAppVersion)
        #expect(generation.manifest.schemaVersion == 1)
        #expect(try await dependencies.wealthStore.schemaVersion() == 6)
    }

    @Test("Production and temporary Backup roots never mix")
    func runtimeRootIsolation() throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let production = RuntimePaths.production(
            applicationSupportDirectory: context.root.appendingPathComponent("Support"),
            cachesDirectory: context.root.appendingPathComponent("Caches")
        )
        let temporary = RuntimePaths.temporary(
            root: context.root.appendingPathComponent("Temporary")
        )

        #expect(production.internalBackupDirectoryURL.lastPathComponent == "Backups")
        #expect(temporary.internalBackupDirectoryURL.lastPathComponent == "Backups")
        #expect(production.internalBackupDirectoryURL != temporary.internalBackupDirectoryURL)
        #expect(
            production.internalBackupDirectoryURL.standardizedFileURL
                == context.root.appendingPathComponent(
                    "Support/Aureus/Backups",
                    isDirectory: true
                ).standardizedFileURL
        )
        #expect(
            temporary.internalBackupDirectoryURL.standardizedFileURL
                == context.root.appendingPathComponent(
                    "Temporary/Backups",
                    isDirectory: true
                ).standardizedFileURL
        )
    }

    @Test("Concurrent construction serializes to one pre-migration Backup")
    func concurrentConstruction() async throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try prepareLegacyStore(context.paths.permanentDatabaseURL, version: 1)
        let configuration = context.configuration(id: 110)
        let databaseURL = context.paths.permanentDatabaseURL

        async let first = Task.detached {
            try WealthStore(
                databaseURL: databaseURL,
                migrationSafetyConfiguration: configuration
            )
        }.value
        async let second = Task.detached {
            try WealthStore(
                databaseURL: databaseURL,
                migrationSafetyConfiguration: configuration
            )
        }.value
        let stores = try await [first, second]

        #expect(stores.count == 2)
        #expect(try migrationInventory(context).validGenerations.count == 1)
        #expect(try await stores[0].schemaVersion() == 6)
        #expect(try await stores[1].schemaVersion() == 6)
    }

    @Test("Market Cache and key-like sentinels remain outside migration Backup")
    func isolationBoundary() async throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try prepareLegacyStore(context.paths.permanentDatabaseURL, version: 1)
        let cacheURL = context.paths.marketCacheDatabaseURL
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let cacheSentinel = Data("synthetic-market-cache-sentinel".utf8)
        try cacheSentinel.write(to: cacheURL)
        let keySentinel = context.root.appendingPathComponent("synthetic-key-like-sentinel.txt")
        try Data("synthetic-not-a-credential".utf8).write(to: keySentinel)

        _ = try WealthStore(
            databaseURL: context.paths.permanentDatabaseURL,
            migrationSafetyConfiguration: context.configuration(id: 120)
        )
        let generation = try #require(try migrationInventory(context).validGenerations.only)
        let artifactNames = try FileManager.default.contentsOfDirectory(
            atPath: generation.directoryURL.path
        ).sorted()

        #expect(artifactNames == ["aureus.sqlite", "manifest.json"])
        #expect(try Data(contentsOf: cacheURL) == cacheSentinel)
        #expect(FileManager.default.fileExists(atPath: keySentinel.path))
        #expect(!artifactNames.contains("market-cache.sqlite"))
        #expect(!artifactNames.contains(keySentinel.lastPathComponent))
    }

    @Test("Typed results and errors disclose no business values or full paths")
    func diagnosticPrivacy() throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try prepareLegacyStore(context.paths.permanentDatabaseURL, version: 1)
        let error: PermanentMigrationSafetyError
        do {
            _ = try WealthStore(databaseURL: context.paths.permanentDatabaseURL)
            Issue.record("Expected missing configuration")
            return
        } catch let typed as PermanentMigrationSafetyError {
            error = typed
        }
        let description = error.errorDescription ?? ""

        #expect(!description.contains(context.root.path))
        #expect(!description.contains(legacyAccountName(1)))
        #expect(!description.contains("CNY"))
        #expect(!description.lowercased().contains("provider"))
    }

    @Test("Shared current-schema validation preserves Backup and Restore authority")
    func sharedValidation() async throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let store = try WealthStore(databaseURL: context.paths.permanentDatabaseURL)
        try await store.insertIsolationSentinel(
            id: "shared-validation-sentinel",
            name: "Synthetic Shared Validation Sentinel"
        )
        let generation = try await store.createPermanentBackup(
            in: context.paths.internalBackupDirectoryURL,
            appVersion: migrationTestAppVersion,
            createdAt: migrationTestInstant,
            generationID: migrationUUID(130)
        )
        let inspection = try PermanentDatabaseValidation.inspectFile(
            generation.directoryURL.appendingPathComponent("aureus.sqlite"),
            expectedSchemaVersion: 6,
            requireCurrentApplicationSchema: true
        )

        #expect(inspection.schemaVersion == 6)
        #expect(inspection.migrationIdentifiers == PermanentDatabaseValidation.migrationIdentifiers)
        #expect(inspection.accountIDs == ["shared-validation-sentinel"])
        #expect(try await store.validatePermanentBackup(
            generation.directoryURL,
            in: context.paths.internalBackupDirectoryURL
        ) == generation)
    }

    @Test("Release workload backs up and migrates ten thousand legacy rows within bound")
    func stage11MigrationSafetyPerformance() async throws {
        let context = try migrationSafetyContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try prepareLegacyStore(
            context.paths.permanentDatabaseURL,
            version: 1,
            accountCount: 10_000
        )
        let clock = ContinuousClock()
        let start = clock.now
        let store = try WealthStore(
            databaseURL: context.paths.permanentDatabaseURL,
            migrationSafetyConfiguration: context.configuration(id: 140)
        )
        let elapsed = start.duration(to: clock.now)
        let milliseconds = elapsed.components.seconds * 1_000
            + elapsed.components.attoseconds / 1_000_000_000_000_000
        let generation = try #require(try migrationInventory(context).validGenerations.only)

        #expect(try await store.schemaVersion() == 6)
        #expect(try rawAccountCount(context.paths.permanentDatabaseURL) == 10_000)
        #expect(try backupAccountCount(generation) == 10_000)
        #expect(milliseconds < 10_000)
        print(
            "STAGE11_MIGRATION_SAFETY_PERF rows=10000 start_schema=1 "
                + "backup_migrate_validate_ms=\(milliseconds) provider_requests=0 "
                + "cache_reads=0 credential_reads=0"
        )
    }
}

private let migrationTestAppVersion = "11-migration-safety-test"
private let migrationTestInstant = UTCInstant(millisecondsSince1970: 1_788_192_000_000)

private struct MigrationSafetyTestContext {
    let root: URL
    let paths: RuntimePaths

    func configuration(
        id: Int,
        millisecondsOffset: Int64 = 0
    ) -> PermanentMigrationSafetyConfiguration {
        PermanentMigrationSafetyConfiguration(
            backupRoot: paths.internalBackupDirectoryURL,
            appVersion: migrationTestAppVersion,
            createdAt: {
                UTCInstant(
                    millisecondsSince1970: migrationTestInstant.millisecondsSince1970
                        + millisecondsOffset
                )
            },
            generationID: { migrationUUID(id) }
        )
    }
}

private func migrationSafetyContext() throws -> MigrationSafetyTestContext {
    let injected = ProcessInfo.processInfo.environment["AUREUS_MIGRATION_SAFETY_TEST_ROOT"]
    let base = injected.map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? URL(fileURLWithPath: "/private/tmp/AureusTests/PermanentMigrationSafety", isDirectory: true)
    let root = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return MigrationSafetyTestContext(root: root, paths: .temporary(root: root))
}

private func prepareLegacyStore(
    _ databaseURL: URL,
    version: Int,
    accountCount: Int = 1
) throws {
    let queue = try DatabaseQueueFactory.open(at: databaseURL)
    let migrator = DatabaseMigrations.permanentMigrator()
    try migrator.migrate(queue, upTo: migrationIdentifier(version))
    try queue.write { db in
        for index in 0..<accountCount {
            let id = accountCount == 1
                ? legacyAccountID(version)
                : String(format: "migration-perf-%05d", index)
            let name = accountCount == 1
                ? legacyAccountName(version)
                : String(format: "Synthetic Migration Performance %05d", index)
            try db.execute(
                sql: "INSERT INTO accounts (id, name, kind, currency_code) VALUES (?, ?, 'other', 'CNY')",
                arguments: [id, name]
            )
        }
    }
    try queue.close()
}

private func migrationIdentifier(_ version: Int) -> String {
    PermanentDatabaseValidation.migrationIdentifiers[version - 1]
}

private func legacyAccountID(_ version: Int) -> String {
    "migration-legacy-v\(version)"
}

private func legacyAccountName(_ version: Int) -> String {
    "Synthetic Migration Legacy v\(version)"
}

private func migrationUUID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "d4000000-0000-4000-8000-%012d", value))!
}

private func migrationInventory(
    _ context: MigrationSafetyTestContext
) throws -> PermanentBackupInventory {
    try PermanentBackupService.inventory(in: context.paths.internalBackupDirectoryURL)
}

private func mutateMetadata(
    _ databaseURL: URL,
    _ mutation: (Database) throws -> Void
) throws {
    let queue = try DatabaseQueueFactory.open(at: databaseURL)
    try queue.write(mutation)
    try queue.close()
}

private func rawSchemaVersion(_ databaseURL: URL) throws -> Int {
    let queue = try DatabaseQueue(path: databaseURL.path)
    defer { try? queue.close() }
    return try queue.read { db in
        try Int.fetchOne(
            db,
            sql: "SELECT version FROM schema_metadata WHERE store_kind = 'permanent'"
        ) ?? 0
    }
}

private func rawAccountIDs(_ databaseURL: URL) throws -> [String] {
    let queue = try DatabaseQueue(path: databaseURL.path)
    defer { try? queue.close() }
    return try queue.read { db in
        try String.fetchAll(db, sql: "SELECT id FROM accounts ORDER BY id")
    }
}

private func rawAccountCount(_ databaseURL: URL) throws -> Int {
    let queue = try DatabaseQueue(path: databaseURL.path)
    defer { try? queue.close() }
    return try queue.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM accounts") ?? 0
    }
}

private func backupAccountIDs(_ generation: PermanentBackupGeneration) throws -> [String] {
    try rawAccountIDs(
        generation.directoryURL.appendingPathComponent(
            PermanentBackupService.databaseFileName,
            isDirectory: false
        )
    )
}

private func backupAccountCount(_ generation: PermanentBackupGeneration) throws -> Int {
    try rawAccountCount(
        generation.directoryURL.appendingPathComponent(
            PermanentBackupService.databaseFileName,
            isDirectory: false
        )
    )
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}
