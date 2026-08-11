import Foundation
import Testing
@testable import Aureus

private actor InMemoryCredentialStore: CredentialStore {
    private var values: [CredentialDescriptor: Data] = [:]

    func credential(for descriptor: CredentialDescriptor) async throws -> Data? {
        values[descriptor]
    }

    func store(_ credential: Data, for descriptor: CredentialDescriptor) async throws {
        values[descriptor] = credential
    }

    func deleteCredential(for descriptor: CredentialDescriptor) async throws {
        values.removeValue(forKey: descriptor)
    }
}

@Suite("Provider and credential boundaries")
struct ProviderBoundaryTests {
    private let clock = FixedClock(
        instant: UTCInstant(millisecondsSince1970: 1_768_435_200_000)
    )

    @Test("Synthetic success is deterministic and never production-labeled")
    func deterministicSyntheticSuccess() async throws {
        let provider = SyntheticMarketDataProvider(scenario: .success, clock: clock)
        let firstSearch = try await provider.search(query: "synthetic")
        let secondSearch = try await provider.search(query: "synthetic")
        let firstPrice = try await provider.latestPrice(for: firstSearch[0])
        let secondPrice = try await provider.latestPrice(for: secondSearch[0])

        #expect(firstSearch == secondSearch)
        #expect(firstPrice == secondPrice)
        #expect(provider.descriptor.kind == .synthetic)
        #expect(!provider.descriptor.isProduction)
        #expect(provider.descriptor.displayName.contains("Synthetic"))
    }

    @Test("Unsupported entitlement is explicit")
    func unsupportedEntitlement() async {
        let provider = SyntheticMarketDataProvider(scenario: .unsupported, clock: clock)
        #expect(await provider.capabilities().entitlement == .unsupportedMarket)
        var captured: ProviderBoundaryError?
        do {
            _ = try await provider.search(query: "synthetic")
        } catch let error as ProviderBoundaryError {
            captured = error
        } catch {
            Issue.record("Unexpected error type")
        }
        #expect(captured == .unsupportedEntitlement)
    }

    @Test("Rate-limited, stale, and offline are distinct")
    func providerStates() async throws {
        let rateLimited = SyntheticMarketDataProvider(scenario: .rateLimited, clock: clock)
        let stale = SyntheticMarketDataProvider(scenario: .stale, clock: clock)
        let offline = SyntheticMarketDataProvider(scenario: .offline, clock: clock)

        #expect(await rateLimited.capabilities().entitlement == .rateLimited)
        #expect(await stale.capabilities().entitlement == .stale)
        #expect(await offline.capabilities().entitlement == .offline)

        let instrument = try await stale.search(query: "synthetic")[0]
        #expect(try await stale.latestPrice(for: instrument).quality == .stale)
    }

    @Test("Synthetic FX preserves USD to CNY direction")
    func syntheticFX() async throws {
        let provider = SyntheticFXRateProvider(clock: clock)
        let rate = try await provider.rate(
            source: .usd,
            target: .cny,
            on: CivilDate(canonical: "2026-01-15")
        )
        #expect(rate.rate.sourceCurrency == .usd)
        #expect(rate.rate.targetCurrency == .cny)
        #expect(rate.providerIdentifier == "synthetic.stage2.fx")
        #expect(!provider.descriptor.isProduction)
    }

    @Test("Production credential policy is Keychain-only and fake is in-memory")
    func credentialBoundary() async throws {
        #expect(ProductionCredentialPolicy.storage == .keychainOnly)
        let store = InMemoryCredentialStore()
        let descriptor = CredentialDescriptor(
            providerIdentifier: "synthetic.stage2.market",
            accountIdentifier: "synthetic-test-account"
        )
        let value = Data([0x01, 0x02, 0x03])
        try await store.store(value, for: descriptor)
        #expect(try await store.credential(for: descriptor) == value)
        try await store.deleteCredential(for: descriptor)
        #expect(try await store.credential(for: descriptor) == nil)
    }
}
