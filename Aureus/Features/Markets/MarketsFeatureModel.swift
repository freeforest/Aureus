import Foundation
import Observation

enum MarketsTerminalState: Equatable, Sendable {
    case idle
    case searching
    case loadingHistory
    case ready
    case noSessionData
    case missingCredential
    case invalidCredential
    case upgradeRequired
    case unsupportedEntitlement
    case unsupportedMarket
    case rateLimited
    case offline
    case timeout
    case cancelled
    case missing
    case invalidPayload
    case providerError
    case insufficientData
    case sessionCleared
}

struct MarketsCapabilityCard: Identifiable, Equatable, Sendable {
    enum Region: String, CaseIterable, Sendable {
        case us = "US"
        case hongKong = "Hong Kong"
        case mainlandChina = "Mainland China"
        case japan = "Japan"
    }

    let region: Region
    let status: String
    let detail: String
    var id: String { region.rawValue }
}

struct SessionHeatmapItem: Identifiable, Equatable, Sendable {
    enum ChangeCategory: String, Sendable {
        case gain = "Gain"
        case loss = "Loss"
        case unchanged = "Unchanged"
        case unknown = "Unknown"
    }

    let identity: MarketWatchlistIdentity
    let range: MarketRange
    let change: Decimal?
    let category: ChangeCategory
    var id: String { identity.id }
}

struct MarketsVisibleSummary: Equatable, Sendable {
    let start: CivilDate
    let end: CivilDate
    let firstClose: Decimal
    let lastClose: Decimal
    let high: Decimal
    let low: Decimal
    let totalVolume: Decimal?
    let change: Decimal
    let changePercentage: Decimal?
}

@MainActor
@Observable
final class MarketsFeatureModel {
    let mode: AppDataMode
    private(set) var state: MarketsTerminalState = .idle
    private(set) var searchResults: [MarketInstrument] = []
    private(set) var watchlist: [MarketWatchlistIdentity] = []
    private(set) var selectedInstrument: MarketInstrument?
    private(set) var historyPage: MarketHistoryPage?
    private(set) var indicatorSnapshot: MarketIndicatorSnapshot?
    private(set) var chartPayload: MarketChartPayload?
    private(set) var chartStatus = "Not loaded"
    private(set) var visibleRangeText = "No visible range"
    private(set) var sessionStatistics = TransientMarketSessionStatistics(
        entryCount: 0,
        accountedBytes: 0,
        maximumBytes: TransientMarketSessionStore.defaultMaximumBytes
    )
    private(set) var errorDisclosure: String?
    private(set) var lastActionDisclosure = "No automatic market request is made at launch."
    private(set) var ephemeralInstruments: [MarketWatchlistIdentity: MarketInstrument] = [:]

    var query = "" {
        didSet {
            if oldValue != query {
                searchTask?.cancel()
                searchGeneration = UUID()
            }
        }
    }
    var selectedRange: MarketRange = .oneYear
    var enabledIndicators: Set<MarketIndicatorKind> = [.sma20, .ema12]
    var showsAccessibleTable = false

    private let marketDataService: MarketDataService
    private let marketProvider: any MarketDataProvider
    private let sessionStore: TransientMarketSessionStore
    private let preferences: MarketPreferencesStore
    private let clock: any Clock
    private var searchTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var searchGeneration = UUID()
    private var historyGeneration = UUID()

    init(
        marketDataService: MarketDataService,
        marketProvider: any MarketDataProvider,
        sessionStore: TransientMarketSessionStore,
        preferences: MarketPreferencesStore,
        clock: any Clock,
        mode: AppDataMode
    ) {
        self.marketDataService = marketDataService
        self.marketProvider = marketProvider
        self.sessionStore = sessionStore
        self.preferences = preferences
        self.clock = clock
        self.mode = mode
    }

