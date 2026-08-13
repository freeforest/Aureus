import CryptoKit
import Foundation

struct HTTPTransportResponse: Sendable {
    let data: Data
    let statusCode: Int
    let headers: [String: String]
}

protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> HTTPTransportResponse
}

struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    init(session: URLSession) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderBoundaryError.providerError(statusCode: nil)
        }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            result[String(describing: pair.key).lowercased()] = String(describing: pair.value)
        }
        return HTTPTransportResponse(data: data, statusCode: http.statusCode, headers: headers)
    }
}

struct OfflineHTTPTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        throw URLError(.notConnectedToInternet)
    }
}

protocol ProviderSleeper: Sendable {
    func sleep(milliseconds: Int64) async throws
}

struct TaskProviderSleeper: ProviderSleeper {
    func sleep(milliseconds: Int64) async throws {
        guard milliseconds > 0 else { return }
        try await Task.sleep(for: .milliseconds(milliseconds))
    }
}

protocol RetryJitterSource: Sendable {
    func milliseconds(upperBound: Int64) -> Int64
}

struct SystemRetryJitterSource: RetryJitterSource {
    func milliseconds(upperBound: Int64) -> Int64 {
        guard upperBound > 0 else { return 0 }
        return Int64.random(in: 0...upperBound)
    }
}

struct ZeroRetryJitterSource: RetryJitterSource {
    func milliseconds(upperBound: Int64) -> Int64 { 0 }
}

private struct ProviderHTTPError: Error, Sendable {
    let response: HTTPTransportResponse
}

actor ProviderRequestGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private let maximumConcurrentRequests: Int
    private let clock: any Clock
    private let sleeper: any ProviderSleeper
    private let initialMinuteLimit: Int
    private let initialDailyLimit: Int?
    private var minuteLimit: Int
    private var dailyLimit: Int?
    private var observedHeaderMinuteLimit: Int?
    private var minuteWindowStart: UTCInstant
    private var dayWindowStart: UTCInstant
    private var windowArithmeticError: ProviderBoundaryError?
    private var minuteCredits = 0
    private var dailyCredits = 0
    private var activeRequests = 0
    private var waiters: [Waiter] = []

    init(
        maximumConcurrentRequests: Int = 2,
        minuteLimit: Int = 8,
        dailyLimit: Int? = 800,
        clock: any Clock,
        sleeper: any ProviderSleeper
    ) {
        self.maximumConcurrentRequests = maximumConcurrentRequests
        initialMinuteLimit = minuteLimit
        initialDailyLimit = dailyLimit
        self.minuteLimit = minuteLimit
        self.dailyLimit = dailyLimit
        observedHeaderMinuteLimit = nil
        self.clock = clock
        self.sleeper = sleeper
        let now = clock.now()
        let minuteStart = try? Self.windowStart(
            containing: now.millisecondsSince1970,
            duration: 60_000
        )
        let dayStart = try? Self.windowStart(
            containing: now.millisecondsSince1970,
            duration: 86_400_000
        )
        minuteWindowStart = UTCInstant(millisecondsSince1970: minuteStart ?? 0)
        dayWindowStart = UTCInstant(millisecondsSince1970: dayStart ?? 0)
        windowArithmeticError = minuteStart == nil || dayStart == nil
            ? .invalidTimeArithmetic
            : nil
    }

    func execute<T: Sendable>(
        credits: Int,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        guard credits > 0 else { throw ProviderBoundaryError.invalidRequest }
        try validateWindowState()
        try validateRequestCost(credits)
        try await acquireConcurrencyPermit()
        defer { releaseConcurrencyPermit() }
        try Task.checkCancellation()
        try await consumeCredits(credits)
        return try await operation()
    }

    func resetForCredentialIdentity() {
        minuteLimit = initialMinuteLimit
        dailyLimit = initialDailyLimit
        observedHeaderMinuteLimit = nil
        minuteCredits = 0
        dailyCredits = 0
        let now = clock.now()
        let minuteStart = try? Self.windowStart(
            containing: now.millisecondsSince1970,
            duration: 60_000
        )
        let dayStart = try? Self.windowStart(
            containing: now.millisecondsSince1970,
            duration: 86_400_000
        )
        minuteWindowStart = UTCInstant(millisecondsSince1970: minuteStart ?? 0)
        dayWindowStart = UTCInstant(millisecondsSince1970: dayStart ?? 0)
        windowArithmeticError = minuteStart == nil || dayStart == nil
            ? .invalidTimeArithmetic
            : nil
    }

    func applyVerifiedLimits(
        perMinute: Int?,
        dailyQuota: ProviderDailyQuota,
        allowIncrease: Bool
    ) {
        let proposedMinuteLimit: Int
        if let perMinute, perMinute > 0 {
            proposedMinuteLimit = allowIncrease
                ? perMinute
                : min(initialMinuteLimit, perMinute)
        } else {
            proposedMinuteLimit = initialMinuteLimit
        }
        minuteLimit = min(proposedMinuteLimit, observedHeaderMinuteLimit ?? .max)
        switch dailyQuota {
        case .capped(let perDay) where perDay > 0:
            dailyLimit = allowIncrease
                ? perDay
                : initialDailyLimit.map { min($0, perDay) } ?? perDay
        case .uncapped where allowIncrease:
            dailyLimit = nil
        case .capped, .uncapped, .unknown:
            dailyLimit = initialDailyLimit
        }
    }

    func applyObservedHeaderLimit(perMinute: Int) {
        guard perMinute > 0 else { return }
        observedHeaderMinuteLimit = observedHeaderMinuteLimit.map { min($0, perMinute) }
            ?? perMinute
        minuteLimit = min(minuteLimit, perMinute)
    }

    func currentLimits() -> (perMinute: Int, perDay: Int?) {
        (minuteLimit, dailyLimit)
    }

    func currentCreditUsage() throws -> (perMinute: Int, perDay: Int) {
        try rollWindows(now: clock.now())
        return (minuteCredits, dailyCredits)
    }

    private func acquireConcurrencyPermit() async throws {
        try Task.checkCancellation()
        if activeRequests < maximumConcurrentRequests {
            activeRequests += 1
            return
        }

        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func releaseConcurrencyPermit() {
        if waiters.isEmpty {
            activeRequests -= 1
        } else {
            let waiter = waiters.removeFirst()
            waiter.continuation.resume()
        }
    }

    private func validateRequestCost(_ credits: Int) throws {
        guard credits <= minuteLimit else {
            throw ProviderBoundaryError.requestCostExceedsLimit(
                requiredCredits: credits,
                availableCredits: minuteLimit
            )
        }
        if let dailyLimit, credits > dailyLimit {
            throw ProviderBoundaryError.requestCostExceedsLimit(
                requiredCredits: credits,
                availableCredits: dailyLimit
            )
        }
    }

    private func consumeCredits(_ credits: Int) async throws {
        while true {
            try Task.checkCancellation()
            let now = clock.now()
            try rollWindows(now: now)
            try validateRequestCost(credits)

            let minuteTotal = minuteCredits.addingReportingOverflow(credits)
            guard !minuteTotal.overflow else { throw ProviderBoundaryError.invalidPayload }
            if minuteTotal.partialValue > minuteLimit {
                try await sleeper.sleep(milliseconds: try Self.delayUntilNextWindow(
                    start: minuteWindowStart.millisecondsSince1970,
                    duration: 60_000,
                    now: now.millisecondsSince1970
                ))
                continue
            }
            let dailyTotal = dailyCredits.addingReportingOverflow(credits)
            guard !dailyTotal.overflow else { throw ProviderBoundaryError.invalidPayload }
            if let dailyLimit, dailyTotal.partialValue > dailyLimit {
                try await sleeper.sleep(milliseconds: try Self.delayUntilNextWindow(
                    start: dayWindowStart.millisecondsSince1970,
                    duration: 86_400_000,
                    now: now.millisecondsSince1970
                ))
                continue
            }

            minuteCredits = minuteTotal.partialValue
            dailyCredits = dailyTotal.partialValue
            return
        }
    }

    private func rollWindows(now: UTCInstant) throws {
        try validateWindowState()
        let minuteStart = try Self.windowStart(
            containing: now.millisecondsSince1970,
            duration: 60_000
        )
        if minuteStart != minuteWindowStart.millisecondsSince1970 {
            minuteWindowStart = UTCInstant(millisecondsSince1970: minuteStart)
            minuteCredits = 0
        }
        let dayStart = try Self.windowStart(
            containing: now.millisecondsSince1970,
            duration: 86_400_000
        )
        if dayStart != dayWindowStart.millisecondsSince1970 {
            dayWindowStart = UTCInstant(millisecondsSince1970: dayStart)
            dailyCredits = 0
        }
    }

    private func validateWindowState() throws {
        if let windowArithmeticError { throw windowArithmeticError }
    }

    private static func windowStart(containing instant: Int64, duration: Int64) throws -> Int64 {
        guard duration > 0 else { throw ProviderBoundaryError.invalidTimeArithmetic }
        let quotient = instant / duration
        let remainder = instant % duration
        let floorQuotient: Int64
        if remainder < 0 {
            let adjusted = quotient.subtractingReportingOverflow(1)
            guard !adjusted.overflow else { throw ProviderBoundaryError.invalidTimeArithmetic }
            floorQuotient = adjusted.partialValue
        } else {
            floorQuotient = quotient
        }
        let start = floorQuotient.multipliedReportingOverflow(by: duration)
        guard !start.overflow else { throw ProviderBoundaryError.invalidTimeArithmetic }
        return start.partialValue
    }

    private static func delayUntilNextWindow(
        start: Int64,
        duration: Int64,
        now: Int64
    ) throws -> Int64 {
        let boundary = start.addingReportingOverflow(duration)
        guard !boundary.overflow else { throw ProviderBoundaryError.invalidTimeArithmetic }
        let delay = boundary.partialValue.subtractingReportingOverflow(now)
        guard !delay.overflow, delay.partialValue > 0 else {
            throw ProviderBoundaryError.invalidTimeArithmetic
        }
        return delay.partialValue
    }
}

