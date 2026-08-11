import Foundation

enum LedgerDomainError: Error, Equatable, Sendable {
    case emptyDescription
    case invalidPostingCount
    case invalidPostingRole
    case duplicatePostingRole
    case sameTransferContainer
    case nonPositiveAmount
    case invalidCNYIdentity
    case invalidUSDFX
    case categoryNotAllowedForTransfer
    case duplicateTag
    case invalidName
    case ruleRequiresCondition
    case ruleRequiresResult
    case overflow
}

enum LedgerPostingRole: String, Codable, CaseIterable, Equatable, Sendable {
    case primary
    case transferSource
    case transferTarget
}

enum LedgerAmountDirection: String, Codable, CaseIterable, Equatable, Sendable {
    case inflow
    case outflow
}

extension TransactionKind {
    var title: String {
        switch self {
        case .income: "Income"
        case .expense: "Expense"
        case .transfer: "Transfer"
        case .buy: "Buy"
        case .sell: "Sell"
        case .dividend: "Dividend"
        case .interest: "Interest"
        case .fee: "Fee"
        }
    }

    var amountDirection: LedgerAmountDirection? {
        switch self {
        case .income, .sell, .dividend, .interest: .inflow
        case .expense, .buy, .fee: .outflow
        case .transfer: nil
        }
    }
}

struct LedgerPosting: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let role: LedgerPostingRole
    let containerID: UUID
    let valuation: FXValuation

    init(id: UUID = UUID(), role: LedgerPostingRole, containerID: UUID, valuation: FXValuation) throws {
        guard valuation.original.minorUnits > 0 else { throw LedgerDomainError.nonPositiveAmount }
        try Self.validate(valuation)
        self.id = id
        self.role = role
        self.containerID = containerID
        self.valuation = valuation
    }

    private static func validate(_ valuation: FXValuation) throws {
        switch valuation.original.currency {
        case .cny:
            guard valuation.rate == .cnyIdentity,
                  valuation.convertedCNY == valuation.original,
                  valuation.providerIdentifier == "identity",
                  !valuation.isManualOverride else {
                throw LedgerDomainError.invalidCNYIdentity
            }
        case .usd:
            guard valuation.rate.sourceCurrency == .usd,
                  valuation.rate.targetCurrency == .cny,
                  valuation.rate.coefficient > 0,
                  valuation.isManualOverride,
                  valuation.providerIdentifier.localizedCaseInsensitiveContains("manual") else {
                throw LedgerDomainError.invalidUSDFX
            }
        }
    }
}

struct LedgerEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: TransactionKind
    let civilDate: CivilDate
    let recordedAt: UTCInstant
    let description: String
    let payee: String?
    let category: Category?
    let tags: [Tag]
    let postings: [LedgerPosting]
    let note: String?
    let importFingerprint: String?

    init(
        id: UUID = UUID(),
        kind: TransactionKind,
        civilDate: CivilDate,
        recordedAt: UTCInstant,
        description: String,
        payee: String? = nil,
        category: Category? = nil,
        tags: [Tag] = [],
        postings: [LedgerPosting],
        note: String? = nil,
        importFingerprint: String? = nil
    ) throws {
        let normalizedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDescription.isEmpty else { throw LedgerDomainError.emptyDescription }
        guard Set(tags.map(\.id)).count == tags.count else { throw LedgerDomainError.duplicateTag }

        if kind == .transfer {
            guard category == nil else { throw LedgerDomainError.categoryNotAllowedForTransfer }
            guard postings.count == 2 else { throw LedgerDomainError.invalidPostingCount }
            let grouped = Dictionary(grouping: postings, by: \.role)
            guard grouped[.transferSource]?.count == 1,
                  grouped[.transferTarget]?.count == 1,
                  grouped[.primary] == nil else {
                throw LedgerDomainError.invalidPostingRole
            }
            guard grouped[.transferSource]![0].containerID != grouped[.transferTarget]![0].containerID else {
                throw LedgerDomainError.sameTransferContainer
            }
        } else {
            guard postings.count == 1 else { throw LedgerDomainError.invalidPostingCount }
            guard postings[0].role == .primary else { throw LedgerDomainError.invalidPostingRole }
        }

        self.id = id
        self.kind = kind
        self.civilDate = civilDate
        self.recordedAt = recordedAt
        self.description = normalizedDescription
        self.payee = Self.normalizedOptional(payee)
        self.category = category
        self.tags = tags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.postings = postings
        self.note = Self.normalizedOptional(note)
        self.importFingerprint = importFingerprint
    }

    var primaryPosting: LedgerPosting? { postings.first { $0.role == .primary } }
    var transferSource: LedgerPosting? { postings.first { $0.role == .transferSource } }
    var transferTarget: LedgerPosting? { postings.first { $0.role == .transferTarget } }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

