import Foundation
import CryptoKit
import Darwin

struct ManagedEvidenceFile: Equatable, Sendable {
    let id: UUID
    let originalFilename: String
    let relativeReference: String
    let byteCount: Int64
    let sha256: String
    let copiedAt: Date
}

enum ManagedEvidenceFailure: Error, Equatable, Sendable {
    case invalidConfiguration, unsafePath, notRegularFile, busy, cancelled
    case tooLarge, sourceChanged, collision, readFailed, writeFailed
    case closeFailed, publishFailed, integrityFailed, cleanupFailed
}

struct ManagedEvidenceArtifact: Equatable, Sendable {
    enum State: Equatable, Sendable { case stagingRetained, ownershipUnconfirmed, published }
    let relativeReference: String
    let device: Int32
    let inode: UInt64
    let state: State
}

struct ManagedEvidenceFileError: Error, Equatable, Sendable {
    let reason: ManagedEvidenceFailure
    let artifact: ManagedEvidenceArtifact?
}

/// Narrow deterministic I/O boundaries for synthetic fault/race tests.
enum ManagedEvidenceIOPoint: Equatable, Sendable {
    case openedSource, beforeRead, beforeWrite, copiedChunk, beforeClose
    case beforePublish, afterPublish, beforeCleanup
}

struct ManagedEvidenceFileConfiguration: Sendable {
    var maximumBytes: Int64 = 256 * 1_024 * 1_024
    var chunkBytes: Int = 1_048_576
    var makeID: @Sendable () -> UUID = { UUID() }
    var now: @Sendable () -> Date = { Date() }
    var checkpoint: @Sendable (ManagedEvidenceIOPoint) throws -> Void = { _ in }
}

/// Internal, opt-in file layer. No I/O at initialization and no production path discovery.
/// The caller must own the existing root namespace; this is not a same-user adversarial sandbox.
final class ManagedEvidenceFiles: @unchecked Sendable {
    private let root: URL
    private let configuration: ManagedEvidenceFileConfiguration
    // Protects the single writer for the whole synchronous operation, including injected callbacks.
    private let writer = NSLock()

    init(root: URL, configuration: ManagedEvidenceFileConfiguration = .init()) {
        self.root = root
        self.configuration = configuration
    }

