import Foundation
import GRDB
import Testing
@testable import Aureus

@Suite("Permanent External Backup Restore foundation")
struct PermanentExternalRestoreTests {
    @Test("Current-schema External generation restores into the same Store with one safety generation")
    func currentSchemaRestore() async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try await seedExternalAccounts(
            context.store,
            prefix: "external-current-only",
            count: 1
        )
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-candidate-only",
            count: 1,
            identity: 1
        )
        let sourceBefore = try externalFingerprint(candidate)

        let result = try await performExternalRestore(context, candidate: candidate, operation: 1)

        #expect(result.previousSchemaVersion == 8)
        #expect(result.candidateSchemaVersion == 8)
        #expect(result.finalSchemaVersion == 8)
        #expect(!result.migrationRan)
        #expect(result.operationCategory == .externalGenerationRestore)
        #expect(result.databaseByteCount == candidate.manifest.databaseByteCount)
        #expect(try await externalAccountIDs(context.store) == ["external-candidate-only-00000"])
        try await context.store.insertIsolationSentinel(
            id: "external-post-restore-crud",
            name: "Synthetic Post Restore CRUD"
        )
        #expect(try await externalAccountIDs(context.store) == [
            "external-candidate-only-00000", "external-post-restore-crud"
        ])
        #expect(await context.store.maintenanceState == .ready)

        let inventory = try externalInventory(context)
        #expect(inventory.validGenerations.count == 1)
        let safety = try #require(inventory.validGenerations.first)
        #expect(safety.directoryURL.lastPathComponent == result.safetyGenerationIdentity)
        #expect(try externalGenerationAccountIDs(safety) == ["external-current-only-00000"])
        #expect(try externalFingerprint(candidate) == sourceBefore)
        #expect(try externalOwnedStageNames(context).isEmpty)
        #expect(!inventory.validGenerations.contains {
            $0.directoryURL.lastPathComponent == candidate.directoryURL.lastPathComponent
        })
    }

    @Test("External candidate remains independently valid and neighboring artifacts are untouched")
    func externalSourceIndependence() async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-independent",
            count: 2,
            identity: 2
        )
        let sibling = context.externalRoot.appendingPathComponent("owner-unknown-sibling")
        let siblingBytes = Data("synthetic external sibling".utf8)
        try siblingBytes.write(to: sibling)
        let before = try externalFingerprint(candidate)

        _ = try await performExternalRestore(context, candidate: candidate, operation: 2)
        let validated = try PermanentBackupService.validateStandaloneExternalGeneration(
            candidate.directoryURL,
            excluding: context.protectedSourceURLs
        )

        #expect(validated == candidate)
        #expect(try externalGenerationAccountIDs(validated) == [
            "external-independent-00000", "external-independent-00001"
        ])
        #expect(try externalFingerprint(candidate) == before)
        #expect(try Data(contentsOf: sibling) == siblingBytes)
    }

    @Test("Legacy schema 1 through 7 migrate forward without modifying External source", arguments: [1, 2, 3, 4, 5, 6, 7])
    func legacyForwardMigration(version: Int) async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: version,
            prefix: "external-legacy-v\(version)",
            count: 1,
            identity: 10 + version
        )
        let sourceBefore = try externalFingerprint(candidate)

        let result = try await performExternalRestore(
            context,
            candidate: candidate,
            operation: 10 + version
        )

        #expect(result.candidateSchemaVersion == version)
        #expect(result.finalSchemaVersion == 8)
        #expect(result.migrationRan)
        #expect(try await context.store.schemaVersion() == 8)
        #expect(try await externalAccountIDs(context.store) == [
            "external-legacy-v\(version)-00000"
        ])
        #expect(try externalFingerprint(candidate) == sourceBefore)
    }

    @Test("Raw SQLite WAL SHM archives and non-file URLs are rejected", arguments: ExternalUnsupportedInput.allCases)
    func unsupportedInput(variant: ExternalUnsupportedInput) async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-unsupported",
            count: 1,
            identity: 20 + variant.rawValue
        )
        let input: URL
        switch variant {
        case .rawSQLite:
            input = externalDatabaseURL(candidate)
        case .wal:
            input = context.externalRoot.appendingPathComponent("aureus.sqlite-wal")
            try Data("synthetic wal".utf8).write(to: input)
        case .shm:
            input = context.externalRoot.appendingPathComponent("aureus.sqlite-shm")
            try Data("synthetic shm".utf8).write(to: input)
        case .archive:
            input = context.externalRoot.appendingPathComponent("backup.zip")
            try Data("synthetic archive".utf8).write(to: input)
        case .nonFileURL:
            input = try #require(URL(string: "https://example.invalid/backup"))
        }

        let operations = ExternalTrackingRestoreOperations()
        let error = await externalRestoreError(
            context,
            candidateURL: input,
            operation: 20 + variant.rawValue,
            fileOperations: operations
        )

        guard case .invalidExternalCandidate = error else {
            Issue.record("Unsupported input was not rejected as an External candidate")
            return
        }
        #expect(operations.copyCount == 0)
        #expect(operations.replacementCount == 0)
        #expect(try externalInventory(context).validGenerations.isEmpty)
    }

    @Test("Missing malformed noncanonical and unsupported manifests are rejected", arguments: ExternalManifestFailure.allCases)
    func invalidManifest(variant: ExternalManifestFailure) async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-manifest",
            count: 1,
            identity: 30 + variant.rawValue
        )
        switch variant {
        case .missing:
            try FileManager.default.removeItem(at: externalManifestURL(candidate))
        case .malformed:
            try Data("{malformed".utf8).write(to: externalManifestURL(candidate))
        case .unsupportedFormat:
            try rewriteExternalManifest(candidate) { manifest in
                externalManifestCopy(manifest, backupFormatVersion: 2)
            }
        case .noncanonicalUTC:
            try rewriteExternalManifest(candidate) { manifest in
                externalManifestCopy(manifest, createdAt: "2026-01-01T00:00:00Z")
            }
        case .invalidAppVersion:
            try rewriteExternalManifest(candidate) { manifest in
                externalManifestCopy(manifest, appVersion: "invalid/version")
            }
        }

        let error = await externalRestoreError(
            context,
            candidate: candidate,
            operation: 30 + variant.rawValue
        )
        guard case .invalidExternalCandidate = error else {
            Issue.record("Invalid manifest was not rejected before Restore")
            return
        }
        #expect(try externalInventory(context).validGenerations.isEmpty)
        #expect(try await externalAccountIDs(context.store).isEmpty)
    }

    @Test("Hash and byte-count tampering are rejected before safety Backup", arguments: ExternalDigestFailure.allCases)
    func digestTamper(variant: ExternalDigestFailure) async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-digest",
            count: 1,
            identity: 40 + variant.rawValue
        )
        switch variant {
        case .hash:
            var data = try Data(contentsOf: externalDatabaseURL(candidate))
            data[data.index(before: data.endIndex)] ^= 0x01
            try data.write(to: externalDatabaseURL(candidate))
        case .byteCount:
            try rewriteExternalManifest(candidate) { manifest in
                externalManifestCopy(
                    manifest,
                    databaseByteCount: manifest.databaseByteCount + 1
                )
            }
        }

        let error = await externalRestoreError(
            context,
            candidate: candidate,
            operation: 40 + variant.rawValue
        )
        guard case let .invalidExternalCandidate(reason) = error else {
            Issue.record("Tampered External candidate was not rejected")
            return
        }
        #expect(reason == (variant == .hash ? .hashMismatch : .byteCountMismatch))
        #expect(try externalInventory(context).validGenerations.isEmpty)
    }

    @Test("Matching manifest cannot authorize corrupt non-SQLite content")
    func corruptDatabase() async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-corrupt",
            count: 1,
            identity: 50
        )
        try Data(repeating: 0x41, count: 4_096).write(to: externalDatabaseURL(candidate))
        try resignExternalGeneration(candidate, schemaVersion: 8)

        #expect(await externalRestoreError(context, candidate: candidate, operation: 50)
            == .invalidExternalCandidate(.databaseOpenOrIntegrityFailure))
        #expect(try externalInventory(context).validGenerations.isEmpty)
    }

    @Test("Foreign-key-invalid External content is rejected")
    func foreignKeyViolation() async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-fk",
            count: 1,
            identity: 51
        )
        let queue = try DatabaseQueue(path: externalDatabaseURL(candidate).path)
        try await queue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
            try db.execute(sql: """
                INSERT INTO assets (id, container_id, name, currency_code, instrument_reference_id)
                VALUES ('external-invalid-asset', 'missing-container', 'Synthetic Invalid', 'CNY', NULL)
                """)
        }
        try queue.close()
        try resignExternalGeneration(candidate, schemaVersion: 8)

        #expect(await externalRestoreError(context, candidate: candidate, operation: 51)
            == .invalidExternalCandidate(.foreignKeyFailure))
    }

    @Test("Unexpected third artifacts are rejected")
    func unexpectedArtifact() async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-third-file",
            count: 1,
            identity: 52
        )
        try Data("synthetic unexpected".utf8).write(
            to: candidate.directoryURL.appendingPathComponent("unexpected.txt")
        )

        #expect(await externalRestoreError(context, candidate: candidate, operation: 52)
            == .invalidExternalCandidate(.unexpectedArtifact))
    }

    @Test("Generation database and manifest symbolic links are rejected", arguments: ExternalSymlinkFailure.allCases)
    func symbolicLinkRejection(variant: ExternalSymlinkFailure) async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-symlink",
            count: 1,
            identity: 60 + variant.rawValue
        )
        let selectedURL: URL
        switch variant {
        case .generation:
            let linkName = try PermanentBackupService.externalExportGenerationName(
                createdAt: candidate.manifest.createdAt,
                operationID: externalUUID(6_900)
            )
            selectedURL = context.externalRoot.appendingPathComponent(linkName)
            try FileManager.default.createSymbolicLink(
                at: selectedURL,
                withDestinationURL: candidate.directoryURL
            )
        case .database:
            selectedURL = candidate.directoryURL
            let original = externalDatabaseURL(candidate)
            let copy = context.root.appendingPathComponent("external-database-copy.sqlite")
            try FileManager.default.copyItem(at: original, to: copy)
            try FileManager.default.removeItem(at: original)
            try FileManager.default.createSymbolicLink(at: original, withDestinationURL: copy)
        case .manifest:
            selectedURL = candidate.directoryURL
            let original = externalManifestURL(candidate)
            let copy = context.root.appendingPathComponent("external-manifest-copy.json")
            try FileManager.default.copyItem(at: original, to: copy)
            try FileManager.default.removeItem(at: original)
            try FileManager.default.createSymbolicLink(at: original, withDestinationURL: copy)
        }

        #expect(await externalRestoreError(
            context,
            candidateURL: selectedURL,
            operation: 60 + variant.rawValue
        ) == .invalidExternalCandidate(.symbolicLinkRejected))
    }

    @Test("Manifest schema zero is rejected by the External Restore API before staging")
    func schemaZeroManifest() async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try await seedExternalAccounts(
            context.store,
            prefix: "external-schema-zero-live",
            count: 1
        )
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-schema-zero",
            count: 1,
            identity: 70
        )
        try rewriteExternalManifest(candidate) { manifest in
            externalManifestCopy(manifest, schemaVersion: 0)
        }
        let sourceBefore = try externalFingerprint(candidate)
        let liveBefore = try await externalAccountIDs(context.store)
        let operations = ExternalTrackingRestoreOperations()

        let error = await externalRestoreError(
            context,
            candidate: candidate,
            operation: 70,
            fileOperations: operations
        )

        #expect(error == .invalidExternalCandidate(.malformedManifest))
        #expect(operations.copyCount == 0)
        #expect(operations.replacementCount == 0)
        #expect(try externalInventory(context).validGenerations.isEmpty)
        #expect(try await externalAccountIDs(context.store) == liveBefore)
        #expect(await context.store.maintenanceState == .ready)
        #expect(try externalFingerprint(candidate) == sourceBefore)
    }

    @Test("Future schema nine is rejected by the External Restore API before staging")
    func futureSchemaNine() async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try await seedExternalAccounts(
            context.store,
            prefix: "external-schema-nine-live",
            count: 1
        )
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-schema-nine",
            count: 1,
            identity: 77
        )
        try mutateExternalDatabase(candidate) { db in
            try db.execute(
                sql: "UPDATE schema_metadata SET version = ? WHERE store_kind = 'permanent'",
                arguments: [9]
            )
        }
        try resignExternalGeneration(candidate, schemaVersion: 9)
        let sourceBefore = try externalFingerprint(candidate)
        let liveBefore = try await externalAccountIDs(context.store)
        let operations = ExternalTrackingRestoreOperations()

        let error = await externalRestoreError(
            context,
            candidate: candidate,
            operation: 77,
            fileOperations: operations
        )

        #expect(error == .invalidExternalCandidate(.schemaMismatch))
        #expect(operations.copyCount == 0)
        #expect(operations.replacementCount == 0)
        #expect(try externalInventory(context).validGenerations.isEmpty)
        #expect(try await externalAccountIDs(context.store) == liveBefore)
        #expect(await context.store.maintenanceState == .ready)
        #expect(try externalFingerprint(candidate) == sourceBefore)
    }

    @Test("Internal Backup Permanent Market Cache and additional protected roots reject overlap", arguments: ExternalOverlapFailure.allCases)
    func protectedSourceOverlap(variant: ExternalOverlapFailure) async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-overlap",
            count: 1,
            identity: 90 + variant.rawValue
        )
        let protectedParent: URL
        var configuration = context.configuration
        switch variant {
        case .internalBackup:
            protectedParent = context.paths.internalBackupDirectoryURL
        case .permanent:
            protectedParent = context.paths.permanentDatabaseURL.deletingLastPathComponent()
        case .marketCache:
            protectedParent = context.paths.marketCacheDatabaseURL.deletingLastPathComponent()
        case .additional:
            protectedParent = context.additionalProtectedRoot
        }
        try FileManager.default.createDirectory(
            at: protectedParent,
            withIntermediateDirectories: true
        )
        let protectedCandidateURL = protectedParent.appendingPathComponent(
            candidate.directoryURL.lastPathComponent,
            isDirectory: true
        )
        try FileManager.default.copyItem(at: candidate.directoryURL, to: protectedCandidateURL)
        if variant == .additional {
            configuration = PermanentExternalRestoreConfiguration(
                internalBackupRootURL: context.paths.internalBackupDirectoryURL,
                permanentDatabaseURL: context.paths.permanentDatabaseURL,
                marketCacheDatabaseURL: context.paths.marketCacheDatabaseURL,
                additionalProtectedSourceRoots: [context.additionalProtectedRoot]
            )
        }

        let operations = ExternalTrackingRestoreOperations()
        let error = await externalRestoreError(
            context,
            candidateURL: protectedCandidateURL,
            operation: 90 + variant.rawValue,
            configuration: configuration,
            fileOperations: operations
        )

        #expect(error == .invalidExternalCandidate(.unsafePath))
        #expect(operations.copyCount == 0)
        #expect(operations.replacementCount == 0)
    }

    @Test("Validation failure occurs before safety Backup queue close or replacement")
    func validationFailureIsEarly() async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try await seedExternalAccounts(context.store, prefix: "external-early-live", count: 1)
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-early-candidate",
            count: 1,
            identity: 100
        )
        try FileManager.default.removeItem(at: externalManifestURL(candidate))
        let operations = ExternalTrackingRestoreOperations()

        _ = await externalRestoreError(
            context,
            candidate: candidate,
            operation: 100,
            fileOperations: operations
        )

        #expect(operations.copyCount == 0)
        #expect(operations.replacementCount == 0)
        #expect(try externalInventory(context).validGenerations.isEmpty)
        #expect(try await externalAccountIDs(context.store) == ["external-early-live-00000"])
        try await context.store.insertIsolationSentinel(
            id: "external-early-still-open",
            name: "Synthetic Still Open"
        )
    }

    @Test("Candidate staging copy and digest failures leave the live Store unchanged", arguments: ExternalStagingFailure.allCases)
    func stagingFailure(variant: ExternalStagingFailure) async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try await seedExternalAccounts(context.store, prefix: "external-stage-live", count: 1)
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-stage-candidate",
            count: 1,
            identity: 110 + variant.rawValue
        )
        let operations = ExternalTrackingRestoreOperations(delegate: variant == .copy
            ? ExternalFailingCopyOperations()
            : ExternalCorruptingCopyOperations())

        #expect(await externalRestoreError(
            context,
            candidate: candidate,
            operation: 110 + variant.rawValue,
            fileOperations: operations
        ) == .candidateStagingFailed)
        #expect(operations.copyCount == 1 && operations.replacementCount == 0)
        #expect(try await externalAccountIDs(context.store) == ["external-stage-live-00000"])
        #expect(try externalInventory(context).validGenerations.isEmpty)
        #expect(try externalOwnedStageNames(context).isEmpty)
    }

    @Test("Safety Backup failure leaves the live Store open and unchanged")
    func safetyBackupFailure() async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try await seedExternalAccounts(context.store, prefix: "external-safety-live", count: 1)
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-safety-candidate",
            count: 1,
            identity: 120
        )
        let invalidRoot = context.root.appendingPathComponent("NotBackups")
        let configuration = PermanentExternalRestoreConfiguration(
            internalBackupRootURL: invalidRoot,
            permanentDatabaseURL: context.paths.permanentDatabaseURL,
            marketCacheDatabaseURL: context.paths.marketCacheDatabaseURL,
            additionalProtectedSourceRoots: [context.additionalProtectedRoot]
        )
        let operations = ExternalTrackingRestoreOperations()

        #expect(await externalRestoreError(
            context,
            candidate: candidate,
            operation: 120,
            configuration: configuration,
            fileOperations: operations
        ) == .safetyBackupFailed)
        #expect(operations.copyCount == 1)
        #expect(operations.replacementCount == 0)
        #expect(try await externalAccountIDs(context.store) == ["external-safety-live-00000"])
        #expect(await context.store.maintenanceState == .ready)
        #expect(try externalOwnedStageNames(context).isEmpty)
    }

    @Test("Replacement failure preserves the current Store and immutable External source")
    func replacementFailure() async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try await seedExternalAccounts(context.store, prefix: "external-replace-live", count: 1)
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-replace-candidate",
            count: 1,
            identity: 130
        )
        let before = try externalFingerprint(candidate)
        let operations = ExternalFailingFirstReplacementOperations()

        #expect(await externalRestoreError(
            context,
            candidate: candidate,
            operation: 130,
            fileOperations: operations
        ) == .replacementFailed)
        #expect(operations.replacementCount == 1)
        #expect(try await externalAccountIDs(context.store) == ["external-replace-live-00000"])
        #expect(try externalFingerprint(candidate) == before)
        #expect(try externalInventory(context).validGenerations.count == 1)
    }

    @Test("Migration and post-activation failures use the safety rollback", arguments: ExternalActivationFailure.allCases)
    func activationFailureRollsBack(variant: ExternalActivationFailure) async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try await seedExternalAccounts(context.store, prefix: "external-rollback-live", count: 1)
        let candidate: PermanentBackupGeneration
        let operations: any PermanentRestoreFileOperations
        if variant == .migration {
            candidate = try await makeMigrationFailureExternalCandidate(context, identity: 140)
            operations = LocalPermanentRestoreFileOperations()
        } else {
            candidate = try await makeExternalCandidate(
                context,
                schemaVersion: 8,
                prefix: "external-activation-candidate",
                count: 1,
                identity: 140 + variant.rawValue
            )
            operations = ExternalPostReplacementMutationOperations(variant: variant)
        }
        let before = try externalFingerprint(candidate)

        let tracking = ExternalTrackingRestoreOperations(delegate: operations)
        let error = await externalRestoreError(
            context,
            candidate: candidate,
            operation: 140 + variant.rawValue,
            fileOperations: tracking
        )
        guard case .restoreFailedRollbackSucceeded = error else {
            Issue.record("Activation failure did not return the rollback-succeeded state")
            return
        }
        #expect(tracking.copyCount == 2 && tracking.replacementCount == 2)
        #expect(try await externalAccountIDs(context.store) == ["external-rollback-live-00000"])
        #expect(await context.store.maintenanceState == .ready)
        #expect(try externalFingerprint(candidate) == before)
        let inventory = try externalInventory(context)
        #expect(inventory.validGenerations.count == 1)
        #expect(try externalGenerationAccountIDs(try #require(inventory.validGenerations.first))
            == ["external-rollback-live-00000"])
        #expect(try externalOwnedStageNames(context).isEmpty)
    }

    @Test("Rollback failure enters recoveryRequired retains safety and blocks another operation")
    func rollbackFailure() async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try await seedExternalAccounts(context.store, prefix: "external-recovery-live", count: 1)
        let candidate = try await makeMigrationFailureExternalCandidate(context, identity: 150)
        let before = try externalFingerprint(candidate)
        let operations = ExternalFailingSecondReplacementOperations()

        #expect(await externalRestoreError(
            context,
            candidate: candidate,
            operation: 150,
            fileOperations: operations
        ) == .rollbackFailed)
        #expect(operations.replacementCount == 2)
        #expect(await context.store.maintenanceState == .recoveryRequired)
        #expect(try externalInventory(context).validGenerations.count == 1)
        #expect(try externalFingerprint(candidate) == before)
        #expect(await externalRestoreError(
            context,
            candidate: candidate,
            operation: 151
        ) == .maintenanceUnavailable)
    }

    @Test("Internal Restore continues to reject External paths and succeeds for internal direct children")
    func internalRestoreBoundary() async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let external = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-boundary",
            count: 1,
            identity: 160
        )

        do {
            _ = try await context.store.restorePermanentBackup(
                external.directoryURL,
                in: context.paths.internalBackupDirectoryURL,
                appVersion: externalRestoreAppVersion,
                createdAt: externalRestoreInstant,
                operationID: externalUUID(16_001),
                safetyGenerationID: externalUUID(16_002)
            )
            Issue.record("Internal Restore accepted an External path")
        } catch let error as PermanentRestoreError {
            #expect(error == .candidateValidationFailed)
        }

        let sourceStore = try WealthStore(
            databaseURL: context.root.appendingPathComponent("InternalSource/aureus.sqlite")
        )
        try await seedExternalAccounts(sourceStore, prefix: "internal-candidate", count: 1)
        let internalCandidate = try await sourceStore.createPermanentBackup(
            in: context.paths.internalBackupDirectoryURL,
            appVersion: externalRestoreAppVersion,
            createdAt: externalRestoreInstant,
            generationID: externalUUID(16_003)
        )
        let result = try await context.store.restorePermanentBackup(
            internalCandidate.directoryURL,
            in: context.paths.internalBackupDirectoryURL,
            appVersion: externalRestoreAppVersion,
            createdAt: UTCInstant(
                millisecondsSince1970: externalRestoreInstant.millisecondsSince1970 + 1
            ),
            operationID: externalUUID(16_004),
            safetyGenerationID: externalUUID(16_005)
        )
        #expect(result.operationCategory == .internalGenerationRestore)
        #expect(try await externalAccountIDs(context.store) == ["internal-candidate-00000"])
    }

    @Test("External Restore safety Backup obeys five-generation retention and preserves unknown siblings")
    func retentionAndUnknownSiblings() async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try await seedExternalAccounts(context.store, prefix: "external-retention-live", count: 1)
        for index in 0..<5 {
            _ = try await context.store.createPermanentBackup(
                in: context.paths.internalBackupDirectoryURL,
                appVersion: externalRestoreAppVersion,
                createdAt: UTCInstant(
                    millisecondsSince1970: externalRestoreInstant.millisecondsSince1970 + Int64(index)
                ),
                generationID: externalUUID(17_000 + index)
            )
        }
        let unknownInternal = context.paths.internalBackupDirectoryURL
            .appendingPathComponent("owner-unknown-internal")
        try Data("preserve internal".utf8).write(to: unknownInternal)
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-retention-candidate",
            count: 1,
            identity: 170
        )

        let result = try await performExternalRestore(context, candidate: candidate, operation: 170)
        let inventory = try externalInventory(context)

        #expect(inventory.validGenerations.count == 5)
        #expect(inventory.ignoredArtifactCount == 1)
        #expect(FileManager.default.fileExists(atPath: unknownInternal.path))
        #expect(inventory.validGenerations.contains {
            $0.directoryURL.lastPathComponent == result.safetyGenerationIdentity
        })
        #expect(!inventory.validGenerations.contains {
            $0.directoryURL.lastPathComponent == candidate.directoryURL.lastPathComponent
        })
        #expect(FileManager.default.fileExists(atPath: candidate.directoryURL.path))
    }

    @Test("Typed results and errors expose no path filename hash or business value")
    func diagnosticPrivacy() async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-private-business-987654",
            count: 1,
            identity: 180
        )
        let result = try await performExternalRestore(context, candidate: candidate, operation: 180)
        let resultText = String(reflecting: result)
        let errorText = PermanentExternalRestoreError
            .invalidExternalCandidate(.hashMismatch).localizedDescription
        for forbidden in [
            context.root.path,
            candidate.directoryURL.lastPathComponent,
            candidate.manifest.databaseSHA256,
            "external-private-business",
            "987654"
        ] {
            #expect(!resultText.contains(forbidden))
            #expect(!errorText.contains(forbidden))
        }
    }

    @Test("Repeated operations are explicit independent and persist no External history")
    func repeatedExplicitOperations() async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-repeat",
            count: 1,
            identity: 190
        )
        #expect(try externalInventory(context).validGenerations.isEmpty)

        let first = try await performExternalRestore(context, candidate: candidate, operation: 190)
        let afterFirst = try externalInventory(context)
        let second = try await performExternalRestore(context, candidate: candidate, operation: 191)
        let afterSecond = try externalInventory(context)

        #expect(first.safetyGenerationIdentity != second.safetyGenerationIdentity)
        #expect(afterFirst.validGenerations.count == 1)
        #expect(afterSecond.validGenerations.count == 2)
        #expect(try externalOwnedStageNames(context).isEmpty)
        #expect(FileManager.default.fileExists(atPath: candidate.directoryURL.path))
        #expect(try !externalAllFileNames(in: context.paths.internalBackupDirectoryURL).contains {
            $0.contains(candidate.directoryURL.path)
        })
    }

    @Test("Market Cache key-like and Provider-adjacent sentinels remain untouched")
    func dependencyIsolation() async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try FileManager.default.createDirectory(
            at: context.paths.marketCacheDatabaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let cacheBytes = Data("synthetic cache sentinel".utf8)
        try cacheBytes.write(to: context.paths.marketCacheDatabaseURL)
        let keyLike = context.root.appendingPathComponent("synthetic-key-like-sentinel")
        let providerLike = context.root.appendingPathComponent("synthetic-provider-like-sentinel")
        try Data("not a credential".utf8).write(to: keyLike)
        try Data("not a provider payload".utf8).write(to: providerLike)
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-isolation",
            count: 1,
            identity: 200
        )

        _ = try await performExternalRestore(context, candidate: candidate, operation: 200)

        #expect(try Data(contentsOf: context.paths.marketCacheDatabaseURL) == cacheBytes)
        #expect(try String(contentsOf: keyLike, encoding: .utf8) == "not a credential")
        #expect(try String(contentsOf: providerLike, encoding: .utf8) == "not a provider payload")
        for generation in try externalInventory(context).validGenerations {
            #expect(try externalArtifactNames(generation.directoryURL)
                == ["aureus.sqlite", "manifest.json"])
        }
    }

    @Test("Release workload validates safety-backs-up and restores ten thousand rows")
    func stage11ExternalRestorePerformance() async throws {
        let context = try externalRestoreContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try await seedExternalAccounts(
            context.store,
            prefix: "external-perf-current",
            count: 10_000
        )
        let candidate = try await makeExternalCandidate(
            context,
            schemaVersion: 8,
            prefix: "external-perf-candidate",
            count: 10_000,
            identity: 900
        )
        let sourceBefore = try externalFingerprint(candidate)
        let clock = ContinuousClock()
        let start = clock.now

        let result = try await performExternalRestore(context, candidate: candidate, operation: 900)
        let elapsed = start.duration(to: clock.now)
        let restored = try await externalAccountSummary(context.store)
        let inventory = try externalInventory(context)
        let safety = try #require(inventory.validGenerations.first {
            $0.directoryURL.lastPathComponent == result.safetyGenerationIdentity
        })
        let safetySummary = try externalGenerationAccountSummary(safety)
        let milliseconds = externalMilliseconds(elapsed)

        #expect(restored.count == 10_000)
        #expect(restored.first == "external-perf-candidate-00000")
        #expect(restored.last == "external-perf-candidate-09999")
        #expect(safetySummary.count == 10_000)
        #expect(safetySummary.first == "external-perf-current-00000")
        #expect(safetySummary.last == "external-perf-current-09999")
        #expect(try externalFingerprint(candidate) == sourceBefore)
        #expect(elapsed < .seconds(10))
        print(
            "STAGE11_EXTERNAL_RESTORE_PERF rows=10000 "
                + "validate_safety_restore_ms=\(milliseconds) migration_applied=0 "
                + "provider_requests=0 cache_reads=0 credential_reads=0"
        )
    }
}

