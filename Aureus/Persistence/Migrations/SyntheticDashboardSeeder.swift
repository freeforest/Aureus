import Foundation

enum SyntheticDashboardSeeder {
    private struct HistoryDefinition {
        let date: String
        let createdAtMS: Int64
        let assetBasisPoints: Int64
        let liabilityBasisPoints: Int64
    }

    static func seed(in store: WealthStore) async throws {
        try await seedSnapshots(in: store)
        try await seedHistoricalLedger(in: store)
    }

    private static func seedSnapshots(in store: WealthStore) async throws {
        let records = try SyntheticWealthSeeder.records()
        let history = [
            HistoryDefinition(date: "2025-01-02", createdAtMS: 1_735_776_000_000, assetBasisPoints: 7_800, liabilityBasisPoints: 10_500),
            HistoryDefinition(date: "2025-03-31", createdAtMS: 1_743_379_200_000, assetBasisPoints: 8_400, liabilityBasisPoints: 10_300),
            HistoryDefinition(date: "2025-07-15", createdAtMS: 1_752_537_600_000, assetBasisPoints: 8_000, liabilityBasisPoints: 10_700),
            HistoryDefinition(date: "2025-12-31", createdAtMS: 1_767_139_200_000, assetBasisPoints: 9_300, liabilityBasisPoints: 10_200),
            HistoryDefinition(date: "2026-01-05", createdAtMS: 1_767_571_200_000, assetBasisPoints: 8_900, liabilityBasisPoints: 11_000),
            HistoryDefinition(date: "2026-01-12", createdAtMS: 1_768_176_000_000, assetBasisPoints: 9_700, liabilityBasisPoints: 10_000),
            HistoryDefinition(date: "2026-01-15", createdAtMS: 1_768_435_200_000, assetBasisPoints: 10_000, liabilityBasisPoints: 10_000)
        ]

        for (historyIndex, definition) in history.enumerated() {
            let date = try CivilDate(canonical: definition.date)
            let snapshotID = deterministicUUID(5_000 + historyIndex * 100)
            var items: [DashboardSnapshotItem] = []
            var assets = Money(minorUnits: 0, currency: .cny)
            var liabilities = Money(minorUnits: 0, currency: .cny)

            for (recordIndex, record) in records.enumerated() {
                let basisPoints = record.isLiability
                    ? definition.liabilityBasisPoints
                    : definition.assetBasisPoints
                let original = Money(
                    minorUnits: try scaled(record.originalValue.minorUnits, basisPoints: basisPoints),
                    currency: record.originalValue.currency
                )
                let converted = try record.valuation.rate.convert(original)
                let item = try DashboardSnapshotItem(
                    id: deterministicUUID(5_001 + historyIndex * 100 + recordIndex),
                    snapshotID: snapshotID,
                    containerID: record.id,
                    containerName: record.container.name,
                    containerKind: record.container.kind,
                    isLiability: record.isLiability,
                    originalValue: original,
                    rate: record.valuation.rate,
                    convertedCNY: converted,
                    fxSource: record.valuation.providerIdentifier,
                    fxReferenceDate: date,
                    fxRecordedAt: UTCInstant(millisecondsSince1970: definition.createdAtMS),
                    isManualFX: record.valuation.isManualOverride,
                    isStaleFX: record.valuation.isStale
                )
                items.append(item)
                if record.isLiability {
                    liabilities = try liabilities.adding(converted)
                } else {
                    assets = try assets.adding(converted)
                }
            }

            let snapshot = try DashboardSnapshot(
                id: snapshotID,
                civilDate: date,
                createdAt: UTCInstant(millisecondsSince1970: definition.createdAtMS),
                summary: WealthSummary(
                    totalAssetsCNY: assets,
                    totalLiabilitiesCNY: liabilities,
                    netWorthCNY: try assets.subtracting(liabilities)
                ),
                items: items
            )
            try await store.insertSyntheticDashboardSnapshot(snapshot)
        }
    }

