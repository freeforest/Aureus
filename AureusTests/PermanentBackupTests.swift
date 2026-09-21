import CryptoKit
import Foundation
import GRDB
import Testing
@testable import Aureus

@Suite("Permanent backup foundation")
struct PermanentBackupTests {
    @Test("Production and temporary Backup roots remain isolated")
    func runtimePaths() throws {
        let root = try backupTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("ApplicationSupport", isDirectory: true)
        let caches = root.appendingPathComponent("Caches", isDirectory: true)
        let production = RuntimePaths.production(
            applicationSupportDirectory: support,
            cachesDirectory: caches
        )
        let temporary = RuntimePaths.temporary(
            root: root.appendingPathComponent("InjectedTemporary", isDirectory: true)
        )

        #expect(
            production.internalBackupDirectoryURL
                == support.appendingPathComponent("Aureus/Backups", isDirectory: true)
        )
        #expect(
            temporary.internalBackupDirectoryURL
                == root.appendingPathComponent("InjectedTemporary/Backups", isDirectory: true)
        )
        #expect(production.internalBackupDirectoryURL != production.permanentDatabaseURL)
        #expect(production.internalBackupDirectoryURL != production.marketCacheDatabaseURL)
        #expect(temporary.internalBackupDirectoryURL != temporary.permanentDatabaseURL)
        #expect(temporary.internalBackupDirectoryURL != temporary.marketCacheDatabaseURL)
    }

    @Test("Consistent Backup opens read-only and contains committed records")
    func consistentBackupRoundTrip() async throws {
        let context = try backupContext()
        try await context.store.insertIsolationSentinel(
            id: "backup-round-trip-sentinel",
            name: "Synthetic Backup Round Trip Sentinel"
        )

        let generation = try await createBackup(context)
        let names = try backupAccountNames(generation)
        #expect(names == ["Synthetic Backup Round Trip Sentinel"])
        #expect(try await context.store.validatePermanentBackup(
            generation.directoryURL,
            in: context.paths.internalBackupDirectoryURL
        ) == generation)
    }

    @Test("Later source mutation cannot alter a committed generation")
    func immutableGenerationAfterSourceMutation() async throws {
        let context = try backupContext()
        try await context.store.insertIsolationSentinel(
            id: "backup-before-mutation",
            name: "Synthetic Before Backup"
        )
        let generation = try await createBackup(context)

        try await context.store.insertIsolationSentinel(
            id: "backup-after-mutation",
            name: "Synthetic After Backup"
        )
        #expect(try backupAccountNames(generation) == ["Synthetic Before Backup"])
        #expect(
            try await context.store.isolationSentinels()
                == ["Synthetic After Backup", "Synthetic Before Backup"]
        )
    }

    @Test("Manifest contains exactly six required fields")
    func manifestFields() async throws {
        let context = try backupContext()
        let generation = try await createBackup(context)
        let manifestURL = manifestURL(for: generation)
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
                as? [String: Any]
        )

        #expect(Set(object.keys) == Set([
            "backupFormatVersion", "appVersion", "schemaVersion", "createdAt",
            "databaseByteCount", "databaseSHA256"
        ]))
        #expect(generation.manifest.backupFormatVersion == 1)
        #expect(generation.manifest.appVersion == backupTestAppVersion)
        #expect(generation.manifest.schemaVersion == 7)
    }

    @Test("Manifest excludes business values Provider Credential and absolute paths")
    func manifestPrivacy() async throws {
        let context = try backupContext()
        try await context.store.createGoal(try Goal(
            id: UUID(uuidString: "a1000000-0000-4000-8000-000000000001")!,
            name: "Synthetic Private Goal Sentinel",
            target: Money(minorUnits: 98_765_432, currency: .cny),
            targetDate: try CivilDate(canonical: "2035-12-31")
        ))
        let generation = try await createBackup(context)
        let text = try String(contentsOf: manifestURL(for: generation), encoding: .utf8)
        let lowered = text.lowercased()

        #expect(!text.contains("Synthetic Private Goal Sentinel"))
        #expect(!text.contains("98765432"))
        #expect(!lowered.contains("provider"))
        #expect(!lowered.contains("credential"))
        #expect(!text.contains(context.root.path))
    }

    @Test("Manifest byte count matches the closed database file")
    func databaseByteCount() async throws {
        let context = try backupContext()
        let generation = try await createBackup(context)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: databaseURL(for: generation).path
        )
        let size = try #require(attributes[.size] as? NSNumber).int64Value
        #expect(size == generation.manifest.databaseByteCount)
    }

    @Test("Manifest SHA-256 matches the streaming database digest")
    func databaseSHA256() async throws {
        let context = try backupContext()
        let generation = try await createBackup(context)
        let digest = try PermanentBackupService.streamingDigest(of: databaseURL(for: generation))
        #expect(digest.byteCount == generation.manifest.databaseByteCount)
        #expect(digest.sha256 == generation.manifest.databaseSHA256)
        #expect(digest.sha256.count == 64)
        #expect(digest.sha256 == digest.sha256.lowercased())
    }

    @Test("Same-length database tamper is rejected by hash validation")
    func tamperedDatabase() async throws {
        let context = try backupContext()
        let generation = try await createBackup(context)
        let url = databaseURL(for: generation)
        var bytes = try Data(contentsOf: url)
        let index = bytes.index(before: bytes.endIndex)
        bytes[index] ^= 0x01
        try bytes.write(to: url)

        #expect(
            try await validationError(context, generation.directoryURL) == .hashMismatch
        )
    }

    @Test("Malformed manifest is rejected")
    func malformedManifest() async throws {
        let context = try backupContext()
        let generation = try await createBackup(context)
        try Data("{not-json".utf8).write(to: manifestURL(for: generation))
        #expect(
            try await validationError(context, generation.directoryURL) == .malformedManifest
        )
    }

    @Test("Unsupported manifest format is rejected")
    func unsupportedManifest() async throws {
        let context = try backupContext()
        let generation = try await createBackup(context)
        try rewriteManifest(generation) { manifest in
            replacing(manifest, backupFormatVersion: 2)
        }
        #expect(
            try await validationError(context, generation.directoryURL) == .unsupportedFormat
        )
    }

    @Test("Missing database is rejected")
    func missingDatabase() async throws {
        let context = try backupContext()
        let generation = try await createBackup(context)
        try FileManager.default.removeItem(at: databaseURL(for: generation))
        #expect(
            try await validationError(context, generation.directoryURL) == .missingDatabase
        )
    }

    @Test("Missing manifest is rejected")
    func missingManifest() async throws {
        let context = try backupContext()
        let generation = try await createBackup(context)
        try FileManager.default.removeItem(at: manifestURL(for: generation))
        #expect(
            try await validationError(context, generation.directoryURL) == .missingManifest
        )
    }

    @Test("Matching hash for non-SQLite content still fails integrity validation")
    func nonSQLiteWithMatchingHash() async throws {
        let context = try backupContext()
        let generation = try await createBackup(context)
        let database = databaseURL(for: generation)
        try Data(repeating: 0x41, count: 4_096).write(to: database)
        let digest = try PermanentBackupService.streamingDigest(of: database)
        try rewriteManifest(generation) { manifest in
            replacing(
                manifest,
                databaseByteCount: digest.byteCount,
                databaseSHA256: digest.sha256
            )
        }
        #expect(
            try await validationError(context, generation.directoryURL)
                == .databaseOpenOrIntegrityFailure
        )
    }

    @Test("Foreign-key violation fails staging validation before retention")
    func foreignKeyViolation() async throws {
        let context = try backupContext()
        let probe = try DatabaseQueue(path: context.paths.permanentDatabaseURL.path)
        try await probe.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
            try db.execute(sql: """
                INSERT INTO assets (id, container_id, name, currency_code, instrument_reference_id)
                VALUES ('backup-invalid-fk', 'missing-container', 'Synthetic Invalid FK', 'CNY', NULL)
                """)
        }
        try probe.close()

        do {
            _ = try await context.store.createPermanentBackup(
                in: context.paths.internalBackupDirectoryURL,
                appVersion: backupTestAppVersion,
                createdAt: backupTestInstant,
                generationID: UUID(uuidString: "b1000000-0000-4000-8000-000000000001")!
            )
            Issue.record("Foreign-key-invalid source must not commit a generation")
        } catch let error as PermanentBackupError {
            #expect(error == .foreignKeyFailure)
        }
        let inventory = try await context.store.permanentBackupInventory(
            in: context.paths.internalBackupDirectoryURL
        )
        #expect(inventory.validGenerations.isEmpty)
    }

    @Test("Manifest and database schema mismatch is rejected")
    func schemaMismatch() async throws {
        let context = try backupContext()
        let generation = try await createBackup(context)
        try rewriteManifest(generation) { manifest in
            replacing(manifest, schemaVersion: 5)
        }
        #expect(
            try await validationError(context, generation.directoryURL) == .schemaMismatch
        )
    }

    @Test("Generation symbolic link is rejected")
    func generationSymbolicLink() async throws {
        let context = try backupContext()
        let generation = try await createBackup(context)
        let link = context.paths.internalBackupDirectoryURL.appendingPathComponent(
            "backup-20260101T000000000Z-b2000000-0000-4000-8000-000000000001",
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: generation.directoryURL
        )
        #expect(try await validationError(context, link) == .symbolicLinkRejected)
    }

    @Test("Database symbolic link is rejected")
    func databaseSymbolicLink() async throws {
        let context = try backupContext()
        let generation = try await createBackup(context)
        let database = databaseURL(for: generation)
        let outside = context.root.appendingPathComponent("synthetic-database-copy.sqlite")
        try FileManager.default.copyItem(at: database, to: outside)
        try FileManager.default.removeItem(at: database)
        try FileManager.default.createSymbolicLink(at: database, withDestinationURL: outside)
        #expect(
            try await validationError(context, generation.directoryURL)
                == .symbolicLinkRejected
        )
    }

    @Test("Manifest symbolic link is rejected")
    func manifestSymbolicLink() async throws {
        let context = try backupContext()
        let generation = try await createBackup(context)
        let manifest = manifestURL(for: generation)
        let outside = context.root.appendingPathComponent("synthetic-manifest-copy.json")
        try FileManager.default.copyItem(at: manifest, to: outside)
        try FileManager.default.removeItem(at: manifest)
        try FileManager.default.createSymbolicLink(at: manifest, withDestinationURL: outside)
        #expect(
            try await validationError(context, generation.directoryURL)
                == .symbolicLinkRejected
        )
    }

    @Test("Unexpected artifact and SQLite sidecar are rejected")
    func unexpectedArtifact() async throws {
        let context = try backupContext()
        let generation = try await createBackup(context)
        try Data("synthetic-sidecar".utf8).write(
            to: generation.directoryURL.appendingPathComponent("aureus.sqlite-wal")
        )
        #expect(
            try await validationError(context, generation.directoryURL)
                == .unexpectedArtifact
        )
    }

    @Test("Seven valid generations retain only the latest five")
    func retainsLatestFive() async throws {
        let context = try backupContext()
        for offset in 0..<7 {
            _ = try await createBackup(
                context,
                millisecondsOffset: Int64(offset),
                generationID: orderedUUID(offset + 1)
            )
        }
        let inventory = try await context.store.permanentBackupInventory(
            in: context.paths.internalBackupDirectoryURL
        )
        #expect(inventory.validGenerations.count == 5)
        #expect(inventory.invalidGenerations.isEmpty)
        #expect(
            inventory.validGenerations.map(\.directoryURL.lastPathComponent)
                .allSatisfy { !$0.contains(orderedUUID(1).uuidString.lowercased()) }
        )
        #expect(
            inventory.validGenerations.map(\.directoryURL.lastPathComponent)
                .allSatisfy { !$0.contains(orderedUUID(2).uuidString.lowercased()) }
        )
    }

    @Test("Equal generation timestamps use deterministic identity ordering")
    func deterministicTieBreaker() async throws {
        let context = try backupContext()
        for offset in 0..<7 {
            _ = try await createBackup(
                context,
                generationID: orderedUUID(offset + 1)
            )
        }
        let inventory = try await context.store.permanentBackupInventory(
            in: context.paths.internalBackupDirectoryURL
        )
        let names = inventory.validGenerations.map(\.directoryURL.lastPathComponent)
        #expect(names == names.sorted())
        #expect(names.count == 5)
        #expect(names.first?.contains(orderedUUID(3).uuidString.lowercased()) == true)
        #expect(names.last?.contains(orderedUUID(7).uuidString.lowercased()) == true)
    }

    @Test("Failed sixth generation validation preserves the existing five")
    func failedSixthPreservesFive() async throws {
        let context = try backupContext()
        for offset in 0..<5 {
            _ = try await createBackup(
                context,
                millisecondsOffset: Int64(offset),
                generationID: orderedUUID(offset + 1)
            )
        }
        let before = try await context.store.permanentBackupInventory(
            in: context.paths.internalBackupDirectoryURL
        )
        let probe = try DatabaseQueue(path: context.paths.permanentDatabaseURL.path)
        try await probe.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
            try db.execute(sql: """
                INSERT INTO assets (id, container_id, name, currency_code, instrument_reference_id)
                VALUES ('backup-sixth-invalid-fk', 'missing-container', 'Synthetic Invalid Sixth', 'CNY', NULL)
                """)
        }
        try probe.close()

        do {
            _ = try await createBackup(
                context,
                millisecondsOffset: 6,
                generationID: orderedUUID(6)
            )
            Issue.record("Invalid sixth generation must fail before pruning")
        } catch let error as PermanentBackupError {
            #expect(error == .foreignKeyFailure)
        }
        let after = try await context.store.permanentBackupInventory(
            in: context.paths.internalBackupDirectoryURL
        )
        #expect(after.validGenerations == before.validGenerations)
        #expect(after.validGenerations.count == 5)
    }

    @Test("Invalid and unknown siblings are neither deleted nor counted as valid")
    func preservesInvalidAndUnknownSiblings() async throws {
        let context = try backupContext()
        _ = try await createBackup(context)
        let unknown = context.paths.internalBackupDirectoryURL
            .appendingPathComponent("owner-unknown-artifact", isDirectory: true)
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: false)
        let invalid = context.paths.internalBackupDirectoryURL.appendingPathComponent(
            "backup-20260101T000000000Z-b3000000-0000-4000-8000-000000000001",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: false)

        let inventory = try await context.store.prunePermanentBackups(
            in: context.paths.internalBackupDirectoryURL
        )
        #expect(inventory.validGenerations.count == 1)
        #expect(inventory.invalidGenerations.count == 1)
        #expect(inventory.invalidGenerations.first?.error == .missingManifest)
        #expect(inventory.ignoredArtifactCount == 1)
        #expect(FileManager.default.fileExists(atPath: unknown.path))
        #expect(FileManager.default.fileExists(atPath: invalid.path))
    }

    @Test("Backup does not mutate permanent schema records or source digest")
    func sourceRemainsUnchanged() async throws {
        let context = try backupContext()
        try await context.store.insertIsolationSentinel(
            id: "backup-source-integrity",
            name: "Synthetic Source Integrity Sentinel"
        )
        try await context.store.checkpoint()
        let hashBefore = try PermanentBackupService.streamingDigest(
            of: context.paths.permanentDatabaseURL
        )
        let recordsBefore = try await context.store.isolationSentinels()
        let schemaBefore = try await context.store.schemaVersion()

        _ = try await createBackup(context)
        try await context.store.checkpoint()
        let hashAfter = try PermanentBackupService.streamingDigest(
            of: context.paths.permanentDatabaseURL
        )
        #expect(hashAfter == hashBefore)
        #expect(try await context.store.isolationSentinels() == recordsBefore)
        #expect(try await context.store.schemaVersion() == schemaBefore)
        #expect(schemaBefore == 7)
    }

    @Test("Market Cache and key-like sentinels remain adjacent and excluded")
    func adjacentIsolation() async throws {
        let context = try backupContext()
        try FileManager.default.createDirectory(
            at: context.paths.marketCacheDatabaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let cacheSentinel = context.paths.marketCacheDatabaseURL
        let keyLikeSentinel = context.root.appendingPathComponent(
            "synthetic-key-like-sentinel.txt",
            isDirectory: false
        )
        try Data("synthetic-cache-only".utf8).write(to: cacheSentinel)
        try Data("synthetic-not-a-credential".utf8).write(to: keyLikeSentinel)
        let cacheBefore = try fileSHA256(cacheSentinel)
        let keyBefore = try fileSHA256(keyLikeSentinel)

        let generation = try await createBackup(context)
        #expect(try fileSHA256(cacheSentinel) == cacheBefore)
        #expect(try fileSHA256(keyLikeSentinel) == keyBefore)
        let artifactNames = try FileManager.default.contentsOfDirectory(
            atPath: generation.directoryURL.path
        )
        #expect(artifactNames.sorted() == ["aureus.sqlite", "manifest.json"])
        #expect(!artifactNames.contains(cacheSentinel.lastPathComponent))
        #expect(!artifactNames.contains(keyLikeSentinel.lastPathComponent))
    }

    @Test("Committed generation contains exactly database and manifest")
    func exactArtifactSet() async throws {
        let context = try backupContext()
        let generation = try await createBackup(context)
        let names = try FileManager.default.contentsOfDirectory(
            atPath: generation.directoryURL.path
        ).sorted()
        #expect(names == ["aureus.sqlite", "manifest.json"])
        #expect(!names.contains { $0.hasSuffix("-wal") || $0.hasSuffix("-shm") })
    }

    @Test("Repeated validation is deterministic")
    func deterministicValidation() async throws {
        let context = try backupContext()
        let generation = try await createBackup(context)
        let first = try await context.store.validatePermanentBackup(
            generation.directoryURL,
            in: context.paths.internalBackupDirectoryURL
        )
        let second = try await context.store.validatePermanentBackup(
            generation.directoryURL,
            in: context.paths.internalBackupDirectoryURL
        )
        #expect(first == second)
        #expect(first == generation)
    }

    @Test("Release workload creates and validates ten thousand permanent rows")
    func stage11BackupPerformance() async throws {
        let context = try backupContext(seedStore: false)
        try seedPerformanceRows(at: context.paths.permanentDatabaseURL, count: 10_000)
        let store = try WealthStore(databaseURL: context.paths.permanentDatabaseURL)
        let sourceBefore = try performanceSentinel(at: context.paths.permanentDatabaseURL)
        let clock = ContinuousClock()
        let start = clock.now
        let generation = try await store.createPermanentBackup(
            in: context.paths.internalBackupDirectoryURL,
            appVersion: backupTestAppVersion,
            createdAt: backupTestInstant,
            generationID: UUID(uuidString: "b4000000-0000-4000-8000-000000000001")!
        )
        _ = try await store.validatePermanentBackup(
            generation.directoryURL,
            in: context.paths.internalBackupDirectoryURL
        )
        let elapsed = start.duration(to: clock.now)
        let sourceAfter = try performanceSentinel(at: context.paths.permanentDatabaseURL)
        let components = elapsed.components
        let milliseconds = components.seconds * 1_000
            + components.attoseconds / 1_000_000_000_000_000

        #expect(sourceBefore == sourceAfter)
        #expect(sourceAfter.count == 10_000)
        #expect(elapsed < .seconds(10))
        print(
            "STAGE11_BACKUP_PERF rows=10000 create_validate_ms=\(milliseconds) "
                + "provider_requests=0 cache_reads=0 credential_reads=0"
        )
    }
}