private let externalRestoreAppVersion = "0.1-external-restore-test"
private let externalRestoreInstant = UTCInstant(millisecondsSince1970: 1_788_285_600_000)

private struct ExternalRestoreTestContext: Sendable {
    let root: URL
    let paths: RuntimePaths
    let externalRoot: URL
    let additionalProtectedRoot: URL
    let store: WealthStore

    var configuration: PermanentExternalRestoreConfiguration {
        PermanentExternalRestoreConfiguration(
            internalBackupRootURL: paths.internalBackupDirectoryURL,
            permanentDatabaseURL: paths.permanentDatabaseURL,
            marketCacheDatabaseURL: paths.marketCacheDatabaseURL,
            additionalProtectedSourceRoots: [additionalProtectedRoot]
        )
    }

    var protectedSourceURLs: [URL] {
        [
            paths.internalBackupDirectoryURL,
            paths.permanentDatabaseURL,
            paths.permanentDatabaseURL.deletingLastPathComponent(),
            paths.marketCacheDatabaseURL,
            paths.marketCacheDatabaseURL.deletingLastPathComponent(),
            additionalProtectedRoot
        ]
    }
}

enum ExternalUnsupportedInput: Int, CaseIterable, Sendable {
    case rawSQLite
    case wal
    case shm
    case archive
    case nonFileURL
}

