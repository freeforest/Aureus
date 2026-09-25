import Foundation
import GRDB
import Testing
@testable import Aureus

@Suite("Process-local dataset ownership", .serialized)
struct PermanentDatasetAccessTests {
    @Test("Core physical and linked aliases support absent parents, sharing and reopen", arguments: [false, true])
    func corePathCompatibility(_ useLink: Bool) async throws {
        let f = try OwnerFixture(); defer { f.remove() }
        let alias = f.root.appendingPathComponent("core-alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: f.root)
        let physical = f.root.appendingPathComponent("New/Nested/aureus.sqlite")
        let selected = useLink ? alias.appendingPathComponent("New/Nested/aureus.sqlite") : physical.resolvingSymlinksInPath()
        var first: WealthStore? = try WealthStore(databaseURL: selected)
        var second: WealthStore? = try WealthStore(databaseURL: physical)
        try await first!.insertIsolationSentinel(id: "synthetic-core-path", name: "Synthetic Core Path")
        #expect(try await second!.isolationSentinels() == ["Synthetic Core Path"])
        #expect(throws: EvidenceError.ownerConflict) {
            _ = try WealthStore(databaseURL: physical, evidenceConfiguration: f.configuration)
        }
        weak var released = first, releasedSecond = second
        first = nil; second = nil
        try #require(released == nil && releasedSecond == nil)
        var owner: WealthStore? = try WealthStore(databaseURL: physical, evidenceConfiguration: f.configuration)
        #expect(throws: EvidenceError.ownerConflict) { _ = try WealthStore(databaseURL: selected) }
        weak var releasedOwner = owner; owner = nil; try #require(releasedOwner == nil)
        let reopened = try WealthStore(databaseURL: selected)
        #expect(try await reopened.isolationSentinels() == ["Synthetic Core Path"])
    }

    @Test("Core sharing remains allowed; Evidence ownership conflicts in both directions")
    func bidirectionalConflict() throws {
        let f = try OwnerFixture(); defer { f.remove() }
        var core: WealthStore? = try WealthStore(databaseURL: f.database)
        var anotherCore: WealthStore? = try WealthStore(databaseURL: f.database)
        #expect(throws: EvidenceError.ownerConflict) { _ = try f.open() }
        weak var weakCore = core, weakOther = anotherCore
        core = nil; anotherCore = nil
        try #require(weakCore == nil && weakOther == nil)
        var owner: WealthStore? = try f.open()
        #expect(throws: EvidenceError.ownerConflict) { _ = try WealthStore(databaseURL: f.database) }
        #expect(throws: EvidenceError.ownerConflict) { _ = try f.open() }
        weak var weakOwner = owner; owner = nil; try #require(weakOwner == nil)
        _ = try WealthStore(databaseURL: f.database)
    }

    @Test("New database namespace remains exclusive after creation and empty Restore")
    func creationAndReplacement() async throws {
        let f = try OwnerFixture(); defer { f.remove() }
        let owner = try f.open()
        let instant = UTCInstant(millisecondsSince1970: 1_800_000_000_000)
        let generation = try await owner.createPermanentBackup(in: f.backups, appVersion: "synthetic", createdAt: instant)
        _ = try await owner.restorePermanentBackup(generation.directoryURL, in: f.backups, appVersion: "synthetic", createdAt: instant)
        #expect(throws: EvidenceError.ownerConflict) { _ = try WealthStore(databaseURL: f.database) }
        #expect(throws: EvidenceError.ownerConflict) { _ = try f.open() }
        #expect(try await owner.schemaVersion() == 9)
    }

