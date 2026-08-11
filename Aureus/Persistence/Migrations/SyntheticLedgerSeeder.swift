import Foundation

enum SyntheticLedgerSeeder {
    static func seed(in store: WealthStore) async throws {
        guard try await store.ledgerTransactionCount() == 0 else { return }
        let containers = try await store.fetchWealthContainers()
        guard containers.count >= 3 else { return }
        let incomeCategory = try await store.createCategory(name: "Synthetic Income", id: UUID(uuidString: "00000000-0000-4000-8000-000000004101")!)
        let dailyCategory = try await store.createCategory(name: "Synthetic Daily", id: UUID(uuidString: "00000000-0000-4000-8000-000000004102")!)
        let demoTag = try await store.createTag(name: "synthetic-demo", id: UUID(uuidString: "00000000-0000-4000-8000-000000004201")!)
        let date = try CivilDate(canonical: "2026-01-15")
        let instant = UTCInstant(millisecondsSince1970: 1_768_435_200_000)

        func valuation(_ amount: String, currency: CurrencyCode) throws -> FXValuation {
            let money = try Money(decimal: FixedPointMath.parseCanonical(amount), currency: currency)
            let rate = currency == .cny ? FXRate.cnyIdentity : try FXRate(decimal: FixedPointMath.parseCanonical("7.125"), sourceCurrency: .usd, targetCurrency: .cny)
            return try FXValuation(
                original: money, rate: rate, referenceDate: date, fetchedAt: instant,
                providerIdentifier: currency == .cny ? "identity" : "manual.synthetic.stage4",
                isManualOverride: currency == .usd, isStale: false
            )
        }

        let definitions: [(String, TransactionKind, String, CurrencyCode, WealthContainer, Category?)] = [
            ("00000000-0000-4000-8000-000000004001", .income, "5000.00", .cny, containers[0], incomeCategory),
            ("00000000-0000-4000-8000-000000004002", .expense, "800.00", .cny, containers[0], dailyCategory),
            ("00000000-0000-4000-8000-000000004003", .buy, "100.00", .usd, containers[1], nil),
            ("00000000-0000-4000-8000-000000004004", .sell, "20.00", .usd, containers[1], nil),
            ("00000000-0000-4000-8000-000000004005", .dividend, "10.00", .usd, containers[1], nil),
            ("00000000-0000-4000-8000-000000004006", .interest, "15.00", .cny, containers[0], incomeCategory),
            ("00000000-0000-4000-8000-000000004007", .fee, "5.00", .cny, containers[0], dailyCategory)
        ]
        for definition in definitions {
            let entry = try LedgerEntry(
                id: UUID(uuidString: definition.0)!, kind: definition.1,
                civilDate: date, recordedAt: instant,
                description: "Synthetic \(definition.1.title)", category: definition.5,
                tags: [demoTag],
                postings: [try LedgerPosting(role: .primary, containerID: definition.4.id, valuation: valuation(definition.2, currency: definition.3))],
                note: "Synthetic demonstration transaction only."
            )
            try await store.createLedgerEntry(entry)
        }
        let transfer = try LedgerEntry(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000004008")!,
            kind: .transfer, civilDate: date, recordedAt: instant,
            description: "Synthetic Internal Transfer", tags: [demoTag],
            postings: [
                try LedgerPosting(role: .transferSource, containerID: containers[0].id, valuation: valuation("100.00", currency: .cny)),
                try LedgerPosting(role: .transferTarget, containerID: containers[2].id, valuation: valuation("100.00", currency: .cny))
            ], note: "Synthetic transfer excluded from cash flow."
        )
        try await store.createLedgerEntry(transfer)
        try await store.createClassificationRule(ClassificationRule(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000004301")!,
            name: "Synthetic exact payee rule", priority: 10, isEnabled: true,
            matchMode: .exact, payeePattern: "Synthetic Payee", kind: .expense,
            sourceContainerID: nil, amountDirection: .outflow,
            resultCategory: dailyCategory, resultTags: [demoTag]
        ))
    }
}