struct CashFlowSummary: Equatable, Sendable {
    let ordinaryInflowCNY: Money
    let ordinaryOutflowCNY: Money
    let investmentInflowCNY: Money
    let investmentOutflowCNY: Money
    let netCashFlowCNY: Money
    let transferSourceAmountCNY: Money
    let transferCount: Int

    static let zero = CashFlowSummary(
        ordinaryInflowCNY: Money(minorUnits: 0, currency: .cny),
        ordinaryOutflowCNY: Money(minorUnits: 0, currency: .cny),
        investmentInflowCNY: Money(minorUnits: 0, currency: .cny),
        investmentOutflowCNY: Money(minorUnits: 0, currency: .cny),
        netCashFlowCNY: Money(minorUnits: 0, currency: .cny),
        transferSourceAmountCNY: Money(minorUnits: 0, currency: .cny),
        transferCount: 0
    )
}

enum LedgerCashFlow {
    static func summarize(_ entries: [LedgerEntry]) throws -> CashFlowSummary {
        var ordinaryInflow = Money(minorUnits: 0, currency: .cny)
        var ordinaryOutflow = Money(minorUnits: 0, currency: .cny)
        var investmentInflow = Money(minorUnits: 0, currency: .cny)
        var investmentOutflow = Money(minorUnits: 0, currency: .cny)
        var transferAmount = Money(minorUnits: 0, currency: .cny)
        var transferCount = 0

        for entry in entries {
            switch entry.kind {
            case .income:
                ordinaryInflow = try ordinaryInflow.adding(try requiredPrimary(entry).valuation.convertedCNY)
            case .expense:
                ordinaryOutflow = try ordinaryOutflow.adding(try requiredPrimary(entry).valuation.convertedCNY)
            case .dividend, .interest, .sell:
                investmentInflow = try investmentInflow.adding(try requiredPrimary(entry).valuation.convertedCNY)
            case .fee, .buy:
                investmentOutflow = try investmentOutflow.adding(try requiredPrimary(entry).valuation.convertedCNY)
            case .transfer:
                guard let source = entry.transferSource else { throw LedgerDomainError.invalidPostingCount }
                transferAmount = try transferAmount.adding(source.valuation.convertedCNY)
                transferCount += 1
            }
        }

        let inflows = try ordinaryInflow.adding(investmentInflow)
        let outflows = try ordinaryOutflow.adding(investmentOutflow)
        return CashFlowSummary(
            ordinaryInflowCNY: ordinaryInflow,
            ordinaryOutflowCNY: ordinaryOutflow,
            investmentInflowCNY: investmentInflow,
            investmentOutflowCNY: investmentOutflow,
            netCashFlowCNY: try inflows.subtracting(outflows),
            transferSourceAmountCNY: transferAmount,
            transferCount: transferCount
        )
    }

    private static func requiredPrimary(_ entry: LedgerEntry) throws -> LedgerPosting {
        guard let posting = entry.primaryPosting else { throw LedgerDomainError.invalidPostingCount }
        return posting
    }
}

struct LedgerFilter: Equatable, Sendable {
    var kind: TransactionKind?
    var categoryID: UUID?
    var tagID: UUID?
    var containerID: UUID?
    var currency: CurrencyCode?
    var startDate: CivilDate?
    var endDate: CivilDate?

    static let all = LedgerFilter()

    var hasInvalidDateRange: Bool {
        guard let startDate, let endDate else { return false }
        return endDate < startDate
    }

