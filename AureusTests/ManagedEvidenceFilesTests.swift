import Foundation
import CryptoKit
import Darwin
import Testing
@testable import Aureus

@Suite("Managed original files", .serialized)
struct ManagedEvidenceFilesTests {
    @Test("Initialization is inert; exact text, binary and empty copies use bounded chunks")
    func exactCopies() throws {
        let f = try EvidenceFixture()
        defer { f.remove() }
        let missing = f.root.appendingPathComponent("not-created")
        _ = ManagedEvidenceFiles(root: missing)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        for bytes in [Data(), Data("synthetic 文本\n".utf8), Data((0..<257).map { UInt8($0 % 256) })] {
            let source = try f.source(bytes)
            let identity = try FileManager.default.attributesOfItem(atPath: source.path)[.systemFileNumber] as? NSNumber
            let chunks = EvidenceBox(0)
            var config = f.config
            config.checkpoint = { if $0 == .copiedChunk { chunks.change { $0 += 1 } } }
            let service = ManagedEvidenceFiles(root: f.managed, configuration: config)
            let result = try service.copy(source: source)
            #expect(result.originalFilename == source.lastPathComponent)
            #expect(result.relativeReference == result.id.uuidString.lowercased() + ".original")
            #expect(result.byteCount == Int64(bytes.count))
            #expect(result.sha256 == evidenceHash(bytes))
            #expect(result.copiedAt == Date(timeIntervalSince1970: 100))
            #expect(chunks.value == (bytes.count + 6) / 7)
            #expect(try Data(contentsOf: f.file(result)) == bytes)
            #expect(try Data(contentsOf: source) == bytes)
            #expect(try FileManager.default.attributesOfItem(atPath: source.path)[.systemFileNumber] as? NSNumber == identity)
            try service.validate(result)
        }
    }

    @Test("Saved reference survives source rename, move, deletion and service reconstruction")
    func independentAndReopened() throws {
        let f = try EvidenceFixture()
        defer { f.remove() }
        let bytes = Data("independent synthetic original".utf8)
        let source = try f.source(bytes)
        let result = try ManagedEvidenceFiles(root: f.managed).copy(source: source)
        let renamed = f.root.appendingPathComponent("renamed")
        try FileManager.default.moveItem(at: source, to: renamed)
        try ManagedEvidenceFiles(root: f.managed).validate(result)
        let folder = f.root.appendingPathComponent("moved")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let moved = folder.appendingPathComponent("original")
        try FileManager.default.moveItem(at: renamed, to: moved)
        try ManagedEvidenceFiles(root: f.managed).validate(result)
        try FileManager.default.removeItem(at: moved)
        try ManagedEvidenceFiles(root: f.managed).validate(result)
        #expect(try Data(contentsOf: f.file(result)) == bytes)
    }

    @Test("Same names, identical content, case and Unicode variants receive independent identities")
    func distinctIdentities() throws {
        let f = try EvidenceFixture()
        defer { f.remove() }
        let service = ManagedEvidenceFiles(root: f.managed)
        var results: [ManagedEvidenceFile] = []
        for (i, name) in ["same", "same", "SAME", "é", "e\u{301}", "same"].enumerated() {
            let bytes = Data((i == 5 ? "0" : String(i)).utf8)
            let result = try service.copy(source: f.source(bytes, name: name))
            results.append(result)
            #expect(try Data(contentsOf: f.file(result)) == bytes)
        }
        #expect(Set(results.map(\.id)).count == 6)
        for r in results { try service.validate(r) }
    }

    @Test("Existing final or staging targets are never overwritten or removed")
    func collisions() throws {
        for staged in [false, true] {
            let f = try EvidenceFixture()
            defer { f.remove() }
            let id = UUID()
            let name = staged ? "." + id.uuidString.lowercased() + ".pending" : id.uuidString.lowercased() + ".original"
            let target = f.managed.appendingPathComponent(name)
            try Data("keep".utf8).write(to: target)
            var config = f.config
            config.makeID = { id }
            let error = try evidenceFailure { try ManagedEvidenceFiles(root: f.managed, configuration: config).copy(source: f.source(Data([1, 2]))) }
            #expect(error.reason == .collision)
            #expect(error.artifact == nil)
            #expect(try Data(contentsOf: target) == Data("keep".utf8))
            #expect(try FileManager.default.contentsOfDirectory(atPath: f.managed.path) == [name])
        }
    }

