import Foundation
import GRDB
import Testing
@testable import Aureus

@Suite("Settings internal data lifecycle")
struct SettingsDataLifecycleTests {
    @Test("Initial load and reconstruction remain read-only and empty")
    @MainActor
    func initialLoadIsReadOnly() async throws {
        let context = try lifecycleContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        let model = context.model()
        #expect(model.state == .idle)
        #expect(model.generations.isEmpty)
        await model.load()
        #expect(model.state == .ready)
        #expect(model.validGenerationCount == 0)

        let replacement = context.model()
        #expect(replacement.state == .idle)
        #expect(replacement.validGenerationCount == 0)
        #expect(!FileManager.default.fileExists(atPath: context.paths.internalBackupDirectoryURL.path))
    }

    @Test("Valid inventory preserves Foundation order and ignored diagnostics")
    @MainActor
    func inventoryOrderingAndDiagnostics() async throws {
        let context = try lifecycleContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let first = try await lifecycleBackup(context, instantOffset: 1, identity: lifecycleUUID(1))
        let second = try await lifecycleBackup(context, instantOffset: 2, identity: lifecycleUUID(2))
        try FileManager.default.createDirectory(
            at: context.paths.internalBackupDirectoryURL.appendingPathComponent(
                "backup-20260115T000003000Z-11000000-0000-4000-8000-000000000003"
            ),
            withIntermediateDirectories: false
        )
        try Data("ignored".utf8).write(
            to: context.paths.internalBackupDirectoryURL.appendingPathComponent("unknown-sibling")
        )

        let authority = try await context.store.permanentBackupInventory(
            in: context.paths.internalBackupDirectoryURL
        )
        let model = context.model()
        await model.load()

        #expect(model.generations.map(\.id) == authority.validGenerations.map { $0.directoryURL.lastPathComponent })
        #expect(model.generations.map(\.id) == [
            first.directoryURL.lastPathComponent,
            second.directoryURL.lastPathComponent
        ])
        #expect(model.invalidGenerationCount == 1)
        #expect(model.ignoredArtifactCount == 1)
        #expect(model.ignoredEntryCount == 2)
        #expect(!model.selectGeneration("unknown-sibling"))
    }

    @Test("Explicit Create commits one validated generation")
    @MainActor
    func explicitCreate() async throws {
        let context = try lifecycleContext(ids: [lifecycleUUID(10)])
        defer { try? FileManager.default.removeItem(at: context.root) }
        let model = context.model()
        await model.load()
        #expect(await model.createBackup())
        #expect(model.state == .ready)
        #expect(model.validGenerationCount == 1)
        #expect(model.operationMessage == "Backup Created")
        #expect(try await context.store.permanentBackupInventory(
            in: context.paths.internalBackupDirectoryURL
        ).validGenerations.count == 1)
    }

    @Test("Create failure publishes no fabricated row")
    @MainActor
    func createFailureHasNoFakeGeneration() async throws {
        let context = try lifecycleContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let model = SettingsDataLifecycleModel(
            store: context.store,
            backupRoot: context.root.appendingPathComponent("NotBackups"),
            appVersion: lifecycleAppVersion,
            clock: lifecycleClock
        )
        #expect(!(await model.createBackup()))
        #expect(model.state == .failed(.createFailed))
        #expect(model.generations.isEmpty)
    }

    @Test("Reload revalidates inventory and clears stale selection")
    @MainActor
    func reloadClearsSelection() async throws {
        let context = try lifecycleContext(ids: [lifecycleUUID(20)])
        defer { try? FileManager.default.removeItem(at: context.root) }
        let model = context.model()
        #expect(await model.createBackup())
        let identity = try #require(model.generations.first?.id)
        #expect(model.selectGeneration(identity))
        #expect(model.canRestore)
        await model.load()
        #expect(model.selectedGenerationID == nil)
        #expect(!model.canRestore)
    }

    @Test("Unconfirmed Restore has zero side effects")
    @MainActor
    func unconfirmedRestore() async throws {
        let context = try lifecycleContext(ids: [lifecycleUUID(30)])
        defer { try? FileManager.default.removeItem(at: context.root) }
        let model = context.model()
        #expect(await model.createBackup())
        let identity = try #require(model.generations.first?.id)
        #expect(model.selectGeneration(identity))
        #expect(!(await model.restoreSelected(confirmed: false)))
        #expect(model.validGenerationCount == 1)
        #expect(try await context.store.permanentBackupInventory(
            in: context.paths.internalBackupDirectoryURL
        ).validGenerations.count == 1)
        #expect(await context.store.maintenanceState == .ready)
    }

    @Test("Confirmed Restore retains candidate and safety and rebinds the same Store")
    @MainActor
    func confirmedRestore() async throws {
        let context = try lifecycleContext(ids: [
            lifecycleUUID(40), lifecycleUUID(41), lifecycleUUID(42)
        ])
        defer { try? FileManager.default.removeItem(at: context.root) }
        try await context.store.insertIsolationSentinel(
            id: "settings-restore-original",
            name: "Synthetic Settings Restore Original"
        )
        let model = context.model()
        #expect(await model.createBackup())
        let candidateIdentity = try #require(model.generations.first?.id)
        let candidate = try #require(try await context.store.permanentBackupInventory(
            in: context.paths.internalBackupDirectoryURL
        ).validGenerations.first)
        let before = try PermanentBackupService.streamingDigest(
            of: candidate.directoryURL.appendingPathComponent(PermanentBackupService.databaseFileName)
        )
        try await context.store.insertIsolationSentinel(
            id: "settings-restore-current-only",
            name: "Synthetic Settings Restore Current Only"
        )

        #expect(model.selectGeneration(candidateIdentity))
        #expect(await model.restoreSelected(confirmed: true))
        #expect(model.validGenerationCount == 2)
        #expect(model.operationMessage == "Restore Completed")
        #expect(try await context.store.isolationSentinels() == ["Synthetic Settings Restore Original"])
        let after = try PermanentBackupService.streamingDigest(
            of: candidate.directoryURL.appendingPathComponent(PermanentBackupService.databaseFileName)
        )
        #expect(after == before)
        let inventory = try await context.store.permanentBackupInventory(
            in: context.paths.internalBackupDirectoryURL
        )
        let safety = try #require(inventory.validGenerations.first {
            $0.directoryURL.lastPathComponent != candidateIdentity
        })
        #expect(try lifecycleAccountNames(in: safety).contains("Synthetic Settings Restore Current Only"))
    }

    @Test("Rollback-succeeded Restore is a finite failed state")
    @MainActor
    func rollbackSucceededPresentation() async throws {
        let operations = InvalidatingRestoreOperations(failRollback: false)
        let context = try lifecycleContext(
            ids: [lifecycleUUID(50), lifecycleUUID(51), lifecycleUUID(52)],
            operations: operations
        )
        defer { try? FileManager.default.removeItem(at: context.root) }
        try await context.store.insertIsolationSentinel(
            id: "settings-rollback-old",
            name: "Synthetic Settings Rollback Old"
        )
        let model = context.model()
        #expect(await model.createBackup())
        let identity = try #require(model.generations.first?.id)
        #expect(model.selectGeneration(identity))
        #expect(!(await model.restoreSelected(confirmed: true)))
        #expect(model.state == .failed(.restoreRolledBack))
        #expect(model.errorLabel?.contains("recovered from the safety Backup") == true)
        #expect(try await context.store.isolationSentinels() == ["Synthetic Settings Rollback Old"])
    }

    @Test("Rollback failure enters recoveryRequired and blocks mutations")
    @MainActor
    func rollbackFailurePresentation() async throws {
        let operations = InvalidatingRestoreOperations(failRollback: true)
        let context = try lifecycleContext(
            ids: [lifecycleUUID(60), lifecycleUUID(61), lifecycleUUID(62)],
            operations: operations
        )
        defer { try? FileManager.default.removeItem(at: context.root) }
        let model = context.model()
        #expect(await model.createBackup())
        let identity = try #require(model.generations.first?.id)
        #expect(model.selectGeneration(identity))
        #expect(!(await model.restoreSelected(confirmed: true)))
        #expect(model.state == .recoveryRequired)
        #expect(model.recoveryRequiredLabel != nil)
        #expect(!model.canCreateBackup)
        #expect(!model.canRestore)
        #expect(!(await model.createBackup()))
        #expect(!model.selectGeneration(identity))
    }

    @Test("A restoring operation rejects concurrent mutation")
    @MainActor
    func concurrentOperationRejected() async throws {
        let operations = BlockingRestoreOperations()
        let context = try lifecycleContext(
            ids: [lifecycleUUID(70), lifecycleUUID(71), lifecycleUUID(72)],
            operations: operations
        )
        defer {
            operations.allowCopyToFinish.signal()
            try? FileManager.default.removeItem(at: context.root)
        }
        let model = context.model()
        #expect(await model.createBackup())
        let identity = try #require(model.generations.first?.id)
        #expect(model.selectGeneration(identity))
        let restore = Task { await model.restoreSelected(confirmed: true) }
        for _ in 0..<1_000 where !operations.copyHasStarted {
            await Task.yield()
        }
        #expect(operations.copyHasStarted)
        #expect(model.state == .restoring)
        #expect(!(await model.createBackup()))
        operations.allowCopyToFinish.signal()
        #expect(await restore.value)
    }

    @Test("Errors and rows expose no absolute path or financial content")
    @MainActor
    func presentationSanitization() async throws {
        let context = try lifecycleContext(ids: [lifecycleUUID(80)])
        defer { try? FileManager.default.removeItem(at: context.root) }
        let model = context.model()
        #expect(await model.createBackup())
        let combined = ([model.statusLabel, model.errorLabel ?? ""] + model.generations.flatMap {
            [$0.id, $0.createdAt, $0.appVersion, String($0.schemaVersion), String($0.databaseByteCount)]
        }).joined(separator: " ")
        #expect(!combined.contains(context.root.path))
        #expect(!combined.contains("Credential"))
        #expect(!combined.contains("Provider payload"))
        #expect(!combined.contains("Synthetic Settings"))
    }

    @Test("Temporary composition uses its injected internal Backup root")
    func temporaryCompositionRootIsolation() async throws {
        let root = try lifecycleTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = LaunchConfiguration(
            dataMode: .local,
            usesTemporaryStores: true,
            temporaryRoot: root
        )
        let dependencies = try await AppDependencies.make(
            configuration: configuration,
            migrationSafetyInputs: PermanentMigrationSafetyInputs(
                appVersion: lifecycleAppVersion,
                createdAt: { lifecycleInstant },
                generationID: { lifecycleUUID(90) }
            )
        )
        #expect(
            dependencies.internalBackupDirectoryURL
                == RuntimePaths.temporary(root: root).internalBackupDirectoryURL
        )
        #expect(dependencies.appVersion == lifecycleAppVersion)
        #expect(dependencies.internalBackupDirectoryURL.path.hasPrefix(root.path))
    }

    @Test("Inventory presentation remains bounded by Foundation retention")
    @MainActor
    func boundedInventory() async throws {
        let context = try lifecycleContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        for index in 1...7 {
            _ = try await lifecycleBackup(
                context,
                instantOffset: Int64(index),
                identity: lifecycleUUID(100 + index)
            )
        }
        let model = context.model()
        await model.load()
        #expect(model.validGenerationCount == PermanentBackupService.retentionLimit)
        #expect(model.generations.count == 5)
    }

    @Test("Model dependencies exclude Provider Credential Keychain Cache and external files")
    @MainActor
    func dependencyBoundary() async throws {
        let context = try lifecycleContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let model = context.model()
        await model.load()
        #expect(model.state == .ready)
        #expect(model.ignoredEntryCount == 0)
        #expect(!FileManager.default.fileExists(
            atPath: context.paths.marketCacheDatabaseURL.path
        ))
    }
}

