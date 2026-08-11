import Foundation

enum CachePolicyError: Error, Equatable, Sendable {
    case maximumOutOfRange
    case invalidWatermarks
    case overflow
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

    static let `default` = try! CachePolicyConfiguration(
        maximumBytes: defaultMaximumBytes,
        highWaterBasisPoints: 9_000,
        cleanupTargetBasisPoints: 8_000
    )

    init(
        maximumBytes: Int64,
        highWaterBasisPoints: Int64 = 9_000,
        cleanupTargetBasisPoints: Int64 = 8_000
    ) throws {
        guard (Self.minimumMaximumBytes...Self.maximumMaximumBytes).contains(maximumBytes) else {
            throw CachePolicyError.maximumOutOfRange
        }
        guard cleanupTargetBasisPoints > 0,
              cleanupTargetBasisPoints < highWaterBasisPoints,
              highWaterBasisPoints <= 10_000 else {
            throw CachePolicyError.invalidWatermarks
        }
        self.maximumBytes = maximumBytes
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
