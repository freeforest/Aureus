import CryptoKit
import Foundation
import GRDB
import Testing
@testable import Aureus

@Suite("Permanent Restore foundation")
struct PermanentRestoreTests {
    @Test("Current-schema internal generation restores into the same WealthStore")
    func currentSchemaRestore() async throws {
        let context = try restoreContext()
        try await seedAccount(context.store, id: "restore-current-only", name: "Synthetic Current Only")
        let candidate = try await currentCandidate(
            context,
            id: "restore-candidate-only",
            name: "Synthetic Candidate Only",
            generation: 1
        )

        let result = try await performRestore(context, candidate: candidate, operation: 1)

        #expect(result.previousSchemaVersion == 6)
        #expect(result.candidateSchemaVersion == 6)
        #expect(result.finalSchemaVersion == 6)
        #expect(!result.migrationRan)
        #expect(result.operationCategory == .internalGenerationRestore)
        #expect(try await accountIDs(context.store) == ["restore-candidate-only"])
        #expect(try await context.store.isolationSentinels() == ["Synthetic Candidate Only"])
        #expect(await context.store.maintenanceState == .ready)
    }

    @Test("Safety generation preserves the complete pre-Restore Store and remains valid")
    func safetyBackupPreserved() async throws {
        let context = try restoreContext()
        try await seedAccount(context.store, id: "restore-safety-old", name: "Synthetic Safety Old")
        let candidate = try await currentCandidate(
            context,
            id: "restore-safety-new",
            name: "Synthetic Safety New",
            generation: 2
        )

        let result = try await performRestore(context, candidate: candidate, operation: 2)
        let safetyURL = context.paths.internalBackupDirectoryURL.appendingPathComponent(
            result.safetyGenerationIdentity,
            isDirectory: true
        )
        let safety = try PermanentBackupService.validateGeneration(
            safetyURL,
            in: context.paths.internalBackupDirectoryURL
        )

        #expect(try generationAccountIDs(safety) == ["restore-safety-old"])
        #expect(try await accountIDs(context.store) == ["restore-safety-new"])
        #expect(FileManager.default.fileExists(atPath: safetyURL.path))
    }

    @Test("Restore never modifies the selected Backup generation")
    func candidateRemainsUnmodified() async throws {
        let context = try restoreContext()
        try await seedAccount(context.store, id: "restore-source-a", name: "Synthetic Source A")
        let candidate = try await currentCandidate(
            context,
            id: "restore-candidate-a",
            name: "Synthetic Candidate A",
            generation: 3
        )
        let before = try generationFingerprint(candidate)

        _ = try await performRestore(context, candidate: candidate, operation: 3)

        #expect(try generationFingerprint(candidate) == before)
        #expect(try generationAccountIDs(candidate) == ["restore-candidate-a"])
    }

    @Test("Legacy schema candidates migrate forward and preserve synthetic records", arguments: [1, 2, 3, 4, 5])
    func legacyForwardMigration(version: Int) async throws {
        let context = try restoreContext()
        try await seedAccount(context.store, id: "restore-current-v\(version)", name: "Synthetic Current v\(version)")
        let candidate = try legacyCandidate(context, version: version, generation: 10 + version)

        let result = try await performRestore(context, candidate: candidate, operation: 10 + version)

        #expect(result.candidateSchemaVersion == version)
        #expect(result.finalSchemaVersion == 6)
        #expect(result.migrationRan)
        #expect(try await context.store.schemaVersion() == 6)
        #expect(try await accountIDs(context.store) == ["restore-legacy-v\(version)"])
    }

