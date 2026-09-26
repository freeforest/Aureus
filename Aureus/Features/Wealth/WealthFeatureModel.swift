import Foundation
import Observation

enum WealthLoadState: Equatable {
    case loading
    case ready
    case failed
}

enum WealthEditLoadState: Equatable { case idle, loading, ready, failed }
enum WealthHistoryLoadState: Equatable { case idle, loading, ready, failed }
enum WealthEditIntent: Equatable {
    case correction
    case currentValuation
}

struct WealthEditorPresentation: Identifiable, Equatable {
    let id = UUID()
    var targetID: UUID?
    let existing: WealthContainer?
    var initialCurrency: CurrencyCode = .cny

    var initialDraft: WealthEditorDraft {
        if let existing { return WealthEditorDraft(existing: existing) }
        var draft = WealthEditorDraft()
        draft.currency = initialCurrency
        return draft
    }
}

struct WealthDeleteConfirmation: Identifiable, Equatable {
    var id: UUID { record.id }
    let record: WealthContainer
    let impact: ContainerDeletionImpact
}

enum WealthEditorError: LocalizedError, Equatable {
    case required(String)
    case invalidNumber(String)
    case invalidDate(String)
    case invalidFX
    case invalidReason

    var errorDescription: String? {
        switch self {
        case let .required(field): "\(field) is required."
        case let .invalidNumber(field): "\(field) must be a valid non-negative decimal value."
        case let .invalidDate(field): "\(field) must use YYYY-MM-DD and be a valid Gregorian date."
        case .invalidFX: "USD records require a positive manual USD → CNY rate."
        case .invalidReason: "An important correction requires a reason of 1–500 characters without NUL."
        }
    }
}

struct WealthEditorDraft: Equatable {
    var name = ""
    var kind: AssetContainerKind = .bankCash
    var institution = ""
    var currency: CurrencyCode = .cny
    var notes = ""

    var amount = ""
    var interestRatePercent = ""

    var ticker = ""
    var mic = ""
    var quantity = ""
    var manualPrice = ""

    var insuranceCompany = ""
    var insuranceProductName = ""
    var premium = ""
    var paymentFrequency: InsurancePaymentFrequency = .annual
    var coverage = ""
    var startDate = "2026-01-15"
    var maturityDate = ""

    var categoryDescription = ""

    var fxRate = ""
    var fxReferenceDate = "2026-01-15"
    var fxIsStale = false

    init() {}

    init(existing record: WealthContainer) {
        name = record.container.name
        kind = record.container.kind
        institution = record.container.institution ?? ""
        currency = record.container.primaryCurrency
        notes = record.container.notes ?? ""
        amount = Self.decimalString(record.originalValue.decimal)
        if record.valuation.isManualOverride {
            fxRate = Self.decimalString(record.valuation.rate.decimal)
        }
        fxReferenceDate = record.valuation.referenceDate.description
        fxIsStale = record.valuation.isStale

        switch record.details {
        case let .bankCash(_, interestRate), let .liability(_, interestRate):
            if let interestRate {
                interestRatePercent = Self.decimalString(interestRate.decimal * 100)
            }
        case let .security(storedTicker, storedMIC, storedQuantity, storedPrice):
            ticker = storedTicker
            mic = storedMIC ?? ""
            quantity = Self.decimalString(storedQuantity.decimal)
            manualPrice = Self.decimalString(storedPrice.decimal)
        case let .insurance(company, product, storedPremium, frequency, storedCoverage, _, start, maturity):
            insuranceCompany = company
            insuranceProductName = product
            premium = Self.decimalString(storedPremium.decimal)
            paymentFrequency = frequency
            coverage = Self.decimalString(storedCoverage.decimal)
            startDate = start.description
            maturityDate = maturity?.description ?? ""
        case let .otherAsset(description, _):
            categoryDescription = description
        }
    }

