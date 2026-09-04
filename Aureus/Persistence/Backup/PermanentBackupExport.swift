import Foundation

enum PermanentBackupExportOperationCategory: String, Equatable, Sendable {
    case internalGenerationExternalExport
}

struct PermanentBackupExportResult: Equatable, Sendable {
    let exportedGenerationIdentity: String
    let schemaVersion: Int
    let databaseByteCount: Int64
    let operationCategory: PermanentBackupExportOperationCategory
}

struct PermanentBackupExportConfiguration: Equatable, Sendable {
    let internalBackupRootURL: URL
    let permanentDatabaseURL: URL
    let marketCacheDatabaseURL: URL
    let additionalProtectedDestinationRoots: [URL]
}

enum PermanentBackupExportError: Error, Equatable, Sendable {
    case invalidSourceGeneration
    case sourceOutsideConfiguredInternalBackupRoot
    case unsafeOrUnsupportedDestination
    case destinationSymbolicLink
    case destinationCollision
    case stagingCreationOrCopyFailure
    case digestOrByteCountMismatch
    case sqliteIntegrityFailure
    case foreignKeyFailure
    case schemaMismatchOrUnsupportedSchema
    case unexpectedArtifact
    case atomicCommitFailure
    case committedRevalidationFailure
}

extension PermanentBackupExportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidSourceGeneration:
            "The internal Backup generation did not pass export validation."
        case .sourceOutsideConfiguredInternalBackupRoot:
            "External export only accepts a configured internal Backup generation."
        case .unsafeOrUnsupportedDestination:
            "The external Backup destination is not eligible for this operation."
        case .destinationSymbolicLink:
            "The external Backup destination cannot use symbolic links."
        case .destinationCollision:
            "The external Backup generation already exists."
        case .stagingCreationOrCopyFailure:
            "The external Backup could not be staged safely."
        case .digestOrByteCountMismatch:
            "The external Backup data did not match its validated source."
        case .sqliteIntegrityFailure:
            "The external Backup database did not pass integrity validation."
        case .foreignKeyFailure:
            "The external Backup database did not pass relationship validation."
        case .schemaMismatchOrUnsupportedSchema:
            "The external Backup schema is not supported by this version."
        case .unexpectedArtifact:
            "The external Backup contains an unexpected artifact."
        case .atomicCommitFailure:
            "The external Backup could not be committed atomically."
        case .committedRevalidationFailure:
            "The committed external Backup did not pass final validation."
        }
    }
}

protocol PermanentBackupExportFileOperations: Sendable {
    func createDirectory(at url: URL) throws
    func copyItem(at sourceURL: URL, to destinationURL: URL) throws
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws
}

struct LocalPermanentBackupExportFileOperations: PermanentBackupExportFileOperations {
    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false
        )
    }

    func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }
}

