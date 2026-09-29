import Foundation
import Darwin

struct RuntimePaths: Equatable, Sendable {
    let permanentDatabaseURL: URL
    let marketCacheDatabaseURL: URL
    let internalBackupDirectoryURL: URL

    static func production(fileManager: FileManager = .default) throws -> RuntimePaths {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let caches = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return production(
            applicationSupportDirectory: applicationSupport,
            cachesDirectory: caches
        )
    }

    static func production(
        applicationSupportDirectory: URL,
        cachesDirectory: URL
    ) -> RuntimePaths {
        let applicationDirectory = applicationSupportDirectory
            .appendingPathComponent("Aureus", isDirectory: true)
        return RuntimePaths(
            permanentDatabaseURL: applicationDirectory
                .appendingPathComponent("Permanent", isDirectory: true)
                .appendingPathComponent("aureus.sqlite", isDirectory: false),
            marketCacheDatabaseURL: cachesDirectory
                .appendingPathComponent("Aureus", isDirectory: true)
                .appendingPathComponent("Market", isDirectory: true)
                .appendingPathComponent("market-cache.sqlite", isDirectory: false),
            internalBackupDirectoryURL: applicationDirectory
                .appendingPathComponent("Backups", isDirectory: true)
        )
    }

    static func development(fileManager: FileManager = .default) throws -> RuntimePaths {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let caches = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return development(applicationSupportDirectory: applicationSupport, cachesDirectory: caches)
    }

    static func development(
        applicationSupportDirectory: URL,
        cachesDirectory: URL
    ) -> RuntimePaths {
        let applicationDirectory = applicationSupportDirectory
            .appendingPathComponent("AureusDev", isDirectory: true)
        return RuntimePaths(
            permanentDatabaseURL: applicationDirectory
                .appendingPathComponent("Permanent", isDirectory: true)
                .appendingPathComponent("aureus.sqlite", isDirectory: false),
            marketCacheDatabaseURL: cachesDirectory
                .appendingPathComponent("AureusDev", isDirectory: true)
                .appendingPathComponent("Market", isDirectory: true)
                .appendingPathComponent("market-cache.sqlite", isDirectory: false),
            internalBackupDirectoryURL: applicationDirectory
                .appendingPathComponent("Backups", isDirectory: true)
        )
    }

    static func temporary(root: URL) -> RuntimePaths {
        RuntimePaths(
            permanentDatabaseURL: root
                .appendingPathComponent("Permanent", isDirectory: true)
                .appendingPathComponent("aureus.sqlite", isDirectory: false),
            marketCacheDatabaseURL: root
                .appendingPathComponent("MarketCache", isDirectory: true)
                .appendingPathComponent("market-cache.sqlite", isDirectory: false),
            internalBackupDirectoryURL: root
                .appendingPathComponent("Backups", isDirectory: true)
        )
    }

    func validateSelected(for environment: RuntimeEnvironment) throws {
        let permanentRoot = permanentDatabaseURL.deletingLastPathComponent().deletingLastPathComponent()
        let cacheRoot = marketCacheDatabaseURL.deletingLastPathComponent().deletingLastPathComponent()
        switch environment {
        case .production, .development:
            let name = environment == .production ? "Aureus" : "AureusDev"
            guard permanentRoot.lastPathComponent == name, cacheRoot.lastPathComponent == name else {
                throw RuntimeEnvironmentError.unsafeStorageRoot
            }
        case .temporary:
            let temporaryBase = FileManager.default.temporaryDirectory.standardizedFileURL
            let legacyTestBase = URL(fileURLWithPath: "/private/tmp/AureusTests", isDirectory: true)
            let selectedRoot = permanentRoot.standardizedFileURL
            let rootName = selectedRoot.lastPathComponent
            let hasUUIDName = UUID(uuidString: rootName) != nil
                || (rootName.hasPrefix("Aureus-")
                    && UUID(uuidString: String(rootName.suffix(36))) != nil)
            let allowedBase: URL?
            if Self.isDescendant(selectedRoot, of: temporaryBase) {
                allowedBase = temporaryBase
            } else if Self.isDescendant(selectedRoot, of: legacyTestBase) {
                allowedBase = legacyTestBase
            } else {
                allowedBase = nil
            }
            guard permanentRoot == cacheRoot,
                  hasUUIDName,
                  let allowedBase else {
                throw RuntimeEnvironmentError.unsafeStorageRoot
            }
            var component = selectedRoot
            while component.path != allowedBase.path {
                try Self.requireDirectoryOrMissing(component)
                component = component.deletingLastPathComponent()
            }
            try Self.requireDirectoryOrMissing(allowedBase)
        }
        for url in [permanentRoot, permanentDatabaseURL.deletingLastPathComponent(),
                    internalBackupDirectoryURL, cacheRoot,
                    marketCacheDatabaseURL.deletingLastPathComponent()] {
            try Self.requireDirectoryOrMissing(url)
        }
    }

