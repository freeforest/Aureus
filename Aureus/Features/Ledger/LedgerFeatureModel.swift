import Foundation
import Observation

enum LedgerFormMode: Equatable { case create, edit(UUID) }
enum ClassificationRuleFormMode: Equatable { case create, edit(UUID) }
enum LedgerEditLoadState: Equatable { case idle, loading, ready, failed }
enum LedgerHistoryLoadState: Equatable { case idle, loading, ready, failed }

struct ClassificationRuleDraft: Equatable {
    var name = ""
    var priority = "100"
    var isEnabled = true
    var matchMode: ClassificationMatchMode = .contains
    var payeePattern = ""
    var kind: TransactionKind?
    var sourceContainerID: UUID?
    var amountDirection: LedgerAmountDirection?
    var resultCategoryID: UUID?
    var resultTagIDs: Set<UUID> = []

    static func editing(_ rule: ClassificationRule) -> ClassificationRuleDraft {
        ClassificationRuleDraft(
            name: rule.name,
            priority: String(rule.priority),
            isEnabled: rule.isEnabled,
            matchMode: rule.matchMode,
            payeePattern: rule.payeePattern ?? "",
            kind: rule.kind,
            sourceContainerID: rule.sourceContainerID,
            amountDirection: rule.amountDirection,
            resultCategoryID: rule.resultCategory?.id,
            resultTagIDs: Set(rule.resultTags.map(\.id))
        )
    }
}

struct LedgerDraft: Equatable {
    var kind: TransactionKind = .income
    var description = ""
    var payee = ""
    var date = "2026-01-15"
    var sourceContainerID: UUID?
    var sourceCurrency: CurrencyCode = .cny
    var sourceAmount = ""
    var sourceFXRate = "7.00"
    var targetContainerID: UUID?
    var targetCurrency: CurrencyCode = .cny
    var targetAmount = ""
    var targetFXRate = "7.00"
    var categoryID: UUID?
    var tagIDs: Set<UUID> = []
    var note = ""

    static func editing(_ entry: LedgerEntry) -> LedgerDraft {
        let source = entry.kind == .transfer ? entry.transferSource! : entry.primaryPosting!
        let target = entry.transferTarget
        return LedgerDraft(
            kind: entry.kind, description: entry.description, payee: entry.payee ?? "",
            date: entry.civilDate.description, sourceContainerID: source.containerID,
            sourceCurrency: source.valuation.original.currency,
            sourceAmount: NSDecimalNumber(decimal: source.valuation.original.decimal).stringValue,
            sourceFXRate: NSDecimalNumber(decimal: source.valuation.rate.decimal).stringValue,
            targetContainerID: target?.containerID, targetCurrency: target?.valuation.original.currency ?? .cny,
            targetAmount: target.map { NSDecimalNumber(decimal: $0.valuation.original.decimal).stringValue } ?? "",
            targetFXRate: target.map { NSDecimalNumber(decimal: $0.valuation.rate.decimal).stringValue } ?? "7.00",
            categoryID: entry.category?.id, tagIDs: Set(entry.tags.map(\.id)), note: entry.note ?? ""
        )
    }
}

@MainActor
@Observable
final class LedgerFeatureModel {
    private(set) var entries: [LedgerEntry] = []
    private(set) var visibleEntries: [LedgerEntry] = []
    private(set) var containers: [WealthContainer] = []
    private(set) var categories: [Category] = []
    private(set) var tags: [Tag] = []
    private(set) var rules: [ClassificationRule] = []
    private(set) var summary: CashFlowSummary = .zero
    var importPreview: LedgerImportPreview?
    var filter = LedgerFilter.all
    var filterStartDateText = ""
    var filterEndDateText = ""
    private(set) var filterValidationMessage: String?
    private(set) var formMode: LedgerFormMode?
    var draft = LedgerDraft()
    private(set) var editLoadState: LedgerEditLoadState = .idle
    private(set) var editFeedback: String?
    private(set) var isSaving = false
    private(set) var requiresEditReload = false
    var correctionReason = ""
    private(set) var historyTargetID: UUID?
    private(set) var correctionHistory: [LedgerCorrectionHistory] = []
    private(set) var historyLoadState: LedgerHistoryLoadState = .idle
    var ruleFormMode: ClassificationRuleFormMode?
    var ruleDraft = ClassificationRuleDraft()
    var errorMessage: String?
    var pendingDeletion: LedgerEntry?