    @Test("Future schema is rejected before safety Backup or replacement")
    func futureSchemaRejectedEarly() async throws {
        let context = try restoreContext()
        try await seedAccount(context.store, id: "restore-future-current", name: "Synthetic Future Current")
        let candidate = try await currentCandidate(
            context,
            id: "restore-future-candidate",
            name: "Synthetic Future Candidate",
            generation: 20
        )
        try mutateGeneration(candidate) { db in
            try db.execute(sql: "UPDATE schema_metadata SET version = 7 WHERE store_kind = 'permanent'")
        }
        try resignGeneration(candidate, schemaVersion: 7)
        #expect(try PermanentBackupService.validateGeneration(
            candidate.directoryURL,
            in: context.paths.internalBackupDirectoryURL
        ).manifest.schemaVersion == 7)

        let error = await restoreError(context, candidate: candidate, operation: 20)

        #expect(error == .unsupportedCandidateSchema)
        #expect(try await accountIDs(context.store) == ["restore-future-current"])
        #expect(try validGenerationCount(context) == 1)
    }

    @Test("Tampered candidate is rejected before safety Backup or replacement")
    func tamperedCandidateRejectedEarly() async throws {
        let context = try restoreContext()
        try await seedAccount(context.store, id: "restore-tamper-current", name: "Synthetic Tamper Current")
        let candidate = try await currentCandidate(
            context,
            id: "restore-tamper-candidate",
            name: "Synthetic Tamper Candidate",
            generation: 21
        )
        let database = generationDatabaseURL(candidate)
        var bytes = try Data(contentsOf: database)
        bytes[bytes.index(before: bytes.endIndex)] ^= 0x01
        try bytes.write(to: database)

        let error = await restoreError(context, candidate: candidate, operation: 21)

        #expect(error == .candidateValidationFailed)
        #expect(try await accountIDs(context.store) == ["restore-tamper-current"])
        #expect(try backupDirectoryCount(context) == 1)
    }

    @Test("Symlink raw database and generation outside configured root are rejected")
    func unsafeCandidatesRejected() async throws {
        let context = try restoreContext()
        let candidate = try await currentCandidate(
            context,
            id: "restore-unsafe-candidate",
            name: "Synthetic Unsafe Candidate",
            generation: 22
        )

        #expect(await restoreError(
            context,
            candidateURL: generationDatabaseURL(candidate),
            operation: 220
        ) == .candidateValidationFailed)

        let linkedName = "backup-20260831T000000000Z-c2000000-0000-4000-8000-000000000022"
        let linkedURL = context.paths.internalBackupDirectoryURL.appendingPathComponent(
            linkedName,
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(
            at: linkedURL,
            withDestinationURL: candidate.directoryURL
        )
        #expect(await restoreError(
            context,
            candidateURL: linkedURL,
            operation: 221
        ) == .candidateValidationFailed)

        let otherContext = try restoreContext()
        let external = try await currentCandidate(
            otherContext,
            id: "restore-other-root",
            name: "Synthetic Other Root",
            generation: 23
        )
        #expect(await restoreError(
            context,
            candidateURL: external.directoryURL,
            operation: 222
        ) == .candidateValidationFailed)
    }

    @Test("Missing and malformed manifests are rejected")
    func invalidManifestRejected() async throws {
        let missingContext = try restoreContext()
        let missing = try await currentCandidate(
            missingContext,
            id: "restore-missing-manifest",
            name: "Synthetic Missing Manifest",
            generation: 24
        )
        try FileManager.default.removeItem(at: generationManifestURL(missing))
        #expect(await restoreError(
            missingContext,
            candidateURL: missing.directoryURL,
            operation: 240
        ) == .candidateValidationFailed)

        let malformedContext = try restoreContext()
        let malformed = try await currentCandidate(
            malformedContext,
            id: "restore-malformed-manifest",
            name: "Synthetic Malformed Manifest",
            generation: 25
        )
        try Data("{not-json".utf8).write(to: generationManifestURL(malformed))
        #expect(await restoreError(
            malformedContext,
            candidateURL: malformed.directoryURL,
            operation: 250
        ) == .candidateValidationFailed)
    }

    @Test("Candidate staging digest mismatch is rejected before safety Backup")
    func candidateStagingDigestMismatch() async throws {
        let context = try restoreContext()
        try await seedAccount(context.store, id: "restore-stage-current", name: "Synthetic Stage Current")
        let candidate = try await currentCandidate(
            context,
            id: "restore-stage-candidate",
            name: "Synthetic Stage Candidate",
            generation: 26
        )
        let operations = CorruptingCandidateCopyOperations()

        let error = await restoreError(
            context,
            candidate: candidate,
            operation: 26,
            fileOperations: operations
        )

        #expect(error == .candidateStagingFailed)
        #expect(try await accountIDs(context.store) == ["restore-stage-current"])
        #expect(try validGenerationCount(context) == 1)
        #expect(try ownedStageNames(context).isEmpty)
    }

    @Test("Migration failure rolls back to the safety generation")
    func migrationFailureRollsBack() async throws {
        let context = try restoreContext()
        try await seedAccount(context.store, id: "restore-migration-old", name: "Synthetic Migration Old")
        let candidate = try migrationFailureCandidate(context, generation: 27)

        let error = await restoreError(context, candidate: candidate, operation: 27)

        #expect(error == .restoreFailedRollbackSucceeded(.migration))
        #expect(try await accountIDs(context.store) == ["restore-migration-old"])
        #expect(try await context.store.schemaVersion() == 6)
        #expect(await context.store.maintenanceState == .ready)
        #expect(!(try await accountIDs(context.store)).contains("restore-migration-bad"))
    }

    @Test("Migration rollback preserves a valid safety generation")
    func migrationRollbackSafetyRemainsValid() async throws {
        let context = try restoreContext()
        try await seedAccount(context.store, id: "restore-rollback-safe", name: "Synthetic Rollback Safe")
        let candidate = try migrationFailureCandidate(context, generation: 28)
        let safetyID = restoreUUID(10_028)

        _ = await restoreError(
            context,
            candidate: candidate,
            operation: 28,
            safetyGenerationID: safetyID
        )
        let safety = try #require(
            try PermanentBackupService.inventory(in: context.paths.internalBackupDirectoryURL)
                .validGenerations.first { $0.directoryURL.lastPathComponent.contains(safetyID.uuidString.lowercased()) }
        )

        #expect(try PermanentBackupService.validateGeneration(
            safety.directoryURL,
            in: context.paths.internalBackupDirectoryURL
        ) == safety)
        #expect(try generationAccountIDs(safety) == ["restore-rollback-safe"])
    }

    @Test("Post-Restore required-table failure triggers rollback")
    func postRestoreInvariantFailureRollsBack() async throws {
        let context = try restoreContext()
        try await seedAccount(context.store, id: "restore-invariant-old", name: "Synthetic Invariant Old")
        let candidate = try await currentCandidate(
            context,
            id: "restore-invariant-new",
            name: "Synthetic Invariant New",
            generation: 29
        )
        try mutateGeneration(candidate) { db in
            try db.execute(sql: "DROP TABLE goals")
        }
        try resignGeneration(candidate, schemaVersion: 6)
        _ = try PermanentBackupService.validateGeneration(
            candidate.directoryURL,
            in: context.paths.internalBackupDirectoryURL
        )

        let error = await restoreError(context, candidate: candidate, operation: 29)

        #expect(error == .restoreFailedRollbackSucceeded(.requiredTables))
        #expect(try await accountIDs(context.store) == ["restore-invariant-old"])
        #expect(await context.store.maintenanceState == .ready)
    }

    @Test("Rollback failure enters recovery-required and retains safety")
    func rollbackFailureIsFinite() async throws {
        let context = try restoreContext()
        try await seedAccount(context.store, id: "restore-recovery-old", name: "Synthetic Recovery Old")
        let candidate = try migrationFailureCandidate(context, generation: 30)
        let safetyID = restoreUUID(10_030)
        let operations = FailingSecondReplacementOperations()

        let error = await restoreError(
            context,
            candidate: candidate,
            operation: 30,
            safetyGenerationID: safetyID,
            fileOperations: operations
        )

        #expect(error == .rollbackFailed)
        #expect(await context.store.maintenanceState == .recoveryRequired)
        let safety = try #require(
            try PermanentBackupService.inventory(in: context.paths.internalBackupDirectoryURL)
                .validGenerations.first { $0.directoryURL.lastPathComponent.contains(safetyID.uuidString.lowercased()) }
        )
        #expect(try generationAccountIDs(safety) == ["restore-recovery-old"])
        #expect(operations.replacementCount == 2)
    }

    @Test("Owned candidate and rollback staging files are cleaned after success")
    func stagingCleanupAfterSuccess() async throws {
        let context = try restoreContext()
        let candidate = try await currentCandidate(
            context,
            id: "restore-clean-success",
            name: "Synthetic Clean Success",
            generation: 31
        )

        _ = try await performRestore(context, candidate: candidate, operation: 31)

        #expect(try ownedStageNames(context).isEmpty)
        #expect(try sidecarNames(context).isEmpty)
    }

    @Test("Owned staging files are cleaned after failed Restore and rollback")
    func stagingCleanupAfterRollback() async throws {
        let context = try restoreContext()
        let candidate = try migrationFailureCandidate(context, generation: 32)

        _ = await restoreError(context, candidate: candidate, operation: 32)

        #expect(try ownedStageNames(context).isEmpty)
        #expect(try sidecarNames(context).isEmpty)
    }

    @Test("Files outside the Permanent database parent are unchanged")
    func outsideParentSentinelUnchanged() async throws {
        let context = try restoreContext()
        let outside = context.root.appendingPathComponent("outside-owned-sentinel.txt")
        let original = Data("synthetic outside sentinel".utf8)
        try original.write(to: outside)
        let candidate = try await currentCandidate(
            context,
            id: "restore-outside-candidate",
            name: "Synthetic Outside Candidate",
            generation: 33
        )

        _ = try await performRestore(context, candidate: candidate, operation: 33)

        #expect(try Data(contentsOf: outside) == original)
    }

    @Test("Market Cache sentinel is not read copied modified or deleted")
    func marketCacheIsolation() async throws {
        let context = try restoreContext()
        try FileManager.default.createDirectory(
            at: context.paths.marketCacheDatabaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let marker = Data("synthetic market cache sentinel".utf8)
        try marker.write(to: context.paths.marketCacheDatabaseURL)
        let candidate = try await currentCandidate(
            context,
            id: "restore-cache-candidate",
            name: "Synthetic Cache Candidate",
            generation: 34
        )

        _ = try await performRestore(context, candidate: candidate, operation: 34)

        #expect(try Data(contentsOf: context.paths.marketCacheDatabaseURL) == marker)
        for generation in try PermanentBackupService.inventory(
            in: context.paths.internalBackupDirectoryURL
        ).validGenerations {
            #expect(try generationArtifactNames(generation) == Set(["aureus.sqlite", "manifest.json"]))
        }
    }

    @Test("Synthetic key-like sentinel never enters candidate safety or active Store")
    func keyLikeSentinelIsolation() async throws {
        let context = try restoreContext()
        let sentinelURL = context.root.appendingPathComponent("synthetic-key-like-sentinel.txt")
        let marker = Data("synthetic-key-like-value-not-a-credential".utf8)
        try marker.write(to: sentinelURL)
        let candidate = try await currentCandidate(
            context,
            id: "restore-key-candidate",
            name: "Synthetic Key Candidate",
            generation: 35
        )

        let result = try await performRestore(context, candidate: candidate, operation: 35)

        #expect(try Data(contentsOf: sentinelURL) == marker)
        #expect(try Data(contentsOf: generationDatabaseURL(candidate)).range(of: marker) == nil)
        let safetyURL = context.paths.internalBackupDirectoryURL.appendingPathComponent(
            result.safetyGenerationIdentity,
            isDirectory: true
        )
        #expect(try Data(contentsOf: safetyURL.appendingPathComponent("aureus.sqlite")).range(of: marker) == nil)
        #expect(try Data(contentsOf: context.paths.permanentDatabaseURL).range(of: marker) == nil)
    }

    @Test("Successful Restore retains no more than five valid generations including safety")
    func retentionAfterSuccess() async throws {
        let context = try restoreContext()
        var candidate: PermanentBackupGeneration?
        for generation in 40..<45 {
            candidate = try await currentCandidate(
                context,
                id: "restore-retention-\(generation)",
                name: "Synthetic Retention \(generation)",
                generation: generation,
                millisecondsOffset: Int64(generation)
            )
        }
        let selected = try #require(candidate)

        let result = try await performRestore(context, candidate: selected, operation: 45)
        let inventory = try PermanentBackupService.inventory(
            in: context.paths.internalBackupDirectoryURL
        )

        #expect(inventory.validGenerations.count == 5)
        #expect(inventory.validGenerations.contains {
            $0.directoryURL.lastPathComponent == result.safetyGenerationIdentity
        })
    }

    @Test("Failed Restore never prunes the required safety generation")
    func failedRestoreRetainsSafety() async throws {
        let context = try restoreContext()
        for generation in 50..<54 {
            _ = try await currentCandidate(
                context,
                id: "restore-failure-retention-\(generation)",
                name: "Synthetic Failure Retention \(generation)",
                generation: generation,
                millisecondsOffset: Int64(generation)
            )
        }
        let failed = try migrationFailureCandidate(context, generation: 54)
        let safetyID = restoreUUID(10_054)

        let error = await restoreError(
            context,
            candidate: failed,
            operation: 54,
            safetyGenerationID: safetyID
        )
        let inventory = try PermanentBackupService.inventory(
            in: context.paths.internalBackupDirectoryURL
        )

        #expect(error == .restoreFailedRollbackSucceeded(.migration))
        #expect(inventory.validGenerations.count == 5)
        #expect(inventory.validGenerations.contains {
            $0.directoryURL.lastPathComponent.contains(safetyID.uuidString.lowercased())
        })
    }

    @Test("Repeated current-schema Restore is deterministic")
    func repeatedRestoreDeterminism() async throws {
        let context = try restoreContext()
        let candidate = try await currentCandidate(
            context,
            id: "restore-repeat-candidate",
            name: "Synthetic Repeat Candidate",
            generation: 60
        )

        let first = try await performRestore(context, candidate: candidate, operation: 60)
        let firstIDs = try await accountIDs(context.store)
        let second = try await performRestore(context, candidate: candidate, operation: 61)

        #expect(first.candidateSchemaVersion == second.candidateSchemaVersion)
        #expect(first.finalSchemaVersion == second.finalSchemaVersion)
        #expect(first.migrationRan == second.migrationRan)
        #expect(first.operationCategory == second.operationCategory)
        #expect(try await accountIDs(context.store) == firstIDs)
    }

    @Test("Synchronous actor maintenance admits no reentrancy window")
    func noActorReentrancyWindow() async throws {
        let context = try restoreContext()
        let candidate = try await currentCandidate(
            context,
            id: "restore-reentrancy-candidate",
            name: "Synthetic Reentrancy Candidate",
            generation: 62
        )
        let operations = BlockingCandidateCopyOperations()
        let restoreTask = Task {
            try await performRestore(
                context,
                candidate: candidate,
                operation: 62,
                fileOperations: operations
            )
        }
        let copyStarted = await Task.detached {
            waitForSemaphore(operations.copyStarted, timeout: .now() + 2)
        }.value
        #expect(copyStarted == .success)
        let actorCallCompleted = DispatchSemaphore(value: 0)
        let actorCall = Task {
            _ = await context.store.maintenanceState
            actorCallCompleted.signal()
        }

        let actorBlocked = await Task.detached {
            waitForSemaphore(actorCallCompleted, timeout: .now() + 0.05)
        }.value
        #expect(actorBlocked == .timedOut)
        operations.allowCopyToFinish.signal()
        _ = try await restoreTask.value
        let actorResumed = await Task.detached {
            waitForSemaphore(actorCallCompleted, timeout: .now() + 2)
        }.value
        #expect(actorResumed == .success)
        _ = await actorCall.value
        #expect(await context.store.maintenanceState == .ready)
    }

    @Test("Restore results and typed errors disclose no business value or full path")
    func resultAndErrorPrivacy() async throws {
        let context = try restoreContext()
        try await seedAccount(
            context.store,
            id: "restore-private-current",
            name: "Synthetic Confidential Name 987654"
        )
        let candidate = try await currentCandidate(
            context,
            id: "restore-private-candidate",
            name: "Synthetic Candidate Confidential 123456",
            generation: 63
        )
        let result = try await performRestore(context, candidate: candidate, operation: 63)
        let resultText = String(describing: result)
        let errorText = PermanentRestoreError.rollbackFailed.localizedDescription

        for forbidden in [
            "Synthetic Confidential", "987654", "123456", context.root.path,
            candidate.directoryURL.path
        ] {
            #expect(!resultText.contains(forbidden))
            #expect(!errorText.contains(forbidden))
        }
    }

    @Test("Restore has no Provider Credential Keychain or Market Cache dependency")
    func localDependencyBoundary() async throws {
        let context = try restoreContext()
        let candidate = try await currentCandidate(
            context,
            id: "restore-local-only",
            name: "Synthetic Local Only",
            generation: 64
        )

        _ = try await performRestore(context, candidate: candidate, operation: 64)

        #expect(try await accountIDs(context.store) == ["restore-local-only"])
        #expect(!FileManager.default.fileExists(atPath: context.paths.marketCacheDatabaseURL.path))
    }

    @Test("Restore rejects a Store whose live filename is not aureus.sqlite")
    func unsafeLiveStoreRejected() async throws {
        let context = try restoreContext()
        let candidate = try await currentCandidate(
            context,
            id: "restore-unsafe-live-candidate",
            name: "Synthetic Unsafe Live Candidate",
            generation: 65
        )
        let otherURL = context.root.appendingPathComponent("Permanent/not-aureus.sqlite")
        let otherStore = try WealthStore(databaseURL: otherURL)

        do {
            _ = try await otherStore.restorePermanentBackup(
                candidate.directoryURL,
                in: context.paths.internalBackupDirectoryURL,
                appVersion: restoreTestAppVersion,
                createdAt: restoreTestInstant
            )
            Issue.record("Unsafe live Store filename must be rejected")
        } catch let error as PermanentRestoreError {
            #expect(error == .unsafeCurrentStore)
        }
        #expect(await otherStore.maintenanceState == .ready)
    }

    @Test("Release workload restores ten thousand synthetic rows within the bound")
    func stage11RestorePerformance() async throws {
        let context = try restoreContext()
        try await seedManyAccounts(
            context.store,
            prefix: "restore-perf-current",
            count: 10_000
        )
        let candidateSourceURL = context.root
            .appendingPathComponent("PerformanceCandidate", isDirectory: true)
            .appendingPathComponent("aureus.sqlite", isDirectory: false)
        let candidateStore = try WealthStore(databaseURL: candidateSourceURL)
        try await seedManyAccounts(
            candidateStore,
            prefix: "restore-perf-candidate",
            count: 10_000
        )

        let clock = ContinuousClock()
        let started = clock.now
        let candidate = try await candidateStore.createPermanentBackup(
            in: context.paths.internalBackupDirectoryURL,
            appVersion: restoreTestAppVersion,
            createdAt: UTCInstant(
                millisecondsSince1970: restoreTestInstant.millisecondsSince1970 - 1_000
            ),
            generationID: restoreUUID(70)
        )
        let result = try await performRestore(context, candidate: candidate, operation: 70)
        let restored = try await accountSummary(context.store)
        let safetyURL = context.paths.internalBackupDirectoryURL.appendingPathComponent(
            result.safetyGenerationIdentity,
            isDirectory: true
        )
        let safety = try PermanentBackupService.validateGeneration(
            safetyURL,
            in: context.paths.internalBackupDirectoryURL
        )
        let safetySummary = try generationAccountSummary(safety)
        let elapsed = started.duration(to: clock.now)
        let milliseconds = restoreMilliseconds(elapsed)

        #expect(restored.count == 10_000)
        #expect(restored.first == "restore-perf-candidate-00000")
        #expect(restored.last == "restore-perf-candidate-09999")
        #expect(safetySummary.count == 10_000)
        #expect(safetySummary.first == "restore-perf-current-00000")
        #expect(safetySummary.last == "restore-perf-current-09999")
        #expect(elapsed < .seconds(10))
        print(
            "STAGE11_RESTORE_PERF rows=10000 safety_backup_restore_validate_ms=\(milliseconds) "
                + "migration_applied=0 provider_requests=0 cache_reads=0 credential_reads=0"
        )
    }
}

