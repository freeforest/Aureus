import Foundation
import Observation

enum DashboardLoadState: Equatable, Sendable {
    case loading
    case empty
    case ready
    case failed
}

struct DashboardPayload: Sendable {
    let currentSummary: WealthSummary
    let completeSnapshots: [DashboardSnapshot]
    let history: [DashboardHistoryPoint]
    let changeMetrics: DashboardChangeMetrics
    let allocation: [DashboardAllocationSlice]
    let subassets: [DashboardSubassetValue]
    let cashFlow: [DashboardCashFlowPoint]
    let netWorthHeatmap: [DashboardHeatmapCell]
    let cashFlowHeatmap: [DashboardHeatmapCell]
    let currentSnapshot: DashboardSnapshot?
    let legacyIncompleteCount: Int
}

actor DashboardDataService {
    private let store: WealthStore
    private let calendar: Calendar

    init(store: WealthStore, timeZone: TimeZone) {
        self.store = store
        self.calendar = DashboardDateMath.gregorian(timeZone: timeZone)
    }

    func load(
        today: CivilDate,
        now: UTCInstant,
        range: DashboardTimeRange,
        heatmapMode: DashboardCashFlowHeatmapMode
    ) async throws -> DashboardPayload? {
        let records = try await store.fetchWealthContainers()
        guard !records.isEmpty else { return nil }
        _ = try await store.ensureDashboardSnapshot(for: today, createdAt: now)
        let snapshots = try await store.fetchDashboardSnapshots(through: today)
        let entries = try await store.fetchLedgerEntries()
        let summary = try WealthValuation.aggregate(records)
        let history = try DashboardCalculations.history(
            snapshots: snapshots,
            range: range,
            referenceDate: today,
            calendar: calendar
        )
        let cashFlow = try DashboardCalculations.cashFlow(
            entries: entries,
            range: range,
            referenceDate: today,
            calendar: calendar
        )
        return try DashboardPayload(
            currentSummary: summary,
            completeSnapshots: snapshots,
            history: history,
            changeMetrics: DashboardCalculations.changeMetrics(
                current: summary,
                snapshots: snapshots,
                today: today,
                calendar: calendar
            ),
            allocation: DashboardCalculations.allocation(records: records),
            subassets: DashboardCalculations.subassets(records: records, summary: summary),
            cashFlow: cashFlow,
            netWorthHeatmap: DashboardCalculations.netWorthHeatmap(
                snapshots: snapshots,
                range: range,
                referenceDate: today,
                calendar: calendar
            ),
            cashFlowHeatmap: DashboardCalculations.cashFlowHeatmap(
                points: cashFlow,
                mode: heatmapMode,
                range: range,
                referenceDate: today,
                calendar: calendar
            ),
            currentSnapshot: snapshots.last { $0.civilDate == today },
            legacyIncompleteCount: try await store.legacyIncompleteSnapshotCount()
        )
    }

    func refresh(today: CivilDate, now: UTCInstant) async throws {
        _ = try await store.refreshDashboardSnapshot(for: today, createdAt: now)
    }
}

@MainActor
@Observable
final class DashboardFeatureModel {
    private(set) var loadState: DashboardLoadState = .loading
    private(set) var currentSummary: WealthSummary = .zero
    private(set) var snapshots: [DashboardSnapshot] = []
    private(set) var history: [DashboardHistoryPoint] = []
    private(set) var changeMetrics: DashboardChangeMetrics?
    private(set) var allocation: [DashboardAllocationSlice] = []
    private(set) var subassets: [DashboardSubassetValue] = []
    private(set) var cashFlow: [DashboardCashFlowPoint] = []
    private(set) var netWorthHeatmap: [DashboardHeatmapCell] = []
    private(set) var cashFlowHeatmap: [DashboardHeatmapCell] = []
    private(set) var currentSnapshot: DashboardSnapshot?
    private(set) var legacyIncompleteCount = 0
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    var selectedRange: DashboardTimeRange = .oneMonth
    var cashFlowHeatmapMode: DashboardCashFlowHeatmapMode = .netCashFlow
    var selectedHistoryDate: CivilDate?
    var selectedNetWorthHeatmapDate: CivilDate?
    var selectedCashFlowHeatmapDate: CivilDate?

    @ObservationIgnored private let service: DashboardDataService
    @ObservationIgnored private let clock: any Clock
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var hasLoaded = false

    init(store: WealthStore, clock: any Clock, timeZone: TimeZone = .current) {
        self.service = DashboardDataService(store: store, timeZone: timeZone)
        self.clock = clock
        self.calendar = DashboardDateMath.gregorian(timeZone: timeZone)
    }

    var hasInsufficientHistory: Bool { !history.isEmpty && history.count < 2 }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reload()
    }

    func reload() async {
        loadState = .loading
        do {
            let now = clock.now()
            let today = try DashboardDateMath.civilDate(now.date, calendar: calendar)
            guard let payload = try await service.load(
                today: today,
                now: now,
                range: selectedRange,
                heatmapMode: cashFlowHeatmapMode
            ) else {
                clearForEmptyStore()
                loadState = .empty
                errorMessage = nil
                return
            }
            apply(payload)
            loadState = .ready
            errorMessage = nil
        } catch {
            loadState = .failed
            errorMessage = "Dashboard data could not be loaded. No Snapshot or wealth record was silently replaced."
        }
    }

    func selectRange(_ range: DashboardTimeRange) async {
        guard selectedRange != range else { return }
        selectedRange = range
        selectedHistoryDate = nil
        selectedNetWorthHeatmapDate = nil
        selectedCashFlowHeatmapDate = nil
        await reload()
    }

    func selectCashFlowHeatmapMode(_ mode: DashboardCashFlowHeatmapMode) async {
        guard cashFlowHeatmapMode != mode else { return }
        cashFlowHeatmapMode = mode
        selectedCashFlowHeatmapDate = nil
        await reload()
    }

    func refreshTodaySnapshot() async {
        guard loadState == .ready else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let now = clock.now()
            let today = try DashboardDateMath.civilDate(now.date, calendar: calendar)
            try await service.refresh(today: today, now: now)
            await reload()
        } catch DashboardPersistenceError.emptyWealthStore {
            clearForEmptyStore()
            loadState = .empty
            errorMessage = "An empty Wealth Store does not create a zero-value Snapshot."
        } catch {
            errorMessage = "Today’s Snapshot refresh failed atomically. The prior Snapshot remains available."
        }
    }

    private func apply(_ payload: DashboardPayload) {
        currentSummary = payload.currentSummary
        snapshots = payload.completeSnapshots
        history = payload.history
        changeMetrics = payload.changeMetrics
        allocation = payload.allocation
        subassets = payload.subassets
        cashFlow = payload.cashFlow
        netWorthHeatmap = payload.netWorthHeatmap
        cashFlowHeatmap = payload.cashFlowHeatmap
        currentSnapshot = payload.currentSnapshot
        legacyIncompleteCount = payload.legacyIncompleteCount
    }

    private func clearForEmptyStore() {
        currentSummary = .zero
        snapshots = []
        history = []
        changeMetrics = nil
        allocation = []
        subassets = []
        cashFlow = []
        netWorthHeatmap = []
        cashFlowHeatmap = []
        currentSnapshot = nil
        legacyIncompleteCount = 0
    }
}
