import Charts
import SwiftUI

struct DashboardView: View {
    @State private var model: DashboardFeatureModel
    @State private var selectedSection: DashboardSection = .overview
    let mode: AppDataMode

    init(store: WealthStore, clock: any Clock, mode: AppDataMode) {
        _model = State(initialValue: DashboardFeatureModel(store: store, clock: clock))
        self.mode = mode
    }

    var body: some View {
        @Bindable var bindable = model

        VStack(spacing: 0) {
            DashboardModeHeader(mode: mode, loadState: model.loadState)
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.08))
                    .accessibilityIdentifier("dashboard.error")
            }
            dashboardContent(bindable: bindable)
        }
        .navigationTitle("Dashboard")
        .task { await model.loadIfNeeded() }
    }

    @ViewBuilder
    private func dashboardContent(bindable: DashboardFeatureModel) -> some View {
        switch model.loadState {
        case .loading:
            ProgressView("Loading Dashboard…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("dashboard.loading")
        case .empty:
            ContentUnavailableView(
                "No Wealth Data",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("Add a Wealth Container first. Aureus does not create a fabricated zero-value Snapshot for an empty local store.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("dashboard.empty")
        case .failed:
            ContentUnavailableView(
                "Dashboard unavailable",
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text("Permanent wealth history could not be loaded. Existing data was not replaced.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("dashboard.failed")
        case .ready:
            VStack(spacing: 0) {
                Picker("Dashboard Section", selection: $selectedSection) {
                    ForEach(DashboardSection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .accessibilityIdentifier("dashboard.section")
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            DashboardCurrentSection(
                                summary: model.currentSummary,
                                metrics: model.changeMetrics,
                                historicalHighCNY: model.historicalHighCNY,
                                snapshot: model.currentSnapshot,
                                snapshotCount: model.snapshots.count,
                                legacyCount: model.legacyIncompleteCount,
                                isRefreshing: model.isRefreshing,
                                refresh: { Task { await model.refreshTodaySnapshot() } }
                            )
                            .id(DashboardSection.overview)
                            DashboardRangeSelector(
                                selection: Binding(
                                    get: { model.selectedRange },
                                    set: { range in Task { await model.selectRange(range) } }
                                )
                            )
                            .id(DashboardSection.history)
                            DashboardNetWorthChart(
                                points: model.history,
                                selectedDate: Binding(
                                    get: { model.selectedHistoryDate },
                                    set: { model.selectedHistoryDate = $0 }
                                )
                            )
                            if model.hasInsufficientHistory {
                                Label("Not enough history for a change trend. The single persisted Snapshot remains visible.", systemImage: "clock.badge.questionmark")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("dashboard.insufficientHistory")
                            }
                            DashboardAllocationView(slices: model.allocation)
                                .id(DashboardSection.allocation)
                            DashboardSubassetView(values: model.subassets)
                            DashboardCashFlowChart(points: model.cashFlow)
                                .id(DashboardSection.cashFlow)
                            DashboardHeatmapView(
                                title: "Net Worth Change Heatmap",
                                subtitle: "Adjacent complete Snapshot delta; missing dates remain empty.",
                                cells: model.netWorthHeatmap,
                                selection: Binding(
                                    get: { model.selectedNetWorthHeatmapDate },
                                    set: { model.selectedNetWorthHeatmapDate = $0 }
                                ),
                                identifier: "dashboard.heatmap.netWorth"
                            )
                            .id(DashboardSection.heatmaps)
                            VStack(alignment: .leading, spacing: 10) {
                                Picker(
                                    "Cash Flow Heatmap",
                                    selection: Binding(
                                        get: { model.cashFlowHeatmapMode },
                                        set: { mode in Task { await model.selectCashFlowHeatmapMode(mode) } }
                                    )
                                ) {
                                    ForEach(DashboardCashFlowHeatmapMode.allCases) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .accessibilityIdentifier("dashboard.heatmap.cashFlow.mode")
                                DashboardHeatmapView(
                                    title: "Cash Flow Heatmap",
                                    subtitle: "Ordinary Income/Expense or full frozen Net Cash Flow; Transfer is neutral.",
                                    cells: model.cashFlowHeatmap,
                                    selection: Binding(
                                        get: { model.selectedCashFlowHeatmapDate },
                                        set: { model.selectedCashFlowHeatmapDate = $0 }
                                    ),
                                    identifier: "dashboard.heatmap.cashFlow"
                                )
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: 1_300, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: selectedSection) { _, section in
                        proxy.scrollTo(section, anchor: .top)
                    }
                    .accessibilityIdentifier("dashboard.content")
                }
            }
        }
    }
}

private enum DashboardSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case history = "History"
    case allocation = "Allocation"
    case cashFlow = "Cash Flow"
    case heatmaps = "Heatmaps"

    var id: Self { self }
}

private struct DashboardModeHeader: View {
    let mode: AppDataMode
    let loadState: DashboardLoadState

    var body: some View {
        HStack {
            Image(systemName: mode == .syntheticDemo ? "testtube.2" : "rectangle.3.group")
            Text(mode == .syntheticDemo ? "Synthetic Demo Dashboard" : "Local Wealth Dashboard")
                .font(.subheadline.weight(.semibold))
            if mode == .syntheticDemo {
                Text("Persisted fictional history only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Stage 5 Implementation Candidate")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(mode == .syntheticDemo ? "Synthetic Demo Mode" : "Local Data Mode"), Dashboard \(String(describing: loadState))"
        )
        .accessibilityIdentifier(mode == .syntheticDemo ? "mode.demo" : "mode.local")
    }
}

private struct DashboardCurrentSection: View {
    let summary: WealthSummary?
    let metrics: DashboardChangeMetrics?
    let historicalHighCNY: Money?
    let snapshot: DashboardSnapshot?
    let snapshotCount: Int
    let legacyCount: Int
    let isRefreshing: Bool
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Wealth")
                        .font(.title2.weight(.semibold))
                        .accessibilityIdentifier("dashboard.current.title")
                    if let snapshot {
                        Text("Complete Snapshot: \(snapshot.civilDate.description) · \(snapshot.items.count) self-contained items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("dashboard.snapshot.status")
                    } else {
                        Text("No complete Snapshot is available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("dashboard.snapshot.status")
                    }
                    if snapshotCount > 0 {
                        Text("\(snapshotCount) complete persisted Snapshot(s) available")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("dashboard.snapshot.historyCount")
                    }
                    if legacyCount > 0 {
                        Text("\(legacyCount) legacy/incomplete Snapshot row(s) preserved and excluded from Dashboard metrics")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("dashboard.snapshot.legacy")
                    }
                }
                Spacer()
                Button(action: refresh) {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh Today’s Snapshot", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing || summary == nil)
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .accessibilityIdentifier("dashboard.snapshot.refresh")
            }

            if let summary {
                HStack(spacing: 12) {
                    DashboardValueCard(title: "Total Assets", value: summary.totalAssetsCNY, color: .blue, identifier: "dashboard.current.assets")
                    DashboardValueCard(title: "Total Liabilities", value: summary.totalLiabilitiesCNY, color: .orange, identifier: "dashboard.current.liabilities")
                    DashboardValueCard(title: "Net Worth", value: summary.netWorthCNY, color: summary.netWorthCNY.minorUnits < 0 ? .red : .green, identifier: "dashboard.current.netWorth")
                }
            } else {
                Label(
                    "No current Wealth Container. Persisted Snapshot history remains available and no zero-value Snapshot was created.",
                    systemImage: "clock.arrow.circlepath"
                )
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("dashboard.current.empty")
            }

            if let metrics {
                HStack(spacing: 10) {
                    DashboardChangeCard(title: "Today", metric: metrics.today, identifier: "dashboard.change.today")
                    DashboardChangeCard(title: "This Week", metric: metrics.week, identifier: "dashboard.change.week")
                    DashboardChangeCard(title: "This Month", metric: metrics.month, identifier: "dashboard.change.month")
                    DashboardChangeCard(title: "YTD", metric: metrics.yearToDate, identifier: "dashboard.change.ytd")
                    if let historicalHighCNY {
                        DashboardValueCard(title: "Historical High", value: historicalHighCNY, color: .purple, identifier: "dashboard.historicalHigh")
                    }
                }
            } else if let historicalHighCNY {
                HStack(spacing: 10) {
                    Text("Current-period change metrics are unavailable without a current Wealth Container.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("dashboard.change.unavailable")
                    DashboardValueCard(
                        title: "Historical High",
                        value: historicalHighCNY,
                        color: .purple,
                        identifier: "dashboard.historicalHigh"
                    )
                }
            }
        }
        .dashboardPanel()
    }
}

private struct DashboardValueCard: View {
    let title: String
    let value: Money
    let color: Color
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(DashboardDisplay.money(value))
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(DashboardDisplay.money(value))")
        .accessibilityIdentifier(identifier)
    }
}

private struct DashboardChangeCard: View {
    let title: String
    let metric: DashboardChangeMetric
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let absolute = metric.absoluteChangeCNY {
                Text(DashboardDisplay.signedMoney(absolute))
                    .font(.body.monospacedDigit().weight(.semibold))
                Text(metric.percentage.map(DashboardDisplay.percentage) ?? "N/A %")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let date = metric.baselineDate {
                    Text("from \(date.description)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Not enough history")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

private struct DashboardRangeSelector: View {
    @Binding var selection: DashboardTimeRange

    var body: some View {
        Picker("Dashboard Time Range", selection: $selection) {
            ForEach(DashboardTimeRange.allCases) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("dashboard.range")
    }
}

private struct DashboardNetWorthChart: View {
    let points: [DashboardHistoryPoint]
    @Binding var selectedDate: CivilDate?
    @State private var visibleDomain: TimeInterval = 31 * 86_400
    @State private var zoomStart: TimeInterval = 31 * 86_400

    private var chartData: [DashboardChartDatum] {
        DashboardChartDatum.make(points: points)
    }

    private var selectedPoint: DashboardHistoryPoint? {
        guard let selectedDate else { return nil }
        return points.min { lhs, rhs in
            abs(lhs.civilDate.dayOrdinal - selectedDate.dayOrdinal)
                < abs(rhs.civilDate.dayOrdinal - selectedDate.dayOrdinal)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Wealth History").font(.headline)
                Spacer()
                DashboardSeriesLegend()
            }
            if points.isEmpty {
                ContentUnavailableView(
                    "No Snapshot History in Range",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Missing dates are not interpolated or fabricated.")
                )
                .frame(minHeight: 220)
                .accessibilityIdentifier("dashboard.history.empty")
            } else {
                Chart {
                    ForEach(chartData) { datum in
                        LineMark(
                            x: .value("Date", datum.date),
                            y: .value("CNY", datum.value),
                            series: .value("Continuous segment", datum.segmentID)
                        )
                        .foregroundStyle(datum.color)
                        .lineStyle(StrokeStyle(lineWidth: datum.series == .netWorth ? 2.5 : 1.5))
                        PointMark(
                            x: .value("Date", datum.date),
                            y: .value("CNY", datum.value)
                        )
                        .foregroundStyle(datum.color)
                        .symbolSize(points.count == 1 ? 50 : 15)
                    }
                    if let selectedPoint,
                       let date = DashboardDisplay.chartDate(selectedPoint.civilDate) {
                        RuleMark(x: .value("Selected date", date))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                DashboardChartTooltip(point: selectedPoint)
                            }
                    }
                }
                .chartScrollableAxes(points.count > 2 ? .horizontal : [])
                .chartXVisibleDomain(length: visibleDomain)
                .chartXSelection(
                    value: Binding<Date?>(
                        get: { selectedDate.flatMap(DashboardDisplay.chartDate) },
                        set: { date in
                            selectedDate = date.flatMap { DashboardDisplay.civilDate($0) }
                        }
                    )
                )
                .chartYAxisLabel("CNY")
                .frame(minHeight: 280)
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let proposed = zoomStart / Double(value.magnification)
                            visibleDomain = min(max(proposed, 86_400), 5 * 366 * 86_400)
                        }
                        .onEnded { _ in zoomStart = visibleDomain }
                )
                .onAppear { resetVisibleDomain() }
                .onChange(of: points) { _, _ in resetVisibleDomain() }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Interactive persisted Assets, Liabilities, and Net Worth history. Horizontal pan and magnification zoom are enabled when history is sufficient.")
                .accessibilityIdentifier("dashboard.history.chart")

                Text(selectedPoint.map(DashboardDisplay.historySummary) ?? DashboardDisplay.historyFallback(points))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("dashboard.history.accessibleSummary")
            }
        }
        .dashboardPanel()
    }

    private func resetVisibleDomain() {
        let days = max(1, min(points.count > 1 ? points.first!.civilDate.days(to: points.last!.civilDate) + 1 : 1, 366))
        visibleDomain = TimeInterval(days * 86_400)
        zoomStart = visibleDomain
    }
}

private struct DashboardChartTooltip: View {
    let point: DashboardHistoryPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.civilDate.description).font(.caption.weight(.semibold))
            Text("Assets \(DashboardDisplay.money(point.totalAssetsCNY))")
            Text("Liabilities \(DashboardDisplay.money(point.totalLiabilitiesCNY))")
            Text("Net \(DashboardDisplay.money(point.netWorthCNY))")
        }
        .font(.caption2.monospacedDigit())
        .padding(7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct DashboardSeriesLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            legend("Assets", .blue)
            legend("Liabilities", .orange)
            legend("Net Worth", .green)
        }
        .font(.caption)
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
        }
    }
}

private struct DashboardAllocationView: View {
    let slices: [DashboardAllocationSlice]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Current Asset Allocation").font(.headline)
            Text("Positive assets only; liabilities are excluded from the denominator.")
                .font(.caption).foregroundStyle(.secondary)
            if slices.isEmpty {
                Text("No positive asset value is available for allocation.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .accessibilityIdentifier("dashboard.allocation.empty")
            } else {
                HStack(alignment: .center, spacing: 24) {
                    Chart(slices) { slice in
                        SectorMark(
                            angle: .value("Amount", DashboardDisplay.chartValue(slice.amountCNY)),
                            innerRadius: .ratio(0.58),
                            angularInset: 1.5
                        )
                        .foregroundStyle(DashboardDisplay.color(slice.kind))
                    }
                    .frame(width: 220, height: 220)
                    .accessibilityLabel(DashboardDisplay.allocationSummary(slices))
                    .accessibilityIdentifier("dashboard.allocation.chart")

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(slices) { slice in
                            HStack {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(DashboardDisplay.color(slice.kind))
                                    .frame(width: 10, height: 10)
                                Text(slice.kind.title)
                                Spacer()
                                Text(DashboardDisplay.money(slice.amountCNY)).monospacedDigit()
                                Text(DashboardDisplay.percentage(slice.ratio)).monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: 560)
                }
            }
        }
        .dashboardPanel()
    }
}

private struct DashboardSubassetView: View {
    let values: [DashboardSubassetValue]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Container Values").font(.headline)
            let assets = values.filter { !$0.isLiability }
            let liabilities = values.filter(\.isLiability)
            subassetSection("Assets", values: assets, color: .blue, identifier: "dashboard.subassets.assets")
            subassetSection("Liabilities", values: liabilities, color: .orange, identifier: "dashboard.subassets.liabilities")
        }
        .dashboardPanel()
    }

    @ViewBuilder
    private func subassetSection(
        _ title: String,
        values: [DashboardSubassetValue],
        color: Color,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.weight(.semibold))
            if values.isEmpty {
                Text("No \(title.lowercased())").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(values) { value in
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                        GridRow {
                            Text(value.name).lineLimit(1)
                            Text(value.kind.title).font(.caption).foregroundStyle(.secondary)
                            Text(DashboardDisplay.money(value.amountCNY)).monospacedDigit()
                            Text(value.ratioWithinSection.map(DashboardDisplay.percentage) ?? "N/A")
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                        GridRow {
                            ProgressView(value: DashboardDisplay.progress(value.ratioWithinSection))
                                .tint(color)
                                .gridCellColumns(4)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(title), \(value.name), \(value.kind.title), \(DashboardDisplay.money(value.amountCNY)), \(value.ratioWithinSection.map(DashboardDisplay.percentage) ?? "percentage unavailable")")
                }
            }
        }
        .accessibilityIdentifier(identifier)
    }
}