private enum HTTPRetryExecutor {
    static func run(
        request: URLRequest,
        credits: Int,
        transport: any HTTPTransport,
        gate: ProviderRequestGate,
        sleeper: any ProviderSleeper,
        jitter: any RetryJitterSource
    ) async throws -> HTTPTransportResponse {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                let response = try await gate.execute(credits: credits) {
                    try await transport.data(for: request)
                }
                guard (200...299).contains(response.statusCode) else {
                    throw ProviderHTTPError(response: response)
                }
                return response
            } catch is CancellationError {
                throw ProviderBoundaryError.cancelled
            } catch let error as ProviderHTTPError {
                guard attempt < 3, isRetryableStatus(error.response.statusCode) else {
                    throw error
                }
                let delay = retryDelay(
                    attempt: attempt,
                    headers: error.response.headers,
                    jitter: jitter
                )
                attempt += 1
                try await sleeper.sleep(milliseconds: delay)
            } catch let error as URLError {
                guard attempt < 3, isRetryableNetwork(error.code) else {
                    if error.code == .cancelled { throw ProviderBoundaryError.cancelled }
                    if error.code == .timedOut { throw ProviderBoundaryError.timeout }
                    throw ProviderBoundaryError.offline
                }
                let delay = retryDelay(attempt: attempt, headers: [:], jitter: jitter)
                attempt += 1
                try await sleeper.sleep(milliseconds: delay)
            }
        }
    }

    private static func isRetryableStatus(_ status: Int) -> Bool {
        status == 408 || status == 429 || (500...599).contains(status)
    }

    private static func isRetryableNetwork(_ code: URLError.Code) -> Bool {
        switch code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost,
             .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable:
            true
        default:
            false
        }
    }

    private static func retryDelay(
        attempt: Int,
        headers: [String: String],
        jitter: any RetryJitterSource
    ) -> Int64 {
        if let retryAfter = retryAfterMilliseconds(headers["retry-after"]) {
            return retryAfter
        }
        let base: Int64 = [1_000, 2_000, 4_000][min(attempt, 2)]
        let jitterValue = jitter.milliseconds(upperBound: 250)
        guard jitterValue >= 0 else { return base }
        let total = base.addingReportingOverflow(jitterValue)
        return total.overflow ? base : total.partialValue
    }

    static func retryAfterMilliseconds(_ value: String?) -> Int64? {
        guard let value, let seconds = Int64(value), seconds >= 0 else { return nil }
        let result = seconds.multipliedReportingOverflow(by: 1_000)
        return result.overflow ? nil : result.partialValue
    }
}