    func includes(_ entry: LedgerEntry) -> Bool {
        if let kind, entry.kind != kind { return false }
        if let categoryID, entry.category?.id != categoryID { return false }
        if let tagID, !entry.tags.contains(where: { $0.id == tagID }) { return false }
        if let containerID, !entry.postings.contains(where: { $0.containerID == containerID }) { return false }
        if let currency, !entry.postings.contains(where: { $0.valuation.original.currency == currency }) { return false }
        if let startDate, entry.civilDate < startDate { return false }
        if let endDate, endDate < entry.civilDate { return false }
        return true
    }
}

enum ClassificationMatchMode: String, Codable, CaseIterable, Equatable, Sendable {
    case exact
    case contains
}

struct ClassificationRule: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let priority: Int
    let isEnabled: Bool
    let matchMode: ClassificationMatchMode
    let payeePattern: String?
    let kind: TransactionKind?
    let sourceContainerID: UUID?
    let amountDirection: LedgerAmountDirection?
    let resultCategory: Category?
    let resultTags: [Tag]

    func validated() throws -> ClassificationRule {
        let normalizedName = try LedgerNameNormalization.displayName(name)
        let normalizedPattern = try payeePattern.map(LedgerNameNormalization.displayName)
        guard normalizedPattern != nil || kind != nil || sourceContainerID != nil || amountDirection != nil else {
            throw LedgerDomainError.ruleRequiresCondition
        }
        guard resultCategory != nil || !resultTags.isEmpty else {
            throw LedgerDomainError.ruleRequiresResult
        }
        guard Set(resultTags.map(\.id)).count == resultTags.count else {
            throw LedgerDomainError.duplicateTag
        }
        return ClassificationRule(
            id: id,
            name: normalizedName,
            priority: priority,
            isEnabled: isEnabled,
            matchMode: matchMode,
            payeePattern: normalizedPattern,
            kind: kind,
            sourceContainerID: sourceContainerID,
            amountDirection: amountDirection,
            resultCategory: resultCategory,
            resultTags: resultTags.sorted { $0.id.uuidString < $1.id.uuidString }
        )
    }
}

struct ClassificationInput: Equatable, Sendable {
    let payee: String?
    let description: String
    let kind: TransactionKind
    let sourceContainerID: UUID
}

struct ClassificationResult: Equatable, Sendable {
    let ruleID: UUID
    let category: Category?
    let tags: [Tag]
}

enum DeterministicLedgerClassifier {
    static func classify(
        _ input: ClassificationInput,
        rules: [ClassificationRule]
    ) -> ClassificationResult? {
        let ordered = rules
            .filter(\.isEnabled)
            .sorted { lhs, rhs in
                lhs.priority == rhs.priority
                    ? lhs.id.uuidString < rhs.id.uuidString
                    : lhs.priority < rhs.priority
            }
        for rule in ordered where matches(rule, input: input) {
            return ClassificationResult(
                ruleID: rule.id,
                category: rule.resultCategory,
                tags: rule.resultTags
            )
        }
        return nil
    }

    private static func matches(_ rule: ClassificationRule, input: ClassificationInput) -> Bool {
        if let kind = rule.kind, kind != input.kind { return false }
        if let source = rule.sourceContainerID, source != input.sourceContainerID { return false }
        if let direction = rule.amountDirection, direction != input.kind.amountDirection { return false }
        if let pattern = rule.payeePattern {
            let candidate = (input.payee ?? input.description).folding(
                options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
            )
            let normalizedPattern = pattern.folding(
                options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
            )
            switch rule.matchMode {
            case .exact where candidate != normalizedPattern: return false
            case .contains where !candidate.contains(normalizedPattern): return false
            default: break
            }
        }
        return true
    }
}

enum LedgerNameNormalization {
    static func displayName(_ raw: String) throws -> String {
        let canonical = raw.precomposedStringWithCanonicalMapping
        let pieces = canonical.split(whereSeparator: \.isWhitespace)
        let value = pieces.joined(separator: " ")
        guard !value.isEmpty else { throw LedgerDomainError.invalidName }
        return value
    }

    static func key(_ raw: String) throws -> String {
        try displayName(raw).folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).precomposedStringWithCanonicalMapping
    }
}