enum PermanentBackupExportService {
    static func export(
        internalGenerationURL: URL,
        to externalDestinationDirectoryURL: URL,
        configuration: PermanentBackupExportConfiguration,
        operationID: UUID,
        fileOperations: any PermanentBackupExportFileOperations
            = LocalPermanentBackupExportFileOperations(),
        fileManager: FileManager = .default
    ) throws -> PermanentBackupExportResult {
        let source = try validatedSource(
            internalGenerationURL,
            configuration: configuration,
            fileManager: fileManager
        )
        try validateDestination(
            externalDestinationDirectoryURL,
            configuration: configuration,
            fileManager: fileManager
        )

        let sourceDatabaseURL = source.directoryURL.appendingPathComponent(
            PermanentBackupService.databaseFileName,
            isDirectory: false
        )
        let sourceManifestURL = source.directoryURL.appendingPathComponent(
            PermanentBackupService.manifestFileName,
            isDirectory: false
        )
        let sourceDigest = try mappedDigest(of: sourceDatabaseURL)
        let sourceManifestData = try readManifestBytes(at: sourceManifestURL)
        let finalName: String
        do {
            finalName = try PermanentBackupService.externalExportGenerationName(
                createdAt: source.manifest.createdAt,
                operationID: operationID
            )
        } catch {
            throw PermanentBackupExportError.invalidSourceGeneration
        }

        let destinationRoot = externalDestinationDirectoryURL.standardizedFileURL
        let stagingName = ".staging-\(operationID.uuidString.lowercased())"
        let stagingURL = destinationRoot.appendingPathComponent(
            stagingName,
            isDirectory: true
        )
        let finalURL = destinationRoot.appendingPathComponent(
            finalName,
            isDirectory: true
        )
        guard isDirectChild(stagingURL, of: destinationRoot),
              isDirectChild(finalURL, of: destinationRoot),
              isOwnedStagingName(stagingName, operationID: operationID) else {
            throw PermanentBackupExportError.unsafeOrUnsupportedDestination
        }
        guard !fileManager.fileExists(atPath: stagingURL.path),
              !fileManager.fileExists(atPath: finalURL.path) else {
            throw PermanentBackupExportError.destinationCollision
        }

        var stagingMayBeOwned = true
        defer {
            if stagingMayBeOwned {
                cleanupOwnedStaging(
                    stagingURL,
                    destinationRoot: destinationRoot,
                    operationID: operationID,
                    fileManager: fileManager
                )
            }
        }

        do {
            try fileOperations.createDirectory(at: stagingURL)
            try fileOperations.copyItem(
                at: sourceDatabaseURL,
                to: stagingURL.appendingPathComponent(
                    PermanentBackupService.databaseFileName,
                    isDirectory: false
                )
            )
            try fileOperations.copyItem(
                at: sourceManifestURL,
                to: stagingURL.appendingPathComponent(
                    PermanentBackupService.manifestFileName,
                    isDirectory: false
                )
            )
        } catch {
            throw PermanentBackupExportError.stagingCreationOrCopyFailure
        }

        let staged = try validateCopiedArtifact(
            stagingURL,
            destinationRoot: destinationRoot,
            sourceDigest: sourceDigest,
            sourceManifestData: sourceManifestData,
            committed: false,
            fileManager: fileManager
        )
        guard staged.manifest == source.manifest else {
            throw PermanentBackupExportError.digestOrByteCountMismatch
        }

        do {
            try fileOperations.moveItem(at: stagingURL, to: finalURL)
            stagingMayBeOwned = false
        } catch {
            throw PermanentBackupExportError.atomicCommitFailure
        }

        let committed = try validateCopiedArtifact(
            finalURL,
            destinationRoot: destinationRoot,
            sourceDigest: sourceDigest,
            sourceManifestData: sourceManifestData,
            committed: true,
            fileManager: fileManager
        )
        guard committed.manifest == source.manifest else {
            throw PermanentBackupExportError.committedRevalidationFailure
        }

        let sourceAfter: PermanentBackupGeneration
        do {
            sourceAfter = try PermanentBackupService.validateGeneration(
                source.directoryURL,
                in: configuration.internalBackupRootURL,
                fileManager: fileManager
            )
        } catch {
            throw PermanentBackupExportError.invalidSourceGeneration
        }
        guard sourceAfter.manifest == source.manifest,
              try mappedDigest(of: sourceDatabaseURL) == sourceDigest,
              try readManifestBytes(at: sourceManifestURL) == sourceManifestData else {
            throw PermanentBackupExportError.invalidSourceGeneration
        }

        return PermanentBackupExportResult(
            exportedGenerationIdentity: finalName,
            schemaVersion: committed.manifest.schemaVersion,
            databaseByteCount: committed.manifest.databaseByteCount,
            operationCategory: .internalGenerationExternalExport
        )
    }

    private static func validatedSource(
        _ generationURL: URL,
        configuration: PermanentBackupExportConfiguration,
        fileManager: FileManager
    ) throws -> PermanentBackupGeneration {
        let source: PermanentBackupGeneration
        do {
            source = try PermanentBackupService.validateGeneration(
                generationURL,
                in: configuration.internalBackupRootURL,
                fileManager: fileManager
            )
        } catch let error as PermanentBackupError where error == .unsafePath {
            throw PermanentBackupExportError.sourceOutsideConfiguredInternalBackupRoot
        } catch {
            throw PermanentBackupExportError.invalidSourceGeneration
        }
        guard (1...PermanentDatabaseValidation.currentSchemaVersion)
            .contains(source.manifest.schemaVersion) else {
            throw PermanentBackupExportError.schemaMismatchOrUnsupportedSchema
        }
        return source
    }

    private static func validateDestination(
        _ destinationURL: URL,
        configuration: PermanentBackupExportConfiguration,
        fileManager: FileManager
    ) throws {
        guard destinationURL.isFileURL,
              destinationURL.path.hasPrefix("/") else {
            throw PermanentBackupExportError.unsafeOrUnsupportedDestination
        }
        let destination = destinationURL.standardizedFileURL
        guard destination.resolvingSymlinksInPath().path == destination.path else {
            throw PermanentBackupExportError.destinationSymbolicLink
        }
        let type: FileAttributeType?
        do {
            type = try fileManager.attributesOfItem(atPath: destination.path)[.type]
                as? FileAttributeType
        } catch {
            throw PermanentBackupExportError.unsafeOrUnsupportedDestination
        }
        if type == .typeSymbolicLink {
            throw PermanentBackupExportError.destinationSymbolicLink
        }
        guard type == .typeDirectory,
              fileManager.isWritableFile(atPath: destination.path) else {
            throw PermanentBackupExportError.unsafeOrUnsupportedDestination
        }

        let protectedURLs = [
            configuration.internalBackupRootURL,
            configuration.permanentDatabaseURL.deletingLastPathComponent(),
            configuration.permanentDatabaseURL,
            configuration.marketCacheDatabaseURL.deletingLastPathComponent(),
            configuration.marketCacheDatabaseURL
        ] + configuration.additionalProtectedDestinationRoots
        guard protectedURLs.allSatisfy({
            !pathsOverlap(destination, $0.standardizedFileURL)
        }) else {
            throw PermanentBackupExportError.unsafeOrUnsupportedDestination
        }
    }