private final class TransportTerminationRace: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var resolved = false

    func wait(
        for tasks: [Task<HTTPTransportResponse, Error>],
        timeoutMilliseconds: Int64
    ) async -> Bool {
        guard !tasks.isEmpty else { return true }
        guard timeoutMilliseconds > 0 else { return false }
        return await withCheckedContinuation { continuation in
            lock.withLock { self.continuation = continuation }
            Task {
                for task in tasks { _ = await task.result }
                self.resolve(true)
            }
            Task {
                try? await Task.sleep(for: .milliseconds(timeoutMilliseconds))
                self.resolve(false)
            }
        }
    }

    private func resolve(_ value: Bool) {
        let continuation = lock.withLock { () -> CheckedContinuation<Bool, Never>? in
            guard !resolved else { return nil }
            resolved = true
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: value)
    }
}

actor TwelveDataClient: MarketDataProvider {
    private struct InFlightRequest {
        let requestID: UUID
        let task: Task<HTTPTransportResponse, Error>
        var waiters: [UUID: CheckedContinuation<HTTPTransportResponse, Error>]
    }

    private struct LiveObservationKey: Hashable {
        let endpoint: MarketProviderEndpoint
        let rawMIC: String?
    }

    private struct LiveObservationRecord {
        let capabilityKey: String?
        let rawMIC: String?
        let state: ProviderLiveObservation
    }

    private enum RequestAdmissionState: Equatable {
        case accepting
        case quiescing
        case disconnected
    }

    nonisolated let descriptor = ProviderDescriptor(
        identifier: "twelve-data",
        displayName: "Twelve Data",
        kind: .production
    )

    nonisolated static let credentialDescriptor = CredentialDescriptor(
        providerIdentifier: "twelve-data",
        accountIdentifier: "user-owned-api-key"
    )

    private let credentialStore: any CredentialStore
    private let transport: any HTTPTransport
    private let gate: ProviderRequestGate
    private let clock: any Clock
    private let sleeper: any ProviderSleeper
    private let jitter: any RetryJitterSource
    private let baseURL: URL
    private let shutdownTimeoutMilliseconds: Int64
    private var inFlight: [String: InFlightRequest] = [:]
    private var transportTasks: [UUID: Task<HTTPTransportResponse, Error>] = [:]
    private var requestAdmissionState: RequestAdmissionState = .accepting
    private var credentialGeneration = UUID()
    private var lastUsage: ProviderUsageObservation?
    private var liveObservations: [LiveObservationKey: LiveObservationRecord] = [:]

    init(
        credentialStore: any CredentialStore,
        transport: any HTTPTransport,
        gate: ProviderRequestGate,
        clock: any Clock,
        sleeper: any ProviderSleeper = TaskProviderSleeper(),
        jitter: any RetryJitterSource = SystemRetryJitterSource(),
        shutdownTimeoutMilliseconds: Int64 = 5_000,
        baseURL: URL = URL(string: "https://api.twelvedata.com")!
    ) {
        self.credentialStore = credentialStore
        self.transport = transport
        self.gate = gate
        self.clock = clock
        self.sleeper = sleeper
        self.jitter = jitter
        self.shutdownTimeoutMilliseconds = shutdownTimeoutMilliseconds
        self.baseURL = baseURL
    }

    func capabilities() -> MarketProviderCapabilities {
        let entitlement = lastUsage?.entitlement ?? .unknown
        let observedAt = lastUsage?.observedAt

        func marketCapability(
            mic: String,
            minimum: MarketEntitlementState,
            catalog: ProviderCapabilityEvidence,
            supportsHistoricalBars: Bool,
            evidenceStatus: String
        ) -> MarketCapability {
            let matching = liveObservations.values.filter { $0.capabilityKey == mic }
            let liveObservation = Self.aggregateObservation(matching.map(\.state))
            let observedEntitlement: MarketEntitlementState
            switch liveObservation {
            case .denied:
                observedEntitlement = .upgradeRequired
            case .succeeded:
                observedEntitlement = entitlement
            case .mixed, .notVerified:
                observedEntitlement = .unknown
            }
            return MarketCapability(
                mic: mic,
                minimumEntitlement: minimum,
                observedEntitlement: observedEntitlement,
                freshness: .unknown,
                catalogEvidence: catalog,
                liveObservation: liveObservation,
                liveObservedMICs: Array(Set(matching.compactMap(\.rawMIC))).sorted(),
                supportsSearch: true,
                supportsHistoricalBars: supportsHistoricalBars,
                supportsCorporateActions: false,
                evidenceStatus: evidenceStatus
            )
        }

        func endpointCapability(
            endpoint: MarketProviderEndpoint,
            minimumPlanName: String,
            creditWeight: Int
        ) -> ProviderEndpointCapability {
            let live = aggregateObservation(for: endpoint)
            let observed: MarketEntitlementState
            switch live {
            case .succeeded:
                observed = entitlement
            case .denied:
                observed = .upgradeRequired
            case .mixed, .notVerified:
                observed = .unknown
            }
            return ProviderEndpointCapability(
                endpoint: endpoint,
                minimumPlanName: minimumPlanName,
                creditWeight: creditWeight,
                catalogEvidence: .officialCatalogOnly,
                liveObservation: live,
                observedEntitlement: observed
            )
        }

        let markets = [
            marketCapability(
                mic: "US", minimum: .basic, catalog: .officialCatalogOnly,
                supportsHistoricalBars: true,
                evidenceStatus: "OFFICIAL_CATALOG_ONLY; CORPORATE_ACTIONS_REQUIRE_GROW_OR_HIGHER"
            ),
            marketCapability(
                mic: "XHKG", minimum: .proOrHigher, catalog: .conflicting,
                supportsHistoricalBars: false, evidenceStatus: "CONFLICTING_EOD_EVIDENCE"
            ),
            marketCapability(
                mic: "XSHG", minimum: .proOrHigher, catalog: .officialCatalogOnly,
                supportsHistoricalBars: true, evidenceStatus: "OFFICIAL_CATALOG_NOT_LIVE_VERIFIED"
            ),
            marketCapability(
                mic: "XSHE", minimum: .proOrHigher, catalog: .officialCatalogOnly,
                supportsHistoricalBars: true, evidenceStatus: "OFFICIAL_CATALOG_NOT_LIVE_VERIFIED"
            ),
            marketCapability(
                mic: "XJPX", minimum: .proOrHigher, catalog: .conflicting,
                supportsHistoricalBars: false, evidenceStatus: "CONFLICTING_EOD_EVIDENCE"
            )
        ]
        return MarketProviderCapabilities(
            provider: descriptor,
            entitlement: requestAdmissionState == .disconnected ? .missing : entitlement,
            observedPlanName: lastUsage?.planName,
            markets: markets,
            supportsSearch: true,
            supportsHistoricalPrices: true,
            supportsCorporateActions: aggregateObservation(for: .splits) == .succeeded &&
                aggregateObservation(for: .dividends) == .succeeded,
            endpointCapabilities: [
                endpointCapability(
                    endpoint: .symbolSearch, minimumPlanName: "Basic", creditWeight: 1
                ),
                endpointCapability(
                    endpoint: .latestQuote, minimumPlanName: "Basic for eligible US data",
                    creditWeight: 1
                ),
                endpointCapability(
                    endpoint: .historicalOHLCV,
                    minimumPlanName: "Basic for eligible US data", creditWeight: 1
                ),
                endpointCapability(
                    endpoint: .splits,
                    minimumPlanName: "Grow (Individual) or Venture (Business)",
                    creditWeight: 20
                ),
                endpointCapability(
                    endpoint: .dividends,
                    minimumPlanName: "Grow (Individual) or Venture (Business)",
                    creditWeight: 20
                )
            ],
            observedAt: observedAt
        )
    }

    func validateCredential() async throws -> ProviderUsageObservation {
        let response = try await authenticatedRequest(
            path: "/api_usage",
            queryItems: [],
            creditWeight: 1
        )
        try throwProviderErrorIfPresent(response.data, statusCode: response.statusCode)
        let dto = try decodeProviderPayload(TwelveUsageDTO.self, from: response.data)
        let plan = dto.planName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let entitlement = Self.entitlement(forPlanName: plan)
        if let perMinute = dto.perMinuteLimit, perMinute <= 0 {
            throw ProviderBoundaryError.invalidPayload
        }
        if let perDay = dto.dailyLimit, perDay <= 0 {
            throw ProviderBoundaryError.invalidPayload
        }
        let minute: Int?
        let dailyQuota: ProviderDailyQuota
        let allowIncrease: Bool
        switch entitlement {
        case .basic:
            minute = dto.perMinuteLimit ?? 8
            dailyQuota = .capped(dto.dailyLimit ?? 800)
            allowIncrease = false
        case .proOrHigher:
            minute = dto.perMinuteLimit
            dailyQuota = dto.dailyLimit.map(ProviderDailyQuota.capped) ?? .uncapped
            allowIncrease = true
        default:
            minute = dto.perMinuteLimit
            dailyQuota = .unknown
            allowIncrease = false
        }
        await gate.applyVerifiedLimits(
            perMinute: minute,
            dailyQuota: dailyQuota,
            allowIncrease: allowIncrease
        )
        let observation = ProviderUsageObservation(
            planName: plan,
            entitlement: entitlement,
            perMinuteLimit: minute,
            dailyLimit: dailyQuota,
            observedAt: clock.now()
        )
        lastUsage = observation
        return observation
    }

    func prepareForCredentialChange() async throws {
        try await stopAndAwaitTransportTermination()
        lastUsage = nil
        liveObservations = [:]
    }

    func credentialDidChange() async {
        await gate.resetForCredentialIdentity()
        credentialGeneration = UUID()
        requestAdmissionState = .accepting
        lastUsage = nil
        liveObservations = [:]
    }

    func disconnect() async throws {
        try await stopAndAwaitTransportTermination()
        await gate.resetForCredentialIdentity()
        credentialGeneration = UUID()
        requestAdmissionState = .disconnected
        lastUsage = nil
        liveObservations = [:]
    }

    func inFlightRequestState() -> (requests: Int, waiters: Int) {
        (
            inFlight.count,
            inFlight.values.reduce(0) { $0 + $1.waiters.count }
        )
    }

    func transportTaskCount() -> Int { transportTasks.count }

    func credentialIdentitySnapshot() -> (generation: UUID, acceptsRequests: Bool) {
        (credentialGeneration, requestAdmissionState == .accepting)
    }

    func search(query: String) async throws -> [MarketInstrument] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 128 else {
            throw ProviderBoundaryError.invalidRequest
        }
        let response = try await authenticatedRequest(
            path: "/symbol_search",
            queryItems: [
                URLQueryItem(name: "symbol", value: normalized),
                URLQueryItem(name: "outputsize", value: "30")
            ],
            creditWeight: 1,
            endpoint: .symbolSearch
        )
        try throwProviderErrorIfPresent(
            response.data,
            statusCode: response.statusCode,
            endpoint: .symbolSearch
        )
        let dto = try decodeProviderPayload(TwelveSearchResponseDTO.self, from: response.data)
        let instruments = try validatedProviderMapping {
            try dto.data.map { item in
                guard let mic = item.micCode?.uppercased(), mic.count == 4 else {
                    throw ProviderBoundaryError.invalidPayload
                }
                let currency = try MarketCurrencyCode(validating: item.currency)
                return MarketInstrument(
                    id: StableMarketIdentifier.uuid(
                        "twelve-data|\(item.symbol.uppercased())|\(mic)"
                    ),
                    symbol: item.symbol.uppercased(),
                    mic: mic,
                    currency: currency,
                    displayName: item.instrumentName
                )
            }
        }
        recordObservation(endpoint: .symbolSearch, marketMIC: nil, state: .succeeded)
        return instruments
    }

    func latestQuote(for instrument: MarketInstrument) async throws -> MarketQuote {
        let response = try await authenticatedRequest(
            path: "/quote",
            queryItems: instrumentQueryItems(instrument),
            creditWeight: 1,
            endpoint: .latestQuote,
            marketMIC: instrument.mic
        )
        try throwProviderErrorIfPresent(
            response.data,
            statusCode: response.statusCode,
            endpoint: .latestQuote,
            marketMIC: instrument.mic
        )
        let dto = try decodeProviderPayload(TwelveQuoteDTO.self, from: response.data)
        let price = try validatedProviderMapping {
            try MarketQuotePrice(decimal: dto.close.decimal, quoteCurrency: instrument.currency)
        }
        let observedAt: UTCInstant
        if let timestamp = dto.timestamp {
            guard timestamp >= 0 else { throw ProviderBoundaryError.invalidPayload }
            let milliseconds = timestamp.multipliedReportingOverflow(by: 1_000)
            guard !milliseconds.overflow else { throw ProviderBoundaryError.invalidPayload }
            observedAt = UTCInstant(millisecondsSince1970: milliseconds.partialValue)
        } else {
            observedAt = clock.now()
        }
        recordObservation(endpoint: .latestQuote, marketMIC: instrument.mic, state: .succeeded)
        return MarketQuote(
            instrument: instrument,
            price: price,
            observedAt: observedAt,
            fetchedAt: clock.now(),
            providerIdentifier: descriptor.identifier,
            // Trading-session status alone does not prove quote freshness.
            quality: .unknown,
            freshness: .unknown
        )
    }

    func historicalBars(_ request: MarketHistoryRequest) async throws -> MarketHistoryPage {
        var query = instrumentQueryItems(request.instrument)
        query.append(URLQueryItem(name: "interval", value: request.interval.rawValue))
        query.append(URLQueryItem(name: "adjust", value: request.adjustment.rawValue))
        query.append(URLQueryItem(name: "outputsize", value: String(request.outputSize)))
        if let startDate = request.startDate {
            query.append(URLQueryItem(name: "start_date", value: startDate.description))
        }
        if let endDate = request.endDate {
            query.append(URLQueryItem(name: "end_date", value: endDate.description))
        }
        let response = try await authenticatedRequest(
            path: "/time_series",
            queryItems: query,
            creditWeight: 1,
            endpoint: .historicalOHLCV,
            marketMIC: request.instrument.mic
        )
        try throwProviderErrorIfPresent(
            response.data,
            statusCode: response.statusCode,
            endpoint: .historicalOHLCV,
            marketMIC: request.instrument.mic
        )
        let dto = try decodeProviderPayload(TwelveTimeSeriesDTO.self, from: response.data)
        guard dto.meta.micCode.uppercased() == request.instrument.mic,
              let responseCurrency = try? MarketCurrencyCode(validating: dto.meta.currency),
              responseCurrency == request.instrument.currency else {
            throw ProviderBoundaryError.invalidPayload
        }
        let fetchedAt = clock.now()
        let freshness: MarketFreshness = .unknown
        let bars = try validatedProviderMapping {
            try dto.values.map { value in
                let sessionDate = try CivilDate(canonical: String(value.datetime.prefix(10)))
                return try MarketOHLCVBar(
                    sessionDate: sessionDate,
                    openedAt: Self.parseMarketDateTime(
                        value.datetime,
                        timeZoneIdentifier: dto.meta.exchangeTimezone
                    ),
                    open: MarketQuotePrice(decimal: value.open.decimal, quoteCurrency: request.instrument.currency),
                    high: MarketQuotePrice(decimal: value.high.decimal, quoteCurrency: request.instrument.currency),
                    low: MarketQuotePrice(decimal: value.low.decimal, quoteCurrency: request.instrument.currency),
                    close: MarketQuotePrice(decimal: value.close.decimal, quoteCurrency: request.instrument.currency),
                    volume: try value.volume.map { try AssetQuantity(decimal: $0.decimal) },
                    adjustment: request.adjustment,
                    providerIdentifier: descriptor.identifier,
                    fetchedAt: fetchedAt,
                    freshness: freshness
                )
            }.sorted { $0.sessionDate < $1.sessionDate }
        }
        guard !bars.isEmpty else { throw ProviderBoundaryError.missing }
        let nextEnd = bars.count == request.outputSize ? bars.first?.sessionDate : nil
        recordObservation(
            endpoint: .historicalOHLCV,
            marketMIC: request.instrument.mic,
            state: .succeeded
        )
        return MarketHistoryPage(
            instrument: request.instrument,
            bars: bars,
            nextEndDate: nextEnd,
            sourceRevision: response.headers["etag"] ?? response.headers["last-modified"],
            providerIdentifier: descriptor.identifier
        )
    }

    func corporateActions(
        for instrument: MarketInstrument,
        from startDate: CivilDate?,
        through endDate: CivilDate?
    ) async throws -> [MarketCorporateAction] {
        async let splits = fetchSplits(for: instrument, from: startDate, through: endDate)
        async let dividends = fetchDividends(for: instrument, from: startDate, through: endDate)
        let actions = try await splits + dividends
        return actions.sorted {
            ($0.effectiveDate, $0.kind.rawValue, $0.id) <
                ($1.effectiveDate, $1.kind.rawValue, $1.id)
        }
    }

    private func fetchSplits(
        for instrument: MarketInstrument,
        from startDate: CivilDate?,
        through endDate: CivilDate?
    ) async throws -> [MarketCorporateAction] {
        let response = try await authenticatedRequest(
            path: "/splits",
            queryItems: actionQueryItems(instrument, from: startDate, through: endDate),
            creditWeight: 20,
            endpoint: .splits,
            marketMIC: instrument.mic
        )
        try throwProviderErrorIfPresent(
            response.data,
            statusCode: response.statusCode,
            endpoint: .splits,
            marketMIC: instrument.mic
        )
        let dto = try decodeProviderPayload(TwelveSplitsDTO.self, from: response.data)
        let actions = try validatedProviderMapping { try dto.splits.map { split in
            let date = try CivilDate(canonical: split.date)
            let fromFactor = try FixedPointMath.coefficient(from: split.fromFactor.decimal, scale: 0)
            let toFactor = try FixedPointMath.coefficient(from: split.toFactor.decimal, scale: 0)
            guard fromFactor > 0, toFactor > 0 else { throw ProviderBoundaryError.invalidPayload }
            return MarketCorporateAction(
                id: StableMarketIdentifier.hex(
                    "twelve-data|split|\(instrument.symbol)|\(instrument.mic)|\(date)"
                ),
                instrument: instrument,
                kind: .split,
                effectiveDate: date,
                amount: nil,
                splitFrom: fromFactor,
                splitTo: toFactor,
                providerIdentifier: descriptor.identifier,
                fetchedAt: clock.now()
            )
        } }
        recordObservation(endpoint: .splits, marketMIC: instrument.mic, state: .succeeded)
        return actions
    }

    private func fetchDividends(
        for instrument: MarketInstrument,
        from startDate: CivilDate?,
        through endDate: CivilDate?
    ) async throws -> [MarketCorporateAction] {
        let response = try await authenticatedRequest(
            path: "/dividends",
            queryItems: actionQueryItems(instrument, from: startDate, through: endDate),
            creditWeight: 20,
            endpoint: .dividends,
            marketMIC: instrument.mic
        )
        try throwProviderErrorIfPresent(
            response.data,
            statusCode: response.statusCode,
            endpoint: .dividends,
            marketMIC: instrument.mic
        )
        let dto = try decodeProviderPayload(TwelveDividendsDTO.self, from: response.data)
        let actions = try validatedProviderMapping { try dto.dividends.map { dividend in
            let date = try CivilDate(canonical: dividend.exDate)
            return MarketCorporateAction(
                id: StableMarketIdentifier.hex(
                    "twelve-data|dividend|\(instrument.symbol)|\(instrument.mic)|\(date)"
                ),
                instrument: instrument,
                kind: .dividend,
                effectiveDate: date,
                amount: try MarketQuotePrice(
                    decimal: dividend.amount.decimal,
                    quoteCurrency: instrument.currency
                ),
                splitFrom: nil,
                splitTo: nil,
                providerIdentifier: descriptor.identifier,
                fetchedAt: clock.now()
            )
        } }
        recordObservation(endpoint: .dividends, marketMIC: instrument.mic, state: .succeeded)
        return actions
    }

    private func authenticatedRequest(
        path: String,
        queryItems: [URLQueryItem],
        creditWeight: Int,
        endpoint: MarketProviderEndpoint? = nil,
        marketMIC: String? = nil
    ) async throws -> HTTPTransportResponse {
        guard requestAdmissionState == .accepting else {
            throw requestAdmissionState == .disconnected
                ? ProviderBoundaryError.missingCredential
                : ProviderBoundaryError.cancelled
        }
        let generation = credentialGeneration
        guard let credential = try await credentialStore.credential(for: Self.credentialDescriptor),
              let key = String(data: credential, encoding: .utf8),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderBoundaryError.missingCredential
        }
        guard requestAdmissionState == .accepting, generation == credentialGeneration else {
            throw ProviderBoundaryError.cancelled
        }

        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw ProviderBoundaryError.invalidRequest }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("apikey \(key)", forHTTPHeaderField: "Authorization")

        let deduplicationKey = "GET|\(path)|\(components?.percentEncodedQuery ?? "")"
        do {
            let response = try await sharedResponse(
                for: deduplicationKey,
                request: request,
                creditWeight: creditWeight,
                generation: generation
            )
            await observeCreditHeaders(response.headers)
            return response
        } catch let error as ProviderHTTPError {
            let mapped = mapHTTPError(error.response)
            if mapped == .unsupportedEntitlement {
                recordDenied(endpoint: endpoint, marketMIC: marketMIC)
            }
            throw mapped
        } catch is CancellationError {
            throw ProviderBoundaryError.cancelled
        }
    }

    private func sharedResponse(
        for key: String,
        request: URLRequest,
        creditWeight: Int,
        generation: UUID
    ) async throws -> HTTPTransportResponse {
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<HTTPTransportResponse, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                guard requestAdmissionState == .accepting,
                      generation == credentialGeneration else {
                    continuation.resume(throwing: ProviderBoundaryError.cancelled)
                    return
                }
                if var current = inFlight[key] {
                    current.waiters[waiterID] = continuation
                    inFlight[key] = current
                    return
                }

                let transport = self.transport
                let gate = self.gate
                let sleeper = self.sleeper
                let jitter = self.jitter
                let requestID = UUID()
                let task = Task<HTTPTransportResponse, Error> {
                    try await HTTPRetryExecutor.run(
                        request: request,
                        credits: creditWeight,
                        transport: transport,
                        gate: gate,
                        sleeper: sleeper,
                        jitter: jitter
                    )
                }
                transportTasks[requestID] = task
                inFlight[key] = InFlightRequest(
                    requestID: requestID,
                    task: task,
                    waiters: [waiterID: continuation]
                )
                Task {
                    let result = await task.result
                    self.finishSharedResponse(
                        for: key,
                        requestID: requestID,
                        result: result
                    )
                }
            }
        } onCancel: {
            Task { await self.cancelSharedWaiter(id: waiterID, for: key) }
        }
    }

    private func cancelSharedWaiter(id: UUID, for key: String) {
        guard var current = inFlight[key],
              let continuation = current.waiters.removeValue(forKey: id) else { return }
        continuation.resume(throwing: CancellationError())
        if current.waiters.isEmpty {
            current.task.cancel()
            inFlight[key] = nil
        } else {
            inFlight[key] = current
        }
    }

    private func finishSharedResponse(
        for key: String,
        requestID: UUID,
        result: Result<HTTPTransportResponse, Error>
    ) {
        transportTasks[requestID] = nil
        guard let current = inFlight[key], current.requestID == requestID else { return }
        inFlight[key] = nil
        for continuation in current.waiters.values {
            continuation.resume(with: result)
        }
    }

    private func stopAndAwaitTransportTermination() async throws {
        requestAdmissionState = .quiescing
        let requests = Array(inFlight.values)
        inFlight.removeAll()
        for request in requests {
            for continuation in request.waiters.values {
                continuation.resume(throwing: ProviderBoundaryError.cancelled)
            }
        }
        let captured = transportTasks
        for task in captured.values { task.cancel() }
        let terminated = await TransportTerminationRace().wait(
            for: Array(captured.values),
            timeoutMilliseconds: shutdownTimeoutMilliseconds
        )
        guard terminated else { throw ProviderBoundaryError.transportShutdownTimedOut }
        for requestID in captured.keys { transportTasks[requestID] = nil }
    }

    private func observeCreditHeaders(_ headers: [String: String]) async {
        guard let usedText = headers["api-credits-used"],
              let leftText = headers["api-credits-left"],
              let used = Int64(usedText), let left = Int64(leftText),
              used >= 0, left >= 0 else { return }
        let total = used.addingReportingOverflow(left)
        guard !total.overflow, let limit = Int(exactly: total.partialValue) else { return }
        await gate.applyObservedHeaderLimit(perMinute: limit)
    }

    private func mapHTTPError(_ response: HTTPTransportResponse) -> ProviderBoundaryError {
        switch response.statusCode {
        case 401:
            return .invalidOrExpired
        case 403:
            return .unsupportedEntitlement
        case 404:
            return .missing
        case 408:
            return .timeout
        case 429:
            let retryAfter = HTTPRetryExecutor.retryAfterMilliseconds(
                response.headers["retry-after"]
            )
            return .rateLimited(retryAfterMilliseconds: retryAfter)
        default:
            return .providerError(statusCode: response.statusCode)
        }
    }

    private func throwProviderErrorIfPresent(
        _ data: Data,
        statusCode: Int,
        endpoint: MarketProviderEndpoint? = nil,
        marketMIC: String? = nil
    ) throws {
        guard let error = try? JSONDecoder().decode(TwelveErrorDTO.self, from: data),
              error.status?.lowercased() == "error" else { return }
        switch error.code {
        case 401:
            throw ProviderBoundaryError.invalidOrExpired
        case 403:
            recordDenied(endpoint: endpoint, marketMIC: marketMIC)
            throw ProviderBoundaryError.unsupportedEntitlement
        case 404:
            throw ProviderBoundaryError.missing
        case 429:
            throw ProviderBoundaryError.rateLimited(retryAfterMilliseconds: nil)
        default:
            throw ProviderBoundaryError.providerError(statusCode: error.code ?? statusCode)
        }
    }

    private func instrumentQueryItems(_ instrument: MarketInstrument) -> [URLQueryItem] {
        [
            URLQueryItem(name: "symbol", value: instrument.symbol),
            URLQueryItem(name: "mic_code", value: instrument.mic)
        ]
    }

    private func actionQueryItems(
        _ instrument: MarketInstrument,
        from startDate: CivilDate?,
        through endDate: CivilDate?
    ) -> [URLQueryItem] {
        var items = instrumentQueryItems(instrument)
        if let startDate { items.append(URLQueryItem(name: "start_date", value: startDate.description)) }
        if let endDate { items.append(URLQueryItem(name: "end_date", value: endDate.description)) }
        return items
    }

    private func recordDenied(endpoint: MarketProviderEndpoint?, marketMIC: String?) {
        guard let endpoint else { return }
        recordObservation(endpoint: endpoint, marketMIC: marketMIC, state: .denied)
    }

    private func recordObservation(
        endpoint: MarketProviderEndpoint,
        marketMIC: String?,
        state: ProviderLiveObservation
    ) {
        let rawMIC = marketMIC?.uppercased()
        let key = LiveObservationKey(endpoint: endpoint, rawMIC: rawMIC)
        liveObservations[key] = LiveObservationRecord(
            capabilityKey: rawMIC.map(Self.capabilityKey(for:)),
            rawMIC: rawMIC,
            state: state
        )
    }

    private func aggregateObservation(for endpoint: MarketProviderEndpoint) -> ProviderLiveObservation {
        Self.aggregateObservation(
            liveObservations.compactMap { key, value in
                key.endpoint == endpoint ? value.state : nil
            }
        )
    }

    private static func aggregateObservation(
        _ observations: [ProviderLiveObservation]
    ) -> ProviderLiveObservation {
        let hasSuccess = observations.contains(.succeeded)
        let hasDenial = observations.contains(.denied)
        if hasSuccess && hasDenial { return .mixed }
        if hasSuccess { return .succeeded }
        if hasDenial { return .denied }
        return .notVerified
    }

    private static func capabilityKey(for mic: String) -> String {
        let normalized = mic.uppercased()
        let unitedStatesMICs: Set<String> = [
            "XNAS", "XNYS", "XASE", "ARCX", "BATS", "XNCM", "XNGS", "XNMS"
        ]
        return unitedStatesMICs.contains(normalized) ? "US" : normalized
    }

    private static func entitlement(forPlanName name: String?) -> MarketEntitlementState {
        guard let normalized = name?.lowercased() else { return .unknown }
        let token = normalized.split(whereSeparator: { $0.isWhitespace || $0 == "-" }).first
        if token == "basic" { return .basic }
        if token == "grow" || token == "pro" || token == "ultra" || token == "venture" {
            return .proOrHigher
        }
        return .unknown
    }

    private static func parseMarketDateTime(
        _ value: String,
        timeZoneIdentifier: String
    ) -> UTCInstant? {
        guard value.count > 10, let zone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: value).map(UTCInstant.init(date:))
    }
}

