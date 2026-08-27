import Charts
import SwiftUI

struct AnalyticsView: View {
    @State private var model: AnalyticsFeatureModel
    @State private var showsAccessibleData = true

    init(store: WealthStore, mode: AppDataMode) {
        _model = State(initialValue: AnalyticsFeatureModel(store: store, mode: mode))
    }

    var body: some View {
        @Bindable var bindable = model
        VStack(spacing: 0) {
            header
            HSplitView {
                controls(selection: $bindable.selectedPortfolioID)
                    .frame(minWidth: 235, idealWidth: 275)
                detail
                    .frame(minWidth: 660)
            }
        }
        .navigationTitle("Analytics")
        .task { await model.start() }
        .onChange(of: model.selectedPortfolioID) { _, id in model.selectPortfolio(id) }
        .onChange(of: model.selectedRange) { _, range in model.selectRange(range) }
        .onChange(of: model.annualRiskFreePercentText) { _, _ in model.riskFreeInputChanged() }
    }

    private var header: some View {
        HStack {
            Image(systemName: model.mode == .syntheticDemo ? "testtube.2" : "chart.xyaxis.line")
            Text(model.mode == .syntheticDemo ? "Synthetic Demo Analytics" : "Local Portfolio Analytics")
                .font(.subheadline.weight(.semibold))
            if model.mode == .syntheticDemo {
                Text("Deterministic fictional records only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("analytics.mode.synthetic")
            } else {
                Text("Production local records")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("analytics.mode.production")
            }
            Spacer()
            Text("Stage 9 Portfolio Analytics Implementation Candidate")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("analytics.page")
    }

    private func controls(selection: Binding<UUID?>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Portfolio").font(.headline)
            if model.portfolios.isEmpty {
                ContentUnavailableView(
                    "No Portfolios",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Create local Portfolio activities and complete NAV snapshots first.")
                )
                .accessibilityIdentifier("analytics.empty")
            } else {
                List(model.portfolios, selection: selection) { portfolio in
                    Text(portfolio.name)
                        .tag(portfolio.id)
                        .accessibilityIdentifier("analytics.portfolio.\(portfolio.id.uuidString)")
                }
                .frame(minHeight: 110)
            }

            Picker("Range", selection: $model.selectedRange) {
                ForEach(PortfolioAnalyticsRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .accessibilityIdentifier("analytics.range")

            TextField("Annual risk-free rate %", text: $model.annualRiskFreePercentText)
                .accessibilityLabel("Annual risk-free rate percent")
                .accessibilityIdentifier("analytics.risk-free")
            Text("Session input only. Default 0%. It is never persisted.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("User assumption; no Provider rate is requested.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Risk-free rate: User assumption; no Provider rate is requested.")
                .accessibilityIdentifier("analytics.risk-free.disclosure")

            HStack {
                Button("Calculate") { model.calculate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectedPortfolio == nil || model.state == .calculating)
                    .accessibilityIdentifier("analytics.calculate")
                if model.state == .calculating {
                    Button("Cancel") { model.cancelCalculation() }
                        .accessibilityIdentifier("analytics.cancel")
                }
            }

            let statusLabel = "Analytics status: \(AnalyticsDisplay.status(model.state))"
            Text(statusLabel)
                .font(.caption.weight(.semibold))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(statusLabel)
                .accessibilityIdentifier("analytics.status")

            Spacer()
            Text(AnalyticsFeatureModel.localOnlyDisclosure)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(AnalyticsFeatureModel.localOnlyDisclosure)
                .accessibilityIdentifier("analytics.disclosure.local-only")
        }
        .padding(14)
    }

    @ViewBuilder private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error = model.errorDisclosure {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("analytics.error")
                }

                if let report = model.report {
                    reportView(report)
                } else if model.state == .calculating {
                    ProgressView("Calculating checked Decimal analytics…")
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .accessibilityIdentifier("analytics.progress")
                } else {
                    ContentUnavailableView(
                        "Analytics Not Calculated",
                        systemImage: "function",
                        description: Text("Choose a local Portfolio and range, then explicitly Calculate. Opening Analytics never starts a Provider request or an automatic analysis.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .accessibilityIdentifier("analytics.not-calculated")
                }
            }
            .padding(18)
        }
    }

    private func reportView(_ report: PortfolioAnalyticsReport) -> some View {
        let coverageLabel = "Observation coverage: range \(report.coverage.requestedRange.rawValue), \(report.coverage.firstDate) through \(report.coverage.lastDate), \(report.coverage.completeSnapshotsUsed) complete snapshots used, \(report.coverage.incompleteSnapshotsExcluded) incomplete snapshots excluded"
        return VStack(alignment: .leading, spacing: 18) {
            Text(model.selectedPortfolio?.name ?? "Portfolio Analytics")
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("analytics.report.portfolio")
            Text("\(report.coverage.firstDate.description) – \(report.coverage.lastDate.description) · \(report.coverage.completeSnapshotsUsed) complete snapshots · \(report.coverage.incompleteSnapshotsExcluded) incomplete excluded")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: coverageLabel))
                .accessibilityIdentifier("analytics.coverage")

            metrics(report)
            Toggle("Show Accessible Data", isOn: $showsAccessibleData)
                .toggleStyle(.switch)
                .accessibilityIdentifier("analytics.accessible-data.toggle")
            performanceChart(report)
            drawdownChart(report)
            observedReturns(report)
            if showsAccessibleData {
                subperiodTable(report.subperiodReturns)
                xirrCashFlowTable(report.xirrCashFlows)
                cashFlowTable(report)
            }
            calculationEvidence(report)
        }
    }

    private func metrics(_ report: PortfolioAnalyticsReport) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
            metricCard("Cash-flow-adjusted Total Return", AnalyticsDisplay.percent(report.cashFlowAdjustedTotalReturn), "analytics.metric.total-return")
            metricCard("Time-weighted Return", AnalyticsDisplay.percent(report.timeWeightedReturn), "analytics.metric.twr")
            metricCard("CAGR", AnalyticsDisplay.metricPercent(report.cagr), "analytics.metric.cagr")
            metricCard("XIRR", AnalyticsDisplay.metricPercent(report.xirr), "analytics.metric.xirr")
            metricCard("Annualized Volatility", AnalyticsDisplay.metricPercent(report.annualizedVolatility), "analytics.metric.volatility")
            metricCard("Sharpe Ratio", AnalyticsDisplay.metricNumber(report.sharpeRatio), "analytics.metric.sharpe")
            metricCard("Maximum Drawdown", AnalyticsDisplay.percent(-report.maximumDrawdown.magnitude), "analytics.metric.drawdown")
        }
        .accessibilityIdentifier("analytics.metrics")
    }

    private func metricCard(_ title: String, _ value: String, _ identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityIdentifier(identifier)
    }

    private func performanceChart(_ report: PortfolioAnalyticsReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Portfolio Wealth Index — Base 100").font(.headline)
            Chart(AnalyticsDisplay.indexPoints(report.wealthIndex), id: \.date) { point in
                LineMark(
                    x: .value("Civil Date", point.date.description),
                    y: .value("Index", point.value)
                )
                .foregroundStyle(.blue)
            }
            .frame(height: 190)
            .accessibilityHidden(true)
            Text("Native visual summary; authoritative values remain checked Decimal in Swift.")
                .font(.caption).foregroundStyle(.secondary)
            let summary = "TWR index chart summary: range \(report.coverage.requestedRange.rawValue), \(report.coverage.firstDate) through \(report.coverage.lastDate), \(report.wealthIndex.count) observations, analytics calculated"
            Text(summary)
                .font(.caption)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(summary)
                .accessibilityIdentifier("analytics.chart.performance.summary")
            if showsAccessibleData { nativeIndexTable(report.wealthIndex) }
        }
        .accessibilityIdentifier("analytics.chart.performance")
    }

    private func drawdownChart(_ report: PortfolioAnalyticsReport) -> some View {
        let visualSummary = "Peak \(report.maximumDrawdown.peakDate) · trough \(report.maximumDrawdown.troughDate) · recovery \(report.maximumDrawdown.recoveryDate?.description ?? "Not observed")"
        let accessibilitySummary = "Observed snapshot drawdown summary: range \(report.coverage.requestedRange.rawValue), \(report.coverage.firstDate) through \(report.coverage.lastDate), \(report.drawdownSeries.count) observations, peak \(report.maximumDrawdown.peakDate), trough \(report.maximumDrawdown.troughDate), recovery \(report.maximumDrawdown.recoveryDate?.description ?? "not observed")"
        return VStack(alignment: .leading, spacing: 8) {
            Text("Drawdown from Running Peak").font(.headline)
            Chart(AnalyticsDisplay.drawdownPoints(report.drawdownSeries), id: \.date) { point in
                AreaMark(
                    x: .value("Civil Date", point.date.description),
                    y: .value("Drawdown", point.value)
                )
                .foregroundStyle(.orange.opacity(0.55))
            }
            .frame(height: 150)
            .accessibilityHidden(true)
            Text(verbatim: visualSummary)
                .font(.caption)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: accessibilitySummary))
                .accessibilityIdentifier("analytics.drawdown.summary")
            if showsAccessibleData { nativeDrawdownTable(report.drawdownSeries) }
        }
        .accessibilityIdentifier("analytics.chart.drawdown")
    }

    private func observedReturns(_ report: PortfolioAnalyticsReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Observed Period Returns").font(.headline)
            Text(AnalyticsFeatureModel.observedPeriodDisclosure)
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("analytics.observed.disclosure")
            HStack(alignment: .top, spacing: 18) {
                observedMonthlyTable(report.monthlyReturns)
                observedAnnualTable(report.annualReturns)
            }
        }
        .accessibilityIdentifier("analytics.observed.tables")
    }

    private func observedMonthlyTable(_ rows: [ObservedMonthlyTWR]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Monthly").font(.subheadline.weight(.semibold))
            ForEach(rows) { row in
                let label = "\(row.id): \(AnalyticsDisplay.percent(row.returnDecimal)), \(AnalyticsDisplay.coverage(row.coverage)), available"
                Text(label)
                    .font(.caption.monospacedDigit())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
                    .accessibilityIdentifier("analytics.month.\(row.id)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("analytics.monthly.table")
    }

    private func observedAnnualTable(_ rows: [ObservedAnnualTWR]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Annual").font(.subheadline.weight(.semibold))
            ForEach(rows) { row in
                let label = "\(row.year): \(AnalyticsDisplay.percent(row.returnDecimal)), \(AnalyticsDisplay.coverage(row.coverage)), available"
                Text(label)
                    .font(.caption.monospacedDigit())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
                    .accessibilityIdentifier("analytics.year.\(row.year)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("analytics.annual.table")
    }

    private func cashFlowTable(_ report: PortfolioAnalyticsReport) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Capital Flows Used").font(.headline)
            Text("Opening Lots and Buys are contributions; Sells are withdrawals; Manual Splits are zero-flow. XIRR uses the inverse investor sign.")
                .font(.caption).foregroundStyle(.secondary)
            if report.capitalFlows.isEmpty {
                Text("No capital flows inside (start, end].")
            } else {
                ForEach(Array(report.capitalFlows.enumerated()), id: \.element.activityID) { index, flow in
                    let signed = flow.direction == .contribution ? "+" : "−"
                    let label = "\(flow.date): \(flow.direction.rawValue), \(signed)\(WealthDisplay.money(flow.amountCNY))"
                    Text(label)
                        .font(.caption.monospacedDigit())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(label)
                        .accessibilityIdentifier("analytics.cash-flow.\(index)")
                }
            }
        }
        .accessibilityIdentifier("analytics.cash-flow.table")
    }

    private func subperiodTable(_ rows: [AnalyticsSubperiodReturn]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Accessible TWR Subperiod Table").font(.headline)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                let label = "\(row.startDate) to \(row.endDate): Portfolio NAV Snapshot return \(AnalyticsDisplay.percent(row.returnDecimal)), capital flow \(WealthDisplay.money(row.portfolioCashFlow))"
                Text(label)
                    .font(.caption.monospacedDigit())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
                    .accessibilityIdentifier("analytics.subperiod.\(index)")
            }
        }
        .accessibilityIdentifier("analytics.subperiod.table")
    }

    private func xirrCashFlowTable(_ rows: [AnalyticsXIRRCashFlow]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Accessible XIRR Cash-flow Table").font(.headline)
            Text("Investor perspective: negative is invested capital; positive is returned capital or ending value.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                let direction = row.investorAmountCNY.minorUnits < 0 ? "invested" : "returned"
                let label = "\(row.date): \(direction), \(WealthDisplay.money(row.investorAmountCNY))"
                Text(label)
                    .font(.caption.monospacedDigit())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
                    .accessibilityIdentifier("analytics.xirr-flow.\(index)")
            }
        }
        .accessibilityIdentifier("analytics.xirr-flow.table")
    }

    private func calculationEvidence(_ report: PortfolioAnalyticsReport) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Calculation Evidence").font(.headline)
            Text("CNY P&L: \(WealthDisplay.money(report.cashFlowAdjustedPnL))")
            Text("Starting Portfolio NAV Snapshot: \(WealthDisplay.money(report.startingNAV))")
            Text("Ending Portfolio NAV Snapshot: \(WealthDisplay.money(report.endingNAV))")
            Text("Contributions: \(WealthDisplay.money(report.contributions)) · Withdrawals: \(WealthDisplay.money(report.withdrawals))")
            Text("Flow valuation boundaries: \(report.coverage.flowValuationBoundariesComplete ? "Complete" : "Missing")")
            Text("Daily risk series: \(report.coverage.dailySeriesIsRegular ? "Regular adjacent daily observations" : "Irregular — risk metrics unavailable")")
            Text("No benchmark, Provider value, Market Cache, Credential, or Market session data was read.")
        }
        .font(.caption)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("analytics.evidence")
    }

    private func nativeIndexTable(_ rows: [AnalyticsIndexPoint]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Accessible Wealth Index Table").font(.subheadline.weight(.semibold))
            ForEach(rows, id: \.date) { row in
                let label = "\(row.date): index \(AnalyticsDisplay.number(row.value, digits: 6))"
                Text(label).font(.caption.monospacedDigit())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
            }
        }
        .accessibilityIdentifier("analytics.performance.table")
    }

    private func nativeDrawdownTable(_ rows: [AnalyticsDrawdownPoint]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Accessible Drawdown Table").font(.subheadline.weight(.semibold))
            ForEach(rows, id: \.date) { row in
                let label = "\(row.date): drawdown \(AnalyticsDisplay.percent(row.signedDrawdown))"
                Text(label).font(.caption.monospacedDigit())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
            }
        }
        .accessibilityIdentifier("analytics.drawdown.table")
    }
}

