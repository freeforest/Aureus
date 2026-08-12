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

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        try await Task.sleep(for: .seconds(60))
        return HTTPTransportResponse(data: Data(), statusCode: 200, headers: [:])
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }
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
            let client = try await makeClient(
                transport: transport,
                sleeper: sleeper,
                minuteLimit: 100
            )
            #expect(try await client.search(query: "retry").count == 1)
            #expect(await transport.requests().count == 4)
            #expect(await sleeper.delays() == [2_000, 2_000, 2_000])
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
        await #expect(throws: ProviderBoundaryError.rateLimited(retryAfterMilliseconds: 60_000)) {
            _ = try await gate.execute(credits: 2) { 1 }
        }
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
            .response(status: 200, body: #"{"plan_name":"User Typed Platinum"}"#)
        ])
        let unknownGate = ProviderRequestGate(clock: clock, sleeper: RecordingProviderSleeper())
        let unknownClient = try await makeClient(transport: unknown, gate: unknownGate)
        #expect(try await unknownClient.validateCredential().entitlement == .unknown)
        #expect(await unknownGate.currentLimits().perMinute == 8)
        #expect(await unknownGate.currentLimits().perDay == 800)
    }

    @Test("A closed market is not inferred to be delayed and capability catalog remains conservative")
    func qualityAndEntitlementConservatism() async throws {
        let transport = ScriptedHTTPTransport([
            .response(status: 200, body: #"{"close":"12.5","timestamp":1768435200,"is_market_open":false}"#)
        ])
        let client = try await makeClient(transport: transport)
        let quote = try await client.latestQuote(for: instrument())
        let capabilities = await client.capabilities()

        #expect(quote.quality == .current)
        #expect(quote.freshness == .unknown)
        #expect(capabilities.markets.first(where: { $0.mic == "XHKG" })?.evidenceStatus == "CONFLICTING_EOD_EVIDENCE")
        #expect(!capabilities.supportedMICs.contains("XHKG"))
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
}
