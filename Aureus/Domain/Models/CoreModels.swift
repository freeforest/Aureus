import Foundation

struct Currency: Codable, Equatable, Sendable {
    let code: CurrencyCode
}

enum AccountKind: String, Codable, Sendable {
    case cash
    case bank
    case brokerage
    case other
}

struct Account: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let kind: AccountKind
    let currency: CurrencyCode
}

enum AssetContainerKind: String, CaseIterable, Codable, Sendable {
    case bankCash
    case stock
    case etf
    case fund
    case insurance
    case otherAsset
    case liability

    var title: String {
        switch self {
        case .bankCash: "Bank / Cash"
        case .stock: "Stock"
        case .etf: "ETF"
        case .fund: "Fund"
        case .insurance: "Insurance"
        case .otherAsset: "Other Asset"
        case .liability: "Liability"
        }
    }

    var isManualSecurity: Bool {
        self == .stock || self == .etf || self == .fund
    }
}

struct AssetContainer: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let accountID: UUID?
    let name: String
    let kind: AssetContainerKind
    let institution: String?
    let primaryCurrency: CurrencyCode
    let notes: String?
    let createdDate: CivilDate
    let updatedDate: CivilDate
}

struct MarketInstrument: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let symbol: String
    let mic: String
    let currency: CurrencyCode
    let displayName: String
}

struct Asset: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let containerID: UUID
    let name: String
    let currency: CurrencyCode
    let instrumentID: UUID?
}

enum TransactionKind: String, Codable, CaseIterable, Equatable, Sendable {
    case income
    case expense
    case transfer
    case buy
    case sell
    case dividend
    case interest
    case fee
}

struct Transaction: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let accountID: UUID
    let civilDate: CivilDate
    let amount: Money
    let kind: TransactionKind
}

struct Holding: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let accountID: UUID
    let instrumentID: UUID
    let quantity: AssetQuantity
    let originalCost: Money
}

enum TradeKind: String, Codable, Sendable {
    case buy
    case sell
}

struct Trade: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let holdingID: UUID
    let session: ExchangeSessionDate
    let quantity: AssetQuantity
    let price: MarketPrice
    let kind: TradeKind
}

struct Price: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let instrumentID: UUID
    let value: MarketPrice
    let observedAt: UTCInstant
    let providerIdentifier: String
    let quality: MarketDataQuality
}

struct Snapshot: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let date: CivilDate
    let createdAt: UTCInstant
    let totalCNY: Money
    let valuations: [FXValuation]
}

struct Portfolio: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let baseCurrency: CurrencyCode
}

struct Goal: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let target: Money
    let targetDate: CivilDate?
}

struct InsurancePolicy: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let assetID: UUID
    let name: String
    let premium: Money
}

struct Category: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let parentID: UUID?
    let name: String
}

struct Tag: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
}

struct ExchangeRate: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let rate: FXRate
    let referenceDate: CivilDate
    let fetchedAt: UTCInstant
    let providerIdentifier: String
}
