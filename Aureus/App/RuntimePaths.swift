import Foundation

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
}

enum AppDataMode: String, Equatable, Sendable {
    case local
    case syntheticDemo
}

struct LaunchConfiguration: Equatable, Sendable {
    let dataMode: AppDataMode
    let usesTemporaryStores: Bool
    let temporaryRoot: URL?
    var settingsCacheAuditEnabled = false

    static func current(arguments: [String] = ProcessInfo.processInfo.arguments) -> LaunchConfiguration {
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
        return LaunchConfiguration(
            dataMode: isDemo ? .syntheticDemo : .local,
            usesTemporaryStores: isTemporary,
            temporaryRoot: temporaryRoot,
            settingsCacheAuditEnabled: isDemo
                && arguments.contains("--aureus-ui-testing")
                && arguments.contains("--aureus-settings-cache-audit")
        )
    }
}
