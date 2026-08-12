import Foundation
import Testing
@testable import Aureus

@Suite("Stage 5 Dashboard domain")
struct DashboardDomainTests {
    private let calendar = DashboardDateMath.gregorian(timeZone: TimeZone(identifier: "Asia/Shanghai")!)

    @Test("Complete Snapshot is self-contained and preserves USD FX provenance")
    func snapshotCapture() throws {
        let records = try SyntheticWealthSeeder.records()
        let date = try CivilDate(canonical: "2026-01-15")
        let snapshot = try DashboardSnapshot.capture(
            civilDate: date,
            createdAt: SyntheticWealthSeeder.demoInstant,
            records: records
        )
        let expectedSummary = try WealthValuation.aggregate(records)
        #expect(snapshot.summary == expectedSummary)
        #expect(snapshot.items.count == 7)
        #expect(snapshot.items.filter(\.isLiability).count == 1)
        let usd = try #require(snapshot.items.first { $0.originalValue.currency == .usd })
        #expect(usd.rate.sourceCurrency == .usd)
        #expect(usd.rate.targetCurrency == .cny)
        #expect(usd.fxSource == "manual.synthetic.stage3")
        #expect(usd.isManualFX)
        let reconverted = try usd.rate.convert(usd.originalValue)
        #expect(usd.convertedCNY == reconverted)
    }

    @Test("Allocation groups assets and excludes liabilities from denominator")
    func allocation() throws {
        let records = try SyntheticWealthSeeder.records()
        let slices = try DashboardCalculations.allocation(records: records)
        #expect(!slices.isEmpty)
        #expect(!slices.contains { $0.kind == .liability })
        let ratioTotal = slices.reduce(Decimal(0)) { $0 + $1.ratio.decimal }
        #expect(abs(ratioTotal - 1) < Decimal(string: "0.000000001")!)
        let expectedAssets = try WealthValuation.aggregate(records).totalAssetsCNY
        let allocated = try slices.reduce(Money(minorUnits: 0, currency: .cny)) {
            try $0.adding($1.amountCNY)
        }
        #expect(allocated == expectedAssets)
    }

    @Test("Sub-asset ratios use separate asset and liability sections")
    func subassets() throws {
        let records = try SyntheticWealthSeeder.records()
        let summary = try WealthValuation.aggregate(records)
        let values = try DashboardCalculations.subassets(records: records, summary: summary)
        #expect(values.count == records.count)
        let liability = try #require(values.first { $0.isLiability })
        #expect(liability.ratioWithinSection?.coefficient == 10_000_000_000)
        #expect(values.filter { !$0.isLiability }.allSatisfy { $0.ratioWithinSection != nil })
    }

    @Test("Change metrics use prior complete baselines and current wealth")
    func changeMetrics() throws {
        let snapshots = [
            try makeSnapshot(date: "2025-12-31", assets: 100_000, liabilities: 20_000),
            try makeSnapshot(date: "2026-01-04", assets: 110_000, liabilities: 20_000),
            try makeSnapshot(date: "2026-01-14", assets: 115_000, liabilities: 20_000),
            try makeSnapshot(date: "2026-01-16", assets: 500_000, liabilities: 0)
        ]
        let current = WealthSummary(
            totalAssetsCNY: Money(minorUnits: 130_000, currency: .cny),
            totalLiabilitiesCNY: Money(minorUnits: 25_000, currency: .cny),
            netWorthCNY: Money(minorUnits: 105_000, currency: .cny)
        )
        let metrics = try DashboardCalculations.changeMetrics(
            current: current,
            snapshots: snapshots,
            today: try CivilDate(canonical: "2026-01-15"),
            calendar: calendar
        )
        #expect(metrics.today.baselineDate?.description == "2026-01-14")
        #expect(metrics.today.absoluteChangeCNY?.minorUnits == 10_000)
        #expect(metrics.week.baselineDate?.description == "2026-01-04")
        #expect(metrics.month.baselineDate?.description == "2025-12-31")
        #expect(metrics.yearToDate.baselineDate?.description == "2025-12-31")
        #expect(metrics.historicalHighCNY == current.netWorthCNY)
    }

