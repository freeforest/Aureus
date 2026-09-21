import Foundation
import GRDB

enum PermanentRestoreMaintenanceState: Equatable, Sendable {
    case ready
    case restoring
    case recoveryRequired
}

enum PermanentRestoreFailureCategory: String, Equatable, Sendable {
    case databaseOpen
    case migration
    case integrity
    case foreignKeys
    case schema
    case migrationMetadata
    case requiredTables
    case applicationInvariant
}

enum PermanentRestoreOperationCategory: String, Equatable, Sendable {
    case internalGenerationRestore
    case externalGenerationRestore
}

struct PermanentRestoreResult: Equatable, Sendable {
    let previousSchemaVersion: Int
    let candidateSchemaVersion: Int
    let finalSchemaVersion: Int
    let migrationRan: Bool
    let safetyGenerationIdentity: String
    let operationCategory: PermanentRestoreOperationCategory
}

enum PermanentRestoreError: Error, Equatable, Sendable {
    case maintenanceUnavailable
    case unsafeCurrentStore
    case candidateValidationFailed
    case unsupportedCandidateSchema
    case candidateStagingFailed
    case currentStoreValidationFailed
    case safetyBackupFailed
    case storeCloseFailed
    case replacementFailed
    case restoreFailedRollbackSucceeded(PermanentRestoreFailureCategory)
    case rollbackFailed
    case evidenceRequiresCompleteRestore
}

extension PermanentRestoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .maintenanceUnavailable:
            "Permanent Store maintenance is unavailable."
        case .unsafeCurrentStore:
            "The Permanent Store location is not eligible for internal Restore."
        case .candidateValidationFailed:
            "The internal Backup generation did not pass Restore validation."
        case .unsupportedCandidateSchema:
            "The internal Backup schema is not supported by this version."
        case .candidateStagingFailed:
            "The validated internal Backup could not be staged safely."
        case .currentStoreValidationFailed:
            "The current Permanent Store did not pass pre-Restore validation."
        case .safetyBackupFailed:
            "A validated safety Backup could not be created."
        case .storeCloseFailed:
            "The current Permanent Store could not enter maintenance safely."
        case .replacementFailed:
            "The Permanent Store replacement did not complete."
        case .restoreFailedRollbackSucceeded:
            "Restore failed and the prior Permanent Store was recovered from the safety Backup."
        case .rollbackFailed:
            "Restore recovery requires manual maintenance; the safety Backup was retained."
        case .evidenceRequiresCompleteRestore:
            "This dataset requires a complete material-aware Restore."
        }
    }
}

protocol PermanentRestoreFileOperations: Sendable {
    func copyValidatedDatabase(from sourceURL: URL, to stagingURL: URL) throws
    func atomicallyReplaceDatabase(at databaseURL: URL, with stagingURL: URL) throws
}

struct LocalPermanentRestoreFileOperations: PermanentRestoreFileOperations {
    func copyValidatedDatabase(from sourceURL: URL, to stagingURL: URL) throws {
        try FileManager.default.copyItem(at: sourceURL, to: stagingURL)
    }

    func atomicallyReplaceDatabase(at databaseURL: URL, with stagingURL: URL) throws {
        _ = try FileManager.default.replaceItemAt(
            databaseURL,
            withItemAt: stagingURL,
            backupItemName: nil,
            options: []
        )
    }
}

private extension PermanentDatabaseValidationFailure {
    var category: PermanentRestoreFailureCategory {
        switch self {
        case .databaseOpenOrIntegrity: .integrity
        case .foreignKeys: .foreignKeys
        case .schema: .schema
        case .migrationMetadata: .migrationMetadata
        case .requiredTables: .requiredTables
        case .financialAuthority: .applicationInvariant
        case .applicationInvariant: .applicationInvariant
        }
    }
}

enum PermanentRestoreStageKind: String {
    case candidate
    case rollback
}

enum PermanentRestoreService {
    static let currentSchemaVersion = PermanentDatabaseValidation.currentSchemaVersion

