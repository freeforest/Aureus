import CryptoKit
import Foundation
import GRDB

struct PermanentBackupManifest: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    let backupFormatVersion: Int
    let appVersion: String
    let schemaVersion: Int
    let createdAt: String
    let databaseByteCount: Int64
    let databaseSHA256: String
}

struct PermanentBackupGeneration: Equatable, Sendable {
    let directoryURL: URL
    let manifest: PermanentBackupManifest
}

struct PermanentBackupDiagnostic: Equatable, Sendable {
    let generationIdentity: String
    let error: PermanentBackupError
}

struct PermanentBackupInventory: Equatable, Sendable {
    let validGenerations: [PermanentBackupGeneration]
    let invalidGenerations: [PermanentBackupDiagnostic]
    let ignoredArtifactCount: Int
}

enum PermanentBackupError: Error, Equatable, Sendable {
    case missingManifest
    case malformedManifest
    case unsupportedFormat
    case missingDatabase
    case unexpectedArtifact
    case symbolicLinkRejected
    case byteCountMismatch
    case hashMismatch
    case databaseOpenOrIntegrityFailure
    case foreignKeyFailure
    case schemaMismatch
    case unsafePath
    case consistentBackupFailure
    case invalidAppVersion
    case fileSystemFailure
    case retentionFailure
    case evidenceRequiresCompleteBackup
}

struct PermanentBackupFileDigest: Equatable, Sendable {
    let byteCount: Int64
    let sha256: String
}

enum PermanentBackupService {
    static let databaseFileName = "aureus.sqlite"
    static let manifestFileName = "manifest.json"
    static let retentionLimit = 5

    static func create(
        from source: DatabaseQueue,
        in backupRoot: URL,
        appVersion: String,
        createdAt: UTCInstant,
        generationID: UUID,
        fileManager: FileManager = .default
    ) throws -> PermanentBackupGeneration {
        let normalizedVersion = appVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedVersion.isEmpty,
              normalizedVersion.count <= 64,
              !normalizedVersion.contains("/"),
              !normalizedVersion.contains("\\") else {
            throw PermanentBackupError.invalidAppVersion
        }

        try source.read { db in
            guard try !EvidenceSQL.containsEvidence(db) else { throw PermanentBackupError.evidenceRequiresCompleteBackup }
        }
        try ensureBackupRoot(backupRoot, createIfMissing: true, fileManager: fileManager)
        let createdAtText = canonicalCreatedAt(createdAt)
        let identity = generationID.uuidString.lowercased()
        let finalName = generationName(createdAt: createdAtText, identity: identity)
        let stagingName = ".staging-\(identity)"
        let stagingURL = backupRoot.appendingPathComponent(stagingName, isDirectory: true)
        let finalURL = backupRoot.appendingPathComponent(finalName, isDirectory: true)

        try requireDirectChild(stagingURL, of: backupRoot, acceptedName: isStagingName)
        try requireDirectChild(finalURL, of: backupRoot, acceptedName: isGenerationName)
        guard !itemExists(at: stagingURL, fileManager: fileManager),
              !itemExists(at: finalURL, fileManager: fileManager) else {
            throw PermanentBackupError.fileSystemFailure
        }

        do {
            try fileManager.createDirectory(
                at: stagingURL,
                withIntermediateDirectories: false
            )
        } catch {
            throw PermanentBackupError.fileSystemFailure
        }

        var stagingStillOwned = true
        defer {
            if stagingStillOwned {
                removeOwnedStagingDirectory(
                    stagingURL,
                    from: backupRoot,
                    fileManager: fileManager
                )
            }
        }

        let databaseURL = stagingURL.appendingPathComponent(
            databaseFileName,
            isDirectory: false
        )
        let destination: DatabaseQueue
        do {
            destination = try DatabaseQueueFactory.open(at: databaseURL)
            do {
                try source.backup(to: destination)
                try destination.close()
            } catch {
                try? destination.close()
                throw PermanentBackupError.consistentBackupFailure
            }
        } catch let error as PermanentBackupError {
            throw error
        } catch {
            throw PermanentBackupError.consistentBackupFailure
        }

        let schemaVersion = try readSchemaVersion(from: databaseURL)
        let digest = try streamingDigest(of: databaseURL)
        let manifest = PermanentBackupManifest(
            backupFormatVersion: PermanentBackupManifest.currentFormatVersion,
            appVersion: normalizedVersion,
            schemaVersion: schemaVersion,
            createdAt: createdAtText,
            databaseByteCount: digest.byteCount,
            databaseSHA256: digest.sha256
        )
        try writeManifest(
            manifest,
            to: stagingURL.appendingPathComponent(manifestFileName, isDirectory: false)
        )

        _ = try validateDirectory(
            stagingURL,
            in: backupRoot,
            acceptedName: isStagingName,
            fileManager: fileManager
        )

        do {
            try fileManager.moveItem(at: stagingURL, to: finalURL)
            stagingStillOwned = false
        } catch {
            throw PermanentBackupError.fileSystemFailure
        }

        let committed = try validateGeneration(
            finalURL,
            in: backupRoot,
            fileManager: fileManager
        )
        do {
            _ = try pruneValidGenerations(in: backupRoot, fileManager: fileManager)
        } catch let error as PermanentBackupError {
            throw error
        } catch {
            throw PermanentBackupError.retentionFailure
        }
        return committed
    }