    @Test("Missing baseline is explicit and zero or negative baseline percentage is unavailable")
    func unavailablePercentage() throws {
        let zero = try makeSnapshot(date: "2026-01-01", assets: 10_000, liabilities: 10_000)
        let negative = try makeSnapshot(date: "2026-01-02", assets: 10_000, liabilities: 20_000)
        let current = WealthSummary(
            totalAssetsCNY: Money(minorUnits: 20_000, currency: .cny),
            totalLiabilitiesCNY: Money(minorUnits: 5_000, currency: .cny),
            netWorthCNY: Money(minorUnits: 15_000, currency: .cny)
        )
        let zeroMetric = try DashboardCalculations.changeMetrics(
            current: current,
            snapshots: [zero],
            today: try CivilDate(canonical: "2026-01-02"),
            calendar: calendar
        )
        #expect(zeroMetric.today.absoluteChangeCNY?.minorUnits == 15_000)
        #expect(zeroMetric.today.percentage == nil)
        let negativeMetric = try DashboardCalculations.changeMetrics(
            current: current,
            snapshots: [negative],
            today: try CivilDate(canonical: "2026-01-03"),
            calendar: calendar
        )
        #expect(negativeMetric.today.percentage == nil)
        #expect(negativeMetric.week == .insufficientHistory)
    }

    @Test("All nine frozen time ranges have stable boundaries", arguments: DashboardTimeRange.allCases)
    func timeRanges(_ range: DashboardTimeRange) throws {
        let reference = try CivilDate(canonical: "2026-03-01")
        let start = try range.startDate(reference: reference, calendar: calendar)
        switch range {
        case .oneDay: #expect(start?.description == "2026-03-01")
        case .oneWeek: #expect(start?.description == "2026-02-23")
        case .oneMonth: #expect(start?.description == "2026-02-01")
        case .threeMonths: #expect(start?.description == "2025-12-01")
        case .oneYear: #expect(start?.description == "2025-03-01")
        case .threeYears: #expect(start?.description == "2023-03-01")
        case .fiveYears: #expect(start?.description == "2021-03-01")
        case .yearToDate: #expect(start?.description == "2026-01-01")
        case .maximum: #expect(start == nil)
        }
    }

    @Test("Gregorian leap, month, year, and ISO Monday boundaries are explicit")
    func calendarBoundaries() throws {
        let leap = try DashboardDateMath.adding(
            .day,
            value: 1,
            to: CivilDate(canonical: "2024-02-28"),
            calendar: calendar
        )
        #expect(leap.description == "2024-02-29")
        #expect(try DashboardDateMath.adding(.day, value: 1, to: leap, calendar: calendar).description == "2024-03-01")
        #expect(try DashboardDateMath.adding(.day, value: 1, to: CivilDate(canonical: "2025-12-31"), calendar: calendar).description == "2026-01-01")
        #expect(try DashboardDateMath.mondayStart(of: CivilDate(canonical: "2026-01-15"), calendar: calendar).description == "2026-01-12")
    }

    @Test("History and heatmap preserve missing days instead of fabricating points")
    func missingDays() throws {
        let snapshots = [
            try makeSnapshot(date: "2026-01-01", assets: 100_000, liabilities: 20_000),
            try makeSnapshot(date: "2026-01-03", assets: 120_000, liabilities: 20_000)
        ]
        let history = try DashboardCalculations.history(
            snapshots: snapshots,
            range: .oneWeek,
            referenceDate: CivilDate(canonical: "2026-01-03"),
            calendar: calendar
        )
        #expect(history.map(\.civilDate.description) == ["2026-01-01", "2026-01-03"])
        let heatmap = try DashboardCalculations.netWorthHeatmap(
            snapshots: snapshots,
            range: .oneWeek,
            referenceDate: CivilDate(canonical: "2026-01-03"),
            calendar: calendar
        )
        #expect(heatmap.count == 7)
        #expect(heatmap.first { $0.civilDate.description == "2026-01-02" }?.valueCNY == nil)
        #expect(heatmap.first { $0.civilDate.description == "2026-01-03" }?.valueCNY?.minorUnits == 20_000)
    }