    static func validateLiveDatabaseURL(_ databaseURL: URL) throws {
        guard databaseURL.isFileURL,
              databaseURL.path.hasPrefix("/"),
              databaseURL.lastPathComponent == PermanentBackupService.databaseFileName else {
            throw PermanentRestoreError.unsafeCurrentStore
        }
        let parentURL = databaseURL.deletingLastPathComponent()
        do {
            let parentValues = try parentURL.resourceValues(forKeys: [
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
                throw PermanentRestoreError.unsafeCurrentStore
            }
        } catch let error as PermanentRestoreError {
            throw error
        } catch {
            throw PermanentRestoreError.unsafeCurrentStore
        }
    }

    static func validateCandidate(
        _ generationURL: URL,
        in backupRoot: URL
    ) throws -> PermanentBackupGeneration {
        let generation: PermanentBackupGeneration
        do {
            generation = try PermanentBackupService.validateGeneration(
                generationURL,
                in: backupRoot
            )
        } catch {
            throw PermanentRestoreError.candidateValidationFailed
        }
        guard (1...currentSchemaVersion).contains(generation.manifest.schemaVersion) else {
            throw PermanentRestoreError.unsupportedCandidateSchema
        }
        return generation
    }

    static func stage(
        generation: PermanentBackupGeneration,
        databaseURL: URL,
        operationID: UUID,
        kind: PermanentRestoreStageKind,
        fileOperations: any PermanentRestoreFileOperations
    ) throws -> (url: URL, inspection: PermanentDatabaseInspection) {
        let parentURL = databaseURL.deletingLastPathComponent().standardizedFileURL
        let stagingURL = ownedStageURL(
            parentURL: parentURL,
            operationID: operationID,
            kind: kind
        )
        guard isOwnedStage(
            stagingURL,
            parentURL: parentURL,
            operationID: operationID,
            kind: kind
        ), !FileManager.default.fileExists(atPath: stagingURL.path) else {
            throw PermanentRestoreError.candidateStagingFailed
        }

        let sourceURL = generation.directoryURL.appendingPathComponent(
            PermanentBackupService.databaseFileName,
            isDirectory: false
        )
        do {
            try fileOperations.copyValidatedDatabase(from: sourceURL, to: stagingURL)
            let values = try stagingURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey
            ])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw PermanentRestoreError.candidateStagingFailed
            }
            let digest = try PermanentBackupService.streamingDigest(of: stagingURL)
            guard digest.byteCount == generation.manifest.databaseByteCount,
                  digest.sha256 == generation.manifest.databaseSHA256 else {
                throw PermanentRestoreError.candidateStagingFailed
            }
            let inspection = try inspectFile(
                stagingURL,
                expectedSchemaVersion: generation.manifest.schemaVersion,
                requireCurrentApplicationSchema: false
            )
            return (stagingURL, inspection)
        } catch let error as PermanentRestoreError {
            cleanupOwnedStage(
                stagingURL,
                parentURL: parentURL,
                operationID: operationID,
                kind: kind
            )
            throw error
        } catch {
            cleanupOwnedStage(
                stagingURL,
                parentURL: parentURL,
                operationID: operationID,
                kind: kind
            )
            throw PermanentRestoreError.candidateStagingFailed
        }
    }

    static func inspectFile(
        _ databaseURL: URL,
        expectedSchemaVersion: Int,
        requireCurrentApplicationSchema: Bool
    ) throws -> PermanentDatabaseInspection {
        try PermanentDatabaseValidation.inspectFile(
            databaseURL,
            expectedSchemaVersion: expectedSchemaVersion,
            requireCurrentApplicationSchema: requireCurrentApplicationSchema
        )
    }

    static func inspect(
        _ queue: DatabaseQueue,
        expectedSchemaVersion: Int,
        requireCurrentApplicationSchema: Bool
    ) throws -> PermanentDatabaseInspection {
        try PermanentDatabaseValidation.inspect(
            queue,
            expectedSchemaVersion: expectedSchemaVersion,
            requireCurrentApplicationSchema: requireCurrentApplicationSchema
        )
    }

    static func reopenValidatedCurrentDatabase(
        at databaseURL: URL,
        expectedAccountIDs: [String]
    ) throws -> DatabaseQueue {
        let reopened = try DatabaseQueueFactory.open(at: databaseURL)
        do {
            let inspection = try inspect(
                reopened,
                expectedSchemaVersion: currentSchemaVersion,
                requireCurrentApplicationSchema: true
            )
            guard inspection.accountIDs == expectedAccountIDs else {
                throw PermanentDatabaseValidationFailure.applicationInvariant
            }
            return reopened
        } catch {
            try? reopened.close()
            throw error
        }
    }

    static func removeLiveSidecars(for databaseURL: URL) throws {
        let parentURL = databaseURL.deletingLastPathComponent().standardizedFileURL
        for suffix in ["-wal", "-shm"] {
            let sidecarURL = URL(fileURLWithPath: databaseURL.path + suffix)
            guard sidecarURL.deletingLastPathComponent().standardizedFileURL == parentURL else {
                throw PermanentRestoreError.unsafeCurrentStore
            }
            guard FileManager.default.fileExists(atPath: sidecarURL.path) else { continue }
            do {
                let values = try sidecarURL.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey
                ])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    throw PermanentRestoreError.unsafeCurrentStore
                }
                try FileManager.default.removeItem(at: sidecarURL)
            } catch let error as PermanentRestoreError {
                throw error
            } catch {
                throw PermanentRestoreError.storeCloseFailed
            }
        }
    }

    static func cleanupOwnedStage(
        _ stagingURL: URL,
        databaseURL: URL,
        operationID: UUID,
        kind: PermanentRestoreStageKind
    ) {
        cleanupOwnedStage(
            stagingURL,
            parentURL: databaseURL.deletingLastPathComponent().standardizedFileURL,
            operationID: operationID,
            kind: kind
        )
    }

    private static func cleanupOwnedStage(
        _ stagingURL: URL,
        parentURL: URL,
        operationID: UUID,
        kind: PermanentRestoreStageKind
    ) {
        guard isOwnedStage(
            stagingURL,
            parentURL: parentURL,
            operationID: operationID,
            kind: kind
        ), FileManager.default.fileExists(atPath: stagingURL.path) else { return }
        try? FileManager.default.removeItem(at: stagingURL)
    }

    private static func ownedStageURL(
        parentURL: URL,
        operationID: UUID,
        kind: PermanentRestoreStageKind
    ) -> URL {
        parentURL.appendingPathComponent(
            ".restore-\(kind.rawValue)-\(operationID.uuidString.lowercased()).sqlite",
            isDirectory: false
        )
    }

    private static func isOwnedStage(
        _ stagingURL: URL,
        parentURL: URL,
        operationID: UUID,
        kind: PermanentRestoreStageKind
    ) -> Bool {
        stagingURL.standardizedFileURL == ownedStageURL(
            parentURL: parentURL,
            operationID: operationID,
            kind: kind
        ).standardizedFileURL
            && stagingURL.deletingLastPathComponent().standardizedFileURL == parentURL
    }
}

