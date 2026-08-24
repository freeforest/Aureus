import Foundation
import Testing
@testable import Aureus

private enum SyntheticTransportStep: Sendable {
    case response(status: Int, body: String, headers: [String: String] = [:])
    case urlError(Int)
}

private struct RecordedHTTPRequest: Sendable {
    let url: String
    let authorization: String?
    let timeout: TimeInterval
}

private actor ScriptedHTTPTransport: HTTPTransport {
    private var steps: [SyntheticTransportStep]
    private var recorded: [RecordedHTTPRequest] = []

    init(_ steps: [SyntheticTransportStep]) {
        self.steps = steps
    }

    func data(for request: URLRequest) throws -> HTTPTransportResponse {
        recorded.append(RecordedHTTPRequest(
            url: request.url?.absoluteString ?? "",
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            timeout: request.timeoutInterval
        ))
        guard !steps.isEmpty else { throw URLError(.resourceUnavailable) }
        switch steps.removeFirst() {
        case let .response(status, body, headers):
            return HTTPTransportResponse(
                data: Data(body.utf8),
                statusCode: status,
                headers: headers.reduce(into: [:]) { $0[$1.key.lowercased()] = $1.value }
            )
        case let .urlError(raw):
            throw URLError(URLError.Code(rawValue: raw))
        }
    }

    func requests() -> [RecordedHTTPRequest] { recorded }
}

private actor RoutingHTTPTransport: HTTPTransport {
    private let routes: [String: HTTPTransportResponse]
    private var paths: [String] = []

    init(routes: [String: HTTPTransportResponse]) {
        self.routes = routes
    }

    func data(for request: URLRequest) throws -> HTTPTransportResponse {
        let path = request.url?.path ?? ""
        paths.append(path)
        guard let response = routes[path] else { throw URLError(.unsupportedURL) }
        return response
    }

    func requestedPaths() -> [String] { paths }
}

private actor RecordingProviderSleeper: ProviderSleeper {
    private var values: [Int64] = []

    func sleep(milliseconds: Int64) throws {
        try Task.checkCancellation()
        values.append(milliseconds)
    }

    func delays() -> [Int64] { values }
}

private actor CancellationHTTPTransport: HTTPTransport {
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancellationCount = 0
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
    private var calls = 0

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        calls += 1
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        do {
            try await Task.sleep(for: .seconds(60))
            return HTTPTransportResponse(data: Data(), statusCode: 200, headers: [:])
        } catch {
            cancellationCount += 1
            let waiters = cancellationWaiters
            cancellationWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
            throw error
        }
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func waitUntilCancelled() async {
        guard cancellationCount == 0 else { return }
        await withCheckedContinuation { continuation in
            cancellationWaiters.append(continuation)
        }
    }

    func callCount() -> Int { calls }
}

private actor ControlledHTTPTransport: HTTPTransport {
    private var calls = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var responseWaiters: [CheckedContinuation<HTTPTransportResponse, Never>] = []

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        calls += 1
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        return await withCheckedContinuation { continuation in
            responseWaiters.append(continuation)
        }
    }

    func waitUntilStarted() async {
        guard calls == 0 else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseAll(with response: HTTPTransportResponse) {
        let waiters = responseWaiters
        responseWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: response) }
    }

    func callCount() -> Int { calls }
}

private actor GenerationalHTTPTransport: HTTPTransport {
    private var calls = 0
    private var pending: [Int: CheckedContinuation<HTTPTransportResponse, Error>] = [:]
    private var callWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var cancelledCalls: Set<Int> = []
    private var cancellationWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        calls += 1
        let call = calls
        let ready = callWaiters.filter { $0.0 <= calls }
        callWaiters.removeAll { $0.0 <= calls }
        for (_, waiter) in ready { waiter.resume() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[call] = continuation
            }
        } onCancel: {
            Task { await self.recordCancellation(call: call) }
        }
    }

    func waitForCallCount(_ target: Int) async {
        guard calls < target else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append((target, continuation))
        }
    }

    func waitForCancellation(call: Int) async {
        guard !cancelledCalls.contains(call) else { return }
        await withCheckedContinuation { continuation in
            cancellationWaiters[call, default: []].append(continuation)
        }
    }

    private func recordCancellation(call: Int) {
        cancelledCalls.insert(call)
        let waiters = cancellationWaiters.removeValue(forKey: call) ?? []
        for waiter in waiters { waiter.resume() }
    }

    func succeed(call: Int, response: HTTPTransportResponse) {
        pending.removeValue(forKey: call)?.resume(returning: response)
    }

    func failCancelled(call: Int) {
        pending.removeValue(forKey: call)?.resume(throwing: URLError(.cancelled))
    }

    func callCount() -> Int { calls }
    func wasCancelled(call: Int) -> Bool { cancelledCalls.contains(call) }
}

private enum SyntheticLifecycleOrderingError: Error {
    case cacheWasNotPurgedBeforeCredentialDelete
    case credentialStoreFailed
}

private actor LifecycleCredentialStore: CredentialStore {
    private var value: Data?
    private let beforeDelete: (@Sendable () async throws -> Void)?
    private let failReads: Bool
    private let failStores: Bool
    private var deletes = 0
    private var stores = 0

    init(
        value: Data?,
        failReads: Bool = false,
        failStores: Bool = false,
        beforeDelete: (@Sendable () async throws -> Void)? = nil
    ) {
        self.value = value
        self.failReads = failReads
        self.failStores = failStores
        self.beforeDelete = beforeDelete
    }

    func credential(for descriptor: CredentialDescriptor) throws -> Data? {
        guard !failReads else { throw SyntheticLifecycleOrderingError.credentialStoreFailed }
        return value
    }

    func store(_ credential: Data, for descriptor: CredentialDescriptor) throws {
        guard !failStores else { throw SyntheticLifecycleOrderingError.credentialStoreFailed }
        stores += 1
        value = credential
    }

    func deleteCredential(for descriptor: CredentialDescriptor) async throws {
        try await beforeDelete?()
        deletes += 1
        value = nil
    }

    func currentValue() -> Data? { value }
    func deleteCount() -> Int { deletes }
    func storeCount() -> Int { stores }
}

private actor BlockingGateOperation {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?

    func run() async throws -> Int {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        try await Task.sleep(for: .seconds(60))
        return 1
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiter = continuation
        }
    }
}

private final class MutableProviderClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: UTCInstant

    init(milliseconds: Int64) {
        instant = UTCInstant(millisecondsSince1970: milliseconds)
    }

    func now() -> UTCInstant {
        lock.withLock { instant }
    }

    func advance(milliseconds: Int64) {
        lock.withLock {
            instant = UTCInstant(
                millisecondsSince1970: instant.millisecondsSince1970 + milliseconds
            )
        }
    }
}

private actor AdvancingProviderSleeper: ProviderSleeper {
    private let clock: MutableProviderClock
    private var values: [Int64] = []

    init(clock: MutableProviderClock) {
        self.clock = clock
    }

    func sleep(milliseconds: Int64) throws {
        try Task.checkCancellation()
        values.append(milliseconds)
        clock.advance(milliseconds: milliseconds)
    }

    func delays() -> [Int64] { values }
}

private actor ConcurrencyHTTPTransport: HTTPTransport {
    private var active = 0
    private var maximum = 0
    private var firstWaiter: CheckedContinuation<Void, Never>?
    private let response = HTTPTransportResponse(
        data: Data(#"{"data":[{"symbol":"SYN","instrument_name":"Synthetic Concurrency","mic_code":"XNAS","currency":"USD"}]}"#.utf8),
        statusCode: 200,
        headers: [:]
    )

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        active += 1
        maximum = max(maximum, active)
        if active == 1 {
            await withCheckedContinuation { continuation in
                firstWaiter = continuation
            }
        } else if let waiter = firstWaiter {
            firstWaiter = nil
            waiter.resume()
        }
        active -= 1
        return response
    }

    func maximumConcurrent() -> Int { maximum }
}

private actor SessionMarketProvider: MarketDataProvider {
    enum Scenario: Sendable {
        case success
        case offline
        case timeout
        case invalidCredential
        case unsupportedEntitlement
        case unsupportedMarket
        case upgradeRequired
        case rateLimited
        case missing
        case invalidRequest
        case cancelled
        case providerError
    }

    nonisolated let descriptor = ProviderDescriptor(
        identifier: "synthetic.session.market",
        displayName: "Synthetic Session Market",
        kind: .synthetic
    )
    private let clock: any Clock
    private var scenario: Scenario
    private var counts: [MarketProviderEndpoint: Int] = [:]

    init(clock: any Clock, scenario: Scenario = .success) {
        self.clock = clock
        self.scenario = scenario
    }

    func setScenario(_ value: Scenario) { scenario = value }
    func callCount(_ endpoint: MarketProviderEndpoint) -> Int { counts[endpoint, default: 0] }

    func capabilities() -> MarketProviderCapabilities {
        MarketProviderCapabilities(
            provider: descriptor,
            entitlement: .basic,
            observedPlanName: "Synthetic",
            markets: [],
            supportsSearch: true,
            supportsHistoricalPrices: true,
            supportsCorporateActions: true,
            endpointCapabilities: [],
            observedAt: clock.now()
        )
    }

    func search(query: String) throws -> [MarketInstrument] {
        try check(.symbolSearch)
        return [instrument()]
    }

    func latestQuote(for instrument: MarketInstrument) throws -> MarketQuote {
        try check(.latestQuote)
        return MarketQuote(
            instrument: instrument,
            price: try MarketQuotePrice(coefficient: 12_340_000_000, quoteCurrency: .usd),
            observedAt: clock.now(),
            fetchedAt: clock.now(),
            providerIdentifier: descriptor.identifier,
            quality: .unknown,
            freshness: .unknown
        )
    }

    func historicalBars(_ request: MarketHistoryRequest) throws -> MarketHistoryPage {
        try check(.historicalOHLCV)
        let bar = try MarketOHLCVBar(
            sessionDate: request.startDate ?? CivilDate(canonical: "2026-01-15"),
            openedAt: nil,
            open: MarketQuotePrice(coefficient: 10_000_000_000, quoteCurrency: request.instrument.currency),
            high: MarketQuotePrice(coefficient: 13_000_000_000, quoteCurrency: request.instrument.currency),
            low: MarketQuotePrice(coefficient: 9_000_000_000, quoteCurrency: request.instrument.currency),
            close: MarketQuotePrice(coefficient: 12_000_000_000, quoteCurrency: request.instrument.currency),
            volume: AssetQuantity(coefficient: 1_000_000_000),
            adjustment: request.adjustment,
            providerIdentifier: descriptor.identifier,
            fetchedAt: clock.now(),
            freshness: .unknown
        )
        return MarketHistoryPage(
            instrument: request.instrument,
            bars: [bar],
            nextEndDate: nil,
            sourceRevision: "synthetic-session-v1",
            providerIdentifier: descriptor.identifier
        )
    }

    func corporateActions(
        for instrument: MarketInstrument,
        from startDate: CivilDate?,
        through endDate: CivilDate?
    ) throws -> [MarketCorporateAction] {
        try check(.splits)
        counts[.dividends, default: 0] += 1
        let date = try CivilDate(canonical: "2026-01-15")
        return [
            MarketCorporateAction(
                id: "synthetic-split",
                instrument: instrument,
                kind: .split,
                effectiveDate: date,
                amount: nil,
                splitFrom: 1,
                splitTo: 2,
                providerIdentifier: descriptor.identifier,
                fetchedAt: clock.now()
            ),
            MarketCorporateAction(
                id: "synthetic-dividend",
                instrument: instrument,
                kind: .dividend,
                effectiveDate: date,
                amount: try MarketQuotePrice(coefficient: 50_000_000, quoteCurrency: .usd),
                splitFrom: nil,
                splitTo: nil,
                providerIdentifier: descriptor.identifier,
                fetchedAt: clock.now()
            )
        ]
    }

    private func check(_ endpoint: MarketProviderEndpoint) throws {
        counts[endpoint, default: 0] += 1
        switch scenario {
        case .success: return
        case .offline: throw ProviderBoundaryError.offline
        case .timeout: throw ProviderBoundaryError.timeout
        case .invalidCredential: throw ProviderBoundaryError.invalidOrExpired
        case .unsupportedEntitlement: throw ProviderBoundaryError.unsupportedEntitlement
        case .unsupportedMarket: throw ProviderBoundaryError.unsupportedMarket("XNAS")
        case .upgradeRequired: throw ProviderBoundaryError.upgradeRequired("Synthetic Grow")
        case .rateLimited:
            throw ProviderBoundaryError.rateLimited(retryAfterMilliseconds: 1_000)
        case .missing: throw ProviderBoundaryError.missing
        case .invalidRequest: throw ProviderBoundaryError.invalidRequest
        case .cancelled: throw ProviderBoundaryError.cancelled
        case .providerError: throw ProviderBoundaryError.providerError(statusCode: 500)
        }
    }

    private func instrument() -> MarketInstrument {
        MarketInstrument(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000006901")!,
            symbol: "SYN",
            mic: "XNAS",
            currency: .usd,
            displayName: "Synthetic Session Instrument"
        )
    }
}

