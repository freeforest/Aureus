import Foundation
import Observation

enum SettingsDataLifecycleState: Equatable, Sendable {
    case idle
    case loading
    case ready
    case creatingBackup
    case restoring
    case exportingBackup
    case restoringExternalBackup
    case failed(SettingsDataLifecycleFailure)
    case recoveryRequired
}

enum SettingsDataLifecycleFailure: Equatable, Sendable {
    case inventoryUnavailable
    case createFailed
    case invalidSelection
    case restoreFailed
    case restoreRolledBack
    case exportFailed
    case externalRestoreFailed
    case externalRestoreRolledBack
}

struct SettingsBackupGeneration: Identifiable, Equatable, Sendable {
    let id: String
    let createdAt: String
    let appVersion: String
    let schemaVersion: Int
    let databaseByteCount: Int64
}

struct SettingsExternalBackupExportPresentation: Equatable, Sendable {
    let schemaVersion: Int
    let databaseByteCount: Int64
    let operationCategory: PermanentBackupExportOperationCategory
}

struct SettingsExternalBackupRestorePresentation: Equatable, Sendable {
    let sourceSchemaVersion: Int
    let finalSchemaVersion: Int
    let migrationRan: Bool
    let databaseByteCount: Int64
    let operationCategory: PermanentRestoreOperationCategory
}

struct SettingsDataLifecycleExportClient: Sendable {
    let export: @Sendable (URL, URL, UUID) async throws -> PermanentBackupExportResult

    static func live(
        configuration: PermanentBackupExportConfiguration
    ) -> SettingsDataLifecycleExportClient {
        SettingsDataLifecycleExportClient { source, destination, operationID in
            try await Task.detached(priority: .userInitiated) {
                try PermanentBackupExportService.export(
                    internalGenerationURL: source,
                    to: destination,
                    configuration: configuration,
                    operationID: operationID
                )
            }.value
        }
    }
}

struct SettingsDataLifecycleExternalRestoreClient: Sendable {
    let restore: @Sendable (
        URL,
        String,
        UTCInstant,
        UUID,
        UUID
    ) async throws -> PermanentExternalRestoreResult

    static func live(
        store: WealthStore,
        configuration: PermanentExternalRestoreConfiguration
    ) -> SettingsDataLifecycleExternalRestoreClient {
        SettingsDataLifecycleExternalRestoreClient {
            generationURL,
            appVersion,
            createdAt,
            operationID,
            safetyGenerationID in
            try await store.restoreExternalPermanentBackup(
                generationURL,
                configuration: configuration,
                appVersion: appVersion,
                createdAt: createdAt,
                operationID: operationID,
                safetyGenerationID: safetyGenerationID
            )
        }
    }
}

@MainActor
@Observable
final class SettingsDataLifecycleModel {
    private(set) var state: SettingsDataLifecycleState = .idle
    private(set) var generations: [SettingsBackupGeneration] = []
    private(set) var invalidGenerationCount = 0
    private(set) var ignoredArtifactCount = 0
    private(set) var selectedGenerationID: String?
    private(set) var operationMessage: String?
    private(set) var externalExportResult: SettingsExternalBackupExportPresentation?
    private(set) var externalRestoreResult: SettingsExternalBackupRestorePresentation?

    @ObservationIgnored private let store: WealthStore
    @ObservationIgnored private let backupRoot: URL
    @ObservationIgnored private let appVersion: String
    @ObservationIgnored private let clock: any Clock
    @ObservationIgnored private let generationID: @Sendable () -> UUID
    @ObservationIgnored private let restoreFileOperations: any PermanentRestoreFileOperations
    @ObservationIgnored private let exportClient: SettingsDataLifecycleExportClient
    @ObservationIgnored private let externalRestoreClient: SettingsDataLifecycleExternalRestoreClient
    @ObservationIgnored private let diagnostics: DataLifecycleDiagnostics
    @ObservationIgnored private var generationURLs: [String: URL] = [:]
    @ObservationIgnored private var revision = 0

    init(
        store: WealthStore,
        backupRoot: URL,
        appVersion: String,
        clock: any Clock,
        generationID: @escaping @Sendable () -> UUID = { UUID() },
        restoreFileOperations: any PermanentRestoreFileOperations = LocalPermanentRestoreFileOperations(),
        exportClient: SettingsDataLifecycleExportClient,
        externalRestoreClient: SettingsDataLifecycleExternalRestoreClient,
        diagnostics: DataLifecycleDiagnostics = .disabled
    ) {
        self.store = store
        self.backupRoot = backupRoot
        self.appVersion = appVersion
        self.clock = clock
        self.generationID = generationID
        self.restoreFileOperations = restoreFileOperations
        self.exportClient = exportClient
        self.externalRestoreClient = externalRestoreClient
        self.diagnostics = diagnostics
    }