actor FrankfurterFXRateProvider: FXRateProvider {
    nonisolated let descriptor = ProviderDescriptor(
        identifier: "frankfurter.ecb",
        displayName: "ECB reference rates via Frankfurter",
        kind: .production
    )

    private let transport: any HTTPTransport
    private let gate: ProviderRequestGate
    private let clock: any Clock
    private let sleeper: any ProviderSleeper
    private let jitter: any RetryJitterSource
    private let baseURL: URL

    init(
        transport: any HTTPTransport,
        gate: ProviderRequestGate,
        clock: any Clock,
        sleeper: any ProviderSleeper = TaskProviderSleeper(),
        jitter: any RetryJitterSource = SystemRetryJitterSource(),
        baseURL: URL = URL(string: "https://api.frankfurter.dev")!
    ) {
        self.transport = transport
        self.gate = gate
        self.clock = clock
        self.sleeper = sleeper
        self.jitter = jitter
        self.baseURL = baseURL
    }

    func rate(
        source: CurrencyCode,
        target: CurrencyCode,
        on date: CivilDate
    ) async throws -> ExchangeRate {
        guard target == .cny else { throw ProviderBoundaryError.unsupportedEntitlement }
        if source == .cny {
            return ExchangeRate(
                id: StableMarketIdentifier.uuid("frankfurter|CNY|CNY|\(date)"),
                rate: .cnyIdentity,
                referenceDate: date,
                fetchedAt: clock.now(),
                providerIdentifier: descriptor.identifier,
                provenance: .identity,
                freshness: .endOfDay
            )
        }
        guard source == .usd else { throw ProviderBoundaryError.unsupportedEntitlement }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("/v2/rates"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "date", value: date.description),
            URLQueryItem(name: "base", value: "EUR"),
            URLQueryItem(name: "quotes", value: "USD,CNY"),
            URLQueryItem(name: "providers", value: "ECB")
        ]
        guard let url = components?.url else { throw ProviderBoundaryError.invalidRequest }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response: HTTPTransportResponse
        do {
            response = try await HTTPRetryExecutor.run(
                request: request,
                credits: 1,
                transport: transport,
                gate: gate,
                sleeper: sleeper,
                jitter: jitter
            )
        } catch let error as ProviderHTTPError {
            if error.response.statusCode == 404 { throw ProviderBoundaryError.missing }
            throw ProviderBoundaryError.providerError(statusCode: error.response.statusCode)
        }
        let rows = try decodeProviderPayload([FrankfurterRateDTO].self, from: response.data)
        guard let usd = rows.first(where: { $0.base == "EUR" && $0.quote == "USD" }),
              let cny = rows.first(where: { $0.base == "EUR" && $0.quote == "CNY" }),
              usd.date == cny.date,
              let referenceDate = try? CivilDate(canonical: usd.date),
              referenceDate <= date,
              usd.rate.decimal > 0,
              cny.rate.decimal > 0 else {
            throw ProviderBoundaryError.invalidPayload
        }
        let cross = cny.rate.decimal / usd.rate.decimal
        return try validatedProviderMapping {
            ExchangeRate(
                id: StableMarketIdentifier.uuid("frankfurter|USD|CNY|\(referenceDate)"),
                rate: try FXRate(decimal: cross, sourceCurrency: .usd, targetCurrency: .cny),
                referenceDate: referenceDate,
                fetchedAt: clock.now(),
                providerIdentifier: descriptor.identifier,
                provenance: .derivedCrossRate,
                freshness: .endOfDay
            )
        }
    }
}

