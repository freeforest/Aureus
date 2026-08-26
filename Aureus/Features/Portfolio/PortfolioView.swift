import Charts
import SwiftUI

struct PortfolioView: View {
    @State private var model: PortfolioFeatureModel
    @State private var newPortfolioName = ""
    @State private var renameText = ""
    @State private var activityKind: PortfolioActivity.Kind = .openingLot
    @State private var activityLinkID: UUID?
    @State private var activityDate = "2026-01-15"
    @State private var quantityText = "10"
    @State private var priceOrCostText = "100"
    @State private var feeText = "0"
    @State private var fxText = "1"
    @State private var splitToText = "2"
    @State private var benchmarkSymbol = ""
    @State private var benchmarkMIC = ""

    init(
        store: WealthStore,
        marketDataService: MarketDataService,
        marketSessionStore: TransientMarketSessionStore,
        preferences: PortfolioPreferencesStore,
        clock: any Clock,
        mode: AppDataMode
    ) {
        _model = State(initialValue: PortfolioFeatureModel(
            store: store, marketDataService: marketDataService,
            marketSessionStore: marketSessionStore, preferences: preferences,
            clock: clock, mode: mode
        ))
    }

    var body: some View {
        @Bindable var bindable = model
        VStack(spacing: 0) {
            header
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("portfolio.error")
            }
            HSplitView {
                master(selection: $bindable.selectedPortfolioID)
                    .frame(minWidth: 230, idealWidth: 270)
                detail
                    .frame(minWidth: 620)
            }
        }
        .navigationTitle("Portfolio")
        .task { await model.start() }
        .onChange(of: model.selectedPortfolioID) { _, id in
            Task { await model.select(id) }
        }
        .alert("Delete Portfolio?", isPresented: Binding(
            get: { model.pendingPortfolioDeletion != nil },
            set: { if !$0 { model.cancelDelete() } }
        )) {
            Button("Cancel", role: .cancel) { model.cancelDelete() }
            Button("Delete Portfolio Records", role: .destructive) { Task { await model.confirmDelete() } }
                .accessibilityIdentifier("portfolio.delete.confirm")
        } message: {
            Text("Only this Portfolio's links, activities, and Portfolio NAV snapshots will be deleted. Wealth, Ledger, Dashboard snapshots, Market Cache, and Credentials remain unchanged.")
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: model.mode == .syntheticDemo ? "testtube.2" : "briefcase")
            Text(model.mode == .syntheticDemo ? "Synthetic Demo Portfolio" : "Local Portfolio Terminal")
                .font(.subheadline.weight(.semibold))
            if model.mode == .syntheticDemo {
                Text("Fictional records only").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Stage 8 Portfolio Implementation Candidate")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18).padding(.vertical, 10).background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("portfolio.page")
    }

