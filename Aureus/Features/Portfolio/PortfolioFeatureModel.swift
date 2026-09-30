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

    init(requiredSuiteName: String) throws {
        guard !requiredSuiteName.isEmpty,
              let defaults = UserDefaults(suiteName: requiredSuiteName) else {
            throw RuntimeEnvironmentError.invalidPreferenceSuite
        }
        self.defaults = defaults
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

enum PortfolioActivityLoadState: Equatable { case idle, loading, ready, failed }
enum PortfolioEditFXIntent: String, CaseIterable { case preserve, manualReset }
enum PortfolioActivityEditorError: Error, Equatable { case invalidField, incompatibleLink, missingFX }

/// Exact editable inputs; immutable metadata always comes from the same-read context.
struct PortfolioActivityDraft: Equatable {
    var kind: PortfolioActivity.Kind = .openingLot
    var securityLinkID: UUID?
    var civilDate = ""
    var quantity = ""
    var totalCost = ""
    var unitPrice = ""
    var fee = ""
    var splitFrom = ""
    var splitTo = ""
    var note = ""
    var fxIntent: PortfolioEditFXIntent = .preserve
    var fxRate = ""
    var fxReferenceDate = ""
    var fxIsStale = false

    init() {}

    init(_ activity: PortfolioActivity) {
        kind = activity.kind; securityLinkID = activity.securityLinkID
        civilDate = activity.civilDate.description
        switch activity.payload {
        case let .openingLot(q, cost, _, originalNote):
            quantity = Self.text(q.decimal); totalCost = Self.text(cost.decimal)
            note = originalNote ?? ""
        case let .buy(q, price, tradeFee, _), let .sell(q, price, tradeFee, _):
            quantity = Self.text(q.decimal); unitPrice = Self.text(price.decimal)
            fee = Self.text(tradeFee.decimal)
        case let .manualSplit(from, to):
            splitFrom = Self.text(from.decimal); splitTo = Self.text(to.decimal)
        }
        if let fx = Self.fx(activity.payload) {
            fxRate = Self.text(fx.rate.decimal); fxReferenceDate = fx.referenceDate.description
            fxIsStale = fx.isStale
        }
    }

    static func text(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
    static func fx(_ payload: PortfolioActivityPayload) -> PortfolioFXProvenance? {
        switch payload {
        case let .openingLot(_, _, fx, _), let .buy(_, _, _, fx), let .sell(_, _, _, fx): fx
        case .manualSplit: nil
        }
    }

    private func number(_ text: String) throws -> Decimal {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Decimal(string:) accepts a numeric prefix. Require the whole canonical input.
        guard raw.range(of: #"^[+-]?[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil else {
            throw PortfolioActivityEditorError.invalidField
        }
        return try FixedPointMath.parseCanonical(raw)
    }

    func candidate(context: PortfolioActivityEditContext, link: PortfolioSecurityLink,
                   commandTime: UTCInstant) throws -> PortfolioActivity {
        let old = context.activity
        guard link.id == securityLinkID, link.portfolioID == old.portfolioID,
              link.currency == context.link.currency else { throw PortfolioActivityEditorError.incompatibleLink }
        let date = try CivilDate(canonical: civilDate)
        let payload: PortfolioActivityPayload
        if kind == .manualSplit {
            payload = .manualSplit(from: try Ratio(decimal: number(splitFrom)), to: try Ratio(decimal: number(splitTo)))
        } else {
            let q = try AssetQuantity(decimal: number(quantity))
            let original: Money
            var price: MarketPrice?
            var tradeFee: Money?
            if kind == .openingLot {
                original = try Money(decimal: number(totalCost), currency: link.currency)
            } else {
                let p = try MarketPrice(decimal: number(unitPrice), quoteCurrency: link.currency)
                let f = try Money(decimal: number(fee), currency: link.currency)
                let gross = try PortfolioCheckedMath.moneyProduct(quantity: q, price: p)
                original = kind == .buy ? try gross.adding(f) : try gross.subtracting(f)
                price = p; tradeFee = f
            }
            let fx: PortfolioFXProvenance
            switch fxIntent {
            case .preserve:
                guard let prior = Self.fx(old.payload) else { throw PortfolioActivityEditorError.missingFX }
                fx = try PortfolioFXProvenance(original: original, rate: prior.rate, source: prior.source,
                    referenceDate: prior.referenceDate, recordedAt: prior.recordedAt,
                    isManual: prior.isManual, isStale: prior.isStale)
            case .manualReset:
                let enteredRate = try number(fxRate)
                guard link.currency != .cny || enteredRate == 1 else { throw PortfolioActivityEditorError.invalidField }
                let rate = link.currency == .cny ? FXRate.cnyIdentity : try FXRate(decimal: enteredRate,
                    sourceCurrency: .usd, targetCurrency: .cny)
                fx = try PortfolioFXProvenance(original: original, rate: rate,
                    source: link.currency == .cny ? "identity" : "manual",
                    referenceDate: CivilDate(canonical: fxReferenceDate), recordedAt: commandTime,
                    isManual: link.currency == .usd, isStale: fxIsStale)
            }
            if kind == .openingLot {
                let savedNote: String?
                if case let .openingLot(_, _, _, originalNote) = old.payload, note == (originalNote ?? "") {
                    savedNote = originalNote
                } else { savedNote = note.isEmpty ? nil : note }
                payload = .openingLot(quantity: q, totalCost: original, fx: fx, note: savedNote)
            } else if let price, let tradeFee {
                payload = kind == .buy ? .buy(quantity: q, unitPrice: price, fee: tradeFee, fx: fx)
                    : .sell(quantity: q, unitPrice: price, fee: tradeFee, fx: fx)
            } else { throw PortfolioActivityEditorError.invalidField }
        }
        let candidate = try PortfolioActivity(id: old.id, portfolioID: old.portfolioID,
            securityLinkID: link.id, civilDate: date, recordedAt: old.recordedAt,
            exchangeTimeZoneIdentifier: old.exchangeTimeZoneIdentifier,
            ledgerEntryID: old.ledgerEntryID, payload: payload)
        try PortfolioCorrectionProjection(candidate, link: link).validate()
        return candidate
    }
}

/// The same finite, read-only presentation is consumed by the View and Feature tests.
struct PortfolioActivityHistoryDisplay: Identifiable, Equatable {
    let id: UUID
    let title: String
    let explanation: String
    let before: String
    let after: String

    init(_ history: PortfolioCorrectionHistory) {
        id = history.id
        title = "\(history.kind) · sequence \(history.sequence) · UTC ms \(history.occurredAt.millisecondsSince1970)"
        explanation = history.kind == "correction" ? (history.reason ?? "")
            : "Context from \(history.payload.deletion?.origin ?? "unknown API"); no user correction reason."
        before = Self.projection(history.payload.before)
        after = history.payload.after.map(Self.projection) ?? "Activity deleted; historical values are read-only."
    }

    static func projection(_ p: PortfolioCorrectionProjection) -> String {
        let a = p.details.domain
        var values = ["Activity \(p.id.uuidString) · Portfolio \(p.portfolioID.uuidString)",
            "\(p.civilDate) · UTC ms \(p.recordedAt.millisecondsSince1970) · \(p.exchangeTimeZoneIdentifier)",
            "Link \(p.securityLinkID.uuidString) · \(p.link.symbol)/\(p.link.rawMIC) · \(p.link.currency.rawValue) · Wealth \(p.link.wealthContainerID.uuidString)",
            "Ledger \(p.ledgerEntryID?.uuidString ?? "none")"]
        switch a {
        case let .openingLot(q, c, _, note):
            values.append("openingLot · quantity \(PortfolioActivityDraft.text(q.decimal)) · cost \(PortfolioActivityDraft.text(c.decimal)) · note \(note ?? "none")")
        case let .buy(q, price, fee, _), let .sell(q, price, fee, _):
            let kind: String = { if case .buy = a { return "buy" }; return "sell" }()
            values.append("\(kind) · quantity \(PortfolioActivityDraft.text(q.decimal)) · price \(PortfolioActivityDraft.text(price.decimal)) · fee \(PortfolioActivityDraft.text(fee.decimal))")
        case let .manualSplit(from, to):
            values.append("manualSplit · \(PortfolioActivityDraft.text(from.decimal)) → \(PortfolioActivityDraft.text(to.decimal))")
        }
        if let fx = PortfolioActivityDraft.fx(a) {
            values.append("\(fx.original.currency.rawValue) \(PortfolioActivityDraft.text(fx.original.decimal)) · FX \(PortfolioActivityDraft.text(fx.rate.decimal)) · CNY \(PortfolioActivityDraft.text(fx.convertedCNY.decimal))")
            values.append("Source \(fx.source) · reference \(fx.referenceDate) · FX UTC ms \(fx.recordedAt.millisecondsSince1970) · manual \(fx.isManual) · stale \(fx.isStale)")
        }
        return values.joined(separator: "\n")
    }
}

@MainActor
@Observable
final class PortfolioFeatureModel {
    static let stableProviderPolicyDisclosure = "Portfolio records are local and use Manual Wealth Marks. No Provider request is made automatically."
    static let benchmarkNotLoadedDisclosure = "Benchmark session data not loaded."

    let mode: AppDataMode
    private(set) var state: PortfolioTerminalState = .idle
    private(set) var portfolios: [PortfolioRecord] = []
    private var selectionID: UUID?
    var selectedPortfolioID: UUID? {
        get { selectionID }
        set {
            guard !isSavingActivity, newValue != selectionID else { return }
            selectionID = newValue
            selectionSession = UUID()
            cancelActivityEdit()
            closeActivityHistory()
        }
    }
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

    private(set) var activityEditID: UUID?
    private(set) var activityEditContext: PortfolioActivityEditContext?
    private(set) var activityEditLinks: [PortfolioSecurityLink] = []
    var activityDraft = PortfolioActivityDraft()
    var activityCorrectionReason = ""
    private(set) var activityEditState: PortfolioActivityLoadState = .idle
    private(set) var activityEditFeedback: String?
    private(set) var requiresActivityReload = false
    private(set) var isSavingActivity = false
    private(set) var activitySaveOutcome: String?
    private(set) var activityHistoryID: UUID?
    private(set) var activityHistoryState: PortfolioActivityLoadState = .idle
    private(set) var activityHistory: [PortfolioCorrectionHistory] = []

    @ObservationIgnored private let contextLoader: @Sendable (UUID) async throws -> PortfolioActivityEditContext
    @ObservationIgnored private let historyLoader: @Sendable (UUID) async throws -> [PortfolioCorrectionHistory]
    @ObservationIgnored private let correctionWriter: @Sendable (PortfolioCorrectionRequest) async throws -> PortfolioCorrectionResult
    @ObservationIgnored private let activityLoader: @Sendable (UUID) async throws -> [PortfolioActivity]
    @ObservationIgnored private var editSession = UUID()
    @ObservationIgnored private var historySession = UUID()
    @ObservationIgnored private var selectionSession = UUID()
    @ObservationIgnored private var reloadSession = UUID()
    @ObservationIgnored private var pendingActivityRequest: PortfolioCorrectionRequest?
    @ObservationIgnored private var pendingActivityDraft: PortfolioActivityDraft?

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
        mode: AppDataMode,
        contextLoader: (@Sendable (UUID) async throws -> PortfolioActivityEditContext)? = nil,
        historyLoader: (@Sendable (UUID) async throws -> [PortfolioCorrectionHistory])? = nil,
        correctionWriter: (@Sendable (PortfolioCorrectionRequest) async throws -> PortfolioCorrectionResult)? = nil,
        activityLoader: (@Sendable (UUID) async throws -> [PortfolioActivity])? = nil
    ) {
        self.store = store
        self.marketDataService = marketDataService
        self.marketSessionStore = marketSessionStore
        self.preferences = preferences
        self.clock = clock
        self.mode = mode
        self.contextLoader = contextLoader ?? { try await store.readPortfolioActivityEditContext(id: $0) }
        self.historyLoader = historyLoader ?? { try await store.portfolioActivityCorrectionHistory(id: $0) }
        self.correctionWriter = correctionWriter ?? { try await store.correctPortfolioActivity($0) }
        self.activityLoader = activityLoader ?? { try await store.fetchPortfolioActivities(portfolioID: $0) }
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
        reloadSession = UUID()
        let load = reloadSession, selection = selectionSession
        do {
            let loadedPortfolios = try await store.fetchPortfolios()
            guard load == reloadSession, selection == selectionSession else { return }
            portfolios = loadedPortfolios
            selectedPortfolioID = id.flatMap { candidate in portfolios.contains { $0.id == candidate } ? candidate : nil }
                ?? selectedPortfolioID.flatMap { candidate in portfolios.contains { $0.id == candidate } ? candidate : nil }
                ?? portfolios.first?.id
            let currentSelection = selectionSession
            let wealth = try await store.fetchWealthContainers().filter { $0.container.kind.isManualSecurity }
            guard load == reloadSession, currentSelection == selectionSession else { return }
            eligibleWealth = wealth
            try await reloadSelection()
            guard load == reloadSession, currentSelection == selectionSession else { return }
            state = portfolios.isEmpty ? .empty : .ready
            errorMessage = nil
        } catch {
            guard load == reloadSession else { return }
            state = .error
            errorMessage = "Portfolio records could not be loaded. Permanent data was not replaced."
        }
    }

    func select(_ id: UUID?) async {
        guard !isSavingActivity else { return }
        benchmarkTask?.cancel()
        generation = UUID()
        selectedPortfolioID = id
        benchmarkComparison = []
        benchmarkDisclosure = Self.benchmarkNotLoadedDisclosure
        await reload(selecting: id)
    }

    func createPortfolio(name: String) async {
        guard !isSavingActivity else { return }
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
        guard !isSavingActivity else { return }
        guard let id = selectedPortfolioID else { return }
        do {
            try await store.renamePortfolio(id: id, name: name, updatedAt: clock.now())
            await reload(selecting: id)
        } catch { errorMessage = "Portfolio rename failed without changing holdings." }
    }

    func moveSelected(offset: Int) async {
        guard !isSavingActivity else { return }
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

    func requestDeleteSelected() {
        guard !isSavingActivity else { return }
        pendingPortfolioDeletion = selectedPortfolio
    }

    func cancelDelete() { pendingPortfolioDeletion = nil }

    func confirmDelete(id: UUID) async {
        guard !isSavingActivity else { return }
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
        guard !isSavingActivity else { return }
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
        guard !isSavingActivity else { return }
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
        guard !isSavingActivity else { return }
        guard let portfolioID = selectedPortfolioID else { return }
        do {
            try await store.deletePortfolioActivity(id: id)
            await reload(selecting: portfolioID)
        } catch { errorMessage = "Deleting this activity would invalidate later FIFO history; no change was saved." }
    }

    func captureNAV(on date: CivilDate) async {
        guard !isSavingActivity else { return }
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
        let selection = selectionSession, load = reloadSession
        let links = try await store.fetchPortfolioSecurityLinks(portfolioID: portfolioID)
        let rows = try await activityLoader(portfolioID)
        let summaries = try await store.portfolioHoldingSummaries(portfolioID: portfolioID)
        let nav = try await store.fetchPortfolioNAVSnapshots(portfolioID: portfolioID)
        let preference = try await preferences.preference(for: portfolioID)
        guard selection == selectionSession, load == reloadSession, selectedPortfolioID == portfolioID else { return }
        securityLinks = links; activities = rows; holdings = summaries
        snapshots = nav; benchmarkPreference = preference
    }

    func beginActivityEdit(id: UUID) async {
        guard !isSavingActivity, let portfolioID = selectedPortfolioID else { return }
        cancelActivityEdit()
        closeActivityHistory()
        let session = editSession, selection = selectionSession
        activityEditID = id; activityEditState = .loading
        activitySaveOutcome = nil
        do {
            let context = try await contextLoader(id)
            let links = try await store.fetchPortfolioSecurityLinks(portfolioID: portfolioID)
            guard session == editSession, selection == selectionSession, activityEditID == id else { return }
            guard context.activity.id == id, context.activity.portfolioID == portfolioID else {
                throw PortfolioActivityEditorError.incompatibleLink
            }
            activityEditContext = context
            activityEditLinks = links.filter { $0.currency == context.link.currency }
            activityDraft = PortfolioActivityDraft(context.activity)
            activityEditState = .ready
        } catch {
            guard session == editSession, selection == selectionSession else { return }
            activityEditState = .failed
            activityEditFeedback = "Activity could not be loaded. Close or explicitly reload current data."
        }
    }

    func cancelActivityEdit() {
        guard !isSavingActivity else { return }
        clearActivityEdit()
    }

    private func clearActivityEdit() {
        editSession = UUID(); activityEditID = nil; activityEditContext = nil
        activityEditLinks = []; activityDraft = PortfolioActivityDraft()
        activityCorrectionReason = ""; activityEditFeedback = nil
        activityEditState = .idle; requiresActivityReload = false
        pendingActivityRequest = nil; pendingActivityDraft = nil
    }

    /// The View asks for explicit discard confirmation before invoking this method.
    func reloadActivityEdit() async {
        guard !isSavingActivity, let id = activityEditID else { return }
        await beginActivityEdit(id: id)
    }

    func activityCandidate(at time: UTCInstant) throws -> PortfolioActivity {
        guard let context = activityEditContext,
              let link = activityEditLinks.first(where: { $0.id == activityDraft.securityLinkID }) else {
            throw PortfolioActivityEditorError.incompatibleLink
        }
        return try activityDraft.candidate(context: context, link: link, commandTime: time)
    }

    private func isImportant(_ candidate: PortfolioActivity) throws -> Bool {
        guard let context = activityEditContext,
              let link = activityEditLinks.first(where: { $0.id == candidate.securityLinkID }) else {
            throw PortfolioActivityEditorError.incompatibleLink
        }
        return !PortfolioCorrectionProjection(context.activity, link: context.link)
            .hasSameImportantValues(as: PortfolioCorrectionProjection(candidate, link: link))
    }

    var needsActivityCorrectionReason: Bool {
        guard let context = activityEditContext else { return false }
        if activityDraft.kind != .manualSplit, activityDraft.fxIntent == .manualReset { return true }
        guard let candidate = try? activityCandidate(at: context.activity.recordedAt) else { return false }
        return (try? isImportant(candidate)) == true
    }

    var canSaveActivity: Bool {
        guard !isSavingActivity, activityEditState == .ready, !requiresActivityReload,
              let context = activityEditContext,
              (try? activityCandidate(at: context.activity.recordedAt)) != nil else { return false }
        return !needsActivityCorrectionReason || (try? PortfolioCorrectionEncoding.reason(activityCorrectionReason)) != nil
    }

    func saveActivityEdit() async {
        guard !isSavingActivity, activityEditState == .ready, !requiresActivityReload,
              let context = activityEditContext else { return }
        let request: PortfolioCorrectionRequest
        let durable: Bool
        do {
            if let pending = pendingActivityRequest {
                guard pendingActivityDraft == activityDraft,
                      pending.reason == activityCorrectionReason.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    requiresActivityReload = true
                    activityEditFeedback = "The pending draft or FX intent changed. Discard the draft and reload before a new request."
                    return
                }
                request = pending; durable = true
            } else {
                let now = clock.now()
                let candidate = try activityCandidate(at: now)
                durable = try isImportant(candidate)
                let reason = durable ? try PortfolioCorrectionEncoding.reason(activityCorrectionReason) : ""
                request = PortfolioCorrectionRequest(candidate: candidate, expected: context.token,
                    operationID: UUID(), reason: reason, occurredAt: now)
                if durable { pendingActivityRequest = request; pendingActivityDraft = activityDraft }
            }
        } catch {
            activityEditFeedback = "Check the payload, date, security link, FX inputs and correction reason (1–500 characters, no NUL)."
            return
        }
        isSavingActivity = true
        defer { isSavingActivity = false }
        activityEditFeedback = nil
        let session = editSession
        let result: PortfolioCorrectionResult
        do {
            result = try await correctionWriter(request)
        } catch {
            guard session == editSession else { return }
            switch error {
            case PortfolioCorrectionError.staleDraft, PortfolioPersistenceError.notFound:
                requiresActivityReload = true
                activityEditFeedback = "Activity changed or was deleted. Your draft remains; discard and reload current data."
            case PortfolioCorrectionError.operationConflict:
                requiresActivityReload = true
                activityEditFeedback = "Operation conflicts with a different request. Discard and reload current data."
            case PortfolioCorrectionError.maintenanceUnavailable:
                requiresActivityReload = !durable
                activityEditFeedback = durable ? "Maintenance is in progress. Retry this unchanged request later."
                    : "Maintenance is in progress. Reload before another non-durable edit."
            case PortfolioPersistenceError.invalidHistoricalMutation, PortfolioCorrectionError.invalidRequest,
                 PortfolioCorrectionError.invalidHistory, is PortfolioDomainError, is FinancialValueError:
                pendingActivityRequest = nil; pendingActivityDraft = nil
                activityEditFeedback = "Correction rejected. Check the payload, link and subsequent FIFO activities; no edit was committed."
            default:
                requiresActivityReload = !durable
                activityEditFeedback = durable ? "Save status is unknown. Retry the same unchanged request, or explicitly discard and reload."
                    : "Save status is unknown. This edit has no durable receipt; discard and reload before saving again."
            }
            return
        }
        guard session == editSession else { return }
        switch result {
        case .alreadyApplied(_, .changed), .alreadyApplied(_, .deleted):
            requiresActivityReload = true
            activitySaveOutcome = "committed-later-state"
            activityEditFeedback = "The correction was committed, but the Activity later changed or was deleted. Reload; it will not be overwritten or recreated."
        case .applied, .alreadyApplied(_, .unchanged), .minorUpdate, .noChange:
            switch result {
            case .noChange: activitySaveOutcome = "noChange"
            case .minorUpdate: activitySaveOutcome = "minorUpdate"
            default: activitySaveOutcome = "committed"
            }
            clearActivityEdit()
            // A refresh error cannot turn an acknowledged commit into an uncertain write.
            do { try await reloadSelection() }
            catch {
                errorMessage = "Activity save was confirmed, but the local display refresh failed. Reload the Portfolio; do not resubmit the correction."
            }
        }
    }

    func showActivityHistory(id: UUID) async {
        guard !isSavingActivity, let portfolioID = selectedPortfolioID else { return }
        cancelActivityEdit()
        historySession = UUID()
        let session = historySession, selection = selectionSession
        activityHistoryID = id; activityHistory = []; activityHistoryState = .loading
        do {
            let rows = try await historyLoader(id)
            guard session == historySession, selection == selectionSession else { return }
            guard rows.allSatisfy({ $0.targetID == id && $0.payload.before.portfolioID == portfolioID }) else {
                throw PortfolioCorrectionError.invalidHistory
            }
            activityHistory = rows.sorted { $0.sequence < $1.sequence }
            activityHistoryState = .ready
        } catch {
            guard session == historySession, selection == selectionSession else { return }
            activityHistoryState = .failed
        }
    }

    func closeActivityHistory() {
        historySession = UUID(); activityHistoryID = nil
        activityHistory = []; activityHistoryState = .idle
    }
}
