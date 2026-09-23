import CryptoKit
import Foundation
import GRDB
import Testing
@testable import Aureus

@Suite("Permanent external Backup export foundation")
struct PermanentBackupExportTests {
    @Test("Valid internal generation exports as exactly two files")
    func validExport() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)

        let result = try exportGeneration(context, source: source, operation: 1)
        let exported = exportedURL(context, result: result)
        #expect(result.schemaVersion == 8)
        #expect(result.databaseByteCount == source.manifest.databaseByteCount)
        #expect(result.operationCategory == .internalGenerationExternalExport)
        #expect(try artifactNames(at: exported) == ["aureus.sqlite", "manifest.json"])
    }

    @Test("Exported database and manifest are byte-identical to the source")
    func byteIdentity() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        let result = try exportGeneration(context, source: source, operation: 2)
        let exported = exportedURL(context, result: result)

        #expect(try fileData(databaseURL(source)) == fileData(databaseURL(exported)))
        #expect(try fileData(manifestURL(source)) == fileData(manifestURL(exported)))
    }

    @Test("Exported digest byte count and manifest remain authoritative")
    func digestAndManifest() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        let result = try exportGeneration(context, source: source, operation: 3)
        let exported = exportedURL(context, result: result)
        let validated = try PermanentBackupService.validateExternalExportArtifact(
            exported,
            in: context.destination
        )
        let digest = try PermanentBackupService.streamingDigest(of: databaseURL(exported))

        #expect(validated.manifest == source.manifest)
        #expect(digest.byteCount == validated.manifest.databaseByteCount)
        #expect(digest.sha256 == validated.manifest.databaseSHA256)
    }

    @Test("Exported SQLite passes integrity foreign-key and schema validation")
    func sqliteValidation() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        let result = try exportGeneration(context, source: source, operation: 4)
        let inspection = try PermanentDatabaseValidation.inspectFile(
            databaseURL(exportedURL(context, result: result)),
            expectedSchemaVersion: source.manifest.schemaVersion,
            requireCurrentApplicationSchema: true
        )

        #expect(inspection.schemaVersion == 8)
        #expect(inspection.migrationIdentifiers == PermanentDatabaseValidation.migrationIdentifiers)
    }

    @Test("Source generation and manifest are unchanged by export")
    func sourceUnchanged() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        let databaseBefore = try PermanentBackupService.streamingDigest(of: databaseURL(source))
        let manifestBefore = try fileData(manifestURL(source))

        _ = try exportGeneration(context, source: source, operation: 5)

        #expect(try PermanentBackupService.streamingDigest(of: databaseURL(source)) == databaseBefore)
        #expect(try fileData(manifestURL(source)) == manifestBefore)
    }

    @Test("Later source mutation cannot alter an exported generation")
    func sourceMutationAfterExport() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        let result = try exportGeneration(context, source: source, operation: 6)
        let exported = exportedURL(context, result: result)
        let databaseBefore = try fileData(databaseURL(exported))
        let manifestBefore = try fileData(manifestURL(exported))

        try Data("synthetic-later-source-artifact".utf8).write(
            to: source.directoryURL.appendingPathComponent("later-source-artifact")
        )

        #expect(try fileData(databaseURL(exported)) == databaseBefore)
        #expect(try fileData(manifestURL(exported)) == manifestBefore)
        _ = try PermanentBackupService.validateExternalExportArtifact(
            exported,
            in: context.destination
        )
    }

    @Test("Tampered source is rejected before destination write")
    func tamperedSource() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        let handle = try FileHandle(forWritingTo: databaseURL(source))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0xA5]))
        try handle.close()

        #expect(exportError(context, source: source, operation: 7) == .invalidSourceGeneration)
        #expect(try artifactNames(at: context.destination).isEmpty)
    }

    @Test("Malformed and missing manifests are rejected before destination write", arguments: [0, 1])
    func invalidManifest(variant: Int) async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        if variant == 0 {
            try Data("{malformed".utf8).write(to: manifestURL(source))
        } else {
            try FileManager.default.removeItem(at: manifestURL(source))
        }

        #expect(exportError(context, source: source, operation: 10 + variant) == .invalidSourceGeneration)
        #expect(try artifactNames(at: context.destination).isEmpty)
    }

    @Test("Unsupported Backup format is rejected")
    func unsupportedFormat() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        try rewriteExportManifest(source) { manifest in
            PermanentBackupManifest(
                backupFormatVersion: 2,
                appVersion: manifest.appVersion,
                schemaVersion: manifest.schemaVersion,
                createdAt: manifest.createdAt,
                databaseByteCount: manifest.databaseByteCount,
                databaseSHA256: manifest.databaseSHA256
            )
        }

        #expect(exportError(context, source: source, operation: 12) == .invalidSourceGeneration)
        #expect(try artifactNames(at: context.destination).isEmpty)
    }

    @Test("Source generation symbolic links are rejected")
    func sourceSymbolicLink() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        let linkName = try PermanentBackupService.externalExportGenerationName(
            createdAt: source.manifest.createdAt,
            operationID: exportUUID(13)
        )
        let link = context.paths.internalBackupDirectoryURL.appendingPathComponent(linkName)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source.directoryURL)

        #expect(
            exportError(context, sourceURL: link, operation: 13)
                == .invalidSourceGeneration
        )
        #expect(try artifactNames(at: context.destination).isEmpty)
    }

    @Test("Source outside configured internal Backup root is rejected")
    func outsideSource() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        let result = try exportGeneration(context, source: source, operation: 14)
        let external = exportedURL(context, result: result)
        let secondDestination = context.root.appendingPathComponent("SecondExternal")
        try FileManager.default.createDirectory(at: secondDestination, withIntermediateDirectories: false)

        #expect(
            exportError(
                context,
                sourceURL: external,
                destination: secondDestination,
                operation: 15
            ) == .sourceOutsideConfiguredInternalBackupRoot
        )
        #expect(try artifactNames(at: secondDestination).isEmpty)
    }

    @Test("Internal Restore still rejects an external generation")
    func internalRestoreRejectsExternal() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        let result = try exportGeneration(context, source: source, operation: 16)

        do {
            _ = try await context.store.restorePermanentBackup(
                exportedURL(context, result: result),
                in: context.paths.internalBackupDirectoryURL,
                appVersion: exportTestAppVersion,
                createdAt: exportTestInstant,
                operationID: exportUUID(160),
                safetyGenerationID: exportUUID(161)
            )
            Issue.record("Internal Restore must reject an external generation")
        } catch let error as PermanentRestoreError {
            #expect(error == .candidateValidationFailed)
        }
    }

    @Test("Non-file destination URL is rejected")
    func nonFileDestination() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        let url = try #require(URL(string: "https://example.invalid/export"))

        #expect(
            exportError(context, source: source, destination: url, operation: 17)
                == .unsafeOrUnsupportedDestination
        )
    }

    @Test("Missing and non-directory destinations are rejected", arguments: [0, 1])
    func invalidDestinationType(variant: Int) async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        let destination = context.root.appendingPathComponent("InvalidDestination-\(variant)")
        if variant == 1 {
            try Data("synthetic-not-directory".utf8).write(to: destination)
        }

        #expect(
            exportError(context, source: source, destination: destination, operation: 18 + variant)
                == .unsafeOrUnsupportedDestination
        )
    }

    @Test("Destination symbolic link and escape are rejected")
    func destinationSymbolicLink() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        let real = context.root.appendingPathComponent("ExternalReal")
        let link = context.root.appendingPathComponent("ExternalLink")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        #expect(
            exportError(context, source: source, destination: link, operation: 20)
                == .destinationSymbolicLink
        )
        #expect(try artifactNames(at: real).isEmpty)
    }

    @Test("Repository and protected storage destinations are rejected")
    func protectedDestinations() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        let permanentParent = context.paths.permanentDatabaseURL.deletingLastPathComponent()
        let cacheParent = context.paths.marketCacheDatabaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: cacheParent, withIntermediateDirectories: true)

        #expect(
            exportError(context, source: source, destination: context.repositoryRoot, operation: 21)
                == .unsafeOrUnsupportedDestination
        )
        #expect(
            exportError(context, source: source, destination: permanentParent, operation: 22)
                == .unsafeOrUnsupportedDestination
        )
        #expect(
            exportError(context, source: source, destination: cacheParent, operation: 23)
                == .unsafeOrUnsupportedDestination
        )
    }

    @Test("Destination collision never overwrites an existing artifact")
    func destinationCollision() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        let operation = 24
        let name = try PermanentBackupService.externalExportGenerationName(
            createdAt: source.manifest.createdAt,
            operationID: exportUUID(operation)
        )
        let collision = context.destination.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: collision, withIntermediateDirectories: false)
        let sentinel = collision.appendingPathComponent("synthetic-existing")
        try Data("preserve".utf8).write(to: sentinel)

        #expect(exportError(context, source: source, operation: operation) == .destinationCollision)
        #expect(try String(decoding: fileData(sentinel), as: UTF8.self) == "preserve")
    }

    @Test("Unexpected destination siblings are retained")
    func unrelatedSiblingPreserved() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        let sibling = context.destination.appendingPathComponent("owner-unrelated")
        try Data("preserve".utf8).write(to: sibling)

        _ = try exportGeneration(context, source: source, operation: 25)

        #expect(try String(decoding: fileData(sibling), as: UTF8.self) == "preserve")
    }

    @Test("Copy failure removes only operation-owned staging")
    func copyFailureCleanup() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        let sibling = context.destination.appendingPathComponent("owner-unrelated")
        try Data("preserve".utf8).write(to: sibling)

        #expect(
            exportError(
                context,
                source: source,
                operation: 26,
                fileOperations: ExportCopyFailure()
            ) == .stagingCreationOrCopyFailure
        )
        #expect(try artifactNames(at: context.destination) == ["owner-unrelated"])
    }

    @Test("Staged digest mismatch is rejected and staging is cleaned")
    func stagingValidationFailure() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)

        #expect(
            exportError(
                context,
                source: source,
                operation: 27,
                fileOperations: ExportCorruptingCopy()
            ) == .digestOrByteCountMismatch
        )
        #expect(try artifactNames(at: context.destination).isEmpty)
    }

    @Test("Atomic commit failure does not create a final generation")
    func atomicCommitFailure() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)

        #expect(
            exportError(
                context,
                source: source,
                operation: 28,
                fileOperations: ExportMoveFailure()
            ) == .atomicCommitFailure
        )
        #expect(try artifactNames(at: context.destination).isEmpty)
    }

    @Test("Committed generation is revalidated before success")
    func committedRevalidationFailure() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)

        #expect(
            exportError(
                context,
                source: source,
                operation: 29,
                fileOperations: ExportCorruptingMove()
            ) == .committedRevalidationFailure
        )
    }

    @Test("External export performs no retention pruning")
    func noExternalRetention() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)

        for operation in 30..<37 {
            _ = try exportGeneration(context, source: source, operation: operation)
        }

        #expect(try artifactNames(at: context.destination).count == 7)
    }

    @Test("Internal five-generation retention is unchanged by export")
    func internalRetentionUnchanged() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        var latest: PermanentBackupGeneration?
        for index in 0..<7 {
            latest = try await context.store.createPermanentBackup(
                in: context.paths.internalBackupDirectoryURL,
                appVersion: exportTestAppVersion,
                createdAt: UTCInstant(
                    millisecondsSince1970: exportTestInstant.millisecondsSince1970 + Int64(index)
                ),
                generationID: exportUUID(100 + index)
            )
        }
        let before = try PermanentBackupService.inventory(
            in: context.paths.internalBackupDirectoryURL
        )
        _ = try exportGeneration(context, source: try #require(latest), operation: 37)
        let after = try PermanentBackupService.inventory(
            in: context.paths.internalBackupDirectoryURL
        )

        #expect(before.validGenerations.count == 5)
        #expect(after == before)
    }

    @Test("Market Cache key-like and Repository sentinels remain excluded")
    func isolation() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        try FileManager.default.createDirectory(
            at: context.paths.marketCacheDatabaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let cache = context.paths.marketCacheDatabaseURL
        let keyLike = context.root.appendingPathComponent("synthetic-key-like")
        let repository = context.repositoryRoot.appendingPathComponent("synthetic-source")
        try Data("cache-only".utf8).write(to: cache)
        try Data("not-a-credential".utf8).write(to: keyLike)
        try Data("repository-only".utf8).write(to: repository)
        let before = try [cache, keyLike, repository].map(fileData)

        let result = try exportGeneration(context, source: source, operation: 38)
        let exportedNames = try artifactNames(at: exportedURL(context, result: result))

        #expect(try [cache, keyLike, repository].map(fileData) == before)
        #expect(exportedNames == ["aureus.sqlite", "manifest.json"])
    }

    @Test("Typed result and errors do not disclose paths or business values")
    func sanitizedResultAndErrors() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        let result = try exportGeneration(context, source: source, operation: 39)
        let resultText = String(reflecting: result)
        let forbidden = [context.root.path, "Synthetic Export Sentinel", "123456.78"]
        #expect(forbidden.allSatisfy { !resultText.contains($0) })

        for error in allExportErrors {
            let text = error.errorDescription ?? ""
            #expect(forbidden.allSatisfy { !text.contains($0) })
        }
    }

    @Test("Repeated exports with new identities are deterministic and independent")
    func repeatedExports() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        let first = try exportGeneration(context, source: source, operation: 40)
        let second = try exportGeneration(context, source: source, operation: 41)

        #expect(first.exportedGenerationIdentity != second.exportedGenerationIdentity)
        #expect(first.schemaVersion == second.schemaVersion)
        #expect(first.databaseByteCount == second.databaseByteCount)
        #expect(try fileData(databaseURL(exportedURL(context, result: first)))
            == fileData(databaseURL(exportedURL(context, result: second))))
    }

    @Test("Export persists no destination history bookmark or metadata")
    func noDestinationPersistence() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let source = try await exportSource(context)
        let result = try exportGeneration(context, source: source, operation: 42)

        #expect(try artifactNames(at: context.destination) == [result.exportedGenerationIdentity])
        #expect(try artifactNames(at: exportedURL(context, result: result))
            == ["aureus.sqlite", "manifest.json"])
    }

    @Test("Release workload exports and validates ten thousand synthetic rows")
    func stage11ExternalBackupExportPerformance() async throws {
        let context = try exportTestContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try seedExportPerformanceRows(at: context.paths.permanentDatabaseURL, count: 10_000)
        try await context.store.checkpoint()
        let sourceInputBefore = try exportPerformanceSentinel(
            at: context.paths.permanentDatabaseURL
        )
        let source = try await context.store.createPermanentBackup(
            in: context.paths.internalBackupDirectoryURL,
            appVersion: exportTestAppVersion,
            createdAt: exportTestInstant,
            generationID: exportUUID(900)
        )
        let sourceDigestBefore = try PermanentBackupService.streamingDigest(of: databaseURL(source))
        let clock = ContinuousClock()
        let start = clock.now
        let result = try exportGeneration(context, source: source, operation: 901)
        let exported = exportedURL(context, result: result)
        _ = try PermanentBackupService.validateExternalExportArtifact(
            exported,
            in: context.destination
        )
        let elapsed = start.duration(to: clock.now)
        let sourceInputAfter = try exportPerformanceSentinel(
            at: context.paths.permanentDatabaseURL
        )
        let components = elapsed.components
        let milliseconds = components.seconds * 1_000
            + components.attoseconds / 1_000_000_000_000_000

        #expect(sourceInputAfter == sourceInputBefore)
        #expect(sourceInputAfter.count == 10_000)
        #expect(try PermanentBackupService.streamingDigest(of: databaseURL(source))
            == sourceDigestBefore)
        #expect(try artifactNames(at: exported).count == 2)
        #expect(elapsed < .seconds(10))
        print(
            "STAGE11_EXTERNAL_BACKUP_EXPORT_PERF rows=10000 "
                + "export_validate_ms=\(milliseconds) exported_files=2 "
                + "provider_requests=0 cache_reads=0 credential_reads=0"
        )
    }
}

