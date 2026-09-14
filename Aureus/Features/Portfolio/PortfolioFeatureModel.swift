import Foundation
import Observation

actor PortfolioPreferencesStore {
    private struct Snapshot: Codable, Sendable {
        let version: Int
        let benchmarkByPortfolio: [String: PortfolioBenchmarkPreference]
    }

    private let defaults: UserDefaults?
    private var memory: [UUID: PortfolioBenchmarkPreference] = [:]
    private let key = "portfolio.identifier-only-preferences.v1"

    init(suiteName: String?, memoryOnly: Bool) {
        defaults = memoryOnly ? nil : (suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard)
    }

    func preference(for portfolioID: UUID) throws -> PortfolioBenchmarkPreference? {
        if defaults == nil { return memory[portfolioID] }
        guard let data = defaults?.data(forKey: key) else { return nil }
        let decoded = try JSONDecoder().decode(Snapshot.self, from: data)
        return decoded.benchmarkByPortfolio[portfolioID.uuidString]
    }

    func save(_ preference: PortfolioBenchmarkPreference?, for portfolioID: UUID) throws {
        memory[portfolioID] = preference
        guard let defaults else { return }
        var values: [String: PortfolioBenchmarkPreference] = [:]
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) {
            values = decoded.benchmarkByPortfolio
        }
        values[portfolioID.uuidString] = preference
        defaults.set(try JSONEncoder().encode(Snapshot(version: 1, benchmarkByPortfolio: values)), forKey: key)
    }
}

enum PortfolioTerminalState: Equatable, Sendable {
    case idle
    case ready
    case empty
    case loadingBenchmark
    case benchmarkReady
    case benchmarkMissing
    case benchmarkDenied
    case benchmarkOffline
    case benchmarkTimeout
    case error
}

@MainActor
@Observable
final class PortfolioFeatureModel {
    static let stableProviderPolicyDisclosure = "Portfolio records are local and use Manual Wealth Marks. No Provider request is made automatically."
    static let benchmarkNotLoadedDisclosure = "Benchmark session data not loaded."

    let mode: AppDataMode
    private(set) var state: PortfolioTerminalState = .idle
    private(set) var portfolios: [PortfolioRecord] = []
    var selectedPortfolioID: UUID?
    private(set) var securityLinks: [PortfolioSecurityLink] = []
    private(set) var activities: [PortfolioActivity] = []
    private(set) var holdings: [PortfolioHoldingSummary] = []
    private(set) var snapshots: [PortfolioNAVSnapshot] = []
    private(set) var eligibleWealth: [WealthContainer] = []
    private(set) var benchmarkPreference: PortfolioBenchmarkPreference?
    private(set) var benchmarkComparison: [PortfolioIndexedPoint] = []
    private(set) var errorMessage: String?
    private(set) var benchmarkDisclosure = PortfolioFeatureModel.benchmarkNotLoadedDisclosure
    var pendingPortfolioDeletion: PortfolioRecord?

    private let store: WealthStore
    private let marketDataService: MarketDataService
    private let marketSessionStore: TransientMarketSessionStore
    private let preferences: PortfolioPreferencesStore
    private let clock: any Clock
    private var benchmarkTask: Task<Void, Never>?
    private var generation = UUID()

    init(
        store: WealthStore,
        marketDataService: MarketDataService,
        marketSessionStore: TransientMarketSessionStore,
        preferences: PortfolioPreferencesStore,
        clock: any Clock,
        mode: AppDataMode
    ) {
        self.store = store
        self.marketDataService = marketDataService
        self.marketSessionStore = marketSessionStore
        self.preferences = preferences
        self.clock = clock
        self.mode = mode
    }

    var selectedPortfolio: PortfolioRecord? {
        portfolios.first { $0.id == selectedPortfolioID }
    }

    var providerPolicyDisclosure: String { Self.stableProviderPolicyDisclosure }

    var totalNAV: Money {
        (try? holdings.map(\.marketValueCNY).reduce(Money(minorUnits: 0, currency: .cny)) { try $0.adding($1) })
            ?? Money(minorUnits: 0, currency: .cny)
    }

    func start() async {
        await reload(selecting: selectedPortfolioID)
    }

    func reload(selecting id: UUID?) async {
        do {
            portfolios = try await store.fetchPortfolios()
            selectedPortfolioID = id.flatMap { candidate in portfolios.contains { $0.id == candidate } ? candidate : nil }
                ?? selectedPortfolioID.flatMap { candidate in portfolios.contains { $0.id == candidate } ? candidate : nil }
                ?? portfolios.first?.id
            eligibleWealth = try await store.fetchWealthContainers().filter { $0.container.kind.isManualSecurity }
            try await reloadSelection()
            state = portfolios.isEmpty ? .empty : .ready
            errorMessage = nil
        } catch {
            state = .error
            errorMessage = "Portfolio records could not be loaded. Permanent data was not replaced."
        }
    }

