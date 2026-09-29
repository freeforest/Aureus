import Foundation

enum RuntimeEnvironment: String, Equatable, Sendable {
    case production
    case development
    case temporary

    static let productionBundleID = "com.aureus.wealthterminal"
    static let developmentBundleID = "com.aureus.wealthterminal.dev"

    static func buildIdentity(bundleID: String?, declaredEnvironment: String?) -> RuntimeEnvironment? {
        switch (bundleID, declaredEnvironment) {
        case (productionBundleID, "production"): .production
        case (developmentBundleID, "development"): .development
        default: nil
        }
    }

    var keychainService: String? {
        switch self {
        case .production: "com.aureus.wealthterminal.provider-credentials"
        case .development: "com.aureus.wealthterminal.dev.provider-credentials"
        case .temporary: nil
        }
    }

    var preferenceSuiteName: String? {
        switch self {
        case .production, .temporary: nil
        case .development: Self.developmentBundleID
        }
    }

    var displayName: String {
        switch self {
        case .production: "Aureus"
        case .development: "Aureus Dev"
        case .temporary: "Aureus Test"
        }
    }
}

enum RuntimeEnvironmentError: Error, Equatable, Sendable {
    case invalidBuildIdentity
    case invalidLaunchConfiguration
    case unsafeStorageRoot
    case invalidPreferenceSuite
}