private let restoreTestAppVersion = "0.1-restore-test"
private let restoreTestInstant = UTCInstant(millisecondsSince1970: 1_788_199_200_000)

private struct RestoreTestContext: Sendable {
    let root: URL
    let paths: RuntimePaths
    let store: WealthStore
}

private func restoreContext() throws -> RestoreTestContext {
    let base: URL
    if let injected = ProcessInfo.processInfo.environment["AUREUS_RESTORE_TEST_ROOT"],
       !injected.isEmpty {
        base = URL(fileURLWithPath: injected, isDirectory: true)
    } else {
        base = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("AureusTests/PermanentRestore", isDirectory: true)
    }
    let root = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let paths = RuntimePaths.temporary(root: root)
    return RestoreTestContext(
        root: root,
        paths: paths,
        store: try WealthStore(databaseURL: paths.permanentDatabaseURL)
    )
}

private func restoreUUID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "c3000000-0000-4000-8000-%012d", value))!
}

private func waitForSemaphore(
    _ semaphore: DispatchSemaphore,
    timeout: DispatchTime
) -> DispatchTimeoutResult {
    semaphore.wait(timeout: timeout)
}

private func seedAccount(_ store: WealthStore, id: String, name: String) async throws {
    try await store.insertIsolationSentinel(id: id, name: name)
}

