import Foundation
import Observation

enum DashboardLoadState: Equatable, Sendable {
    case loading
    case empty
    case ready
    case failed
}

struct DashboardPayload: Sendable {
    let currentSummary: WealthSummary?
    let goalProjections: [DashboardGoalProjection]
    let completeSnapshots: [DashboardSnapshot]
    let history: [DashboardHistoryPoint]
    let changeMetrics: DashboardChangeMetrics?
    let historicalHighCNY: Money?
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
        let source = try await store.readDashboardSource(for: today, createdAt: now)
        let displayableEntries = source.ledgerEntries.filter { $0.civilDate <= today }
        guard !source.currentWealthRecords.isEmpty
                || !source.completeSnapshots.isEmpty
                || !displayableEntries.isEmpty
                || !source.goals.isEmpty
                || source.legacyIncompleteSnapshotCount > 0 else {
            return nil
        }
        let summary = source.currentWealthRecords.isEmpty
            ? nil
            : try WealthValuation.aggregate(source.currentWealthRecords)
        let history = try DashboardCalculations.history(
            snapshots: source.completeSnapshots,
            range: range,
            referenceDate: today,
            calendar: calendar
        )
        let cashFlow = try DashboardCalculations.cashFlow(
            entries: source.ledgerEntries,
            range: range,
            referenceDate: today,
            calendar: calendar
        )
        let changeMetrics = try summary.map {
            try DashboardCalculations.changeMetrics(
                current: $0,
                snapshots: source.completeSnapshots,
                today: today,
                calendar: calendar
            )
        }
        return try DashboardPayload(
            currentSummary: summary,
            goalProjections: DashboardCalculations.goalProjections(
                goals: source.goals,
                currentNetWorthCNY: summary?.netWorthCNY
            ),
            completeSnapshots: source.completeSnapshots,
            history: history,
            changeMetrics: changeMetrics,
            historicalHighCNY: changeMetrics?.historicalHighCNY
                ?? DashboardCalculations.historicalHigh(
                    snapshots: source.completeSnapshots,
                    through: today
                ),
            allocation: try DashboardCalculations.allocation(
                records: source.currentWealthRecords
            ),
            subassets: try summary.map {
                try DashboardCalculations.subassets(
                    records: source.currentWealthRecords,
                    summary: $0
                )
            } ?? [],
            cashFlow: cashFlow,
            netWorthHeatmap: DashboardCalculations.netWorthHeatmap(
                snapshots: source.completeSnapshots,
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
            currentSnapshot: source.completeSnapshots.last { $0.civilDate == today },
            legacyIncompleteCount: source.legacyIncompleteSnapshotCount
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
    private(set) var currentSummary: WealthSummary?
    private(set) var goalProjections: [DashboardGoalProjection] = []
    private(set) var snapshots: [DashboardSnapshot] = []
    private(set) var history: [DashboardHistoryPoint] = []
    private(set) var changeMetrics: DashboardChangeMetrics?
    private(set) var historicalHighCNY: Money?
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

    init(store: WealthStore, clock: any Clock, timeZone: TimeZone = .current) {
        self.service = DashboardDataService(store: store, timeZone: timeZone)
        self.clock = clock
        self.calendar = DashboardDateMath.gregorian(timeZone: timeZone)
    }

    var hasInsufficientHistory: Bool { !history.isEmpty && history.count < 2 }
    var hasCurrentWealth: Bool { currentSummary != nil }

    func loadIfNeeded() async {
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
        guard loadState == .ready, currentSummary != nil else {
            errorMessage = "No current Wealth Container is available, so Aureus will not create a zero-value Snapshot."
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let now = clock.now()
            let today = try DashboardDateMath.civilDate(now.date, calendar: calendar)
            try await service.refresh(today: today, now: now)
            await reload()
        } catch DashboardPersistenceError.emptyWealthStore {
            await reload()
            errorMessage = "No current Wealth Container is available. Existing history remains unchanged."
        } catch {
            errorMessage = "Today’s Snapshot refresh failed atomically. The prior Snapshot remains available."
        }
    }

    private func apply(_ payload: DashboardPayload) {
        currentSummary = payload.currentSummary
        goalProjections = payload.goalProjections
        snapshots = payload.completeSnapshots
        history = payload.history
        changeMetrics = payload.changeMetrics
        historicalHighCNY = payload.historicalHighCNY
        allocation = payload.allocation
        subassets = payload.subassets
        cashFlow = payload.cashFlow
        netWorthHeatmap = payload.netWorthHeatmap
        cashFlowHeatmap = payload.cashFlowHeatmap
        currentSnapshot = payload.currentSnapshot
        legacyIncompleteCount = payload.legacyIncompleteCount
    }

    private func clearForEmptyStore() {
        currentSummary = nil
        goalProjections = []
        snapshots = []
        history = []
        changeMetrics = nil
        historicalHighCNY = nil
        allocation = []
        subassets = []
        cashFlow = []
        netWorthHeatmap = []
        cashFlowHeatmap = []
        currentSnapshot = nil
        legacyIncompleteCount = 0
    }
}