private let exportTestAppVersion = "0.1-export-test"
private let exportTestInstant = UTCInstant(millisecondsSince1970: 1_788_199_200_000)

private struct ExportTestContext {
    let root: URL
    let paths: RuntimePaths
    let repositoryRoot: URL
    let destination: URL
    let store: WealthStore

    var configuration: PermanentBackupExportConfiguration {
        PermanentBackupExportConfiguration(
            internalBackupRootURL: paths.internalBackupDirectoryURL,
            permanentDatabaseURL: paths.permanentDatabaseURL,
            marketCacheDatabaseURL: paths.marketCacheDatabaseURL,
            additionalProtectedDestinationRoots: [repositoryRoot]
        )
    }
}

private func exportTestContext() throws -> ExportTestContext {
    let base: URL
    if let injected = ProcessInfo.processInfo.environment["AUREUS_BACKUP_EXPORT_TEST_ROOT"],
       !injected.isEmpty {
        base = URL(fileURLWithPath: injected, isDirectory: true)
    } else {
        base = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("AureusTests/PermanentBackupExport", isDirectory: true)
    }
    let root = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let paths = RuntimePaths.temporary(
        root: root.appendingPathComponent("Runtime", isDirectory: true)
    )
    let repository = root.appendingPathComponent("SyntheticRepository", isDirectory: true)
    let destination = root.appendingPathComponent("ExternalDestination", isDirectory: true)
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    return ExportTestContext(
        root: root,
        paths: paths,
        repositoryRoot: repository,
        destination: destination,
        store: try WealthStore(databaseURL: paths.permanentDatabaseURL)
    )
}

