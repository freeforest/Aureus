import SwiftUI
import UniformTypeIdentifiers

struct LedgerView: View {
    @State private var model: LedgerFeatureModel
    @State private var showingImport = false
    @State private var showingExport = false
    @State private var showingTaxonomy = false
    @State private var showingRules = false
    @State private var categoryName = ""
    @State private var tagName = ""
    let mode: AppDataMode

    init(store: WealthStore, clock: any Clock, mode: AppDataMode) {
        _model = State(initialValue: LedgerFeatureModel(store: store, clock: clock))
        self.mode = mode
    }

    var body: some View {
        VStack(spacing: 0) {
            ledgerModeBanner
            if model.entries.isEmpty {
                ContentUnavailableView(
                    "No Ledger Transactions",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Create an income, expense, transfer, or investment cash-flow record. Wealth valuations remain unchanged.")
                )
                .accessibilityIdentifier("ledger.empty")
            } else {
                summaryCards
                filterBar
                transactionTable
            }
        }
        .navigationTitle("Ledger")
        .toolbar {
            ToolbarItemGroup {
                Button { model.beginCreate() } label: { Label("Add Transaction", systemImage: "plus") }
                    .accessibilityIdentifier("ledger.add")
                Button { showingTaxonomy = true } label: { Label("Categories & Tags", systemImage: "tag") }
                    .accessibilityIdentifier("ledger.taxonomy")
                Button { showingRules = true } label: { Label("Classification Rules", systemImage: "list.bullet.clipboard") }
                    .accessibilityIdentifier("ledger.rules")
                Button { showingImport = true } label: { Label("Import CSV", systemImage: "square.and.arrow.down") }
                    .accessibilityIdentifier("ledger.import")
                Button { showingExport = true } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }
                    .disabled(model.entries.isEmpty)
                    .accessibilityIdentifier("ledger.export")
            }
        }
        .task { await model.load() }
        .sheet(isPresented: Binding(get: { model.formMode != nil }, set: { if !$0 { model.formMode = nil } })) {
            LedgerEntryForm(model: model)
        }
        .sheet(isPresented: $showingTaxonomy) {
            taxonomySheet
        }
        .sheet(isPresented: $showingRules) {
            rulesSheet
        }
        .sheet(isPresented: Binding(get: { model.importPreview != nil }, set: { if !$0 { model.importPreview = nil } })) {
            if let preview = model.importPreview { importPreviewSheet(preview) }
        }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.commaSeparatedText, .plainText], allowsMultipleSelection: false) { result in
            Task {
                do {
                    let url = try result.get().first!
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    await model.prepareImport(data: try Data(contentsOf: url))
                } catch { model.errorMessage = "CSV file could not be opened." }
            }
        }
        .fileExporter(
            isPresented: $showingExport,
            document: LedgerCSVDocument(data: model.exportData()),
            contentType: .commaSeparatedText,
            defaultFilename: "Aureus-Ledger-V1"
        ) { result in
            if case .failure = result { model.errorMessage = "CSV export did not complete." }
        }
        .confirmationDialog(
            "Delete this ledger transaction?",
            isPresented: Binding(get: { model.pendingDeletion != nil }, set: { if !$0 { model.pendingDeletion = nil } }),
            presenting: model.pendingDeletion
        ) { entry in
            Button("Delete Transaction", role: .destructive) { Task { await model.delete(entry) } }
                .accessibilityIdentifier("ledger.delete.confirm")
            Button("Cancel", role: .cancel) { model.pendingDeletion = nil }
        } message: { entry in
            Text("Deletes “\(entry.description)” and its Ledger postings/tag links only. Containers, Stage 3 valuations, and Market Cache are not deleted.")
        }
        .alert("Ledger Error", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "Unknown error") }
    }

    private var ledgerModeBanner: some View {
        HStack {
            Image(systemName: mode == .syntheticDemo ? "testtube.2" : "tray")
            Text(mode == .syntheticDemo ? "Synthetic Demo Mode" : "Empty Local Store")
            Spacer()
            Text("Stage 4 Ledger Candidate")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 18).padding(.vertical, 10).background(.bar)
        .accessibilityIdentifier(mode == .syntheticDemo ? "ledger.mode.demo" : "ledger.mode.empty")
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard("Ordinary Inflow", model.summary.ordinaryInflowCNY, "ledger.summary.ordinaryInflow")
            summaryCard("Ordinary Outflow", model.summary.ordinaryOutflowCNY, "ledger.summary.ordinaryOutflow")
            summaryCard("Investment Inflow", model.summary.investmentInflowCNY, "ledger.summary.investmentInflow")
            summaryCard("Investment Outflow", model.summary.investmentOutflowCNY, "ledger.summary.investmentOutflow")
            summaryCard("Net Cash Flow", model.summary.netCashFlowCNY, "ledger.summary.net")
            VStack(alignment: .leading) {
                Text("Transfers").font(.caption).foregroundStyle(.secondary)
                Text("\(model.summary.transferCount)").font(.title3.monospacedDigit())
                Text("Excluded from cash flow").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ledger.summary.transfers")
        }
        .padding(16)
    }

    private func summaryCard(_ title: String, _ money: Money, _ identifier: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Self.money(money)).font(.title3.monospacedDigit())
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine).accessibilityIdentifier(identifier)
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Kind", selection: Binding(get: { model.filter.kind?.rawValue ?? "all" }, set: { model.filter.kind = $0 == "all" ? nil : TransactionKind(rawValue: $0); model.applyFilter() })) {
                    Text("All Kinds").tag("all")
                    ForEach(TransactionKind.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }.frame(width: 150).accessibilityIdentifier("ledger.filter.kind")
                Picker("Category", selection: Binding(get: { model.filter.categoryID?.uuidString ?? "all" }, set: { model.filter.categoryID = UUID(uuidString: $0); model.applyFilter() })) {
                    Text("All Categories").tag("all")
                    ForEach(model.categories) { Text($0.name).tag($0.id.uuidString) }
                }.frame(width: 170).accessibilityIdentifier("ledger.filter.category")
                Picker("Tag", selection: Binding(get: { model.filter.tagID?.uuidString ?? "all" }, set: { model.filter.tagID = UUID(uuidString: $0); model.applyFilter() })) {
                    Text("All Tags").tag("all")
                    ForEach(model.tags) { Text($0.name).tag($0.id.uuidString) }
                }.frame(width: 150).accessibilityIdentifier("ledger.filter.tag")
                Picker("Container", selection: Binding(get: { model.filter.containerID?.uuidString ?? "all" }, set: { model.filter.containerID = UUID(uuidString: $0); model.applyFilter() })) {
                    Text("All Containers").tag("all")
                    ForEach(model.containers) { Text($0.container.name).tag($0.id.uuidString) }
                }.frame(width: 180).accessibilityIdentifier("ledger.filter.container")
                Picker("Currency", selection: Binding(get: { model.filter.currency?.rawValue ?? "all" }, set: { model.filter.currency = $0 == "all" ? nil : CurrencyCode(rawValue: $0); model.applyFilter() })) {
                    Text("All Currencies").tag("all")
                    ForEach(CurrencyCode.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                }.frame(width: 140).accessibilityIdentifier("ledger.filter.currency")
            }
            HStack {
                TextField("Start Date (YYYY-MM-DD)", text: $model.filterStartDateText)
                    .frame(width: 190).accessibilityIdentifier("ledger.filter.startDate")
                TextField("End Date (YYYY-MM-DD)", text: $model.filterEndDateText)
                    .frame(width: 190).accessibilityIdentifier("ledger.filter.endDate")
                Button("Apply Dates") { model.applyFilter() }
                    .accessibilityIdentifier("ledger.filter.applyDates")
                Button("Clear Filters") { model.clearFilters() }
                    .accessibilityIdentifier("ledger.filter.clear")
                if let message = model.filterValidationMessage {
                    Text(message).foregroundStyle(.red).accessibilityIdentifier("ledger.filter.validation")
                }
                Spacer()
            }
        }.padding(.horizontal, 16).padding(.bottom, 8)
    }

    private var transactionTable: some View {
        Group {
            if model.visibleEntries.isEmpty {
                ContentUnavailableView(
                    "No Matching Transactions",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("No Ledger transactions match the current filters.")
                ).accessibilityIdentifier("ledger.filter.empty")
            } else {
                List(model.visibleEntries) { entry in
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.description).font(.headline)
                    Text("\(entry.civilDate.description) · \(entry.kind.title)" + (entry.category.map { " · \($0.name)" } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                    if !entry.tags.isEmpty { Text(entry.tags.map(\.name).joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer()
                if entry.kind == .transfer {
                    Text("Internal Transfer").foregroundStyle(.secondary)
                } else if let posting = entry.primaryPosting {
                    Text(Self.money(posting.valuation.original))
                    Text("→ \(Self.money(posting.valuation.convertedCNY))").foregroundStyle(.secondary)
                }
                Button("Edit") { model.beginEdit(entry) }
                    .accessibilityIdentifier("ledger.edit.\(entry.id.uuidString)")
                    .accessibilityLabel("Edit \(entry.kind.title) transaction")
                Button("Delete", role: .destructive) { model.pendingDeletion = entry }
                    .accessibilityIdentifier("ledger.delete.\(entry.id.uuidString)")
                    .accessibilityLabel("Delete \(entry.kind.title) transaction")
            }
            .accessibilityIdentifier("ledger.row.\(entry.id.uuidString)")
                }
                .accessibilityIdentifier("ledger.history")
            }
        }
    }

    private var rulesSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Deterministic Classification Rules").font(.title2)
                Spacer()
                Button("New Rule") { model.beginCreateRule() }
                    .accessibilityIdentifier("ledger.rule.add")
            }
            Text("Rules apply only to CSV Import Preview. Lower priority numbers run first.")
                .foregroundStyle(.secondary)
            List(model.rules) { rule in
                HStack {
                    VStack(alignment: .leading) {
                        Text(rule.name).font(.headline)
                        Text("Priority \(rule.priority) · \(rule.matchMode.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Enabled", isOn: Binding(
                        get: { rule.isEnabled },
                        set: { enabled in Task { await model.setRuleEnabled(rule, enabled: enabled) } }
                    ))
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("ledger.rule.enabled.\(rule.id.uuidString)")
                    Button("Edit") { model.beginEditRule(rule) }
                        .accessibilityIdentifier("ledger.rule.edit.\(rule.id.uuidString)")
                    Button("Delete", role: .destructive) { Task { await model.deleteRule(rule) } }
                        .accessibilityIdentifier("ledger.rule.delete.\(rule.id.uuidString)")
                }
            }
            if model.ruleFormMode != nil {
                Divider()
                ruleEditor
            }
            HStack { Spacer(); Button("Done") { showingRules = false } }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 620)
    }

    private var ruleEditor: some View {
        Form {
            TextField("Rule name", text: $model.ruleDraft.name)
                .accessibilityIdentifier("ledger.rule.name")
            TextField("Priority", text: $model.ruleDraft.priority)
                .accessibilityIdentifier("ledger.rule.priority")
            Toggle("Enabled", isOn: $model.ruleDraft.isEnabled)
                .accessibilityIdentifier("ledger.rule.enabled")
            Picker("Match", selection: $model.ruleDraft.matchMode) {
                ForEach(ClassificationMatchMode.allCases, id: \.rawValue) { Text($0.rawValue.capitalized).tag($0) }
            }.accessibilityIdentifier("ledger.rule.matchMode")
            TextField("Payee/Description pattern (optional)", text: $model.ruleDraft.payeePattern)
                .accessibilityIdentifier("ledger.rule.pattern")
            Picker("Transaction Kind", selection: $model.ruleDraft.kind) {
                Text("Any Kind").tag(nil as TransactionKind?)
                ForEach(TransactionKind.allCases, id: \.rawValue) { Text($0.title).tag($0 as TransactionKind?) }
            }.accessibilityIdentifier("ledger.rule.kind")
            Picker("Source Container", selection: $model.ruleDraft.sourceContainerID) {
                Text("Any Container").tag(nil as UUID?)
                ForEach(model.containers) { Text($0.container.name).tag($0.id as UUID?) }
            }.accessibilityIdentifier("ledger.rule.container")
            Picker("Amount Direction", selection: $model.ruleDraft.amountDirection) {
                Text("Any Direction").tag(nil as LedgerAmountDirection?)
                ForEach(LedgerAmountDirection.allCases, id: \.rawValue) { Text($0.rawValue.capitalized).tag($0 as LedgerAmountDirection?) }
            }.accessibilityIdentifier("ledger.rule.direction")
            Picker("Result Category", selection: $model.ruleDraft.resultCategoryID) {
                Text("No Category").tag(nil as UUID?)
                ForEach(model.categories) { Text($0.name).tag($0.id as UUID?) }
            }.accessibilityIdentifier("ledger.rule.category")
            if !model.tags.isEmpty {
                Text("Result Tags")
                ForEach(model.tags) { tag in
                    Toggle(tag.name, isOn: Binding(
                        get: { model.ruleDraft.resultTagIDs.contains(tag.id) },
                        set: { enabled in
                            if enabled { model.ruleDraft.resultTagIDs.insert(tag.id) }
                            else { model.ruleDraft.resultTagIDs.remove(tag.id) }
                        }
                    )).accessibilityIdentifier("ledger.rule.tag.\(tag.id.uuidString)")
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { model.ruleFormMode = nil }
                Button("Save Rule") { Task { await model.saveRule() } }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("ledger.rule.save")
            }
        }
    }

    private var taxonomySheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Categories & Tags").font(.title2)
            HStack {
                TextField("New category", text: $categoryName).accessibilityIdentifier("ledger.category.name")
                Button("Add Category") { let value = categoryName; categoryName = ""; Task { await model.createCategory(name: value) } }
                    .accessibilityIdentifier("ledger.category.add")
            }
            ForEach(model.categories) { category in
                EditableTaxonomyRow(
                    name: category.name,
                    save: { value in await model.updateCategory(category, name: value) },
                    delete: { await model.deleteCategory(category) }
                )
            }
            Divider()
            HStack {
                TextField("New tag", text: $tagName).accessibilityIdentifier("ledger.tag.name")
                Button("Add Tag") { let value = tagName; tagName = ""; Task { await model.createTag(name: value) } }
                    .accessibilityIdentifier("ledger.tag.add")
            }
            ForEach(model.tags) { tag in
                EditableTaxonomyRow(
                    name: tag.name,
                    save: { value in await model.updateTag(tag, name: value) },
                    delete: { await model.deleteTag(tag) }
                )
            }
            Spacer()
            HStack { Spacer(); Button("Done") { showingTaxonomy = false }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(minWidth: 500, minHeight: 420)
    }

    private func importPreviewSheet(_ preview: LedgerImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Aureus Ledger V1 Import Preview").font(.title2)
            Text("\(preview.rows.count) rows · \(preview.errorCount) errors · \(preview.duplicateCount) duplicates")
                .accessibilityIdentifier("ledger.import.preview.summary")
            List(preview.rows) { row in
                HStack {
                    Text("Row \(row.id)")
                    Text(row.entry?.description ?? row.error ?? "Invalid row")
                    Spacer()
                    if row.isDuplicate {
                        Text("Duplicate: \(row.duplicateReasons.map(\.rawValue).joined(separator: ", "))")
                            .foregroundStyle(.orange)
                    }
                    else if row.error != nil { Text("Invalid").foregroundStyle(.red) }
                    else if let application = row.ruleApplication {
                        VStack(alignment: .trailing) {
                            Text("Rule: \(application.ruleName)")
                            Text("Category: \(application.finalCategoryName ?? "None") (\(application.categorySource.rawValue))")
                            Text("Tags: \(application.finalTagNames.joined(separator: ", ").isEmpty ? "None" : application.finalTagNames.joined(separator: ", ")) (\(application.tagsSource.rawValue))")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("ledger.import.ruleResult.\(row.id)")
                    }
                    else { Text("Ready").foregroundStyle(.green) }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { model.importPreview = nil }
                Button("Import") { Task { await model.confirmImport() } }
                    .disabled(!preview.canImport).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("ledger.import.confirm")
            }
        }.padding(24).frame(minWidth: 700, minHeight: 450)
    }

    private static func money(_ money: Money) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        return "\(money.currency.rawValue) \(formatter.string(from: NSDecimalNumber(decimal: money.decimal)) ?? "—")"
    }
}

