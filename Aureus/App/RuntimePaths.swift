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
            let temporaryBase = try Self.temporaryPathComponents(FileManager.default.temporaryDirectory)
            let legacyTestBase = ["/", "private", "tmp", "AureusTests"]
            let selectedRoot = try Self.temporaryPathComponents(permanentRoot)
            let rootName = selectedRoot.last ?? ""
            let hasUUIDName = UUID(uuidString: rootName) != nil
                || (rootName.hasPrefix("Aureus-")
                    && UUID(uuidString: String(rootName.suffix(36))) != nil)
            let allowedBase = [temporaryBase, legacyTestBase].first {
                selectedRoot.count > $0.count && selectedRoot.starts(with: $0)
            }
            guard hasUUIDName,
                  try Self.temporaryPathComponents(cacheRoot) == selectedRoot,
                  try Self.temporaryPathComponents(permanentDatabaseURL)
                    == selectedRoot + ["Permanent", "aureus.sqlite"],
                  try Self.temporaryPathComponents(marketCacheDatabaseURL)
                    == selectedRoot + ["MarketCache", "market-cache.sqlite"],
                  try Self.temporaryPathComponents(internalBackupDirectoryURL)
                    == selectedRoot + ["Backups"],
                  let allowedBase else {
                throw RuntimeEnvironmentError.unsafeStorageRoot
            }
            // Check every managed ancestor without resolving arbitrary symlinks.
            // Component counts bound the walk, including for a root not yet created.
            for count in stride(from: selectedRoot.count, through: allowedBase.count, by: -1) {
                let path = "/" + selectedRoot.prefix(count).dropFirst().joined(separator: "/")
                try Self.requireDirectoryOrMissing(URL(fileURLWithPath: path, isDirectory: true))
            }
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

    private static func temporaryPathComponents(_ url: URL) throws -> [String] {
        var components = url.pathComponents
        guard url.isFileURL, components.first == "/",
              !components.contains(".."), !components.contains(".") else {
            throw RuntimeEnvironmentError.unsafeStorageRoot
        }
        // These macOS system aliases are the only links accepted during comparison.
        // Keep all components below them intact so lstat can still reject managed links.
        if components.count > 1, components[1] == "tmp" || components[1] == "var" {
            let alias = "/" + components[1]
            let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: alias)
            guard destination == "private" + alias || destination == "/private" + alias else {
                throw RuntimeEnvironmentError.unsafeStorageRoot
            }
            components.insert("private", at: 1)
        }
        return components
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