private func seedManyAccounts(
    _ store: WealthStore,
    prefix: String,
    count: Int
) async throws {
    let queue = await store.queue
    try await queue.write { db in
        for index in 0..<count {
            try db.execute(
                sql: "INSERT INTO accounts (id, name, kind, currency_code) VALUES (?, ?, 'other', 'CNY')",
                arguments: [
                    String(format: "%@-%05d", prefix, index),
                    String(format: "Synthetic Restore Performance %05d", index)
                ]
            )
        }
    }
}

private func accountIDs(_ store: WealthStore) async throws -> [String] {
    let queue = await store.queue
    return try await queue.read { db in
        try String.fetchAll(db, sql: "SELECT id FROM accounts ORDER BY id")
    }
}

private func accountSummary(_ store: WealthStore) async throws -> (
    count: Int,
    first: String?,
    last: String?
) {
    let ids = try await accountIDs(store)
    return (ids.count, ids.first, ids.last)
}

private func currentCandidate(
    _ context: RestoreTestContext,
    id: String,
    name: String,
    generation: Int,
    millisecondsOffset: Int64 = 0
) async throws -> PermanentBackupGeneration {
    let sourceURL = context.root
        .appendingPathComponent("CandidateSources", isDirectory: true)
        .appendingPathComponent("candidate-\(generation)", isDirectory: true)
        .appendingPathComponent("aureus.sqlite", isDirectory: false)
    let sourceStore = try WealthStore(databaseURL: sourceURL)
    try await seedAccount(sourceStore, id: id, name: name)
    return try await sourceStore.createPermanentBackup(
        in: context.paths.internalBackupDirectoryURL,
        appVersion: restoreTestAppVersion,
        createdAt: UTCInstant(
            millisecondsSince1970: restoreTestInstant.millisecondsSince1970
                - 100_000 + millisecondsOffset
        ),
        generationID: restoreUUID(generation)
    )
}

