import Foundation
import Observation

enum WealthLoadState: Equatable {
    case loading
    case ready
    case failed
}

struct WealthEditorPresentation: Identifiable, Equatable {
    let id = UUID()
    let existing: WealthContainer?
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

    var errorDescription: String? {
        switch self {
        case let .required(field): "\(field) is required."
        case let .invalidNumber(field): "\(field) must be a valid non-negative decimal value."
        case let .invalidDate(field): "\(field) must use YYYY-MM-DD and be a valid Gregorian date."
        case .invalidFX: "USD records require a positive manual USD → CNY rate."
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
    private(set) var records: [WealthContainer] = []
    private(set) var summary: WealthSummary = .zero
    private(set) var loadState: WealthLoadState = .loading
    var selection: UUID?
    var editor: WealthEditorPresentation?
    var pendingDeletion: WealthDeleteConfirmation?
    var editorErrorMessage: String?
    var persistenceErrorMessage: String?
    var deletionProtectionMessage: String?

    @ObservationIgnored private let store: WealthStore
    @ObservationIgnored private let clock: any Clock
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private var hasLoaded = false

    init(store: WealthStore, clock: any Clock, timeZone: TimeZone = .current) {
        self.store = store
        self.clock = clock
        self.timeZone = timeZone
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
        editorErrorMessage = nil
        editor = WealthEditorPresentation(existing: nil)
    }

    func beginEdit() {
        guard let selectedRecord else { return }
        editorErrorMessage = nil
        editor = WealthEditorPresentation(existing: selectedRecord)
    }

    func save(_ draft: WealthEditorDraft) async {
        guard let editor else { return }
        do {
            let now = clock.now()
            let today = try civilDate(for: now)
            let record = try draft.makeRecord(
                existing: editor.existing,
                today: today,
                now: now
            )
            if editor.existing == nil {
                try await store.createWealthContainer(record)
            } else {
                try await store.updateWealthContainer(record)
            }
            self.editor = nil
            editorErrorMessage = nil
            selection = record.id
            await reload()
        } catch let error as WealthEditorError {
            editorErrorMessage = error.localizedDescription
        } catch let error as LocalizedError where error.errorDescription != nil {
            editorErrorMessage = error.errorDescription
        } catch is FinancialValueError {
            editorErrorMessage = "Validation failed: check amount, quantity, price, currency, and manual FX direction."
        } catch is WealthDomainError {
            editorErrorMessage = "Validation failed: the selected type and financial fields are inconsistent."
        } catch {
            editorErrorMessage = "Persistence failed. No partial Container was saved."
        }
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