enum ExternalManifestFailure: Int, CaseIterable, Sendable {
    case missing
    case malformed
    case unsupportedFormat
    case noncanonicalUTC
    case invalidAppVersion
}

enum ExternalDigestFailure: Int, CaseIterable, Sendable {
    case hash
    case byteCount
}

enum ExternalSymlinkFailure: Int, CaseIterable, Sendable {
    case generation
    case database
    case manifest
}

enum ExternalOverlapFailure: Int, CaseIterable, Sendable {
    case internalBackup
    case permanent
    case marketCache
    case additional
}

enum ExternalStagingFailure: Int, CaseIterable, Sendable {
    case copy
    case digest
}

enum ExternalActivationFailure: Int, CaseIterable, Sendable {
    case migration
    case databaseOpen
    case foreignKey
    case schema
    case requiredTable
    case applicationInvariant
}

private enum ExternalSyntheticFailure: Error {
    case intentional
}

private func externalRestoreContext() throws -> ExternalRestoreTestContext {
    let base: URL
    if let injected = ProcessInfo.processInfo.environment["AUREUS_EXTERNAL_RESTORE_TEST_ROOT"],
       !injected.isEmpty {
        base = URL(fileURLWithPath: injected, isDirectory: true)
    } else {
        base = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("AureusTests/PermanentExternalRestore", isDirectory: true)
    }
    let root = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let runtimeRoot = root.appendingPathComponent("LiveRuntime", isDirectory: true)
    let paths = RuntimePaths.temporary(root: runtimeRoot)
    let externalRoot = root.appendingPathComponent("ExternalGenerations", isDirectory: true)
    let protectedRoot = root.appendingPathComponent("SyntheticProtectedRoot", isDirectory: true)
    try FileManager.default.createDirectory(at: externalRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: protectedRoot, withIntermediateDirectories: true)
    return ExternalRestoreTestContext(
        root: root,
        paths: paths,
        externalRoot: externalRoot,
        additionalProtectedRoot: protectedRoot,
        store: try WealthStore(databaseURL: paths.permanentDatabaseURL)
    )
}