    var validGenerationCount: Int { generations.count }

    var ignoredEntryCount: Int {
        invalidGenerationCount + ignoredArtifactCount
    }

    var isWorking: Bool {
        state == .loading
            || state == .creatingBackup
            || state == .restoring
            || state == .exportingBackup
            || state == .restoringExternalBackup
    }

    var isRecoveryRequired: Bool { state == .recoveryRequired }

    var canCreateBackup: Bool {
        !isWorking && !isRecoveryRequired
    }

    var canRestore: Bool {
        !isWorking
            && !isRecoveryRequired
            && selectedGenerationID.flatMap { generationURLs[$0] } != nil
    }

    var canExport: Bool {
        !isWorking
            && !isRecoveryRequired
            && selectedGenerationID.flatMap { generationURLs[$0] } != nil
    }

    var canRestoreExternal: Bool {
        !isWorking && !isRecoveryRequired
    }

    var statusLabel: String {
        switch state {
        case .idle: "Data lifecycle status: Idle"
        case .loading: "Data lifecycle status: Loading"
        case .ready: operationMessage.map { "Data lifecycle status: \($0)" }
                ?? "Data lifecycle status: Ready"
        case .creatingBackup: "Data lifecycle status: Creating Backup"
        case .restoring: "Data lifecycle status: Restoring"
        case .exportingBackup: "Data lifecycle status: Exporting Backup"
        case .restoringExternalBackup: "Data lifecycle status: Restoring External Backup"
        case .failed: "Data lifecycle status: Failed"
        case .recoveryRequired: "Data lifecycle status: Recovery Required"
        }
    }

    var errorLabel: String? {
        guard case let .failed(failure) = state else { return nil }
        return switch failure {
        case .inventoryUnavailable:
            "Data lifecycle error: Internal Backup inventory is unavailable."
        case .createFailed:
            "Data lifecycle error: The internal Backup could not be created and verified."
        case .invalidSelection:
            "Data lifecycle error: Select a currently valid internal Backup generation."
        case .restoreFailed:
            "Data lifecycle error: Restore did not complete. The active Store was not reported as restored."
        case .restoreRolledBack:
            "Data lifecycle error: Restore failed and the prior Permanent Store was recovered from the safety Backup."
        case .exportFailed:
            "Data lifecycle error: The selected internal Backup could not be exported and verified."
        case .externalRestoreFailed:
            "Data lifecycle error: The selected External Backup could not be restored safely."
        case .externalRestoreRolledBack:
            "Data lifecycle error: External Restore failed and the prior Permanent Store was recovered from the safety Backup."
        }
    }

    var externalExportResultLabel: String? {
        guard let result = externalExportResult else { return nil }
        return "External Backup export completed: schema \(result.schemaVersion), "
            + "\(result.databaseByteCount) bytes."
    }

    var externalRestoreResultLabel: String? {
        guard let result = externalRestoreResult else { return nil }
        return "External Backup Restore completed: source schema \(result.sourceSchemaVersion), "
            + "final schema \(result.finalSchemaVersion), \(result.databaseByteCount) bytes."
    }

    var recoveryRequiredLabel: String? {
        guard state == .recoveryRequired else { return nil }
        return "Data lifecycle recovery required: automatic operations are disabled and the retained safety Backup requires manual maintenance."
    }

    func load() async {
        guard !isWorking, !isRecoveryRequired else { return }
        let token = begin(.loading)
        do {
            let inventory = try await store.permanentBackupInventory(in: backupRoot)
            guard token == revision else { return }
            publish(inventory, clearingSelection: true)
            operationMessage = nil
            externalExportResult = nil
            externalRestoreResult = nil
            state = .ready
        } catch {
            guard token == revision else { return }
            clearInventory()
            state = .failed(.inventoryUnavailable)
        }
    }

