import Foundation
import GRDB
import Testing
@testable import Aureus

@Suite("Settings internal data lifecycle")
struct SettingsDataLifecycleTests {
    @Test("Post-commit inventory failure is not an External Restore rollback")
    @MainActor
    func committedRestoreRefreshFailureDiagnostics() async throws {
        let context = try lifecycleContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try await context.store.insertIsolationSentinel(id: "original", name: "Synthetic Private Original")
        let setup = context.model()
        #expect(await setup.createBackup())
        #expect(setup.selectGeneration(try #require(setup.generations.first?.id)))
        #expect(await setup.exportSelected(to: context.destination))
        let source = try #require(FileManager.default.contentsOfDirectory(at: context.destination, includingPropertiesForKeys: nil).first)
        try await context.store.insertIsolationSentinel(id: "later", name: "Synthetic Later Value")
        let live = context.externalRestoreClient
        let backupRoot = context.paths.internalBackupDirectoryURL
        let retained = context.root.appendingPathComponent("SyntheticRetainedBackups")
        let client = SettingsDataLifecycleExternalRestoreClient { url, version, instant, operation, safety in
            let result = try await live.restore(url, version, instant, operation, safety)
            try FileManager.default.moveItem(at: backupRoot, to: retained)
            try Data("synthetic inventory failure".utf8).write(to: backupRoot)
            return result
        }
        let sink = RecordingDataLifecycleSink()
        let model = context.model(externalRestoreClient: client, diagnostics: sink.diagnostics)
        #expect(!(await model.restoreExternal(from: source)))
        #expect(model.state == .failed(.externalRestoreFailed))
        #expect(!model.isRecoveryRequired)
        #expect(try await context.store.isolationSentinels() == ["Synthetic Private Original"])
        #expect(FileManager.default.fileExists(atPath: retained.path))
        #expect(sink.events == [.init(operation: .settingsExternalRestoreWorkflow, outcome: .failed, errorCategory: .inventoryRefreshAfterCommit)])
    }

    @Test("Guard rejection and raw synthetic error payload never become diagnostic payload")
    @MainActor
    func diagnosticPrivacyAndGuards() async throws {
        let context = try lifecycleContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let sink = RecordingDataLifecycleSink()
        let client = SettingsDataLifecycleExportClient { _, _, _ in
            throw NSError(domain: "Synthetic.Private.Account", code: 1, userInfo: [NSLocalizedDescriptionKey: "/synthetic/private/backup-secret.sqlite"])
        }
        let model = context.model(exportClient: client, diagnostics: sink.diagnostics)
        await model.load()
        #expect(!(await model.restoreSelected(confirmed: false)))
        #expect(!(await model.restoreSelected(confirmed: true)))
        #expect(!(await model.exportSelected(to: context.destination)))
        model.externalSourceSelectionFailed()
        model.externalDestinationSelectionFailed()
        #expect(sink.events.isEmpty)
        #expect(await model.createBackup())
        #expect(model.selectGeneration(try #require(model.generations.first?.id)))
        #expect(!(await model.exportSelected(to: context.destination)))
        #expect(model.state == .failed(.exportFailed))
        #expect(sink.events == [.init(operation: .settingsBackupWorkflow, outcome: .succeeded, errorCategory: .none), .init(operation: .settingsExportWorkflow, outcome: .failed, errorCategory: .unknown)])
    }