    private static func validateCopiedArtifact(
        _ generationURL: URL,
        destinationRoot: URL,
        sourceDigest: PermanentBackupFileDigest,
        sourceManifestData: Data,
        committed: Bool,
        fileManager: FileManager
    ) throws -> PermanentBackupGeneration {
        do {
            let generation: PermanentBackupGeneration
            if committed {
                generation = try PermanentBackupService.validateExternalExportArtifact(
                    generationURL,
                    in: destinationRoot,
                    fileManager: fileManager
                )
            } else {
                generation = try PermanentBackupService.validateExternalExportStagingArtifact(
                    generationURL,
                    in: destinationRoot,
                    fileManager: fileManager
                )
            }
            guard (1...PermanentDatabaseValidation.currentSchemaVersion)
                .contains(generation.manifest.schemaVersion) else {
                throw PermanentBackupExportError.schemaMismatchOrUnsupportedSchema
            }
            let databaseURL = generationURL.appendingPathComponent(
                PermanentBackupService.databaseFileName,
                isDirectory: false
            )
            let manifestURL = generationURL.appendingPathComponent(
                PermanentBackupService.manifestFileName,
                isDirectory: false
            )
            guard try mappedDigest(of: databaseURL) == sourceDigest,
                  try readManifestBytes(at: manifestURL) == sourceManifestData else {
                throw PermanentBackupExportError.digestOrByteCountMismatch
            }
            return generation
        } catch let error as PermanentBackupExportError {
            if committed {
                throw PermanentBackupExportError.committedRevalidationFailure
            }
            throw error
        } catch let error as PermanentBackupError {
            if committed {
                throw PermanentBackupExportError.committedRevalidationFailure
            }
            throw mapValidationError(error)
        } catch {
            if committed {
                throw PermanentBackupExportError.committedRevalidationFailure
            }
            throw PermanentBackupExportError.stagingCreationOrCopyFailure
        }
    }

    private static func mapValidationError(
        _ error: PermanentBackupError
    ) -> PermanentBackupExportError {
        switch error {
        case .byteCountMismatch, .hashMismatch:
            .digestOrByteCountMismatch
        case .databaseOpenOrIntegrityFailure:
            .sqliteIntegrityFailure
        case .foreignKeyFailure:
            .foreignKeyFailure
        case .schemaMismatch, .unsupportedFormat:
            .schemaMismatchOrUnsupportedSchema
        case .unexpectedArtifact:
            .unexpectedArtifact
        default:
            .stagingCreationOrCopyFailure
        }
    }

    private static func mappedDigest(of url: URL) throws -> PermanentBackupFileDigest {
        do {
            return try PermanentBackupService.streamingDigest(of: url)
        } catch {
            throw PermanentBackupExportError.digestOrByteCountMismatch
        }
    }

    private static func readManifestBytes(at url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw PermanentBackupExportError.invalidSourceGeneration
        }
    }

    private static func cleanupOwnedStaging(
        _ stagingURL: URL,
        destinationRoot: URL,
        operationID: UUID,
        fileManager: FileManager
    ) {
        guard isDirectChild(stagingURL, of: destinationRoot),
              isOwnedStagingName(stagingURL.lastPathComponent, operationID: operationID),
              let type = try? fileManager.attributesOfItem(atPath: stagingURL.path)[.type]
                as? FileAttributeType,
              type == .typeDirectory else {
            return
        }
        try? fileManager.removeItem(at: stagingURL)
    }

    private static func isOwnedStagingName(_ name: String, operationID: UUID) -> Bool {
        name == ".staging-\(operationID.uuidString.lowercased())"
    }

    private static func isDirectChild(_ child: URL, of parent: URL) -> Bool {
        child.standardizedFileURL.deletingLastPathComponent() == parent.standardizedFileURL
    }

    private static func pathsOverlap(_ lhs: URL, _ rhs: URL) -> Bool {
        isEqualOrDescendant(lhs, of: rhs) || isEqualOrDescendant(rhs, of: lhs)
    }

    private static func isEqualOrDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let ancestorPath = ancestor.standardizedFileURL.path
        return candidatePath == ancestorPath
            || candidatePath.hasPrefix(ancestorPath.hasSuffix("/") ? ancestorPath : ancestorPath + "/")
    }
}
