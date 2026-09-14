import Foundation

enum CachePolicyError: Error, Equatable, Sendable {
    case maximumOutOfRange
    case invalidWatermarks
    case overflow
    case persistentRetentionUnverified
    case capacityCannotBeSatisfied
    case invalidEntry
}

enum MarketCacheDataType: String, CaseIterable, Codable, Sendable {
    case latestQuote = "latest_quote"
    case marketStatus = "market_status"
    case symbolSearch = "symbol_search"
    case symbolMetadata = "symbol_metadata"
    case eodRecent = "eod_recent"
    case eodHistorical = "eod_historical"
    case intraday
    case corporateAction = "corporate_action"
    case derivedHeatmap = "derived_heatmap"
    case derivedIndicator = "derived_indicator"
    case fxRate = "fx_rate"

    var timeToLiveMilliseconds: Int64 {
        let minute: Int64 = 60_000
        let hour = 60 * minute
        let day = 24 * hour
        switch self {
        case .latestQuote, .marketStatus, .intraday, .derivedHeatmap:
            return 15 * minute
        case .symbolSearch, .symbolMetadata:
            return 7 * day
        case .eodRecent:
            return 12 * hour
        case .eodHistorical:
            return 30 * day
        case .corporateAction, .derivedIndicator, .fxRate:
            return 24 * hour
        }
    }

    var maximumRetentionMilliseconds: Int64? {
        if self == .intraday { return 30 * 24 * 60 * 60 * 1_000 }
        return nil
    }

    var cleanupPriority: Int {
        switch self {
        case .derivedHeatmap, .derivedIndicator: 0
        case .intraday: 1
        case .latestQuote, .marketStatus, .symbolSearch, .symbolMetadata: 2
        case .eodRecent, .eodHistorical, .corporateAction, .fxRate: 3
        }
    }
}

enum CacheDeletionPolicy: String, Codable, Sendable {
    case recoverable
    case disconnect
    case termination
}

enum ProviderCacheAuthorization: Equatable, Sendable {
    case authorized
    case unverified
}

struct CachePolicyConfiguration: Codable, Equatable, Sendable {
    static let mebibyte: Int64 = 1_048_576
    static let gibibyte: Int64 = 1_073_741_824
    static let minimumMaximumBytes = 128 * mebibyte
    static let maximumMaximumBytes = 4 * gibibyte
    static let defaultMaximumBytes = 512 * mebibyte

    let maximumBytes: Int64
    let highWaterBasisPoints: Int64
    let cleanupTargetBasisPoints: Int64

    static let `default`: CachePolicyConfiguration = {
        do {
            return try CachePolicyConfiguration(
                maximumBytes: defaultMaximumBytes,
                highWaterBasisPoints: 9_000,
                cleanupTargetBasisPoints: 8_000
            )
        } catch {
            preconditionFailure("Frozen cache policy is invalid")
        }
    }()

    init(
        maximumBytes: Int64,
        highWaterBasisPoints: Int64 = 9_000,
        cleanupTargetBasisPoints: Int64 = 8_000
    ) throws {
        guard (Self.minimumMaximumBytes...Self.maximumMaximumBytes).contains(maximumBytes) else {
            throw CachePolicyError.maximumOutOfRange
        }
        try self.init(
            uncheckedMaximumBytes: maximumBytes,
            highWaterBasisPoints: highWaterBasisPoints,
            cleanupTargetBasisPoints: cleanupTargetBasisPoints
        )
    }

    /// Allows bounded, small synthetic databases without weakening production validation.
    static func testing(maximumBytes: Int64) throws -> CachePolicyConfiguration {
        guard maximumBytes > 0 else { throw CachePolicyError.maximumOutOfRange }
        return try CachePolicyConfiguration(
            uncheckedMaximumBytes: maximumBytes,
            highWaterBasisPoints: 9_000,
            cleanupTargetBasisPoints: 8_000
        )
    }

    private init(
        uncheckedMaximumBytes: Int64,
        highWaterBasisPoints: Int64,
        cleanupTargetBasisPoints: Int64
    ) throws {
        guard cleanupTargetBasisPoints > 0,
              cleanupTargetBasisPoints < highWaterBasisPoints,
              highWaterBasisPoints <= 10_000 else {
            throw CachePolicyError.invalidWatermarks
        }
        maximumBytes = uncheckedMaximumBytes
        self.highWaterBasisPoints = highWaterBasisPoints
        self.cleanupTargetBasisPoints = cleanupTargetBasisPoints
    }

    var highWaterBytes: Int64 {
        maximumBytes * highWaterBasisPoints / 10_000
    }

    var cleanupTargetBytes: Int64 {
        maximumBytes * cleanupTargetBasisPoints / 10_000
    }
}