    @Test("Source links, linked parents, directory, FIFO and non-file URLs are rejected")
    func unsafeSources() throws {
        let f = try EvidenceFixture()
        defer { f.remove() }
        let source = try f.source(Data("sentinel".utf8))
        let link = f.root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let parentLink = f.root.appendingPathComponent("parent-link")
        try FileManager.default.createSymbolicLink(at: parentLink, withDestinationURL: source.deletingLastPathComponent())
        let fifo = f.root.appendingPathComponent("pipe")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        for url in [link, parentLink.appendingPathComponent(source.lastPathComponent), f.root, fifo, URL(string: "https://example.invalid/file")!] {
            _ = try evidenceFailure { try ManagedEvidenceFiles(root: f.managed).copy(source: url) }
        }
        #expect(try Data(contentsOf: source) == Data("sentinel".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.managed.path).isEmpty)
    }

    @Test("Root links, final links and malformed internal references never follow the sentinel")
    func unsafeTargetsAndReferences() throws {
        let f = try EvidenceFixture()
        defer { f.remove() }
        let source = try f.source(Data("sentinel".utf8))
        let rootLink = f.root.appendingPathComponent("root-link")
        try FileManager.default.createSymbolicLink(at: rootLink, withDestinationURL: f.managed)
        #expect(try evidenceFailure { try ManagedEvidenceFiles(root: rootLink).copy(source: source) }.reason == .unsafePath)
        let service = ManagedEvidenceFiles(root: f.managed)
        let result = try service.copy(source: source)
        for bad in ["../sentinel", "/private/tmp/sentinel", result.relativeReference + "/../x", result.relativeReference.uppercased()] {
            let invalid = ManagedEvidenceFile(id: result.id, originalFilename: "display", relativeReference: bad, byteCount: result.byteCount, sha256: result.sha256, copiedAt: result.copiedAt)
            #expect(try evidenceFailure { try service.validate(invalid) }.reason == .unsafePath)
        }
        try FileManager.default.removeItem(at: f.file(result))
        try FileManager.default.createSymbolicLink(at: f.file(result), withDestinationURL: source)
        #expect(try evidenceFailure { try service.validate(result) }.reason == .unsafePath)
        var config = f.config
        config.makeID = { result.id }
        #expect(try evidenceFailure { try ManagedEvidenceFiles(root: f.managed, configuration: config).copy(source: source) }.reason == .collision)
        #expect(try Data(contentsOf: source) == Data("sentinel".utf8))
    }

    @Test("Replacing a root parent cannot redirect writes or cleanup")
    func replacedParent() throws {
        let f = try EvidenceFixture()
        defer { f.remove() }
        let source = try f.source(Data(repeating: 3, count: 40))
        let moved = f.root.appendingPathComponent("old-managed")
        let outside = f.root.appendingPathComponent("sentinel-dir")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let sentinel = outside.appendingPathComponent("keep")
        try Data([9]).write(to: sentinel)
        let once = EvidenceBox(false)
        var config = f.config
        config.checkpoint = { point in
            if point == .copiedChunk && !once.value {
                once.change { $0 = true }
                try FileManager.default.moveItem(at: f.managed, to: moved)
                try FileManager.default.createSymbolicLink(at: f.managed, withDestinationURL: outside)
            }
        }
        #expect(try evidenceFailure { try ManagedEvidenceFiles(root: f.managed, configuration: config).copy(source: source) }.reason == .unsafePath)
        #expect(try FileManager.default.contentsOfDirectory(atPath: moved.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path) == ["keep"])
        #expect(try Data(contentsOf: sentinel) == Data([9]))
    }

    @Test("Ordinary source edit, replacement, truncation and growth are detected")
    func sourceChanges() throws {
        for variant in 0..<4 {
            let f = try EvidenceFixture()
            defer { f.remove() }
            let source = try f.source(Data(repeating: 1, count: 40))
            let once = EvidenceBox(false)
            var config = f.config
            config.checkpoint = { point in
                if point == .copiedChunk && !once.value {
                    once.change { $0 = true }
                    if variant == 1 {
                        try FileManager.default.removeItem(at: source)
                        try Data(repeating: 2, count: 40).write(to: source)
                    } else {
                        let h = try FileHandle(forWritingTo: source)
                        defer { try? h.close() }
                        if variant == 2 { try h.truncate(atOffset: 0) }
                        else if variant == 3 { try h.seekToEnd(); try h.write(contentsOf: Data([2])) }
                        else { try h.write(contentsOf: Data([2])) }
                    }
                }
            }
            #expect(try evidenceFailure { try ManagedEvidenceFiles(root: f.managed, configuration: config).copy(source: source) }.reason == .sourceChanged)
            #expect(try FileManager.default.contentsOfDirectory(atPath: f.managed.path).isEmpty)
        }
    }