    func copy(source: URL, cancelled: @Sendable () -> Bool = { false }) throws -> ManagedEvidenceFile {
        guard writer.try() else { throw ManagedEvidenceFileError(reason: .busy, artifact: nil) }
        defer { writer.unlock() }
        var directory: Descriptor?
        var staging: Descriptor?
        var owned: Stamp?
        var pending = ""
        var final = ""
        var committed = false
        do {
            try checkConfiguration()
            try checkCancellation(cancelled)
            let parent = try Self.openDirectory(root)
            directory = parent
            let rootIdentity = try Stamp(parent.raw)
            let input = try Self.openFile(source)
            let initial = try Stamp(input.raw)
            guard initial.regular else { throw ManagedEvidenceFailure.notRegularFile }
            guard initial.size >= 0, initial.size <= configuration.maximumBytes else {
                throw ManagedEvidenceFailure.tooLarge
            }
            try configuration.checkpoint(.openedSource)
            try checkSource(source, initial: initial, input: input)
            let id = configuration.makeID()
            let name = id.uuidString.lowercased()
            pending = "." + name + ".pending"
            final = name + ".original"
            try checkRoot(rootIdentity)
            let fd = openat(parent.raw, pending, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw errno == EEXIST ? ManagedEvidenceFailure.collision : .writeFailed }
            let output = Descriptor(fd)
            staging = output
            owned = try Stamp(fd)
            var count: Int64 = 0
            var hash = SHA256()
            var buffer = [UInt8](repeating: 0, count: configuration.chunkBytes)
            while true {
                try checkCancellation(cancelled)
                try configuration.checkpoint(.beforeRead)
                let n = buffer.withUnsafeMutableBytes { Darwin.read(input.raw, $0.baseAddress, $0.count) }
                guard n >= 0 else { throw ManagedEvidenceFailure.readFailed }
                if n == 0 { break }
                let sum = count.addingReportingOverflow(Int64(n))
                guard !sum.overflow, sum.partialValue <= configuration.maximumBytes else {
                    throw ManagedEvidenceFailure.tooLarge
                }
                count = sum.partialValue
                try checkRoot(rootIdentity)
                try configuration.checkpoint(.beforeWrite)
                var offset = 0
                while offset < n {
                    let written = buffer.withUnsafeBytes {
                        Darwin.write(output.raw, $0.baseAddress!.advanced(by: offset), n - offset)
                    }
                    guard written > 0 else { throw ManagedEvidenceFailure.writeFailed }
                    offset += written
                }
                hash.update(data: Data(buffer[0..<n]))
                try configuration.checkpoint(.copiedChunk)
            }
            guard count == initial.size else { throw ManagedEvidenceFailure.sourceChanged }
            try checkSource(source, initial: initial, input: input)
            guard fsync(output.raw) == 0 else { throw ManagedEvidenceFailure.writeFailed }
            try configuration.checkpoint(.beforeClose)
            try output.closeChecked()
            try input.closeChecked()
            let digest = Self.hex(hash.finalize())
            let staged = try Self.openRegular(at: parent.raw, name: pending)
            guard let identity = owned, try Stamp(staged.raw).sameObject(identity) else {
                throw ManagedEvidenceFailure.integrityFailed
            }
            try checkDigest(staged, bytes: count, hash: digest)
            try staged.closeChecked()
            try configuration.checkpoint(.beforePublish)
            try checkCancellation(cancelled)
            try checkRoot(rootIdentity)
            let sourceAgain = try Self.openFile(source)
            guard try Stamp(sourceAgain.raw) == initial else { throw ManagedEvidenceFailure.sourceChanged }
            try sourceAgain.closeChecked()
            guard try Self.stamp(at: parent.raw, name: pending).sameObject(identity) else {
                throw ManagedEvidenceFailure.integrityFailed
            }
            // Atomic exclusive namespace commit. Cancellation no longer implies "no file" after this.
            guard renameatx_np(parent.raw, pending, parent.raw, final, UInt32(RENAME_EXCL)) == 0 else {
                throw errno == EEXIST ? ManagedEvidenceFailure.collision : .publishFailed
            }
            committed = true
            try configuration.checkpoint(.afterPublish)
            try checkRoot(rootIdentity)
            let published = try Self.openRegular(at: parent.raw, name: final)
            guard try Stamp(published.raw).sameObject(identity) else { throw ManagedEvidenceFailure.integrityFailed }
            try checkDigest(published, bytes: count, hash: digest)
            try published.closeChecked()
            try parent.closeChecked()
            return ManagedEvidenceFile(
                id: id, originalFilename: source.lastPathComponent, relativeReference: final,
                byteCount: count, sha256: digest, copiedAt: configuration.now()
            )
        } catch {
            let reason = (error as? ManagedEvidenceFailure) ?? .writeFailed
            guard let identity = owned, let parent = directory else {
                throw ManagedEvidenceFileError(reason: reason, artifact: nil)
            }
            if committed {
                throw ManagedEvidenceFileError(reason: reason, artifact: identity.artifact(final, .published))
            }
            // A failed close is not retried on a potentially reused descriptor.
            var cleanupReason = reason
            do { try staging?.closeChecked() } catch { cleanupReason = .closeFailed }
            do {
                try configuration.checkpoint(.beforeCleanup)
                guard try Self.stamp(at: parent.raw, name: pending).sameObject(identity) else {
                    throw ManagedEvidenceFileError(reason: cleanupReason, artifact: identity.artifact(pending, .ownershipUnconfirmed))
                }
                guard unlinkat(parent.raw, pending, 0) == 0 else { throw ManagedEvidenceFailure.cleanupFailed }
            } catch let failure as ManagedEvidenceFileError {
                throw failure
            } catch {
                let observed = try? Self.stamp(at: parent.raw, name: pending)
                let state: ManagedEvidenceArtifact.State = observed?.sameObject(identity) == true
                    ? .stagingRetained : .ownershipUnconfirmed
                throw ManagedEvidenceFileError(reason: cleanupReason, artifact: identity.artifact(pending, state))
            }
            throw ManagedEvidenceFileError(reason: cleanupReason, artifact: nil)
        }
    }

    /// Validates a saved reference with bounded reads, without any source URL or prior instance.
    /// It does not grant a race-free external-open URL or commit Document metadata.
    func validate(_ file: ManagedEvidenceFile) throws {
        do {
            try checkConfiguration()
            guard file.relativeReference == file.id.uuidString.lowercased() + ".original",
                  file.byteCount >= 0, file.byteCount <= configuration.maximumBytes,
                  file.sha256.count == 64,
                  file.sha256.allSatisfy({ "0123456789abcdef".contains($0) }) else {
                throw ManagedEvidenceFailure.unsafePath
            }
            let parent = try Self.openDirectory(root)
            let identity = try Stamp(parent.raw)
            let input = try Self.openRegular(at: parent.raw, name: file.relativeReference)
            try checkDigest(input, bytes: file.byteCount, hash: file.sha256)
            try checkRoot(identity)
            guard try Self.stamp(at: parent.raw, name: file.relativeReference).sameObject(Stamp(input.raw)) else {
                throw ManagedEvidenceFailure.integrityFailed
            }
            try input.closeChecked()
            try parent.closeChecked()
        } catch {
            throw ManagedEvidenceFileError(reason: (error as? ManagedEvidenceFailure) ?? .integrityFailed, artifact: nil)
        }
    }

    private func checkConfiguration() throws {
        guard configuration.maximumBytes >= 0, (1...1_048_576).contains(configuration.chunkBytes) else {
            throw ManagedEvidenceFailure.invalidConfiguration
        }
    }

    private func checkCancellation(_ cancelled: () -> Bool) throws {
        if cancelled() { throw ManagedEvidenceFailure.cancelled }
    }