    func makeRecord(
        existing: WealthContainer?,
        today: CivilDate,
        now: UTCInstant
    ) throws -> WealthContainer {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw WealthEditorError.required("Name") }

        let details: WealthRecordDetails
        switch kind {
        case .bankCash:
            details = .bankCash(
                balance: try money(from: amount, field: "Current balance"),
                interestRate: try optionalInterestRate()
            )
        case .stock, .etf, .fund:
            let normalizedTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !normalizedTicker.isEmpty else { throw WealthEditorError.required("Ticker / Code") }
            details = .security(
                ticker: normalizedTicker,
                mic: normalizedOptional(mic)?.uppercased(),
                quantity: try AssetQuantity(decimal: decimal(from: quantity, field: "Quantity")),
                manualPrice: try MarketPrice(
                    decimal: decimal(from: manualPrice, field: "Manual current price"),
                    quoteCurrency: currency
                )
            )
        case .insurance:
            let company = insuranceCompany.trimmingCharacters(in: .whitespacesAndNewlines)
            let product = insuranceProductName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !company.isEmpty else { throw WealthEditorError.required("Insurance company") }
            guard !product.isEmpty else { throw WealthEditorError.required("Product name") }
            let start = try civilDate(from: startDate, field: "Start date")
            let maturity = try optionalCivilDate(from: maturityDate, field: "Maturity date")
            details = .insurance(
                company: company,
                productName: product,
                premium: try money(from: premium, field: "Premium"),
                paymentFrequency: paymentFrequency,
                coverage: try money(from: coverage, field: "Coverage"),
                currentCashValue: try money(from: amount, field: "Current cash value"),
                startDate: start,
                maturityDate: maturity
            )
        case .otherAsset:
            let description = categoryDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !description.isEmpty else { throw WealthEditorError.required("Category / Description") }
            details = .otherAsset(
                categoryDescription: description,
                currentValue: try money(from: amount, field: "Current value")
            )
        case .liability:
            details = .liability(
                outstandingBalance: try money(from: amount, field: "Outstanding balance"),
                interestRate: try optionalInterestRate()
            )
        }