private struct DashboardCashFlowChart: View {
    let points: [DashboardCashFlowPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cash Flow Trend").font(.headline)
            Text("Ordinary Income is Income only; Ordinary Expense is Expense only. Net Cash Flow uses the frozen full Ledger semantics and excludes Transfer.")
                .font(.caption).foregroundStyle(.secondary)
            if points.isEmpty {
                Text("No Ledger cash flow in the selected range.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .accessibilityIdentifier("dashboard.cashFlow.empty")
            } else {
                Chart {
                    ForEach(points) { point in
                        BarMark(
                            x: .value("Date", DashboardDisplay.chartDate(point.civilDate)!),
                            y: .value("CNY", DashboardDisplay.chartValue(point.ordinaryIncomeCNY))
                        )
                        .foregroundStyle(.green)
                        .position(by: .value("Flow", "Ordinary Income"))
                        BarMark(
                            x: .value("Date", DashboardDisplay.chartDate(point.civilDate)!),
                            y: .value("CNY", DashboardDisplay.chartValue(point.ordinaryExpenseCNY))
                        )
                        .foregroundStyle(.red)
                        .position(by: .value("Flow", "Ordinary Expense"))
                        LineMark(
                            x: .value("Date", DashboardDisplay.chartDate(point.civilDate)!),
                            y: .value("CNY", DashboardDisplay.chartValue(point.netCashFlowCNY))
                        )
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                .chartScrollableAxes(points.count > 8 ? .horizontal : [])
                .frame(minHeight: 230)
                .accessibilityLabel(DashboardDisplay.cashFlowSummary(points))
                .accessibilityIdentifier("dashboard.cashFlow.chart")
                Text(DashboardDisplay.cashFlowSummary(points))
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("dashboard.cashFlow.accessibleSummary")
            }
        }
        .dashboardPanel()
    }
}

private struct DashboardHeatmapView: View {
    let title: String
    let subtitle: String
    let cells: [DashboardHeatmapCell]
    @Binding var selection: CivilDate?
    let identifier: String

    private let columns = Array(repeating: GridItem(.fixed(18), spacing: 4), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            if cells.isEmpty {
                Text("No data in this range.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                        ForEach(cells) { cell in
                            DashboardHeatmapCellButton(
                                cell: cell,
                                isSelected: selection == cell.civilDate,
                                identifier: identifier,
                                select: { selection = cell.civilDate }
                            )
                        }
                    }
                }
                .frame(maxHeight: 220)
                HStack(spacing: 12) {
                    heatmapLegend("Negative", .red)
                    heatmapLegend("Zero", .gray)
                    heatmapLegend("Positive", .green)
                    heatmapLegend("Unavailable", .secondary.opacity(0.2))
                    Spacer()
                    Text(selectedCellSummary)
                        .font(.caption.monospacedDigit())
                        .accessibilityIdentifier("\(identifier).selection")
                }
            }
        }
        .dashboardPanel()
        .accessibilityIdentifier(identifier)
    }

    private var selectedCellSummary: String {
        guard let selection,
              let cell = cells.first(where: { $0.civilDate == selection }) else {
            return "Select a date for exact CNY value"
        }
        return DashboardDisplay.heatmapSummary(cell)
    }

    private func heatmapLegend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 11, height: 11)
            Text(title).font(.caption2)
        }
    }
}