private let backupTestAppVersion = "0.1-test"
private let backupTestInstant = UTCInstant(millisecondsSince1970: 1_788_112_800_000)

private struct BackupTestContext {
    let root: URL
    let paths: RuntimePaths
    let store: WealthStore
}

private func backupTestDirectory() throws -> URL {
    let base: URL
    if let injected = ProcessInfo.processInfo.environment["AUREUS_BACKUP_TEST_ROOT"],
       !injected.isEmpty {
        base = URL(fileURLWithPath: injected, isDirectory: true)
    } else {
        base = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("AureusTests/PermanentBackup", isDirectory: true)
    }
    let root = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func backupContext(seedStore: Bool = true) throws -> BackupTestContext {
    let root = try backupTestDirectory()
    let paths = RuntimePaths.temporary(root: root)
    let store = try WealthStore(databaseURL: paths.permanentDatabaseURL)
    if !seedStore {
        return BackupTestContext(root: root, paths: paths, store: store)
    }
    return BackupTestContext(root: root, paths: paths, store: store)
}

private func createBackup(
    _ context: BackupTestContext,
    millisecondsOffset: Int64 = 0,
    generationID: UUID = UUID(uuidString: "b0000000-0000-4000-8000-000000000001")!
) async throws -> PermanentBackupGeneration {
    try await context.store.createPermanentBackup(
        in: context.paths.internalBackupDirectoryURL,
        appVersion: backupTestAppVersion,
        createdAt: UTCInstant(
            millisecondsSince1970: backupTestInstant.millisecondsSince1970 + millisecondsOffset
        ),
        generationID: generationID
    )
}

private func validationError(
    _ context: BackupTestContext,
    _ generationURL: URL
) async throws -> PermanentBackupError? {
    do {
        _ = try await context.store.validatePermanentBackup(
            generationURL,
            in: context.paths.internalBackupDirectoryURL
        )
        return nil
    } catch let error as PermanentBackupError {
        return error
    }
}

private func databaseURL(for generation: PermanentBackupGeneration) -> URL {
    generation.directoryURL.appendingPathComponent("aureus.sqlite", isDirectory: false)
}

private func manifestURL(for generation: PermanentBackupGeneration) -> URL {
    generation.directoryURL.appendingPathComponent("manifest.json", isDirectory: false)
}

private func backupAccountNames(_ generation: PermanentBackupGeneration) throws -> [String] {
    var configuration = Configuration()
    configuration.readonly = true
    let queue = try DatabaseQueue(
        path: databaseURL(for: generation).path,
        configuration: configuration
    )
    defer { try? queue.close() }
    return try queue.read { db in
        try String.fetchAll(db, sql: "SELECT name FROM accounts ORDER BY name")
    }
}

private func rewriteManifest(
    _ generation: PermanentBackupGeneration,
    transform: (PermanentBackupManifest) -> PermanentBackupManifest
) throws {
    let url = manifestURL(for: generation)
    let original = try JSONDecoder().decode(
        PermanentBackupManifest.self,
        from: Data(contentsOf: url)
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(transform(original))
    data.append(0x0A)
    try data.write(to: url, options: .atomic)
}

private func replacing(
    _ manifest: PermanentBackupManifest,
    backupFormatVersion: Int? = nil,
    schemaVersion: Int? = nil,
    databaseByteCount: Int64? = nil,
    databaseSHA256: String? = nil
) -> PermanentBackupManifest {
    PermanentBackupManifest(
        backupFormatVersion: backupFormatVersion ?? manifest.backupFormatVersion,
        appVersion: manifest.appVersion,
        schemaVersion: schemaVersion ?? manifest.schemaVersion,
        createdAt: manifest.createdAt,
        databaseByteCount: databaseByteCount ?? manifest.databaseByteCount,
        databaseSHA256: databaseSHA256 ?? manifest.databaseSHA256
    )
}

private func orderedUUID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "b5000000-0000-4000-8000-%012d", value))!
}

private func fileSHA256(_ url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url))
        .map { String(format: "%02x", $0) }
        .joined()
}

private func seedPerformanceRows(at databaseURL: URL, count: Int) throws {
    let queue = try DatabaseQueueFactory.open(at: databaseURL)
    try DatabaseMigrations.permanentMigrator().migrate(queue)
    try queue.write { db in
        for index in 0..<count {
            try db.execute(
                sql: """
                    INSERT INTO accounts (id, name, kind, currency_code)
                    VALUES (?, ?, 'other', 'CNY')
                    """,
                arguments: [
                    String(format: "backup-perf-%05d", index),
                    String(format: "Synthetic Backup Row %05d", index)
                ]
            )
        }
    }
    try queue.close()
}

private func performanceSentinel(at databaseURL: URL) throws -> (count: Int, totalNameLength: Int) {
    var configuration = Configuration()
    configuration.readonly = true
    let queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
    defer { try? queue.close() }
    return try queue.read { db in
        let row = try #require(try Row.fetchOne(
            db,
            sql: "SELECT COUNT(*) AS count, COALESCE(SUM(length(name)), 0) AS length FROM accounts"
        ))
        return (row["count"], row["length"])
    }
}
