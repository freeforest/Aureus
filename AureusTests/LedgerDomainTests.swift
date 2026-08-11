import Foundation
import Testing
@testable import Aureus

@Suite("Stage 4 ledger domain")
struct LedgerDomainTests {
    @Test("All eight kinds have explicit cash-flow semantics", arguments: TransactionKind.allCases)
    func allKinds(_ kind: TransactionKind) throws {
        let context = try LedgerTestContext.make()
        let entry = try context.entry(kind: kind)
        let summary = try LedgerCashFlow.summarize([entry])
        switch kind {
        case .income:
            #expect(summary.ordinaryInflowCNY.minorUnits == 10_000)
        case .expense:
            #expect(summary.ordinaryOutflowCNY.minorUnits == 10_000)
        case .dividend, .interest, .sell:
            #expect(summary.investmentInflowCNY.minorUnits == 10_000)
        case .fee, .buy:
            #expect(summary.investmentOutflowCNY.minorUnits == 10_000)
        case .transfer:
            #expect(summary.netCashFlowCNY.minorUnits == 0)
            #expect(summary.transferCount == 1)
        }
    }

    @Test("Transfer is neutral even when converted sides differ")
    func transferNeutrality() throws {
        let context = try LedgerTestContext.make()
        let transfer = try context.transfer(source: "100.00", target: "10.00", targetCurrency: .usd)
        let summary = try LedgerCashFlow.summarize([transfer])
        #expect(summary.ordinaryInflowCNY.minorUnits == 0)
        #expect(summary.ordinaryOutflowCNY.minorUnits == 0)
        #expect(summary.investmentInflowCNY.minorUnits == 0)
        #expect(summary.investmentOutflowCNY.minorUnits == 0)
        #expect(summary.netCashFlowCNY.minorUnits == 0)
        #expect(summary.transferCount == 1)
    }

    @Test("USD provenance is retained and invalid FX is rejected")
    func usdFX() throws {
        let context = try LedgerTestContext.make()
        let valuation = try context.valuation("10.00", currency: .usd)
        #expect(valuation.original == Money(minorUnits: 1_000, currency: .usd))
        #expect(valuation.rate.sourceCurrency == .usd)
        #expect(valuation.convertedCNY == Money(minorUnits: 7_000, currency: .cny))
        #expect(valuation.providerIdentifier == "manual.synthetic.stage4.tests")
        #expect(throws: LedgerDomainError.invalidUSDFX) {
            _ = try LedgerPosting(
                role: .primary, containerID: context.source.id,
                valuation: FXValuation(
                    original: Money(minorUnits: 1_000, currency: .usd),
                    rate: FXRate(decimal: FixedPointMath.parseCanonical("7.00"), sourceCurrency: .usd, targetCurrency: .cny), referenceDate: context.date,
                    fetchedAt: context.instant, providerIdentifier: "identity", isStale: false
                )
            )
        }
    }

    @Test("Fixed-point half-even and overflow remain authoritative")
    func fixedPointBoundaries() throws {
        #expect(try Money(decimal: FixedPointMath.parseCanonical("1.005"), currency: .cny).minorUnits == 100)
        #expect(try Money(decimal: FixedPointMath.parseCanonical("1.015"), currency: .cny).minorUnits == 102)
        let context = try LedgerTestContext.make()
        let huge = try LedgerEntry(
            kind: .income, civilDate: context.date, recordedAt: context.instant,
            description: "Synthetic Huge", postings: [try context.posting(Int64.max)]
        )
        #expect(throws: FinancialValueError.overflow) { try LedgerCashFlow.summarize([huge, huge]) }
    }

    @Test("Classification priority is deterministic and disabled rules are ignored")
    func deterministicRules() throws {
        let context = try LedgerTestContext.make()
        let category = Category(id: UUID(), parentID: nil, name: "Synthetic Food")
        let enabled = ClassificationRule(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, name: "Exact", priority: 1,
            isEnabled: true, matchMode: .exact, payeePattern: "Synthetic Cafe", kind: .expense,
            sourceContainerID: context.source.id, amountDirection: .outflow,
            resultCategory: category, resultTags: []
        )
        let disabled = ClassificationRule(
            id: UUID(), name: "Disabled", priority: 0, isEnabled: false, matchMode: .contains,
            payeePattern: "Synthetic", kind: nil, sourceContainerID: nil, amountDirection: nil,
            resultCategory: nil, resultTags: []
        )
        let input = ClassificationInput(payee: "Synthetic Cafe", description: "Synthetic Meal", kind: .expense, sourceContainerID: context.source.id)
        let first = DeterministicLedgerClassifier.classify(input, rules: [enabled, disabled])
        let second = DeterministicLedgerClassifier.classify(input, rules: [disabled, enabled])
        #expect(first == second)
        #expect(first?.category == category)
    }

    @Test("Classification rules require a condition and a result")
    func ruleValidation() throws {
        let empty = ClassificationRule(
            id: UUID(), name: "Synthetic Empty", priority: 1, isEnabled: true,
            matchMode: .contains, payeePattern: nil, kind: nil,
            sourceContainerID: nil, amountDirection: nil,
            resultCategory: nil, resultTags: []
        )
        #expect(throws: LedgerDomainError.ruleRequiresCondition) { try empty.validated() }
        let noResult = ClassificationRule(
            id: UUID(), name: "Synthetic No Result", priority: 1, isEnabled: true,
            matchMode: .contains, payeePattern: "Synthetic", kind: nil,
            sourceContainerID: nil, amountDirection: nil,
            resultCategory: nil, resultTags: []
        )
        #expect(throws: LedgerDomainError.ruleRequiresResult) { try noResult.validated() }
    }

    @Test("Category, tag, container, date, kind, and currency combine over one result set")
    func combinedFilterAndSummary() throws {
        let context = try LedgerTestContext.make()
        let category = Category(id: UUID(), parentID: nil, name: "Synthetic Filter")
        let tag = Tag(id: UUID(), name: "Synthetic Filter Tag")
        let base = try context.entry(kind: .income)
        let matching = try LedgerEntry(
            id: base.id, kind: base.kind, civilDate: base.civilDate, recordedAt: base.recordedAt,
            description: base.description, category: category, tags: [tag], postings: base.postings
        )
        let other = try context.entry(kind: .expense)
        let filter = LedgerFilter(
            kind: .income,
            categoryID: category.id,
            tagID: tag.id,
            containerID: context.source.id,
            currency: .cny,
            startDate: context.date,
            endDate: context.date
        )
        let visible = [matching, other].filter(filter.includes)
        #expect(visible.map(\.id) == [matching.id])
        #expect(try LedgerCashFlow.summarize(visible).ordinaryInflowCNY.minorUnits == 10_000)
        #expect(LedgerFilter(startDate: try CivilDate(canonical: "2026-08-12"), endDate: context.date).hasInvalidDateRange)
    }
}