private struct DashboardHeatmapCellButton: View {
    let cell: DashboardHeatmapCell
    let isSelected: Bool
    let identifier: String
    let select: () -> Void

    var body: some View {
        let strokeColor: Color = isSelected ? .primary : .clear
        Button(action: select) {
            RoundedRectangle(cornerRadius: 3)
                .fill(DashboardDisplay.heatmapColor(cell.valueCNY))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(strokeColor, lineWidth: 2)
                )
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .help(DashboardDisplay.heatmapSummary(cell))
        .accessibilityLabel(DashboardDisplay.heatmapSummary(cell))
        .accessibilityIdentifier("\(identifier).cell.\(cell.civilDate.description)")
    }
}

private enum DashboardChartSeries: String {
    case assets
    case liabilities
    case netWorth
}

private struct DashboardChartDatum: Identifiable {
    let id: String
    let date: Date
    let value: Double
    let series: DashboardChartSeries
    let segmentID: String

    var color: Color {
        switch series {
        case .assets: .blue
        case .liabilities: .orange
        case .netWorth: .green
        }
    }

    static func make(points: [DashboardHistoryPoint]) -> [DashboardChartDatum] {
        var segment = 0
        var previous: CivilDate?
        var result: [DashboardChartDatum] = []
        for point in points {
            if let previous, previous.days(to: point.civilDate) > 1 { segment += 1 }
            guard let date = DashboardDisplay.chartDate(point.civilDate) else { continue }
            let values: [(DashboardChartSeries, Money)] = [
                (.assets, point.totalAssetsCNY),
                (.liabilities, point.totalLiabilitiesCNY),
                (.netWorth, point.netWorthCNY)
            ]
            for value in values {
                result.append(
                    DashboardChartDatum(
                        id: "\(point.snapshotID.uuidString)-\(value.0.rawValue)",
                        date: date,
                        value: DashboardDisplay.chartValue(value.1),
                        series: value.0,
                        segmentID: "\(value.0.rawValue)-\(segment)"
                    )
                )
            }
            previous = point.civilDate
        }
        return result
    }
}