private actor ControlledSessionMarketProvider: MarketDataProvider {
    nonisolated let descriptor = ProviderDescriptor(
        identifier: "synthetic.session.market",
        displayName: "Controlled Synthetic Session Market",
        kind: .synthetic
    )

    private let clock: any Clock
    private var searchContinuation: CheckedContinuation<[MarketInstrument], Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var searchCalls = 0

    init(clock: any Clock) {
        self.clock = clock
    }

    func capabilities() -> MarketProviderCapabilities {
        MarketProviderCapabilities(
            provider: descriptor,
            entitlement: .basic,
            observedPlanName: "Synthetic",
            markets: [],
            supportsSearch: true,
            supportsHistoricalPrices: true,
            supportsCorporateActions: true,
            endpointCapabilities: [],
            observedAt: clock.now()
        )
    }

    func search(query: String) async throws -> [MarketInstrument] {
        searchCalls += 1
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        return try await withCheckedThrowingContinuation { continuation in
            searchContinuation = continuation
        }
    }

    func latestQuote(for instrument: MarketInstrument) throws -> MarketQuote {
        throw ProviderBoundaryError.missing
    }

    func historicalBars(_ request: MarketHistoryRequest) throws -> MarketHistoryPage {
        throw ProviderBoundaryError.missing
    }

    func corporateActions(
        for instrument: MarketInstrument,
        from startDate: CivilDate?,
        through endDate: CivilDate?
    ) throws -> [MarketCorporateAction] {
        throw ProviderBoundaryError.missing
    }

    func waitUntilSearchStarted() async {
        guard searchCalls == 0 else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func succeedSearch() {
        searchContinuation?.resume(returning: [MarketInstrument(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000006902")!,
            symbol: "SYN",
            mic: "XNAS",
            currency: .usd,
            displayName: String(repeating: "Synthetic Controlled Result ", count: 32)
        )])
        searchContinuation = nil
    }

    func callCount() -> Int { searchCalls }
}

@Suite("Stage 6 market provider networking")
struct MarketDataInfrastructureTests {
    private let clock = FixedClock(
        instant: UTCInstant(millisecondsSince1970: 1_768_435_200_000)
    )

    @Test("Search uses an authenticated header without leaking the key into the URL")
    func requestConstructionAndRedaction() async throws {
        let transport = ScriptedHTTPTransport([
            .response(
                status: 200,
                body: #"{"data":[{"symbol":"SYN","instrument_name":"Synthetic Orchard","exchange":"Synthetic","mic_code":"XNAS","currency":"USD"}]}"#
            )
        ])
        let client = try await makeClient(transport: transport)

        let result = try await client.search(query: "SYN")
        let requests = await transport.requests()

        #expect(result.count == 1)
        #expect(result[0].currency == .usd)
        #expect(requests.count == 1)
        #expect(requests[0].url.contains("symbol=SYN"))
        #expect(!requests[0].url.lowercased().contains("apikey"))
        #expect(requests[0].authorization == "apikey synthetic-stage6-credential")
        #expect(requests[0].timeout == 30)
        #expect(client.descriptor.kind == .production)
    }

    @Test("Search maps the documented row shape and ignores extra Provider fields")
    func searchDocumentedRowShape() async throws {
        let transport = ScriptedHTTPTransport([.response(
            status: 200,
            body: #"{"data":[{"symbol":"AAPL","instrument_name":"Apple Synthetic","exchange":"NASDAQ","mic_code":"XNAS","currency":"USD","country":"United States","extra":{"ignored":true}}],"status":"ok","ignored_root":1}"#
        )])
        let client = try await makeClient(transport: transport)

        let result = try await client.search(query: "AAPL")

        #expect(result.count == 1)
        #expect(result[0].symbol == "AAPL")
        #expect(result[0].mic == "XNAS")
        #expect(result[0].currency == .usd)
        #expect(result[0].displayName == "Apple Synthetic")
    }

    @Test("Unsupported currencies before or after an accepted row do not poison Search")
    func searchIsolatesOutOfScopeCurrencies() async throws {
        let accepted = #"{"symbol":"AAPL","instrument_name":"Apple Synthetic","mic_code":"XNAS","currency":"USD"}"#
        let eur = #"{"symbol":"SYN-EUR","instrument_name":"Synthetic EUR","mic_code":"XPAR","currency":"EUR"}"#
        let gbp = #"{"symbol":"SYN-GBP","instrument_name":"Synthetic GBP","mic_code":"XLON","currency":"GBP"}"#
        let transports = [
            ScriptedHTTPTransport([.response(status: 200, body: "{\"data\":[\(eur),\(accepted),\(gbp)]}")]),
            ScriptedHTTPTransport([.response(status: 200, body: "{\"data\":[\(gbp),\(accepted),\(eur)]}")])
        ]

        for transport in transports {
            let client = try await makeClient(transport: transport)
            let result = try await client.search(query: "AAPL")
            #expect(result.map(\.symbol) == ["AAPL"])
            #expect(result.map(\.currency) == [.usd])
        }
        #expect(MarketCurrencyCode.allCases == [.cny, .usd, .hkd, .jpy])
        #expect(CurrencyCode.allCases == [.cny, .usd])
    }

    @Test("Missing and invalid MIC rows do not poison an accepted Search row")
    func searchIsolatesOutOfScopeMICs() async throws {
        let body = #"{"data":[{"symbol":"NO-MIC","instrument_name":"Synthetic Missing MIC","currency":"USD"},{"symbol":"LONG-MIC","instrument_name":"Synthetic Long MIC","mic_code":"XNAS5","currency":"USD"},{"symbol":"NON-ASCII","instrument_name":"Synthetic Non ASCII MIC","mic_code":"XNÄS","currency":"USD"},{"symbol":"PUNCT","instrument_name":"Synthetic Punctuation MIC","mic_code":"XN@S","currency":"USD"},{"symbol":"AAPL","instrument_name":"Apple Synthetic","mic_code":"XNAS","currency":"USD"}]}"#
        let transport = ScriptedHTTPTransport([.response(status: 200, body: body)])
        let client = try await makeClient(transport: transport)

        let result = try await client.search(query: "AAPL")

        #expect(result.map(\.symbol) == ["AAPL"])
        #expect(result.map(\.mic) == ["XNAS"])
    }

    @Test("Search normalizes identity fields and uses symbol for an empty display name")
    func searchNormalizationAndNameFallback() async throws {
        let transport = ScriptedHTTPTransport([.response(
            status: 200,
            body: #"{"data":[{"symbol":"  aapl \n","instrument_name":"  \n","mic_code":" xnas ","currency":" usd "}]}"#
        )])
        let client = try await makeClient(transport: transport)

        let instrument = try #require(try await client.search(query: "AAPL").first)

        #expect(instrument.symbol == "AAPL")
        #expect(instrument.mic == "XNAS")
        #expect(instrument.currency == .usd)
        #expect(instrument.displayName == "AAPL")
    }

    @Test("Search preserves Provider relevance order and keeps the first duplicate")
    func searchStableOrderAndDeduplication() async throws {
        let body = #"{"data":[{"symbol":"MSFT","instrument_name":"Microsoft Synthetic First","mic_code":"XNAS","currency":"USD"},{"symbol":"AAPL","instrument_name":"Apple Synthetic First","mic_code":"XNAS","currency":"USD"},{"symbol":" aapl ","instrument_name":"Apple Synthetic Duplicate","mic_code":" xnas ","currency":"USD"},{"symbol":"MSFT","instrument_name":"Microsoft Synthetic Duplicate","mic_code":"XNAS","currency":"USD"}]}"#
        let transport = ScriptedHTTPTransport([.response(status: 200, body: body)])
        let client = try await makeClient(transport: transport)

        let result = try await client.search(query: "synthetic")

        #expect(result.map(\.symbol) == ["MSFT", "AAPL"])
        #expect(result.map(\.displayName) == [
            "Microsoft Synthetic First", "Apple Synthetic First"
        ])
    }

    @Test("Empty and entirely out-of-scope Search batches are valid empty success")
    func searchEmptyAndOutOfScopeSuccess() async throws {
        let transport = ScriptedHTTPTransport([
            .response(status: 200, body: #"{"data":[]}"#),
            .response(
                status: 200,
                body: #"{"data":[{"symbol":"SYN-EUR","mic_code":"XPAR","currency":"EUR"},{"symbol":"SYN-NO-MIC","currency":"USD"}]}"#
            )
        ])
        let client = try await makeClient(transport: transport)

        #expect(try await client.search(query: "empty").isEmpty)
        #expect(try await client.search(query: "out-of-scope").isEmpty)

        let capabilities = await client.capabilities()
        #expect(capabilities.endpointCapabilities.first {
            $0.endpoint == .symbolSearch
        }?.liveObservation == .succeeded)
        #expect(capabilities.markets.allSatisfy { $0.liveObservation == .notVerified })
    }

    @Test("A nonempty entirely malformed Search batch remains invalid payload")
    func searchAllMalformedFails() async throws {
        let transport = ScriptedHTTPTransport([.response(
            status: 200,
            body: #"{"data":[{}, {"symbol":"   ","mic_code":"XNAS","currency":"USD"}, 42]}"#
        )])
        let client = try await makeClient(transport: transport)

        await #expect(throws: ProviderBoundaryError.invalidPayload) {
            _ = try await client.search(query: "malformed")
        }
        #expect(await transport.requests().count == 1)
        let capabilities = await client.capabilities()
        #expect(capabilities.endpointCapabilities.first {
            $0.endpoint == .symbolSearch
        }?.liveObservation == .notVerified)
    }

    @Test("A malformed row cannot poison an accepted Search row")
    func searchMalformedRowIsolation() async throws {
        let transport = ScriptedHTTPTransport([.response(
            status: 200,
            body: #"{"data":[{"instrument_name":"Synthetic Missing Symbol","mic_code":"XNAS","currency":"USD"},{"symbol":"AAPL","instrument_name":"Apple Synthetic","mic_code":"XNAS","currency":"USD"}]}"#
        )])
        let client = try await makeClient(transport: transport)

        #expect(try await client.search(query: "AAPL").map(\.symbol) == ["AAPL"])
    }

    @Test("Search envelope requires a data array while allowing an empty array")
    func searchEnvelopeValidation() async throws {
        for body in [#"{}"#, #"{"data":{}}"#, #"{"data":"not-an-array"}"#] {
            let transport = ScriptedHTTPTransport([.response(status: 200, body: body)])
            let client = try await makeClient(transport: transport)
            await #expect(throws: ProviderBoundaryError.invalidPayload) {
                _ = try await client.search(query: "envelope")
            }
            #expect(await transport.requests().count == 1)
        }
    }

    @Test("Provider quote currencies preserve USD, HKD, CNY, and JPY")
    func nativeQuoteCurrencies() async throws {
        let bodies = [
            ("USD", "XNAS"), ("HKD", "XHKG"), ("CNY", "XSHG"), ("JPY", "XJPX")
        ].map { currency, mic in
            SyntheticTransportStep.response(
                status: 200,
                body: #"{"data":[{"symbol":"SYN","instrument_name":"Synthetic Currency","mic_code":"\#(mic)","currency":"\#(currency)"}]}"#
            )
        }
        let transport = ScriptedHTTPTransport(bodies)
        let client = try await makeClient(transport: transport)

        var observed: [MarketCurrencyCode] = []
        for index in 0..<4 {
            observed.append(try await client.search(query: "SYN\(index)")[0].currency)
        }
        #expect(observed == [.usd, .hkd, .cny, .jpy])
        #expect(CurrencyCode.allCases == [.cny, .usd])
    }

    @Test("Historical OHLCV maps losslessly and rejects inconsistent bars")
    func historicalMappingAndValidation() async throws {
        let valid = #"{"meta":{"currency":"USD","exchange_timezone":"America/New_York","mic_code":"XNAS"},"values":[{"datetime":"2026-01-14","open":"10.00000001","high":"12","low":"9","close":"11.50000001","volume":"123.125"}]}"#
        let invalid = #"{"meta":{"currency":"USD","exchange_timezone":"America/New_York","mic_code":"XNAS"},"values":[{"datetime":"2026-01-15","open":"10","high":"8","low":"9","close":"11","volume":"1"}]}"#
        let transport = ScriptedHTTPTransport([
            .response(status: 200, body: valid),
            .response(status: 200, body: invalid)
        ])
        let client = try await makeClient(transport: transport)
        let request = try MarketHistoryRequest(
            instrument: instrument(),
            interval: .oneDay,
            adjustment: .all,
            outputSize: 10
        )

        let page = try await client.historicalBars(request)
        #expect(page.bars[0].open.coefficient == 1_000_000_001)
        #expect(page.bars[0].close.coefficient == 1_150_000_001)
        #expect(page.bars[0].volume?.coefficient == 12_312_500_000)
        #expect(page.bars[0].adjustment == .all)

        await #expect(throws: ProviderBoundaryError.invalidPayload) {
            _ = try await client.historicalBars(request)
        }
    }

    @Test("Adjustment query, pagination marker, splits, and dividends remain domain values")
    func adjustmentPaginationAndActions() async throws {
        let history = #"{"meta":{"currency":"USD","exchange_timezone":"America/New_York","mic_code":"XNAS"},"values":[{"datetime":"2026-01-14","open":"10","high":"12","low":"9","close":"11","volume":"1"}]}"#
        let routes = RoutingHTTPTransport(routes: [
            "/time_series": response(history, headers: ["etag": "synthetic-revision"]),
            "/splits": response(#"{"splits":[{"date":"2025-12-01","from_factor":"2","to_factor":"1"}]}"#),
            "/dividends": response(#"{"dividends":[{"ex_date":"2025-12-15","amount":"0.125"}]}"#)
        ])
        let client = try await makeClient(transport: routes, minuteLimit: 100)
        let request = try MarketHistoryRequest(
            instrument: instrument(), interval: .oneDay, adjustment: .dividends, outputSize: 1
        )

        let page = try await client.historicalBars(request)
        let actions = try await client.corporateActions(
            for: instrument(),
            from: try CivilDate(canonical: "2025-01-01"),
            through: try CivilDate(canonical: "2026-01-15")
        )

        let expectedNextEndDate = try CivilDate(canonical: "2026-01-14")
        #expect(page.nextEndDate == expectedNextEndDate)
        #expect(page.sourceRevision == "synthetic-revision")
        #expect(actions.map(\.kind) == [.split, .dividend])
        #expect(actions[1].amount?.coefficient == 12_500_000)
        #expect(Set(await routes.requestedPaths()) == ["/time_series", "/splits", "/dividends"])
        let capabilities = await client.capabilities()
        #expect(capabilities.endpointCapabilities.first {
            $0.endpoint == .splits
        }?.liveObservation == .succeeded)
        #expect(capabilities.endpointCapabilities.first {
            $0.endpoint == .dividends
        }?.liveObservation == .succeeded)
    }

    @Test("Split and dividend live observations are endpoint-specific")
    func corporateActionObservationsAreIndependent() async throws {
        let routes = RoutingHTTPTransport(routes: [
            "/splits": response(#"{"splits":[{"date":"2025-12-01","from_factor":"2","to_factor":"1"}]}"#),
            "/dividends": response("{}", status: 403)
        ])
        let client = try await makeClient(transport: routes, minuteLimit: 100)
        await #expect(throws: ProviderBoundaryError.unsupportedEntitlement) {
            _ = try await client.corporateActions(for: instrument(), from: nil, through: nil)
        }
        let capabilities = await client.capabilities()
        #expect(capabilities.endpointCapabilities.first {
            $0.endpoint == .splits
        }?.liveObservation == .succeeded)
        #expect(capabilities.endpointCapabilities.first {
            $0.endpoint == .dividends
        }?.liveObservation == .denied)
    }

    @Test("408, 429, and 5xx retry at most three times and respect Retry-After")
    func retryableStatuses() async throws {
        for status in [408, 429, 503] {
            let transport = ScriptedHTTPTransport([
                .response(status: status, body: "{}", headers: ["Retry-After": "2"]),
                .response(status: status, body: "{}", headers: ["Retry-After": "2"]),
                .response(status: status, body: "{}", headers: ["Retry-After": "2"]),
                .response(status: 200, body: #"{"data":[{"symbol":"SYN","instrument_name":"Synthetic Retry","mic_code":"XNAS","currency":"USD"}]}"#)
            ])
            let sleeper = RecordingProviderSleeper()
            let gate = ProviderRequestGate(
                minuteLimit: 100,
                dailyLimit: 1_000,
                clock: clock,
                sleeper: sleeper
            )
            let client = try await makeClient(
                transport: transport,
                sleeper: sleeper,
                gate: gate
            )
            #expect(try await client.search(query: "retry").count == 1)
            #expect(await transport.requests().count == 4)
            #expect(await sleeper.delays() == [2_000, 2_000, 2_000])
            #expect(try await gate.currentCreditUsage() == (perMinute: 4, perDay: 4))
        }
    }

    @Test("Authentication and decoding failures are not retried")
    func nonRetryableFailures() async throws {
        let auth = ScriptedHTTPTransport([.response(status: 401, body: "{}")])
        let authClient = try await makeClient(transport: auth)
        await #expect(throws: ProviderBoundaryError.invalidOrExpired) {
            _ = try await authClient.search(query: "auth")
        }
        #expect(await auth.requests().count == 1)

        let malformed = ScriptedHTTPTransport([.response(status: 200, body: "{not-json")])
        let malformedClient = try await makeClient(transport: malformed)
        await #expect(throws: ProviderBoundaryError.invalidPayload) {
            _ = try await malformedClient.search(query: "decode")
        }
        #expect(await malformed.requests().count == 1)
    }

    @Test("HTTP and structured body 401/403 errors retain distinct credential and entitlement semantics")
    func credentialAndEntitlementErrorsAreDistinct() async throws {
        for body in ["{}", #"{"status":"error","code":401,"message":"synthetic"}"#] {
            let status = body == "{}" ? 401 : 200
            let transport = ScriptedHTTPTransport([.response(status: status, body: body)])
            let client = try await makeClient(transport: transport)
            await #expect(throws: ProviderBoundaryError.invalidOrExpired) {
                _ = try await client.search(query: "credential")
            }
            #expect(await transport.requests().count == 1)
        }

        for body in ["{}", #"{"status":"error","code":403,"message":"synthetic"}"#] {
            let status = body == "{}" ? 403 : 200
            let transport = ScriptedHTTPTransport([.response(status: status, body: body)])
            let client = try await makeClient(transport: transport)
            await #expect(throws: ProviderBoundaryError.unsupportedEntitlement) {
                _ = try await client.search(query: "entitlement")
            }
            #expect(await transport.requests().count == 1)
            let capabilities = await client.capabilities()
            #expect(capabilities.endpointCapabilities.first {
                $0.endpoint == .symbolSearch
            }?.liveObservation == .denied)
            #expect(capabilities.markets.allSatisfy { $0.liveObservation == .notVerified })
        }
    }

    @Test("Transient timeout retry uses deterministic 1, 2, 4 second backoff")
    func timeoutBackoff() async throws {
        let transport = ScriptedHTTPTransport([
            .urlError(URLError.timedOut.rawValue),
            .urlError(URLError.timedOut.rawValue),
            .urlError(URLError.timedOut.rawValue),
            .urlError(URLError.timedOut.rawValue)
        ])
        let sleeper = RecordingProviderSleeper()
        let client = try await makeClient(transport: transport, sleeper: sleeper, minuteLimit: 100)

        await #expect(throws: ProviderBoundaryError.timeout) {
            _ = try await client.search(query: "timeout")
        }
        #expect(await sleeper.delays() == [1_000, 2_000, 4_000])
    }

    @Test("Cancellation reaches an in-flight provider request")
    func cancellation() async throws {
        let transport = CancellationHTTPTransport()
        let client = try await makeClient(transport: transport)
        let task = Task { try await client.search(query: "cancel") }
        await transport.waitUntilStarted()
        task.cancel()
        await #expect(throws: ProviderBoundaryError.cancelled) {
            _ = try await task.value
        }
    }

    @Test("Identical in-flight requests share transport while one waiter cancellation stays isolated")
    func sharedRequestCancellationIsolation() async throws {
        let transport = ControlledHTTPTransport()
        let client = try await makeClient(transport: transport)
        let first = Task { try await client.search(query: "same") }
        let second = Task { try await client.search(query: "same") }
        await transport.waitUntilStarted()
        for _ in 0..<100 {
            if await client.inFlightRequestState().waiters >= 2 { break }
            await Task.yield()
        }
        #expect(await client.inFlightRequestState() == (requests: 1, waiters: 2))
        #expect(await transport.callCount() == 1)

        first.cancel()
        await #expect(throws: ProviderBoundaryError.cancelled) {
            _ = try await first.value
        }
        #expect(await client.inFlightRequestState() == (requests: 1, waiters: 1))

        await transport.releaseAll(with: response(
            #"{"data":[{"symbol":"SYN","instrument_name":"Synthetic Shared","mic_code":"XNAS","currency":"USD"}]}"#
        ))
        #expect(try await second.value.count == 1)
        #expect(await client.inFlightRequestState() == (requests: 0, waiters: 0))
        #expect(await transport.callCount() == 1)
    }

    @Test("All waiter cancellation cancels the shared request without residual state")
    func allWaitersCancelSharedRequest() async throws {
        let transport = CancellationHTTPTransport()
        let client = try await makeClient(transport: transport)
        let first = Task { try await client.search(query: "shared-cancel") }
        let second = Task { try await client.search(query: "shared-cancel") }
        await transport.waitUntilStarted()
        for _ in 0..<100 {
            if await client.inFlightRequestState().waiters >= 2 { break }
            await Task.yield()
        }
        first.cancel()
        second.cancel()
        await #expect(throws: ProviderBoundaryError.cancelled) { _ = try await first.value }
        await #expect(throws: ProviderBoundaryError.cancelled) { _ = try await second.value }
        await transport.waitUntilCancelled()
        #expect(await transport.callCount() == 1)
        #expect(await client.inFlightRequestState() == (requests: 0, waiters: 0))
    }

    @Test("Disconnect cancels the shared request without residual state")
    func disconnectCancelsSharedRequest() async throws {
        let disconnectTransport = CancellationHTTPTransport()
        let disconnectClient = try await makeClient(transport: disconnectTransport)
        let request = Task { try await disconnectClient.search(query: "disconnect") }
        await disconnectTransport.waitUntilStarted()
        try await disconnectClient.disconnect()
        await #expect(throws: ProviderBoundaryError.cancelled) { _ = try await request.value }
        await disconnectTransport.waitUntilCancelled()
        #expect(await disconnectClient.inFlightRequestState() == (requests: 0, waiters: 0))
    }

    @Test("Old same-key completion cannot remove or resume a newer request generation")
    func sameKeyGenerationIsolation() async throws {
        let transport = GenerationalHTTPTransport()
        let client = try await makeClient(transport: transport)
        let first = Task { try await client.search(query: "generation") }
        await transport.waitForCallCount(1)
        first.cancel()
        await #expect(throws: ProviderBoundaryError.cancelled) { _ = try await first.value }

        let second = Task { try await client.search(query: "generation") }
        await transport.waitForCallCount(2)
        await transport.failCancelled(call: 1)
        await transport.succeed(call: 2, response: response(
            #"{"data":[{"symbol":"SYN-B","instrument_name":"Synthetic Generation B","mic_code":"XNAS","currency":"USD"}]}"#
        ))

        #expect(try await second.value.first?.symbol == "SYN-B")
        #expect(await transport.callCount() == 2)
        #expect(await client.inFlightRequestState() == (requests: 0, waiters: 0))
    }

    @Test("Disconnect waits for its old generation before credential restart")
    func disconnectGenerationIsolation() async throws {
        let transport = GenerationalHTTPTransport()
        let client = try await makeClient(transport: transport)
        let first = Task { try await client.search(query: "restart") }
        await transport.waitForCallCount(1)
        let disconnect = Task { try await client.disconnect() }
        await transport.waitForCancellation(call: 1)
        await #expect(throws: ProviderBoundaryError.cancelled) { _ = try await first.value }
        await transport.failCancelled(call: 1)
        try await disconnect.value
        await client.credentialDidChange()

        let second = Task { try await client.search(query: "restart") }
        await transport.waitForCallCount(2)
        await transport.failCancelled(call: 1)
        await transport.succeed(call: 2, response: response(
            #"{"data":[{"symbol":"SYN-R","instrument_name":"Synthetic Restart B","mic_code":"XNAS","currency":"USD"}]}"#
        ))

        #expect(try await second.value.first?.symbol == "SYN-R")
        #expect(await transport.callCount() == 2)
        #expect(await client.inFlightRequestState() == (requests: 0, waiters: 0))
    }

    @Test("Revoke waits for transport terminal before provider cache purge and credential delete")
    func revokeLifecycleOrdering() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try MarketCacheStore(databaseURL: root.appendingPathComponent("cache.sqlite"))
        let now = clock.now()
        let providerEntry = try lifecycleCacheEntry(key: "revoke-order", fetchedAt: now)
        try await cache.store(providerEntry, authorization: .authorized)
        let session = TransientMarketSessionStore()
        let sessionGeneration = await session.generation(for: "twelve-data")
        _ = try await session.store(
            providerIdentifier: "twelve-data",
            logicalKey: "revoke-order",
            payload: .search([instrument()]),
            fetchedAt: now,
            generation: sessionGeneration
        )
        let credential = Data("synthetic-stage6-old-credential".utf8)
        let store = LifecycleCredentialStore(value: credential) {
            let state = try await cache.lookup(
                providerIdentifier: "twelve-data",
                logicalKey: "revoke-order",
                dataType: .latestQuote,
                now: now,
                allowStale: true
            )
            guard state == .missing else {
                throw SyntheticLifecycleOrderingError.cacheWasNotPurgedBeforeCredentialDelete
            }
            guard await session.statistics().entryCount == 0 else {
                throw SyntheticLifecycleOrderingError.cacheWasNotPurgedBeforeCredentialDelete
            }
        }
        let transport = GenerationalHTTPTransport()
        let gate = ProviderRequestGate(clock: clock, sleeper: RecordingProviderSleeper())
        let client = TwelveDataClient(
            credentialStore: store,
            transport: transport,
            gate: gate,
            clock: clock,
            sleeper: RecordingProviderSleeper(),
            jitter: ZeroRetryJitterSource(),
            shutdownTimeoutMilliseconds: 1_000,
            baseURL: URL(string: "https://synthetic-provider.invalid")!
        )
        let coordinator = ProviderCredentialCoordinator(
            credentialStore: store,
            provider: client,
            cache: cache,
            sessionStore: session,
            clock: clock
        )
        let request = Task { try await client.search(query: "revoke-order") }
        await transport.waitForCallCount(1)

        let revoke = Task { try await coordinator.disconnect() }
        await transport.waitForCancellation(call: 1)
        #expect(try await cache.lookup(
            providerIdentifier: "twelve-data",
            logicalKey: "revoke-order",
            dataType: .latestQuote,
            now: now,
            allowStale: true
        ) != .missing)
        #expect(await store.currentValue() == credential)
        #expect(await store.deleteCount() == 0)
        #expect(await session.statistics().entryCount == 1)

        await transport.failCancelled(call: 1)
        _ = try await revoke.value
        await #expect(throws: ProviderBoundaryError.cancelled) { _ = try await request.value }
        #expect(try await cache.lookup(
            providerIdentifier: "twelve-data",
            logicalKey: "revoke-order",
            dataType: .latestQuote,
            now: now,
            allowStale: true
        ) == .missing)
        #expect(await store.currentValue() == nil)
        #expect(await store.deleteCount() == 1)
        #expect(await session.statistics().entryCount == 0)
        #expect(await client.transportTaskCount() == 0)
    }

    @Test("A non-terminal transport blocks purge and credential deletion with a typed error")
    func shutdownTimeoutPreservesCredentialAndCache() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try MarketCacheStore(databaseURL: root.appendingPathComponent("cache.sqlite"))
        let now = clock.now()
        let providerEntry = try lifecycleCacheEntry(key: "shutdown-timeout", fetchedAt: now)
        try await cache.store(providerEntry, authorization: .authorized)
        let session = TransientMarketSessionStore()
        let sessionGeneration = await session.generation(for: "twelve-data")
        _ = try await session.store(
            providerIdentifier: "twelve-data",
            logicalKey: "shutdown-timeout",
            payload: .search([instrument()]),
            fetchedAt: now,
            generation: sessionGeneration
        )
        let credential = Data("synthetic-stage6-timeout-credential".utf8)
        let store = LifecycleCredentialStore(value: credential)
        let transport = GenerationalHTTPTransport()
        let client = TwelveDataClient(
            credentialStore: store,
            transport: transport,
            gate: ProviderRequestGate(clock: clock, sleeper: RecordingProviderSleeper()),
            clock: clock,
            sleeper: RecordingProviderSleeper(),
            jitter: ZeroRetryJitterSource(),
            shutdownTimeoutMilliseconds: 20,
            baseURL: URL(string: "https://synthetic-provider.invalid")!
        )
        let coordinator = ProviderCredentialCoordinator(
            credentialStore: store,
            provider: client,
            cache: cache,
            sessionStore: session,
            clock: clock
        )
        let request = Task { try await client.search(query: "shutdown-timeout") }
        await transport.waitForCallCount(1)

        await #expect(throws: ProviderBoundaryError.transportShutdownTimedOut) {
            _ = try await coordinator.deleteCredential()
        }
        #expect(await store.currentValue() == credential)
        #expect(await store.deleteCount() == 0)
        #expect(await session.statistics().entryCount == 1)
        #expect(try await cache.lookup(
            providerIdentifier: "twelve-data",
            logicalKey: "shutdown-timeout",
            dataType: .latestQuote,
            now: now,
            allowStale: true
        ) != .missing)

        await transport.failCancelled(call: 1)
        await #expect(throws: ProviderBoundaryError.cancelled) { _ = try await request.value }
        for _ in 0..<100 {
            if await client.transportTaskCount() == 0 { break }
            await Task.yield()
        }
        #expect(await client.transportTaskCount() == 0)
    }

    @Test("Credential rotation waits for old transport and resets only the new identity usage")
    func rotationLifecycleOrderingAndQuotaIdentity() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try MarketCacheStore(databaseURL: root.appendingPathComponent("cache.sqlite"))
        let now = clock.now()
        let providerEntry = try lifecycleCacheEntry(key: "rotation-keeps-cache", fetchedAt: now)
        try await cache.store(providerEntry, authorization: .authorized)
        let session = TransientMarketSessionStore()
        let oldSessionGeneration = await session.generation(for: "twelve-data")
        _ = try await session.store(
            providerIdentifier: "twelve-data",
            logicalKey: "rotation-old-session",
            payload: .search([instrument()]),
            fetchedAt: now,
            generation: oldSessionGeneration
        )
        let oldCredential = Data("synthetic-stage6-old-rotation".utf8)
        let newCredentialText = "synthetic-stage6-new-rotation"
        let store = LifecycleCredentialStore(value: oldCredential)
        let transport = GenerationalHTTPTransport()
        let gate = ProviderRequestGate(clock: clock, sleeper: RecordingProviderSleeper())
        let client = TwelveDataClient(
            credentialStore: store,
            transport: transport,
            gate: gate,
            clock: clock,
            sleeper: RecordingProviderSleeper(),
            jitter: ZeroRetryJitterSource(),
            shutdownTimeoutMilliseconds: 1_000,
            baseURL: URL(string: "https://synthetic-provider.invalid")!
        )
        let coordinator = ProviderCredentialCoordinator(
            credentialStore: store,
            provider: client,
            cache: cache,
            sessionStore: session,
            clock: clock
        )
        let oldRequest = Task { try await client.search(query: "rotation") }
        await transport.waitForCallCount(1)

        let rotation = Task { try await coordinator.save(newCredentialText) }
        await transport.waitForCancellation(call: 1)
        #expect(await store.currentValue() == oldCredential)
        await #expect(throws: ProviderBoundaryError.cancelled) {
            _ = try await client.search(query: "rotation-blocked")
        }
        #expect(await transport.callCount() == 1)

        await transport.failCancelled(call: 1)
        try await rotation.value
        await #expect(throws: ProviderBoundaryError.cancelled) { _ = try await oldRequest.value }
        #expect(await store.currentValue() == Data(newCredentialText.utf8))
        #expect(await session.statistics().entryCount == 0)
        #expect(try await session.store(
            providerIdentifier: "twelve-data",
            logicalKey: "late-old-generation",
            payload: .search([instrument()]),
            fetchedAt: now,
            generation: oldSessionGeneration
        ) == .ignoredStaleGeneration)
        #expect(try await cache.lookup(
            providerIdentifier: "twelve-data",
            logicalKey: "rotation-keeps-cache",
            dataType: .latestQuote,
            now: now,
            allowStale: true
        ) != .missing)

        let newRequest = Task { try await client.search(query: "rotation") }
        await transport.waitForCallCount(2)
        await transport.succeed(call: 2, response: response(
            #"{"data":[{"symbol":"SYN-NEW","instrument_name":"Synthetic New Credential","mic_code":"XNAS","currency":"USD"}]}"#
        ))
        #expect(try await newRequest.value.first?.symbol == "SYN-NEW")
        #expect(try await gate.currentCreditUsage() == (perMinute: 1, perDay: 1))
        #expect(await transport.callCount() == 2)
        #expect(await client.transportTaskCount() == 0)
    }

    @Test("Saving the same trimmed credential is an identity-preserving no-op")
    func sameCredentialSavePreservesIdentityState() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try MarketCacheStore(databaseURL: root.appendingPathComponent("cache.sqlite"))
        let now = clock.now()
        let cacheEntry = try lifecycleCacheEntry(key: "same-credential", fetchedAt: now)
        try await cache.store(cacheEntry, authorization: .authorized)
        let session = TransientMarketSessionStore()
        let sessionGeneration = await session.generation(for: "twelve-data")
        _ = try await session.store(
            providerIdentifier: "twelve-data",
            logicalKey: "same-credential",
            payload: .search([instrument()]),
            fetchedAt: now,
            generation: sessionGeneration
        )

        let credentialText = "synthetic-stage6-same-credential"
        let store = LifecycleCredentialStore(value: Data(credentialText.utf8))
        let transport = GenerationalHTTPTransport()
        let gate = ProviderRequestGate(clock: clock, sleeper: RecordingProviderSleeper())
        let client = TwelveDataClient(
            credentialStore: store,
            transport: transport,
            gate: gate,
            clock: clock,
            sleeper: RecordingProviderSleeper(),
            jitter: ZeroRetryJitterSource(),
            shutdownTimeoutMilliseconds: 1_000,
            baseURL: URL(string: "https://synthetic-provider.invalid")!
        )
        let coordinator = ProviderCredentialCoordinator(
            credentialStore: store,
            provider: client,
            cache: cache,
            sessionStore: session,
            clock: clock
        )

        let validation = Task { try await client.validateCredential() }
        await transport.waitForCallCount(1)
        await transport.succeed(call: 1, response: response(
            #"{"plan_name":"Basic","api_credits_per_minute":8,"daily_limit":800}"#
        ))
        _ = try await validation.value

        let quote = Task { try await client.latestQuote(for: instrument()) }
        await transport.waitForCallCount(2)
        await transport.succeed(call: 2, response: response(
            #"{"close":"12.5","timestamp":1768435200,"is_market_open":true}"#
        ))
        _ = try await quote.value

        let active = Task { try await client.search(query: "same-active") }
        await transport.waitForCallCount(3)
        let identityBefore = await client.credentialIdentitySnapshot()
        let usageBefore = try await gate.currentCreditUsage()
        let limitsBefore = await gate.currentLimits()
        let capabilitiesBefore = await client.capabilities()

        try await coordinator.save("  \(credentialText)\n")
        try await coordinator.save(credentialText)

        #expect(await client.credentialIdentitySnapshot() == identityBefore)
        #expect(try await gate.currentCreditUsage() == usageBefore)
        #expect(await gate.currentLimits() == limitsBefore)
        #expect(await client.capabilities() == capabilitiesBefore)
        #expect(await client.inFlightRequestState() == (requests: 1, waiters: 1))
        #expect(await transport.wasCancelled(call: 3) == false)
        #expect(await transport.callCount() == 3)
        #expect(await store.storeCount() == 0)
        #expect(await session.statistics().entryCount == 1)
        #expect(await session.generation(for: "twelve-data") == sessionGeneration)
        #expect(try await cache.lookup(
            providerIdentifier: "twelve-data",
            logicalKey: "same-credential",
            dataType: .latestQuote,
            now: now,
            allowStale: true
        ) != .missing)

        await transport.succeed(call: 3, response: response(
            #"{"data":[{"symbol":"SYN-SAME","instrument_name":"Synthetic Same Credential","mic_code":"XNAS","currency":"USD"}]}"#
        ))
        #expect(try await active.value.first?.symbol == "SYN-SAME")
        #expect(await client.transportTaskCount() == 0)
    }

    @Test("Credential first save and retrieval failure have explicit safe outcomes")
    func credentialFirstSaveAndRetrievalFailure() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try MarketCacheStore(databaseURL: root.appendingPathComponent("cache.sqlite"))

        let emptyStore = LifecycleCredentialStore(value: nil)
        let firstClient = TwelveDataClient(
            credentialStore: emptyStore,
            transport: ScriptedHTTPTransport([]),
            gate: ProviderRequestGate(clock: clock, sleeper: RecordingProviderSleeper()),
            clock: clock,
            sleeper: RecordingProviderSleeper(),
            jitter: ZeroRetryJitterSource(),
            baseURL: URL(string: "https://synthetic-provider.invalid")!
        )
        let firstCoordinator = ProviderCredentialCoordinator(
            credentialStore: emptyStore,
            provider: firstClient,
            cache: cache,
            clock: clock
        )
        try await firstCoordinator.save("synthetic-stage6-first-save")
        #expect(await emptyStore.storeCount() == 1)
        #expect(await emptyStore.currentValue() != nil)
        #expect(await firstClient.credentialIdentitySnapshot().acceptsRequests)

        let failingStore = LifecycleCredentialStore(value: nil, failReads: true)
        let failingClient = TwelveDataClient(
            credentialStore: failingStore,
            transport: ScriptedHTTPTransport([]),
            gate: ProviderRequestGate(clock: clock, sleeper: RecordingProviderSleeper()),
            clock: clock,
            sleeper: RecordingProviderSleeper(),
            jitter: ZeroRetryJitterSource(),
            baseURL: URL(string: "https://synthetic-provider.invalid")!
        )
        let failingCoordinator = ProviderCredentialCoordinator(
            credentialStore: failingStore,
            provider: failingClient,
            cache: cache,
            clock: clock
        )
        let identityBefore = await failingClient.credentialIdentitySnapshot()
        do {
            try await failingCoordinator.save("synthetic-stage6-never-reported")
            Issue.record("Credential retrieval failure must not report success")
        } catch {
            #expect(error is SyntheticLifecycleOrderingError)
            #expect(!String(describing: error).contains("synthetic-stage6-never-reported"))
        }
        #expect(await failingStore.storeCount() == 0)
        #expect(await failingClient.credentialIdentitySnapshot() == identityBefore)
    }

    @Test("A credential-store rotation failure leaves the old identity quiesced and unchanged")
    func rotationStoreFailureRemainsSafe() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try MarketCacheStore(databaseURL: root.appendingPathComponent("cache.sqlite"))
        let oldCredential = Data("synthetic-stage6-old-store-failure".utf8)
        let store = LifecycleCredentialStore(value: oldCredential, failStores: true)
        let transport = GenerationalHTTPTransport()
        let client = TwelveDataClient(
            credentialStore: store,
            transport: transport,
            gate: ProviderRequestGate(clock: clock, sleeper: RecordingProviderSleeper()),
            clock: clock,
            sleeper: RecordingProviderSleeper(),
            jitter: ZeroRetryJitterSource(),
            shutdownTimeoutMilliseconds: 1_000,
            baseURL: URL(string: "https://synthetic-provider.invalid")!
        )
        let coordinator = ProviderCredentialCoordinator(
            credentialStore: store,
            provider: client,
            cache: cache,
            clock: clock
        )

        await #expect(throws: SyntheticLifecycleOrderingError.credentialStoreFailed) {
            try await coordinator.save("synthetic-stage6-new-store-failure")
        }
        #expect(await store.currentValue() == oldCredential)
        await #expect(throws: ProviderBoundaryError.cancelled) {
            _ = try await client.search(query: "must-remain-quiesced")
        }
        #expect(await transport.callCount() == 0)
        #expect(await client.transportTaskCount() == 0)
    }

    @Test("Request gate enforces concurrency two and rejects impossible credit weight")
    func concurrencyAndCredits() async throws {
        let transport = ConcurrencyHTTPTransport()
        let client = try await makeClient(transport: transport, minuteLimit: 100)
        try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<4 {
                group.addTask { try await client.search(query: "query-\(index)").count }
            }
            for try await count in group { #expect(count == 1) }
        }
        #expect(await transport.maximumConcurrent() == 2)

        let gate = ProviderRequestGate(
            maximumConcurrentRequests: 2,
            minuteLimit: 1,
            dailyLimit: 1,
            clock: clock,
            sleeper: RecordingProviderSleeper()
        )
        await #expect(throws: ProviderBoundaryError.requestCostExceedsLimit(
            requiredCredits: 2,
            availableCredits: 1
        )) {
            _ = try await gate.execute(credits: 2) { 1 }
        }
    }

    @Test("Request gate resets at provider minute and UTC day boundaries")
    func officialCreditBoundaries() async throws {
        let minuteClock = MutableProviderClock(milliseconds: 119_900)
        let minuteSleeper = AdvancingProviderSleeper(clock: minuteClock)
        let minuteGate = ProviderRequestGate(
            minuteLimit: 1,
            dailyLimit: 10,
            clock: minuteClock,
            sleeper: minuteSleeper
        )
        _ = try await minuteGate.execute(credits: 1) { 1 }
        _ = try await minuteGate.execute(credits: 1) { 2 }
        #expect(await minuteSleeper.delays() == [100])

        let dayClock = MutableProviderClock(milliseconds: 86_399_900)
        let daySleeper = AdvancingProviderSleeper(clock: dayClock)
        let dayGate = ProviderRequestGate(
            minuteLimit: 100,
            dailyLimit: 1,
            clock: dayClock,
            sleeper: daySleeper
        )
        _ = try await dayGate.execute(credits: 1) { 1 }
        _ = try await dayGate.execute(credits: 1) { 2 }
        #expect(await daySleeper.delays() == [100])
    }

    @Test("Queued cancellation does not consume credits while a started attempt does")
    func cancellationCreditAccounting() async throws {
        let gate = ProviderRequestGate(
            maximumConcurrentRequests: 1,
            minuteLimit: 8,
            dailyLimit: 800,
            clock: clock,
            sleeper: RecordingProviderSleeper()
        )
        let firstOperation = BlockingGateOperation()
        let first = Task { try await gate.execute(credits: 1) { try await firstOperation.run() } }
        await firstOperation.waitUntilStarted()
        let queued = Task { try await gate.execute(credits: 1) { 2 } }
        queued.cancel()
        await #expect(throws: CancellationError.self) { _ = try await queued.value }
        #expect(try await gate.currentCreditUsage() == (perMinute: 1, perDay: 1))

        first.cancel()
        await #expect(throws: CancellationError.self) { _ = try await first.value }
        #expect(try await gate.currentCreditUsage() == (perMinute: 1, perDay: 1))

        let startedOperation = BlockingGateOperation()
        let started = Task {
            try await gate.execute(credits: 1) { try await startedOperation.run() }
        }
        await startedOperation.waitUntilStarted()
        started.cancel()
        await #expect(throws: CancellationError.self) { _ = try await started.value }
        #expect(try await gate.currentCreditUsage() == (perMinute: 2, perDay: 2))
    }

    @Test("Provider usage can lower limits while unknown plan text cannot raise Basic defaults")
    func conservativePlanAndHeaders() async throws {
        let actual = ScriptedHTTPTransport([
            .response(status: 200, body: #"{"plan_name":"Pro","api_credits_per_minute":5,"daily_limit":500}"#)
        ])
        let actualSleeper = RecordingProviderSleeper()
        let actualGate = ProviderRequestGate(clock: clock, sleeper: actualSleeper)
        let actualClient = try await makeClient(transport: actual, gate: actualGate)
        let observation = try await actualClient.validateCredential()
        #expect(observation.entitlement == .proOrHigher)
        #expect(await actualGate.currentLimits().perMinute == 5)
        #expect(await actualGate.currentLimits().perDay == 500)

        let unknown = ScriptedHTTPTransport([
            .response(
                status: 200,
                body: #"{"plan_name":"User Typed Platinum","api_credits_per_minute":999,"daily_limit":999999}"#
            )
        ])
        let unknownGate = ProviderRequestGate(clock: clock, sleeper: RecordingProviderSleeper())
        let unknownClient = try await makeClient(transport: unknown, gate: unknownGate)
        #expect(try await unknownClient.validateCredential().entitlement == .unknown)
        #expect(await unknownGate.currentLimits().perMinute == 8)
        #expect(await unknownGate.currentLimits().perDay == 800)

        let paidWithoutDailyCap = ScriptedHTTPTransport([
            .response(status: 200, body: #"{"plan_name":"Pro","api_credits_per_minute":55}"#)
        ])
        let paidGate = ProviderRequestGate(clock: clock, sleeper: RecordingProviderSleeper())
        let paidClient = try await makeClient(transport: paidWithoutDailyCap, gate: paidGate)
        let paid = try await paidClient.validateCredential()
        #expect(paid.dailyLimit == .uncapped)
        #expect(await paidGate.currentLimits().perMinute == 55)
        #expect(await paidGate.currentLimits().perDay == nil)
    }

    @Test("Credential validation preserves every actual attempt in rolling credit usage")
    func validationCreditUsageIsPreserved() async throws {
        let basicBody = #"{"plan_name":"Basic","api_credits_per_minute":8,"daily_limit":800}"#
        let transport = ScriptedHTTPTransport([
            .response(status: 200, body: basicBody),
            .response(status: 200, body: basicBody)
        ])
        let gate = ProviderRequestGate(clock: clock, sleeper: RecordingProviderSleeper())
        let client = try await makeClient(transport: transport, gate: gate)

        _ = try await client.validateCredential()
        #expect(try await gate.currentCreditUsage() == (perMinute: 1, perDay: 1))
        _ = try await client.validateCredential()
        #expect(try await gate.currentCreditUsage() == (perMinute: 2, perDay: 2))

        let retryTransport = ScriptedHTTPTransport([
            .response(status: 503, body: "{}"),
            .response(status: 200, body: basicBody)
        ])
        let retrySleeper = RecordingProviderSleeper()
        let retryGate = ProviderRequestGate(
            minuteLimit: 8,
            dailyLimit: 800,
            clock: clock,
            sleeper: retrySleeper
        )
        let retryClient = try await makeClient(
            transport: retryTransport,
            sleeper: retrySleeper,
            gate: retryGate
        )
        _ = try await retryClient.validateCredential()
        #expect(try await retryGate.currentCreditUsage() == (perMinute: 2, perDay: 2))
        #expect(await retryTransport.requests().count == 2)
    }

    @Test("Paid uncapped daily quota preserves minute usage and stricter headers win")
    func paidQuotaAndHeaderConservatism() async throws {
        let paidTransport = ScriptedHTTPTransport([
            .response(
                status: 200,
                body: #"{"plan_name":"Pro","api_credits_per_minute":55}"#
            )
        ])
        let paidGate = ProviderRequestGate(clock: clock, sleeper: RecordingProviderSleeper())
        let paidClient = try await makeClient(transport: paidTransport, gate: paidGate)
        let paid = try await paidClient.validateCredential()
        #expect(paid.dailyLimit == .uncapped)
        #expect(await paidGate.currentLimits() == (perMinute: 55, perDay: nil))
        #expect(try await paidGate.currentCreditUsage() == (perMinute: 1, perDay: 1))

        let headerTransport = ScriptedHTTPTransport([
            .response(
                status: 200,
                body: #"{"plan_name":"Pro","api_credits_per_minute":55}"#,
                headers: ["api-credits-used": "1", "api-credits-left": "3"]
            )
        ])
        let headerGate = ProviderRequestGate(clock: clock, sleeper: RecordingProviderSleeper())
        let headerClient = try await makeClient(transport: headerTransport, gate: headerGate)
        _ = try await headerClient.validateCredential()
        #expect(await headerGate.currentLimits().perMinute == 4)
        #expect(try await headerGate.currentCreditUsage() == (perMinute: 1, perDay: 1))
    }

    @Test("Plan, endpoint, and market live observations remain independent")
    func independentCapabilityObservations() async throws {
        let history = #"{"meta":{"currency":"USD","exchange_timezone":"America/New_York","mic_code":"XNAS"},"values":[{"datetime":"2026-01-14","open":"10","high":"12","low":"9","close":"11","volume":"1"}]}"#
        let transport = ScriptedHTTPTransport([
            .response(status: 200, body: #"{"plan_name":"Basic","api_credits_per_minute":8,"daily_limit":800}"#),
            .response(status: 200, body: #"{"data":[{"symbol":"SYN","instrument_name":"Synthetic Search","mic_code":"XNAS","currency":"USD"}]}"#),
            .response(status: 200, body: #"{"close":"12.5","timestamp":1768435200,"is_market_open":true}"#),
            .response(status: 200, body: history)
        ])
        let client = try await makeClient(transport: transport, minuteLimit: 8)
        _ = try await client.validateCredential()
        var capabilities = await client.capabilities()
        #expect(capabilities.entitlement == .basic)
        #expect(capabilities.markets.allSatisfy { $0.liveObservation == .notVerified })
        #expect(capabilities.endpointCapabilities.allSatisfy {
            $0.liveObservation == .notVerified
        })

        _ = try await client.search(query: "SYN")
        capabilities = await client.capabilities()
        #expect(capabilities.endpointCapabilities.first {
            $0.endpoint == .symbolSearch
        }?.liveObservation == .succeeded)
        #expect(capabilities.endpointCapabilities.first {
            $0.endpoint == .historicalOHLCV
        }?.liveObservation == .notVerified)
        #expect(capabilities.markets.first { $0.mic == "US" }?.liveObservation == .notVerified)

        _ = try await client.latestQuote(for: instrument())
        capabilities = await client.capabilities()
        let us = capabilities.markets.first { $0.mic == "US" }
        #expect(us?.liveObservation == .succeeded)
        #expect(us?.liveObservedMICs == ["XNAS"])
        #expect(capabilities.endpointCapabilities.first {
            $0.endpoint == .latestQuote
        }?.liveObservation == .succeeded)
        #expect(capabilities.endpointCapabilities.first {
            $0.endpoint == .historicalOHLCV
        }?.liveObservation == .notVerified)

        let request = try MarketHistoryRequest(
            instrument: instrument(), interval: .oneDay, adjustment: .all, outputSize: 10
        )
        _ = try await client.historicalBars(request)
        capabilities = await client.capabilities()
        #expect(capabilities.endpointCapabilities.first {
            $0.endpoint == .historicalOHLCV
        }?.liveObservation == .succeeded)
        #expect(capabilities.endpointCapabilities.first {
            $0.endpoint == .splits
        }?.liveObservation == .notVerified)

        await client.credentialDidChange()
        capabilities = await client.capabilities()
        #expect(capabilities.markets.allSatisfy { $0.liveObservation == .notVerified })
        #expect(capabilities.endpointCapabilities.allSatisfy {
            $0.liveObservation == .notVerified
        })
    }

    @Test("Endpoint and market observations retain simultaneous success and denial facts")
    func mixedEndpointMarketObservations() async throws {
        let usHistory = #"{"meta":{"currency":"USD","exchange_timezone":"America/New_York","mic_code":"XNAS"},"values":[{"datetime":"2026-01-14","open":"10","high":"12","low":"9","close":"11","volume":"1"}]}"#
        let hongKongHistory = #"{"meta":{"currency":"HKD","exchange_timezone":"Asia/Hong_Kong","mic_code":"XHKG"},"values":[{"datetime":"2026-01-14","open":"10","high":"12","low":"9","close":"11","volume":"1"}]}"#
        let transport = ScriptedHTTPTransport([
            .response(status: 200, body: usHistory),
            .response(status: 403, body: "{}"),
            .response(status: 200, body: hongKongHistory)
        ])
        let client = try await makeClient(transport: transport, minuteLimit: 100)
        let usRequest = try MarketHistoryRequest(
            instrument: instrument(), interval: .oneDay, adjustment: .all, outputSize: 10
        )
        let hongKongInstrument = MarketInstrument(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000006002")!,
            symbol: "SYN-HK",
            mic: "XHKG",
            currency: .hkd,
            displayName: "Synthetic Hong Kong Instrument"
        )
        let hongKongRequest = try MarketHistoryRequest(
            instrument: hongKongInstrument,
            interval: .oneDay,
            adjustment: .all,
            outputSize: 10
        )

        _ = try await client.historicalBars(usRequest)
        await #expect(throws: ProviderBoundaryError.unsupportedEntitlement) {
            _ = try await client.historicalBars(hongKongRequest)
        }
        var capabilities = await client.capabilities()
        #expect(capabilities.markets.first { $0.mic == "US" }?.liveObservation == .succeeded)
        #expect(capabilities.markets.first { $0.mic == "US" }?.liveObservedMICs == ["XNAS"])
        #expect(capabilities.markets.first { $0.mic == "XHKG" }?.liveObservation == .denied)
        #expect(capabilities.markets.first { $0.mic == "XHKG" }?.liveObservedMICs == ["XHKG"])
        #expect(capabilities.endpointCapabilities.first {
            $0.endpoint == .historicalOHLCV
        }?.liveObservation == .mixed)
        #expect(capabilities.endpointCapabilities.first {
            $0.endpoint == .latestQuote
        }?.liveObservation == .notVerified)
        #expect(capabilities.endpointCapabilities.first {
            $0.endpoint == .symbolSearch
        }?.liveObservation == .notVerified)

        _ = try await client.historicalBars(hongKongRequest)
        capabilities = await client.capabilities()
        #expect(capabilities.markets.first { $0.mic == "US" }?.liveObservation == .succeeded)
        #expect(capabilities.markets.first { $0.mic == "XHKG" }?.liveObservation == .succeeded)
        #expect(capabilities.endpointCapabilities.first {
            $0.endpoint == .historicalOHLCV
        }?.liveObservation == .succeeded)

        try await client.disconnect()
        capabilities = await client.capabilities()
        #expect(capabilities.markets.allSatisfy { $0.liveObservation == .notVerified })
        #expect(capabilities.endpointCapabilities.allSatisfy {
            $0.liveObservation == .notVerified
        })
    }

    @Test("Basic capability keeps Corporate Actions catalog-only and aggregates US MIC observations")
    func basicActionsAndUSMICAggregation() async throws {
        let transport = ScriptedHTTPTransport([
            .response(
                status: 200,
                body: #"{"plan_name":"Basic","api_credits_per_minute":8,"daily_limit":800}"#
            ),
            .response(
                status: 200,
                body: #"{"close":"12.5","timestamp":1768435200,"is_market_open":true}"#
            )
        ])
        let client = try await makeClient(transport: transport, minuteLimit: 8)
        _ = try await client.validateCredential()
        let quote = try await client.latestQuote(for: instrument())
        let capabilities = await client.capabilities()
        let us = capabilities.markets.first(where: { $0.mic == "US" })

        #expect(quote.instrument.mic == "XNAS")
        #expect(us?.observedEntitlement == .basic)
        #expect(us?.liveObservation == .succeeded)
        #expect(us?.liveObservedMICs == ["XNAS"])
        #expect(us?.supportsCorporateActions == false)
        #expect(capabilities.supportsCorporateActions == false)
        #expect(capabilities.endpointCapabilities.first(where: { $0.endpoint == .splits })?.creditWeight == 20)
        #expect(capabilities.endpointCapabilities.first(where: { $0.endpoint == .splits })?.liveObservation == .notVerified)
        #expect(capabilities.endpointCapabilities.first(where: { $0.endpoint == .dividends })?.minimumPlanName.contains("Grow") == true)

        let actionTransport = ScriptedHTTPTransport([])
        let basicClient = try await makeClient(transport: actionTransport, minuteLimit: 8)
        await #expect(throws: ProviderBoundaryError.requestCostExceedsLimit(
            requiredCredits: 20,
            availableCredits: 8
        )) {
            _ = try await basicClient.corporateActions(
                for: instrument(),
                from: nil,
                through: nil
            )
        }
        #expect(await actionTransport.requests().isEmpty)
    }

    @Test("A closed market is not inferred to be delayed and capability catalog remains conservative")
    func qualityAndEntitlementConservatism() async throws {
        let transport = ScriptedHTTPTransport([
            .response(status: 200, body: #"{"close":"12.5","timestamp":1768435200,"is_market_open":false}"#)
        ])
        let client = try await makeClient(transport: transport)
        let quote = try await client.latestQuote(for: instrument())
        let capabilities = await client.capabilities()

        #expect(quote.quality == .unknown)
        #expect(quote.freshness == .unknown)
        #expect(capabilities.markets.first(where: { $0.mic == "XHKG" })?.evidenceStatus == "CONFLICTING_EOD_EVIDENCE")
        #expect(!capabilities.supportedMICs.contains("XHKG"))
    }

    @Test("Session status and interval never manufacture provider freshness")
    func freshnessRequiresExplicitEvidence() async throws {
        let history = #"{"meta":{"currency":"USD","exchange_timezone":"America/New_York","mic_code":"XNAS"},"values":[{"datetime":"2026-01-14","open":"10","high":"12","low":"9","close":"11","volume":"1"}]}"#
        let transport = ScriptedHTTPTransport([
            .response(status: 200, body: #"{"close":"12.5","timestamp":1768435200,"is_market_open":true}"#),
            .response(status: 200, body: #"{"close":"12.5","timestamp":1768435200,"is_market_open":false}"#),
            .response(status: 200, body: history),
            .response(status: 200, body: history)
        ])
        let client = try await makeClient(transport: transport)
        #expect(try await client.latestQuote(for: instrument()).freshness == .unknown)
        #expect(try await client.latestQuote(for: instrument()).freshness == .unknown)
        let intraday = try MarketHistoryRequest(
            instrument: instrument(), interval: .oneMinute, adjustment: .all, outputSize: 10
        )
        let daily = try MarketHistoryRequest(
            instrument: instrument(), interval: .oneDay, adjustment: .all, outputSize: 10
        )
        #expect(try await client.historicalBars(intraday).bars.allSatisfy {
            $0.freshness == .unknown
        })
        #expect(try await client.historicalBars(daily).bars.allSatisfy {
            $0.freshness == .unknown
        })
        #expect((await client.capabilities()).markets.allSatisfy {
            $0.freshness == .unknown
        })
    }

    @Test("Untrusted timestamps Retry-After and credit sums cannot overflow")
    func providerIntegerArithmeticIsChecked() async throws {
        let invalidTimestamp = ScriptedHTTPTransport([
            .response(
                status: 200,
                body: #"{"close":"12.5","timestamp":9223372036854775807,"is_market_open":true}"#
            )
        ])
        let timestampClient = try await makeClient(transport: invalidTimestamp)
        await #expect(throws: ProviderBoundaryError.invalidPayload) {
            _ = try await timestampClient.latestQuote(for: instrument())
        }

        let negativeTimestamp = ScriptedHTTPTransport([
            .response(
                status: 200,
                body: #"{"close":"12.5","timestamp":-1,"is_market_open":true}"#
            )
        ])
        let negativeTimestampClient = try await makeClient(transport: negativeTimestamp)
        await #expect(throws: ProviderBoundaryError.invalidPayload) {
            _ = try await negativeTimestampClient.latestQuote(for: instrument())
        }

        let legalSeconds = Int64.max / 1_000
        let legalTimestamp = ScriptedHTTPTransport([
            .response(
                status: 200,
                body: "{\"close\":\"12.5\",\"timestamp\":\(legalSeconds),\"is_market_open\":true}"
            )
        ])
        let legalClient = try await makeClient(transport: legalTimestamp)
        #expect(
            try await legalClient.latestQuote(for: instrument()).observedAt.millisecondsSince1970
                == legalSeconds * 1_000
        )

        for retryAfter in ["9223372036854775807", "-1"] {
            let transport = ScriptedHTTPTransport([
                .response(status: 429, body: "{}", headers: ["Retry-After": retryAfter]),
                .response(
                    status: 200,
                    body: #"{"data":[{"symbol":"SYN","instrument_name":"Synthetic Retry","mic_code":"XNAS","currency":"USD"}]}"#
                )
            ])
            let sleeper = RecordingProviderSleeper()
            let client = try await makeClient(
                transport: transport, sleeper: sleeper, minuteLimit: 100
            )
            #expect(try await client.search(query: "retry-overflow").count == 1)
            #expect(await sleeper.delays() == [1_000])
        }

        let headers = ScriptedHTTPTransport([
            .response(
                status: 200,
                body: #"{"data":[{"symbol":"SYN","instrument_name":"Synthetic Header Overflow","mic_code":"XNAS","currency":"USD"}]}"#,
                headers: ["api-credits-used": String(Int64.max), "api-credits-left": "1"]
            ),
            .response(
                status: 200,
                body: #"{"data":[{"symbol":"SYN","instrument_name":"Synthetic Header Legal","mic_code":"XNAS","currency":"USD"}]}"#,
                headers: ["api-credits-used": "60", "api-credits-left": "40"]
            )
        ])
        let headerGate = ProviderRequestGate(
            minuteLimit: 200,
            dailyLimit: 1_000,
            clock: clock,
            sleeper: RecordingProviderSleeper()
        )
        let headerClient = try await makeClient(transport: headers, gate: headerGate)
        _ = try await headerClient.search(query: "overflow-header")
        #expect(await headerGate.currentLimits().perMinute == 200)
        _ = try await headerClient.search(query: "legal-header")
        #expect(await headerGate.currentLimits().perMinute == 100)
    }

    @Test("Rate windows handle negative time and reject unrepresentable Int64 boundaries")
    func checkedRateWindowArithmetic() async throws {
        let negativeClock = MutableProviderClock(milliseconds: -1)
        let negativeSleeper = AdvancingProviderSleeper(clock: negativeClock)
        let negativeGate = ProviderRequestGate(
            minuteLimit: 1,
            dailyLimit: 10,
            clock: negativeClock,
            sleeper: negativeSleeper
        )
        _ = try await negativeGate.execute(credits: 1) { 1 }
        _ = try await negativeGate.execute(credits: 1) { 2 }
        #expect(await negativeSleeper.delays() == [1])

        let minimumGate = ProviderRequestGate(
            minuteLimit: 1,
            dailyLimit: 1,
            clock: FixedClock(instant: UTCInstant(millisecondsSince1970: .min)),
            sleeper: RecordingProviderSleeper()
        )
        await #expect(throws: ProviderBoundaryError.invalidTimeArithmetic) {
            _ = try await minimumGate.execute(credits: 1) { 1 }
        }
        await #expect(throws: ProviderBoundaryError.invalidTimeArithmetic) {
            _ = try await minimumGate.currentCreditUsage()
        }

        let maximumMinuteGate = ProviderRequestGate(
            minuteLimit: 1,
            dailyLimit: 10,
            clock: FixedClock(instant: UTCInstant(millisecondsSince1970: .max)),
            sleeper: RecordingProviderSleeper()
        )
        _ = try await maximumMinuteGate.execute(credits: 1) { 1 }
        await #expect(throws: ProviderBoundaryError.invalidTimeArithmetic) {
            _ = try await maximumMinuteGate.execute(credits: 1) { 2 }
        }

        let maximumDayGate = ProviderRequestGate(
            minuteLimit: 10,
            dailyLimit: 1,
            clock: FixedClock(instant: UTCInstant(millisecondsSince1970: .max)),
            sleeper: RecordingProviderSleeper()
        )
        _ = try await maximumDayGate.execute(credits: 1) { 1 }
        await #expect(throws: ProviderBoundaryError.invalidTimeArithmetic) {
            _ = try await maximumDayGate.execute(credits: 1) { 2 }
        }
    }

    @Test("Transient Session Store provides TTL, deterministic LRU, capacity, replacement, and clear")
    func transientSessionStoreCoreLifecycle() async throws {
        let provider = "synthetic.session.market"
        let now = clock.now()
        let payload = TransientMarketSessionPayload.search([instrument()])
        let probe = TransientMarketSessionStore(maximumBytes: 8_192)
        let probeGeneration = await probe.generation(for: provider)
        #expect(try await probe.store(
            providerIdentifier: provider,
            logicalKey: "one",
            payload: payload,
            fetchedAt: now,
            generation: probeGeneration
        ) == .stored)
        let oneEntryBytes = await probe.statistics().accountedBytes
        #expect(oneEntryBytes > 0)

        let exact = TransientMarketSessionStore(maximumBytes: oneEntryBytes)
        let exactGeneration = await exact.generation(for: provider)
        #expect(try await exact.store(
            providerIdentifier: provider,
            logicalKey: "one",
            payload: payload,
            fetchedAt: now,
            generation: exactGeneration
        ) == .stored)
        #expect(await exact.statistics().accountedBytes == oneEntryBytes)

        let oversize = TransientMarketSessionStore(maximumBytes: oneEntryBytes - 1)
        let oversizeGeneration = await oversize.generation(for: provider)
        #expect(try await oversize.store(
            providerIdentifier: provider,
            logicalKey: "one",
            payload: payload,
            fetchedAt: now,
            generation: oversizeGeneration
        ) == .notStoredOversize)
        #expect(await oversize.statistics().entryCount == 0)

        _ = try await probe.store(
            providerIdentifier: provider,
            logicalKey: "two",
            payload: payload,
            fetchedAt: now,
            generation: probeGeneration
        )
        _ = try await probe.lookup(
            providerIdentifier: provider,
            logicalKey: "one",
            dataType: .search,
            now: now
        )
        let twoEntriesBytes = await probe.statistics().accountedBytes
        _ = try await probe.updateMaximumBytes(twoEntriesBytes - oneEntryBytes / 2)
        #expect(try await probe.lookup(
            providerIdentifier: provider,
            logicalKey: "one",
            dataType: .search,
            now: now
        ) != .missing)
        #expect(try await probe.lookup(
            providerIdentifier: provider,
            logicalKey: "two",
            dataType: .search,
            now: now
        ) == .missing)

        let beforeReplacement = await probe.statistics()
        _ = try await probe.store(
            providerIdentifier: provider,
            logicalKey: "one",
            payload: payload,
            fetchedAt: now,
            generation: probeGeneration
        )
        #expect(await probe.statistics().accountedBytes == beforeReplacement.accountedBytes)
        let cleared = try await probe.clear(providerIdentifier: provider)
        #expect(cleared.removedEntries == 1)
        #expect(await probe.statistics().entryCount == 0)
        #expect(await probe.clearAll().removedEntries == 0)
    }

    @Test("Transient Session Store reports fresh stale missing and rejects stale generations safely")
    func transientSessionStoreFreshnessAndGeneration() async throws {
        let provider = "synthetic.session.market"
        let store = TransientMarketSessionStore(maximumBytes: 4_096)
        let generation = await store.generation(for: provider)
        let quote = MarketQuote(
            instrument: instrument(),
            price: try MarketQuotePrice(coefficient: 10_000_000_000, quoteCurrency: .usd),
            observedAt: clock.now(),
            fetchedAt: clock.now(),
            providerIdentifier: provider,
            quality: .unknown,
            freshness: .unknown
        )
        _ = try await store.store(
            providerIdentifier: provider,
            logicalKey: "quote",
            payload: .quote(quote),
            fetchedAt: clock.now(),
            generation: generation
        )
        #expect(try await store.lookup(
            providerIdentifier: provider,
            logicalKey: "quote",
            dataType: .quote,
            now: clock.now()
        ) != .missing)
        let expiryMilliseconds = clock.now().millisecondsSince1970 + 15 * 60 * 1_000
        let justBeforeExpiry = UTCInstant(millisecondsSince1970: expiryMilliseconds - 1)
        guard case .fresh = try await store.lookup(
            providerIdentifier: provider,
            logicalKey: "quote",
            dataType: .quote,
            now: justBeforeExpiry
        ) else {
            Issue.record("Expected now < expiresAt to remain fresh")
            return
        }
        let exactExpiry = UTCInstant(millisecondsSince1970: expiryMilliseconds)
        guard case .stale = try await store.lookup(
            providerIdentifier: provider,
            logicalKey: "quote",
            dataType: .quote,
            now: exactExpiry
        ) else {
            Issue.record("Expected now == expiresAt to be stale")
            return
        }
        let staleNow = UTCInstant(millisecondsSince1970: expiryMilliseconds + 1)
        guard case .stale = try await store.lookup(
            providerIdentifier: provider,
            logicalKey: "quote",
            dataType: .quote,
            now: staleNow
        ) else {
            Issue.record("Expected a stale session quote")
            return
        }
        #expect(try await store.lookup(
            providerIdentifier: provider,
            logicalKey: "missing",
            dataType: .quote,
            now: staleNow
        ) == .missing)

        _ = try await store.clear(providerIdentifier: provider)
        #expect(try await store.store(
            providerIdentifier: provider,
            logicalKey: "late-old-generation",
            payload: .quote(quote),
            fetchedAt: staleNow,
            generation: generation
        ) == .ignoredStaleGeneration)
        #expect(await store.statistics().entryCount == 0)

        let currentGeneration = await store.generation(for: provider)
        await #expect(throws: TransientMarketSessionStoreError.accountingOverflow) {
            _ = try await store.store(
                providerIdentifier: provider,
                logicalKey: "overflow",
                payload: .quote(quote),
                fetchedAt: UTCInstant(millisecondsSince1970: .max),
                generation: currentGeneration
            )
        }
    }

    @Test("Market service routes every Twelve Data value through session memory only")
    func sessionOnlyServiceRouting() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let providerClock = MutableProviderClock(milliseconds: clock.now().millisecondsSince1970)
        let provider = SessionMarketProvider(clock: providerClock)
        let cache = try MarketCacheStore(databaseURL: root.appendingPathComponent("cache.sqlite"))
        let diskSentinel = try lifecycleCacheEntry(key: "old-persistent-row", fetchedAt: clock.now())
        try await cache.store(diskSentinel, authorization: .authorized)
        let session = TransientMarketSessionStore()
        let service = MarketDataService(
            marketProvider: provider,
            fxProvider: SyntheticFXRateProvider(clock: providerClock),
            cache: cache,
            sessionStore: session,
            clock: providerClock
        )
        let request = try MarketHistoryRequest(
            instrument: instrument(),
            interval: .oneDay,
            adjustment: .all,
            startDate: try CivilDate(canonical: "2026-01-15")
        )

        _ = try await service.search(query: "SYN")
        _ = try await service.search(query: "SYN")
        _ = try await service.latestQuote(for: instrument())
        _ = try await service.latestQuote(for: instrument())
        _ = try await service.historicalBars(request)
        _ = try await service.historicalBars(request)
        _ = try await service.corporateActions(for: instrument(), from: nil, through: nil)
        _ = try await service.corporateActions(for: instrument(), from: nil, through: nil)

        #expect(await provider.callCount(.symbolSearch) == 1)
        #expect(await provider.callCount(.latestQuote) == 1)
        #expect(await provider.callCount(.historicalOHLCV) == 1)
        #expect(await provider.callCount(.splits) == 1)
        #expect(await provider.callCount(.dividends) == 1)
        #expect(await session.statistics().entryCount == 5)
        #expect(try await cache.cachedRowCount() == 1)
        #expect(try await cache.lookup(
            providerIdentifier: "twelve-data",
            logicalKey: "old-persistent-row",
            dataType: .latestQuote,
            now: clock.now(),
            allowStale: true
        ) != .missing)
    }

    @Test("Session stale fallback is limited to recoverable failures and never hides credential errors")
    func sessionStaleFallbackBoundaries() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let providerClock = MutableProviderClock(milliseconds: clock.now().millisecondsSince1970)
        let provider = SessionMarketProvider(clock: providerClock)
        let session = TransientMarketSessionStore()
        let service = MarketDataService(
            marketProvider: provider,
            fxProvider: SyntheticFXRateProvider(clock: providerClock),
            cache: try MarketCacheStore(databaseURL: root.appendingPathComponent("cache.sqlite")),
            sessionStore: session,
            clock: providerClock
        )
        let original = try await service.latestQuote(for: instrument())
        providerClock.advance(milliseconds: 15 * 60 * 1_000 + 1)
        await provider.setScenario(.offline)
        let stale = try await service.latestQuote(for: instrument())
        #expect(stale.price == original.price)
        #expect(stale.quality == .offline)
        #expect(stale.freshness == .stale)

        await provider.setScenario(.invalidCredential)
        await #expect(throws: ProviderBoundaryError.invalidOrExpired) {
            _ = try await service.latestQuote(for: instrument())
        }
        #expect(await session.statistics().entryCount == 0)

        _ = await session.clearAll()
        await provider.setScenario(.offline)
        await #expect(throws: ProviderBoundaryError.missing) {
            _ = try await service.search(query: "missing-offline")
        }
    }

    @Test("Confirmed entitlement loss clears only the Twelve Data provider session and preserves the typed error")
    func confirmedEntitlementLossClearsSession() async throws {
        let cases: [(SessionMarketProvider.Scenario, ProviderBoundaryError)] = [
            (.invalidCredential, .invalidOrExpired),
            (.unsupportedEntitlement, .unsupportedEntitlement),
            (.unsupportedMarket, .unsupportedMarket("XNAS")),
            (.upgradeRequired, .upgradeRequired("Synthetic Grow"))
        ]
        for (index, item) in cases.enumerated() {
            let root = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let providerClock = MutableProviderClock(milliseconds: clock.now().millisecondsSince1970)
            let provider = SessionMarketProvider(clock: providerClock)
            let session = TransientMarketSessionStore()
            let service = MarketDataService(
                marketProvider: provider,
                fxProvider: SyntheticFXRateProvider(clock: providerClock),
                cache: try MarketCacheStore(databaseURL: root.appendingPathComponent("cache-\(index).sqlite")),
                sessionStore: session,
                clock: providerClock
            )
            _ = try await service.latestQuote(for: instrument())
            #expect(await session.statistics().entryCount == 1)
            providerClock.advance(milliseconds: 15 * 60 * 1_000)
            await provider.setScenario(item.0)
            do {
                _ = try await service.latestQuote(for: instrument())
                Issue.record("Expected confirmed entitlement loss \(item.1)")
            } catch let error as ProviderBoundaryError {
                #expect(error == item.1)
            }
            #expect(await session.statistics().entryCount == 0)
        }
    }

    @Test("Recoverable and ordinary failures do not masquerade as confirmed entitlement loss")
    func nonEntitlementFailuresPreserveSession() async throws {
        let cases: [SessionMarketProvider.Scenario] = [
            .offline, .timeout, .rateLimited, .missing,
            .invalidRequest, .cancelled, .providerError
        ]
        for (index, scenario) in cases.enumerated() {
            let root = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let providerClock = MutableProviderClock(milliseconds: clock.now().millisecondsSince1970)
            let provider = SessionMarketProvider(clock: providerClock)
            let session = TransientMarketSessionStore()
            let service = MarketDataService(
                marketProvider: provider,
                fxProvider: SyntheticFXRateProvider(clock: providerClock),
                cache: try MarketCacheStore(databaseURL: root.appendingPathComponent("cache-\(index).sqlite")),
                sessionStore: session,
                clock: providerClock
            )
            _ = try await service.latestQuote(for: instrument())
            providerClock.advance(milliseconds: 15 * 60 * 1_000)
            await provider.setScenario(scenario)
            do {
                _ = try await service.latestQuote(for: instrument())
            } catch {
                // The assertion here is lifecycle-specific: ordinary errors may
                // still be returned, but they must not erase reusable session data.
            }
            #expect(await session.statistics().entryCount == 1)
        }
    }

    @Test("Session generation rejects a Provider success that completes after explicit Clear")
    func clearLinearizesAgainstLateProviderSuccess() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let providerClock = MutableProviderClock(milliseconds: clock.now().millisecondsSince1970)
        let provider = ControlledSessionMarketProvider(clock: providerClock)
        let session = TransientMarketSessionStore(maximumBytes: 128)
        let service = MarketDataService(
            marketProvider: provider,
            fxProvider: SyntheticFXRateProvider(clock: providerClock),
            cache: try MarketCacheStore(databaseURL: root.appendingPathComponent("cache.sqlite")),
            sessionStore: session,
            clock: providerClock
        )

        let request = Task { try await service.search(query: "SYN") }
        await provider.waitUntilSearchStarted()
        _ = try await service.clearSessionMarketData()
        await provider.succeedSearch()
        do {
            _ = try await request.value
            Issue.record("A late old-generation response must not reach the caller")
        } catch let error as ProviderBoundaryError {
            #expect(error == .cancelled)
        }
        #expect(await provider.callCount() == 1)
        #expect(await session.statistics().entryCount == 0)
    }

    @Test("Fresh and stale lookups are invalidated by the same provider Clear generation")
    func lookupGenerationLinearization() async throws {
        let provider = "synthetic.session.market"
        let store = TransientMarketSessionStore()
        let generation = await store.generation(for: provider)
        _ = try await store.store(
            providerIdentifier: provider,
            logicalKey: "fresh",
            payload: .search([instrument()]),
            fetchedAt: clock.now(),
            generation: generation
        )
        _ = try await store.store(
            providerIdentifier: provider,
            logicalKey: "stale",
            payload: .search([instrument()]),
            fetchedAt: UTCInstant(
                millisecondsSince1970: clock.now().millisecondsSince1970
                    - TransientMarketSessionDataType.search.timeToLiveMilliseconds
            ),
            generation: generation
        )
        guard case .fresh = try await store.lookup(
            providerIdentifier: provider,
            logicalKey: "fresh",
            dataType: .search,
            now: clock.now()
        ) else {
            Issue.record("Expected a fresh lookup before Clear")
            return
        }
        guard case .stale = try await store.lookup(
            providerIdentifier: provider,
            logicalKey: "stale",
            dataType: .search,
            now: clock.now()
        ) else {
            Issue.record("Expected an exact-boundary stale lookup before Clear")
            return
        }
        _ = try await store.clear(providerIdentifier: provider)
        #expect(await store.isCurrent(generation: generation, providerIdentifier: provider) == false)
    }

    @Test("Corporate Actions require a complete pair and use stale fallback only for recoverable failures")
    func corporateActionsMixedSessionStates() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let providerClock = MutableProviderClock(milliseconds: clock.now().millisecondsSince1970)
        let provider = SessionMarketProvider(clock: providerClock)
        let session = TransientMarketSessionStore()
        let service = MarketDataService(
            marketProvider: provider,
            fxProvider: SyntheticFXRateProvider(clock: providerClock),
            cache: try MarketCacheStore(databaseURL: root.appendingPathComponent("cache.sqlite")),
            sessionStore: session,
            clock: providerClock
        )
        let instrument = instrument()
        let key = "actions|\(instrument.symbol)|\(instrument.mic)||"
        let complete = try await service.corporateActions(for: instrument, from: nil, through: nil)
        #expect(complete.count == 2)
        #expect(await provider.callCount(.splits) == 1)
        _ = try await service.corporateActions(for: instrument, from: nil, through: nil)
        #expect(await provider.callCount(.splits) == 1)

        let splits = complete.filter { $0.kind == .split }
        let dividends = complete.filter { $0.kind == .dividend }
        let staleAt = UTCInstant(
            millisecondsSince1970: providerClock.now().millisecondsSince1970
                - TransientMarketSessionDataType.split.timeToLiveMilliseconds
        )

        for (splitFetchedAt, dividendFetchedAt) in [
            (providerClock.now(), staleAt),
            (staleAt, providerClock.now()),
            (staleAt, staleAt)
        ] {
            _ = try await service.clearSessionMarketData()
            let generation = await session.generation(for: provider.descriptor.identifier)
            _ = try await session.store(
                providerIdentifier: provider.descriptor.identifier,
                logicalKey: key,
                payload: .splits(splits),
                fetchedAt: splitFetchedAt,
                generation: generation
            )
            _ = try await session.store(
                providerIdentifier: provider.descriptor.identifier,
                logicalKey: key,
                payload: .dividends(dividends),
                fetchedAt: dividendFetchedAt,
                generation: generation
            )
            await provider.setScenario(.offline)
            let fallback = try await service.corporateActions(for: instrument, from: nil, through: nil)
            #expect(fallback.count == 2)
        }

        _ = try await service.clearSessionMarketData()
        let generation = await session.generation(for: provider.descriptor.identifier)
        _ = try await session.store(
            providerIdentifier: provider.descriptor.identifier,
            logicalKey: key,
            payload: .dividends(dividends),
            fetchedAt: staleAt,
            generation: generation
        )
        await provider.setScenario(.offline)
        await #expect(throws: ProviderBoundaryError.missing) {
            _ = try await service.corporateActions(for: instrument, from: nil, through: nil)
        }
        #expect(await session.statistics().entryCount == 1)

        await provider.setScenario(.success)
        _ = try await service.clearSessionMarketData()
        _ = try await service.corporateActions(for: instrument, from: nil, through: nil)
        providerClock.advance(milliseconds: TransientMarketSessionDataType.split.timeToLiveMilliseconds)
        await provider.setScenario(.unsupportedEntitlement)
        await #expect(throws: ProviderBoundaryError.unsupportedEntitlement) {
            _ = try await service.corporateActions(for: instrument, from: nil, through: nil)
        }
        #expect(await session.statistics().entryCount == 0)

    }

    @Test("App dependency graphs isolate local and Demo sessions and purge only legacy Twelve Data rows")
    func appDependencySessionIsolationAndStartupPurge() async throws {
        let localRoot = try temporaryDirectory()
        let demoRoot = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: localRoot)
            try? FileManager.default.removeItem(at: demoRoot)
        }
        let localPaths = RuntimePaths.temporary(root: localRoot)
        let preflightCache = try MarketCacheStore(databaseURL: localPaths.marketCacheDatabaseURL)
        let twelveEntry = try lifecycleCacheEntry(key: "legacy-twelve-row", fetchedAt: clock.now())
        let fxEntry = try MarketCacheEntry(
            providerIdentifier: "frankfurter-ecb",
            logicalKey: "synthetic-fx-row",
            dataType: .fxRate,
            payload: Data("synthetic-authorized-fx".utf8),
            fetchedAt: clock.now(),
            entitlementContext: "synthetic-test",
            freshness: .unknown
        )
        try await preflightCache.store(twelveEntry, authorization: .authorized)
        try await preflightCache.store(fxEntry, authorization: .authorized)

        let local = try await AppDependencies.make(configuration: LaunchConfiguration(
            dataMode: .local,
            usesTemporaryStores: true,
            temporaryRoot: localRoot
        ))
        let demo = try await AppDependencies.make(configuration: LaunchConfiguration(
            dataMode: .syntheticDemo,
            usesTemporaryStores: true,
            temporaryRoot: demoRoot
        ))
        #expect(try await local.marketCacheStore.lookup(
            providerIdentifier: "twelve-data",
            logicalKey: "legacy-twelve-row",
            dataType: .latestQuote,
            now: clock.now(),
            allowStale: true
        ) == .missing)
        #expect(try await local.marketCacheStore.lookup(
            providerIdentifier: "frankfurter-ecb",
            logicalKey: "synthetic-fx-row",
            dataType: .fxRate,
            now: clock.now(),
            allowStale: true
        ) != .missing)

        let localGeneration = await local.marketSessionStore.generation(for: "synthetic.market")
        _ = try await local.marketSessionStore.store(
            providerIdentifier: "synthetic.market",
            logicalKey: "local-only",
            payload: .search([instrument()]),
            fetchedAt: clock.now(),
            generation: localGeneration
        )
        #expect(await local.marketSessionStore.statistics().entryCount == 1)
        #expect(await demo.marketSessionStore.statistics().entryCount == 0)

        let demoGeneration = await demo.marketSessionStore.generation(for: "synthetic.market")
        _ = try await demo.marketSessionStore.store(
            providerIdentifier: "synthetic.market",
            logicalKey: "demo-only",
            payload: .search([instrument()]),
            fetchedAt: clock.now(),
            generation: demoGeneration
        )
        _ = await local.marketSessionStore.clearAll()
        #expect(await local.marketSessionStore.statistics().entryCount == 0)
        #expect(await demo.marketSessionStore.statistics().entryCount == 1)
    }

    @MainActor
    @Test("Settings clear reports deterministic Session Market Data statistics")
    func settingsSessionClear() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dependencies = try await AppDependencies.make(configuration: LaunchConfiguration(
            dataMode: .local,
            usesTemporaryStores: true,
            temporaryRoot: root
        ))
        let providerIdentifier = dependencies.marketDataProvider.descriptor.identifier
        let generation = await dependencies.marketSessionStore.generation(for: providerIdentifier)
        _ = try await dependencies.marketSessionStore.store(
            providerIdentifier: providerIdentifier,
            logicalKey: "settings-session-entry",
            payload: .search([instrument()]),
            fetchedAt: clock.now(),
            generation: generation
        )
        let model = SettingsFeatureModel(
            provider: dependencies.marketDataProvider,
            marketDataService: dependencies.marketDataService,
            credentialCoordinator: dependencies.credentialCoordinator,
            cache: dependencies.marketCacheStore,
            sessionStore: dependencies.marketSessionStore,
            clock: dependencies.clock
        )

        await model.load()
        #expect(model.sessionStatistics?.entryCount == 1)
        #expect((model.sessionStatistics?.accountedBytes ?? 0) > 0)
        await model.clearSessionMarketData()
        #expect(model.sessionStatistics?.entryCount == 0)
        #expect(model.sessionStatistics?.accountedBytes == 0)
        #expect(model.statusMessage?.contains("Session Market Data") == true)
    }

    private func makeClient(
        transport: any HTTPTransport,
        sleeper: any ProviderSleeper = RecordingProviderSleeper(),
        minuteLimit: Int = 100,
        gate suppliedGate: ProviderRequestGate? = nil
    ) async throws -> TwelveDataClient {
        let credentials = InMemoryCredentialStore()
        try await credentials.store(
            Data("synthetic-stage6-credential".utf8),
            for: TwelveDataClient.credentialDescriptor
        )
        let gate = suppliedGate ?? ProviderRequestGate(
            maximumConcurrentRequests: 2,
            minuteLimit: minuteLimit,
            dailyLimit: 1_000,
            clock: clock,
            sleeper: sleeper
        )
        return TwelveDataClient(
            credentialStore: credentials,
            transport: transport,
            gate: gate,
            clock: clock,
            sleeper: sleeper,
            jitter: ZeroRetryJitterSource(),
            baseURL: URL(string: "https://synthetic-provider.invalid")!
        )
    }

    private func instrument() -> MarketInstrument {
        MarketInstrument(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000006001")!,
            symbol: "SYN",
            mic: "XNAS",
            currency: .usd,
            displayName: "Synthetic Market Instrument"
        )
    }

    private func response(
        _ body: String,
        status: Int = 200,
        headers: [String: String] = [:]
    ) -> HTTPTransportResponse {
        HTTPTransportResponse(data: Data(body.utf8), statusCode: status, headers: headers)
    }

    private func lifecycleCacheEntry(
        key: String,
        fetchedAt: UTCInstant
    ) throws -> MarketCacheEntry {
        try MarketCacheEntry(
            providerIdentifier: "twelve-data",
            logicalKey: key,
            dataType: .latestQuote,
            payload: Data("synthetic-lifecycle-cache".utf8),
            fetchedAt: fetchedAt,
            entitlementContext: "synthetic-test",
            freshness: .unknown
        )
    }
}