    private func checkRoot(_ expected: Stamp) throws {
        let current = try Self.openDirectory(root)
        guard try Stamp(current.raw).sameObject(expected) else { throw ManagedEvidenceFailure.unsafePath }
        try current.closeChecked()
    }

    private func checkSource(_ url: URL, initial: Stamp, input: Descriptor) throws {
        let current = try Self.openFile(url)
        guard try Stamp(input.raw) == initial, try Stamp(current.raw) == initial else {
            throw ManagedEvidenceFailure.sourceChanged
        }
        try current.closeChecked()
    }

    private func checkDigest(_ file: Descriptor, bytes: Int64, hash: String) throws {
        let before = try Stamp(file.raw)
        guard before.regular, before.size == bytes else { throw ManagedEvidenceFailure.integrityFailed }
        var digest = SHA256()
        var total: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: configuration.chunkBytes)
        while true {
            let n = buffer.withUnsafeMutableBytes { Darwin.read(file.raw, $0.baseAddress, $0.count) }
            guard n >= 0 else { throw ManagedEvidenceFailure.readFailed }
            if n == 0 { break }
            let sum = total.addingReportingOverflow(Int64(n))
            guard !sum.overflow, sum.partialValue <= configuration.maximumBytes else { throw ManagedEvidenceFailure.tooLarge }
            total = sum.partialValue
            digest.update(data: Data(buffer[0..<n]))
        }
        guard total == bytes, Self.hex(digest.finalize()) == hash, try Stamp(file.raw) == before else {
            throw ManagedEvidenceFailure.integrityFailed
        }
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func components(_ url: URL) throws -> [String] {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
              url.path.hasPrefix("/"), !url.path.utf8.contains(0) else { throw ManagedEvidenceFailure.unsafePath }
        let parts = url.path.split(separator: "/").map(String.init)
        guard !parts.contains("."), !parts.contains("..") else { throw ManagedEvidenceFailure.unsafePath }
        return parts
    }

    private static func openDirectory(_ url: URL) throws -> Descriptor {
        try walk(components(url))
    }

    private static func walk(_ parts: [String]) throws -> Descriptor {
        var current = Descriptor(Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC))
        guard current.raw >= 0 else { throw ManagedEvidenceFailure.unsafePath }
        for part in parts {
            let next = openat(current.raw, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw ManagedEvidenceFailure.unsafePath }
            let opened = Descriptor(next)
            try current.closeChecked()
            current = opened
        }
        return current
    }

    private static func openFile(_ url: URL) throws -> Descriptor {
        let parts = try components(url)
        guard let name = parts.last else { throw ManagedEvidenceFailure.notRegularFile }
        let parent = try walk(Array(parts.dropLast()))
        let result = try openRegular(at: parent.raw, name: name)
        try parent.closeChecked()
        return result
    }

    private static func openRegular(at parent: Int32, name: String) throws -> Descriptor {
        let raw = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard raw >= 0 else { throw ManagedEvidenceFailure.unsafePath }
        let file = Descriptor(raw)
        guard try Stamp(raw).regular else { throw ManagedEvidenceFailure.notRegularFile }
        return file
    }

    private static func stamp(at parent: Int32, name: String) throws -> Stamp {
        var value = stat()
        guard fstatat(parent, name, &value, AT_SYMLINK_NOFOLLOW) == 0 else { throw ManagedEvidenceFailure.unsafePath }
        return Stamp(value)
    }

    private final class Descriptor {
        private(set) var raw: Int32
        init(_ raw: Int32) { self.raw = raw }
        func closeChecked() throws {
            guard raw >= 0 else { return }
            let fd = raw
            raw = -1
            guard Darwin.close(fd) == 0 else { throw ManagedEvidenceFailure.closeFailed }
        }
        deinit { if raw >= 0 { _ = Darwin.close(raw) } }
    }

    private struct Stamp: Equatable {
        let device: Int32
        let inode: UInt64
        let mode: UInt16
        let links: UInt16
        let size: Int64
        let modifiedSeconds: Int
        let modifiedNanos: Int
        let changedSeconds: Int
        let changedNanos: Int
        var regular: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFREG) }
        init(_ fd: Int32) throws {
            var value = stat()
            guard fstat(fd, &value) == 0 else { throw ManagedEvidenceFailure.readFailed }
            self.init(value)
        }
        init(_ s: stat) {
            device = s.st_dev; inode = s.st_ino; mode = s.st_mode; links = s.st_nlink; size = s.st_size
            modifiedSeconds = s.st_mtimespec.tv_sec; modifiedNanos = s.st_mtimespec.tv_nsec
            changedSeconds = s.st_ctimespec.tv_sec; changedNanos = s.st_ctimespec.tv_nsec
        }
        func sameObject(_ other: Stamp) -> Bool { device == other.device && inode == other.inode && mode == other.mode }
        func artifact(_ name: String, _ state: ManagedEvidenceArtifact.State) -> ManagedEvidenceArtifact {
            .init(relativeReference: name, device: device, inode: inode, state: state)
        }
    }
}