    @Test("Cash flow daily grouping preserves ordinary and investment semantics with neutral Transfer")
    func cashFlow() throws {
        let date = try CivilDate(canonical: "2026-01-15")
        let containerA = UUID()
        let containerB = UUID()
        let entries = try [
            makeLedger(kind: .income, amount: 10_000, date: date, container: containerA),
            makeLedger(kind: .expense, amount: 2_000, date: date, container: containerA),
            makeLedger(kind: .buy, amount: 3_000, date: date, container: containerA),
            makeLedger(kind: .sell, amount: 1_000, date: date, container: containerA),
            makeLedger(kind: .dividend, amount: 500, date: date, container: containerA),
            makeLedger(kind: .interest, amount: 300, date: date, container: containerA),
            makeLedger(kind: .fee, amount: 200, date: date, container: containerA),
            makeTransfer(amount: 50_000, date: date, source: containerA, target: containerB)
        ]
        let points = try DashboardCalculations.cashFlow(
            entries: entries,
            range: .oneDay,
            referenceDate: date,
            calendar: calendar
        )
        let point = try #require(points.first)
        #expect(point.ordinaryIncomeCNY.minorUnits == 10_000)
        #expect(point.ordinaryExpenseCNY.minorUnits == 2_000)
        #expect(point.netCashFlowCNY.minorUnits == 6_600)
        let heat = try DashboardCalculations.cashFlowHeatmap(
            points: points,
            mode: .netCashFlow,
            range: .oneDay,
            referenceDate: date,
            calendar: calendar
        )
        #expect(heat.first?.valueCNY?.minorUnits == 6_600)
    }

