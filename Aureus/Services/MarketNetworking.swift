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
    private var minuteLimit: Int
    private var dailyLimit: Int?
    private var minuteWindowStart: UTCInstant
    private var dayWindowStart: UTCInstant
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
        self.minuteLimit = minuteLimit
        self.dailyLimit = dailyLimit
        self.clock = clock
        self.sleeper = sleeper
        let now = clock.now()
        minuteWindowStart = now
        dayWindowStart = now
    }

    func execute<T: Sendable>(
        credits: Int,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        guard credits > 0 else { throw ProviderBoundaryError.invalidRequest }
        try await acquireConcurrencyPermit()
        defer { releaseConcurrencyPermit() }
        try await reserveCredits(credits)
        try Task.checkCancellation()
        return try await operation()
    }

    func applyVerifiedLimits(perMinute: Int?, perDay: Int?) {
        if let perMinute, perMinute > 0 { minuteLimit = perMinute }
        if let perDay, perDay > 0 { dailyLimit = perDay }
    }

    func applyObservedHeaderLimit(perMinute: Int) {
        guard perMinute > 0 else { return }
        minuteLimit = min(minuteLimit, perMinute)
    }

    func currentLimits() -> (perMinute: Int, perDay: Int?) {
        (minuteLimit, dailyLimit)
    }

    private func acquireConcurrencyPermit() async throws {
        try Task.checkCancellation()
        if activeRequests < maximumConcurrentRequests {
            activeRequests += 1
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
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

    private func reserveCredits(_ credits: Int) async throws {
        let now = clock.now()
        rollWindows(now: now)
        guard credits <= minuteLimit else {
            throw ProviderBoundaryError.rateLimited(retryAfterMilliseconds: 60_000)
        }
        if let dailyLimit, credits > dailyLimit {
            throw ProviderBoundaryError.rateLimited(retryAfterMilliseconds: nil)
        }

        if minuteCredits + credits > minuteLimit {
            let elapsed = now.millisecondsSince1970 - minuteWindowStart.millisecondsSince1970
            try await sleeper.sleep(milliseconds: max(1, 60_000 - elapsed))
            try await reserveCredits(credits)
            return
        }
        if let dailyLimit, dailyCredits + credits > dailyLimit {
            let elapsed = now.millisecondsSince1970 - dayWindowStart.millisecondsSince1970
            try await sleeper.sleep(milliseconds: max(1, 86_400_000 - elapsed))
            try await reserveCredits(credits)
            return
        }

        minuteCredits += credits
        dailyCredits += credits
    }

    private func rollWindows(now: UTCInstant) {
        if now.millisecondsSince1970 - minuteWindowStart.millisecondsSince1970 >= 60_000 {
            minuteWindowStart = now
            minuteCredits = 0
        }
        if now.millisecondsSince1970 - dayWindowStart.millisecondsSince1970 >= 86_400_000 {
            dayWindowStart = now
            dailyCredits = 0
        }
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
        if let value = headers["retry-after"], let seconds = Int64(value), seconds >= 0 {
            return seconds * 1_000
        }
        let base: Int64 = [1_000, 2_000, 4_000][min(attempt, 2)]
        return base + jitter.milliseconds(upperBound: 250)
    }
}

actor TwelveDataClient: MarketDataProvider {
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
    private var inFlight: [String: Task<HTTPTransportResponse, Error>] = [:]
    private var isDisconnected = false
    private var lastUsage: ProviderUsageObservation?
    private var marketObservations: [String: MarketEntitlementState] = [:]

    init(
        credentialStore: any CredentialStore,
        transport: any HTTPTransport,
        gate: ProviderRequestGate,
        clock: any Clock,
        sleeper: any ProviderSleeper = TaskProviderSleeper(),
        jitter: any RetryJitterSource = SystemRetryJitterSource(),
        baseURL: URL = URL(string: "https://api.twelvedata.com")!
    ) {
        self.credentialStore = credentialStore
        self.transport = transport
        self.gate = gate
        self.clock = clock
        self.sleeper = sleeper
        self.jitter = jitter
        self.baseURL = baseURL
    }

    func capabilities() -> MarketProviderCapabilities {
        let entitlement = lastUsage?.entitlement ?? .unknown
        let observedAt = lastUsage?.observedAt
        let isBasic = entitlement == .basic
        let isPro = entitlement == .proOrHigher

        func observed(for mic: String) -> MarketEntitlementState {
            if let actual = marketObservations[mic] { return actual }
            if mic == "US" { return isBasic ? .basic : (isPro ? .proOrHigher : .unknown) }
            if isBasic { return .upgradeRequired }
            return .unknown
        }

        let markets = [
            MarketCapability(
                mic: "US", minimumEntitlement: .basic, observedEntitlement: observed(for: "US"),
                freshness: .realTime, supportsSearch: true, supportsHistoricalBars: true,
                supportsCorporateActions: true, evidenceStatus: "OFFICIAL_CATALOG"
            ),
            MarketCapability(
                mic: "XHKG", minimumEntitlement: .proOrHigher,
                observedEntitlement: observed(for: "XHKG"), freshness: .unknown,
                supportsSearch: true, supportsHistoricalBars: false,
                supportsCorporateActions: false, evidenceStatus: "CONFLICTING_EOD_EVIDENCE"
            ),
            MarketCapability(
                mic: "XSHG", minimumEntitlement: .proOrHigher,
                observedEntitlement: observed(for: "XSHG"), freshness: .endOfDay,
                supportsSearch: true, supportsHistoricalBars: true,
                supportsCorporateActions: false, evidenceStatus: "OFFICIAL_CATALOG_NOT_LIVE_VERIFIED"
            ),
            MarketCapability(
                mic: "XSHE", minimumEntitlement: .proOrHigher,
                observedEntitlement: observed(for: "XSHE"), freshness: .endOfDay,
                supportsSearch: true, supportsHistoricalBars: true,
                supportsCorporateActions: false, evidenceStatus: "OFFICIAL_CATALOG_NOT_LIVE_VERIFIED"
            ),
            MarketCapability(
                mic: "XJPX", minimumEntitlement: .proOrHigher,
                observedEntitlement: observed(for: "XJPX"), freshness: .unknown,
                supportsSearch: true, supportsHistoricalBars: false,
                supportsCorporateActions: false, evidenceStatus: "CONFLICTING_EOD_EVIDENCE"
            )
        ]
        return MarketProviderCapabilities(
            provider: descriptor,
            entitlement: isDisconnected ? .missing : entitlement,
            observedPlanName: lastUsage?.planName,
            markets: markets,
            supportsSearch: true,
            supportsHistoricalPrices: true,
            supportsCorporateActions: true,
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
        let fallbackMinute: Int?
        let fallbackDay: Int?
        switch entitlement {
        case .basic:
            fallbackMinute = 8
            fallbackDay = 800
        default:
            fallbackMinute = nil
            fallbackDay = nil
        }
        let minute = dto.perMinuteLimit ?? fallbackMinute
        let day = dto.dailyLimit ?? fallbackDay
        await gate.applyVerifiedLimits(perMinute: minute, perDay: day)
        let observation = ProviderUsageObservation(
            planName: plan,
            entitlement: entitlement,
            perMinuteLimit: minute,
            dailyLimit: day,
            observedAt: clock.now()
        )
        lastUsage = observation
        return observation
    }

    func credentialDidChange() {
        isDisconnected = false
        lastUsage = nil
        marketObservations = [:]
    }

    func disconnect() {
        isDisconnected = true
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        lastUsage = nil
        marketObservations = [:]
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
            creditWeight: 1
        )
        try throwProviderErrorIfPresent(response.data, statusCode: response.statusCode)
        let dto = try decodeProviderPayload(TwelveSearchResponseDTO.self, from: response.data)
        return try validatedProviderMapping {
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
    }

    func latestQuote(for instrument: MarketInstrument) async throws -> MarketQuote {
        let response = try await authenticatedRequest(
            path: "/quote",
            queryItems: instrumentQueryItems(instrument),
            creditWeight: 1
        )
        try throwProviderErrorIfPresent(response.data, statusCode: response.statusCode)
        let dto = try decodeProviderPayload(TwelveQuoteDTO.self, from: response.data)
        let price = try validatedProviderMapping {
            try MarketQuotePrice(decimal: dto.close.decimal, quoteCurrency: instrument.currency)
        }
        let observedAt = dto.timestamp.map { UTCInstant(millisecondsSince1970: $0 * 1_000) }
            ?? clock.now()
        recordSuccessfulMarket(instrument.mic)
        return MarketQuote(
            instrument: instrument,
            price: price,
            observedAt: observedAt,
            fetchedAt: clock.now(),
            providerIdentifier: descriptor.identifier,
            // A closed exchange is not evidence that a quote is delayed.
            quality: .current,
            freshness: dto.isMarketOpen == true ? .realTime : .unknown
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
            creditWeight: 1
        )
        try throwProviderErrorIfPresent(response.data, statusCode: response.statusCode)
        let dto = try decodeProviderPayload(TwelveTimeSeriesDTO.self, from: response.data)
        guard dto.meta.micCode.uppercased() == request.instrument.mic,
              let responseCurrency = try? MarketCurrencyCode(validating: dto.meta.currency),
              responseCurrency == request.instrument.currency else {
            throw ProviderBoundaryError.invalidPayload
        }
        let fetchedAt = clock.now()
        let freshness: MarketFreshness = request.interval.isIntraday ? .delayed : .endOfDay
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
        recordSuccessfulMarket(request.instrument.mic)
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
        recordSuccessfulMarket(instrument.mic)
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
            creditWeight: 20
        )
        try throwProviderErrorIfPresent(response.data, statusCode: response.statusCode)
        let dto = try decodeProviderPayload(TwelveSplitsDTO.self, from: response.data)
        return try validatedProviderMapping { try dto.splits.map { split in
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
    }

    private func fetchDividends(
        for instrument: MarketInstrument,
        from startDate: CivilDate?,
        through endDate: CivilDate?
    ) async throws -> [MarketCorporateAction] {
        let response = try await authenticatedRequest(
            path: "/dividends",
            queryItems: actionQueryItems(instrument, from: startDate, through: endDate),
            creditWeight: 20
        )
        try throwProviderErrorIfPresent(response.data, statusCode: response.statusCode)
        let dto = try decodeProviderPayload(TwelveDividendsDTO.self, from: response.data)
        return try validatedProviderMapping { try dto.dividends.map { dividend in
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
    }

    private func authenticatedRequest(
        path: String,
        queryItems: [URLQueryItem],
        creditWeight: Int
    ) async throws -> HTTPTransportResponse {
        guard !isDisconnected else { throw ProviderBoundaryError.missingCredential }
        guard let credential = try await credentialStore.credential(for: Self.credentialDescriptor),
              let key = String(data: credential, encoding: .utf8),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderBoundaryError.missingCredential
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
        if let task = inFlight[deduplicationKey] {
            return try await awaitResponse(task)
        }
        let transport = self.transport
        let gate = self.gate
        let sleeper = self.sleeper
        let jitter = self.jitter
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
        inFlight[deduplicationKey] = task
        defer { inFlight[deduplicationKey] = nil }
        do {
            let response = try await awaitResponse(task)
            await observeCreditHeaders(response.headers)
            return response
        } catch let error as ProviderHTTPError {
            throw mapHTTPError(error.response)
        }
    }

    private func awaitResponse(
        _ task: Task<HTTPTransportResponse, Error>
    ) async throws -> HTTPTransportResponse {
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func observeCreditHeaders(_ headers: [String: String]) async {
        guard let usedText = headers["api-credits-used"],
              let leftText = headers["api-credits-left"],
              let used = Int(usedText), let left = Int(leftText),
              used >= 0, left >= 0 else { return }
        await gate.applyObservedHeaderLimit(perMinute: used + left)
    }

    private func mapHTTPError(_ response: HTTPTransportResponse) -> ProviderBoundaryError {
        switch response.statusCode {
        case 401, 403:
            return .invalidOrExpired
        case 404:
            return .missing
        case 408:
            return .timeout
        case 429:
            let retryAfter = response.headers["retry-after"].flatMap(Int64.init).map { $0 * 1_000 }
            return .rateLimited(retryAfterMilliseconds: retryAfter)
        default:
            return .providerError(statusCode: response.statusCode)
        }
    }

    private func throwProviderErrorIfPresent(_ data: Data, statusCode: Int) throws {
        guard let error = try? JSONDecoder().decode(TwelveErrorDTO.self, from: data),
              error.status?.lowercased() == "error" else { return }
        switch error.code {
        case 401, 403:
            throw ProviderBoundaryError.invalidOrExpired
        case 404:
            throw ProviderBoundaryError.missing
        case 429:
            throw ProviderBoundaryError.rateLimited(retryAfterMilliseconds: nil)
        default:
            let text = error.message?.lowercased() ?? ""
            if text.contains("plan") || text.contains("premium") {
                throw ProviderBoundaryError.upgradeRequired("Provider entitlement required")
            }
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

    private func recordSuccessfulMarket(_ mic: String) {
        switch lastUsage?.entitlement {
        case .basic:
            marketObservations[mic] = .basic
        case .proOrHigher:
            marketObservations[mic] = .proOrHigher
        default:
            marketObservations[mic] = .unknown
        }
    }

    private static func entitlement(forPlanName name: String?) -> MarketEntitlementState {
        guard let normalized = name?.lowercased() else { return .unknown }
        if normalized.contains("basic") { return .basic }
        if normalized.contains("pro") || normalized.contains("ultra") {
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
