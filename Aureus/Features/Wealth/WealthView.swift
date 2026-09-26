import SwiftUI

struct WealthView: View {
    @State private var model: WealthFeatureModel
    let mode: AppDataMode

    init(store: WealthStore, clock: any Clock, mode: AppDataMode,
         generalPreferences: GeneralPreferencesStore = GeneralPreferencesStore()) {
        _model = State(initialValue: WealthFeatureModel(store: store, clock: clock, generalPreferences: generalPreferences))
        self.mode = mode
    }

    var body: some View {
        @Bindable var bindable = model

        VStack(spacing: 0) {
            WealthModeHeader(mode: mode, pageAccessibilityLabel: pageAccessibilityLabel)
            if let message = model.persistenceErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.08))
                    .accessibilityIdentifier("wealth.persistenceError")
            }
            if let message = model.deletionProtectionMessage {
                Label(message, systemImage: "lock.shield.fill")
                    .foregroundStyle(.orange)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.08))
                    .accessibilityIdentifier("wealth.delete.protected")
            }
            WealthSummaryView(summary: model.summary, grouping: model.generalPreferences.snapshot.groupWealthAmounts)
            Divider()
            wealthContent(selection: $bindable.selection)
        }
        .navigationTitle("Wealth")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.beginAdd()
                } label: {
                    Label("Add Container", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityIdentifier("wealth.add")

                Button {
                    Task { await model.beginEdit() }
                } label: {
                    Label("Edit Container", systemImage: "pencil")
                }
                .disabled(model.selectedRecord == nil)
                .accessibilityIdentifier("wealth.edit")

                Button {
                    if let id = model.selectedRecord?.id {
                        Task { await model.showCorrectionHistory(id: id) }
                    }
                } label: {
                    Label("Correction History", systemImage: "clock.arrow.circlepath")
                }
                .disabled(model.selectedRecord == nil)
                .accessibilityIdentifier("wealth.history.open")

                Button(role: .destructive) {
                    Task { await model.requestDelete() }
                } label: {
                    Label("Delete Container", systemImage: "trash")
                }
                .disabled(model.selectedRecord == nil)
                .accessibilityIdentifier("wealth.delete")
            }
        }
        .sheet(item: $bindable.editor) { presentation in
            WealthEditorSheet(presentation: presentation, model: model)
                .id(presentation.id)
                .interactiveDismissDisabled(model.isSaving)
        }
        .sheet(isPresented: Binding(
            get: { model.historyTargetID != nil },
            set: { if !$0 { model.closeCorrectionHistory() } }
        )) {
            WealthCorrectionHistorySheet(model: model)
        }
        .alert(
            "Delete Container?",
            isPresented: Binding(
                get: { model.pendingDeletion != nil },
                set: { if !$0 { model.pendingDeletion = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                model.pendingDeletion = nil
            }
            if let confirmation = model.pendingDeletion {
                Button("Delete", role: .destructive) {
                    Task { await model.confirmDelete(confirmation) }
                }
                .accessibilityIdentifier("wealth.delete.confirm")
            }
        } message: {
            if let pending = model.pendingDeletion {
                Text(
                    "Delete \"\(pending.record.container.name)\" and "
                    + "\(pending.impact.wealthRecordCount) Stage 3 Wealth Record? "
                    + "Market Cache is not affected."
                )
            }
        }
        .task {
            await model.loadIfNeeded()
        }
    }

    private var pageAccessibilityLabel: String {
        var parts = [
            mode == .syntheticDemo ? "Synthetic Demo Wealth" : "Local Wealth Store",
            "Total Assets, \(WealthDisplay.money(model.summary.totalAssetsCNY, grouping: model.generalPreferences.snapshot.groupWealthAmounts))",
            "Total Liabilities, \(WealthDisplay.money(model.summary.totalLiabilitiesCNY, grouping: model.generalPreferences.snapshot.groupWealthAmounts))",
            "Net Worth, \(WealthDisplay.money(model.summary.netWorthCNY, grouping: model.generalPreferences.snapshot.groupWealthAmounts))"
        ]
        switch model.loadState {
        case .loading:
            parts.append("Loading Wealth")
        case .failed:
            parts.append("Wealth unavailable")
        case .ready where model.records.isEmpty:
            parts.append("No Asset Containers")
        case .ready:
            parts.append(contentsOf: model.records.map(\.container.name))
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func wealthContent(selection: Binding<UUID?>) -> some View {
        switch model.loadState {
        case .loading:
            ProgressView("Loading Wealth…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("wealth.loading")
        case .failed:
            ContentUnavailableView(
                "Wealth unavailable",
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text("The permanent store could not be read. No replacement database was created by this screen.")
            )
            .accessibilityIdentifier("wealth.loadFailed")
        case .ready where model.records.isEmpty:
            VStack(spacing: 12) {
                Image(systemName: "building.columns")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("No Asset Containers")
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier("wealth.empty.title")
                Text("Create a Bank / Cash, security, insurance, other asset, or liability Container. New local stores start empty.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Add Container") { model.beginAdd() }
                    .accessibilityIdentifier("wealth.empty.add")
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            List(model.records, selection: selection) { record in
                WealthContainerRow(record: record, grouping: model.generalPreferences.snapshot.groupWealthAmounts)
                    .tag(record.id)
            }
            .listStyle(.inset)
        }
    }
}

private struct WealthModeHeader: View {
    let mode: AppDataMode
    let pageAccessibilityLabel: String

    var body: some View {
        HStack {
            Image(systemName: mode == .syntheticDemo ? "testtube.2" : "externaldrive")
            Text(mode == .syntheticDemo ? "Synthetic Demo Wealth" : "Local Wealth Store")
                .font(.subheadline.weight(.semibold))
            if mode == .syntheticDemo {
                Text("Fictional records only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Stage 3 Implementation Candidate")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(pageAccessibilityLabel)
        .accessibilityIdentifier("wealth.page")
    }
}

private struct WealthSummaryView: View {
    let summary: WealthSummary
    let grouping: Bool

    var body: some View {
        HStack(spacing: 14) {
            summaryCard(
                title: "Total Assets",
                value: summary.totalAssetsCNY,
                identifier: "wealth.summary.assets",
                color: .blue
            )
            summaryCard(
                title: "Total Liabilities",
                value: summary.totalLiabilitiesCNY,
                identifier: "wealth.summary.liabilities",
                color: .orange
            )
            summaryCard(
                title: "Net Worth",
                value: summary.netWorthCNY,
                identifier: "wealth.summary.netWorth",
                color: .green
            )
        }
        .padding(18)
    }

    private func summaryCard(
        title: String,
        value: Money,
        identifier: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(WealthDisplay.money(value, grouping: grouping))
                .font(.title2.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(WealthDisplay.money(value, grouping: grouping))")
        .accessibilityIdentifier(identifier)
    }
}

private struct WealthContainerRow: View {
    let record: WealthContainer
    let grouping: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(record.isLiability ? .orange : .blue)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(record.container.name)
                        .font(.headline)
                    Text(record.container.kind.title)
                        .font(.caption)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    if record.container.kind.isManualSecurity {
                        Text("Manual Valuation")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.blue)
                            .accessibilityIdentifier("wealth.manualValuation.\(record.id.uuidString)")
                    }
                }
                if let institution = record.container.institution {
                    Text(institution)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if record.container.primaryCurrency == .usd {
                    HStack(spacing: 4) {
                        Text("Manual FX")
                        Text(WealthDisplay.rate(record.valuation.rate))
                        Text("· \(record.valuation.referenceDate.description)")
                        if record.valuation.isStale { Text("· Stale") }
                    }
                    .font(.caption)
                    .foregroundStyle(record.valuation.isStale ? .orange : .secondary)
                }
            }
            Spacer(minLength: 20)
            VStack(alignment: .trailing, spacing: 4) {
                Text(WealthDisplay.money(record.originalValue, grouping: grouping))
                    .font(.body.monospacedDigit())
                Text("CNY \(WealthDisplay.amount(record.convertedCNYValue.decimal, grouping: grouping))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(record.container.name), \(record.container.kind.title)"
            + (record.container.kind.isManualSecurity ? ", Manual Valuation" : "")
            + ", original \(WealthDisplay.money(record.originalValue, grouping: grouping))"
            + ", converted CNY \(WealthDisplay.amount(record.convertedCNYValue.decimal, grouping: grouping))"
        )
        .accessibilityIdentifier(
            "wealth.row.\(record.container.kind.rawValue)."
                + record.container.primaryCurrency.rawValue.lowercased()
        )
    }

    private var icon: String {
        switch record.container.kind {
        case .bankCash: "banknote"
        case .stock: "chart.line.uptrend.xyaxis"
        case .etf: "square.stack.3d.up"
        case .fund: "chart.pie"
        case .insurance: "shield"
        case .otherAsset: "shippingbox"
        case .liability: "creditcard"
        }
    }
}

private struct WealthEditorSheet: View {
    let presentation: WealthEditorPresentation
    @Bindable var model: WealthFeatureModel
    @State private var draft: WealthEditorDraft

    init(presentation: WealthEditorPresentation, model: WealthFeatureModel) {
        self.presentation = presentation
        self.model = model
        _draft = State(
            initialValue: presentation.initialDraft
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(presentation.targetID == nil ? "Add Asset Container" : "Edit Asset Container")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("CNY / USD · Local only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            if presentation.targetID != nil && model.editLoadState != .ready {
                VStack(spacing: 16) {
                    if model.editLoadState == .loading {
                        ProgressView("Loading current Container and edit token…")
                            .accessibilityIdentifier("wealth.form.loading")
                    } else {
                        Text(model.editFeedback ?? "This Container cannot be edited now.")
                            .accessibilityIdentifier("wealth.form.loadFailed")
                        Button("Discard Draft and Reload") { Task { await model.reloadEdit() } }
                            .accessibilityIdentifier("wealth.form.reload")
                    }
                    Button("Cancel") { model.cancelEditor() }
                        .accessibilityIdentifier("wealth.form.cancel")
                }
                .frame(minWidth: 620, minHeight: 520)
            } else {
            Form {
                if presentation.targetID != nil {
                    Section("Edit intent") {
                        Picker("Operation", selection: $model.editIntent) {
                            Text("Correct existing record").tag(WealthEditIntent.correction)
                            Text("Record new current valuation").tag(WealthEditIntent.currentValuation)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("wealth.form.intent")
                        if model.editIntent == .correction && model.needsCorrectionReason(draft) {
                            TextField("Correction reason", text: $model.correctionReason, axis: .vertical)
                                .lineLimit(2...4)
                                .accessibilityIdentifier("wealth.form.correctionReason")
                        }
                        if model.editIntent == .currentValuation {
                            Text("Only the current value/price and explicitly changed FX inputs can be updated. No correction history is created.")
                                .font(.caption)
                        }
                    }
                }
                Section("Container") {
                    TextField("Name", text: $draft.name)
                        .accessibilityIdentifier("wealth.form.name")
                        .disabled(isValuationEdit)
                    Picker("Type", selection: $draft.kind) {
                        ForEach(AssetContainerKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("wealth.form.type")
                    .disabled(isValuationEdit)
                    TextField("Institution (optional)", text: $draft.institution)
                        .accessibilityIdentifier("wealth.form.institution")
                        .disabled(isValuationEdit)
                    Picker("Primary Currency", selection: $draft.currency) {
                        Text("CNY")
                            .tag(CurrencyCode.cny)
                            .accessibilityIdentifier("wealth.form.currency.cny")
                        Text("USD")
                            .tag(CurrencyCode.usd)
                            .accessibilityIdentifier("wealth.form.currency.usd")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("wealth.form.currency")
                    .disabled(isValuationEdit)
                    TextField("Notes (optional)", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("wealth.form.notes")
                        .disabled(isValuationEdit)
                }

                valuationSection

                if draft.currency == .usd {
                    Section("Manual USD → CNY FX") {
                        Text("A positive CNY-per-1-USD rate is required. No network rate is used.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("CNY per 1 USD", text: $draft.fxRate)
                            .accessibilityIdentifier("wealth.form.fx.rate")
                        TextField("Reference Date (YYYY-MM-DD)", text: $draft.fxReferenceDate)
                            .accessibilityIdentifier("wealth.form.fx.date")
                        Toggle("Mark rate as stale", isOn: $draft.fxIsStale)
                            .accessibilityIdentifier("wealth.form.fx.stale")
                    }
                }

                if let message = model.editorErrorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("wealth.form.error")
                    }
                }
                if let message = model.editFeedback {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("wealth.form.feedback")
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 620, minHeight: 520)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    model.cancelEditor()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("wealth.form.cancel")
                .disabled(model.isSaving)
                if model.requiresEditReload {
                    Button("Discard Draft and Reload") { Task { await model.reloadEdit() } }
                        .accessibilityIdentifier("wealth.form.reload")
                        .disabled(model.isSaving)
                }
                Button("Save") {
                    Task { await model.save(draft) }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("wealth.form.save")
                .disabled(!model.canSaveEditor || invalidRequiredReason)
            }
            .padding(16)
            }
        }
    }

    private var isValuationEdit: Bool {
        presentation.targetID != nil && model.editIntent == .currentValuation
    }

    private var invalidRequiredReason: Bool {
        model.needsCorrectionReason(draft)
            && (try? WealthCorrectionEncoding.reason(model.correctionReason)) == nil
    }

    @ViewBuilder
    private var valuationSection: some View {
        switch draft.kind {
        case .bankCash:
            Section("Bank / Cash") {
                TextField("Current Balance", text: $draft.amount)
                    .accessibilityIdentifier("wealth.form.amount")
                TextField("Interest Rate % (optional)", text: $draft.interestRatePercent)
                    .accessibilityIdentifier("wealth.form.interest")
                    .disabled(isValuationEdit)
            }
        case .stock, .etf, .fund:
            Section("Manual Valuation") {
                Label("Manual Valuation — no live or Provider price", systemImage: "hand.raised")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .accessibilityIdentifier("wealth.form.manualValuation")
                TextField("Ticker / Code", text: $draft.ticker)
                    .accessibilityIdentifier("wealth.form.ticker")
                    .disabled(isValuationEdit)
                TextField("MIC (optional)", text: $draft.mic)
                    .accessibilityIdentifier("wealth.form.mic")
                    .disabled(isValuationEdit)
                TextField("Quantity", text: $draft.quantity)
                    .accessibilityIdentifier("wealth.form.quantity")
                    .disabled(isValuationEdit)
                TextField("Manual Current Price", text: $draft.manualPrice)
                    .accessibilityIdentifier("wealth.form.price")
            }
        case .insurance:
            Section("Insurance") {
                TextField("Insurance Company", text: $draft.insuranceCompany)
                    .accessibilityIdentifier("wealth.form.insurance.company")
                    .disabled(isValuationEdit)
                TextField("Product Name", text: $draft.insuranceProductName)
                    .accessibilityIdentifier("wealth.form.insurance.product")
                    .disabled(isValuationEdit)
                TextField("Premium", text: $draft.premium)
                    .accessibilityIdentifier("wealth.form.insurance.premium")
                    .disabled(isValuationEdit)
                Picker("Payment Frequency", selection: $draft.paymentFrequency) {
                    ForEach(InsurancePaymentFrequency.allCases, id: \.self) { frequency in
                        Text(frequency.title).tag(frequency)
                    }
                }
                .accessibilityIdentifier("wealth.form.insurance.frequency")
                .disabled(isValuationEdit)
                TextField("Coverage", text: $draft.coverage)
                    .accessibilityIdentifier("wealth.form.insurance.coverage")
                    .disabled(isValuationEdit)
                TextField("Current Cash Value", text: $draft.amount)
                    .accessibilityIdentifier("wealth.form.amount")
                TextField("Start Date (YYYY-MM-DD)", text: $draft.startDate)
                    .accessibilityIdentifier("wealth.form.insurance.start")
                    .disabled(isValuationEdit)
                TextField("Maturity Date (optional)", text: $draft.maturityDate)
                    .accessibilityIdentifier("wealth.form.insurance.maturity")
                    .disabled(isValuationEdit)
            }
        case .otherAsset:
            Section("Other Asset") {
                TextField("Category / Description", text: $draft.categoryDescription)
                    .accessibilityIdentifier("wealth.form.category")
                    .disabled(isValuationEdit)
                TextField("Current Value", text: $draft.amount)
                    .accessibilityIdentifier("wealth.form.amount")
            }
        case .liability:
            Section("Liability") {
                Text("Enter a positive outstanding balance. It is deducted once in Net Worth.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Outstanding Balance", text: $draft.amount)
                    .accessibilityIdentifier("wealth.form.amount")
                TextField("Interest Rate % (optional)", text: $draft.interestRatePercent)
                    .accessibilityIdentifier("wealth.form.interest")
                    .disabled(isValuationEdit)
            }
        }
    }
}

private struct WealthCorrectionHistorySheet: View {
    @Bindable var model: WealthFeatureModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Correction History")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Close") { model.closeCorrectionHistory() }
                    .accessibilityIdentifier("wealth.history.close")
            }
            Text("Historical snapshots explain earlier facts. Current Wealth totals use only the live record.")
                .font(.caption)
                .foregroundStyle(.secondary)
            switch model.historyLoadState {
            case .idle, .loading:
                ProgressView("Loading history…")
                    .accessibilityIdentifier("wealth.history.loading")
            case .failed:
                ContentUnavailableView("History unavailable", systemImage: "exclamationmark.triangle")
                    .accessibilityIdentifier("wealth.history.failed")
            case .ready where model.correctionHistory.isEmpty:
                ContentUnavailableView("No corrections", systemImage: "clock")
                    .accessibilityIdentifier("wealth.history.empty")
            case .ready:
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(model.correctionHistory, id: \.id) { row in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Sequence \(row.sequence) · UTC ms \(row.occurredAt.millisecondsSince1970)")
                                    .font(.headline)
                                    .accessibilityIdentifier("wealth.history.\(row.id.uuidString).title")
                                if let reason = row.reason {
                                    Text("Reason: \(reason)")
                                        .accessibilityIdentifier("wealth.history.\(row.id.uuidString).reason")
                                }
                                Text("Before: \(WealthView.historyProjection(row.payload.before))")
                                    .accessibilityIdentifier("wealth.history.\(row.id.uuidString).before")
                                if let after = row.payload.after {
                                    Text("After: \(WealthView.historyProjection(after))")
                                        .accessibilityIdentifier("wealth.history.\(row.id.uuidString).after")
                                } else {
                                    Text("Deletion context · \(row.payload.deletion?.links.count ?? 0) prior document link(s)")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityIdentifier("wealth.history.row.\(row.id.uuidString)")
                        }
                    }
                }
                .accessibilityIdentifier("wealth.history.list")
            }
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 450)
        .accessibilityIdentifier("wealth.history.sheet")
    }
}

extension WealthView {
    static func historyProjection(_ value: WealthCorrectionProjection) -> String {
        let fx = value.valuation
        let detail: String
        switch value.details {
        case let .bankCash(_, interest), let .liability(_, interest):
            detail = "interest \(interest.map { NSDecimalNumber(decimal: $0.decimal).stringValue } ?? "none")"
        case let .security(ticker, mic, quantity, price):
            detail = "ticker \(ticker), MIC \(mic ?? "none"), quantity \(NSDecimalNumber(decimal: quantity.decimal).stringValue), price \(WealthDisplay.number(price.decimal, fractionDigits: 8)) \(price.quoteCurrency.rawValue)"
        case let .insurance(company, product, premium, frequency, coverage, _, start, maturity):
            detail = "company \(company), product \(product), premium \(WealthDisplay.money(premium)), frequency \(frequency.rawValue), coverage \(WealthDisplay.money(coverage)), start \(start), maturity \(maturity?.description ?? "none")"
        case let .otherAsset(description, _):
            detail = "category \(description)"
        }
        return "\(value.kind.title), container \(value.id.uuidString), institution \(value.institution ?? "none"), \(detail); original \(WealthDisplay.money(fx.original)), rate \(WealthDisplay.rate(fx.rate)), CNY \(WealthDisplay.money(fx.convertedCNY)), FX source \(fx.providerIdentifier), reference \(fx.referenceDate), fetched UTC ms \(fx.fetchedAt.millisecondsSince1970), manual \(fx.isManualOverride), stale \(fx.isStale)"
    }
}

enum WealthDisplay {
    static func money(_ money: Money, grouping: Bool, locale: Locale = .current) -> String {
        "\(money.currency.rawValue) \(amount(money.decimal, grouping: grouping, locale: locale))"
    }

    static func amount(_ value: Decimal, grouping: Bool, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouping
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }

    static func money(_ money: Money) -> String {
        "\(money.currency.rawValue) \(number(money.decimal, fractionDigits: 2))"
    }

    static func rate(_ rate: FXRate) -> String {
        "\(rate.sourceCurrency.rawValue)→\(rate.targetCurrency.rawValue) "
            + number(rate.decimal, fractionDigits: 10)
    }

    static func number(_ decimal: Decimal, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSDecimalNumber(decimal: decimal)) ?? "—"
    }
}
