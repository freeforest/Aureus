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

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        calls += 1
        let call = calls
        let ready = callWaiters.filter { $0.0 <= calls }
        callWaiters.removeAll { $0.0 <= calls }
        for (_, waiter) in ready { waiter.resume() }
        return try await withCheckedThrowingContinuation { continuation in
            pending[call] = continuation
        }
    }

    func waitForCallCount(_ target: Int) async {
        guard calls < target else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append((target, continuation))
        }
    }

    func succeed(call: Int, response: HTTPTransportResponse) {
        pending.removeValue(forKey: call)?.resume(returning: response)
    }

    func failCancelled(call: Int) {
        pending.removeValue(forKey: call)?.resume(throwing: URLError(.cancelled))
    }

    func callCount() -> Int { calls }
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
            #expect(await gate.currentCreditUsage() == (perMinute: 4, perDay: 4))
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
        await disconnectClient.disconnect()
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

    @Test("Disconnect generation callback is harmless after immediate credential restart")
    func disconnectGenerationIsolation() async throws {
        let transport = GenerationalHTTPTransport()
        let client = try await makeClient(transport: transport)
        let first = Task { try await client.search(query: "restart") }
        await transport.waitForCallCount(1)
        await client.disconnect()
        await #expect(throws: ProviderBoundaryError.cancelled) { _ = try await first.value }
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
        #expect(await gate.currentCreditUsage() == (perMinute: 1, perDay: 1))

        first.cancel()
        await #expect(throws: CancellationError.self) { _ = try await first.value }
        #expect(await gate.currentCreditUsage() == (perMinute: 1, perDay: 1))

        let startedOperation = BlockingGateOperation()
        let started = Task {
            try await gate.execute(credits: 1) { try await startedOperation.run() }
        }
        await startedOperation.waitUntilStarted()
        started.cancel()
        await #expect(throws: CancellationError.self) { _ = try await started.value }
        #expect(await gate.currentCreditUsage() == (perMinute: 2, perDay: 2))
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
