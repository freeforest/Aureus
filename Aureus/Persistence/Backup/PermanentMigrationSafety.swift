import Foundation
import GRDB

enum PermanentMigrationStoreState: Equatable, Sendable {
    case fresh
    case current
    case legacy(schemaVersion: Int)
}

enum PermanentMigrationRejection: Equatable, Sendable {
    case unsafeStore
    case nonPermanentStore
    case unexplainedBusinessState
    case unknownMigrationIdentifier
    case nonPrefixMigrationMetadata
    case futureSchema
    case metadataSchemaMismatch
    case corruptMetadata
}

enum PermanentMigrationFailureStoreState: Equatable, Sendable {
    case unchangedLegacy
    case partiallyMigratedNotReady
    case unavailable
}

enum PermanentMigrationSafetyError: Error, Equatable, Sendable {
    case rejected(PermanentMigrationRejection)
    case missingBackupConfiguration
    case preMigrationBackupFailed
    case migrationFailed(
        preMigrationGenerationIdentity: String,
        storeState: PermanentMigrationFailureStoreState
    )
    case postMigrationValidationFailed(preMigrationGenerationIdentity: String?)
}

extension PermanentMigrationSafetyError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .rejected:
            "The Permanent Store migration state is not recognized."
        case .missingBackupConfiguration:
            "A validated pre-migration Backup is required before this Permanent Store can migrate."
        case .preMigrationBackupFailed:
            "The pre-migration Backup did not complete and migration was not started."
        case .migrationFailed:
            "Permanent Store migration failed after a validated safety generation was retained."
        case .postMigrationValidationFailed:
            "Permanent Store migration completed but current-schema validation did not pass."
        }
    }
}

struct PermanentMigrationSafetyConfiguration: Sendable {
    let backupRoot: URL
    let appVersion: String
    let createdAt: @Sendable () -> UTCInstant
    let generationID: @Sendable () -> UUID

    init(
        backupRoot: URL,
        appVersion: String,
        createdAt: @escaping @Sendable () -> UTCInstant,
        generationID: @escaping @Sendable () -> UUID
    ) {
        self.backupRoot = backupRoot
        self.appVersion = appVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.generationID = generationID
    }
}

struct PermanentMigrationSafetyResult: Equatable, Sendable {
    let initialState: PermanentMigrationStoreState
    let finalSchemaVersion: Int
    let migrationRan: Bool
    let preMigrationGenerationIdentity: String?
}

enum PermanentDatabaseValidationFailure: Error, Equatable, Sendable {
    case databaseOpenOrIntegrity
    case foreignKeys
    case schema
    case migrationMetadata
    case requiredTables
    case financialAuthority
    case applicationInvariant
}

struct PermanentDatabaseInspection: Equatable, Sendable {
    let schemaVersion: Int
    let migrationIdentifiers: [String]
    let tableNames: Set<String>
    let accountIDs: [String]
}

enum PermanentDatabaseValidation {
    static let currentSchemaVersion = 9

    static let migrationIdentifiers = [
        DatabaseMigrations.permanentV1,
        DatabaseMigrations.permanentV2,
        DatabaseMigrations.permanentV3,
        DatabaseMigrations.permanentV4,
        DatabaseMigrations.permanentV5,
        DatabaseMigrations.permanentV6,
        DatabaseMigrations.permanentV7,
        DatabaseMigrations.permanentV8,
        DatabaseMigrations.permanentV9
    ]

    static let requiredPermanentTables: Set<String> = [
        "schema_metadata",
        "grdb_migrations",
        "accounts",
        "asset_containers",
        "assets",
        "wealth_transactions",
        "holdings",
        "trades",
        "snapshots",
        "snapshot_valuations",
        "market_instrument_references",
        "portfolios",
        "goals",
        "insurance_policies",
        "categories",
        "tags",
        "transaction_tags",
        "wealth_records",
        "ledger_transactions",
        "ledger_postings",
        "ledger_transaction_tags",
        "classification_rules",
        "classification_rule_tags",
        "ledger_import_batches",
        "snapshot_items",
        "portfolio_definitions",
        "portfolio_security_links",
        "portfolio_activities",
        "portfolio_nav_snapshots",
        "portfolio_nav_snapshot_items",
        "evidence_documents", "evidence_ledger_links", "evidence_container_links",
        "evidence_portfolio_activity_links", "evidence_import_operations",
        "ledger_correction_history", "wealth_correction_history"
    ]