    static func validateGeneration(
        _ generationURL: URL,
        in backupRoot: URL,
        fileManager: FileManager = .default
    ) throws -> PermanentBackupGeneration {
        try ensureBackupRoot(backupRoot, createIfMissing: false, fileManager: fileManager)
        return try validateDirectory(
            generationURL,
            in: backupRoot,
            acceptedName: isGenerationName,
            fileManager: fileManager
        )
    }

    static func validateExternalExportArtifact(
        _ generationURL: URL,
        in destinationDirectoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> PermanentBackupGeneration {
        try requireExistingPlainDirectory(
            destinationDirectoryURL,
            fileManager: fileManager
        )
        return try validateDirectory(
            generationURL,
            in: destinationDirectoryURL,
            acceptedName: isGenerationName,
            fileManager: fileManager
        )
    }

    static func validateExternalExportStagingArtifact(
        _ generationURL: URL,
        in destinationDirectoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> PermanentBackupGeneration {
        try requireExistingPlainDirectory(
            destinationDirectoryURL,
            fileManager: fileManager
        )
        return try validateDirectory(
            generationURL,
            in: destinationDirectoryURL,
            acceptedName: isStagingName,
            fileManager: fileManager
        )
    }

    static func validateStandaloneExternalGeneration(
        _ generationURL: URL,
        excluding protectedURLs: [URL],
        fileManager: FileManager = .default
    ) throws -> PermanentBackupGeneration {
        guard generationURL.isFileURL,
              generationURL.path.hasPrefix("/") else {
            throw PermanentBackupError.unsafePath
        }
        let normalizedGeneration = generationURL.standardizedFileURL
        guard normalizedGeneration.resolvingSymlinksInPath().path
                == normalizedGeneration.path else {
            throw PermanentBackupError.symbolicLinkRejected
        }

        for protectedURL in protectedURLs {
            guard protectedURL.isFileURL,
                  protectedURL.path.hasPrefix("/") else {
                throw PermanentBackupError.unsafePath
            }
            let normalizedProtectedURL = protectedURL.standardizedFileURL
            guard normalizedProtectedURL.resolvingSymlinksInPath().path
                    == normalizedProtectedURL.path,
                  !pathsOverlap(normalizedGeneration, normalizedProtectedURL) else {
                throw PermanentBackupError.unsafePath
            }
        }

        let generation = try validateGenerationContents(
            normalizedGeneration,
            acceptedName: isGenerationName,
            fileManager: fileManager
        )
        let normalizedAppVersion = generation.manifest.appVersion
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard generation.manifest.appVersion == normalizedAppVersion,
              !normalizedAppVersion.isEmpty,
              normalizedAppVersion.count <= 64,
              !normalizedAppVersion.contains("/"),
              !normalizedAppVersion.contains("\\"),
              (1...PermanentDatabaseValidation.currentSchemaVersion)
                .contains(generation.manifest.schemaVersion) else {
            throw PermanentBackupError.schemaMismatch
        }
        return generation
    }

    static func externalExportGenerationName(
        createdAt: String,
        operationID: UUID
    ) throws -> String {
        guard canonicalCreatedAt(createdAt) != nil else {
            throw PermanentBackupError.malformedManifest
        }
        return generationName(
            createdAt: createdAt,
            identity: operationID.uuidString.lowercased()
        )
    }

    static func inventory(
        in backupRoot: URL,
        fileManager: FileManager = .default
    ) throws -> PermanentBackupInventory {
        guard itemExists(at: backupRoot, fileManager: fileManager) else {
            return PermanentBackupInventory(
                validGenerations: [],
                invalidGenerations: [],
                ignoredArtifactCount: 0
            )
        }
        try ensureBackupRoot(backupRoot, createIfMissing: false, fileManager: fileManager)

        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: backupRoot,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            throw PermanentBackupError.fileSystemFailure
        }

        var valid: [PermanentBackupGeneration] = []
        var invalid: [PermanentBackupDiagnostic] = []
        var ignored = 0
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = entry.lastPathComponent
            guard isGenerationName(name) else {
                ignored += 1
                continue
            }
            do {
                valid.append(try validateGeneration(entry, in: backupRoot, fileManager: fileManager))
            } catch let error as PermanentBackupError {
                invalid.append(
                    PermanentBackupDiagnostic(generationIdentity: name, error: error)
                )
            } catch {
                invalid.append(
                    PermanentBackupDiagnostic(
                        generationIdentity: name,
                        error: .fileSystemFailure
                    )
                )
            }
        }
        valid.sort(by: generationPrecedes)
        return PermanentBackupInventory(
            validGenerations: valid,
            invalidGenerations: invalid,
            ignoredArtifactCount: ignored
        )
    }

