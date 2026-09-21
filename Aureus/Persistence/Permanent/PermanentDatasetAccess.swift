import Foundation
import Darwin

struct EvidenceConfiguration: Sendable {
    let root: URL
    let protectedPaths: [URL]
    var files: ManagedEvidenceFileConfiguration = .init()
    // Synthetic tests can observe the actual final database commit boundary.
    var afterCommit: @Sendable () throws -> Void = {}
}

/// Process-local registration only. No database I/O while the registry mutex is held.
final class PermanentDatasetAccess: @unchecked Sendable {
    private struct Binding {
        let url: URL
        let namespace: String
        let parentNamespace: String
        let exclusive: Bool
        let root: URL?
        let rootIdentity: String?
    }
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var entries: [UUID: Binding] = [:]
    }
    private static let registry = Registry()
    private let token: UUID
    let evidence: EvidenceConfiguration?

    init(database: URL, evidence: EvidenceConfiguration?, backupRoot: URL?) throws {
        // Core callers retain their existing path behavior; Evidence requires a no-link path.
        let database = evidence == nil ? database.resolvingSymlinksInPath() : database
        let namespace = try Self.namespace(database, mustExist: false)
        let parentNamespace = try Self.parentNamespace(database)
        let existing = try Self.objectIdentity(database)
        var rootIdentity: String?
        if let evidence {
            _ = try Self.namespace(evidence.root, mustExist: true)
            var value = stat()
            guard lstat(evidence.root.path, &value) == 0, value.st_mode & S_IFMT == S_IFDIR else { throw EvidenceError.unsafeRoot }
            rootIdentity = "\(value.st_dev):\(value.st_ino)"
            for protected in [database.deletingLastPathComponent()] + evidence.protectedPaths + (backupRoot.map { [$0] } ?? []) {
                let key = try Self.namespace(protected, mustExist: false)
                let rootKey = try Self.namespace(evidence.root, mustExist: true)
                guard !Self.overlap(rootKey, key) else { throw EvidenceError.unsafeRoot }
            }
        }
        let token = UUID()
        try Self.registry.lock.withLock {
            for binding in Self.registry.entries.values {
                // Re-read the live path, not just the inode captured before a supported Restore.
                let liveIdentity = try Self.objectIdentity(binding.url)
                let liveParentNamespace = try Self.parentNamespace(binding.url)
                let alias = existing != nil && existing == liveIdentity
                let same = namespace == binding.namespace || parentNamespace == binding.parentNamespace
                    || parentNamespace == liveParentNamespace || alias
                if same && (evidence != nil || binding.exclusive) { throw EvidenceError.ownerConflict }
                if let rootIdentity, rootIdentity == binding.rootIdentity { throw EvidenceError.ownerConflict }
            }
            Self.registry.entries[token] = Binding(url: database, namespace: namespace, parentNamespace: parentNamespace,
                exclusive: evidence != nil, root: evidence?.root, rootIdentity: rootIdentity)
        }
        self.token = token
        self.evidence = evidence
    }

    deinit { Self.registry.lock.withLock { _ = Self.registry.entries.removeValue(forKey: token) } }

    func requireEmptyEvidenceRoot() throws {
        guard let evidence else { return }
        let current = try Self.objectIdentity(evidence.root)
        let expected = Self.registry.lock.withLock { Self.registry.entries[token]?.rootIdentity }
        guard current == expected else { throw EvidenceError.unsafeRoot }
        _ = try Self.namespace(evidence.root, mustExist: true)
        guard try FileManager.default.contentsOfDirectory(atPath: evidence.root.path).isEmpty else {
            throw EvidenceError.legacyFormatUnsupported
        }
    }

    func validateRoot() throws {
        guard let evidence else { throw EvidenceError.disabled }
        _ = try Self.namespace(evidence.root, mustExist: true)
        let expected = Self.registry.lock.withLock { Self.registry.entries[token]?.rootIdentity }
        guard try Self.objectIdentity(evidence.root) == expected else { throw EvidenceError.unsafeRoot }
    }

    private static func overlap(_ a: String, _ b: String) -> Bool {
        a == b || a.hasPrefix(b + "/") || b.hasPrefix(a + "/")
    }

    private static func parentNamespace(_ database: URL) throws -> String {
        var parent = database.deletingLastPathComponent()
        var names = [database.lastPathComponent.precomposedStringWithCanonicalMapping.lowercased()]
        if let identity = try objectIdentity(parent) {
            return identity + "/" + names.joined(separator: "/")
        }
        // DatabaseQueueFactory may create missing parents after registration. Anchor those
        // names to the nearest existing, verified directory, then re-evaluate on acquisition.
        while parent.path != "/" {
            names.insert(parent.lastPathComponent.precomposedStringWithCanonicalMapping.lowercased(), at: 0)
            parent.deleteLastPathComponent()
            if let identity = try objectIdentity(parent) { return identity + "/" + names.joined(separator: "/") }
        }
        throw EvidenceError.unsafeRoot
    }

    private static func objectIdentity(_ url: URL) throws -> String? {
        var value = stat()
        if lstat(url.path, &value) != 0 {
            if errno == ENOENT { return nil }
            throw EvidenceError.unsafeRoot
        }
        guard value.st_mode & S_IFMT != S_IFLNK else { throw EvidenceError.unsafeRoot }
        return "\(value.st_dev):\(value.st_ino)"
    }

    private static func namespace(_ url: URL, mustExist: Bool) throws -> String {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
              url.path.hasPrefix("/"), !url.path.utf8.contains(0) else { throw EvidenceError.unsafeRoot }
        let parts = url.path.split(separator: "/").map(String.init)
        guard !parts.contains("."), !parts.contains("..") else { throw EvidenceError.unsafeRoot }
        var path = ""
        for (index, part) in parts.enumerated() {
            path += "/" + part
            var value = stat()
            if lstat(path, &value) == 0 {
                guard value.st_mode & S_IFMT != S_IFLNK,
                      index == parts.count - 1 || value.st_mode & S_IFMT == S_IFDIR else { throw EvidenceError.unsafeRoot }
            } else if errno != ENOENT || mustExist { throw EvidenceError.unsafeRoot }
        }
        // Conservative case/normalization collision handling also covers not-yet-created names.
        return url.path.precomposedStringWithCanonicalMapping.lowercased()
    }
}