    @ObservationIgnored private let store: WealthStore
    @ObservationIgnored private let clock: any Clock
    @ObservationIgnored private let contextLoader: @Sendable (UUID) async throws -> LedgerEditContext
    @ObservationIgnored private let historyLoader: @Sendable (UUID) async throws -> [LedgerCorrectionHistory]
    @ObservationIgnored private let correctionWriter: @Sendable (LedgerCorrectionRequest) async throws -> LedgerCorrectionResult
    @ObservationIgnored private var editContext: LedgerEditContext?
    @ObservationIgnored private var editSessionID = UUID()
    @ObservationIgnored private var historySessionID = UUID()
    @ObservationIgnored private var pendingCorrection: LedgerCorrectionRequest?
    @ObservationIgnored private var pendingDraft: LedgerDraft?

    init(
        store: WealthStore, clock: any Clock,
        contextLoader: (@Sendable (UUID) async throws -> LedgerEditContext)? = nil,
        historyLoader: (@Sendable (UUID) async throws -> [LedgerCorrectionHistory])? = nil,
        correctionWriter: (@Sendable (LedgerCorrectionRequest) async throws -> LedgerCorrectionResult)? = nil
    ) {
        self.store = store
        self.clock = clock
        self.contextLoader = contextLoader ?? { try await store.readLedgerEditContext(id: $0) }
        self.historyLoader = historyLoader ?? { try await store.ledgerCorrectionHistory(id: $0) }
        self.correctionWriter = correctionWriter ?? { try await store.correctLedgerEntry($0) }
    }

    func load() async {
        do {
            async let entries = store.fetchLedgerEntries()
            async let containers = store.fetchWealthContainers()
            async let categories = store.fetchCategories()
            async let tags = store.fetchTags()
            async let rules = store.fetchClassificationRules()
            self.entries = try await entries
            self.containers = try await containers
            self.categories = try await categories
            self.tags = try await tags
            self.rules = try await rules
            applyFilter()
        } catch { errorMessage = "Ledger could not be loaded: \(error.localizedDescription)" }
    }

    func applyFilter() {
        do {
            filter.startDate = filterStartDateText.isEmpty ? nil : try CivilDate(canonical: filterStartDateText)
            filter.endDate = filterEndDateText.isEmpty ? nil : try CivilDate(canonical: filterEndDateText)
            guard !filter.hasInvalidDateRange else {
                filterValidationMessage = "Start Date must be on or before End Date."
                visibleEntries = []
                summary = .zero
                return
            }
            filterValidationMessage = nil
        } catch {
            filterValidationMessage = "Dates must use YYYY-MM-DD."
            visibleEntries = []
            summary = .zero
            return
        }
        visibleEntries = entries.filter(filter.includes)
        do { summary = try LedgerCashFlow.summarize(visibleEntries) }
        catch { errorMessage = "Cash flow could not be calculated." }
    }

    func clearFilters() {
        filter = .all
        filterStartDateText = ""
        filterEndDateText = ""
        filterValidationMessage = nil
        applyFilter()
    }

    func beginCreate() {
        guard !isSaving else { return }
        clearEditSession()
        draft = LedgerDraft(sourceContainerID: containers.first?.id, targetContainerID: containers.dropFirst().first?.id)
        formMode = .create
    }

    func beginEdit(id: UUID) async {
        guard !isSaving else { return }
        clearEditSession()
        let session = editSessionID
        formMode = .edit(id)
        editLoadState = .loading
        do {
            let context = try await contextLoader(id)
            guard editSessionID == session, formMode == .edit(id) else { return }
            editContext = context
            draft = .editing(context.entry)
            editLoadState = .ready
        } catch {
            guard editSessionID == session, formMode == .edit(id) else { return }
            editLoadState = .failed
            editFeedback = "Transaction could not be loaded for editing. Close and try again."
        }
    }

