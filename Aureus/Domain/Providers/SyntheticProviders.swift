import Foundation

enum SyntheticProviderScenario: Equatable, Sendable {
    case success
    case unsupported
    case rateLimited
    case stale
    case offline
}

enum SyntheticMarketFailureScenario: String, CaseIterable, Equatable, Sendable {
    case searchOffline = "search-offline"
    case searchTimeout = "search-timeout"
    case searchMissing = "search-missing"
    case historyOffline = "history-offline"
    case historyTimeout = "history-timeout"
    case historyMissing = "history-missing"

    var searchFailure: ProviderBoundaryError? {
        switch self {
        case .searchOffline: .offline
        case .searchTimeout: .timeout
        case .searchMissing: .missing
        case .historyOffline, .historyTimeout, .historyMissing: nil
        }
    }

    var historyFailure: ProviderBoundaryError? {
        switch self {
        case .historyOffline: .offline
        case .historyTimeout: .timeout
        case .historyMissing: .missing
        case .searchOffline, .searchTimeout, .searchMissing: nil
        }
    }
}

struct SyntheticMarketDataProvider: MarketDataProvider {
    let scenario: SyntheticProviderScenario
    let clock: any Clock
    let failureScenario: SyntheticMarketFailureScenario?

    init(scenario: SyntheticProviderScenario, clock: any Clock,
         failureScenario: SyntheticMarketFailureScenario? = nil) {
        self.scenario = scenario
        self.clock = clock
        self.failureScenario = failureScenario
    }

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
        if let error = failureScenario?.searchFailure { throw error }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderBoundaryError.invalidRequest
        }
        return [syntheticInstrument, syntheticInstrumentTwo]
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
        if let error = failureScenario?.historyFailure { throw error }
        let currency = request.instrument.currency
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2025, month: 8, day: 1))!
        let allBars = try (0..<120).map { index in
            let date = calendar.date(byAdding: .day, value: index, to: start)!
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            let close = Int64(10_000_000_000 + index * 21_000_000 + (index % 7) * 8_000_000)
            return try MarketOHLCVBar(
                sessionDate: CivilDate(year: parts.year!, month: parts.month!, day: parts.day!),
                openedAt: nil,
                open: MarketQuotePrice(coefficient: close - 12_000_000, quoteCurrency: currency),
                high: MarketQuotePrice(coefficient: close + 31_000_000, quoteCurrency: currency),
                low: MarketQuotePrice(coefficient: close - 37_000_000, quoteCurrency: currency),
                close: MarketQuotePrice(coefficient: close, quoteCurrency: currency),
                volume: AssetQuantity(coefficient: Int64(100_000_000_000 + index * 1_000_000_000)),
                adjustment: request.adjustment,
                providerIdentifier: descriptor.identifier,
                fetchedAt: clock.now(),
                freshness: scenario == .stale ? .stale : .endOfDay
            )
        }
        let bars = Array(allBars.suffix(min(request.outputSize, allBars.count)))
        return MarketHistoryPage(
            instrument: request.instrument,
            bars: bars,
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

    private var syntheticInstrumentTwo: MarketInstrument {
        MarketInstrument(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000202")!,
            symbol: "SYN-JPY",
            mic: "XJPX",
            currency: .jpy,
            displayName: "Synthetic Cedar Industries"
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