    var capabilityCards: [MarketsCapabilityCard] {
        [
            .init(
                region: .us,
                status: "Verified at observed scope",
                detail: "AAPL / XNGS Search and daily .all Historical succeeded at the Stage 6NBC observation instant. This is not complete US coverage."
            ),
            .init(region: .hongKong, status: "Not Verified", detail: "XHKG requires separate endpoint and exchange-license evidence."),
            .init(region: .mainlandChina, status: "Not Verified", detail: "XSHG and XSHE live endpoints have not been accepted."),
            .init(region: .japan, status: "Not Verified", detail: "XJPX requires separate endpoint and exchange-license evidence.")
        ]
    }

    var heatmapItems: [SessionHeatmapItem] {
        watchlist.map { identity in
            guard let page = historyPage,
                  page.instrument.symbol == identity.symbol,
                  page.instrument.mic == identity.mic,
                  let first = page.bars.first?.close.decimal,
                  let last = page.bars.last?.close.decimal else {
                return .init(identity: identity, range: selectedRange, change: nil, category: .unknown)
            }
            let change = last - first
            let category: SessionHeatmapItem.ChangeCategory = change > 0 ? .gain : (change < 0 ? .loss : .unchanged)
            return .init(identity: identity, range: selectedRange, change: change, category: category)
        }
    }

    var visibleSummary: MarketsVisibleSummary? {
        guard let bars = historyPage?.bars, let first = bars.first, let last = bars.last else { return nil }
        let high = bars.map(\.high.decimal).max() ?? first.high.decimal
        let low = bars.map(\.low.decimal).min() ?? first.low.decimal
        let change = last.close.decimal - first.close.decimal
        let percentage = first.close.decimal == 0 ? nil : change / first.close.decimal * 100
        let volumes = bars.compactMap(\.volume?.decimal)
        return MarketsVisibleSummary(
            start: first.sessionDate,
            end: last.sessionDate,
            firstClose: first.close.decimal,
            lastClose: last.close.decimal,
            high: high,
            low: low,
            totalVolume: volumes.isEmpty ? nil : volumes.reduce(.zero, +),
            change: change,
            changePercentage: percentage
        )
    }

    func start() async {
        do {
            let snapshot = try await preferences.load()
            watchlist = snapshot.watchlist
            selectedRange = snapshot.selectedRange
            enabledIndicators = snapshot.enabledIndicators
            showsAccessibleTable = snapshot.showsAccessibleTable
        } catch {
            errorDisclosure = "Market preferences could not be loaded. Provider data was not restored."
        }
        await refreshSessionStatistics()
        if sessionStatistics.entryCount == 0 { state = .noSessionData }
    }

