import CryptoKit
import Foundation
import Testing
@testable import Aureus

@Suite("Market cache isolation")
struct CacheIsolationTests {
    @Test("Frozen cache policy validates capacity and watermarks")
    func cachePolicy() throws {
        let policy = CachePolicyConfiguration.default
        #expect(policy.maximumBytes == 512 * CachePolicyConfiguration.mebibyte)
        #expect(policy.highWaterBytes == policy.maximumBytes * 9 / 10)
        #expect(policy.cleanupTargetBytes == policy.maximumBytes * 8 / 10)

        var rejectedLow = false
        do {
            _ = try CachePolicyConfiguration(maximumBytes: 127 * CachePolicyConfiguration.mebibyte)
        } catch CachePolicyError.maximumOutOfRange {
            rejectedLow = true
        }
        #expect(rejectedLow)

        let maximum = try CachePolicyConfiguration(
            maximumBytes: 4 * CachePolicyConfiguration.gibibyte
        )
        #expect(maximum.highWaterBasisPoints == 9_000)
        #expect(maximum.cleanupTargetBasisPoints == 8_000)
    }

    @Test("Cache reset cannot change permanent URL, hash, schema, or sentinels")
    func completeResetIsolationProof() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let permanentURL = root.appendingPathComponent("permanent/aureus.sqlite")
        let cacheURL = root.appendingPathComponent("cache/market-cache.sqlite")
        let wealth = try WealthStore(databaseURL: permanentURL)
        let cache = try MarketCacheStore(databaseURL: cacheURL)

        try await wealth.insertIsolationSentinel(
            id: "00000000-0000-4000-8000-000000000501",
            name: "Synthetic Permanent Sentinel"
        )
        try await wealth.seedSyntheticWealth()
        try await cache.seedSyntheticCache()
        try await wealth.checkpoint()

        let permanentURLBefore = wealth.databaseURL
        let permanentHashBefore = try sha256(of: permanentURL)
        let permanentSchemaBefore = try await wealth.schemaVersion()
        let sentinelsBefore = try await wealth.isolationSentinels()
        let wealthRecordsBefore = try await wealth.fetchWealthContainers()
        #expect(try await cache.cachedRowCount() == 2)

        try await cache.reset()

        #expect(try await cache.cachedRowCount() == 0)
        #expect(try await cache.schemaVersion() == 1)
        let reopenedCache = try MarketCacheStore(databaseURL: cacheURL)
        #expect(try await reopenedCache.schemaVersion() == 1)

        let permanentURLAfter = wealth.databaseURL
        let permanentHashAfter = try sha256(of: permanentURL)
        let permanentSchemaAfter = try await wealth.schemaVersion()
        let sentinelsAfter = try await wealth.isolationSentinels()
        let wealthRecordsAfter = try await wealth.fetchWealthContainers()

        #expect(permanentURLBefore == permanentURLAfter)
        #expect(permanentHashBefore == permanentHashAfter)
        #expect(permanentSchemaBefore == permanentSchemaAfter)
        #expect(sentinelsBefore == sentinelsAfter)
        #expect(sentinelsAfter == ["Synthetic Permanent Sentinel"])
        #expect(wealthRecordsBefore == wealthRecordsAfter)
        #expect(wealthRecordsAfter.count == 7)

        try await reopenedCache.seedSyntheticCache()
        #expect(try await reopenedCache.cachedRowCount() == 2)
    }

    private func sha256(of url: URL) throws -> [UInt8] {
        Array(SHA256.hash(data: try Data(contentsOf: url)))
    }
}