    static func inspectFile(
        _ databaseURL: URL,
        expectedSchemaVersion: Int,
        requireCurrentApplicationSchema: Bool
    ) throws -> PermanentDatabaseInspection {
        let reader: DatabaseQueue
        do {
            var configuration = Configuration()
            configuration.readonly = true
            configuration.prepareDatabase { db in
                try db.execute(sql: "PRAGMA query_only = ON")
                try db.execute(sql: "PRAGMA foreign_keys = ON")
            }
            reader = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        } catch {
            throw PermanentDatabaseValidationFailure.databaseOpenOrIntegrity
        }
        defer { try? reader.close() }
        return try inspect(
            reader,
            expectedSchemaVersion: expectedSchemaVersion,
            requireCurrentApplicationSchema: requireCurrentApplicationSchema
        )
    }

    static func inspect(
        _ queue: DatabaseQueue,
        expectedSchemaVersion: Int,
        requireCurrentApplicationSchema: Bool
    ) throws -> PermanentDatabaseInspection {
        do {
            return try queue.read { db in
                guard try String.fetchAll(db, sql: "PRAGMA quick_check") == ["ok"] else {
                    throw PermanentDatabaseValidationFailure.databaseOpenOrIntegrity
                }
                guard try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty else {
                    throw PermanentDatabaseValidationFailure.foreignKeys
                }

                let metadataRows = try Row.fetchAll(
                    db,
                    sql: "SELECT store_kind, version FROM schema_metadata ORDER BY store_kind"
                )
                guard metadataRows.count == 1,
                      metadataRows[0]["store_kind"] as String == "permanent",
                      let schemaVersion = metadataRows[0]["version"] as Int?,
                      schemaVersion == expectedSchemaVersion else {
                    throw PermanentDatabaseValidationFailure.schema
                }

                let tableNames = Set(try String.fetchAll(
                    db,
                    sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
                ))
                let migrations = try String.fetchAll(
                    db,
                    sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid"
                )
                guard tableNames.contains("accounts") else {
                    throw PermanentDatabaseValidationFailure.applicationInvariant
                }
                let accountIDs = try String.fetchAll(
                    db,
                    sql: "SELECT id FROM accounts ORDER BY id"
                )

                guard (1...currentSchemaVersion).contains(schemaVersion),
                      migrations == Array(migrationIdentifiers.prefix(schemaVersion)) else {
                    throw PermanentDatabaseValidationFailure.schema
                }
                if schemaVersion >= 7 { try EvidenceSQL.validateSchema(db) }
                if schemaVersion >= 8 { try LedgerCorrectionSQL.validateSchema(db) }
                if schemaVersion >= 9 { try WealthCorrectionSQL.validateSchema(db) }
                if requireCurrentApplicationSchema {
                    guard schemaVersion == currentSchemaVersion else {
                        throw PermanentDatabaseValidationFailure.schema
                    }
                    guard migrations == migrationIdentifiers else {
                        throw PermanentDatabaseValidationFailure.migrationMetadata
                    }
                    guard requiredPermanentTables.isSubset(of: tableNames) else {
                        throw PermanentDatabaseValidationFailure.requiredTables
                    }
                    for table in requiredPermanentTables {
                        let hasRealAuthority = try db.columns(in: table).contains {
                            $0.type.caseInsensitiveCompare("REAL") == .orderedSame
                        }
                        guard !hasRealAuthority else {
                            throw PermanentDatabaseValidationFailure.financialAuthority
                        }
                    }
                }

                return PermanentDatabaseInspection(
                    schemaVersion: schemaVersion,
                    migrationIdentifiers: migrations,
                    tableNames: tableNames,
                    accountIDs: accountIDs
                )
            }
        } catch let error as PermanentDatabaseValidationFailure {
            throw error
        } catch {
            throw PermanentDatabaseValidationFailure.databaseOpenOrIntegrity
        }
    }
}

enum PermanentMigrationSafetyService {
    typealias MigrationAction = (DatabaseQueue, DatabaseMigrator) throws -> Void