private func decodeProviderPayload<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    do {
        return try JSONDecoder().decode(type, from: data)
    } catch {
        throw ProviderBoundaryError.invalidPayload
    }
}

private func validatedProviderMapping<T>(_ body: () throws -> T) throws -> T {
    do {
        return try body()
    } catch let error as ProviderBoundaryError {
        throw error
    } catch {
        throw ProviderBoundaryError.invalidPayload
    }
}

private enum StableMarketIdentifier {
    static func hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func uuid(_ text: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private struct LosslessDecimalDTO: Codable, Sendable {
    let decimal: Decimal

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self),
           let value = Decimal(string: text, locale: FixedPointMath.canonicalLocale) {
            decimal = value
            return
        }
        decimal = try container.decode(Decimal.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(NSDecimalNumber(decimal: decimal).stringValue)
    }
}

private struct TwelveErrorDTO: Decodable {
    let status: String?
    let code: Int?
    let message: String?
}

private struct TwelveUsageDTO: Decodable {
    let planName: String?
    let perMinuteLimit: Int?
    let dailyLimit: Int?

    enum CodingKeys: String, CodingKey {
        case planName = "plan_name"
        case plan
        case perMinuteLimit = "api_credits_per_minute"
        case dailyLimit = "daily_limit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planName = try container.decodeIfPresent(String.self, forKey: .planName)
            ?? container.decodeIfPresent(String.self, forKey: .plan)
        perMinuteLimit = try container.decodeIfPresent(Int.self, forKey: .perMinuteLimit)
        dailyLimit = try container.decodeIfPresent(Int.self, forKey: .dailyLimit)
    }
}

private struct TwelveSearchResponseDTO: Decodable {
    let data: [TwelveSearchItemDTO]
}

private struct TwelveSearchItemDTO: Decodable {
    let symbol: String
    let instrumentName: String
    let exchange: String?
    let micCode: String?
    let currency: String

