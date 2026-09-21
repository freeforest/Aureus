import Foundation
import Testing
@testable import Aureus

@Suite("Process-local dataset ownership", .serialized)
struct PermanentDatasetAccessTests {
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
        #expect(try await owner.schemaVersion() == 7)
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
        let unknown = f.managed.appendingPathComponent("unknown-synthetic")
        try Data([1, 2, 3]).write(to: unknown)
        await #expect(throws: EvidenceError.legacyFormatUnsupported) {
            _ = try await owner.createPermanentBackup(in: f.backups, appVersion: "synthetic", createdAt: UTCInstant(millisecondsSince1970: 1_800_000_000_000))
        }
        #expect(try Data(contentsOf: unknown) == Data([1, 2, 3]))
        #expect(!FileManager.default.fileExists(atPath: f.backups.path))
    }
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