    private static func requireDirectoryOrMissing(_ url: URL) throws {
        var status = stat()
        if lstat(url.path, &status) == 0 {
            guard status.st_mode & S_IFMT == S_IFDIR else {
                throw RuntimeEnvironmentError.unsafeStorageRoot
            }
        } else if errno != ENOENT {
            throw RuntimeEnvironmentError.unsafeStorageRoot
        }
    }

    private static func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        candidate.path.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/")
    }
}

enum AppDataMode: String, Equatable, Sendable {
    case local
    case syntheticDemo
}

struct LaunchConfiguration: Equatable, Sendable {
    let dataMode: AppDataMode
    let usesTemporaryStores: Bool
    let temporaryRoot: URL?
    var environment: RuntimeEnvironment? = nil
    var buildIdentityValid = true
    var settingsCacheAuditEnabled = false
    var marketFailureScenario: SyntheticMarketFailureScenario? = nil
    var marketStaleAuditEnabled = false

    static func current(arguments: [String] = ProcessInfo.processInfo.arguments) -> LaunchConfiguration {
        #if DEBUG
        let declaredEnvironment = "development"
        #else
        let declaredEnvironment = "production"
        #endif
        let buildEnvironment = RuntimeEnvironment.buildIdentity(
            bundleID: Bundle.main.bundleIdentifier,
            declaredEnvironment: declaredEnvironment
        )
        let displayedName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let validBuildEnvironment = buildEnvironment?.displayName == displayedName ? buildEnvironment : nil
        let isDemo = arguments.contains("--aureus-demo")
        let isTemporary = isDemo
            || arguments.contains("--aureus-ui-testing")
            || arguments.contains("--aureus-temporary-store")
        let temporaryRoot: URL?
        if isTemporary {
            temporaryRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("Aureus-Stage2", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        } else {
            temporaryRoot = nil
        }
        let scenarioIndices = arguments.indices.filter {
            arguments[$0] == "--aureus-market-failure-scenario"
        }
        let marketFailureScenario: SyntheticMarketFailureScenario?
        if isDemo, arguments.contains("--aureus-ui-testing"),
           scenarioIndices.count == 1,
           let index = scenarioIndices.first, index + 1 < arguments.count {
            marketFailureScenario = SyntheticMarketFailureScenario(rawValue: arguments[index + 1])
        } else {
            marketFailureScenario = nil
        }
        return LaunchConfiguration(
            dataMode: isDemo ? .syntheticDemo : .local,
            usesTemporaryStores: isTemporary,
            temporaryRoot: temporaryRoot,
            environment: validBuildEnvironment.map { isTemporary ? .temporary : $0 },
            buildIdentityValid: validBuildEnvironment != nil,
            settingsCacheAuditEnabled: isDemo
                && arguments.contains("--aureus-ui-testing")
                && arguments.contains("--aureus-settings-cache-audit"),
            marketFailureScenario: marketFailureScenario,
            marketStaleAuditEnabled: isDemo
                && arguments.contains("--aureus-ui-testing")
                && arguments.filter { $0 == "--aureus-market-stale-audit" }.count == 1
                && scenarioIndices.isEmpty
                && !arguments.contains("--aureus-settings-cache-audit")
        )
    }

    func resolvedEnvironment() throws -> RuntimeEnvironment {
        guard buildIdentityValid else { throw RuntimeEnvironmentError.invalidBuildIdentity }
        if usesTemporaryStores {
            guard temporaryRoot != nil,
                  environment == nil || environment == .temporary else {
                throw RuntimeEnvironmentError.invalidLaunchConfiguration
            }
            return .temporary
        }
        guard temporaryRoot == nil, dataMode == .local,
              let environment, environment != .temporary else {
            throw RuntimeEnvironmentError.invalidLaunchConfiguration
        }
        return environment
    }
}