private func exportSource(_ context: ExportTestContext) async throws -> PermanentBackupGeneration {
    try await context.store.insertIsolationSentinel(
        id: "export-source-sentinel",
        name: "Synthetic Export Sentinel"
    )
    return try await context.store.createPermanentBackup(
        in: context.paths.internalBackupDirectoryURL,
        appVersion: exportTestAppVersion,
        createdAt: exportTestInstant,
        generationID: exportUUID(0)
    )
}

private func exportGeneration(
    _ context: ExportTestContext,
    source: PermanentBackupGeneration,
    destination: URL? = nil,
    operation: Int,
    fileOperations: any PermanentBackupExportFileOperations
        = LocalPermanentBackupExportFileOperations()
) throws -> PermanentBackupExportResult {
    try PermanentBackupExportService.export(
        internalGenerationURL: source.directoryURL,
        to: destination ?? context.destination,
        configuration: context.configuration,
        operationID: exportUUID(operation),
        fileOperations: fileOperations
    )
}

private func exportError(
    _ context: ExportTestContext,
    source: PermanentBackupGeneration,
    destination: URL? = nil,
    operation: Int,
    fileOperations: any PermanentBackupExportFileOperations
        = LocalPermanentBackupExportFileOperations()
) -> PermanentBackupExportError? {
    exportError(
        context,
        sourceURL: source.directoryURL,
        destination: destination,
        operation: operation,
        fileOperations: fileOperations
    )
}