    static func migrate(
        _ queue: DatabaseQueue,
        databaseURL: URL,
        migrator: DatabaseMigrator,
        configuration: PermanentMigrationSafetyConfiguration?,
        migrationAction: MigrationAction? = nil
    ) throws -> PermanentMigrationSafetyResult {
        try PermanentMigrationCoordinator.shared.withLock {
            try validateLiveDatabaseURL(databaseURL)
            let initialState = try classify(queue, migrator: migrator)
            let executeMigration = migrationAction ?? { queue, migrator in
                try migrator.migrate(queue)
            }

            switch initialState {
            case .fresh:
                do {
                    try executeMigration(queue, migrator)
                } catch {
                    throw PermanentMigrationSafetyError.migrationFailed(
                        preMigrationGenerationIdentity: "none",
                        storeState: .unavailable
                    )
                }
                try validatePostMigration(queue, generationIdentity: nil)
                return PermanentMigrationSafetyResult(
                    initialState: .fresh,
                    finalSchemaVersion: PermanentDatabaseValidation.currentSchemaVersion,
                    migrationRan: true,
                    preMigrationGenerationIdentity: nil
                )

            case .current:
                do {
                    try executeMigration(queue, migrator)
                } catch {
                    throw PermanentMigrationSafetyError.migrationFailed(
                        preMigrationGenerationIdentity: "none",
                        storeState: .unavailable
                    )
                }
                try validatePostMigration(queue, generationIdentity: nil)
                return PermanentMigrationSafetyResult(
                    initialState: .current,
                    finalSchemaVersion: PermanentDatabaseValidation.currentSchemaVersion,
                    migrationRan: false,
                    preMigrationGenerationIdentity: nil
                )

            case .legacy(let schemaVersion):
                guard let configuration else {
                    throw PermanentMigrationSafetyError.missingBackupConfiguration
                }
                let generation: PermanentBackupGeneration
                do {
                    generation = try PermanentBackupService.create(
                        from: queue,
                        in: configuration.backupRoot,
                        appVersion: configuration.appVersion,
                        createdAt: configuration.createdAt(),
                        generationID: configuration.generationID()
                    )
                    let verified = try PermanentBackupService.validateGeneration(
                        generation.directoryURL,
                        in: configuration.backupRoot
                    )
                    let inspection = try PermanentDatabaseValidation.inspectFile(
                        verified.directoryURL.appendingPathComponent(
                            PermanentBackupService.databaseFileName,
                            isDirectory: false
                        ),
                        expectedSchemaVersion: schemaVersion,
                        requireCurrentApplicationSchema: false
                    )
                    guard verified.manifest.schemaVersion == schemaVersion,
                          inspection.migrationIdentifiers
                            == Array(PermanentDatabaseValidation.migrationIdentifiers.prefix(schemaVersion)) else {
                        throw PermanentMigrationSafetyError.preMigrationBackupFailed
                    }
                } catch let error as PermanentMigrationSafetyError {
                    throw error
                } catch {
                    throw PermanentMigrationSafetyError.preMigrationBackupFailed
                }

                let generationIdentity = generation.directoryURL.lastPathComponent
                do {
                    try executeMigration(queue, migrator)
                } catch {
                    throw PermanentMigrationSafetyError.migrationFailed(
                        preMigrationGenerationIdentity: generationIdentity,
                        storeState: failureStoreState(
                            queue,
                            originalSchemaVersion: schemaVersion,
                            migrator: migrator
                        )
                    )
                }
                try validatePostMigration(
                    queue,
                    generationIdentity: generationIdentity
                )
                return PermanentMigrationSafetyResult(
                    initialState: .legacy(schemaVersion: schemaVersion),
                    finalSchemaVersion: PermanentDatabaseValidation.currentSchemaVersion,
                    migrationRan: true,
                    preMigrationGenerationIdentity: generationIdentity
                )
            }
        }
    }