private func legacyCandidate(
    _ context: RestoreTestContext,
    version: Int,
    generation: Int
) throws -> PermanentBackupGeneration {
    let sourceURL = context.root
        .appendingPathComponent("LegacySources", isDirectory: true)
        .appendingPathComponent("legacy-v\(version)", isDirectory: true)
        .appendingPathComponent("aureus.sqlite", isDirectory: false)
    let queue = try DatabaseQueueFactory.open(at: sourceURL)
    let migrator = DatabaseMigrations.permanentMigrator()
    try migrator.migrate(queue, upTo: restoreMigrationIdentifier(version))
    try queue.write { db in
        try db.execute(
            sql: "INSERT INTO accounts (id, name, kind, currency_code) VALUES (?, ?, 'other', 'CNY')",
            arguments: ["restore-legacy-v\(version)", "Synthetic Legacy v\(version)"]
        )
    }
    let result = try PermanentBackupService.create(
        from: queue,
        in: context.paths.internalBackupDirectoryURL,
        appVersion: restoreTestAppVersion,
        createdAt: UTCInstant(
            millisecondsSince1970: restoreTestInstant.millisecondsSince1970 - 90_000 + Int64(version)
        ),
        generationID: restoreUUID(generation)
    )
    try queue.close()
    return result
}

