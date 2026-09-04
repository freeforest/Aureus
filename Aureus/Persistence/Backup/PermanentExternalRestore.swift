import Foundation

struct PermanentExternalRestoreConfiguration: Equatable, Sendable {
    let internalBackupRootURL: URL
    let permanentDatabaseURL: URL
    let marketCacheDatabaseURL: URL
    let additionalProtectedSourceRoots: [URL]
}

struct PermanentExternalRestoreResult: Equatable, Sendable {
    let previousSchemaVersion: Int
    let candidateSchemaVersion: Int
    let finalSchemaVersion: Int
    let migrationRan: Bool
    let safetyGenerationIdentity: String
    let databaseByteCount: Int64
    let operationCategory: PermanentRestoreOperationCategory
}

enum PermanentExternalRestoreError: Error, Equatable, Sendable {
    case maintenanceUnavailable
    case unsafeConfiguration
    case invalidExternalCandidate(PermanentBackupError)
    case candidateStagingFailed
    case currentStoreValidationFailed
    case safetyBackupFailed
    case storeCloseFailed
    case replacementFailed
    case restoreFailedRollbackSucceeded(PermanentRestoreFailureCategory)
    case rollbackFailed
}

extension PermanentExternalRestoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .maintenanceUnavailable:
            "Permanent Store maintenance is unavailable."
        case .unsafeConfiguration:
            "The External Restore configuration is not eligible for this operation."
        case .invalidExternalCandidate:
            "The selected External Backup generation did not pass Restore validation."
        case .candidateStagingFailed:
            "The validated External Backup could not be staged safely."
        case .currentStoreValidationFailed:
            "The current Permanent Store did not pass pre-Restore validation."
        case .safetyBackupFailed:
            "A validated safety Backup could not be created."
        case .storeCloseFailed:
            "The current Permanent Store could not enter maintenance safely."
        case .replacementFailed:
            "The Permanent Store replacement did not complete."
        case .restoreFailedRollbackSucceeded:
            "External Restore failed and the prior Permanent Store was recovered from the safety Backup."
        case .rollbackFailed:
            "External Restore recovery requires manual maintenance; the safety Backup was retained."
        }
    }
}

extension WealthStore {
    func restoreExternalPermanentBackup(
        _ externalGenerationURL: URL,
        configuration: PermanentExternalRestoreConfiguration,
        appVersion: String,
        createdAt: UTCInstant,
        operationID: UUID = UUID(),
        safetyGenerationID: UUID = UUID(),
        fileOperations: any PermanentRestoreFileOperations = LocalPermanentRestoreFileOperations()
    ) throws -> PermanentExternalRestoreResult {
        guard maintenanceState == .ready else {
            throw PermanentExternalRestoreError.maintenanceUnavailable
        }
        guard configuration.permanentDatabaseURL.standardizedFileURL
                == databaseURL.standardizedFileURL else {
            throw PermanentExternalRestoreError.unsafeConfiguration
        }
        do {
            try PermanentRestoreService.validateLiveDatabaseURL(databaseURL)
        } catch {
            throw PermanentExternalRestoreError.unsafeConfiguration
        }

        let candidate: PermanentBackupGeneration
        do {
            candidate = try PermanentBackupService.validateStandaloneExternalGeneration(
                externalGenerationURL,
                excluding: [
                    configuration.internalBackupRootURL,
                    configuration.permanentDatabaseURL,
                    configuration.permanentDatabaseURL.deletingLastPathComponent(),
                    configuration.marketCacheDatabaseURL,
                    configuration.marketCacheDatabaseURL.deletingLastPathComponent()
                ] + configuration.additionalProtectedSourceRoots
            )
        } catch let error as PermanentBackupError {
            throw PermanentExternalRestoreError.invalidExternalCandidate(error)
        } catch {
            throw PermanentExternalRestoreError.invalidExternalCandidate(.unsafePath)
        }

        do {
            let result = try restoreValidatedPermanentBackup(
                candidate,
                in: configuration.internalBackupRootURL,
                appVersion: appVersion,
                createdAt: createdAt,
                operationID: operationID,
                safetyGenerationID: safetyGenerationID,
                operationCategory: .externalGenerationRestore,
                fileOperations: fileOperations
            )
            return PermanentExternalRestoreResult(
                previousSchemaVersion: result.previousSchemaVersion,
                candidateSchemaVersion: result.candidateSchemaVersion,
                finalSchemaVersion: result.finalSchemaVersion,
                migrationRan: result.migrationRan,
                safetyGenerationIdentity: result.safetyGenerationIdentity,
                databaseByteCount: candidate.manifest.databaseByteCount,
                operationCategory: result.operationCategory
            )
        } catch let error as PermanentRestoreError {
            throw mapExternalRestoreError(error)
        } catch {
            throw PermanentExternalRestoreError.invalidExternalCandidate(.fileSystemFailure)
        }
    }

    private func mapExternalRestoreError(
        _ error: PermanentRestoreError
    ) -> PermanentExternalRestoreError {
        switch error {
        case .maintenanceUnavailable:
            .maintenanceUnavailable
        case .unsafeCurrentStore:
            .unsafeConfiguration
        case .candidateValidationFailed:
            .invalidExternalCandidate(.databaseOpenOrIntegrityFailure)
        case .unsupportedCandidateSchema:
            .invalidExternalCandidate(.schemaMismatch)
        case .candidateStagingFailed:
            .candidateStagingFailed
        case .currentStoreValidationFailed:
            .currentStoreValidationFailed
        case .safetyBackupFailed:
            .safetyBackupFailed
        case .storeCloseFailed:
            .storeCloseFailed
        case .replacementFailed:
            .replacementFailed
        case let .restoreFailedRollbackSucceeded(category):
            .restoreFailedRollbackSucceeded(category)
        case .rollbackFailed:
            .rollbackFailed
        }
    }
}