private let lifecycleAppVersion = "11.settings-test"
private let lifecycleInstant = UTCInstant(millisecondsSince1970: 1_768_435_200_000)
private let lifecycleClock = FixedClock(instant: lifecycleInstant)

private struct LifecycleContext {
    let root: URL
    let paths: RuntimePaths
    let store: WealthStore
    let ids: LifecycleIDSequence
    let operations: any PermanentRestoreFileOperations

    @MainActor
    func model() -> SettingsDataLifecycleModel {
        SettingsDataLifecycleModel(
            store: store,
            backupRoot: paths.internalBackupDirectoryURL,
            appVersion: lifecycleAppVersion,
            clock: lifecycleClock,
            generationID: { ids.next() },
            restoreFileOperations: operations
        )
    }
}

private func lifecycleContext(
    ids: [UUID] = [],
    operations: any PermanentRestoreFileOperations = LocalPermanentRestoreFileOperations()
) throws -> LifecycleContext {
    let root = try lifecycleTemporaryDirectory()
    let paths = RuntimePaths.temporary(root: root)
    return LifecycleContext(
        root: root,
        paths: paths,
        store: try WealthStore(databaseURL: paths.permanentDatabaseURL),
        ids: LifecycleIDSequence(ids),
        operations: operations
    )
}