    enum CodingKeys: String, CodingKey {
        case symbol
        case instrumentName = "instrument_name"
        case exchange
        case micCode = "mic_code"
        case currency
    }
}

private struct TwelveQuoteDTO: Decodable {
    let close: LosslessDecimalDTO
    let timestamp: Int64?
    let isMarketOpen: Bool?

    enum CodingKeys: String, CodingKey {
        case close
        case timestamp
        case isMarketOpen = "is_market_open"
    }
}

private struct TwelveTimeSeriesDTO: Decodable {
    let meta: TwelveTimeSeriesMetaDTO
    let values: [TwelveTimeSeriesValueDTO]
}

private struct TwelveTimeSeriesMetaDTO: Decodable {
    let currency: String
    let exchangeTimezone: String
    let micCode: String

    enum CodingKeys: String, CodingKey {
        case currency
        case exchangeTimezone = "exchange_timezone"
        case micCode = "mic_code"
    }
}

private struct TwelveTimeSeriesValueDTO: Decodable {
    let datetime: String
    let open: LosslessDecimalDTO
    let high: LosslessDecimalDTO
    let low: LosslessDecimalDTO
    let close: LosslessDecimalDTO
    let volume: LosslessDecimalDTO?
}

private struct TwelveSplitsDTO: Decodable {
    let splits: [TwelveSplitDTO]
}

private struct TwelveSplitDTO: Decodable {
    let date: String
    let fromFactor: LosslessDecimalDTO
    let toFactor: LosslessDecimalDTO

    enum CodingKeys: String, CodingKey {
        case date
        case fromFactor = "from_factor"
        case toFactor = "to_factor"
    }
}

private struct TwelveDividendsDTO: Decodable {
    let dividends: [TwelveDividendDTO]
}

private struct TwelveDividendDTO: Decodable {
    let exDate: String
    let amount: LosslessDecimalDTO

    enum CodingKeys: String, CodingKey {
        case exDate = "ex_date"
        case amount
    }
}

private struct FrankfurterRateDTO: Decodable {
    let date: String
    let base: String
    let quote: String
    let rate: LosslessDecimalDTO
}