    func reloadEdit() async {
        guard case .edit(let id) = formMode, !isSaving else { return }
        await beginEdit(id: id)
    }

    func cancelForm() {
        guard !isSaving else { return }
        clearEditSession()
        formMode = nil
    }

    private func clearEditSession() {
        editSessionID = UUID()
        editContext = nil
        pendingCorrection = nil
        pendingDraft = nil
        correctionReason = ""
        editFeedback = nil
        editLoadState = .idle
        requiresEditReload = false
    }

    var needsCorrectionReason: Bool {
        guard case .edit = formMode, let context = editContext,
              let candidate = try? makeEntry() else { return false }
        return !LedgerCorrectionProjection(context.entry)
            .hasSameImportantValues(as: LedgerCorrectionProjection(candidate))
    }

    var canSaveForm: Bool {
        guard !isSaving else { return false }
        switch formMode {
        case .create: return true
        case .edit:
            guard editLoadState == .ready, !requiresEditReload else { return false }
            return !needsCorrectionReason || (try? LedgerCorrectionEncoding.reason(correctionReason)) != nil
        case nil: return false
        }
    }

    func save() async {
        guard !isSaving, let mode = formMode else { return }
        guard mode == .create || (editLoadState == .ready && !requiresEditReload) else { return }
        do {
            let request: LedgerCorrectionRequest?
            let entry: LedgerEntry
            switch mode {
            case .create:
                entry = try makeEntry()
                request = nil
            case .edit(let id):
                guard let context = editContext, context.entry.id == id else { return }
                if let pendingCorrection {
                    guard pendingDraft == draft,
                          correctionReason.trimmingCharacters(in: .whitespacesAndNewlines) == pendingCorrection.reason else {
                        editFeedback = "This draft differs from the pending request. Reload the current transaction before making a new request."
                        return
                    }
                    entry = pendingCorrection.candidate
                    request = pendingCorrection
                } else {
                    entry = try makeEntry()
                    let important = !LedgerCorrectionProjection(context.entry)
                        .hasSameImportantValues(as: LedgerCorrectionProjection(entry))
                    let reason = important ? try LedgerCorrectionEncoding.reason(correctionReason) : ""
                    let prepared = LedgerCorrectionRequest(candidate: entry, expected: context.token,
                        operationID: UUID(), reason: reason, occurredAt: clock.now())
                    pendingCorrection = prepared
                    pendingDraft = draft
                    request = prepared
                }
            }
            isSaving = true
            editFeedback = nil
            let session = editSessionID
            do {
                if let request {
                    let result = try await correctionWriter(request)
                    guard editSessionID == session else { isSaving = false; return }
                    switch result {
                    case .applied, .noChange, .minorUpdate, .alreadyApplied(_, .unchanged):
                        isSaving = false
                        cancelForm()
                        await load()
                    case .alreadyApplied(_, .changed):
                        requiresEditReload = true
                        editFeedback = "The correction was saved, but this transaction changed afterward. Reload current data before another edit."
                        isSaving = false
                    case .alreadyApplied(_, .deleted):
                        requiresEditReload = true
                        editFeedback = "The correction was saved, but this transaction was later deleted. Reload current data."
                        isSaving = false
                    }
                } else {
                    try await store.createLedgerEntry(entry)
                    guard editSessionID == session else { isSaving = false; return }
                    isSaving = false
                    cancelForm()
                    await load()
                }
            } catch {
                isSaving = false
                if case .edit = mode {
                    switch error {
                    case LedgerCorrectionError.staleDraft, LedgerPersistenceError.transactionNotFound:
                        requiresEditReload = true
                        editFeedback = "This transaction changed or was deleted. Your draft remains; reload current data before editing again."
                    case LedgerCorrectionError.operationConflict:
                        requiresEditReload = true
                        editFeedback = "This request ID belongs to another correction. Reload current data before editing again."
                    case LedgerCorrectionError.maintenanceUnavailable:
                        editFeedback = "Data maintenance is in progress. Retry the same request when it finishes."
                    default:
                        editFeedback = "Save status could not be confirmed. Retry the same request without changing this draft."
                    }
                } else {
                    errorMessage = "Transaction was not saved. Check the entry and retry."
                }
            }
        } catch {
            editFeedback = "Check the transaction values and correction reason before saving."
        }
    }