private func lifecycleBackup(
    _ context: LifecycleContext,
    instantOffset: Int64,
    identity: UUID
) async throws -> PermanentBackupGeneration {
    try await context.store.createPermanentBackup(
        in: context.paths.internalBackupDirectoryURL,
        appVersion: lifecycleAppVersion,
        createdAt: UTCInstant(
            millisecondsSince1970: lifecycleInstant.millisecondsSince1970 + instantOffset * 1_000
        ),
        generationID: identity
    )
}

private func lifecycleAccountNames(
    in generation: PermanentBackupGeneration
) throws -> [String] {
    var configuration = Configuration()
    configuration.readonly = true
    let queue = try DatabaseQueue(
        path: generation.directoryURL
            .appendingPathComponent(PermanentBackupService.databaseFileName).path,
        configuration: configuration
    )
    defer { try? queue.close() }
    return try queue.read { db in
        try String.fetchAll(db, sql: "SELECT name FROM accounts ORDER BY id")
    }
}

private func lifecycleTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("AureusSettingsDataLifecycleTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func lifecycleUUID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "11000000-0000-4000-8000-%012d", value))!
}

private final class LifecycleIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID]

    init(_ values: [UUID]) {
        self.values = values
    }

    func next() -> UUID {
        lock.withLock {
            values.isEmpty ? UUID() : values.removeFirst()
        }
    }
}