    func select(_ id: UUID?) async {
        benchmarkTask?.cancel()
        generation = UUID()
        selectedPortfolioID = id
        benchmarkComparison = []
        benchmarkDisclosure = Self.benchmarkNotLoadedDisclosure
        await reload(selecting: id)
    }

    func createPortfolio(name: String) async {
        do {
            let now = clock.now()
            let portfolio = try PortfolioRecord(name: name, createdAt: now, updatedAt: now, sortOrder: portfolios.count)
            try await store.createPortfolio(portfolio)
            await reload(selecting: portfolio.id)
        } catch {
            errorMessage = "Portfolio name must be non-empty and unique local records must remain valid."
        }
    }

    func renameSelected(_ name: String) async {
        guard let id = selectedPortfolioID else { return }
        do {
            try await store.renamePortfolio(id: id, name: name, updatedAt: clock.now())
            await reload(selecting: id)
        } catch { errorMessage = "Portfolio rename failed without changing holdings." }
    }

    func moveSelected(offset: Int) async {
        guard let id = selectedPortfolioID, let index = portfolios.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard portfolios.indices.contains(destination) else { return }
        var ids = portfolios.map(\.id)
        ids.swapAt(index, destination)
        do {
            try await store.reorderPortfolios(ids, updatedAt: clock.now())
            await reload(selecting: id)
        } catch { errorMessage = "Portfolio reorder failed atomically." }
    }

    func requestDeleteSelected() { pendingPortfolioDeletion = selectedPortfolio }

    func cancelDelete() { pendingPortfolioDeletion = nil }

    func confirmDelete(id: UUID) async {
        defer {
            if pendingPortfolioDeletion?.id == id {
                pendingPortfolioDeletion = nil
            }
        }
        do {
            try await store.deletePortfolio(id: id)
            await reload(selecting: nil)
        } catch { errorMessage = "Portfolio delete failed. Wealth, Ledger, and Snapshots were not altered." }
    }

    func linkWealthContainer(_ containerID: UUID) async {
        guard let portfolioID = selectedPortfolioID,
              let wealth = eligibleWealth.first(where: { $0.id == containerID }),
              case let .security(ticker, mic, _, _) = wealth.details,
              let mic else { return }
        do {
            let link = try PortfolioSecurityLink(
                portfolioID: portfolioID, wealthContainerID: containerID,
                symbol: ticker, rawMIC: mic, currency: wealth.container.primaryCurrency,
                assetKind: wealth.container.kind, sortOrder: securityLinks.count
            )
            try await store.linkPortfolioSecurity(link)
            await reload(selecting: portfolioID)
        } catch { errorMessage = "Security link is invalid, duplicated, or not a Stock/ETF/Fund Wealth record." }
    }

    func addActivity(_ payload: PortfolioActivityPayload, to linkID: UUID, date: CivilDate) async {
        guard let portfolioID = selectedPortfolioID else { return }
        do {
            let activity = try PortfolioActivity(
                portfolioID: portfolioID, securityLinkID: linkID, civilDate: date,
                recordedAt: clock.now(), exchangeTimeZoneIdentifier: "UTC", payload: payload
            )
            try await store.createPortfolioActivity(activity)
            await reload(selecting: portfolioID)
        } catch let error as PortfolioDomainError where error == .oversell {
            errorMessage = "Oversell rejected. Short positions are not supported."
        } catch { errorMessage = "Activity validation failed and the operation was rolled back." }
    }

    func deleteActivity(_ id: UUID) async {
        guard let portfolioID = selectedPortfolioID else { return }
        do {
            try await store.deletePortfolioActivity(id: id)
            await reload(selecting: portfolioID)
        } catch { errorMessage = "Deleting this activity would invalidate later FIFO history; no change was saved." }
    }

    func captureNAV(on date: CivilDate) async {
        guard let portfolioID = selectedPortfolioID else { return }
        do {
            let items = holdings.map { holding in
                PortfolioNAVSnapshotItem(
                    id: UUID(), securityLinkID: holding.link.id,
                    quantity: holding.portfolioQuantity, manualMark: holding.manualMark,
                    originalMarketValue: holding.marketValue, fx: holding.wealthFX,
                    convertedCNYValue: holding.marketValueCNY,
                    remainingCNYBasis: holding.remainingCNYBasis,
                    reconciliation: holding.reconciliation
                )
            }
            let snapshot = PortfolioNAVSnapshot(
                id: UUID(), portfolioID: portfolioID, civilDate: date,
                createdAt: clock.now(), totalCNY: totalNAV, isComplete: true, items: items
            )
            try await store.replacePortfolioNAVSnapshot(snapshot)
            await reload(selecting: portfolioID)
        } catch { errorMessage = "Complete NAV snapshot failed atomically." }
    }

