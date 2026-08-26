import SwiftUI

struct MarketsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @State private var model: MarketsFeatureModel

    init(
        marketDataService: MarketDataService,
        marketProvider: any MarketDataProvider,
        sessionStore: TransientMarketSessionStore,
        preferences: MarketPreferencesStore,
        clock: any Clock,
        mode: AppDataMode
    ) {
        _model = State(initialValue: MarketsFeatureModel(
            marketDataService: marketDataService,
            marketProvider: marketProvider,
            sessionStore: sessionStore,
            preferences: preferences,
            clock: clock,
            mode: mode
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            marketsBanner
            HSplitView {
                masterColumn
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 440)
                detailColumn
                    .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await model.start() }
        .onAppear { Task { await model.refreshCapabilities() } }
    }

    private var marketsBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: model.mode == .syntheticDemo ? "testtube.2" : "chart.xyaxis.line")
            Text("Markets Terminal")
                .font(.headline)
                .accessibilityIdentifier("markets.terminal")
            Text(model.mode == .syntheticDemo ? "Synthetic Demo — no live Provider evidence" : "Personal Local Mode — session-only market data")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier(model.mode == .syntheticDemo ? "markets.mode.synthetic" : "markets.mode.production")
            Spacer()
            Text("Stage 7A Markets Terminal Correctness Repair Candidate")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private var masterColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                capabilityOverview
                searchSection
                watchlistSection
                heatmapSection
            }
            .padding(16)
        }
        .accessibilityIdentifier("markets.master.scroll")
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var capabilityOverview: some View {
        GroupBox("Market Overview") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.capabilityCards) { card in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(card.region.rawValue).font(.headline)
                            Spacer()
                            Text(card.status)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(card.region == .us ? .blue : .secondary)
                        }
                        Text(card.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(9)
                    .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("markets.capability.\(capabilityID(card.region))")
                }
                Divider()
                Text(model.historicalAcceptanceRecord)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("markets.capability.historical-record")
                Text(model.currentCapabilityBoundary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("markets.capability.boundary")
                Button("Refresh Current Capability") { Task { await model.refreshCapabilities() } }
                    .accessibilityIdentifier("markets.capability.refresh")
            }
            .padding(.top, 4)
        }
    }

    private var searchSection: some View {
        GroupBox("Symbol Search") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Symbol or company", text: $model.query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.submitSearch() }
                        .accessibilityIdentifier("markets.search.field")
                    Button("Search") { model.submitSearch() }
                        .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("markets.search.submit")
                }
                if model.state == .searching {
                    ProgressView("Searching…")
                        .controlSize(.small)
                        .accessibilityIdentifier("markets.search.progress")
                }
                ForEach(model.searchResults) { instrument in
                    Button {
                        model.select(instrument)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(instrument.symbol).font(.headline)
                                Text("\(instrument.mic) · \(instrument.currency.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Select \(instrument.symbol), raw MIC \(instrument.mic), currency \(instrument.currency.rawValue)")
                    .accessibilityIdentifier("markets.search.result.\(instrument.symbol).\(instrument.mic)")
                }
                Text("Search order is Provider relevance order. Search success does not establish price or action entitlement.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    private var watchlistSection: some View {
        GroupBox("Watchlist — identifiers only") {
            VStack(alignment: .leading, spacing: 8) {
                if model.watchlist.isEmpty {
                    Text("No saved symbol/MIC identifiers")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("markets.watchlist.empty")
                }
                ForEach(Array(model.watchlist.enumerated()), id: \.element.id) { index, identity in
                    HStack {
                        Button("\(identity.symbol) · \(identity.mic)") { model.select(identity) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("markets.watchlist.select.\(identity.symbol).\(identity.mic)")
                        Spacer()
                        Button {
                            Task { await model.moveWatchlist(identity, offset: -1) }
                        } label: { Image(systemName: "arrow.up") }
                        .buttonStyle(.borderless)
                        .disabled(index == model.watchlist.startIndex)
                        .accessibilityLabel("Move \(identity.symbol) \(identity.mic) up")
                        .accessibilityIdentifier("markets.watchlist.move-up.\(identity.symbol).\(identity.mic)")
                        Button {
                            Task { await model.moveWatchlist(identity, offset: 1) }
                        } label: { Image(systemName: "arrow.down") }
                        .buttonStyle(.borderless)
                        .disabled(index == model.watchlist.index(before: model.watchlist.endIndex))
                        .accessibilityLabel("Move \(identity.symbol) \(identity.mic) down")
                        .accessibilityIdentifier("markets.watchlist.move-down.\(identity.symbol).\(identity.mic)")
                        Button {
                            Task { await model.removeFromWatchlist(identity) }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(identity.symbol) \(identity.mic) from Watchlist")
                        .accessibilityIdentifier("markets.watchlist.remove.\(identity.symbol).\(identity.mic)")
                    }
                }
                Button("Add Selected") { Task { await model.addSelectedToWatchlist() } }
                    .disabled(model.selectedInstrument == nil)
                    .accessibilityIdentifier("markets.watchlist.add")
                Text("Only normalized symbol, raw MIC, order, range and UI choices persist. No Provider values are restored.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    private var heatmapSection: some View {
        GroupBox("Session Watchlist Heatmap") {
            VStack(alignment: .leading, spacing: 8) {
                if model.heatmapItems.isEmpty {
                    Text("No Session Market Data")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                        ForEach(model.heatmapItems) { item in
                            Button { model.select(item.identity) } label: {
                                VStack(spacing: 4) {
                                    Text(item.identity.symbol).font(.headline)
                                    Text(item.identity.mic).font(.caption)
                                    Text(heatmapChange(item))
                                        .font(.caption.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity, minHeight: 70)
                                .background(heatmapColor(item).opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(heatmapColor(item), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(item.identity.symbol), raw MIC \(item.identity.mic), \(item.range.rawValue), \(item.category.rawValue)")
                            .accessibilityIdentifier("markets.heatmap.\(item.identity.symbol).\(item.identity.mic)")
                        }
                    }
                }
                Text("Equal-area session tiles; not market-cap weighted and not a complete market representation.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
        .accessibilityIdentifier("markets.heatmap")
    }

    private var detailColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailToolbar
            Divider()
            if let instrument = model.selectedInstrument {
                stockDetail(instrument)
            } else {
                ContentUnavailableView(
                    "No Session Market Data",
                    systemImage: "chart.xyaxis.line",
                    description: Text(model.errorDisclosure ?? "Search or select an instrument to load session-only data. Market Data Unavailable Offline after relaunch.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("markets.detail.empty")
            }
        }
    }

    private var detailToolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                Text("Session Market Data")
                    .font(.headline)
                Text("\(model.sessionStatistics.entryCount) entries · \(model.sessionStatistics.accountedBytes) logical bytes / 64 MiB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("markets.session.stats")
            }
            Spacer()
            Button("Refresh Daily Data") { model.refreshSelectedHistory() }
                .disabled(model.selectedInstrument == nil || model.state == .loadingHistory)
                .accessibilityIdentifier("markets.history.refresh")
            Button("Clear Session") { Task { await model.clearSession() } }
                .accessibilityIdentifier("markets.session.clear")
        }
        .padding(14)
    }

    @ViewBuilder
    private func stockDetail(_ instrument: MarketInstrument) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(instrument.symbol).font(.largeTitle.weight(.semibold))
                        Text("\(instrument.displayName) · raw MIC \(instrument.mic) · \(instrument.currency.rawValue)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(model.historyPage?.bars.last?.freshness.rawValue.capitalized ?? "Unknown Freshness")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.quaternary, in: Capsule())
                        .accessibilityIdentifier("markets.detail.freshness")
                }
                metadataGrid(instrument)
                rangeAndIndicators
                if let disclosure = model.errorDisclosure {
                    Label(disclosure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("markets.error")
                }
                if model.state == .loadingHistory {
                    ProgressView("Loading daily session data…")
                        .accessibilityIdentifier("markets.history.progress")
                }
                Picker("Presentation", selection: Binding(
                    get: { model.showsAccessibleTable },
                    set: { value in Task { await model.setAccessibleTable(value) } }
                )) {
                    Text("Chart")
                        .tag(false)
                        .accessibilityIdentifier("markets.presentation.chart")
                    Text("Accessible Data")
                        .tag(true)
                        .accessibilityIdentifier("markets.presentation.accessible")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("markets.presentation.picker")

                if model.showsAccessibleTable {
                    accessibleDataTable
                } else if let payload = model.chartPayload {
                    MarketChartWebView(payload: payload.withDarkAppearance(colorScheme == .dark), reduceMotion: reduceMotion) { message in
                        model.receiveChartMessage(message)
                    }
                    .frame(minHeight: 420)
                    .accessibilityIdentifier("markets.chart.webview")
                    HStack(spacing: 4) {
                        Text(model.chartStatus)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(model.chartStatus)
                            .accessibilityIdentifier("markets.chart.status")
                        Text("·")
                            .accessibilityHidden(true)
                        Text(model.visibleRangeText)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(model.visibleRangeText)
                            .accessibilityIdentifier("markets.chart.visible-range")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let summary = model.renderSummary {
                        Text(summary.series.map { "\($0.identifier):\($0.type.rawValue):\($0.pane.rawValue):\($0.pointCount)" }.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Chart renderer pane summary")
                            .accessibilityValue(summary.series.map { "\($0.identifier) pane \($0.pane.rawValue)" }.joined(separator: ", "))
                            .accessibilityIdentifier("markets.chart.render-summary")
                    }
                } else {
                    ContentUnavailableView(
                        model.state == .insufficientData ? "Insufficient Data" : "Daily Data Not Loaded",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Choose a range and select Refresh Daily Data. 1D means Latest Daily Bar, not intraday.")
                    )
                    .frame(minHeight: 300)
                    .accessibilityIdentifier("markets.chart.empty")
                }
                accessibleSummary
                Link("Charts by TradingView", destination: URL(string: "https://www.tradingview.com/")!)
                    .font(.caption)
                    .accessibilityIdentifier("markets.chart.attribution")
                Text(model.lastActionDisclosure)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .accessibilityIdentifier("markets.stock.detail")
    }

    private func metadataGrid(_ instrument: MarketInstrument) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            GridRow { Text("Provider").foregroundStyle(.secondary); Text(model.historyPage?.providerIdentifier ?? (model.mode == .syntheticDemo ? "Synthetic Demo" : "Twelve Data")) }
            GridRow { Text("Interval").foregroundStyle(.secondary); Text("1day") }
            GridRow { Text("Adjustment").foregroundStyle(.secondary); Text("all") }
            GridRow { Text("Latest value").foregroundStyle(.secondary); Text(latestCloseText) }
            GridRow { Text("Fetched").foregroundStyle(.secondary); Text(fetchedText) }
            GridRow { Text("Market Cap").foregroundStyle(.secondary); Text("Unavailable") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("markets.detail.metadata")
    }

    private var rangeAndIndicators: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Daily range", selection: Binding(
                get: { model.selectedRange },
                set: { range in Task { await model.updateRange(range) } }
            )) {
                ForEach(MarketRange.allCases) { range in Text(range.rawValue).tag(range) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("markets.range.selector")
            Text(model.selectedRange.dailyDisclosure)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(MarketIndicatorKind.allCases, id: \.self) { kind in
                    Toggle(indicatorTitle(kind), isOn: Binding(
                        get: { model.enabledIndicators.contains(kind) },
                        set: { _ in Task { await model.toggleIndicator(kind) } }
                    ))
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .accessibilityIdentifier("markets.indicator.\(kind.rawValue)")
                }
            }
        }
    }

    private var accessibleSummary: some View {
        GroupBox("Accessible Visible-range Summary") {
            if let summary = model.visibleSummary {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(summary.start.description) through \(summary.end.description)")
                    Text("First close \(format(summary.firstClose)); last close \(format(summary.lastClose))")
                    Text("High \(format(summary.high)); low \(format(summary.low))")
                    Text("Change \(formatSigned(summary.change)); percentage \(summary.changePercentage.map(formatSigned) ?? "Unavailable")")
                    Text("Volume \(summary.totalVolume.map(format) ?? "Unavailable")")
                    Text(latestIndicatorSummary)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("No visible daily range is available.")
            }
        }
        .accessibilityIdentifier("markets.accessibility.summary")
    }

    private var accessibleDataTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accessible Daily Data").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                GridRow {
                    ForEach(["Date", "Open", "High", "Low", "Close", "Volume", "Freshness"], id: \.self) { Text($0).font(.caption.bold()) }
                }
                ForEach(model.visibleBars, id: \.sessionDate) { bar in
                    GridRow {
                        Text(bar.sessionDate.description)
                        Text(format(bar.open.decimal))
                        Text(format(bar.high.decimal))
                        Text(format(bar.low.decimal))
                        Text(format(bar.close.decimal))
                        Text(bar.volume.map { format($0.decimal) } ?? "—")
                        Text(bar.freshness.rawValue)
                    }
                    .font(.caption.monospacedDigit())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(bar.sessionDate.description), open \(format(bar.open.decimal)), high \(format(bar.high.decimal)), low \(format(bar.low.decimal)), close \(format(bar.close.decimal)), volume \(bar.volume.map { format($0.decimal) } ?? "Unavailable"), freshness \(bar.freshness.rawValue), \(indicatorAccessibilityText(for: bar.sessionDate))")
                }
            }
        }
        .accessibilityIdentifier("markets.accessible.table")
    }

    private var latestCloseText: String {
        guard let close = model.historyPage?.bars.last?.close.decimal else { return "Latest Daily Close Unavailable" }
        return "Latest Daily Close \(format(close))"
    }

    private var fetchedText: String {
        guard let instant = model.historyPage?.bars.last?.fetchedAt else { return "Unavailable" }
        return DateFormatter.localizedString(from: instant.date, dateStyle: .medium, timeStyle: .short)
    }

    private var latestIndicatorSummary: String {
        guard let date = model.visibleBars.last?.sessionDate else { return "Enabled indicators unavailable" }
        return indicatorAccessibilityText(for: date)
    }

    private func indicatorAccessibilityText(for date: CivilDate) -> String {
        guard let snapshot = model.indicatorSnapshot else { return "Enabled indicators unavailable" }
        var values: [String] = []
        func value(_ label: String, _ points: [MarketIndicatorPoint]) {
            values.append("\(label) \(points.first { $0.sessionDate == date }.map { format($0.value) } ?? "Unavailable")")
        }
        if model.enabledIndicators.contains(.sma20) { value("SMA 20", snapshot.sma20) }
        if model.enabledIndicators.contains(.sma50) { value("SMA 50", snapshot.sma50) }
        if model.enabledIndicators.contains(.ema12) { value("EMA 12", snapshot.ema12) }
        if model.enabledIndicators.contains(.ema26) { value("EMA 26", snapshot.ema26) }
        if model.enabledIndicators.contains(.rsi14) { value("RSI 14", snapshot.rsi14) }
        if model.enabledIndicators.contains(.macd) {
            let point = snapshot.macd.first { $0.sessionDate == date }
            values.append("MACD \(point.map { format($0.macd) } ?? "Unavailable")")
            values.append("MACD Signal \(point?.signal.map(format) ?? "Unavailable")")
            values.append("MACD Histogram \(point?.histogram.map(format) ?? "Unavailable")")
        }
        if model.enabledIndicators.contains(.bollinger20) {
            let point = snapshot.bollinger20.first { $0.sessionDate == date }
            values.append("Bollinger Middle \(point.map { format($0.middle) } ?? "Unavailable")")
            values.append("Bollinger Upper \(point.map { format($0.upper) } ?? "Unavailable")")
            values.append("Bollinger Lower \(point.map { format($0.lower) } ?? "Unavailable")")
        }
        return values.isEmpty ? "Enabled indicators unavailable" : values.joined(separator: ", ")
    }

    private func capabilityID(_ region: MarketsCapabilityCard.Region) -> String {
        switch region {
        case .us: "us"
        case .hongKong: "hong-kong"
        case .mainlandChina: "mainland-china"
        case .japan: "japan"
        }
    }

    private func indicatorTitle(_ kind: MarketIndicatorKind) -> String {
        switch kind {
        case .sma20: "SMA 20"
        case .sma50: "SMA 50"
        case .ema12: "EMA 12"
        case .ema26: "EMA 26"
        case .rsi14: "RSI 14"
        case .macd: "MACD"
        case .bollinger20: "Bollinger"
        }
    }

    private func heatmapChange(_ item: SessionHeatmapItem) -> String {
        guard let change = item.change else { return "? Unknown" }
        let prefix = change > 0 ? "+" : (change < 0 ? "−" : "=")
        guard let magnitude = try? MarketPresentationArithmetic.magnitude(change) else { return "? Unknown" }
        return "\(prefix) \(format(magnitude)) \(item.category.rawValue)"
    }

    private func heatmapColor(_ item: SessionHeatmapItem) -> Color {
        if differentiateWithoutColor { return item.category == .unknown ? .gray : .blue }
        return switch item.category {
        case .gain: Color.teal
        case .loss: Color.orange
        case .unchanged: Color.blue
        case .unknown: Color.gray
        }
    }

    private func format(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private func formatSigned(_ value: Decimal) -> String {
        value > 0 ? "+\(format(value))" : format(value)
    }
}
