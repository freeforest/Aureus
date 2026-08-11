import Foundation

struct RuntimePaths: Equatable, Sendable {
    let permanentDatabaseURL: URL
    let marketCacheDatabaseURL: URL

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
        return RuntimePaths(
            permanentDatabaseURL: applicationSupport
                .appendingPathComponent("Aureus", isDirectory: true)
                .appendingPathComponent("Permanent", isDirectory: true)
                .appendingPathComponent("aureus.sqlite", isDirectory: false),
            marketCacheDatabaseURL: caches
                .appendingPathComponent("Aureus", isDirectory: true)
                .appendingPathComponent("Market", isDirectory: true)
                .appendingPathComponent("market-cache.sqlite", isDirectory: false)
        )
    }

    static func temporary(root: URL) -> RuntimePaths {
        RuntimePaths(
            permanentDatabaseURL: root
                .appendingPathComponent("Permanent", isDirectory: true)
                .appendingPathComponent("aureus.sqlite", isDirectory: false),
            marketCacheDatabaseURL: root
                .appendingPathComponent("MarketCache", isDirectory: true)
                .appendingPathComponent("market-cache.sqlite", isDirectory: false)
        )
    }
}

enum AppDataMode: String, Equatable, Sendable {
    case empty
    case syntheticDemo
}

struct LaunchConfiguration: Equatable, Sendable {
    let dataMode: AppDataMode
    let usesTemporaryStores: Bool
    let temporaryRoot: URL?

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
            dataMode: isDemo ? .syntheticDemo : .empty,
            usesTemporaryStores: isTemporary,
            temporaryRoot: temporaryRoot
        )
    }
}
