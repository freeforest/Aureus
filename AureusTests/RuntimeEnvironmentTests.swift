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
}