private extension View {
    func dashboardPanel() -> some View {
        self
            .padding(16)
            .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
    }
}

enum DashboardDisplay {
    private static let utcCalendar = DashboardDateMath.gregorian(timeZone: TimeZone(secondsFromGMT: 0)!)

    static func money(_ money: Money) -> String {
        WealthDisplay.money(money)
    }

    static func signedMoney(_ money: Money) -> String {
        let prefix = money.minorUnits > 0 ? "+" : ""
        return prefix + WealthDisplay.money(money)
    }

    static func percentage(_ ratio: Ratio) -> String {
        let value = ratio.decimal * 100
        let prefix = value > 0 ? "+" : ""
        return prefix + WealthDisplay.number(value, fractionDigits: 2) + "%"
    }

    static func chartValue(_ money: Money) -> Double {
        // Double is a final rendering adapter only. Domain and persistence remain fixed-point/Decimal.
        NSDecimalNumber(decimal: money.decimal).doubleValue
    }

    static func progress(_ ratio: Ratio?) -> Double {
        guard let ratio else { return 0 }
        return min(max(NSDecimalNumber(decimal: ratio.decimal).doubleValue, 0), 1)
    }

    static func chartDate(_ date: CivilDate) -> Date? {
        try? DashboardDateMath.date(date, calendar: utcCalendar)
    }