private final class InvalidatingRestoreOperations: PermanentRestoreFileOperations, @unchecked Sendable {
    private let live = LocalPermanentRestoreFileOperations()
    private let lock = NSLock()
    private let failRollback: Bool
    private var replacementCount = 0

    init(failRollback: Bool) {
        self.failRollback = failRollback
    }

    func copyValidatedDatabase(from sourceURL: URL, to stagingURL: URL) throws {
        try live.copyValidatedDatabase(from: sourceURL, to: stagingURL)
    }

    func atomicallyReplaceDatabase(at databaseURL: URL, with stagingURL: URL) throws {
        let count = lock.withLock { () -> Int in
            replacementCount += 1
            return replacementCount
        }
        if count == 2, failRollback {
            throw CocoaError(.fileWriteUnknown)
        }
        try live.atomicallyReplaceDatabase(at: databaseURL, with: stagingURL)
        if count == 1 {
            let queue = try DatabaseQueue(path: databaseURL.path)
            try queue.write { db in
                try db.execute(sql: "DROP TABLE goals")
            }
            try queue.close()
        }
    }
}

private final class BlockingRestoreOperations: PermanentRestoreFileOperations, @unchecked Sendable {
    let allowCopyToFinish = DispatchSemaphore(value: 0)
    private let live = LocalPermanentRestoreFileOperations()
    private let lock = NSLock()
    private var started = false

    var copyHasStarted: Bool { lock.withLock { started } }

    func copyValidatedDatabase(from sourceURL: URL, to stagingURL: URL) throws {
        try live.copyValidatedDatabase(from: sourceURL, to: stagingURL)
        lock.withLock { started = true }
        allowCopyToFinish.wait()
    }

    func atomicallyReplaceDatabase(at databaseURL: URL, with stagingURL: URL) throws {
        try live.atomicallyReplaceDatabase(at: databaseURL, with: stagingURL)
    }
}