    @Test("Initial load and reconstruction remain read-only and empty")
    @MainActor
    func initialLoadIsReadOnly() async throws {
        let context = try lifecycleContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        let sink = RecordingDataLifecycleSink()
        let model = context.model(diagnostics: sink.diagnostics)
        #expect(model.state == .idle)
        #expect(model.generations.isEmpty)
        await model.load()
        #expect(model.state == .ready)
        #expect(model.validGenerationCount == 0)

        let replacement = context.model()
        #expect(replacement.state == .idle)
        #expect(replacement.validGenerationCount == 0)
        #expect(!FileManager.default.fileExists(atPath: context.paths.internalBackupDirectoryURL.path))
        #expect(sink.events.isEmpty)
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
        let sink = RecordingDataLifecycleSink()
        let model = context.model(diagnostics: sink.diagnostics)
        await model.load()
        #expect(await model.createBackup())
        #expect(model.state == .ready)
        #expect(model.validGenerationCount == 1)
        #expect(model.operationMessage == "Backup Created")
        #expect(try await context.store.permanentBackupInventory(
            in: context.paths.internalBackupDirectoryURL
        ).validGenerations.count == 1)
        #expect(sink.events == [.init(operation: .settingsBackupWorkflow, outcome: .succeeded, errorCategory: .none)])
    }

    @Test("Create failure publishes no fabricated row")
    @MainActor
    func createFailureHasNoFakeGeneration() async throws {
        let context = try lifecycleContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let sink = RecordingDataLifecycleSink()
        let model = SettingsDataLifecycleModel(
            store: context.store,
            backupRoot: context.root.appendingPathComponent("NotBackups"),
            appVersion: lifecycleAppVersion,
            clock: lifecycleClock,
            exportClient: context.exportClient,
            externalRestoreClient: context.externalRestoreClient,
            diagnostics: sink.diagnostics
        )
        #expect(!(await model.createBackup()))
        #expect(model.state == .failed(.createFailed))
        #expect(model.generations.isEmpty)
        #expect(sink.events == [.init(operation: .settingsBackupWorkflow, outcome: .failed, errorCategory: .backup)])
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
        #expect(!model.canExport)
        #expect(model.canRestoreExternal)
    }

    @Test("Export requires a currently valid selection")
    @MainActor
    func exportSelectionLifecycle() async throws {
        let context = try lifecycleContext(ids: [lifecycleUUID(21)])
        defer { try? FileManager.default.removeItem(at: context.root) }
        let model = context.model()
        await model.load()
        #expect(!model.canExport)
        #expect(await model.createBackup())
        #expect(!model.canExport)
        let identity = try #require(model.generations.first?.id)
        #expect(model.selectGeneration(identity))
        #expect(model.canExport)
        await model.load()
        #expect(model.selectedGenerationID == nil)
        #expect(!model.canExport)
    }

    @Test("Explicit Export preserves internal inventory and publishes sanitized result")
    @MainActor
    func explicitExternalExport() async throws {
        let context = try lifecycleContext(ids: [lifecycleUUID(22), lifecycleUUID(23)])
        defer { try? FileManager.default.removeItem(at: context.root) }
        let sink = RecordingDataLifecycleSink()
        let model = context.model(diagnostics: sink.diagnostics)
        await model.load()
        #expect(await model.createBackup())
        let identity = try #require(model.generations.first?.id)
        let source = try #require(try await context.store.permanentBackupInventory(
            in: context.paths.internalBackupDirectoryURL
        ).validGenerations.first)
        let sourceDatabase = source.directoryURL.appendingPathComponent(
            PermanentBackupService.databaseFileName
        )
        let sourceManifest = source.directoryURL.appendingPathComponent(
            PermanentBackupService.manifestFileName
        )
        let digestBefore = try PermanentBackupService.streamingDigest(of: sourceDatabase)
        let manifestBefore = try Data(contentsOf: sourceManifest)

        #expect(model.selectGeneration(identity))
        #expect(await model.exportSelected(to: context.destination))
        #expect(model.state == .ready)
        #expect(model.operationMessage == "External Backup Export Completed")
        #expect(model.selectedGenerationID == identity)
        #expect(model.canExport)
        let result = try #require(model.externalExportResult)
        #expect(result.schemaVersion == 7)
        #expect(result.databaseByteCount > 0)
        #expect(result.operationCategory == .internalGenerationExternalExport)
        #expect(model.externalExportResultLabel == "External Backup export completed: schema 7, \(result.databaseByteCount) bytes.")

        let externalGenerations = try FileManager.default.contentsOfDirectory(
            at: context.destination,
            includingPropertiesForKeys: nil
        )
        #expect(externalGenerations.count == 1)
        let exported = try #require(externalGenerations.first)
        #expect(try lifecycleArtifactNames(at: exported) == ["aureus.sqlite", "manifest.json"])
        #expect(try await context.store.permanentBackupInventory(
            in: context.paths.internalBackupDirectoryURL
        ).validGenerations.count == 1)
        #expect(try PermanentBackupService.streamingDigest(of: sourceDatabase) == digestBefore)
        #expect(try Data(contentsOf: sourceManifest) == manifestBefore)

        let presentation = [
            model.statusLabel,
            model.externalExportResultLabel ?? "",
            model.errorLabel ?? ""
        ].joined(separator: " ")
        #expect(!presentation.contains(context.destination.path))
        #expect(!presentation.contains("Synthetic Settings"))
        #expect(!presentation.contains("Credential"))

        let reconstructed = context.model()
        await reconstructed.load()
        #expect(reconstructed.externalExportResult == nil)
        #expect(reconstructed.selectedGenerationID == nil)
        #expect(!reconstructed.canExport)
        #expect(sink.events == [.init(operation: .settingsBackupWorkflow, outcome: .succeeded, errorCategory: .none), .init(operation: .settingsExportWorkflow, outcome: .succeeded, errorCategory: .none)])
    }

    @Test("Export failure is finite recoverable and never recovery-required")
    @MainActor
    func externalExportFailurePresentation() async throws {
        let context = try lifecycleContext(ids: [lifecycleUUID(24), lifecycleUUID(25)])
        defer { try? FileManager.default.removeItem(at: context.root) }
        let failing = SettingsDataLifecycleExportClient { _, _, _ in
            throw PermanentBackupExportError.destinationCollision
        }
        let sink = RecordingDataLifecycleSink()
        let model = context.model(exportClient: failing, diagnostics: sink.diagnostics)
        await model.load()
        #expect(await model.createBackup())
        let identity = try #require(model.generations.first?.id)
        #expect(model.selectGeneration(identity))
        #expect(!(await model.exportSelected(to: context.destination)))
        #expect(model.state == .failed(.exportFailed))
        #expect(model.errorLabel == "Data lifecycle error: The selected internal Backup could not be exported and verified.")
        #expect(!model.isRecoveryRequired)
        #expect(model.selectedGenerationID == identity)
        #expect(model.canExport)
        #expect(model.externalExportResult == nil)
        #expect(sink.events.last == .init(operation: .settingsExportWorkflow, outcome: .failed, errorCategory: .export))
    }

    @Test("Exporting blocks Create Restore and a second Export")
    @MainActor
    func exportingBlocksConcurrentOperations() async throws {
        let context = try lifecycleContext(ids: [lifecycleUUID(26), lifecycleUUID(27)])
        defer { try? FileManager.default.removeItem(at: context.root) }
        let blocker = BlockingLifecycleExportClient()
        let client = SettingsDataLifecycleExportClient { source, destination, operationID in
            try await blocker.export(source, destination, operationID)
        }
        let sink = RecordingDataLifecycleSink()
        let model = context.model(exportClient: client, diagnostics: sink.diagnostics)
        await model.load()
        #expect(await model.createBackup())
        let identity = try #require(model.generations.first?.id)
        #expect(model.selectGeneration(identity))

        let first = Task { await model.exportSelected(to: context.destination) }
        for _ in 0..<1_000 where !blocker.hasStarted {
            await Task.yield()
        }
        #expect(blocker.hasStarted)
        #expect(model.state == .exportingBackup)
        #expect(!model.canCreateBackup)
        #expect(!model.canRestore)
        #expect(!model.canExport)
        #expect(!model.canRestoreExternal)
        #expect(!(await model.createBackup()))
        #expect(!(await model.restoreSelected(confirmed: true)))
        #expect(!(await model.exportSelected(to: context.destination)))
        blocker.finish()
        #expect(await first.value)
        #expect(model.state == .ready)
        #expect(sink.events.filter { $0.operation == .settingsExportWorkflow }.count == 1)
    }

    @Test("Foundation revalidation rejects a stale source after selection")
    @MainActor
    func staleSourceRejectedAtExport() async throws {
        let context = try lifecycleContext(ids: [lifecycleUUID(28), lifecycleUUID(29)])
        defer { try? FileManager.default.removeItem(at: context.root) }
        let model = context.model()
        await model.load()
        #expect(await model.createBackup())
        let identity = try #require(model.generations.first?.id)
        let generation = try #require(try await context.store.permanentBackupInventory(
            in: context.paths.internalBackupDirectoryURL
        ).validGenerations.first)
        #expect(model.selectGeneration(identity))
        try FileManager.default.removeItem(
            at: generation.directoryURL.appendingPathComponent(PermanentBackupService.manifestFileName)
        )

        #expect(!(await model.exportSelected(to: context.destination)))
        #expect(model.state == .failed(.exportFailed))
        #expect(try FileManager.default.contentsOfDirectory(atPath: context.destination.path).isEmpty)
    }

    @Test("Export identity collision does not overwrite destination")
    @MainActor
    func exportCollisionIsFinite() async throws {
        let backupID = lifecycleUUID(31)
        let exportID = lifecycleUUID(32)
        let context = try lifecycleContext(ids: [backupID, exportID])
        defer { try? FileManager.default.removeItem(at: context.root) }
        let model = context.model()
        await model.load()
        #expect(await model.createBackup())
        let generation = try #require(model.generations.first)
        #expect(model.selectGeneration(generation.id))
        let collisionName = try PermanentBackupService.externalExportGenerationName(
            createdAt: generation.createdAt,
            operationID: exportID
        )
        let collision = context.destination.appendingPathComponent(collisionName)
        try FileManager.default.createDirectory(at: collision, withIntermediateDirectories: false)
        let sentinel = collision.appendingPathComponent("synthetic-existing")
        try Data("preserve".utf8).write(to: sentinel)

        #expect(!(await model.exportSelected(to: context.destination)))
        #expect(model.state == .failed(.exportFailed))
        #expect(try String(decoding: Data(contentsOf: sentinel), as: UTF8.self) == "preserve")
    }

    @Test("External Restore capability is independent of internal selection and uses distinct identities")
    @MainActor
    func externalRestoreCapabilityAndInvocation() async throws {
        let operationID = lifecycleUUID(33)
        let safetyID = lifecycleUUID(34)
        let context = try lifecycleContext(ids: [operationID, safetyID])
        defer { try? FileManager.default.removeItem(at: context.root) }
        let recorder = RecordingLifecycleExternalRestoreClient(
            result: lifecycleExternalRestoreResult(candidateSchema: 3, migrationRan: true)
        )
        let model = context.model(externalRestoreClient: recorder.client)
        await model.load()

        #expect(recorder.invocationCount == 0)
        #expect(model.selectedGenerationID == nil)
        #expect(model.canRestoreExternal)
        #expect(await model.restoreExternal(from: context.destination))
        #expect(recorder.invocationCount == 1)
        #expect(recorder.operationIDs == [operationID])
        #expect(recorder.safetyGenerationIDs == [safetyID])
        #expect(operationID != safetyID)
        #expect(model.operationMessage == "External Backup Restore Completed")
        #expect(model.externalRestoreResult?.sourceSchemaVersion == 3)
        #expect(model.externalRestoreResult?.finalSchemaVersion == 7)
        #expect(model.externalRestoreResult?.migrationRan == true)
        #expect(model.externalRestoreResult?.operationCategory == .externalGenerationRestore)
        #expect(model.externalRestoreResultLabel == "External Backup Restore completed: source schema 3, final schema 7, 4096 bytes.")
    }

    @Test("External Restore migration presentation covers every supported legacy schema", arguments: [1, 2, 3, 4, 5, 6])
    @MainActor
    func externalRestoreLegacyPresentation(schemaVersion: Int) async throws {
        let context = try lifecycleContext(ids: [lifecycleUUID(133), lifecycleUUID(134)])
        defer { try? FileManager.default.removeItem(at: context.root) }
        let recorder = RecordingLifecycleExternalRestoreClient(
            result: lifecycleExternalRestoreResult(
                candidateSchema: schemaVersion,
                migrationRan: true
            )
        )
        let model = context.model(externalRestoreClient: recorder.client)
        await model.load()
        #expect(await model.restoreExternal(from: context.destination))
        #expect(model.externalRestoreResult?.sourceSchemaVersion == schemaVersion)
        #expect(model.externalRestoreResult?.finalSchemaVersion == 7)
        #expect(model.externalRestoreResult?.migrationRan == true)
        #expect(model.externalRestoreResult?.operationCategory == .externalGenerationRestore)
        #expect(model.externalRestoreResultLabel == "External Backup Restore completed: source schema \(schemaVersion), final schema 7, 4096 bytes.")
    }

    @Test("Live External Restore retains the source and publishes only the internal safety generation")
    @MainActor
    func liveExternalRestoreLifecycle() async throws {
        let context = try lifecycleContext(ids: [
            lifecycleUUID(35), lifecycleUUID(36), lifecycleUUID(37), lifecycleUUID(38)
        ])
        defer { try? FileManager.default.removeItem(at: context.root) }
        try await context.store.insertIsolationSentinel(
            id: "settings-external-original",
            name: "Synthetic Settings External Original"
        )
        let sink = RecordingDataLifecycleSink()
        let model = context.model(diagnostics: sink.diagnostics)
        await model.load()
        #expect(await model.createBackup())
        let internalIdentity = try #require(model.generations.first?.id)
        #expect(model.selectGeneration(internalIdentity))
        #expect(await model.exportSelected(to: context.destination))
        let externalGeneration = try #require(
            FileManager.default.contentsOfDirectory(
                at: context.destination,
                includingPropertiesForKeys: nil
            ).first
        )
        let externalDatabase = externalGeneration.appendingPathComponent(
            PermanentBackupService.databaseFileName
        )
        let externalManifest = externalGeneration.appendingPathComponent(
            PermanentBackupService.manifestFileName
        )
        let databaseBefore = try PermanentBackupService.streamingDigest(of: externalDatabase)
        let manifestBefore = try Data(contentsOf: externalManifest)

        try await context.store.insertIsolationSentinel(
            id: "settings-external-current",
            name: "Synthetic Settings External Current"
        )
        #expect(await model.restoreExternal(from: externalGeneration))
        #expect(model.state == .ready)
        #expect(model.selectedGenerationID == nil)
        #expect(model.validGenerationCount == 2)
        #expect(model.generations.contains { $0.id == internalIdentity })
        #expect(!model.generations.contains { $0.id == externalGeneration.lastPathComponent })
        #expect(try await context.store.isolationSentinels() == ["Synthetic Settings External Original"])
        #expect(try PermanentBackupService.streamingDigest(of: externalDatabase) == databaseBefore)
        #expect(try Data(contentsOf: externalManifest) == manifestBefore)

        let inventory = try await context.store.permanentBackupInventory(
            in: context.paths.internalBackupDirectoryURL
        )
        let safety = try #require(inventory.validGenerations.first {
            $0.directoryURL.lastPathComponent != internalIdentity
        })
        #expect(try lifecycleAccountNames(in: safety).contains("Synthetic Settings External Current"))
        #expect(model.externalRestoreResult?.sourceSchemaVersion == 6)
        #expect(model.externalRestoreResult?.finalSchemaVersion == 6)
        #expect(model.externalRestoreResult?.migrationRan == false)
        #expect(model.externalRestoreResult?.operationCategory == .externalGenerationRestore)

        let reconstructed = context.model()
        await reconstructed.load()
        #expect(reconstructed.externalRestoreResult == nil)
        #expect(reconstructed.selectedGenerationID == nil)
        #expect(reconstructed.canRestoreExternal)
        #expect(sink.events == [.init(operation: .settingsBackupWorkflow, outcome: .succeeded, errorCategory: .none), .init(operation: .settingsExportWorkflow, outcome: .succeeded, errorCategory: .none), .init(operation: .settingsExternalRestoreWorkflow, outcome: .succeeded, errorCategory: .none)])
    }

    @Test("Invalid External candidate is a finite sanitized failure before safety Backup")
    @MainActor
    func invalidExternalRestorePresentation() async throws {
        let context = try lifecycleContext(ids: [lifecycleUUID(39), lifecycleUUID(40)])
        defer { try? FileManager.default.removeItem(at: context.root) }
        let sink = RecordingDataLifecycleSink()
        let model = context.model(diagnostics: sink.diagnostics)
        await model.load()
        #expect(!(await model.restoreExternal(from: context.destination)))
        #expect(model.state == .failed(.externalRestoreFailed))
        #expect(model.errorLabel == "Data lifecycle error: The selected External Backup could not be restored safely.")
        #expect(!model.isRecoveryRequired)
        #expect(try await context.store.permanentBackupInventory(
            in: context.paths.internalBackupDirectoryURL
        ).validGenerations.isEmpty)
        #expect(await context.store.maintenanceState == .ready)
        #expect(sink.events == [.init(operation: .settingsExternalRestoreWorkflow, outcome: .failed, errorCategory: .externalRestore)])
    }

    @Test("External Restore rollback success and failure have bounded states")
    @MainActor
    func externalRestoreRecoveryPresentation() async throws {
        let context = try lifecycleContext(ids: [
            lifecycleUUID(43), lifecycleUUID(44), lifecycleUUID(45), lifecycleUUID(46)
        ])
        defer { try? FileManager.default.removeItem(at: context.root) }
        let rolledBack = SettingsDataLifecycleExternalRestoreClient { _, _, _, _, _ in
            throw PermanentExternalRestoreError.restoreFailedRollbackSucceeded(.migration)
        }
        let sink = RecordingDataLifecycleSink()
        let finite = context.model(externalRestoreClient: rolledBack, diagnostics: sink.diagnostics)
        await finite.load()
        #expect(!(await finite.restoreExternal(from: context.destination)))
        #expect(finite.state == .failed(.externalRestoreRolledBack))
        #expect(finite.errorLabel == "Data lifecycle error: External Restore failed and the prior Permanent Store was recovered from the safety Backup.")
        #expect(!finite.isRecoveryRequired)

        let failedRollback = SettingsDataLifecycleExternalRestoreClient { _, _, _, _, _ in
            throw PermanentExternalRestoreError.rollbackFailed
        }
        let recovery = context.model(externalRestoreClient: failedRollback, diagnostics: sink.diagnostics)
        await recovery.load()
        #expect(!(await recovery.restoreExternal(from: context.destination)))
        #expect(sink.events == [.init(operation: .settingsExternalRestoreWorkflow, outcome: .rolledBack, errorCategory: .externalRestore), .init(operation: .settingsExternalRestoreWorkflow, outcome: .recoveryRequired, errorCategory: .externalRestore)])
        #expect(recovery.state == .recoveryRequired)
        #expect(recovery.recoveryRequiredLabel != nil)
        #expect(!recovery.canCreateBackup)
        #expect(!recovery.canRestore)
        #expect(!recovery.canExport)
        #expect(!recovery.canRestoreExternal)
        #expect(!(await recovery.restoreExternal(from: context.destination)))
    }

    @Test("External Restore blocks every concurrent data lifecycle mutation")
    @MainActor
    func externalRestoreBlocksConcurrentOperations() async throws {
        let context = try lifecycleContext(ids: [
            lifecycleUUID(47), lifecycleUUID(48), lifecycleUUID(49)
        ])
        defer { try? FileManager.default.removeItem(at: context.root) }
        let blocker = BlockingLifecycleExternalRestoreClient()
        let model = context.model(externalRestoreClient: blocker.client)
        await model.load()
        #expect(await model.createBackup())
        let identity = try #require(model.generations.first?.id)
        #expect(model.selectGeneration(identity))

        let restore = Task { await model.restoreExternal(from: context.destination) }
        for _ in 0..<1_000 where !blocker.hasStarted {
            await Task.yield()
        }
        #expect(blocker.hasStarted)
        #expect(model.state == .restoringExternalBackup)
        #expect(!model.canCreateBackup)
        #expect(!model.canRestore)
        #expect(!model.canExport)
        #expect(!model.canRestoreExternal)
        #expect(!(await model.createBackup()))
        #expect(!(await model.restoreSelected(confirmed: true)))
        #expect(!(await model.exportSelected(to: context.destination)))
        #expect(!(await model.restoreExternal(from: context.destination)))
        #expect(!model.selectGeneration(identity))
        blocker.finish()
        #expect(await restore.value)
        #expect(model.state == .ready)
    }

    @Test("Unconfirmed Restore has zero side effects")
    @MainActor
    func unconfirmedRestore() async throws {
        let context = try lifecycleContext(ids: [lifecycleUUID(30)])
        defer { try? FileManager.default.removeItem(at: context.root) }
        let sink = RecordingDataLifecycleSink()
        let model = context.model(diagnostics: sink.diagnostics)
        #expect(await model.createBackup())
        let identity = try #require(model.generations.first?.id)
        #expect(model.selectGeneration(identity))
        #expect(!(await model.restoreSelected(confirmed: false)))
        #expect(model.validGenerationCount == 1)
        #expect(try await context.store.permanentBackupInventory(
            in: context.paths.internalBackupDirectoryURL
        ).validGenerations.count == 1)
        #expect(await context.store.maintenanceState == .ready)
        #expect(sink.events.count == 1)
        #expect(sink.events[0].operation == .settingsBackupWorkflow)
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
        let sink = RecordingDataLifecycleSink()
        let model = context.model(diagnostics: sink.diagnostics)
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
        #expect(sink.events == [.init(operation: .settingsBackupWorkflow, outcome: .succeeded, errorCategory: .none), .init(operation: .settingsInternalRestoreWorkflow, outcome: .succeeded, errorCategory: .none)])
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
        let sink = RecordingDataLifecycleSink()
        let model = context.model(diagnostics: sink.diagnostics)
        #expect(await model.createBackup())
        let identity = try #require(model.generations.first?.id)
        #expect(model.selectGeneration(identity))
        #expect(!(await model.restoreSelected(confirmed: true)))
        #expect(model.state == .failed(.restoreRolledBack))
        #expect(model.errorLabel?.contains("recovered from the safety Backup") == true)
        #expect(try await context.store.isolationSentinels() == ["Synthetic Settings Rollback Old"])
        #expect(sink.events.last == .init(operation: .settingsInternalRestoreWorkflow, outcome: .rolledBack, errorCategory: .restore))
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
        let sink = RecordingDataLifecycleSink()
        let model = context.model(diagnostics: sink.diagnostics)
        #expect(await model.createBackup())
        let identity = try #require(model.generations.first?.id)
        #expect(model.selectGeneration(identity))
        #expect(!(await model.restoreSelected(confirmed: true)))
        #expect(model.state == .recoveryRequired)
        #expect(model.recoveryRequiredLabel != nil)
        #expect(!model.canCreateBackup)
        #expect(!model.canRestore)
        #expect(!model.canExport)
        #expect(!model.canRestoreExternal)
        #expect(!(await model.createBackup()))
        #expect(!(await model.exportSelected(to: context.destination)))
        #expect(!(await model.restoreExternal(from: context.destination)))
        #expect(!model.selectGeneration(identity))
        #expect(sink.events.last == .init(operation: .settingsInternalRestoreWorkflow, outcome: .recoveryRequired, errorCategory: .restore))
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
        #expect(
            dependencies.permanentBackupExportConfiguration
                == PermanentBackupExportConfiguration(
                    internalBackupRootURL: RuntimePaths.temporary(root: root).internalBackupDirectoryURL,
                    permanentDatabaseURL: RuntimePaths.temporary(root: root).permanentDatabaseURL,
                    marketCacheDatabaseURL: RuntimePaths.temporary(root: root).marketCacheDatabaseURL,
                    additionalProtectedDestinationRoots: []
                )
        )
        #expect(
            dependencies.permanentExternalRestoreConfiguration
                == PermanentExternalRestoreConfiguration(
                    internalBackupRootURL: RuntimePaths.temporary(root: root).internalBackupDirectoryURL,
                    permanentDatabaseURL: RuntimePaths.temporary(root: root).permanentDatabaseURL,
                    marketCacheDatabaseURL: RuntimePaths.temporary(root: root).marketCacheDatabaseURL,
                    additionalProtectedSourceRoots: []
                )
        )
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
    let destination: URL
    let store: WealthStore
    let ids: LifecycleIDSequence
    let operations: any PermanentRestoreFileOperations

    var exportConfiguration: PermanentBackupExportConfiguration {
        PermanentBackupExportConfiguration(
            internalBackupRootURL: paths.internalBackupDirectoryURL,
            permanentDatabaseURL: paths.permanentDatabaseURL,
            marketCacheDatabaseURL: paths.marketCacheDatabaseURL,
            additionalProtectedDestinationRoots: [
                root.appendingPathComponent("SyntheticRepository", isDirectory: true)
            ]
        )
    }

    var exportClient: SettingsDataLifecycleExportClient {
        .live(configuration: exportConfiguration)
    }

    var externalRestoreConfiguration: PermanentExternalRestoreConfiguration {
        PermanentExternalRestoreConfiguration(
            internalBackupRootURL: paths.internalBackupDirectoryURL,
            permanentDatabaseURL: paths.permanentDatabaseURL,
            marketCacheDatabaseURL: paths.marketCacheDatabaseURL,
            additionalProtectedSourceRoots: []
        )
    }

    var externalRestoreClient: SettingsDataLifecycleExternalRestoreClient {
        .live(store: store, configuration: externalRestoreConfiguration)
    }

    @MainActor
    func model(
        exportClient: SettingsDataLifecycleExportClient? = nil,
        externalRestoreClient: SettingsDataLifecycleExternalRestoreClient? = nil,
        diagnostics: DataLifecycleDiagnostics = .disabled
    ) -> SettingsDataLifecycleModel {
        SettingsDataLifecycleModel(
            store: store,
            backupRoot: paths.internalBackupDirectoryURL,
            appVersion: lifecycleAppVersion,
            clock: lifecycleClock,
            generationID: { ids.next() },
            restoreFileOperations: operations,
            exportClient: exportClient ?? self.exportClient,
            externalRestoreClient: externalRestoreClient ?? self.externalRestoreClient,
            diagnostics: diagnostics
        )
    }
}