enum AnalyticsDisplay {
    struct ChartPoint {
        let date: CivilDate
        let value: Double
    }

    static func status(_ state: AnalyticsTerminalState) -> String {
        switch state {
        case .idle: "Idle"
        case .ready: "Ready"
        case .calculating: "Calculating"
        case .calculated: "Calculated"
        case .empty: "No Portfolios"
        case .insufficientData: "Insufficient Data"
        case .missingValuationBoundary: "Missing Valuation Boundary"
        case .invalidRiskFreeRate: "Invalid Risk-free Rate"
        case .cancelled: "Cancelled"
        case .arithmeticError: "Arithmetic Error"
        case .unavailable: "Unavailable"
        }
    }

    static func percent(_ value: Decimal) -> String {
        guard let scaled = try? AnalyticsDecimalMath.multiply(value, 100) else { return "Unavailable" }
        return "\(number(scaled, digits: 4))%"
    }

    static func metricPercent(_ metric: AnalyticsMetric<Decimal>) -> String {
        switch metric {
        case let .available(value): percent(value)
        case let .unavailable(error): unavailable(error)
        }
    }

    static func metricNumber(_ metric: AnalyticsMetric<Decimal>) -> String {
        switch metric {
        case let .available(value): number(value, digits: 6)
        case let .unavailable(error): unavailable(error)
        }
    }