private func makeExternalCandidate(
    _ context: ExternalRestoreTestContext,
    schemaVersion: Int,
    prefix: String,
    count: Int,
    identity: Int
) async throws -> PermanentBackupGeneration {
    let sourceRoot = context.root.appendingPathComponent(
        "CandidateSource-\(identity)",
        isDirectory: true
    )
    let sourcePaths = RuntimePaths.temporary(root: sourceRoot)
    let sourceQueue: DatabaseQueue
    if schemaVersion == 8 {
        let sourceStore = try WealthStore(databaseURL: sourcePaths.permanentDatabaseURL)
        try await seedExternalAccounts(sourceStore, prefix: prefix, count: count)
        return try await exportExternalGeneration(
            from: sourceStore,
            sourcePaths: sourcePaths,
            to: context.externalRoot,
            identity: identity
        )
    }

    sourceQueue = try DatabaseQueueFactory.open(at: sourcePaths.permanentDatabaseURL)
    let migrator = DatabaseMigrations.permanentMigrator()
    try migrator.migrate(
        sourceQueue,
        upTo: PermanentDatabaseValidation.migrationIdentifiers[schemaVersion - 1]
    )
    try await sourceQueue.write { db in
        try insertExternalAccounts(db, prefix: prefix, count: count)
    }
    let internalGeneration = try PermanentBackupService.create(
        from: sourceQueue,
        in: sourcePaths.internalBackupDirectoryURL,
        appVersion: externalRestoreAppVersion,
        createdAt: UTCInstant(
            millisecondsSince1970: externalRestoreInstant.millisecondsSince1970 - 10_000
                + Int64(identity)
        ),
        generationID: externalUUID(identity)
    )
    try sourceQueue.close()
    return try exportExistingGeneration(
        internalGeneration,
        sourcePaths: sourcePaths,
        to: context.externalRoot,
        identity: identity
    )
}