    private static func seedHistoricalLedger(in store: WealthStore) async throws {
        let existingIDs = Set(try await store.fetchLedgerEntries().map(\.id))
        let records = try await store.fetchWealthContainers()
        guard records.count >= 3 else { return }
        let categories = try await store.fetchCategories()
        let tags = try await store.fetchTags()
        let incomeCategory = categories.first { $0.name == "Synthetic Income" }
        let dailyCategory = categories.first { $0.name == "Synthetic Daily" }
        let demoTag = tags.first { $0.name == "synthetic-demo" }

        let definitions: [(Int, String, TransactionKind, Int64, Category?)] = [
            (5_801, "2025-03-31", .income, 250_000, incomeCategory),
            (5_802, "2025-07-15", .expense, 95_000, dailyCategory),
            (5_803, "2025-12-31", .buy, 120_000, nil),
            (5_804, "2026-01-05", .sell, 70_000, nil),
            (5_805, "2026-01-12", .dividend, 12_000, incomeCategory)
        ]
        for definition in definitions {
            let id = deterministicUUID(definition.0)
            guard !existingIDs.contains(id) else { continue }
            let date = try CivilDate(canonical: definition.1)
            let instant = UTCInstant(millisecondsSince1970: try syntheticNoon(date))
            let valuation = try FXValuation(
                original: Money(minorUnits: definition.3, currency: .cny),
                rate: .cnyIdentity,
                referenceDate: date,
                fetchedAt: instant,
                providerIdentifier: "identity",
                isManualOverride: false,
                isStale: false
            )
            try await store.createLedgerEntry(
                LedgerEntry(
                    id: id,
                    kind: definition.2,
                    civilDate: date,
                    recordedAt: instant,
                    description: "Synthetic Historical \(definition.2.title)",
                    category: definition.4,
                    tags: demoTag.map { [$0] } ?? [],
                    postings: [
                        try LedgerPosting(
                            role: .primary,
                            containerID: records[0].id,
                            valuation: valuation
                        )
                    ],
                    note: "Synthetic Stage 5 history only."
                )
            )
        }

        let transferID = deterministicUUID(5_806)
        if !existingIDs.contains(transferID) {
            let date = try CivilDate(canonical: "2026-01-10")
            let instant = UTCInstant(millisecondsSince1970: try syntheticNoon(date))
            let valuation = try FXValuation(
                original: Money(minorUnits: 50_000, currency: .cny),
                rate: .cnyIdentity,
                referenceDate: date,
                fetchedAt: instant,
                providerIdentifier: "identity",
                isManualOverride: false,
                isStale: false
            )
            try await store.createLedgerEntry(
                LedgerEntry(
                    id: transferID,
                    kind: .transfer,
                    civilDate: date,
                    recordedAt: instant,
                    description: "Synthetic Historical Transfer",
                    tags: demoTag.map { [$0] } ?? [],
                    postings: [
                        try LedgerPosting(role: .transferSource, containerID: records[0].id, valuation: valuation),
                        try LedgerPosting(role: .transferTarget, containerID: records[2].id, valuation: valuation)
                    ],
                    note: "Synthetic transfer remains net-neutral."
                )
            )
        }
    }

    private static func scaled(_ value: Int64, basisPoints: Int64) throws -> Int64 {
        let product = value.multipliedReportingOverflow(by: basisPoints)
        guard !product.overflow else { throw FinancialValueError.overflow }
        return product.partialValue / 10_000
    }

    private static func deterministicUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))!
    }

    private static func syntheticNoon(_ date: CivilDate) throws -> Int64 {
        let calendar = DashboardDateMath.gregorian(timeZone: TimeZone(secondsFromGMT: 0)!)
        return UTCInstant(date: try DashboardDateMath.date(date, calendar: calendar)).millisecondsSince1970
    }
}