    static func pruneValidGenerations(
        in backupRoot: URL,
        fileManager: FileManager = .default
    ) throws -> PermanentBackupInventory {
        let existing = try inventory(in: backupRoot, fileManager: fileManager)
        let excess = existing.validGenerations.count - retentionLimit
        guard excess > 0 else { return existing }

        for generation in existing.validGenerations.prefix(excess) {
            let revalidated = try validateGeneration(
                generation.directoryURL,
                in: backupRoot,
                fileManager: fileManager
            )
            guard revalidated == generation,
                  isGenerationName(generation.directoryURL.lastPathComponent),
                  try itemType(at: generation.directoryURL, fileManager: fileManager) == .typeDirectory else {
                throw PermanentBackupError.retentionFailure
            }
            do {
                try fileManager.removeItem(at: generation.directoryURL)
            } catch {
                throw PermanentBackupError.retentionFailure
            }
        }
        return try inventory(in: backupRoot, fileManager: fileManager)
    }

    static func streamingDigest(of url: URL) throws -> PermanentBackupFileDigest {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw PermanentBackupError.databaseOpenOrIntegrityFailure
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        var byteCount: Int64 = 0
        do {
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                let addition = byteCount.addingReportingOverflow(Int64(data.count))
                guard !addition.overflow else {
                    throw PermanentBackupError.databaseOpenOrIntegrityFailure
                }
                byteCount = addition.partialValue
                hasher.update(data: data)
            }
        } catch let error as PermanentBackupError {
            throw error
        } catch {
            throw PermanentBackupError.databaseOpenOrIntegrityFailure
        }
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return PermanentBackupFileDigest(byteCount: byteCount, sha256: hash)
    }

    private static func validateDirectory(
        _ generationURL: URL,
        in backupRoot: URL,
        acceptedName: (String) -> Bool,
        fileManager: FileManager
    ) throws -> PermanentBackupGeneration {
        try requireDirectChild(generationURL, of: backupRoot, acceptedName: acceptedName)
        return try validateGenerationContents(
            generationURL,
            acceptedName: acceptedName,
            fileManager: fileManager
        )
    }

    private static func validateGenerationContents(
        _ generationURL: URL,
        acceptedName: (String) -> Bool,
        fileManager: FileManager
    ) throws -> PermanentBackupGeneration {
        guard acceptedName(generationURL.lastPathComponent) else {
            throw PermanentBackupError.unsafePath
        }
        let generationType = try itemType(at: generationURL, fileManager: fileManager)
        if generationType == .typeSymbolicLink {
            throw PermanentBackupError.symbolicLinkRejected
        }
        guard generationType == .typeDirectory else {
            throw PermanentBackupError.unsafePath
        }

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: generationURL,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            throw PermanentBackupError.fileSystemFailure
        }
        let names = Set(contents.map(\.lastPathComponent))
        guard names.contains(manifestFileName) else {
            throw PermanentBackupError.missingManifest
        }
        guard names.contains(databaseFileName) else {
            throw PermanentBackupError.missingDatabase
        }
        guard names == Set([databaseFileName, manifestFileName]) else {
            throw PermanentBackupError.unexpectedArtifact
        }

        let databaseURL = generationURL.appendingPathComponent(
            databaseFileName,
            isDirectory: false
        )
        let manifestURL = generationURL.appendingPathComponent(
            manifestFileName,
            isDirectory: false
        )
        try requireRegularFile(databaseURL, fileManager: fileManager)
        try requireRegularFile(manifestURL, fileManager: fileManager)

        let manifest = try readManifest(from: manifestURL)
        guard manifest.backupFormatVersion == PermanentBackupManifest.currentFormatVersion else {
            throw PermanentBackupError.unsupportedFormat
        }
        guard manifest.schemaVersion > 0,
              manifest.databaseByteCount > 0,
              isLowercaseSHA256(manifest.databaseSHA256),
              canonicalCreatedAt(manifest.createdAt) != nil,
              !manifest.appVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.appVersion.count <= 64 else {
            throw PermanentBackupError.malformedManifest
        }

        let digest = try streamingDigest(of: databaseURL)
        guard digest.byteCount == manifest.databaseByteCount else {
            throw PermanentBackupError.byteCountMismatch
        }
        guard digest.sha256 == manifest.databaseSHA256 else {
            throw PermanentBackupError.hashMismatch
        }
        try validateSQLite(databaseURL, expectedSchemaVersion: manifest.schemaVersion)
        return PermanentBackupGeneration(directoryURL: generationURL, manifest: manifest)
    }

    private static func readManifest(from url: URL) throws -> PermanentBackupManifest {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw PermanentBackupError.malformedManifest
        }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys) == Set([
                    "backupFormatVersion", "appVersion", "schemaVersion", "createdAt",
                    "databaseByteCount", "databaseSHA256"
                  ]) else {
                throw PermanentBackupError.malformedManifest
            }
            return try JSONDecoder().decode(PermanentBackupManifest.self, from: data)
        } catch let error as PermanentBackupError {
            throw error
        } catch {
            throw PermanentBackupError.malformedManifest
        }
    }

    private static func writeManifest(_ manifest: PermanentBackupManifest, to url: URL) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            var data = try encoder.encode(manifest)
            data.append(0x0A)
            try data.write(to: url, options: [.withoutOverwriting])
        } catch {
            throw PermanentBackupError.fileSystemFailure
        }
    }

    private static func readSchemaVersion(from databaseURL: URL) throws -> Int {
        do {
            let reader = try readOnlyQueue(at: databaseURL)
            defer { try? reader.close() }
            guard let version = try reader.read({ db in
                try Int.fetchOne(
                    db,
                    sql: "SELECT version FROM schema_metadata WHERE store_kind = 'permanent'"
                )
            }), version > 0 else {
                throw PermanentBackupError.databaseOpenOrIntegrityFailure
            }
            return version
        } catch let error as PermanentBackupError {
            throw error
        } catch {
            throw PermanentBackupError.databaseOpenOrIntegrityFailure
        }
    }

    private static func validateSQLite(
        _ databaseURL: URL,
        expectedSchemaVersion: Int
    ) throws {
        do {
            let reader = try readOnlyQueue(at: databaseURL)
            defer { try? reader.close() }
            try reader.read { db in
                guard try !EvidenceSQL.containsEvidence(db) else { throw PermanentBackupError.evidenceRequiresCompleteBackup }
            }
            _ = try PermanentDatabaseValidation.inspectFile(
                databaseURL,
                expectedSchemaVersion: expectedSchemaVersion,
                requireCurrentApplicationSchema: false
            )
        } catch PermanentDatabaseValidationFailure.foreignKeys {
            throw PermanentBackupError.foreignKeyFailure
        } catch PermanentDatabaseValidationFailure.schema {
            throw PermanentBackupError.schemaMismatch
        } catch let error as PermanentBackupError {
            throw error
        } catch {
            throw PermanentBackupError.databaseOpenOrIntegrityFailure
        }
    }

    private static func readOnlyQueue(at databaseURL: URL) throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.readonly = true
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA query_only = ON")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return try DatabaseQueue(path: databaseURL.path, configuration: configuration)
    }

    private static func ensureBackupRoot(
        _ backupRoot: URL,
        createIfMissing: Bool,
        fileManager: FileManager
    ) throws {
        guard backupRoot.isFileURL,
              backupRoot.path.hasPrefix("/"),
              backupRoot.lastPathComponent == "Backups" else {
            throw PermanentBackupError.unsafePath
        }
        if itemExists(at: backupRoot, fileManager: fileManager) {
            let type = try itemType(at: backupRoot, fileManager: fileManager)
            if type == .typeSymbolicLink {
                throw PermanentBackupError.symbolicLinkRejected
            }
            guard type == .typeDirectory else {
                throw PermanentBackupError.unsafePath
            }
        } else if createIfMissing {
            do {
                try fileManager.createDirectory(
                    at: backupRoot,
                    withIntermediateDirectories: true
                )
            } catch {
                throw PermanentBackupError.fileSystemFailure
            }
        } else {
            throw PermanentBackupError.unsafePath
        }
    }

    private static func requireExistingPlainDirectory(
        _ directoryURL: URL,
        fileManager: FileManager
    ) throws {
        guard directoryURL.isFileURL,
              directoryURL.path.hasPrefix("/"),
              directoryURL.standardizedFileURL.resolvingSymlinksInPath().path
                == directoryURL.standardizedFileURL.path else {
            throw PermanentBackupError.unsafePath
        }
        let type = try itemType(at: directoryURL, fileManager: fileManager)
        if type == .typeSymbolicLink {
            throw PermanentBackupError.symbolicLinkRejected
        }
        guard type == .typeDirectory else {
            throw PermanentBackupError.unsafePath
        }
    }

    private static func requireDirectChild(
        _ candidate: URL,
        of backupRoot: URL,
        acceptedName: (String) -> Bool
    ) throws {
        let normalizedRootPath = backupRoot.standardizedFileURL
            .resolvingSymlinksInPath().path
        let normalizedCandidate = candidate.standardizedFileURL
        let parentPath = normalizedCandidate.deletingLastPathComponent()
            .resolvingSymlinksInPath().path
        let candidateName = normalizedCandidate.lastPathComponent
        guard parentPath == normalizedRootPath,
              acceptedName(candidateName) else {
            throw PermanentBackupError.unsafePath
        }
    }

    private static func requireRegularFile(
        _ url: URL,
        fileManager: FileManager
    ) throws {
        let type = try itemType(at: url, fileManager: fileManager)
        if type == .typeSymbolicLink {
            throw PermanentBackupError.symbolicLinkRejected
        }
        guard type == .typeRegular else {
            throw PermanentBackupError.unexpectedArtifact
        }
    }

    private static func itemType(
        at url: URL,
        fileManager: FileManager
    ) throws -> FileAttributeType? {
        do {
            return try fileManager.attributesOfItem(atPath: url.path)[.type]
                as? FileAttributeType
        } catch {
            throw PermanentBackupError.fileSystemFailure
        }
    }

    private static func itemExists(at url: URL, fileManager: FileManager) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
    }

    private static func removeOwnedStagingDirectory(
        _ stagingURL: URL,
        from backupRoot: URL,
        fileManager: FileManager
    ) {
        guard (try? requireDirectChild(
            stagingURL,
            of: backupRoot,
            acceptedName: isStagingName
        )) != nil,
        (try? itemType(at: stagingURL, fileManager: fileManager)) == .typeDirectory else {
            return
        }
        try? fileManager.removeItem(at: stagingURL)
    }

    private static func generationPrecedes(
        _ lhs: PermanentBackupGeneration,
        _ rhs: PermanentBackupGeneration
    ) -> Bool {
        if lhs.manifest.createdAt != rhs.manifest.createdAt {
            return lhs.manifest.createdAt < rhs.manifest.createdAt
        }
        return lhs.directoryURL.lastPathComponent < rhs.directoryURL.lastPathComponent
    }

    private static func canonicalCreatedAt(_ instant: UTCInstant) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let seconds = TimeInterval(instant.millisecondsSince1970) / 1_000
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    private static func canonicalCreatedAt(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
            return nil
        }
        return date
    }

    private static func generationName(createdAt: String, identity: String) -> String {
        let sortableTimestamp = createdAt
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ".", with: "")
        return "backup-\(sortableTimestamp)-\(identity)"
    }

    private static func isGenerationName(_ name: String) -> Bool {
        name.range(
            of: #"^backup-[0-9]{8}T[0-9]{9}Z-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isStagingName(_ name: String) -> Bool {
        name.range(
            of: #"^\.staging-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
    }

    private static func pathsOverlap(_ lhs: URL, _ rhs: URL) -> Bool {
        isEqualOrDescendant(lhs, of: rhs) || isEqualOrDescendant(rhs, of: lhs)
    }

    private static func isEqualOrDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let ancestorPath = ancestor.standardizedFileURL.path
        return candidatePath == ancestorPath
            || candidatePath.hasPrefix(
                ancestorPath.hasSuffix("/") ? ancestorPath : ancestorPath + "/"
            )
    }
}

extension WealthStore {
    func createPermanentBackup(
        in backupRoot: URL,
        appVersion: String,
        createdAt: UTCInstant,
        generationID: UUID = UUID()
    ) throws -> PermanentBackupGeneration {
        try requireFormatOneEligible()
        return try PermanentBackupService.create(
            from: queue,
            in: backupRoot,
            appVersion: appVersion,
            createdAt: createdAt,
            generationID: generationID
        )
    }

    func validatePermanentBackup(
        _ generationURL: URL,
        in backupRoot: URL
    ) throws -> PermanentBackupGeneration {
        try PermanentBackupService.validateGeneration(generationURL, in: backupRoot)
    }

    func permanentBackupInventory(in backupRoot: URL) throws -> PermanentBackupInventory {
        try PermanentBackupService.inventory(in: backupRoot)
    }

    func prunePermanentBackups(in backupRoot: URL) throws -> PermanentBackupInventory {
        try PermanentBackupService.pruneValidGenerations(in: backupRoot)
    }
}