private func exportExternalGeneration(
    from sourceStore: WealthStore,
    sourcePaths: RuntimePaths,
    to externalRoot: URL,
    identity: Int
) async throws -> PermanentBackupGeneration {
    let internalGeneration = try await sourceStore.createPermanentBackup(
        in: sourcePaths.internalBackupDirectoryURL,
        appVersion: externalRestoreAppVersion,
        createdAt: UTCInstant(
            millisecondsSince1970: externalRestoreInstant.millisecondsSince1970 - 10_000
                + Int64(identity)
        ),
        generationID: externalUUID(identity)
    )
    return try exportExistingGeneration(
        internalGeneration,
        sourcePaths: sourcePaths,
        to: externalRoot,
        identity: identity
    )
}

private func exportExistingGeneration(
    _ generation: PermanentBackupGeneration,
    sourcePaths: RuntimePaths,
    to externalRoot: URL,
    identity: Int
) throws -> PermanentBackupGeneration {
    let result = try PermanentBackupExportService.export(
        internalGenerationURL: generation.directoryURL,
        to: externalRoot,
        configuration: PermanentBackupExportConfiguration(
            internalBackupRootURL: sourcePaths.internalBackupDirectoryURL,
            permanentDatabaseURL: sourcePaths.permanentDatabaseURL,
            marketCacheDatabaseURL: sourcePaths.marketCacheDatabaseURL,
            additionalProtectedDestinationRoots: []
        ),
        operationID: externalUUID(20_000 + identity)
    )
    let externalURL = externalRoot.appendingPathComponent(
        result.exportedGenerationIdentity,
        isDirectory: true
    )
    return try PermanentBackupService.validateStandaloneExternalGeneration(
        externalURL,
        excluding: []
    )
}

