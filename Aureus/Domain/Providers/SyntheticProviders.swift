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
        identifier: "synthetic.stage6.market",
        displayName: "Synthetic Stage 6 Market Provider",
        kind: .synthetic
    )

    func capabilities() async -> MarketProviderCapabilities {
        let entitlement: MarketEntitlementState
        switch scenario {
        case .success: entitlement = .basic
        case .unsupported: entitlement = .unsupportedMarket
        case .rateLimited: entitlement = .rateLimited
        case .stale: entitlement = .stale
        case .offline: entitlement = .offline
        }
        let marketObservation: [(String, ProviderLiveObservation, [String])] = [
            ("US", .mixed, ["XNAS", "XNYS"]),
            ("XHKG", .succeeded, ["XHKG"]),
            ("XSHG", .denied, ["XSHG"]),
            ("XSHE", .notVerified, []),
            ("XJPX", .notVerified, [])
        ]
        let endpointObservation: [MarketProviderEndpoint: ProviderLiveObservation] = [
            .symbolSearch: .succeeded,
            .latestQuote: .denied,
            .historicalOHLCV: .mixed,
            .splits: .notVerified,
            .dividends: .succeeded
        ]
        return MarketProviderCapabilities(
            provider: descriptor,
            entitlement: entitlement,
            observedPlanName: "Synthetic",
            markets: marketObservation.map { mic, live, rawMICs in
                MarketCapability(
                    mic: mic,
                    minimumEntitlement: .basic,
                    observedEntitlement: live == .succeeded ? entitlement : .unknown,
                    freshness: scenario == .stale ? .stale : .unknown,
                    catalogEvidence: .notVerified,
                    liveObservation: scenario == .unsupported ? .denied : live,
                    liveObservedMICs: rawMICs,
                    supportsSearch: true,
                    supportsHistoricalBars: true,
                    supportsCorporateActions: false,
                    evidenceStatus: "SYNTHETIC"
                )
            },
            supportsSearch: true,
            supportsHistoricalPrices: true,
            supportsCorporateActions: false,
            endpointCapabilities: MarketProviderEndpoint.allCases.map {
                ProviderEndpointCapability(
                    endpoint: $0,
                    minimumPlanName: "Synthetic",
                    creditWeight: 1,
                    catalogEvidence: .notVerified,
                    liveObservation: scenario == .unsupported
                        ? .denied
                        : endpointObservation[$0] ?? .notVerified,
                    observedEntitlement: entitlement
                )
            },
            observedAt: clock.now()
        )
    }

    func validateCredential() async throws -> ProviderUsageObservation {
        try validateScenario()
        return ProviderUsageObservation(
            planName: "Synthetic",
            entitlement: .basic,
            perMinuteLimit: 8,
            dailyLimit: .capped(800),
            observedAt: clock.now()
        )
    }

    func search(query: String) async throws -> [MarketInstrument] {
        try validateScenario()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderBoundaryError.invalidRequest
        }
        return [syntheticInstrument]
    }

    func latestQuote(for instrument: MarketInstrument) async throws -> MarketQuote {
        try validateScenario()
        return MarketQuote(
            instrument: instrument,
            price: try MarketQuotePrice(
                decimal: FixedPointMath.parseCanonical("123.45678901"),
                quoteCurrency: instrument.currency
            ),
            observedAt: clock.now(),
            fetchedAt: clock.now(),
            providerIdentifier: descriptor.identifier,
            quality: scenario == .stale ? .stale : .current,
            freshness: scenario == .stale ? .stale : .endOfDay
        )
    }

    func historicalBars(_ request: MarketHistoryRequest) async throws -> MarketHistoryPage {
        try validateScenario()
        let date = try CivilDate(year: 2026, month: 1, day: 15)
        let currency = request.instrument.currency
        let bar = try MarketOHLCVBar(
            sessionDate: date,
            openedAt: nil,
            open: MarketQuotePrice(coefficient: 10_000_000_000, quoteCurrency: currency),
            high: MarketQuotePrice(coefficient: 11_000_000_000, quoteCurrency: currency),
            low: MarketQuotePrice(coefficient: 9_000_000_000, quoteCurrency: currency),
            close: MarketQuotePrice(coefficient: 10_500_000_000, quoteCurrency: currency),
            volume: AssetQuantity(coefficient: 123_000_000_000),
            adjustment: request.adjustment,
            providerIdentifier: descriptor.identifier,
            fetchedAt: clock.now(),
            freshness: scenario == .stale ? .stale : .endOfDay
        )
        return MarketHistoryPage(
            instrument: request.instrument,
            bars: [bar],
            nextEndDate: nil,
            sourceRevision: "synthetic-v1",
            providerIdentifier: descriptor.identifier
        )
    }

    func corporateActions(
        for instrument: MarketInstrument,
        from startDate: CivilDate?,
        through endDate: CivilDate?
    ) async throws -> [MarketCorporateAction] {
        try validateScenario()
        let date = try CivilDate(year: 2025, month: 12, day: 15)
        return [
            MarketCorporateAction(
                id: "synthetic-split-1",
                instrument: instrument,
                kind: .split,
                effectiveDate: date,
                amount: nil,
                splitFrom: 2,
                splitTo: 1,
                providerIdentifier: descriptor.identifier,
                fetchedAt: clock.now()
            )
        ]
    }

    private var syntheticInstrument: MarketInstrument {
        MarketInstrument(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000201")!,
            symbol: "SYN-CNY",
            mic: "XSYN",
            currency: .cny,
            displayName: "Synthetic Orchard Holdings"
        )
    }

    private func validateScenario() throws {
        switch scenario {
        case .success, .stale:
            return
        case .unsupported:
            throw ProviderBoundaryError.unsupportedEntitlement
        case .rateLimited:
            throw ProviderBoundaryError.rateLimited(retryAfterMilliseconds: nil)
        case .offline:
            throw ProviderBoundaryError.offline
        }
    }
}

struct SyntheticFXRateProvider: FXRateProvider {
    let clock: any Clock

    let descriptor = ProviderDescriptor(
        identifier: "synthetic.stage6.fx",
        displayName: "Synthetic Stage 6 FX Provider",
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
            providerIdentifier: descriptor.identifier,
            provenance: .synthetic,
            freshness: .endOfDay
        )
    }
}

actor InMemoryCredentialStore: CredentialStore {
    private var values: [CredentialDescriptor: Data] = [:]
    private var injectedError: CredentialStoreError?

    func credential(for descriptor: CredentialDescriptor) throws -> Data? {
        if let injectedError { throw injectedError }
        return values[descriptor]
    }

    func store(_ credential: Data, for descriptor: CredentialDescriptor) throws {
        if let injectedError { throw injectedError }
        values[descriptor] = credential
    }

    func deleteCredential(for descriptor: CredentialDescriptor) throws {
        if let injectedError { throw injectedError }
        values.removeValue(forKey: descriptor)
    }

    func setInjectedError(_ error: CredentialStoreError?) {
        injectedError = error
    }
}