    static func civilDate(_ date: Date) -> CivilDate? {
        try? DashboardDateMath.civilDate(date, calendar: utcCalendar)
    }

    static func color(_ kind: AssetContainerKind) -> Color {
        switch kind {
        case .bankCash: .blue
        case .stock: .indigo
        case .etf: .cyan
        case .fund: .purple
        case .insurance: .teal
        case .otherAsset: .mint
        case .liability: .orange
        }
    }

    static func heatmapColor(_ money: Money?) -> Color {
        guard let money else { return .secondary.opacity(0.14) }
        if money.minorUnits > 0 { return .green.opacity(0.72) }
        if money.minorUnits < 0 { return .red.opacity(0.72) }
        return .gray.opacity(0.5)
    }

    static func heatmapSummary(_ cell: DashboardHeatmapCell) -> String {
        "\(cell.civilDate.description), \(cell.valueCNY.map(money) ?? "unavailable")"
    }

    static func historySummary(_ point: DashboardHistoryPoint) -> String {
        "\(point.civilDate.description): Assets \(money(point.totalAssetsCNY)); Liabilities \(money(point.totalLiabilitiesCNY)); Net Worth \(money(point.netWorthCNY))"
    }

    static func historyFallback(_ points: [DashboardHistoryPoint]) -> String {
        guard let first = points.first, let last = points.last else { return "No persisted history" }
        return "Persisted history from \(first.civilDate.description) to \(last.civilDate.description), \(points.count) complete point(s); missing dates remain missing."
    }