private func makeMigrationFailureExternalCandidate(
    _ context: ExternalRestoreTestContext,
    identity: Int
) async throws -> PermanentBackupGeneration {
    let sourceRoot = context.root.appendingPathComponent(
        "MigrationFailureSource-\(identity)",
        isDirectory: true
    )
    let sourcePaths = RuntimePaths.temporary(root: sourceRoot)
    let queue = try DatabaseQueueFactory.open(at: sourcePaths.permanentDatabaseURL)
    let migrator = DatabaseMigrations.permanentMigrator()
    try migrator.migrate(queue, upTo: DatabaseMigrations.permanentV1)
    try await queue.write { db in
        try db.execute(
            sql: "INSERT INTO accounts (id, name, kind, currency_code) VALUES ('external-migration-bad', 'Synthetic Migration Bad', 'other', 'CNY')"
        )
        try db.execute(
            sql: "INSERT INTO asset_containers (id, account_id, name, kind) VALUES ('external-invalid-container', 'external-migration-bad', 'Synthetic Invalid', 'unsupported-kind')"
        )
    }
    let internalGeneration = try PermanentBackupService.create(
        from: queue,
        in: sourcePaths.internalBackupDirectoryURL,
        appVersion: externalRestoreAppVersion,
        createdAt: externalRestoreInstant,
        generationID: externalUUID(identity)
    )
    try queue.close()
    return try exportExistingGeneration(
        internalGeneration,
        sourcePaths: sourcePaths,
        to: context.externalRoot,
        identity: identity
    )
}

private func performExternalRestore(
    _ context: ExternalRestoreTestContext,
    candidate: PermanentBackupGeneration,
    operation: Int,
    configuration: PermanentExternalRestoreConfiguration? = nil,
    fileOperations: any PermanentRestoreFileOperations = LocalPermanentRestoreFileOperations()
) async throws -> PermanentExternalRestoreResult {
    try await context.store.restoreExternalPermanentBackup(
        candidate.directoryURL,
        configuration: configuration ?? context.configuration,
        appVersion: externalRestoreAppVersion,
        createdAt: UTCInstant(
            millisecondsSince1970: externalRestoreInstant.millisecondsSince1970
                + Int64(operation)
        ),
        operationID: externalUUID(30_000 + operation),
        safetyGenerationID: externalUUID(40_000 + operation),
        fileOperations: fileOperations
    )
}