    @Test("Corrupt, truncated and absent managed bytes cannot validate")
    func damagedCopies() throws {
        let f = try EvidenceFixture()
        defer { f.remove() }
        let service = ManagedEvidenceFiles(root: f.managed)
        for variant in 0..<3 {
            let result = try service.copy(source: f.source(Data([1, 2, 3])))
            if variant == 0 { try Data([3, 2, 1]).write(to: f.file(result)) }
            else if variant == 1 { try Data([1]).write(to: f.file(result)) }
            else { try FileManager.default.removeItem(at: f.file(result)) }
            _ = try evidenceFailure { try service.validate(result) }
        }
    }

    @Test("Initial and actual byte limits apply, including growth after open")
    func sizeBounds() throws {
        let f = try EvidenceFixture()
        defer { f.remove() }
        var config = f.config
        config.maximumBytes = 14
        let service = ManagedEvidenceFiles(root: f.managed, configuration: config)
        _ = try service.copy(source: f.source(Data(repeating: 1, count: 14)))
        #expect(try evidenceFailure { try service.copy(source: f.source(Data(repeating: 1, count: 15))) }.reason == .tooLarge)
        let source = try f.source(Data(repeating: 1, count: 14))
        let once = EvidenceBox(false)
        config.checkpoint = { point in
            if point == .copiedChunk && !once.value {
                once.change { $0 = true }
                let h = try FileHandle(forWritingTo: source)
                try h.seekToEnd()
                try h.write(contentsOf: Data([1]))
                try h.close()
            }
        }
        #expect(try evidenceFailure { try ManagedEvidenceFiles(root: f.managed, configuration: config).copy(source: source) }.reason == .tooLarge)
        config.chunkBytes = 1_048_577
        #expect(try evidenceFailure { try ManagedEvidenceFiles(root: f.managed, configuration: config).copy(source: source) }.reason == .invalidConfiguration)
    }

    @Test("Cancellation before start, within copy and before commit cleans only owned staging")
    func cancellations() throws {
        for boundary in [ManagedEvidenceIOPoint.openedSource, .copiedChunk, .beforePublish] {
            let f = try EvidenceFixture()
            defer { f.remove() }
            let flag = EvidenceBox(false)
            var config = f.config
            config.checkpoint = { if $0 == boundary { flag.change { $0 = true } } }
            let source = try f.source(Data(repeating: 4, count: 30))
            let sentinel = f.managed.appendingPathComponent(".unknown.pending")
            try Data([8]).write(to: sentinel)
            let service = ManagedEvidenceFiles(root: f.managed, configuration: config)
            #expect(try evidenceFailure { try service.copy(source: source, cancelled: { flag.value }) }.reason == .cancelled)
            #expect(try FileManager.default.contentsOfDirectory(atPath: f.managed.path) == [".unknown.pending"])
            #expect(try Data(contentsOf: source) == Data(repeating: 4, count: 30))
            #expect(try Data(contentsOf: sentinel) == Data([8]))
            #expect(try evidenceFailure { try service.copy(source: source, cancelled: { true }) }.reason == .cancelled)
        }
    }

    @Test("Read, write, close and publication failures retain source and unrelated files")
    func ioFailures() throws {
        for (boundary, failure) in [(ManagedEvidenceIOPoint.beforeRead, ManagedEvidenceFailure.readFailed), (.beforeWrite, .writeFailed), (.beforeClose, .closeFailed), (.beforePublish, .publishFailed)] {
            let f = try EvidenceFixture()
            defer { f.remove() }
            let source = try f.source(Data(repeating: 6, count: 30))
            let existing = try ManagedEvidenceFiles(root: f.managed).copy(source: source)
            var config = f.config
            config.checkpoint = { if $0 == boundary { throw failure } }
            let error = try evidenceFailure { try ManagedEvidenceFiles(root: f.managed, configuration: config).copy(source: source) }
            #expect(error.reason == failure)
            #expect(error.artifact == nil)
            #expect(try Data(contentsOf: source) == Data(repeating: 6, count: 30))
            try ManagedEvidenceFiles(root: f.managed).validate(existing)
            #expect(try FileManager.default.contentsOfDirectory(atPath: f.managed.path) == [existing.relativeReference])
        }
    }