    static func classify(
        _ queue: DatabaseQueue,
        migrator: DatabaseMigrator
    ) throws -> PermanentMigrationStoreState {
        do {
            return try queue.read { db in
                let userObjects = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT name, type
                        FROM sqlite_master
                        WHERE name NOT LIKE 'sqlite_%'
                        ORDER BY type, name
                        """
                )
                let tableNames = Set(userObjects.compactMap { row -> String? in
                    let type: String = row["type"]
                    return type == "table" ? row["name"] : nil
                })
                let canonicalApplied = try migrator.appliedIdentifiers(db)
                let orderedApplied: [String]
                if tableNames.contains("grdb_migrations") {
                    orderedApplied = try String.fetchAll(
                        db,
                        sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid"
                    )
                } else {
                    orderedApplied = []
                }

                guard canonicalApplied == Set(orderedApplied),
                      canonicalApplied.count == orderedApplied.count else {
                    throw PermanentMigrationSafetyError.rejected(.corruptMetadata)
                }

                if orderedApplied.isEmpty {
                    let permittedFreshObjects = Set(["grdb_migrations"])
                    let namedObjects = Set(userObjects.map { $0["name"] as String })
                    guard namedObjects.isSubset(of: permittedFreshObjects) else {
                        throw PermanentMigrationSafetyError.rejected(.unexplainedBusinessState)
                    }
                    return .fresh
                }

                guard tableNames.contains("schema_metadata") else {
                    throw PermanentMigrationSafetyError.rejected(.corruptMetadata)
                }
                let metadataRows = try Row.fetchAll(
                    db,
                    sql: "SELECT store_kind, version FROM schema_metadata ORDER BY store_kind"
                )
                guard metadataRows.count == 1 else {
                    throw PermanentMigrationSafetyError.rejected(.corruptMetadata)
                }
                let storeKind: String = metadataRows[0]["store_kind"]
                guard storeKind == "permanent" else {
                    throw PermanentMigrationSafetyError.rejected(.nonPermanentStore)
                }
                let known = PermanentDatabaseValidation.migrationIdentifiers
                guard canonicalApplied.isSubset(of: Set(known)) else {
                    throw PermanentMigrationSafetyError.rejected(.unknownMigrationIdentifier)
                }
                guard orderedApplied.count <= known.count,
                      orderedApplied == Array(known.prefix(orderedApplied.count)) else {
                    throw PermanentMigrationSafetyError.rejected(.nonPrefixMigrationMetadata)
                }
                guard let schemaVersion = metadataRows[0]["version"] as Int? else {
                    throw PermanentMigrationSafetyError.rejected(.corruptMetadata)
                }
                guard schemaVersion <= PermanentDatabaseValidation.currentSchemaVersion else {
                    throw PermanentMigrationSafetyError.rejected(.futureSchema)
                }
                guard schemaVersion == orderedApplied.count else {
                    throw PermanentMigrationSafetyError.rejected(.metadataSchemaMismatch)
                }
                if schemaVersion == PermanentDatabaseValidation.currentSchemaVersion {
                    return .current
                }
                guard schemaVersion > 0 else {
                    throw PermanentMigrationSafetyError.rejected(.metadataSchemaMismatch)
                }
                return .legacy(schemaVersion: schemaVersion)
            }
        } catch let error as PermanentMigrationSafetyError {
            throw error
        } catch {
            throw PermanentMigrationSafetyError.rejected(.corruptMetadata)
        }
    }

    private static func validateLiveDatabaseURL(_ databaseURL: URL) throws {
        guard databaseURL.isFileURL,
              databaseURL.path.hasPrefix("/") else {
            throw PermanentMigrationSafetyError.rejected(.unsafeStore)
        }
        do {
            let parent = databaseURL.deletingLastPathComponent()
            let parentValues = try parent.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey
            ])
            let databaseValues = try databaseURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey
            ])
            guard parentValues.isDirectory == true,
                  parentValues.isSymbolicLink != true,
                  databaseValues.isRegularFile == true,
                  databaseValues.isSymbolicLink != true else {
                throw PermanentMigrationSafetyError.rejected(.unsafeStore)
            }
        } catch let error as PermanentMigrationSafetyError {
            throw error
        } catch {
            throw PermanentMigrationSafetyError.rejected(.unsafeStore)
        }
    }

    private static func validatePostMigration(
        _ queue: DatabaseQueue,
        generationIdentity: String?
    ) throws {
        do {
            _ = try PermanentDatabaseValidation.inspect(
                queue,
                expectedSchemaVersion: PermanentDatabaseValidation.currentSchemaVersion,
                requireCurrentApplicationSchema: true
            )
        } catch {
            throw PermanentMigrationSafetyError.postMigrationValidationFailed(
                preMigrationGenerationIdentity: generationIdentity
            )
        }
    }

    private static func failureStoreState(
        _ queue: DatabaseQueue,
        originalSchemaVersion: Int,
        migrator: DatabaseMigrator
    ) -> PermanentMigrationFailureStoreState {
        guard let state = try? classify(queue, migrator: migrator) else {
            return .unavailable
        }
        switch state {
        case .legacy(let schemaVersion) where schemaVersion == originalSchemaVersion:
            return .unchangedLegacy
        case .legacy, .current:
            return .partiallyMigratedNotReady
        case .fresh:
            return .unavailable
        }
    }
}

private final class PermanentMigrationCoordinator: @unchecked Sendable {
    static let shared = PermanentMigrationCoordinator()

    private let lock = NSLock()

    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