private func externalRestoreError(
    _ context: ExternalRestoreTestContext,
    candidate: PermanentBackupGeneration,
    operation: Int,
    configuration: PermanentExternalRestoreConfiguration? = nil,
    fileOperations: any PermanentRestoreFileOperations = LocalPermanentRestoreFileOperations()
) async -> PermanentExternalRestoreError? {
    await externalRestoreError(
        context,
        candidateURL: candidate.directoryURL,
        operation: operation,
        configuration: configuration,
        fileOperations: fileOperations
    )
}

private func externalRestoreError(
    _ context: ExternalRestoreTestContext,
    candidateURL: URL,
    operation: Int,
    configuration: PermanentExternalRestoreConfiguration? = nil,
    fileOperations: any PermanentRestoreFileOperations = LocalPermanentRestoreFileOperations()
) async -> PermanentExternalRestoreError? {
    do {
        _ = try await context.store.restoreExternalPermanentBackup(
            candidateURL,
            configuration: configuration ?? context.configuration,
            appVersion: externalRestoreAppVersion,
            createdAt: UTCInstant(
                millisecondsSince1970: externalRestoreInstant.millisecondsSince1970
                    + Int64(operation)
            ),
            operationID: externalUUID(50_000 + operation),
            safetyGenerationID: externalUUID(60_000 + operation),
            fileOperations: fileOperations
        )
        return nil
    } catch let error as PermanentExternalRestoreError {
        return error
    } catch {
        return .invalidExternalCandidate(.fileSystemFailure)
    }
}

private func seedExternalAccounts(
    _ store: WealthStore,
    prefix: String,
    count: Int
) async throws {
    let queue = await store.queue
    try await queue.write { db in
        try insertExternalAccounts(db, prefix: prefix, count: count)
    }
}

private func insertExternalAccounts(
    _ db: Database,
    prefix: String,
    count: Int
) throws {
    for index in 0..<count {
        try db.execute(
            sql: "INSERT INTO accounts (id, name, kind, currency_code) VALUES (?, ?, 'other', 'CNY')",
            arguments: [
                String(format: "%@-%05d", prefix, index),
                String(format: "Synthetic External Restore %05d", index)
            ]
        )
    }
}

private func externalAccountIDs(_ store: WealthStore) async throws -> [String] {
    let queue = await store.queue
    return try await queue.read { db in
        try String.fetchAll(db, sql: "SELECT id FROM accounts ORDER BY id")
    }
}

private func externalAccountSummary(
    _ store: WealthStore
) async throws -> (count: Int, first: String?, last: String?) {
    let ids = try await externalAccountIDs(store)
    return (ids.count, ids.first, ids.last)
}

private func externalGenerationAccountIDs(
    _ generation: PermanentBackupGeneration
) throws -> [String] {
    var configuration = Configuration()
    configuration.readonly = true
    let queue = try DatabaseQueue(
        path: externalDatabaseURL(generation).path,
        configuration: configuration
    )
    defer { try? queue.close() }
    return try queue.read { db in
        try String.fetchAll(db, sql: "SELECT id FROM accounts ORDER BY id")
    }
}

private func externalGenerationAccountSummary(
    _ generation: PermanentBackupGeneration
) throws -> (count: Int, first: String?, last: String?) {
    let ids = try externalGenerationAccountIDs(generation)
    return (ids.count, ids.first, ids.last)
}

private func externalDatabaseURL(_ generation: PermanentBackupGeneration) -> URL {
    generation.directoryURL.appendingPathComponent(
        PermanentBackupService.databaseFileName,
        isDirectory: false
    )
}

private func externalManifestURL(_ generation: PermanentBackupGeneration) -> URL {
    generation.directoryURL.appendingPathComponent(
        PermanentBackupService.manifestFileName,
        isDirectory: false
    )
}

private func externalFingerprint(
    _ generation: PermanentBackupGeneration
) throws -> (PermanentBackupFileDigest, Data) {
    (
        try PermanentBackupService.streamingDigest(of: externalDatabaseURL(generation)),
        try Data(contentsOf: externalManifestURL(generation), options: [.mappedIfSafe])
    )
}

private func mutateExternalDatabase(
    _ generation: PermanentBackupGeneration,
    mutation: (Database) throws -> Void
) throws {
    let queue = try DatabaseQueue(path: externalDatabaseURL(generation).path)
    try queue.write(mutation)
    try queue.close()
}

private func resignExternalGeneration(
    _ generation: PermanentBackupGeneration,
    schemaVersion: Int
) throws {
    let digest = try PermanentBackupService.streamingDigest(of: externalDatabaseURL(generation))
    try rewriteExternalManifest(generation) { manifest in
        externalManifestCopy(
            manifest,
            schemaVersion: schemaVersion,
            databaseByteCount: digest.byteCount,
            databaseSHA256: digest.sha256
        )
    }
}

private func rewriteExternalManifest(
    _ generation: PermanentBackupGeneration,
    transform: (PermanentBackupManifest) -> PermanentBackupManifest
) throws {
    let url = externalManifestURL(generation)
    let manifest = try JSONDecoder().decode(
        PermanentBackupManifest.self,
        from: Data(contentsOf: url)
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(transform(manifest))
    data.append(0x0A)
    try data.write(to: url, options: .atomic)
}

private func externalManifestCopy(
    _ manifest: PermanentBackupManifest,
    backupFormatVersion: Int? = nil,
    appVersion: String? = nil,
    schemaVersion: Int? = nil,
    createdAt: String? = nil,
    databaseByteCount: Int64? = nil,
    databaseSHA256: String? = nil
) -> PermanentBackupManifest {
    PermanentBackupManifest(
        backupFormatVersion: backupFormatVersion ?? manifest.backupFormatVersion,
        appVersion: appVersion ?? manifest.appVersion,
        schemaVersion: schemaVersion ?? manifest.schemaVersion,
        createdAt: createdAt ?? manifest.createdAt,
        databaseByteCount: databaseByteCount ?? manifest.databaseByteCount,
        databaseSHA256: databaseSHA256 ?? manifest.databaseSHA256
    )
}

private func externalInventory(
    _ context: ExternalRestoreTestContext
) throws -> PermanentBackupInventory {
    try PermanentBackupService.inventory(in: context.paths.internalBackupDirectoryURL)
}

private func externalOwnedStageNames(
    _ context: ExternalRestoreTestContext
) throws -> [String] {
    try FileManager.default.contentsOfDirectory(
        at: context.paths.permanentDatabaseURL.deletingLastPathComponent(),
        includingPropertiesForKeys: nil
    ).map(\.lastPathComponent).filter { $0.hasPrefix(".restore-") }
}

private func externalArtifactNames(_ directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
}

private func externalAllFileNames(in directory: URL) throws -> [String] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ).map(\.lastPathComponent)
}