    @Test("Cleanup failure reports retained owned staging without deleting unknown artifacts")
    func cleanupFailure() throws {
        let f = try EvidenceFixture()
        defer { f.remove() }
        var config = f.config
        config.checkpoint = {
            if $0 == .beforeWrite { throw ManagedEvidenceFailure.writeFailed }
            if $0 == .beforeCleanup { throw ManagedEvidenceFailure.cleanupFailed }
        }
        let error = try evidenceFailure { try ManagedEvidenceFiles(root: f.managed, configuration: config).copy(source: f.source(Data([1]))) }
        let retained = try #require(error.artifact)
        #expect(retained.state == .stagingRetained)
        #expect(error.reason == .writeFailed)
        #expect(FileManager.default.fileExists(atPath: f.managed.appendingPathComponent(retained.relativeReference).path))
    }

    @Test("Replaced staging is retained as unknown, never deleted by operation cleanup")
    func replacedStaging() throws {
        let f = try EvidenceFixture()
        defer { f.remove() }
        let id = UUID()
        let stage = f.managed.appendingPathComponent("." + id.uuidString.lowercased() + ".pending")
        let ownedElsewhere = f.managed.appendingPathComponent("moved-owned")
        var config = f.config
        config.makeID = { id }
        config.checkpoint = { point in
            if point == .beforeCleanup {
                try FileManager.default.moveItem(at: stage, to: ownedElsewhere)
                try Data([9]).write(to: stage)
            }
            if point == .beforeWrite { throw ManagedEvidenceFailure.writeFailed }
        }
        let error = try evidenceFailure { try ManagedEvidenceFiles(root: f.managed, configuration: config).copy(source: f.source(Data([1]))) }
        #expect(error.artifact?.state == .ownershipUnconfirmed)
        #expect(try Data(contentsOf: stage) == Data([9]))
        #expect(FileManager.default.fileExists(atPath: ownedElsewhere.path))
    }

    @Test("Missing staging cannot be reported as a verified retained owned artifact")
    func missingStagingOwnership() throws {
        let f = try EvidenceFixture()
        defer { f.remove() }
        let id = UUID()
        let stage = f.managed.appendingPathComponent("." + id.uuidString.lowercased() + ".pending")
        let moved = f.managed.appendingPathComponent("moved-owned")
        var config = f.config
        config.makeID = { id }
        config.checkpoint = { point in
            if point == .beforeWrite { throw ManagedEvidenceFailure.writeFailed }
            if point == .beforeCleanup { try FileManager.default.moveItem(at: stage, to: moved) }
        }
        let source = try f.source(Data([1, 2]))
        let error = try evidenceFailure { try ManagedEvidenceFiles(root: f.managed, configuration: config).copy(source: source) }
        #expect(error.reason == .writeFailed)
        #expect(error.artifact?.state == .ownershipUnconfirmed)
        #expect(!FileManager.default.fileExists(atPath: stage.path))
        #expect(FileManager.default.fileExists(atPath: moved.path))
        #expect(try Data(contentsOf: source) == Data([1, 2]))
    }

    @Test("Cancellation after commit cannot pretend no product; postcommit damage is retained")
    func committedBoundary() throws {
        for corrupt in [false, true] {
            let f = try EvidenceFixture()
            defer { f.remove() }
            let id = UUID()
            let flag = EvidenceBox(false)
            var config = f.config
            config.makeID = { id }
            let final = f.managed.appendingPathComponent(id.uuidString.lowercased() + ".original")
            config.checkpoint = { point in
                if point == .afterPublish {
                    flag.change { $0 = true }
                    if corrupt { try Data([9]).write(to: final) }
                }
            }
            let service = ManagedEvidenceFiles(root: f.managed, configuration: config)
            let source = try f.source(Data([1, 2]))
            if corrupt {
                let error = try evidenceFailure { try service.copy(source: source, cancelled: { flag.value }) }
                #expect(error.reason == .integrityFailed)
                #expect(error.artifact?.state == .published)
                #expect(try Data(contentsOf: final) == Data([9]))
            } else {
                let result = try service.copy(source: source, cancelled: { flag.value })
                try service.validate(result)
                #expect(try evidenceFailure { try service.copy(source: source) }.reason == .collision)
                try service.validate(result)
            }
        }
    }