        let original = try details.currentValue()
        let manualFX: ManualFXInput?
        if currency == .usd {
            guard !fxRate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WealthEditorError.invalidFX
            }
            let rateDecimal = try decimal(from: fxRate, field: "USD → CNY rate")
            let rate = try FXRate(
                decimal: rateDecimal,
                sourceCurrency: .usd,
                targetCurrency: .cny
            )
            manualFX = try ManualFXInput(
                rate: rate,
                source: "manual",
                referenceDate: try civilDate(from: fxReferenceDate, field: "FX reference date"),
                recordedAt: now,
                isStale: fxIsStale
            )
        } else {
            manualFX = nil
        }
        let valuation = try WealthValuation.valuation(
            original: original,
            manualFX: manualFX,
            identityDate: today,
            recordedAt: now
        )
        let createdDate = existing?.container.createdDate ?? today
        return try WealthContainer(
            container: AssetContainer(
                id: existing?.id ?? UUID(),
                accountID: existing?.container.accountID,
                name: normalizedName,
                kind: kind,
                institution: normalizedOptional(institution),
                primaryCurrency: currency,
                notes: normalizedOptional(notes),
                createdDate: createdDate,
                updatedDate: today
            ),
            details: details,
            valuation: valuation
        )
    }

    // The draft's semantic FX inputs decide whether an edit preserves provenance.
    // The submission clock is sampled once by the caller and is only used for new FX.
    func makeEditCandidate(
        from before: WealthContainer, today: CivilDate, commandTime: UTCInstant
    ) throws -> (WealthContainer, WealthFXIntent) {
        let rebuilt = try makeRecord(existing: before, today: today, now: commandTime)
        let old = before.valuation
        let sameCurrency = currency == before.container.primaryCurrency
        let sameInput: Bool
        if currency == .usd && sameCurrency {
            let enteredRate = try decimal(from: fxRate, field: "USD → CNY rate")
            let enteredDate = try civilDate(from: fxReferenceDate, field: "FX reference date")
            sameInput = enteredRate == old.rate.decimal
                && enteredDate == old.referenceDate
                && fxIsStale == old.isStale
        } else {
            sameInput = sameCurrency
        }
        guard sameInput else { return (rebuilt, .newInput) }
        let valuation = try FXValuation(original: rebuilt.originalValue, rate: old.rate,
            referenceDate: old.referenceDate, fetchedAt: old.fetchedAt,
            providerIdentifier: old.providerIdentifier,
            isManualOverride: old.isManualOverride, isStale: old.isStale)
        return (try WealthContainer(container: rebuilt.container, details: rebuilt.details,
            valuation: valuation), .preserve)
    }

    private func money(from text: String, field: String) throws -> Money {
        let value = try decimal(from: text, field: field)
        guard value >= 0 else { throw WealthEditorError.invalidNumber(field) }
        return try Money(decimal: value, currency: currency)
    }

    private func decimal(from text: String, field: String) throws -> Decimal {
        do {
            return try FixedPointMath.parseCanonical(
                text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            throw WealthEditorError.invalidNumber(field)
        }
    }

    private func optionalInterestRate() throws -> Percentage? {
        let normalized = interestRatePercent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let percent = try decimal(from: normalized, field: "Interest rate")
        guard percent >= 0 else { throw WealthEditorError.invalidNumber("Interest rate") }
        return try Percentage(decimal: percent / 100)
    }

    private func civilDate(from text: String, field: String) throws -> CivilDate {
        do {
            return try CivilDate(canonical: text.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            throw WealthEditorError.invalidDate(field)
        }
    }

    private func optionalCivilDate(from text: String, field: String) throws -> CivilDate? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return try civilDate(from: normalized, field: field)
    }

    private func normalizedOptional(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func decimalString(_ decimal: Decimal) -> String {
        NSDecimalNumber(decimal: decimal).stringValue
    }
}

@MainActor
@Observable
final class WealthFeatureModel {
    let generalPreferences: GeneralPreferencesStore
    private(set) var records: [WealthContainer] = []
    private(set) var summary: WealthSummary = .zero
    private(set) var loadState: WealthLoadState = .loading
    var selection: UUID?
    var editor: WealthEditorPresentation?
    var pendingDeletion: WealthDeleteConfirmation?
    var editorErrorMessage: String?
    var persistenceErrorMessage: String?
    var deletionProtectionMessage: String?
    private(set) var editLoadState: WealthEditLoadState = .idle
    private(set) var isSaving = false
    private(set) var requiresEditReload = false
    private(set) var editFeedback: String?
    var editIntent: WealthEditIntent = .correction
    var correctionReason = ""
    private(set) var historyTargetID: UUID?
    private(set) var correctionHistory: [WealthCorrectionHistory] = []
    private(set) var historyLoadState: WealthHistoryLoadState = .idle

    @ObservationIgnored private let store: WealthStore
    @ObservationIgnored private let clock: any Clock
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private let contextLoader: @Sendable (UUID) async throws -> WealthEditContext
    @ObservationIgnored private let historyLoader: @Sendable (UUID) async throws -> [WealthCorrectionHistory]
    @ObservationIgnored private let correctionWriter: @Sendable (WealthCorrectionRequest) async throws -> WealthCorrectionResult
    @ObservationIgnored private let valuationWriter: @Sendable (WealthCurrentValuationRequest) async throws -> WealthCurrentValuationResult
    @ObservationIgnored private var editContext: WealthEditContext?
    @ObservationIgnored private var editSessionID = UUID()
    @ObservationIgnored private var historySessionID = UUID()
    @ObservationIgnored private var pendingCorrection: WealthCorrectionRequest?
    @ObservationIgnored private var pendingDraft: WealthEditorDraft?
    @ObservationIgnored private var pendingIntent: WealthEditIntent?

    init(store: WealthStore, clock: any Clock, timeZone: TimeZone = .current,
         generalPreferences: GeneralPreferencesStore = GeneralPreferencesStore(),
         contextLoader: (@Sendable (UUID) async throws -> WealthEditContext)? = nil,
         historyLoader: (@Sendable (UUID) async throws -> [WealthCorrectionHistory])? = nil,
         correctionWriter: (@Sendable (WealthCorrectionRequest) async throws -> WealthCorrectionResult)? = nil,
         valuationWriter: (@Sendable (WealthCurrentValuationRequest) async throws -> WealthCurrentValuationResult)? = nil) {
        self.store = store
        self.clock = clock
        self.timeZone = timeZone
        self.generalPreferences = generalPreferences
        self.contextLoader = contextLoader ?? { try await store.readWealthEditContext(id: $0) }
        self.historyLoader = historyLoader ?? { try await store.wealthCorrectionHistory(id: $0) }
        self.correctionWriter = correctionWriter ?? { try await store.correctWealthContainer($0) }
        self.valuationWriter = valuationWriter ?? { try await store.recordCurrentValuation($0) }
    }

    var selectedRecord: WealthContainer? {
        records.first { $0.id == selection }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reload()
    }

    func reload() async {
        loadState = .loading
        do {
            let values = try await store.fetchWealthContainers()
            records = values
            summary = try WealthValuation.aggregate(values)
            if let selection, !values.contains(where: { $0.id == selection }) {
                self.selection = nil
            }
            loadState = .ready
            persistenceErrorMessage = nil
        } catch {
            loadState = .failed
            persistenceErrorMessage = "Wealth data could not be loaded. The persistent store was not silently replaced."
        }
    }

    func beginAdd() {
        guard !isSaving else { return }
        clearEditSession()
        editorErrorMessage = nil
        editor = WealthEditorPresentation(targetID: nil, existing: nil,
            initialCurrency: generalPreferences.snapshot.newWealthCurrency)
    }

    func beginEdit() async {
        guard let selectedRecord else { return }
        await beginEdit(id: selectedRecord.id)
    }

    func beginEdit(id: UUID) async {
        guard !isSaving else { return }
        clearEditSession()
        let session = editSessionID
        editLoadState = .loading
        editorErrorMessage = nil
        editor = WealthEditorPresentation(targetID: id, existing: nil)
        do {
            let context = try await contextLoader(id)
            guard editSessionID == session, editor?.targetID == id else { return }
            editContext = context
            editor = WealthEditorPresentation(targetID: id, existing: context.record)
            editLoadState = .ready
        } catch {
            guard editSessionID == session, editor?.targetID == id else { return }
            editLoadState = .failed
            editFeedback = "This Container could not be loaded for editing. Close or reload it."
        }
    }

    func reloadEdit() async {
        guard let id = editor?.targetID, !isSaving else { return }
        await beginEdit(id: id)
    }

    func cancelEditor() {
        guard !isSaving else { return }
        clearEditSession()
        editor = nil
    }

    private func clearEditSession() {
        editSessionID = UUID()
        editContext = nil
        pendingCorrection = nil
        pendingDraft = nil
        pendingIntent = nil
        correctionReason = ""
        editIntent = .correction
        editFeedback = nil
        editLoadState = .idle
        requiresEditReload = false
        editorErrorMessage = nil
    }

    var canSaveEditor: Bool {
        guard !isSaving, editor != nil, !requiresEditReload else { return false }
        if editor?.targetID == nil { return true }
        return editLoadState == .ready
    }

    func needsCorrectionReason(_ draft: WealthEditorDraft) -> Bool {
        guard editIntent == .correction, let before = editContext?.record,
              let candidate = try? draft.makeEditCandidate(from: before,
                  today: before.container.updatedDate, commandTime: before.valuation.fetchedAt).0 else {
            return false
        }
        return !WealthCorrectionProjection(before)
            .hasSameImportantValues(as: WealthCorrectionProjection(candidate))
    }

    func save(_ draft: WealthEditorDraft) async {
        guard !isSaving, let editor, canSaveEditor else { return }
        do {
            let session = editSessionID
            if editor.targetID == nil {
                isSaving = true
                defer { isSaving = false }
                let now = clock.now()
                let record = try draft.makeRecord(existing: nil, today: civilDate(for: now), now: now)
                try await store.createWealthContainer(record)
                guard editSessionID == session else { return }
                await finishSuccessfulSave(selecting: record.id)
            } else {
                guard let context = editContext, editor.targetID == context.record.id else { return }
                if let pendingCorrection {
                    let effectiveReason = pendingCorrection.reason.isEmpty ? "" :
                        correctionReason.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard pendingDraft == draft, pendingIntent == editIntent,
                          effectiveReason == pendingCorrection.reason else {
                        requiresEditReload = true
                        editFeedback = "This draft differs from the pending request. Discard it and reload current data before a new request."
                        return
                    }
                    try await submitCorrection(pendingCorrection, session: session)
                } else {
                    let now = clock.now()
                    let today = try civilDate(for: now)
                    let (candidate, fxIntent) = try draft.makeEditCandidate(
                        from: context.record, today: today, commandTime: now)
                    switch editIntent {
                    case .correction:
                        let important = !WealthCorrectionProjection(context.record)
                            .hasSameImportantValues(as: WealthCorrectionProjection(candidate))
                        let reason = important ? try WealthCorrectionEncoding.reason(correctionReason) : ""
                        let request = WealthCorrectionRequest(candidate: candidate, expected: context.token,
                            operationID: UUID(), reason: reason, occurredAt: now, fxIntent: fxIntent)
                        if important {
                            pendingCorrection = request
                            pendingDraft = draft
                            pendingIntent = editIntent
                        }
                        try await submitCorrection(request, session: session, durable: important)
                    case .currentValuation:
                        let request = WealthCurrentValuationRequest(candidate: candidate,
                            expected: context.token, occurredAt: now, fxIntent: fxIntent)
                        isSaving = true
                        do {
                            _ = try await valuationWriter(request)
                            isSaving = false
                            guard editSessionID == session else { return }
                            await finishSuccessfulSave(selecting: candidate.id)
                        } catch {
                            isSaving = false
                            requiresEditReload = true
                            if let known = error as? WealthCorrectionError, known == .invalidRequest {
                                editorErrorMessage = "This valuation changes fields outside the current-value whitelist."
                            } else if error is WealthCorrectionError || error is WealthPersistenceError {
                                requiresEditReload = true
                                editFeedback = "Valuation was rejected or the object changed. Reload current data before retrying."
                            } else {
                                requiresEditReload = true
                                editFeedback = "Valuation status is unknown. Reload current data before another valuation; it has no durable retry receipt."
                            }
                        }
                    }
                }
            }
        } catch let error as WealthEditorError {
            editorErrorMessage = error.localizedDescription
        } catch is FinancialValueError {
            editorErrorMessage = "Validation failed: check amount, quantity, price, currency, and manual FX direction."
        } catch is WealthDomainError {
            editorErrorMessage = "Validation failed: the selected type and financial fields are inconsistent."
        } catch {
            editorErrorMessage = "The request was not prepared. Check its values and retry."
        }
    }

    private func submitCorrection(_ request: WealthCorrectionRequest, session: UUID,
                                  durable: Bool = true) async throws {
        isSaving = true
        editFeedback = nil
        do {
            let result = try await correctionWriter(request)
            isSaving = false
            guard editSessionID == session else { return }
            switch result {
            case .applied, .noChange, .minorUpdate, .alreadyApplied(_, .unchanged):
                await finishSuccessfulSave(selecting: request.candidate.id)
            case .alreadyApplied(_, .changed):
                requiresEditReload = true
                editFeedback = "The correction was saved, but this Container changed afterward. Reload current data."
            case .alreadyApplied(_, .deleted):
                requiresEditReload = true
                editFeedback = "The correction was saved, but this Container was later deleted. Reload current data."
            }
        } catch {
            isSaving = false
            switch error {
            case WealthCorrectionError.staleDraft, WealthPersistenceError.containerNotFound:
                requiresEditReload = true
                editFeedback = "This Container changed or was deleted. Your draft remains; discard it and reload current data."
            case WealthCorrectionError.operationConflict:
                requiresEditReload = true
                editFeedback = "This operation ID belongs to another request. Reload current data."
            case WealthCorrectionError.invalidRequest:
                editorErrorMessage = "This edit intent or its financial inputs are invalid. No new request was sent."
                pendingCorrection = nil
                pendingDraft = nil
                pendingIntent = nil
            case WealthCorrectionError.maintenanceUnavailable:
                editFeedback = durable ? "Maintenance is in progress. Retry the same request afterward."
                    : "Maintenance is in progress. Reload current data before retrying this non-durable edit."
                if !durable { requiresEditReload = true }
            default:
                if durable {
                    editFeedback = "Save status is unknown. Retry the same unchanged request, or explicitly discard and reload."
                } else {
                    requiresEditReload = true
                    editFeedback = "Save status is unknown. Reload current data before another minor edit; it has no durable retry receipt."
                }
            }
        }
    }

    private func finishSuccessfulSave(selecting id: UUID) async {
        clearEditSession()
        editor = nil
        selection = id
        await reload()
    }

    func showCorrectionHistory(id: UUID) async {
        historySessionID = UUID()
        let session = historySessionID
        historyTargetID = id
        correctionHistory = []
        historyLoadState = .loading
        do {
            let rows = try await historyLoader(id)
            guard historySessionID == session, historyTargetID == id else { return }
            correctionHistory = rows
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

    func requestDelete() async {
        guard let selectedRecord else { return }
        do {
            let impact = try await store.deletionImpact(for: selectedRecord.id)
            guard !impact.hasProtectedPermanentDependents else {
                pendingDeletion = nil
                deletionProtectionMessage = protectedDeletionMessage(impact)
                return
            }
            deletionProtectionMessage = nil
            pendingDeletion = WealthDeleteConfirmation(record: selectedRecord, impact: impact)
        } catch {
            persistenceErrorMessage = "Delete impact could not be read. Nothing was deleted."
        }
    }

    func confirmDelete(_ confirmation: WealthDeleteConfirmation) async {
        do {
            _ = try await store.deleteWealthContainer(id: confirmation.record.id)
            self.pendingDeletion = nil
            deletionProtectionMessage = nil
            selection = nil
            await reload()
        } catch WealthPersistenceError.protectedPermanentDependents {
            self.pendingDeletion = nil
            if let impact = try? await store.deletionImpact(for: confirmation.record.id) {
                deletionProtectionMessage = protectedDeletionMessage(impact)
            } else {
                deletionProtectionMessage = "This Container has protected permanent dependents and cannot be deleted."
            }
        } catch {
            self.pendingDeletion = nil
            persistenceErrorMessage = "The Container could not be deleted. No unrelated wealth record was changed."
        }
    }

    private func protectedDeletionMessage(_ impact: ContainerDeletionImpact) -> String {
        "Cannot delete this Container in Stage 3: "
            + "\(impact.linkedAssetCount) linked Asset record(s) and "
            + "\(impact.linkedInsurancePolicyCount) linked Insurance Policy record(s), and "
            + "\(impact.linkedLedgerPostingCount) linked Ledger posting(s) are protected. "
            + "No permanent record was deleted."
    }

    private func civilDate(for instant: UTCInstant) throws -> CivilDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: instant.date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            throw TimeValueError.invalidCivilDate
        }
        return try CivilDate(year: year, month: month, day: day)
    }
}