    func showCorrectionHistory(id: UUID) async {
        historySessionID = UUID()
        let session = historySessionID
        historyTargetID = id
        correctionHistory = []
        historyLoadState = .loading
        do {
            let records = try await historyLoader(id)
            guard historySessionID == session, historyTargetID == id else { return }
            correctionHistory = records
            historyLoadState = .ready
        } catch {
            guard historySessionID == session, historyTargetID == id else { return }
            historyLoadState = .failed
        }
    }

    func closeCorrectionHistory() {
        historySessionID = UUID()
        historyTargetID = nil
        correctionHistory = []
        historyLoadState = .idle
    }

    func delete(_ entry: LedgerEntry) async {
        do {
            try await store.deleteLedgerEntry(id: entry.id)
            pendingDeletion = nil
            await load()
        } catch { errorMessage = "Transaction was not deleted: \(error.localizedDescription)" }
    }

    func createCategory(name: String) async {
        do { _ = try await store.createCategory(name: name); await load() }
        catch { errorMessage = "Category was not created: \(error.localizedDescription)" }
    }

    func deleteCategory(_ category: Category) async {
        do { try await store.deleteCategory(id: category.id); await load() }
        catch { errorMessage = "Category is in use and was not deleted." }
    }

    func updateCategory(_ category: Category, name: String) async {
        do { _ = try await store.updateCategory(id: category.id, name: name); await load() }
        catch { errorMessage = "Category was not renamed." }
    }

    func createTag(name: String) async {
        do { _ = try await store.createTag(name: name); await load() }
        catch { errorMessage = "Tag was not created: \(error.localizedDescription)" }
    }

    func deleteTag(_ tag: Tag) async {
        do { try await store.deleteTag(id: tag.id); await load() }
        catch { errorMessage = "Tag is in use and was not deleted." }
    }

    func updateTag(_ tag: Tag, name: String) async {
        do { _ = try await store.updateTag(id: tag.id, name: name); await load() }
        catch { errorMessage = "Tag was not renamed." }
    }

    func beginCreateRule() {
        ruleDraft = ClassificationRuleDraft(
            sourceContainerID: nil,
            resultCategoryID: categories.first?.id
        )
        ruleFormMode = .create
    }

    func beginEditRule(_ rule: ClassificationRule) {
        ruleDraft = .editing(rule)
        ruleFormMode = .edit(rule.id)
    }

    func saveRule() async {
        do {
            guard let priority = Int(ruleDraft.priority) else {
                throw LedgerCSVError.invalidField("rule priority")
            }
            let id: UUID
            if case .edit(let existing) = ruleFormMode { id = existing } else { id = UUID() }
            let rule = ClassificationRule(
                id: id,
                name: ruleDraft.name,
                priority: priority,
                isEnabled: ruleDraft.isEnabled,
                matchMode: ruleDraft.matchMode,
                payeePattern: ruleDraft.payeePattern.isEmpty ? nil : ruleDraft.payeePattern,
                kind: ruleDraft.kind,
                sourceContainerID: ruleDraft.sourceContainerID,
                amountDirection: ruleDraft.amountDirection,
                resultCategory: categories.first { $0.id == ruleDraft.resultCategoryID },
                resultTags: tags.filter { ruleDraft.resultTagIDs.contains($0.id) }
            )
            switch ruleFormMode {
            case .create: try await store.createClassificationRule(rule)
            case .edit: try await store.updateClassificationRule(rule)
            case nil: return
            }
            ruleFormMode = nil
            await load()
        } catch {
            errorMessage = "Classification rule was not saved: \(error.localizedDescription)"
        }
    }

    func setRuleEnabled(_ rule: ClassificationRule, enabled: Bool) async {
        do {
            try await store.setClassificationRuleEnabled(id: rule.id, enabled: enabled)
            await load()
        } catch { errorMessage = "Classification rule state was not changed." }
    }