    func submitSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchTask?.cancel()
            searchResults = []
            state = .idle
            errorDisclosure = "Enter a symbol or company query. No request was sent."
            return
        }
        searchTask?.cancel()
        let generation = UUID()
        searchGeneration = generation
        state = .searching
        errorDisclosure = nil
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                guard let self else { return }
                let results = try await self.marketDataService.search(query: trimmed)
                try Task.checkCancellation()
                guard self.searchGeneration == generation else { return }
                self.searchResults = results
                for instrument in results {
                    if let identity = try? MarketWatchlistIdentity(symbol: instrument.symbol, mic: instrument.mic) {
                        self.ephemeralInstruments[identity] = instrument
                    }
                }
                self.state = .ready
                self.lastActionDisclosure = "Search succeeded. Search visibility does not establish price, action, Plan, or freshness entitlement."
                await self.refreshSessionStatistics()
            } catch is CancellationError {
                guard self?.searchGeneration == generation else { return }
                self?.state = .cancelled
            } catch let error as ProviderBoundaryError {
                guard self?.searchGeneration == generation else { return }
                self?.apply(error)
                await self?.refreshSessionStatistics()
            } catch {
                guard self?.searchGeneration == generation else { return }
                self?.state = .providerError
                self?.errorDisclosure = "A redacted local market error occurred."
            }
        }
    }

    func select(_ instrument: MarketInstrument) {
        selectedInstrument = instrument
        historyTask?.cancel()
        historyGeneration = UUID()
        historyPage = nil
        indicatorSnapshot = nil
        chartPayload = nil
        chartStatus = "Not loaded"
        state = .ready
    }

    func select(_ identity: MarketWatchlistIdentity) {
        if let instrument = ephemeralInstruments[identity] {
            select(instrument)
        } else {
            selectedInstrument = nil
            state = .noSessionData
            errorDisclosure = "Only the user-authored symbol and raw MIC were restored. Search to resolve current session data."
        }
    }

    func addSelectedToWatchlist() async {
        guard let instrument = selectedInstrument,
              let identity = try? MarketWatchlistIdentity(symbol: instrument.symbol, mic: instrument.mic) else { return }
        guard !watchlist.contains(identity) else {
            errorDisclosure = "The symbol and raw MIC are already in the Watchlist."
            return
        }
        guard watchlist.count < MarketPreferencesStore.maximumWatchlistCount else {
            errorDisclosure = "The Watchlist limit is 100 identifiers."
            return
        }
        watchlist.append(identity)
        await persistPreferences()
    }

    func removeFromWatchlist(_ identity: MarketWatchlistIdentity) async {
        watchlist.removeAll { $0 == identity }
        await persistPreferences()
    }

    func moveWatchlist(from source: IndexSet, to destination: Int) async {
        watchlist.move(fromOffsets: source, toOffset: destination)
        await persistPreferences()
    }

    func updateRange(_ range: MarketRange) async {
        historyTask?.cancel()
        historyGeneration = UUID()
        selectedRange = range
        lastActionDisclosure = "Range changed. Select Refresh Daily Data to make a bounded request."
        await persistPreferences()
    }

    func toggleIndicator(_ kind: MarketIndicatorKind) async {
        if enabledIndicators.contains(kind) { enabledIndicators.remove(kind) } else { enabledIndicators.insert(kind) }
        await persistPreferences()
        rebuildPresentation()
    }

    func setAccessibleTable(_ value: Bool) async {
        showsAccessibleTable = value
        await persistPreferences()
    }

    func refreshSelectedHistory() {
        guard let instrument = selectedInstrument else {
            state = .missing
            errorDisclosure = "Select a current-session Search result before loading daily data."
            return
        }
        historyTask?.cancel()
        let generation = UUID()
        historyGeneration = generation
        state = .loadingHistory
        errorDisclosure = nil
        historyTask = Task { [weak self] in
            guard let self else { return }
            do {
                let request = try MarketHistoryRequest(
                    instrument: instrument,
                    interval: .oneDay,
                    adjustment: .all,
                    outputSize: self.selectedRange.outputSize
                )
                let page = try await self.marketDataService.historicalBars(request)
                try Task.checkCancellation()
                guard self.historyGeneration == generation,
                      page.instrument.symbol == instrument.symbol,
                      page.instrument.mic == instrument.mic else { return }
                self.historyPage = page
                self.state = page.bars.isEmpty ? .insufficientData : .ready
                self.lastActionDisclosure = page.bars.isEmpty
                    ? "Historical returned no daily bars."
                    : "Daily .all bars loaded into the current session only."
                self.rebuildPresentation()
                await self.refreshSessionStatistics()
            } catch is CancellationError {
                guard self.historyGeneration == generation else { return }
                self.state = .cancelled
            } catch let error as ProviderBoundaryError {
                guard self.historyGeneration == generation else { return }
                self.apply(error)
                await self.refreshSessionStatistics()
            } catch {
                guard self.historyGeneration == generation else { return }
                self.state = .providerError
                self.errorDisclosure = "A redacted local market error occurred."
            }
        }
    }

    func clearSession() async {
        searchTask?.cancel()
        historyTask?.cancel()
        searchGeneration = UUID()
        historyGeneration = UUID()
        do {
            _ = try await marketDataService.clearSessionMarketData()
            searchResults = []
            historyPage = nil
            indicatorSnapshot = nil
            chartPayload = nil
            ephemeralInstruments = [:]
            selectedInstrument = nil
            state = .sessionCleared
            lastActionDisclosure = "Session market data cleared. Watchlist identifiers remain preferences only."
            chartStatus = "Session cleared"
        } catch {
            state = .providerError
            errorDisclosure = "Session clear failed without changing permanent wealth data."
        }
        await refreshSessionStatistics()
    }

    func receiveChartMessage(_ message: MarketChartInboundMessage) {
        switch message {
        case .ready: chartStatus = "Chart ready"
        case let .visibleRange(start, end): visibleRangeText = "Visible range \(start) through \(end)"
        case let .crosshair(date):
            if let date { visibleRangeText = "Crosshair session date \(date)" }
        case let .rendererError(category): chartStatus = "Chart error: \(category)"
        }
    }

    private func rebuildPresentation() {
        guard let page = historyPage else { return }
        do {
            let indicators = try MarketIndicatorCalculator.calculate(
                bars: page.bars,
                interval: .oneDay,
                adjustment: .all
            )
            indicatorSnapshot = indicators
            chartPayload = try MarketChartPayload(
                configuration: .init(
                    schemaVersion: MarketChartPayload.schemaVersion,
                    provider: page.providerIdentifier,
                    symbol: page.instrument.symbol,
                    rawMIC: page.instrument.mic,
                    freshness: page.bars.last?.freshness.rawValue ?? MarketFreshness.unknown.rawValue,
                    selectedRange: selectedRange.rawValue,
                    darkAppearance: false
                ),
                bars: page.bars,
                indicators: indicators,
                enabledIndicators: enabledIndicators
            )
        } catch {
            indicatorSnapshot = nil
            chartPayload = nil
            state = .invalidPayload
            errorDisclosure = "Daily bars could not be represented safely."
        }
    }

    private func persistPreferences() async {
        do {
            try await preferences.save(.init(
                version: MarketPreferencesSnapshot.currentVersion,
                watchlist: watchlist,
                selectedRange: selectedRange,
                enabledIndicators: enabledIndicators,
                showsAccessibleTable: showsAccessibleTable
            ))
        } catch {
            errorDisclosure = "Market preferences could not be saved. Session Provider data was not persisted."
        }
    }

    private func refreshSessionStatistics() async {
        sessionStatistics = await sessionStore.statistics()
    }

    private func apply(_ error: ProviderBoundaryError) {
        switch error {
        case .missingCredential: state = .missingCredential
        case .invalidOrExpired: state = .invalidCredential
        case .upgradeRequired: state = .upgradeRequired
        case .unsupportedEntitlement: state = .unsupportedEntitlement
        case .unsupportedMarket: state = .unsupportedMarket
        case .rateLimited, .requestCostExceedsLimit: state = .rateLimited
        case .offline: state = .offline
        case .timeout: state = .timeout
        case .cancelled: state = .cancelled
        case .missing: state = .missing
        case .invalidPayload, .invalidTimeArithmetic: state = .invalidPayload
        case .invalidRequest, .providerError, .transportShutdownTimedOut, .retentionUnverified: state = .providerError
        }
        errorDisclosure = Self.disclosure(for: state)
    }

    private static func disclosure(for state: MarketsTerminalState) -> String {
        switch state {
        case .missingCredential: "Missing Credential — configure the user-owned key in Settings."
        case .invalidCredential: "Invalid or Expired Credential. Stale data is not used to hide this state."
        case .upgradeRequired: "Upgrade Required for this endpoint or market."
        case .unsupportedEntitlement: "Unsupported by Current Entitlement."
        case .unsupportedMarket: "Unsupported Market for the current entitlement."
        case .rateLimited: "Rate Limited. No exact account quota is displayed."
        case .offline: "Market Data Unavailable Offline."
        case .timeout: "Provider request timed out."
        case .cancelled: "The previous market request was cancelled."
        case .missing: "Requested session data is missing."
        case .invalidPayload: "Provider payload could not be mapped into the typed Domain."
        case .providerError: "Provider Error. Sensitive details are redacted."
        case .insufficientData: "Insufficient Data."
        case .sessionCleared: "Session Cleared."
        case .idle, .searching, .loadingHistory, .ready, .noSessionData: "No Session Market Data."
        }
    }
}