private func exportError(
    _ context: ExportTestContext,
    sourceURL: URL,
    destination: URL? = nil,
    operation: Int,
    fileOperations: any PermanentBackupExportFileOperations
        = LocalPermanentBackupExportFileOperations()
) -> PermanentBackupExportError? {
    do {
        _ = try PermanentBackupExportService.export(
            internalGenerationURL: sourceURL,
            to: destination ?? context.destination,
            configuration: context.configuration,
            operationID: exportUUID(operation),
            fileOperations: fileOperations
        )
        return nil
    } catch let error as PermanentBackupExportError {
        return error
    } catch {
        return .invalidSourceGeneration
    }
}

private func exportedURL(
    _ context: ExportTestContext,
    result: PermanentBackupExportResult
) -> URL {
    context.destination.appendingPathComponent(result.exportedGenerationIdentity, isDirectory: true)
}

private func databaseURL(_ generation: PermanentBackupGeneration) -> URL {
    databaseURL(generation.directoryURL)
}

private func databaseURL(_ generationURL: URL) -> URL {
    generationURL.appendingPathComponent("aureus.sqlite", isDirectory: false)
}

private func manifestURL(_ generation: PermanentBackupGeneration) -> URL {
    manifestURL(generation.directoryURL)
}

private func manifestURL(_ generationURL: URL) -> URL {
    generationURL.appendingPathComponent("manifest.json", isDirectory: false)
}