    func deleteRule(_ rule: ClassificationRule) async {
        do {
            try await store.deleteClassificationRule(id: rule.id)
            await load()
        } catch { errorMessage = "Classification rule was not deleted." }
    }

    func prepareImport(data: Data) async {
        do {
            let identities = try await store.existingImportIdentities()
            importPreview = try LedgerCSV.preview(
                data: data, containers: containers, categories: categories, tags: tags,
                rules: rules,
                existingFingerprints: identities.fingerprints,
                existingTransactionIDs: identities.transactionIDs
            )
        } catch { errorMessage = "CSV preview failed: \(error)" }
    }

    func confirmImport() async {
        guard let preview = importPreview, preview.canImport else { return }
        do {
            try await store.importLedgerEntries(preview.validEntries, batchID: UUID(), importedAt: clock.now())
            importPreview = nil
            await load()
        } catch { errorMessage = "CSV import was rolled back: \(error.localizedDescription)" }
    }

    func exportData() -> Data { LedgerCSV.export(entries) }

    private func makeEntry() throws -> LedgerEntry {
        guard let sourceID = draft.sourceContainerID else { throw LedgerCSVError.invalidField("source container") }
        let date = try CivilDate(canonical: draft.date)
        let original: LedgerEntry?
        if case .edit = formMode { original = editContext?.entry } else { original = nil }
        let instant = original?.recordedAt ?? clock.now()
        let source = try makePosting(
            role: draft.kind == .transfer ? .transferSource : .primary,
            containerID: sourceID, currency: draft.sourceCurrency,
            amount: draft.sourceAmount, rate: draft.sourceFXRate, date: date, instant: instant,
            previous: original?.postings.first { $0.role == (draft.kind == .transfer ? .transferSource : .primary) }
        )
        var postings = [source]
        if draft.kind == .transfer {
            guard let targetID = draft.targetContainerID else { throw LedgerCSVError.invalidField("target container") }
            postings.append(try makePosting(
                role: .transferTarget, containerID: targetID, currency: draft.targetCurrency,
                amount: draft.targetAmount, rate: draft.targetFXRate, date: date, instant: instant,
                previous: original?.transferTarget
            ))
        }
        let id: UUID
        if case .edit(let existing) = formMode { id = existing } else { id = UUID() }
        return try LedgerEntry(
            id: id, kind: draft.kind, civilDate: date, recordedAt: instant,
            description: draft.description, payee: draft.payee,
            category: draft.kind == .transfer ? nil : categories.first { $0.id == draft.categoryID },
            tags: tags.filter { draft.tagIDs.contains($0.id) }, postings: postings, note: draft.note,
            importFingerprint: original?.importFingerprint
        )
    }

    private func makePosting(
        role: LedgerPostingRole, containerID: UUID, currency: CurrencyCode,
        amount: String, rate: String, date: CivilDate, instant: UTCInstant,
        previous: LedgerPosting?
    ) throws -> LedgerPosting {
        let money = try Money(decimal: FixedPointMath.parseCanonical(amount), currency: currency)
        let fx = currency == .cny
            ? FXRate.cnyIdentity
            : try FXRate(decimal: FixedPointMath.parseCanonical(rate), sourceCurrency: .usd, targetCurrency: .cny)
        if let previous, previous.valuation.original.currency == currency, previous.valuation.rate == fx {
            let old = previous.valuation
            let valuation = try FXValuation(original: money, rate: old.rate,
                referenceDate: old.referenceDate, fetchedAt: old.fetchedAt,
                providerIdentifier: old.providerIdentifier,
                isManualOverride: old.isManualOverride, isStale: old.isStale)
            return try LedgerPosting(id: previous.id, role: role, containerID: containerID, valuation: valuation)
        }
        let valuation = try FXValuation(
            original: money, rate: fx, referenceDate: date, fetchedAt: instant,
            providerIdentifier: currency == .cny ? "identity" : "manual.user.stage4",
            isManualOverride: currency == .usd, isStale: false
        )
        return try LedgerPosting(id: previous?.id ?? UUID(), role: role, containerID: containerID, valuation: valuation)
    }
}