struct LedgerTestContext {
    let source: WealthContainer
    let target: WealthContainer
    let date: CivilDate
    let instant: UTCInstant

    static func make() throws -> LedgerTestContext {
        let records = try SyntheticWealthSeeder.records()
        return LedgerTestContext(source: records[0], target: records[1], date: try CivilDate(canonical: "2026-08-11"), instant: UTCInstant(millisecondsSince1970: 1_786_387_200_000))
    }

    func valuation(_ amount: String, currency: CurrencyCode = .cny) throws -> FXValuation {
        let rate = currency == .cny ? FXRate.cnyIdentity : try FXRate(decimal: FixedPointMath.parseCanonical("7.00"), sourceCurrency: .usd, targetCurrency: .cny)
        return try FXValuation(
            original: try Money(decimal: FixedPointMath.parseCanonical(amount), currency: currency), rate: rate,
            referenceDate: date, fetchedAt: instant,
            providerIdentifier: currency == .cny ? "identity" : "manual.synthetic.stage4.tests",
            isManualOverride: currency == .usd, isStale: false
        )
    }

    func posting(_ minorUnits: Int64, role: LedgerPostingRole = .primary, containerID: UUID? = nil) throws -> LedgerPosting {
        try LedgerPosting(
            role: role, containerID: containerID ?? source.id,
            valuation: FXValuation(
                original: Money(minorUnits: minorUnits, currency: .cny), rate: .cnyIdentity,
                referenceDate: date, fetchedAt: instant, providerIdentifier: "identity", isStale: false
            )
        )
    }

    func entry(kind: TransactionKind, id: UUID = UUID(), description: String? = nil) throws -> LedgerEntry {
        if kind == .transfer { return try transfer() }
        return try LedgerEntry(
            id: id, kind: kind, civilDate: date, recordedAt: instant,
            description: description ?? "Synthetic \(kind.title)",
            postings: [try LedgerPosting(role: .primary, containerID: source.id, valuation: valuation("100.00"))]
        )
    }

    func transfer(source sourceAmount: String = "100.00", target targetAmount: String = "100.00", targetCurrency: CurrencyCode = .cny) throws -> LedgerEntry {
        try LedgerEntry(
            kind: .transfer, civilDate: date, recordedAt: instant, description: "Synthetic Transfer",
            postings: [
                try LedgerPosting(role: .transferSource, containerID: source.id, valuation: valuation(sourceAmount)),
                try LedgerPosting(role: .transferTarget, containerID: target.id, valuation: valuation(targetAmount, currency: targetCurrency))
            ]
        )
    }
}