private func migrationFailureCandidate(
    _ context: RestoreTestContext,
    generation: Int
) throws -> PermanentBackupGeneration {
    let sourceURL = context.root
        .appendingPathComponent("FailureSources", isDirectory: true)
        .appendingPathComponent("failure-\(generation)", isDirectory: true)
        .appendingPathComponent("aureus.sqlite", isDirectory: false)
    let queue = try DatabaseQueueFactory.open(at: sourceURL)
    let migrator = DatabaseMigrations.permanentMigrator()
    try migrator.migrate(queue, upTo: DatabaseMigrations.permanentV1)
    try queue.write { db in
        try db.execute(
            sql: "INSERT INTO accounts (id, name, kind, currency_code) VALUES ('restore-migration-bad', 'Synthetic Migration Bad', 'other', 'CNY')"
        )
        try db.execute(
            sql: "INSERT INTO asset_containers (id, account_id, name, kind) VALUES ('restore-invalid-container', 'restore-migration-bad', 'Synthetic Invalid Container', 'unsupported-kind')"
        )
    }
    let result = try PermanentBackupService.create(
        from: queue,
        in: context.paths.internalBackupDirectoryURL,
        appVersion: restoreTestAppVersion,
        createdAt: UTCInstant(
            millisecondsSince1970: restoreTestInstant.millisecondsSince1970 - 80_000 + Int64(generation)
        ),
        generationID: restoreUUID(generation)
    )
    try queue.close()
    return result
}