private func artifactNames(at directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
}

private func fileData(_ url: URL) throws -> Data {
    try Data(contentsOf: url, options: [.mappedIfSafe])
}

private func rewriteExportManifest(
    _ generation: PermanentBackupGeneration,
    transform: (PermanentBackupManifest) -> PermanentBackupManifest
) throws {
    let url = manifestURL(generation)
    let manifest = try JSONDecoder().decode(
        PermanentBackupManifest.self,
        from: fileData(url)
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(transform(manifest))
    data.append(0x0A)
    try data.write(to: url, options: .atomic)
}

private func exportUUID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "e0000000-0000-4000-8000-%012d", value))!
}

private struct ExportCopyFailure: PermanentBackupExportFileOperations {
    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        throw SyntheticExportFailure.intentional
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }
}

private struct ExportCorruptingCopy: PermanentBackupExportFileOperations {
    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        if destinationURL.lastPathComponent == "manifest.json" {
            let database = destinationURL.deletingLastPathComponent()
                .appendingPathComponent("aureus.sqlite")
            let handle = try FileHandle(forWritingTo: database)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data([0xA5]))
            try handle.close()
        }
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }
}

private struct ExportMoveFailure: PermanentBackupExportFileOperations {
    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        throw SyntheticExportFailure.intentional
    }
}

