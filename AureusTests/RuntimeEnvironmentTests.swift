import Foundation
import Testing
@testable import Aureus

@Suite("Runtime environment identity")
struct RuntimeEnvironmentTests {
    @Test("Build identity accepts only matching declared environment and Bundle ID")
    func identityMatrix() {
        #expect(RuntimeEnvironment.buildIdentity(
            bundleID: "com.aureus.wealthterminal", declaredEnvironment: "production") == .production)
        #expect(RuntimeEnvironment.buildIdentity(
            bundleID: "com.aureus.wealthterminal.dev", declaredEnvironment: "development") == .development)
        #expect(RuntimeEnvironment.buildIdentity(
            bundleID: "com.aureus.wealthterminal.dev", declaredEnvironment: "production") == nil)
        #expect(RuntimeEnvironment.buildIdentity(
            bundleID: "com.aureus.wealthterminal", declaredEnvironment: "development") == nil)
        #expect(RuntimeEnvironment.buildIdentity(
            bundleID: "com.aureus.wealthterminal", declaredEnvironment: nil) == nil)
        #expect(RuntimeEnvironment.production.keychainService
            == "com.aureus.wealthterminal.provider-credentials")
        #expect(RuntimeEnvironment.development.keychainService
            == "com.aureus.wealthterminal.dev.provider-credentials")
        #expect(RuntimeEnvironment.temporary.keychainService == nil)
    }

    @Test("Debug host identity resolves before local dependencies")
    func debugHostIdentity() throws {
        let configuration = LaunchConfiguration.current(arguments: ["AureusDev"])
        #expect(configuration.buildIdentityValid)
        #expect(try configuration.resolvedEnvironment() == .development)
        #expect(configuration.temporaryRoot == nil)

        let test = LaunchConfiguration.current(arguments: ["AureusDev", "--aureus-temporary-store"])
        #expect(try test.resolvedEnvironment() == .temporary)
        #expect(test.temporaryRoot != nil)
    }

    @Test("Missing or contradictory test configuration fails before choosing a store")
    func invalidConfiguration() {
        let missingRoot = LaunchConfiguration(dataMode: .local, usesTemporaryStores: true,
            temporaryRoot: nil)
        #expect(throws: RuntimeEnvironmentError.invalidLaunchConfiguration) {
            try missingRoot.resolvedEnvironment()
        }
        let noEnvironment = LaunchConfiguration(dataMode: .local, usesTemporaryStores: false,
            temporaryRoot: nil)
        #expect(throws: RuntimeEnvironmentError.invalidLaunchConfiguration) {
            try noEnvironment.resolvedEnvironment()
        }
        var contradictory = LaunchConfiguration(dataMode: .local, usesTemporaryStores: true,
            temporaryRoot: URL(fileURLWithPath: "/private/tmp/AureusTests/00000000-0000-4000-8000-000000000001"))
        contradictory.environment = .production
        #expect(throws: RuntimeEnvironmentError.invalidLaunchConfiguration) {
            try contradictory.resolvedEnvironment()
        }
        contradictory.environment = .temporary
        contradictory.buildIdentityValid = false
        #expect(throws: RuntimeEnvironmentError.invalidBuildIdentity) {
            try contradictory.resolvedEnvironment()
        }
    }

    @Test("Production, persistent Dev and temporary path rules are distinct")
    func pathRules() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let caches = root.appendingPathComponent("Caches", isDirectory: true)
        let production = RuntimePaths.production(applicationSupportDirectory: support,
            cachesDirectory: caches)
        let development = RuntimePaths.development(applicationSupportDirectory: support,
            cachesDirectory: caches)
        let temporary = RuntimePaths.temporary(root: root)
        #expect(production.permanentDatabaseURL == support.appendingPathComponent("Aureus/Permanent/aureus.sqlite"))
        #expect(production.marketCacheDatabaseURL == caches.appendingPathComponent("Aureus/Market/market-cache.sqlite"))
        #expect(production.internalBackupDirectoryURL.path
            == support.appendingPathComponent("Aureus/Backups").path)
        #expect(development.permanentDatabaseURL == support.appendingPathComponent("AureusDev/Permanent/aureus.sqlite"))
        #expect(development.marketCacheDatabaseURL == caches.appendingPathComponent("AureusDev/Market/market-cache.sqlite"))
        #expect(development.internalBackupDirectoryURL.path
            == support.appendingPathComponent("AureusDev/Backups").path)
        #expect(Set([production.permanentDatabaseURL, development.permanentDatabaseURL,
            temporary.permanentDatabaseURL]).count == 3)
        try production.validateSelected(for: .production)
        try development.validateSelected(for: .development)
        try temporary.validateSelected(for: .temporary)
    }

    @Test("A linked Development namespace is rejected before opening a store")
    func linkedDevRootRejected() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let caches = root.appendingPathComponent("Caches", isDirectory: true)
        let productionRoot = support.appendingPathComponent("Aureus", isDirectory: true)
        try FileManager.default.createDirectory(at: productionRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: support.appendingPathComponent("AureusDev"), withDestinationURL: productionRoot)
        let development = RuntimePaths.development(applicationSupportDirectory: support,
            cachesDirectory: caches)
        #expect(throws: RuntimeEnvironmentError.unsafeStorageRoot) {
            try development.validateSelected(for: .development)
        }
    }

    @Test("Legal temporary roots keep ownership before and after creation, including system aliases and directory URLs",
          arguments: ["system", "legacy"])
    func temporaryRootRepresentations(base: String) throws {
        let manager = FileManager.default
        let parent = base == "system" ? manager.temporaryDirectory
            : URL(fileURLWithPath: "/private/tmp/AureusTests", isDirectory: true)
        let root = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        #expect(!manager.fileExists(atPath: root.path))
        defer { try? manager.removeItem(at: root) }
        var representations = [root, URL(fileURLWithPath: root.path + "/", isDirectory: true),
                               URL(fileURLWithPath: root.path, isDirectory: false)]
        if base == "legacy" {
            representations.append(URL(fileURLWithPath:
                "/tmp/AureusTests/" + root.lastPathComponent, isDirectory: true))
        } else if root.path.hasPrefix("/var/") {
            representations.append(URL(fileURLWithPath: "/private" + root.path, isDirectory: true))
        }
        for created in [false, true] {
            if created {
                for component in ["Permanent", "MarketCache", "Backups"] {
                    try manager.createDirectory(at: root.appendingPathComponent(component),
                        withIntermediateDirectories: true)
                }
            }
            #expect(manager.fileExists(atPath: root.path) == created)
            for representation in representations {
                try RuntimePaths.temporary(root: representation).validateSelected(for: .temporary)
            }
        }
    }

    @Test("A UUID or similar string prefix does not authorize an unrelated root",
          arguments: ["outside", "similar-prefix", "invalid-name", "parent-traversal"])
    func temporaryRootBoundaryRejected(scenario: String) {
        let id = UUID().uuidString
        let path: String
        switch scenario {
        case "outside": path = "/ENV03-Synthetic-Unowned/" + id
        case "similar-prefix": path = "/private/tmp/AureusTestsUnowned/" + id
        case "invalid-name": path = FileManager.default.temporaryDirectory.path + "/Not-A-Controlled-Root"
        default: path = "/private/tmp/AureusTests/../" + id
        }
        #expect(throws: RuntimeEnvironmentError.unsafeStorageRoot) {
            try RuntimePaths.temporary(root: URL(fileURLWithPath: path, isDirectory: true))
                .validateSelected(for: .temporary)
        }
    }

    @Test("Temporary root and each required directory reject ordinary files",
          arguments: ["root", "Permanent", "MarketCache", "Backups"])
    func temporaryDirectoryFilesRejected(component: String) throws {
        let owner = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: owner) }
        let root = owner.appendingPathComponent(UUID().uuidString, isDirectory: true)
        if component != "root" {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        let file = component == "root" ? root : root.appendingPathComponent(component)
        try Data("synthetic file".utf8).write(to: file)
        #expect(throws: RuntimeEnvironmentError.unsafeStorageRoot) {
            try RuntimePaths.temporary(root: root).validateSelected(for: .temporary)
        }
    }

    @Test("Managed links cannot borrow temporary or synthetic Production/Dev ownership",
          arguments: ["root", "parent", "Permanent", "MarketCache", "Backups"],
          ["temporary", "synthetic-production", "synthetic-development"])
    func temporaryManagedLinksRejected(component: String, destination: String) throws {
        let manager = FileManager.default
        let owner = try temporaryDirectory()
        defer { try? manager.removeItem(at: owner) }
        let namespace: String
        switch destination {
        case "synthetic-production": namespace = "Controls/Support/Aureus"
        case "synthetic-development": namespace = "Controls/Support/AureusDev"
        default: namespace = "Controls/Temporary"
        }
        let target = owner.appendingPathComponent(namespace, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: target, withIntermediateDirectories: true)
        let root: URL
        if component == "parent" {
            let linkedParent = owner.appendingPathComponent("LinkedParent", isDirectory: true)
            try manager.createSymbolicLink(at: linkedParent, withDestinationURL: target)
            root = linkedParent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        } else {
            root = owner.appendingPathComponent(UUID().uuidString, isDirectory: true)
            if component == "root" {
                try manager.createSymbolicLink(at: root, withDestinationURL: target)
            } else {
                try manager.createDirectory(at: root, withIntermediateDirectories: true)
                try manager.createSymbolicLink(at: root.appendingPathComponent(component),
                    withDestinationURL: target)
            }
        }
        let alias = URL(fileURLWithPath: root.path.replacingOccurrences(
            of: "/private/tmp/", with: "/tmp/"), isDirectory: true)
        for representation in [root, alias] {
            #expect(throws: RuntimeEnvironmentError.unsafeStorageRoot) {
                try RuntimePaths.temporary(root: representation).validateSelected(for: .temporary)
            }
        }
    }

    @Test("Temporary database, cache and Backup paths must belong to the same exact layout",
          arguments: ["backup", "cache", "permanent-directory", "cache-directory"])
    func temporaryLayoutRejected(component: String) throws {
        let owner = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: owner) }
        let paths = RuntimePaths.temporary(root: owner)
        let other = owner.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let mismatched = RuntimePaths(
            permanentDatabaseURL: component == "permanent-directory"
                ? owner.appendingPathComponent("OtherPermanent/aureus.sqlite") : paths.permanentDatabaseURL,
            marketCacheDatabaseURL: component == "cache"
                ? RuntimePaths.temporary(root: other).marketCacheDatabaseURL
                : component == "cache-directory"
                    ? owner.appendingPathComponent("OtherCache/market-cache.sqlite") : paths.marketCacheDatabaseURL,
            internalBackupDirectoryURL: component == "backup"
                ? other.appendingPathComponent("Backups") : paths.internalBackupDirectoryURL
        )
        #expect(throws: RuntimeEnvironmentError.unsafeStorageRoot) {
            try mismatched.validateSelected(for: .temporary)
        }
    }
}