private func restoreMigrationIdentifier(_ version: Int) -> String {
    switch version {
    case 1: DatabaseMigrations.permanentV1
    case 2: DatabaseMigrations.permanentV2
    case 3: DatabaseMigrations.permanentV3
    case 4: DatabaseMigrations.permanentV4
    case 5: DatabaseMigrations.permanentV5
    default: preconditionFailure("Synthetic Restore fixture version out of range")
    }
}

private func performRestore(
    _ context: RestoreTestContext,
    candidate: PermanentBackupGeneration,
    operation: Int,
    safetyGenerationID: UUID? = nil,
    fileOperations: any PermanentRestoreFileOperations = LocalPermanentRestoreFileOperations()
) async throws -> PermanentRestoreResult {
    try await context.store.restorePermanentBackup(
        candidate.directoryURL,
        in: context.paths.internalBackupDirectoryURL,
        appVersion: restoreTestAppVersion,
        createdAt: UTCInstant(
            millisecondsSince1970: restoreTestInstant.millisecondsSince1970 + Int64(operation)
        ),
        operationID: restoreUUID(1_000 + operation),
        safetyGenerationID: safetyGenerationID ?? restoreUUID(10_000 + operation),
        fileOperations: fileOperations
    )
}

private func restoreError(
    _ context: RestoreTestContext,
    candidate: PermanentBackupGeneration,
    operation: Int,
    safetyGenerationID: UUID? = nil,
    fileOperations: any PermanentRestoreFileOperations = LocalPermanentRestoreFileOperations()
) async -> PermanentRestoreError? {
    await restoreError(
        context,
        candidateURL: candidate.directoryURL,
        operation: operation,
        safetyGenerationID: safetyGenerationID,
        fileOperations: fileOperations
    )
}

private func restoreError(
    _ context: RestoreTestContext,
    candidateURL: URL,
    operation: Int,
    safetyGenerationID: UUID? = nil,
    fileOperations: any PermanentRestoreFileOperations = LocalPermanentRestoreFileOperations()
) async -> PermanentRestoreError? {
    do {
        _ = try await context.store.restorePermanentBackup(
            candidateURL,
            in: context.paths.internalBackupDirectoryURL,
            appVersion: restoreTestAppVersion,
            createdAt: UTCInstant(
                millisecondsSince1970: restoreTestInstant.millisecondsSince1970 + Int64(operation)
            ),
            operationID: restoreUUID(1_000 + operation),
            safetyGenerationID: safetyGenerationID ?? restoreUUID(10_000 + operation),
            fileOperations: fileOperations
        )
        return nil
    } catch let error as PermanentRestoreError {
        return error
    } catch {
        return .candidateValidationFailed
    }
}

private func generationDatabaseURL(_ generation: PermanentBackupGeneration) -> URL {
    generation.directoryURL.appendingPathComponent("aureus.sqlite", isDirectory: false)
}

private func generationManifestURL(_ generation: PermanentBackupGeneration) -> URL {
    generation.directoryURL.appendingPathComponent("manifest.json", isDirectory: false)
}

private func generationAccountIDs(_ generation: PermanentBackupGeneration) throws -> [String] {
    var configuration = Configuration()
    configuration.readonly = true
    let queue = try DatabaseQueue(
        path: generationDatabaseURL(generation).path,
        configuration: configuration
    )
    defer { try? queue.close() }
    return try queue.read { db in
        try String.fetchAll(db, sql: "SELECT id FROM accounts ORDER BY id")
    }
}