    @Test("Shared roots, hard-linked databases and symbolic roots are refused")
    func aliases() throws {
        let f = try OwnerFixture(); defer { f.remove() }
        let owner = try f.open()
        defer { withExtendedLifetime(owner) {} }
        #expect(throws: EvidenceError.ownerConflict) {
            _ = try WealthStore(databaseURL: f.root.appendingPathComponent("Other/aureus.sqlite"), evidenceConfiguration: f.configuration)
        }
        let hard = f.root.appendingPathComponent("hard.sqlite")
        try FileManager.default.linkItem(at: f.database, to: hard)
        #expect(throws: EvidenceError.ownerConflict) { _ = try WealthStore(databaseURL: hard) }
        let symbolic = f.root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: symbolic, withDestinationURL: f.managed)
        #expect(throws: EvidenceError.unsafeRoot) {
            _ = try WealthStore(databaseURL: f.root.appendingPathComponent("Other/aureus.sqlite"), evidenceConfiguration: .init(root: symbolic, protectedPaths: []))
        }
    }

    @Test("Initialization failure releases registration, and unrelated datasets remain independent")
    func failureReleaseAndIndependence() throws {
        let first = try OwnerFixture(), second = try OwnerFixture()
        defer { first.remove(); second.remove() }
        try FileManager.default.createDirectory(at: first.database.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("synthetic invalid database".utf8).write(to: first.database)
        #expect(throws: (any Error).self) { _ = try first.open() }
        try FileManager.default.removeItem(at: first.database)
        let a = try first.open(), b = try second.open()
        withExtendedLifetime((a, b)) {}
    }

    @Test("Unknown root artifacts block format1 without reading or removing their contents")
    func unknownArtifacts() async throws {
        let f = try OwnerFixture(); defer { f.remove() }
        let owner = try f.open()
        let instant = UTCInstant(millisecondsSince1970: 1_800_000_000_000)
        let clean = try await owner.createPermanentBackup(in: f.backups, appVersion: "synthetic", createdAt: instant)
        let unknown = f.managed.appendingPathComponent("unknown-synthetic")
        try Data([1, 2, 3]).write(to: unknown)
        await #expect(throws: EvidenceError.legacyFormatUnsupported) {
            _ = try await owner.createPermanentBackup(in: f.backups, appVersion: "synthetic", createdAt: UTCInstant(millisecondsSince1970: 1_800_000_000_000))
        }
        #expect(try Data(contentsOf: unknown) == Data([1, 2, 3]))
        await #expect(throws: PermanentRestoreError.evidenceRequiresCompleteRestore) {
            _ = try await owner.restorePermanentBackup(clean.directoryURL, in: f.backups, appVersion: "synthetic", createdAt: instant)
        }
        await #expect(throws: PermanentExternalRestoreError.evidenceRequiresCompleteRestore) {
            _ = try await owner.restoreExternalPermanentBackup(clean.directoryURL, configuration: .init(internalBackupRootURL: f.backups, permanentDatabaseURL: f.database, marketCacheDatabaseURL: f.root.appendingPathComponent("Cache/cache.sqlite"), additionalProtectedSourceRoots: []), appVersion: "synthetic", createdAt: instant)
        }
        #expect(try PermanentBackupService.inventory(in: f.backups).validGenerations == [clean])
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.database.deletingLastPathComponent().path).allSatisfy { !$0.hasPrefix(".restore-") })
    }

    @Test("Synchronous import queues Core and automatic Dashboard writes behind durable commit")
    func queuedWriters() async throws {
        let f = try OwnerFixture(); defer { f.remove() }
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        var configuration = f.configuration
        configuration.files.checkpoint = { point in
            if point == .beforePublish {
                entered.signal()
                guard release.wait(timeout: .now() + 20) == .success else { throw ManagedEvidenceFailure.cancelled }
            }
        }
        let owner = try WealthStore(databaseURL: f.database, evidenceConfiguration: configuration)
        let context = try LedgerTestContext.make()
        try await owner.createWealthContainer(context.source)
        let entry = try context.entry(kind: .income)
        try await owner.createLedgerEntry(entry)
        let queue = try DatabaseQueueFactory.open(at: f.database); defer { try? queue.close() }
        // Actual database assertions detect any interleaving at the write boundary.
        try await queue.write { db in
            for table in ["accounts", "snapshots"] {
                try db.execute(sql: "CREATE TRIGGER ordered_\(table) BEFORE INSERT ON \(table) WHEN EXISTS(SELECT 1 FROM evidence_import_operations WHERE state != 'committed') BEGIN SELECT RAISE(ABORT, 'synthetic interleaving'); END")
            }
        }
        let source = f.root.appendingPathComponent("synthetic.bin")
        try Data([1,2,3]).write(to: source)
        let importing = Task { try await owner.importEvidence(source: source, operationID: UUID(), target: .ledger(entry.id)) }
        let reached = await Task.detached { ownerWait(entered) }.value
        guard reached == .success else {
            release.signal(); _ = try await importing.value
            Issue.record("Import did not reach the publication barrier"); return
        }
        let offered = DispatchSemaphore(value: 0)
        let core = Task {
            offered.signal()
            try await owner.insertIsolationSentinel(id: "synthetic-queued", name: "Synthetic Queued")
        }
        let dashboard = Task {
            offered.signal()
            return try await owner.readDashboardSource(for: context.date, createdAt: context.instant)
        }
        let both = await Task.detached { ownerWait(offered) == .success && ownerWait(offered) == .success }.value
        #expect(both)
        #expect(try await queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM snapshots") } == 0)
        release.signal()
        #expect(try await importing.value.availability == .available)
        try await core.value
        _ = try await dashboard.value
        #expect(try await queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM snapshots WHERE is_complete = 1") } == 1)
        #expect(try await owner.isolationSentinels() == ["Synthetic Queued"])
    }
}

private func ownerWait(_ semaphore: DispatchSemaphore) -> DispatchTimeoutResult {
    semaphore.wait(timeout: .now() + 20)
}

private struct OwnerFixture {
    let root: URL, database: URL, managed: URL, backups: URL
    init() throws {
        root = try temporaryDirectory()
        database = root.appendingPathComponent("Permanent/aureus.sqlite")
        managed = root.appendingPathComponent("Materials")
        backups = root.appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: false)
    }
    var configuration: EvidenceConfiguration { .init(root: managed, protectedPaths: [backups]) }
    func open() throws -> WealthStore { try WealthStore(databaseURL: database, evidenceConfiguration: configuration) }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
