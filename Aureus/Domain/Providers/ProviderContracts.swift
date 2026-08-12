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

enum MarketDataQuality: String, CaseIterable, Codable, Equatable, Sendable {
    case current
    case stale
    case delayed
    case offline
    case missing
    case providerError
}

enum MarketFreshness: String, Codable, Equatable, Sendable {
    case realTime
    case delayed
    case endOfDay
    case stale
    case missing
    case unknown
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

struct MarketCapability: Codable, Equatable, Identifiable, Sendable {
    var id: String { mic }

    let mic: String
    let minimumEntitlement: MarketEntitlementState
    let observedEntitlement: MarketEntitlementState
    let freshness: MarketFreshness
    let supportsSearch: Bool
    let supportsHistoricalBars: Bool
    let supportsCorporateActions: Bool
    let evidenceStatus: String
}

struct MarketProviderCapabilities: Codable, Equatable, Sendable {
    let provider: ProviderDescriptor
    let entitlement: MarketEntitlementState
    let observedPlanName: String?
    let markets: [MarketCapability]
    let supportsSearch: Bool
    let supportsHistoricalPrices: Bool
    let supportsCorporateActions: Bool
    let observedAt: UTCInstant?

    var supportedMICs: Set<String> {
        Set(markets.compactMap { market in
            switch market.observedEntitlement {
            case .basic, .proOrHigher:
                market.mic
            default:
                nil
            }
        })
    }
}

enum MarketInterval: String, CaseIterable, Codable, Sendable {
    case oneMinute = "1min"
    case fiveMinutes = "5min"
    case fifteenMinutes = "15min"
    case thirtyMinutes = "30min"
    case fortyFiveMinutes = "45min"
    case oneHour = "1h"
    case twoHours = "2h"
    case fourHours = "4h"
    case eightHours = "8h"
    case oneDay = "1day"
    case oneWeek = "1week"
    case oneMonth = "1month"

    var isIntraday: Bool {
        switch self {
        case .oneDay, .oneWeek, .oneMonth: false
        default: true
        }
    }
}

enum MarketAdjustment: String, CaseIterable, Codable, Sendable {
    case all
    case splits
    case dividends
    case none
}

struct MarketHistoryRequest: Codable, Equatable, Sendable {
    let instrument: MarketInstrument
    let interval: MarketInterval
    let adjustment: MarketAdjustment
    let startDate: CivilDate?
    let endDate: CivilDate?
    let outputSize: Int

    init(
        instrument: MarketInstrument,
        interval: MarketInterval,
        adjustment: MarketAdjustment,
        startDate: CivilDate? = nil,
        endDate: CivilDate? = nil,
        outputSize: Int = 500
    ) throws {
        guard (1...5_000).contains(outputSize),
              startDate == nil || endDate == nil || startDate! <= endDate! else {
            throw ProviderBoundaryError.invalidRequest
        }
        self.instrument = instrument
        self.interval = interval
        self.adjustment = adjustment
        self.startDate = startDate
        self.endDate = endDate
        self.outputSize = outputSize
    }
}

struct MarketOHLCVBar: Codable, Equatable, Sendable {
    let sessionDate: CivilDate
    let openedAt: UTCInstant?
    let open: MarketQuotePrice
    let high: MarketQuotePrice
    let low: MarketQuotePrice
    let close: MarketQuotePrice
    let volume: AssetQuantity?
    let adjustment: MarketAdjustment
    let providerIdentifier: String
    let fetchedAt: UTCInstant
    let freshness: MarketFreshness

    init(
        sessionDate: CivilDate,
        openedAt: UTCInstant?,
        open: MarketQuotePrice,
        high: MarketQuotePrice,
        low: MarketQuotePrice,
        close: MarketQuotePrice,
        volume: AssetQuantity?,
        adjustment: MarketAdjustment,
        providerIdentifier: String,
        fetchedAt: UTCInstant,
        freshness: MarketFreshness
    ) throws {
        let currency = open.quoteCurrency
        guard high.quoteCurrency == currency,
              low.quoteCurrency == currency,
              close.quoteCurrency == currency,
              high.coefficient >= max(open.coefficient, close.coefficient),
              high.coefficient >= low.coefficient,
              low.coefficient <= min(open.coefficient, close.coefficient),
              volume?.coefficient ?? 0 >= 0 else {
            throw ProviderBoundaryError.invalidPayload
        }
        self.sessionDate = sessionDate
        self.openedAt = openedAt
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
        self.adjustment = adjustment
        self.providerIdentifier = providerIdentifier
        self.fetchedAt = fetchedAt
        self.freshness = freshness
    }
}

struct MarketHistoryPage: Codable, Equatable, Sendable {
    let instrument: MarketInstrument
    let bars: [MarketOHLCVBar]
    let nextEndDate: CivilDate?
    let sourceRevision: String?
    let providerIdentifier: String
}

enum CorporateActionKind: String, Codable, Sendable {
    case split
    case dividend
}

struct MarketCorporateAction: Codable, Equatable, Sendable {
    let id: String
    let instrument: MarketInstrument
    let kind: CorporateActionKind
    let effectiveDate: CivilDate
    let amount: MarketQuotePrice?
    let splitFrom: Int64?
    let splitTo: Int64?
    let providerIdentifier: String
    let fetchedAt: UTCInstant
}

struct MarketQuote: Codable, Equatable, Sendable {
    let instrument: MarketInstrument
    let price: MarketQuotePrice
    let observedAt: UTCInstant
    let fetchedAt: UTCInstant
    let providerIdentifier: String
    let quality: MarketDataQuality
    let freshness: MarketFreshness
}

struct ProviderUsageObservation: Codable, Equatable, Sendable {
    let planName: String?
    let entitlement: MarketEntitlementState
    let perMinuteLimit: Int?
    let dailyLimit: Int?
    let observedAt: UTCInstant
}

enum ProviderBoundaryError: Error, Equatable, Sendable {
    case missingCredential
    case invalidOrExpired
    case unsupportedEntitlement
    case unsupportedMarket(String)
    case upgradeRequired(String)
    case rateLimited(retryAfterMilliseconds: Int64?)
    case offline
    case missing
    case timeout
    case cancelled
    case invalidRequest
    case invalidPayload
    case providerError(statusCode: Int?)
    case retentionUnverified
}

protocol MarketDataProvider: Sendable {
    var descriptor: ProviderDescriptor { get }

    func capabilities() async -> MarketProviderCapabilities
    func validateCredential() async throws -> ProviderUsageObservation
    func credentialDidChange() async
    func disconnect() async
    func search(query: String) async throws -> [MarketInstrument]
    func latestQuote(for instrument: MarketInstrument) async throws -> MarketQuote
    func historicalBars(_ request: MarketHistoryRequest) async throws -> MarketHistoryPage
    func corporateActions(
        for instrument: MarketInstrument,
        from startDate: CivilDate?,
        through endDate: CivilDate?
    ) async throws -> [MarketCorporateAction]
}

extension MarketDataProvider {
    func validateCredential() async throws -> ProviderUsageObservation {
        throw ProviderBoundaryError.missingCredential
    }

    func credentialDidChange() async {}
    func disconnect() async {}
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
