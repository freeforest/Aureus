import Foundation
import Observation

enum LedgerFormMode: Equatable { case create, edit(UUID) }
enum ClassificationRuleFormMode: Equatable { case create, edit(UUID) }

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
    var formMode: LedgerFormMode?
    var draft = LedgerDraft()
    var ruleFormMode: ClassificationRuleFormMode?
    var ruleDraft = ClassificationRuleDraft()
    var errorMessage: String?
    var pendingDeletion: LedgerEntry?

    @ObservationIgnored private let store: WealthStore
    @ObservationIgnored private let clock: any Clock

    init(store: WealthStore, clock: any Clock) {
        self.store = store
        self.clock = clock
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
        draft = LedgerDraft(sourceContainerID: containers.first?.id, targetContainerID: containers.dropFirst().first?.id)
        formMode = .create
    }

    func beginEdit(_ entry: LedgerEntry) {
        draft = .editing(entry)
        formMode = .edit(entry.id)
    }

    func save() async {
        do {
            let entry = try makeEntry()
            switch formMode {
            case .create: try await store.createLedgerEntry(entry)
            case .edit: try await store.updateLedgerEntry(entry)
            case nil: return
            }
            formMode = nil
            await load()
        } catch { errorMessage = "Transaction was not saved: \(error.localizedDescription)" }
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
        let instant = clock.now()
        let source = try makePosting(
            role: draft.kind == .transfer ? .transferSource : .primary,
            containerID: sourceID, currency: draft.sourceCurrency,
            amount: draft.sourceAmount, rate: draft.sourceFXRate, date: date, instant: instant
        )
        var postings = [source]
        if draft.kind == .transfer {
            guard let targetID = draft.targetContainerID else { throw LedgerCSVError.invalidField("target container") }
            postings.append(try makePosting(
                role: .transferTarget, containerID: targetID, currency: draft.targetCurrency,
                amount: draft.targetAmount, rate: draft.targetFXRate, date: date, instant: instant
            ))
        }
        let id: UUID
        if case .edit(let existing) = formMode { id = existing } else { id = UUID() }
        return try LedgerEntry(
            id: id, kind: draft.kind, civilDate: date, recordedAt: instant,
            description: draft.description, payee: draft.payee,
            category: draft.kind == .transfer ? nil : categories.first { $0.id == draft.categoryID },
            tags: tags.filter { draft.tagIDs.contains($0.id) }, postings: postings, note: draft.note
        )
    }

    private func makePosting(
        role: LedgerPostingRole, containerID: UUID, currency: CurrencyCode,
        amount: String, rate: String, date: CivilDate, instant: UTCInstant
    ) throws -> LedgerPosting {
        let money = try Money(decimal: FixedPointMath.parseCanonical(amount), currency: currency)
        let fx = currency == .cny
            ? FXRate.cnyIdentity
            : try FXRate(decimal: FixedPointMath.parseCanonical(rate), sourceCurrency: .usd, targetCurrency: .cny)
        let valuation = try FXValuation(
            original: money, rate: fx, referenceDate: date, fetchedAt: instant,
            providerIdentifier: currency == .cny ? "identity" : "manual.user.stage4",
            isManualOverride: currency == .usd, isStale: false
        )
        return try LedgerPosting(role: role, containerID: containerID, valuation: valuation)
    }
}