    static func allocationSummary(_ slices: [DashboardAllocationSlice]) -> String {
        slices.map {
            "\($0.kind.title), \(money($0.amountCNY)), \(percentage($0.ratio))"
        }.joined(separator: "; ")
    }

    static func cashFlowSummary(_ points: [DashboardCashFlowPoint]) -> String {
        guard !points.isEmpty else { return "No Ledger cash flow in range" }
        do {
            let zero = Money(minorUnits: 0, currency: .cny)
            let income = try points.reduce(zero) { try $0.adding($1.ordinaryIncomeCNY) }
            let expense = try points.reduce(zero) { try $0.adding($1.ordinaryExpenseCNY) }
            let net = try points.reduce(zero) { try $0.adding($1.netCashFlowCNY) }
            return "\(points.count) day(s); Ordinary Income \(money(income)); Ordinary Expense \(money(expense)); Net Cash Flow \(money(net))."
        } catch {
            return "Cash flow summary unavailable because the CNY total exceeds the supported fixed-point range."
        }
    }
}

private extension CivilDate {
    var dayOrdinal: Int {
        Int((DashboardDisplay.chartDate(self)?.timeIntervalSince1970 ?? 0) / 86_400)
    }

    func days(to other: CivilDate) -> Int {
        other.dayOrdinal - dayOrdinal
    }
}