private struct ExportCorruptingMove: PermanentBackupExportFileOperations {
    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        let database = destinationURL.appendingPathComponent("aureus.sqlite")
        let handle = try FileHandle(forWritingTo: database)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0xA5]))
        try handle.close()
    }
}

private enum SyntheticExportFailure: Error {
    case intentional
}

private let allExportErrors: [PermanentBackupExportError] = [
    .invalidSourceGeneration,
    .sourceOutsideConfiguredInternalBackupRoot,
    .unsafeOrUnsupportedDestination,
    .destinationSymbolicLink,
    .destinationCollision,
    .stagingCreationOrCopyFailure,
    .digestOrByteCountMismatch,
    .sqliteIntegrityFailure,
    .foreignKeyFailure,
    .schemaMismatchOrUnsupportedSchema,
    .unexpectedArtifact,
    .atomicCommitFailure,
    .committedRevalidationFailure
]

private func seedExportPerformanceRows(at databaseURL: URL, count: Int) throws {
    let queue = try DatabaseQueueFactory.open(at: databaseURL)
    try queue.write { db in
        for index in 0..<count {
            try db.execute(
                sql: """
                    INSERT INTO accounts (id, name, kind, currency_code)
                    VALUES (?, ?, 'other', 'CNY')
                    """,
                arguments: [
                    String(format: "export-perf-%05d", index),
                    String(format: "Synthetic Export Row %05d", index)
                ]
            )
        }
    }
    try queue.close()
}

private func exportPerformanceSentinel(at databaseURL: URL) throws -> (count: Int, length: Int) {
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