    static func number(_ value: Decimal, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "Unavailable"
    }

    static func coverage(_ value: AnalyticsCoverageKind) -> String {
        switch value {
        case .completeCalendarPeriod: "complete observed calendar period"
        case .partialObservedPeriod: "partial observed period"
        }
    }

    static func unavailable(_ error: PortfolioAnalyticsError) -> String {
        switch error {
        case .irregularDailySeries: "Unavailable — irregular daily observations"
        case .insufficientRiskObservations: "Unavailable — insufficient observations"
        case .zeroVolatility: "Unavailable — zero volatility"
        case .nonConventionalCashFlows: "Unavailable — non-conventional cash flows"
        case .noXIRRRoot: "Unavailable — no unique XIRR root"
        case .multipleXIRRRoots: "Unavailable — multiple XIRR roots"
        default: "Unavailable"
        }
    }

    static func indexPoints(_ values: [AnalyticsIndexPoint]) -> [ChartPoint] {
        values.compactMap { value in finiteDouble(value.value).map { ChartPoint(date: value.date, value: $0) } }
    }

    static func drawdownPoints(_ values: [AnalyticsDrawdownPoint]) -> [ChartPoint] {
        values.compactMap { value in finiteDouble(value.signedDrawdown).map { ChartPoint(date: value.date, value: $0) } }
    }

    private static func finiteDouble(_ value: Decimal) -> Double? {
        let converted = NSDecimalNumber(decimal: value).doubleValue
        return converted.isFinite ? converted : nil
    }
}