    private func master(selection: Binding<UUID?>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Portfolios").font(.headline)
            HStack {
                TextField("Portfolio name", text: $newPortfolioName)
                    .accessibilityIdentifier("portfolio.create.name")
                Button("Add") {
                    let value = newPortfolioName
                    newPortfolioName = ""
                    Task { await model.createPortfolio(name: value) }
                }
                .accessibilityIdentifier("portfolio.create")
            }
            if model.portfolios.isEmpty {
                ContentUnavailableView(
                    "No Portfolios",
                    systemImage: "briefcase",
                    description: Text("Create a local CNY-base Portfolio. Market data is not required.")
                )
                .accessibilityIdentifier("portfolio.empty")
            } else {
                List(model.portfolios, selection: selection) { portfolio in
                    Text(portfolio.name)
                        .tag(portfolio.id)
                        .accessibilityIdentifier("portfolio.row.\(portfolio.id.uuidString)")
                }
                HStack {
                    Button("Move Up") { Task { await model.moveSelected(offset: -1) } }
                        .disabled(model.selectedPortfolioID == model.portfolios.first?.id)
                        .accessibilityIdentifier("portfolio.move.up")
                    Button("Move Down") { Task { await model.moveSelected(offset: 1) } }
                        .disabled(model.selectedPortfolioID == model.portfolios.last?.id)
                        .accessibilityIdentifier("portfolio.move.down")
                }
                TextField("Rename selected", text: $renameText)
                    .accessibilityIdentifier("portfolio.rename.name")
                HStack {
                    Button("Rename") { Task { await model.renameSelected(renameText) } }
                        .accessibilityIdentifier("portfolio.rename")
                    Button("Delete", role: .destructive) { model.requestDeleteSelected() }
                        .accessibilityIdentifier("portfolio.delete")
                }
            }
        }
        .padding(14)
    }

    @ViewBuilder private var detail: some View {
        if let portfolio = model.selectedPortfolio {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    portfolioSummary(portfolio)
                    securityLinkSection
                    activitySection
                    holdingsSection
                    visualizationSection
                    benchmarkSection
                    Text(model.providerPolicyDisclosure).font(.caption).foregroundStyle(.secondary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(model.providerPolicyDisclosure)
                        .accessibilityIdentifier("portfolio.disclosure")
                }
                .padding(18)
            }
        } else {
            ContentUnavailableView("Select a Portfolio", systemImage: "briefcase")
                .accessibilityIdentifier("portfolio.noSelection")
        }
    }

    private func portfolioSummary(_ portfolio: PortfolioRecord) -> some View {
        HStack(spacing: 12) {
            summaryCard("Portfolio", portfolio.name, "portfolio.summary.name")
            summaryCard("Base Currency", portfolio.baseCurrency.rawValue, "portfolio.summary.currency")
            summaryCard("CNY NAV", money(model.totalNAV), "portfolio.summary.nav")
            summaryCard("Holdings", "\(model.holdings.count)", "portfolio.summary.holdings")
        }
    }

    private func summaryCard(_ title: String, _ value: String, _ identifier: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine).accessibilityIdentifier(identifier)
    }

    private var securityLinkSection: some View {
        GroupBox("Wealth Security Links") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stock, ETF, and Fund identity is linked by Wealth UUID + normalized ticker + raw MIC. Raw MIC is never rewritten.")
                    .font(.caption).foregroundStyle(.secondary)
                Menu("Link Wealth Security") {
                    ForEach(model.eligibleWealth.filter { wealth in
                        !model.securityLinks.contains { $0.wealthContainerID == wealth.id }
                    }) { wealth in
                        Button(wealth.container.name) { Task { await model.linkWealthContainer(wealth.id) } }
                    }
                }
                .accessibilityIdentifier("portfolio.security.link")
                ForEach(model.securityLinks) { link in
                    Text("\(link.symbol) · raw MIC \(link.rawMIC) · \(link.currency.rawValue) · \(link.assetKind.title)")
                        .accessibilityIdentifier("portfolio.security.\(link.stableIdentity)")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var activitySection: some View {
        GroupBox("Activity History — FIFO") {
            VStack(alignment: .leading, spacing: 8) {
                if !model.securityLinks.isEmpty {
                    Picker("Security", selection: Binding(
                        get: { activityLinkID ?? model.securityLinks.first?.id },
                        set: { activityLinkID = $0 }
                    )) {
                        ForEach(model.securityLinks) { Text("\($0.symbol)/\($0.rawMIC)").tag(Optional($0.id)) }
                    }.accessibilityIdentifier("portfolio.activity.security")
                    Picker("Kind", selection: $activityKind) {
                        ForEach(PortfolioActivity.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.accessibilityIdentifier("portfolio.activity.kind")
                    HStack {
                        TextField("YYYY-MM-DD", text: $activityDate).accessibilityIdentifier("portfolio.activity.date")
                        TextField("Quantity", text: $quantityText).accessibilityIdentifier("portfolio.activity.quantity")
                        TextField(activityKind == .openingLot ? "Total Cost" : "Unit Price", text: $priceOrCostText)
                            .accessibilityIdentifier("portfolio.activity.priceOrCost")
                        if activityKind == .buy || activityKind == .sell {
                            TextField("Fee", text: $feeText).accessibilityIdentifier("portfolio.activity.fee")
                        }
                        if activityKind == .manualSplit {
                            TextField("To ratio", text: $splitToText).accessibilityIdentifier("portfolio.activity.splitTo")
                        } else {
                            TextField("FX to CNY", text: $fxText).accessibilityIdentifier("portfolio.activity.fx")
                        }
                        Button("Add Activity") { addActivity() }.accessibilityIdentifier("portfolio.activity.add")
                    }
                }
                if model.activities.isEmpty { Text("No Portfolio activities").foregroundStyle(.secondary) }
                ForEach(model.activities) { activity in
                    HStack {
                        Text("\(activity.civilDate) · \(activity.kind.rawValue) · Manual local record")
                        Spacer()
                        Button("Delete", role: .destructive) { Task { await model.deleteActivity(activity.id) } }
                            .accessibilityIdentifier("portfolio.activity.delete.\(activity.id.uuidString)")
                    }
                    .accessibilityElement(children: .contain)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var holdingsSection: some View {
        GroupBox("Holdings and Reconciliation") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Manual Wealth Mark · Portfolio-derived quantity · no live price")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.holdings, id: \.id) { holding in
                    Grid(alignment: .leading, horizontalSpacing: 16) {
                        GridRow {
                            Text("\(holding.link.symbol)/\(holding.link.rawMIC)").font(.headline)
                            Text(holding.reconciliation == .matched ? "Reconciled" : "Quantity Mismatch")
                                .foregroundStyle(holding.reconciliation == .matched ? Color.secondary : Color.orange)
                            Text("Portfolio \(holding.portfolioQuantity.decimal)")
                            Text("Wealth \(holding.wealthQuantity.decimal)")
                        }
                        GridRow {
                            Text("Manual Wealth Mark \(money(holding.marketValue))")
                            Text("Value CNY \(money(holding.marketValueCNY))")
                            Text("Basis CNY \(money(holding.remainingCNYBasis))")
                            Text("Unrealized CNY \(money(holding.unrealizedCNYPnL))")
                        }
                        GridRow {
                            Text("Realized CNY \(money(holding.realizedCNYPnL))")
                            Text("Weight \(holding.weight.map { "\($0.decimal * 100)%" } ?? "Unavailable")")
                            Text("Average cost \((try? holding.averageRemainingCost()).flatMap { $0 }.map { NSDecimalNumber(decimal: $0.decimal).stringValue } ?? "Unavailable")")
                            Text("P&L % \((try? holding.unrealizedPercentage()).flatMap { $0 }.map { "\($0.decimal * 100)%" } ?? "Unavailable")")
                        }
                        GridRow {
                            Text("FX \(holding.wealthFX.source) @ \(holding.wealthFX.referenceDate)")
                            Text("Wealth updated \(holding.wealthUpdatedDate.description)")
                            Text(holding.wealthFX.isStale ? "Stale manual FX" : "Manual FX provenance")
                            Text("Manual Wealth Mark")
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("portfolio.holding.\(holding.link.stableIdentity)")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var visualizationSection: some View {
        GroupBox("Portfolio Visualizations") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Snapshot date YYYY-MM-DD", text: $activityDate)
                    Button("Capture Complete NAV Snapshot") {
                        if let date = try? CivilDate(canonical: activityDate) { Task { await model.captureNAV(on: date) } }
                    }.accessibilityIdentifier("portfolio.snapshot.capture")
                }
                Chart(model.snapshots) { snapshot in
                    LineMark(x: .value("Date", snapshot.civilDate.description), y: .value("CNY NAV", NSDecimalNumber(decimal: snapshot.totalCNY.decimal).doubleValue))
                }.frame(height: 180).accessibilityIdentifier("portfolio.nav.chart")
                HStack {
                    Chart(assetKindAllocation, id: \.label) { item in
                        SectorMark(angle: .value("CNY value", item.value))
                            .foregroundStyle(by: .value("Asset kind", item.label))
                    }
                    .frame(height: 160)
                    .accessibilityLabel("Asset-kind allocation using checked CNY holding values")
                    .accessibilityIdentifier("portfolio.allocation.assetKind")
                    Chart(currencyAllocation, id: \.label) { item in
                        SectorMark(angle: .value("CNY value", item.value))
                            .foregroundStyle(by: .value("Currency", item.label))
                    }
                    .frame(height: 160)
                    .accessibilityLabel("Currency allocation using checked converted CNY holding values")
                    .accessibilityIdentifier("portfolio.allocation.currency")
                }
                HStack(spacing: 8) {
                    ForEach(model.holdings, id: \.id) { holding in
                        VStack {
                            Text("\(holding.link.symbol) \(holding.unrealizedCNYPnL.minorUnits >= 0 ? "+" : "−")")
                            Text(money(holding.unrealizedCNYPnL)).font(.caption)
                        }
                        .padding().frame(maxWidth: .infinity)
                        .background(holding.unrealizedCNYPnL.minorUnits >= 0 ? Color.blue.opacity(0.16) : Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(holding.link.symbol), raw MIC \(holding.link.rawMIC), P and L \(money(holding.unrealizedCNYPnL)); equal area holding tile")
                    }
                }.accessibilityIdentifier("portfolio.pnl.heatmap")
                Text("P&L heatmap uses equal-area holding tiles; area is not market capitalization. Sector and geography: Unavailable.")
                    .font(.caption).foregroundStyle(.secondary)
                Table(model.snapshots) {
                    TableColumn("Date") { Text($0.civilDate.description) }
                    TableColumn("CNY NAV") { Text(money($0.totalCNY)) }
                    TableColumn("Status") { Text($0.isComplete ? "Complete" : "Unavailable") }
                }.frame(height: 160).accessibilityIdentifier("portfolio.nav.table")
            }
        }
    }

    private var benchmarkSection: some View {
        GroupBox("Session Benchmark") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Only symbol, raw MIC, and range persist. Benchmark bars and indexed comparison never persist.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("Symbol", text: $benchmarkSymbol).accessibilityIdentifier("portfolio.benchmark.symbol")
                    TextField("Raw MIC", text: $benchmarkMIC).accessibilityIdentifier("portfolio.benchmark.mic")
                    Button("Save Identifier Preference") {
                        Task { await model.saveBenchmark(symbol: benchmarkSymbol, rawMIC: benchmarkMIC, range: .oneYear) }
                    }.accessibilityIdentifier("portfolio.benchmark.save")
                    Button("Load Session Benchmark") { model.loadSessionBenchmark() }
                        .accessibilityIdentifier("portfolio.benchmark.load")
                    Button("Clear Session") { Task { await model.clearSessionBenchmark() } }
                        .accessibilityIdentifier("portfolio.benchmark.clear")
                }
                Text("Benchmark state: \(String(describing: model.state))")
                    .accessibilityIdentifier("portfolio.benchmark.state")
                Text(model.benchmarkDisclosure)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(model.benchmarkDisclosure)
                    .accessibilityIdentifier("portfolio.benchmark.disclosure")
                if !model.benchmarkComparison.isEmpty {
                    Text("Indexed comparison — base 100").font(.headline)
                    Chart(model.benchmarkComparison, id: \.date) { point in
                        LineMark(x: .value("Date", point.date.description), y: .value("Portfolio", NSDecimalNumber(decimal: point.portfolioIndex).doubleValue)).foregroundStyle(by: .value("Series", "Portfolio"))
                        LineMark(x: .value("Date", point.date.description), y: .value("Benchmark", NSDecimalNumber(decimal: point.benchmarkIndex).doubleValue)).foregroundStyle(by: .value("Series", "Benchmark"))
                    }.frame(height: 180).accessibilityIdentifier("portfolio.benchmark.chart")
                }
            }
        }
    }

    private func addActivity() {
        guard let link = model.securityLinks.first(where: { $0.id == (activityLinkID ?? model.securityLinks.first?.id) }),
              let date = try? CivilDate(canonical: activityDate),
              let quantityDecimal = Decimal(string: quantityText),
              let quantity = try? AssetQuantity(decimal: quantityDecimal) else { return }
        do {
            let payload: PortfolioActivityPayload
            if activityKind == .manualSplit {
                guard let toDecimal = Decimal(string: splitToText) else { return }
                payload = .manualSplit(from: try Ratio(decimal: 1), to: try Ratio(decimal: toDecimal))
            } else {
                guard let value = Decimal(string: priceOrCostText), let fxValue = Decimal(string: fxText) else { return }
                let rate = link.currency == .cny ? FXRate.cnyIdentity : try FXRate(decimal: fxValue, sourceCurrency: .usd, targetCurrency: .cny)
                if activityKind == .openingLot {
                    let cost = try Money(decimal: value, currency: link.currency)
                    let fx = try PortfolioFXProvenance(original: cost, rate: rate, source: link.currency == .cny ? "identity" : "manual", referenceDate: date, recordedAt: UTCInstant(millisecondsSince1970: 0), isManual: link.currency == .usd, isStale: false)
                    payload = .openingLot(quantity: quantity, totalCost: cost, fx: fx, note: "Manual opening lot")
                } else {
                    guard let feeDecimal = Decimal(string: feeText) else { return }
                    let price = try MarketPrice(decimal: value, quoteCurrency: link.currency)
                    let fee = try Money(decimal: feeDecimal, currency: link.currency)
                    let gross = try PortfolioCheckedMath.moneyProduct(quantity: quantity, price: price)
                    let total = activityKind == .buy ? try gross.adding(fee) : try gross.subtracting(fee)
                    let fx = try PortfolioFXProvenance(original: total, rate: rate, source: link.currency == .cny ? "identity" : "manual", referenceDate: date, recordedAt: UTCInstant(millisecondsSince1970: 0), isManual: link.currency == .usd, isStale: false)
                    payload = activityKind == .buy ? .buy(quantity: quantity, unitPrice: price, fee: fee, fx: fx) : .sell(quantity: quantity, unitPrice: price, fee: fee, fx: fx)
                }
            }
            Task { await model.addActivity(payload, to: link.id, date: date) }
        } catch { }
    }

    private func money(_ value: Money) -> String {
        "\(value.currency.rawValue) \(NSDecimalNumber(decimal: value.decimal).stringValue)"
    }

    private var assetKindAllocation: [(label: String, value: Double)] {
        [AssetContainerKind.stock, .etf, .fund].compactMap { kind in
            let values = model.holdings.filter { $0.link.assetKind == kind }.map(\.marketValueCNY)
            guard !values.isEmpty,
                  let total = try? values.reduce(Money(minorUnits: 0, currency: .cny), { try $0.adding($1) }) else { return nil }
            return (kind.title, NSDecimalNumber(decimal: total.decimal).doubleValue)
        }
    }

    private var currencyAllocation: [(label: String, value: Double)] {
        CurrencyCode.allCases.compactMap { currency in
            let values = model.holdings.filter { $0.link.currency == currency }.map(\.marketValueCNY)
            guard !values.isEmpty,
                  let total = try? values.reduce(Money(minorUnits: 0, currency: .cny), { try $0.adding($1) }) else { return nil }
            return (currency.rawValue, NSDecimalNumber(decimal: total.decimal).doubleValue)
        }
    }
}