    @Test("Cash Flow accessibility summary uses checked fixed-point accumulation")
    func checkedCashFlowAccessibilitySummary() throws {
        let firstDate = try CivilDate(canonical: "2026-01-14")
        let secondDate = try CivilDate(canonical: "2026-01-15")
        let normal = [
            DashboardCashFlowPoint(
                civilDate: firstDate,
                ordinaryIncomeCNY: Money(minorUnits: 10_000, currency: .cny),
                ordinaryExpenseCNY: Money(minorUnits: 2_000, currency: .cny),
                netCashFlowCNY: Money(minorUnits: 8_000, currency: .cny)
            ),
            DashboardCashFlowPoint(
                civilDate: secondDate,
                ordinaryIncomeCNY: Money(minorUnits: 500, currency: .cny),
                ordinaryExpenseCNY: Money(minorUnits: 200, currency: .cny),
                netCashFlowCNY: Money(minorUnits: 300, currency: .cny)
            )
        ]
        let normalSummary = DashboardDisplay.cashFlowSummary(normal)
        #expect(normalSummary.contains("Ordinary Income CNY 105.00"))
        #expect(normalSummary.contains("Ordinary Expense CNY 22.00"))
        #expect(normalSummary.contains("Net Cash Flow CNY 83.00"))

        let overflowing = [
            DashboardCashFlowPoint(
                civilDate: firstDate,
                ordinaryIncomeCNY: Money(minorUnits: Int64.max, currency: .cny),
                ordinaryExpenseCNY: Money(minorUnits: Int64.max, currency: .cny),
                netCashFlowCNY: Money(minorUnits: Int64.max, currency: .cny)
            ),
            DashboardCashFlowPoint(
                civilDate: secondDate,
                ordinaryIncomeCNY: Money(minorUnits: 1, currency: .cny),
                ordinaryExpenseCNY: Money(minorUnits: -1, currency: .cny),
                netCashFlowCNY: Money(minorUnits: 1, currency: .cny)
            )
        ]
        #expect(
            DashboardDisplay.cashFlowSummary(overflowing)
                == "Cash flow summary unavailable because the CNY total exceeds the supported fixed-point range."
        )
    }

    private func makeSnapshot(date: String, assets: Int64, liabilities: Int64) throws -> DashboardSnapshot {
        let snapshotID = UUID()
        let civilDate = try CivilDate(canonical: date)
        let instant = UTCInstant(millisecondsSince1970: 1_700_000_000_000)
        let assetID = UUID()
        let liabilityID = UUID()
        let items = try [
            DashboardSnapshotItem(
                snapshotID: snapshotID,
                containerID: assetID,
                containerName: "Synthetic Snapshot Asset",
                containerKind: .bankCash,
                isLiability: false,
                originalValue: Money(minorUnits: assets, currency: .cny),
                rate: .cnyIdentity,
                convertedCNY: Money(minorUnits: assets, currency: .cny),
                fxSource: "identity",
                fxReferenceDate: civilDate,
                fxRecordedAt: instant,
                isManualFX: false,
                isStaleFX: false
            ),
            DashboardSnapshotItem(
                snapshotID: snapshotID,
                containerID: liabilityID,
                containerName: "Synthetic Snapshot Liability",
                containerKind: .liability,
                isLiability: true,
                originalValue: Money(minorUnits: liabilities, currency: .cny),
                rate: .cnyIdentity,
                convertedCNY: Money(minorUnits: liabilities, currency: .cny),
                fxSource: "identity",
                fxReferenceDate: civilDate,
                fxRecordedAt: instant,
                isManualFX: false,
                isStaleFX: false
            )
        ]
        return try DashboardSnapshot(
            id: snapshotID,
            civilDate: civilDate,
            createdAt: instant,
            summary: WealthSummary(
                totalAssetsCNY: Money(minorUnits: assets, currency: .cny),
                totalLiabilitiesCNY: Money(minorUnits: liabilities, currency: .cny),
                netWorthCNY: Money(minorUnits: assets - liabilities, currency: .cny)
            ),
            items: items
        )
    }

    private func makeLedger(
        kind: TransactionKind,
        amount: Int64,
        date: CivilDate,
        container: UUID
    ) throws -> LedgerEntry {
        let valuation = try identityValuation(amount: amount, date: date)
        return try LedgerEntry(
            kind: kind,
            civilDate: date,
            recordedAt: valuation.fetchedAt,
            description: "Synthetic Dashboard \(kind.title)",
            postings: [try LedgerPosting(role: .primary, containerID: container, valuation: valuation)]
        )
    }

    private func makeTransfer(
        amount: Int64,
        date: CivilDate,
        source: UUID,
        target: UUID
    ) throws -> LedgerEntry {
        let valuation = try identityValuation(amount: amount, date: date)
        return try LedgerEntry(
            kind: .transfer,
            civilDate: date,
            recordedAt: valuation.fetchedAt,
            description: "Synthetic Dashboard Transfer",
            postings: [
                try LedgerPosting(role: .transferSource, containerID: source, valuation: valuation),
                try LedgerPosting(role: .transferTarget, containerID: target, valuation: valuation)
            ]
        )
    }

    private func identityValuation(amount: Int64, date: CivilDate) throws -> FXValuation {
        try FXValuation(
            original: Money(minorUnits: amount, currency: .cny),
            rate: .cnyIdentity,
            referenceDate: date,
            fetchedAt: UTCInstant(millisecondsSince1970: 1_700_000_000_000),
            providerIdentifier: "identity",
            isManualOverride: false,
            isStale: false
        )
    }
}