    @Test("Concurrent writer is explicitly refused using a deterministic synchronization boundary")
    func concurrentWriter() async throws {
        let f = try EvidenceFixture()
        defer { f.remove() }
        let entered = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        var config = f.config
        config.checkpoint = { point in
            if point == .openedSource {
                entered.signal()
                guard resume.wait(timeout: .now() + 10) == .success else { throw ManagedEvidenceFailure.readFailed }
            }
        }
        let service = ManagedEvidenceFiles(root: f.managed, configuration: config)
        let source = try f.source(Data([1, 2, 3]))
        let task = Task.detached { try service.copy(source: source) }
        let reached = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: entered.wait(timeout: .now() + 10))
            }
        }
        if reached != .success { resume.signal() }
        #expect(reached == .success)
        let error = try evidenceFailure { try service.copy(source: source) }
        #expect(error.reason == .busy)
        resume.signal()
        let result = try await task.value
        try service.validate(result)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.managed.path) == [result.relativeReference])
    }
    @Test("Fixed ID receipts precede exclusive publication and survive validation")
    func persistentReceiptOrdering() throws {
        let f = try EvidenceFixture(); defer { f.remove() }
        let id = UUID(), source = try f.source(Data([0, 1, 255]))
        var receipts: [ManagedEvidenceReceipt] = []
        let service = ManagedEvidenceFiles(root: f.managed, configuration: f.config)
        let file = try service.copy(source: source, documentID: id, observer: { receipt in
            receipts.append(receipt)
            #expect(!FileManager.default.fileExists(atPath: f.managed.appendingPathComponent(id.uuidString.lowercased() + ".original").path))
            #expect(FileManager.default.fileExists(atPath: f.managed.appendingPathComponent("." + id.uuidString.lowercased() + ".pending").path))
        })
        try #require(receipts.count == 2)
        guard case .stagingOwned(let owned) = receipts[0], case .prepared(let prepared, let identity) = receipts[1] else {
            Issue.record("Receipt order was not staging then prepared"); return
        }
        #expect(file.id == id && file == prepared && owned == identity)
        try service.validate(file, expectedIdentity: identity)
        let replaced = f.managed.appendingPathComponent("replacement")
        try Data([0, 1, 255]).write(to: replaced)
        try FileManager.default.removeItem(at: f.file(file))
        try FileManager.default.moveItem(at: replaced, to: f.file(file))
        #expect(throws: ManagedEvidenceFileError.self) { try service.validate(file, expectedIdentity: identity) }
    }

    @Test("A failed persistent observer prevents publication and only cleans its staging")
    func persistentObserverFailure() throws {
        for failPrepared in [false, true] {
            let f = try EvidenceFixture(); defer { f.remove() }
            let sentinel = f.managed.appendingPathComponent("unknown")
            try Data([9]).write(to: sentinel)
            let id = UUID(), source = try f.source(Data([1, 2]))
            var count = 0
            let error = try evidenceFailure {
                try ManagedEvidenceFiles(root: f.managed, configuration: f.config).copy(source: source, documentID: id, observer: { receipt in
                    count += 1
                    if !failPrepared { throw EvidenceError.operationConflict }
                    if case .prepared = receipt { throw EvidenceError.operationConflict }
                })
            }
            #expect(count == (failPrepared ? 2 : 1))
            #expect(error.artifact == nil)
            #expect(try FileManager.default.contentsOfDirectory(atPath: f.managed.path) == ["unknown"])
            #expect(try Data(contentsOf: sentinel) == Data([9]))
            #expect(try Data(contentsOf: source) == Data([1, 2]))
        }
    }
}

private struct EvidenceFixture: Sendable {
    let root: URL
    let managed: URL
    init() throws {
        root = try temporaryDirectory()
        managed = root.appendingPathComponent("managed")
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }
    var config: ManagedEvidenceFileConfiguration {
        var value = ManagedEvidenceFileConfiguration()
        value.chunkBytes = 7
        value.now = { Date(timeIntervalSince1970: 100) }
        return value
    }
    func source(_ data: Data, name: String = "synthetic.bin") throws -> URL {
        let folder = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let url = folder.appendingPathComponent(name)
        try data.write(to: url, options: .withoutOverwriting)
        return url
    }
    func file(_ value: ManagedEvidenceFile) -> URL { managed.appendingPathComponent(value.relativeReference) }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private final class EvidenceBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.withLock { stored } }
    func change(_ body: (inout Value) -> Void) { lock.withLock { body(&stored) } }
}

private func evidenceHash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func evidenceFailure<T>(_ body: () throws -> T) throws -> ManagedEvidenceFileError {
    do {
        _ = try body()
        Issue.record("Expected a finite managed-file failure")
        throw EvidenceUnexpectedSuccess.expectedFailure
    } catch let error as ManagedEvidenceFileError { return error }
}

private enum EvidenceUnexpectedSuccess: Error { case expectedFailure }