private func externalUUID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "f1000000-0000-4000-8000-%012d", value))!
}

private func externalMilliseconds(_ duration: Duration) -> Int64 {
    let components = duration.components
    return components.seconds * 1_000
        + Int64(components.attoseconds / 1_000_000_000_000_000)
}

private final class ExternalTrackingRestoreOperations: PermanentRestoreFileOperations, @unchecked Sendable {
    private let live: any PermanentRestoreFileOperations
    init(delegate: any PermanentRestoreFileOperations = LocalPermanentRestoreFileOperations()) { live = delegate }
    private let lock = NSLock()
    private var copies = 0
    private var replacements = 0

    var copyCount: Int { lock.withLock { copies } }
    var replacementCount: Int { lock.withLock { replacements } }

    func copyValidatedDatabase(from sourceURL: URL, to stagingURL: URL) throws {
        lock.withLock { copies += 1 }
        try live.copyValidatedDatabase(from: sourceURL, to: stagingURL)
    }

    func atomicallyReplaceDatabase(at databaseURL: URL, with stagingURL: URL) throws {
        lock.withLock { replacements += 1 }
        try live.atomicallyReplaceDatabase(at: databaseURL, with: stagingURL)
    }
}

private struct ExternalFailingCopyOperations: PermanentRestoreFileOperations {
    func copyValidatedDatabase(from sourceURL: URL, to stagingURL: URL) throws {
        throw ExternalSyntheticFailure.intentional
    }

    func atomicallyReplaceDatabase(at databaseURL: URL, with stagingURL: URL) throws {
        throw ExternalSyntheticFailure.intentional
    }
}

private struct ExternalCorruptingCopyOperations: PermanentRestoreFileOperations {
    private let live = LocalPermanentRestoreFileOperations()

    func copyValidatedDatabase(from sourceURL: URL, to stagingURL: URL) throws {
        try live.copyValidatedDatabase(from: sourceURL, to: stagingURL)
        var data = try Data(contentsOf: stagingURL)
        data[data.index(before: data.endIndex)] ^= 0x01
        try data.write(to: stagingURL)
    }

    func atomicallyReplaceDatabase(at databaseURL: URL, with stagingURL: URL) throws {
        try live.atomicallyReplaceDatabase(at: databaseURL, with: stagingURL)
    }
}

private final class ExternalFailingFirstReplacementOperations: PermanentRestoreFileOperations, @unchecked Sendable {
    private let live = LocalPermanentRestoreFileOperations()
    private let lock = NSLock()
    private var replacements = 0

    var replacementCount: Int { lock.withLock { replacements } }

    func copyValidatedDatabase(from sourceURL: URL, to stagingURL: URL) throws {
        try live.copyValidatedDatabase(from: sourceURL, to: stagingURL)
    }

    func atomicallyReplaceDatabase(at databaseURL: URL, with stagingURL: URL) throws {
        lock.withLock { replacements += 1 }
        throw ExternalSyntheticFailure.intentional
    }
}

private final class ExternalPostReplacementMutationOperations: PermanentRestoreFileOperations, @unchecked Sendable {
    private let live = LocalPermanentRestoreFileOperations()
    private let variant: ExternalActivationFailure
    private let lock = NSLock()
    private var replacements = 0

    init(variant: ExternalActivationFailure) {
        self.variant = variant
    }

    func copyValidatedDatabase(from sourceURL: URL, to stagingURL: URL) throws {
        try live.copyValidatedDatabase(from: sourceURL, to: stagingURL)
    }

    func atomicallyReplaceDatabase(at databaseURL: URL, with stagingURL: URL) throws {
        let count = lock.withLock { () -> Int in
            replacements += 1
            return replacements
        }
        try live.atomicallyReplaceDatabase(at: databaseURL, with: stagingURL)
        guard count == 1 else { return }
        switch variant {
        case .migration:
            break
        case .databaseOpen:
            let handle = try FileHandle(forWritingTo: databaseURL)
            try handle.seek(toOffset: 0)
            try handle.write(contentsOf: Data(repeating: 0, count: 128))
            try handle.close()
        case .foreignKey:
            let queue = try DatabaseQueue(path: databaseURL.path)
            try queue.writeWithoutTransaction { db in
                try db.execute(sql: "PRAGMA foreign_keys = OFF")
                try db.execute(sql: """
                    INSERT INTO assets (id, container_id, name, currency_code, instrument_reference_id)
                    VALUES ('external-post-invalid', 'missing-container', 'Synthetic Invalid', 'CNY', NULL)
                    """)
            }
            try queue.close()
        case .schema:
            let queue = try DatabaseQueue(path: databaseURL.path)
            try queue.write { db in
                try db.execute(
                    sql: "UPDATE schema_metadata SET version = 5 WHERE store_kind = 'permanent'"
                )
            }
            try queue.close()
        case .requiredTable:
            let queue = try DatabaseQueue(path: databaseURL.path)
            try queue.write { db in try db.execute(sql: "DROP TABLE goals") }
            try queue.close()
        case .applicationInvariant:
            let queue = try DatabaseQueue(path: databaseURL.path)
            try queue.write { db in try db.execute(sql: "DELETE FROM accounts") }
            try queue.close()
        }
    }
}

private final class ExternalFailingSecondReplacementOperations: PermanentRestoreFileOperations, @unchecked Sendable {
    private let live = LocalPermanentRestoreFileOperations()
    private let lock = NSLock()
    private var replacements = 0

    var replacementCount: Int { lock.withLock { replacements } }

    func copyValidatedDatabase(from sourceURL: URL, to stagingURL: URL) throws {
        try live.copyValidatedDatabase(from: sourceURL, to: stagingURL)
    }

    func atomicallyReplaceDatabase(at databaseURL: URL, with stagingURL: URL) throws {
        let count = lock.withLock { () -> Int in
            replacements += 1
            return replacements
        }
        if count == 2 {
            throw ExternalSyntheticFailure.intentional
        }
        try live.atomicallyReplaceDatabase(at: databaseURL, with: stagingURL)
    }
}