extension WealthStore {
    func restorePermanentBackup(
        _ generationURL: URL,
        in backupRoot: URL,
        appVersion: String,
        createdAt: UTCInstant,
        operationID: UUID = UUID(),
        safetyGenerationID: UUID = UUID(),
        fileOperations: any PermanentRestoreFileOperations = LocalPermanentRestoreFileOperations()
    ) throws -> PermanentRestoreResult {
        guard maintenanceState == .ready else {
            throw PermanentRestoreError.maintenanceUnavailable
        }
        do { try requireFormatOneEligible() }
        catch { throw PermanentRestoreError.evidenceRequiresCompleteRestore }
        try PermanentRestoreService.validateLiveDatabaseURL(databaseURL)
        let candidate = try PermanentRestoreService.validateCandidate(
            generationURL,
            in: backupRoot
        )
        return try restoreValidatedPermanentBackup(
            candidate,
            in: backupRoot,
            appVersion: appVersion,
            createdAt: createdAt,
            operationID: operationID,
            safetyGenerationID: safetyGenerationID,
            operationCategory: .internalGenerationRestore,
            fileOperations: fileOperations
        )
    }

    func restoreValidatedPermanentBackup(
        _ candidate: PermanentBackupGeneration,
        in backupRoot: URL,
        appVersion: String,
        createdAt: UTCInstant,
        operationID: UUID,
        safetyGenerationID: UUID,
        operationCategory: PermanentRestoreOperationCategory,
        fileOperations: any PermanentRestoreFileOperations
    ) throws -> PermanentRestoreResult {
        guard maintenanceState == .ready else {
            throw PermanentRestoreError.maintenanceUnavailable
        }
        do {
            try requireFormatOneEligible()
            _ = try PermanentBackupService.validateGeneration(candidate.directoryURL, in: candidate.directoryURL.deletingLastPathComponent())
        } catch { throw PermanentRestoreError.evidenceRequiresCompleteRestore }
        maintenanceState = .restoring

        var candidateStageURL: URL?
        defer {
            if let candidateStageURL {
                PermanentRestoreService.cleanupOwnedStage(
                    candidateStageURL,
                    databaseURL: databaseURL,
                    operationID: operationID,
                    kind: .candidate
                )
            }
        }

        do {
            try PermanentRestoreService.validateLiveDatabaseURL(databaseURL)
            guard (1...PermanentRestoreService.currentSchemaVersion)
                .contains(candidate.manifest.schemaVersion) else {
                throw PermanentRestoreError.unsupportedCandidateSchema
            }
            let stagedCandidate = try PermanentRestoreService.stage(
                generation: candidate,
                databaseURL: databaseURL,
                operationID: operationID,
                kind: .candidate,
                fileOperations: fileOperations
            )
            candidateStageURL = stagedCandidate.url

            let currentInspection: PermanentDatabaseInspection
            do {
                currentInspection = try PermanentRestoreService.inspect(
                    queue,
                    expectedSchemaVersion: PermanentRestoreService.currentSchemaVersion,
                    requireCurrentApplicationSchema: true
                )
            } catch {
                throw PermanentRestoreError.currentStoreValidationFailed
            }

            let safetyGeneration: PermanentBackupGeneration
            do {
                safetyGeneration = try PermanentBackupService.create(
                    from: queue,
                    in: backupRoot,
                    appVersion: appVersion,
                    createdAt: createdAt,
                    generationID: safetyGenerationID
                )
                let verifiedSafety = try PermanentBackupService.validateGeneration(
                    safetyGeneration.directoryURL,
                    in: backupRoot
                )
                let safetyInspection = try PermanentRestoreService.inspectFile(
                    verifiedSafety.directoryURL.appendingPathComponent(
                        PermanentBackupService.databaseFileName,
                        isDirectory: false
                    ),
                    expectedSchemaVersion: PermanentRestoreService.currentSchemaVersion,
                    requireCurrentApplicationSchema: true
                )
                guard safetyInspection.accountIDs == currentInspection.accountIDs else {
                    throw PermanentRestoreError.safetyBackupFailed
                }
            } catch {
                throw PermanentRestoreError.safetyBackupFailed
            }

            do {
                try checkpoint()
            } catch {
                maintenanceState = .ready
                throw PermanentRestoreError.storeCloseFailed
            }
            do {
                try queue.close()
            } catch {
                if let stillOpenInspection = try? PermanentRestoreService.inspect(
                    queue,
                    expectedSchemaVersion: PermanentRestoreService.currentSchemaVersion,
                    requireCurrentApplicationSchema: true
                ), stillOpenInspection.accountIDs == currentInspection.accountIDs {
                    maintenanceState = .ready
                    throw PermanentRestoreError.storeCloseFailed
                }
                do {
                    queue = try PermanentRestoreService.reopenValidatedCurrentDatabase(
                        at: databaseURL,
                        expectedAccountIDs: currentInspection.accountIDs
                    )
                    maintenanceState = .ready
                    throw PermanentRestoreError.storeCloseFailed
                } catch let error as PermanentRestoreError where error == .storeCloseFailed {
                    throw error
                } catch {
                    maintenanceState = .recoveryRequired
                    throw PermanentRestoreError.storeCloseFailed
                }
            }

            do {
                try PermanentRestoreService.removeLiveSidecars(for: databaseURL)
                try fileOperations.atomicallyReplaceDatabase(
                    at: databaseURL,
                    with: stagedCandidate.url
                )
            } catch {
                if let reopened = try? PermanentRestoreService.reopenValidatedCurrentDatabase(
                    at: databaseURL,
                    expectedAccountIDs: currentInspection.accountIDs
                ) {
                    queue = reopened
                    maintenanceState = .ready
                    throw PermanentRestoreError.replacementFailed
                }
                do {
                    queue = try rollback(
                        from: safetyGeneration,
                        expectedAccountIDs: currentInspection.accountIDs,
                        operationID: operationID,
                        fileOperations: fileOperations
                    )
                    maintenanceState = .ready
                    throw PermanentRestoreError.replacementFailed
                } catch let error as PermanentRestoreError where error == .replacementFailed {
                    throw error
                } catch {
                    maintenanceState = .recoveryRequired
                    throw PermanentRestoreError.rollbackFailed
                }
            }

            let activationFailure: PermanentRestoreFailureCategory?
            var restoredQueue: DatabaseQueue?
            do {
                let reopened = try DatabaseQueueFactory.open(at: databaseURL)
                restoredQueue = reopened
                do {
                    try migrator.migrate(reopened)
                } catch {
                    throw PermanentRestoreActivationFailure(.migration)
                }
                let restoredInspection: PermanentDatabaseInspection
                do {
                    restoredInspection = try PermanentRestoreService.inspect(
                        reopened,
                        expectedSchemaVersion: PermanentRestoreService.currentSchemaVersion,
                        requireCurrentApplicationSchema: true
                    )
                } catch let error as PermanentDatabaseValidationFailure {
                    throw PermanentRestoreActivationFailure(error.category)
                } catch {
                    throw PermanentRestoreActivationFailure(.integrity)
                }
                guard restoredInspection.accountIDs == stagedCandidate.inspection.accountIDs else {
                    throw PermanentRestoreActivationFailure(.applicationInvariant)
                }
                queue = reopened
                activationFailure = nil
            } catch let error as PermanentRestoreActivationFailure {
                activationFailure = error.category
            } catch {
                activationFailure = .databaseOpen
            }

            if let activationFailure {
                try? restoredQueue?.close()
                do {
                    queue = try rollback(
                        from: safetyGeneration,
                        expectedAccountIDs: currentInspection.accountIDs,
                        operationID: operationID,
                        fileOperations: fileOperations
                    )
                    maintenanceState = .ready
                } catch {
                    maintenanceState = .recoveryRequired
                    throw PermanentRestoreError.rollbackFailed
                }
                throw PermanentRestoreError.restoreFailedRollbackSucceeded(activationFailure)
            }

            maintenanceState = .ready
            return PermanentRestoreResult(
                previousSchemaVersion: currentInspection.schemaVersion,
                candidateSchemaVersion: candidate.manifest.schemaVersion,
                finalSchemaVersion: PermanentRestoreService.currentSchemaVersion,
                migrationRan: candidate.manifest.schemaVersion < PermanentRestoreService.currentSchemaVersion,
                safetyGenerationIdentity: safetyGeneration.directoryURL.lastPathComponent,
                operationCategory: operationCategory
            )
        } catch let error as PermanentRestoreError {
            if maintenanceState == .restoring {
                maintenanceState = .ready
            }
            throw error
        } catch {
            if maintenanceState == .restoring {
                maintenanceState = .ready
            }
            throw PermanentRestoreError.candidateValidationFailed
        }
    }

