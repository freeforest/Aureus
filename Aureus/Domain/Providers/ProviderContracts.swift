import Foundation

enum MarketEntitlementState: String, CaseIterable, Codable, Equatable, Sendable {
    case basic
    case proOrHigher
    case unknown
    case invalidOrExpired
    case unsupportedMarket
    case upgradeRequired
    case rateLimited
    case stale
    case delayed
    case offline
    case missing
}

enum MarketDataQuality: String, Codable, Equatable, Sendable {
    case current
    case stale
    case delayed
    case offline
    case missing
}

struct ProviderDescriptor: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case synthetic
        case production
    }

    let identifier: String
    let displayName: String
    let kind: Kind

    var isProduction: Bool { kind == .production }
}

struct MarketProviderCapabilities: Codable, Equatable, Sendable {
    let provider: ProviderDescriptor
    let entitlement: MarketEntitlementState
    let supportedMICs: Set<String>
    let supportsSearch: Bool
    let supportsHistoricalPrices: Bool
}

enum ProviderBoundaryError: Error, Equatable, Sendable {
    case unsupportedEntitlement
    case rateLimited
    case offline
    case missing
    case invalidRequest
}

protocol MarketDataProvider: Sendable {
    var descriptor: ProviderDescriptor { get }

    func capabilities() async -> MarketProviderCapabilities
    func search(query: String) async throws -> [MarketInstrument]
    func latestPrice(for instrument: MarketInstrument) async throws -> Price
}

protocol FXRateProvider: Sendable {
    var descriptor: ProviderDescriptor { get }

    func rate(
        source: CurrencyCode,
        target: CurrencyCode,
        on date: CivilDate
    ) async throws -> ExchangeRate
}

struct CredentialDescriptor: Hashable, Codable, Sendable {
    let providerIdentifier: String
    let accountIdentifier: String
}

protocol CredentialStore: Sendable {
    func credential(for descriptor: CredentialDescriptor) async throws -> Data?
    func store(_ credential: Data, for descriptor: CredentialDescriptor) async throws
    func deleteCredential(for descriptor: CredentialDescriptor) async throws
}

enum ProductionCredentialStorage: String, Codable, Sendable {
    case keychainOnly
}

enum ProductionCredentialPolicy {
    static let storage: ProductionCredentialStorage = .keychainOnly
}
