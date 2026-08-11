import Foundation

enum SyntheticProviderScenario: Equatable, Sendable {
    case success
    case unsupported
    case rateLimited
    case stale
    case offline
}

struct SyntheticMarketDataProvider: MarketDataProvider {
    let scenario: SyntheticProviderScenario
    let clock: any Clock

    let descriptor = ProviderDescriptor(
        identifier: "synthetic.stage2.market",
        displayName: "Synthetic Stage 2 Market Provider",
        kind: .synthetic
    )

    func capabilities() async -> MarketProviderCapabilities {
        let entitlement: MarketEntitlementState
        switch scenario {
        case .success:
            entitlement = .basic
        case .unsupported:
            entitlement = .unsupportedMarket
        case .rateLimited:
            entitlement = .rateLimited
        case .stale:
            entitlement = .stale
        case .offline:
            entitlement = .offline
        }
        return MarketProviderCapabilities(
            provider: descriptor,
            entitlement: entitlement,
            supportedMICs: ["XSYN"],
            supportsSearch: true,
            supportsHistoricalPrices: true
        )
    }

    func search(query: String) async throws -> [MarketInstrument] {
        try validateScenario()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderBoundaryError.invalidRequest
        }
        return [
            MarketInstrument(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000201")!,
                symbol: "SYN-CNY",
                mic: "XSYN",
                currency: .cny,
                displayName: "Synthetic Orchard Holdings"
            )
        ]
    }

    func latestPrice(for instrument: MarketInstrument) async throws -> Price {
        try validateScenario()
        let quality: MarketDataQuality = scenario == .stale ? .stale : .current
        return Price(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000202")!,
            instrumentID: instrument.id,
            value: try MarketPrice(
                decimal: FixedPointMath.parseCanonical("123.45678901"),
                quoteCurrency: instrument.currency
            ),
            observedAt: clock.now(),
            providerIdentifier: descriptor.identifier,
            quality: quality
        )
    }

    private func validateScenario() throws {
        switch scenario {
        case .success, .stale:
            return
        case .unsupported:
            throw ProviderBoundaryError.unsupportedEntitlement
        case .rateLimited:
            throw ProviderBoundaryError.rateLimited
        case .offline:
            throw ProviderBoundaryError.offline
        }
    }
}

struct SyntheticFXRateProvider: FXRateProvider {
    let clock: any Clock

    let descriptor = ProviderDescriptor(
        identifier: "synthetic.stage2.fx",
        displayName: "Synthetic Stage 2 FX Provider",
        kind: .synthetic
    )

    func rate(
        source: CurrencyCode,
        target: CurrencyCode,
        on date: CivilDate
    ) async throws -> ExchangeRate {
        guard target == .cny else { throw ProviderBoundaryError.unsupportedEntitlement }
        let rate: FXRate
        if source == .cny {
            rate = .cnyIdentity
        } else {
            rate = try FXRate(
                decimal: FixedPointMath.parseCanonical("7.1250000000"),
                sourceCurrency: .usd,
                targetCurrency: .cny
            )
        }
        return ExchangeRate(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000203")!,
            rate: rate,
            referenceDate: date,
            fetchedAt: clock.now(),
            providerIdentifier: descriptor.identifier
        )
    }
}