    private func rollback(
        from safetyGeneration: PermanentBackupGeneration,
        expectedAccountIDs: [String],
        operationID: UUID,
        fileOperations: any PermanentRestoreFileOperations
    ) throws -> DatabaseQueue {
        let revalidatedSafety = try PermanentBackupService.validateGeneration(
            safetyGeneration.directoryURL,
            in: safetyGeneration.directoryURL.deletingLastPathComponent()
        )
        let stagedSafety = try PermanentRestoreService.stage(
            generation: revalidatedSafety,
            databaseURL: databaseURL,
            operationID: operationID,
            kind: .rollback,
            fileOperations: fileOperations
        )
        defer {
            PermanentRestoreService.cleanupOwnedStage(
                stagedSafety.url,
                databaseURL: databaseURL,
                operationID: operationID,
                kind: .rollback
            )
        }
        try PermanentRestoreService.removeLiveSidecars(for: databaseURL)
        try fileOperations.atomicallyReplaceDatabase(
            at: databaseURL,
            with: stagedSafety.url
        )
        try PermanentRestoreService.removeLiveSidecars(for: databaseURL)
        let reopened = try DatabaseQueueFactory.open(at: databaseURL)
        do {
            let inspection = try PermanentRestoreService.inspect(
                reopened,
                expectedSchemaVersion: PermanentRestoreService.currentSchemaVersion,
                requireCurrentApplicationSchema: true
            )
            guard inspection.accountIDs == expectedAccountIDs else {
                throw PermanentDatabaseValidationFailure.applicationInvariant
            }
            return reopened
        } catch {
            try? reopened.close()
            throw error
        }
    }
}

private struct PermanentRestoreActivationFailure: Error {
    let category: PermanentRestoreFailureCategory

    init(_ category: PermanentRestoreFailureCategory) {
        self.category = category
    }
}