    func saveBenchmark(symbol: String, rawMIC: String, range: MarketRange) async {
        guard let portfolioID = selectedPortfolioID else { return }
        do {
            let value = try PortfolioBenchmarkPreference(symbol: symbol, rawMIC: rawMIC, range: range)
            try await preferences.save(value, for: portfolioID)
            benchmarkPreference = value
            benchmarkComparison = []
            benchmarkDisclosure = Self.benchmarkNotLoadedDisclosure
        } catch { errorMessage = "Benchmark preference requires a symbol and four-character raw MIC." }
    }

    func loadSessionBenchmark() {
        guard let preference = benchmarkPreference else {
            state = .benchmarkMissing
            benchmarkDisclosure = Self.benchmarkNotLoadedDisclosure
            return
        }
        benchmarkTask?.cancel()
        let operationGeneration = UUID()
        generation = operationGeneration
        state = .loadingBenchmark
        benchmarkTask = Task { [weak self] in
            guard let self else { return }
            do {
                // A persisted benchmark preference intentionally has no Provider currency or
                // description. Resolve the exact typed instrument in the current session instead
                // of guessing either value from its identifier.
                let instruments = try await self.marketDataService.search(query: preference.symbol)
                guard let instrument = instruments.first(where: {
                    $0.symbol == preference.symbol && $0.mic == preference.rawMIC
                }) else {
                    throw ProviderBoundaryError.missing
                }
                let window = try MarketRangeRequestPolicy.window(for: preference.range, now: self.clock.now())
                let request = try MarketHistoryRequest(
                    instrument: instrument, interval: .oneDay, adjustment: .all,
                    startDate: window.startDate, endDate: window.endDate,
                    outputSize: window.outputSizeUpperBound
                )
                let page = try await self.marketDataService.historicalBars(request)
                guard self.generation == operationGeneration else { return }
                self.benchmarkComparison = try PortfolioBenchmarkComparison.indexed100(
                    snapshots: self.snapshots, benchmark: window.filter(page.bars)
                )
                self.state = .benchmarkReady
                self.benchmarkDisclosure = "Indexed comparison — base 100. Session-only; exact overlapping civil dates only."
            } catch let error as ProviderBoundaryError {
                guard self.generation == operationGeneration else { return }
                self.applyBenchmarkFailure(error)
            } catch {
                guard self.generation == operationGeneration else { return }
                self.state = .benchmarkMissing
                self.benchmarkDisclosure = Self.benchmarkNotLoadedDisclosure
                self.errorMessage = "Benchmark comparison needs at least two exact overlapping dates."
            }
        }
    }

    /// Applies only the finite, sanitized presentation state for an already typed
    /// Provider boundary error. It never forwards raw Provider text.
    func applyBenchmarkFailure(_ error: ProviderBoundaryError) {
        switch error {
        case .missingCredential, .missing:
            state = .benchmarkMissing
            benchmarkDisclosure = Self.benchmarkNotLoadedDisclosure
        case .offline:
            state = .benchmarkOffline
            benchmarkDisclosure = "Benchmark unavailable offline."
        case .timeout:
            state = .benchmarkTimeout
            benchmarkDisclosure = "Benchmark request timed out. Session data was not loaded."
        case .invalidOrExpired, .unsupportedEntitlement, .unsupportedMarket, .upgradeRequired:
            state = .benchmarkDenied
            benchmarkDisclosure = "Benchmark requires current entitlement."
        default:
            state = .error
            benchmarkDisclosure = "Benchmark session data is unavailable."
        }
    }

    func clearSessionBenchmark() async {
        benchmarkTask?.cancel()
        generation = UUID()
        benchmarkComparison = []
        benchmarkDisclosure = Self.benchmarkNotLoadedDisclosure
        _ = try? await marketDataService.clearSessionMarketData()
        state = portfolios.isEmpty ? .empty : .ready
    }

    private func reloadSelection() async throws {
        guard let portfolioID = selectedPortfolioID else {
            securityLinks = []; activities = []; holdings = []; snapshots = []; benchmarkPreference = nil
            return
        }
        securityLinks = try await store.fetchPortfolioSecurityLinks(portfolioID: portfolioID)
        activities = try await store.fetchPortfolioActivities(portfolioID: portfolioID)
        holdings = try await store.portfolioHoldingSummaries(portfolioID: portfolioID)
        snapshots = try await store.fetchPortfolioNAVSnapshots(portfolioID: portfolioID)
        benchmarkPreference = try await preferences.preference(for: portfolioID)
    }
}