    @discardableResult
    func createBackup() async -> Bool {
        guard canCreateBackup else { return false }
        let token = begin(.creatingBackup)
        var committed = false
        do {
            _ = try await store.createPermanentBackup(
                in: backupRoot,
                appVersion: appVersion,
                createdAt: clock.now(),
                generationID: generationID()
            )
            committed = true
            let inventory = try await store.permanentBackupInventory(in: backupRoot)
            guard token == revision else { return false }
            publish(inventory, clearingSelection: true)
            operationMessage = "Backup Created"
            state = .ready
            diagnostics.record(.init(operation: .settingsBackupWorkflow, outcome: .succeeded, errorCategory: .none))
            return true
        } catch {
            guard token == revision else { return false }
            selectedGenerationID = nil
            state = .failed(.createFailed)
            diagnostics.record(.init(operation: .settingsBackupWorkflow, outcome: .failed, errorCategory: committed ? .inventoryRefreshAfterCommit : (error is PermanentBackupError ? .backup : .unknown)))
            return false
        }
    }

    @discardableResult
    func selectGeneration(_ identity: String) -> Bool {
        guard !isWorking, !isRecoveryRequired, generationURLs[identity] != nil else {
            return false
        }
        selectedGenerationID = identity
        operationMessage = nil
        externalExportResult = nil
        externalRestoreResult = nil
        if case .failed = state { state = .ready }
        return true
    }

    @discardableResult
    func restoreSelected(confirmed: Bool) async -> Bool {
        guard confirmed else { return false }
        guard canRestore,
              let selectedIdentity = selectedGenerationID,
              let generationURL = generationURLs[selectedIdentity] else {
            if !isWorking, !isRecoveryRequired {
                state = .failed(.invalidSelection)
            }
            return false
        }

        let token = begin(.restoring)
        var committed = false
        do {
            let revalidated = try await store.validatePermanentBackup(
                generationURL,
                in: backupRoot
            )
            guard revalidated.directoryURL.lastPathComponent == selectedIdentity else {
                throw PermanentRestoreError.candidateValidationFailed
            }
            _ = try await store.restorePermanentBackup(
                generationURL,
                in: backupRoot,
                appVersion: appVersion,
                createdAt: clock.now(),
                operationID: generationID(),
                safetyGenerationID: generationID(),
                fileOperations: restoreFileOperations
            )
            committed = true
            let inventory = try await store.permanentBackupInventory(in: backupRoot)
            guard token == revision else { return false }
            publish(inventory, clearingSelection: true)
            operationMessage = "Restore Completed"
            state = .ready
            diagnostics.record(.init(operation: .settingsInternalRestoreWorkflow, outcome: .succeeded, errorCategory: .none))
            return true
        } catch let error as PermanentRestoreError {
            guard token == revision else { return false }
            selectedGenerationID = nil
            switch error {
            case .rollbackFailed:
                state = .recoveryRequired
                diagnostics.record(.init(operation: .settingsInternalRestoreWorkflow, outcome: committed ? .failed : .recoveryRequired, errorCategory: committed ? .inventoryRefreshAfterCommit : .restore))
            case .restoreFailedRollbackSucceeded:
                state = .failed(.restoreRolledBack)
                diagnostics.record(.init(operation: .settingsInternalRestoreWorkflow, outcome: committed ? .failed : .rolledBack, errorCategory: committed ? .inventoryRefreshAfterCommit : .restore))
            default:
                state = .failed(.restoreFailed)
                diagnostics.record(.init(operation: .settingsInternalRestoreWorkflow, outcome: .failed, errorCategory: committed ? .inventoryRefreshAfterCommit : .restore))
            }
            return false
        } catch {
            guard token == revision else { return false }
            selectedGenerationID = nil
            state = .failed(.restoreFailed)
            diagnostics.record(.init(operation: .settingsInternalRestoreWorkflow, outcome: .failed, errorCategory: committed ? .inventoryRefreshAfterCommit : (error is PermanentBackupError ? .backup : .unknown)))
            return false
        }
    }

    @discardableResult
    func exportSelected(to destinationURL: URL) async -> Bool {
        guard canExport,
              let selectedIdentity = selectedGenerationID,
              let generationURL = generationURLs[selectedIdentity] else {
            if !isWorking, !isRecoveryRequired {
                state = .failed(.invalidSelection)
            }
            return false
        }

        let token = begin(.exportingBackup)
        do {
            let result = try await exportClient.export(
                generationURL,
                destinationURL,
                generationID()
            )
            guard token == revision else { return false }
            externalExportResult = SettingsExternalBackupExportPresentation(
                schemaVersion: result.schemaVersion,
                databaseByteCount: result.databaseByteCount,
                operationCategory: result.operationCategory
            )
            operationMessage = "External Backup Export Completed"
            state = .ready
            diagnostics.record(.init(operation: .settingsExportWorkflow, outcome: .succeeded, errorCategory: .none))
            return true
        } catch {
            guard token == revision else { return false }
            externalExportResult = nil
            state = .failed(.exportFailed)
            diagnostics.record(.init(operation: .settingsExportWorkflow, outcome: .failed, errorCategory: error is PermanentBackupExportError ? .export : .unknown))
            return false
        }
    }