private func lifecycleContext(
    ids: [UUID] = [],
    operations: any PermanentRestoreFileOperations = LocalPermanentRestoreFileOperations()
) throws -> LifecycleContext {
    let root = try lifecycleTemporaryDirectory()
    let paths = RuntimePaths.temporary(root: root)
    let destination = root.appendingPathComponent("ExternalDestination", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    return LifecycleContext(
        root: root,
        paths: paths,
        destination: destination,
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

private func lifecycleArtifactNames(at directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
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

private final class BlockingLifecycleExportClient: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var started = false

    var hasStarted: Bool { lock.withLock { started } }

    func export(
        _ source: URL,
        _ destination: URL,
        _ operationID: UUID
    ) async throws -> PermanentBackupExportResult {
        _ = source
        _ = destination
        _ = operationID
        await withCheckedContinuation { continuation in
            lock.withLock {
                started = true
                self.continuation = continuation
            }
        }
        return PermanentBackupExportResult(
            exportedGenerationIdentity: "synthetic-export",
            schemaVersion: 7,
            databaseByteCount: 1,
            operationCategory: .internalGenerationExternalExport
        )
    }

    func finish() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume()
    }
}

private func lifecycleExternalRestoreResult(
    candidateSchema: Int = 7,
    migrationRan: Bool = false
) -> PermanentExternalRestoreResult {
    PermanentExternalRestoreResult(
        previousSchemaVersion: 7,
        candidateSchemaVersion: candidateSchema,
        finalSchemaVersion: 7,
        migrationRan: migrationRan,
        safetyGenerationIdentity: "synthetic-safety",
        databaseByteCount: 4_096,
        operationCategory: .externalGenerationRestore
    )
}

private final class RecordingLifecycleExternalRestoreClient: @unchecked Sendable {
    private let lock = NSLock()
    private let result: PermanentExternalRestoreResult
    private var invocations: [(operationID: UUID, safetyGenerationID: UUID)] = []

    init(result: PermanentExternalRestoreResult) {
        self.result = result
    }

    var invocationCount: Int { lock.withLock { invocations.count } }
    var operationIDs: [UUID] { lock.withLock { invocations.map(\.operationID) } }
    var safetyGenerationIDs: [UUID] {
        lock.withLock { invocations.map(\.safetyGenerationID) }
    }

    var client: SettingsDataLifecycleExternalRestoreClient {
        SettingsDataLifecycleExternalRestoreClient { [self] _, _, _, operationID, safetyID in
            lock.withLock {
                invocations.append((operationID, safetyID))
            }
            return result
        }
    }
}

private final class BlockingLifecycleExternalRestoreClient: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var started = false

    var hasStarted: Bool { lock.withLock { started } }

    var client: SettingsDataLifecycleExternalRestoreClient {
        SettingsDataLifecycleExternalRestoreClient { [self] _, _, _, _, _ in
            await withCheckedContinuation { continuation in
                lock.withLock {
                    started = true
                    self.continuation = continuation
                }
            }
            return lifecycleExternalRestoreResult()
        }
    }

    func finish() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume()
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