private struct LedgerEntryForm: View {
    @Bindable var model: LedgerFeatureModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.formMode == .create ? "New Ledger Transaction" : "Edit Ledger Transaction").font(.title2)
            Form {
                Picker("Kind", selection: $model.draft.kind) {
                    ForEach(TransactionKind.allCases, id: \.rawValue) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("ledger.form.kind")
                TextField("Description", text: $model.draft.description).accessibilityIdentifier("ledger.form.description")
                TextField("Payee", text: $model.draft.payee).accessibilityIdentifier("ledger.form.payee")
                TextField("Date (YYYY-MM-DD)", text: $model.draft.date).accessibilityIdentifier("ledger.form.date")
                Picker("Source Container", selection: $model.draft.sourceContainerID) {
                    Text("Select").tag(nil as UUID?)
                    ForEach(model.containers) { Text($0.container.name).tag($0.id as UUID?) }
                }.accessibilityIdentifier("ledger.form.sourceContainer")
                Picker("Currency", selection: $model.draft.sourceCurrency) {
                    ForEach(CurrencyCode.allCases, id: \.rawValue) { Text($0.rawValue).tag($0) }
                }.accessibilityIdentifier("ledger.form.sourceCurrency")
                TextField("Amount", text: $model.draft.sourceAmount).accessibilityIdentifier("ledger.form.sourceAmount")
                if model.draft.sourceCurrency == .usd {
                    TextField("USD to CNY rate", text: $model.draft.sourceFXRate).accessibilityIdentifier("ledger.form.sourceFX")
                    Text("Manual FX — CNY per 1 USD").font(.caption).foregroundStyle(.secondary)
                }
                if model.draft.kind == .transfer {
                    Picker("Target Container", selection: $model.draft.targetContainerID) {
                        Text("Select").tag(nil as UUID?)
                        ForEach(model.containers) { Text($0.container.name).tag($0.id as UUID?) }
                    }.accessibilityIdentifier("ledger.form.targetContainer")
                    Picker("Target Currency", selection: $model.draft.targetCurrency) {
                        ForEach(CurrencyCode.allCases, id: \.rawValue) { Text($0.rawValue).tag($0) }
                    }.accessibilityIdentifier("ledger.form.targetCurrency")
                    TextField("Target Amount", text: $model.draft.targetAmount).accessibilityIdentifier("ledger.form.targetAmount")
                    if model.draft.targetCurrency == .usd { TextField("Target USD to CNY rate", text: $model.draft.targetFXRate).accessibilityIdentifier("ledger.form.targetFX") }
                } else {
                    Picker("Category", selection: $model.draft.categoryID) {
                        Text("None").tag(nil as UUID?)
                        ForEach(model.categories) { Text($0.name).tag($0.id as UUID?) }
                    }.accessibilityIdentifier("ledger.form.category")
                }
                if !model.tags.isEmpty {
                    Text("Tags")
                    ForEach(model.tags) { tag in
                        Toggle(tag.name, isOn: Binding(get: { model.draft.tagIDs.contains(tag.id) }, set: { value in if value { model.draft.tagIDs.insert(tag.id) } else { model.draft.tagIDs.remove(tag.id) } }))
                            .accessibilityIdentifier("ledger.form.tag.\(tag.id.uuidString)")
                    }
                }
                TextField("Note", text: $model.draft.note).accessibilityIdentifier("ledger.form.note")
            }
            HStack {
                Spacer()
                Button("Cancel") { model.formMode = nil }
                Button("Save") { Task { await model.save() } }.keyboardShortcut(.defaultAction).accessibilityIdentifier("ledger.form.save")
            }
        }.padding(24).frame(minWidth: 620, minHeight: 650)
    }
}

struct LedgerCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct EditableTaxonomyRow: View {
    @State var name: String
    let save: @MainActor (String) async -> Void
    let delete: @MainActor () async -> Void

    var body: some View {
        HStack {
            TextField("Name", text: $name)
            Button("Save") { let value = name; Task { await save(value) } }
            Button("Delete", role: .destructive) { Task { await delete() } }
        }
    }
}