private func generationAccountSummary(
    _ generation: PermanentBackupGeneration
) throws -> (count: Int, first: String?, last: String?) {
    let ids = try generationAccountIDs(generation)
    return (ids.count, ids.first, ids.last)
}

private func generationFingerprint(
    _ generation: PermanentBackupGeneration
) throws -> (database: PermanentBackupFileDigest, manifest: Data) {
    (
        try PermanentBackupService.streamingDigest(of: generationDatabaseURL(generation)),
        try Data(contentsOf: generationManifestURL(generation))
    )
}

private func mutateGeneration(
    _ generation: PermanentBackupGeneration,
    mutation: (Database) throws -> Void
) throws {
    let queue = try DatabaseQueueFactory.open(at: generationDatabaseURL(generation))
    try queue.write(mutation)
    try queue.close()
}

private func resignGeneration(
    _ generation: PermanentBackupGeneration,
    schemaVersion: Int
) throws {
    let digest = try PermanentBackupService.streamingDigest(of: generationDatabaseURL(generation))
    let manifest = PermanentBackupManifest(
        backupFormatVersion: 1,
        appVersion: generation.manifest.appVersion,
        schemaVersion: schemaVersion,
        createdAt: generation.manifest.createdAt,
        databaseByteCount: digest.byteCount,
        databaseSHA256: digest.sha256
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(manifest)
    data.append(0x0A)
    try data.write(to: generationManifestURL(generation), options: .atomic)
}

private func validGenerationCount(_ context: RestoreTestContext) throws -> Int {
    try PermanentBackupService.inventory(
        in: context.paths.internalBackupDirectoryURL
    ).validGenerations.count
}

private func backupDirectoryCount(_ context: RestoreTestContext) throws -> Int {
    try FileManager.default.contentsOfDirectory(
        at: context.paths.internalBackupDirectoryURL,
        includingPropertiesForKeys: nil
    ).count
}

private func generationArtifactNames(
    _ generation: PermanentBackupGeneration
) throws -> Set<String> {
    Set(try FileManager.default.contentsOfDirectory(
        at: generation.directoryURL,
        includingPropertiesForKeys: nil
    ).map(\.lastPathComponent))
}

private func ownedStageNames(_ context: RestoreTestContext) throws -> [String] {
    let parent = context.paths.permanentDatabaseURL.deletingLastPathComponent()
    return try FileManager.default.contentsOfDirectory(
        at: parent,
        includingPropertiesForKeys: nil
    ).map(\.lastPathComponent).filter { $0.hasPrefix(".restore-") }
}

private func sidecarNames(_ context: RestoreTestContext) throws -> [String] {
    let parent = context.paths.permanentDatabaseURL.deletingLastPathComponent()
    return try FileManager.default.contentsOfDirectory(
        at: parent,
        includingPropertiesForKeys: nil
    ).map(\.lastPathComponent).filter {
        $0 == "aureus.sqlite-wal" || $0 == "aureus.sqlite-shm"
    }
}

private func restoreMilliseconds(_ duration: Duration) -> Int64 {
    let components = duration.components
    return components.seconds * 1_000
        + Int64(components.attoseconds / 1_000_000_000_000_000)
}

private final class CorruptingCandidateCopyOperations: PermanentRestoreFileOperations, @unchecked Sendable {
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

private final class FailingSecondReplacementOperations: PermanentRestoreFileOperations, @unchecked Sendable {
    private let live = LocalPermanentRestoreFileOperations()
    private let lock = NSLock()
    private var count = 0

    var replacementCount: Int {
        lock.withLock { count }
    }

    func copyValidatedDatabase(from sourceURL: URL, to stagingURL: URL) throws {
        try live.copyValidatedDatabase(from: sourceURL, to: stagingURL)
    }

    func atomicallyReplaceDatabase(at databaseURL: URL, with stagingURL: URL) throws {
        let current = lock.withLock { () -> Int in
            count += 1
            return count
        }
        if current == 2 {
            throw CocoaError(.fileWriteUnknown)
        }
        try live.atomicallyReplaceDatabase(at: databaseURL, with: stagingURL)
    }
}

private final class BlockingCandidateCopyOperations: PermanentRestoreFileOperations, @unchecked Sendable {
    let copyStarted = DispatchSemaphore(value: 0)
    let allowCopyToFinish = DispatchSemaphore(value: 0)
    private let live = LocalPermanentRestoreFileOperations()

    func copyValidatedDatabase(from sourceURL: URL, to stagingURL: URL) throws {
        try live.copyValidatedDatabase(from: sourceURL, to: stagingURL)
        copyStarted.signal()
        allowCopyToFinish.wait()
    }

    func atomicallyReplaceDatabase(at databaseURL: URL, with stagingURL: URL) throws {
        try live.atomicallyReplaceDatabase(at: databaseURL, with: stagingURL)
    }
}