    func externalDestinationSelectionFailed() {
        guard !isWorking, !isRecoveryRequired else { return }
        externalExportResult = nil
        operationMessage = nil
        state = .failed(.exportFailed)
    }

    func externalSourceSelectionFailed() {
        guard !isWorking, !isRecoveryRequired else { return }
        externalRestoreResult = nil
        operationMessage = nil
        state = .failed(.externalRestoreFailed)
    }

    @discardableResult
    func restoreExternal(from generationURL: URL) async -> Bool {
        guard canRestoreExternal else { return false }

        let token = begin(.restoringExternalBackup)
        var committed = false
        do {
            let result = try await externalRestoreClient.restore(
                generationURL,
                appVersion,
                clock.now(),
                generationID(),
                generationID()
            )
            committed = true
            let inventory = try await store.permanentBackupInventory(in: backupRoot)
            guard token == revision else { return false }
            publish(inventory, clearingSelection: true)
            externalRestoreResult = SettingsExternalBackupRestorePresentation(
                sourceSchemaVersion: result.candidateSchemaVersion,
                finalSchemaVersion: result.finalSchemaVersion,
                migrationRan: result.migrationRan,
                databaseByteCount: result.databaseByteCount,
                operationCategory: result.operationCategory
            )
            operationMessage = "External Backup Restore Completed"
            state = .ready
            diagnostics.record(.init(operation: .settingsExternalRestoreWorkflow, outcome: .succeeded, errorCategory: .none))
            return true
        } catch let error as PermanentExternalRestoreError {
            guard token == revision else { return false }
            selectedGenerationID = nil
            externalRestoreResult = nil
            switch error {
            case .rollbackFailed:
                state = .recoveryRequired
                diagnostics.record(.init(operation: .settingsExternalRestoreWorkflow, outcome: committed ? .failed : .recoveryRequired, errorCategory: committed ? .inventoryRefreshAfterCommit : .externalRestore))
            case .restoreFailedRollbackSucceeded:
                state = .failed(.externalRestoreRolledBack)
                diagnostics.record(.init(operation: .settingsExternalRestoreWorkflow, outcome: committed ? .failed : .rolledBack, errorCategory: committed ? .inventoryRefreshAfterCommit : .externalRestore))
            default:
                state = .failed(.externalRestoreFailed)
                diagnostics.record(.init(operation: .settingsExternalRestoreWorkflow, outcome: .failed, errorCategory: committed ? .inventoryRefreshAfterCommit : .externalRestore))
            }
            return false
        } catch {
            guard token == revision else { return false }
            selectedGenerationID = nil
            externalRestoreResult = nil
            state = .failed(.externalRestoreFailed)
            diagnostics.record(.init(operation: .settingsExternalRestoreWorkflow, outcome: .failed, errorCategory: committed ? .inventoryRefreshAfterCommit : .unknown))
            return false
        }
    }

    private func begin(_ nextState: SettingsDataLifecycleState) -> Int {
        revision += 1
        operationMessage = nil
        externalExportResult = nil
        externalRestoreResult = nil
        state = nextState
        return revision
    }

    private func publish(
        _ inventory: PermanentBackupInventory,
        clearingSelection: Bool
    ) {
        generations = inventory.validGenerations.map { generation in
            SettingsBackupGeneration(
                id: generation.directoryURL.lastPathComponent,
                createdAt: generation.manifest.createdAt,
                appVersion: generation.manifest.appVersion,
                schemaVersion: generation.manifest.schemaVersion,
                databaseByteCount: generation.manifest.databaseByteCount
            )
        }
        generationURLs = Dictionary(
            uniqueKeysWithValues: inventory.validGenerations.map {
                ($0.directoryURL.lastPathComponent, $0.directoryURL)
            }
        )
        invalidGenerationCount = inventory.invalidGenerations.count
        ignoredArtifactCount = inventory.ignoredArtifactCount
        if clearingSelection || selectedGenerationID.flatMap({ generationURLs[$0] }) == nil {
            selectedGenerationID = nil
        }
    }

    private func clearInventory() {
        generations = []
        generationURLs = [:]
        invalidGenerationCount = 0
        ignoredArtifactCount = 0
        selectedGenerationID = nil
        operationMessage = nil
        externalExportResult = nil
        externalRestoreResult = nil
    }
}
