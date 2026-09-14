import Foundation
import Observation

enum AnalyticsTerminalState: String, Equatable, Sendable {
    case idle
    case ready
    case calculating
    case calculated
    case empty
    case insufficientData
    case missingValuationBoundary
    case invalidRiskFreeRate
    case cancelled
    case arithmeticError
    case unavailable
}

/// Read-only Stage 9 presentation model. It owns no Store or Provider values and
/// deliberately has no automatic calculation path: every report begins with an
/// explicit user action.
@MainActor
@Observable
final class AnalyticsFeatureModel {
    static let localOnlyDisclosure =
        "Analytics use only local Portfolio activities and complete CNY NAV snapshots. No Provider request is made."
    static let observedPeriodDisclosure =
        "Monthly and annual returns describe observed complete valuation periods only; missing dates are never forward-filled."

    let mode: AppDataMode
    private(set) var state: AnalyticsTerminalState = .idle
    private(set) var portfolios: [PortfolioRecord] = []
    var selectedPortfolioID: UUID?
    var selectedRange: PortfolioAnalyticsRange = .maximum
    var annualRiskFreePercentText = "0"
    private(set) var report: PortfolioAnalyticsReport?
    private(set) var errorDisclosure: String?
    private(set) var calculationCount = 0

    private let store: WealthStore
    private var calculationTask: Task<Void, Never>?
    private var generation = UUID()

    init(store: WealthStore, mode: AppDataMode) {
        self.store = store
        self.mode = mode
    }

    var selectedPortfolio: PortfolioRecord? {
        portfolios.first { $0.id == selectedPortfolioID }
    }

    func start() async {
        calculationTask?.cancel()
        generation = UUID()
        report = nil
        do {
            portfolios = try await store.fetchPortfolios()
            selectedPortfolioID = selectedPortfolioID.flatMap { selected in
                portfolios.contains { $0.id == selected } ? selected : nil
            } ?? portfolios.first?.id
            state = portfolios.isEmpty ? .empty : .ready
            errorDisclosure = nil
        } catch {
            state = .unavailable
            errorDisclosure = "Local Portfolio definitions are unavailable. No analytics were calculated."
        }
    }

    func selectPortfolio(_ id: UUID?) {
        selectedPortfolioID = id
        invalidateForInputChange()
    }

    func selectRange(_ range: PortfolioAnalyticsRange) {
        selectedRange = range
        invalidateForInputChange()
    }

    func riskFreeInputChanged() {
        invalidateForInputChange()
    }

    func calculate() {
        calculationTask?.cancel()
        guard let portfolio = selectedPortfolio else {
            report = nil
            state = .empty
            errorDisclosure = "Select a local Portfolio before calculating."
            return
        }

        let operationGeneration = UUID()
        generation = operationGeneration
        report = nil
        errorDisclosure = nil
        state = .calculating
        let range = selectedRange
        let riskFreeText = annualRiskFreePercentText

        calculationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let annualRiskFreeRate = try Self.parseRiskFreePercent(riskFreeText)
                let activities = try await self.store.fetchPortfolioActivities(portfolioID: portfolio.id)
                var snapshots = try await self.store.fetchPortfolioNAVSnapshots(portfolioID: portfolio.id)
                if self.mode == .syntheticDemo,
                   let incomplete = Self.syntheticIncompleteSnapshot(for: portfolio, basedOn: snapshots.last) {
                    snapshots.append(incomplete)
                }
                let input = PortfolioAnalyticsInput(
                    portfolio: portfolio,
                    activities: activities,
                    snapshots: snapshots,
                    range: range,
                    annualRiskFreeRate: annualRiskFreeRate
                )
                let calculated = try await Task.detached(priority: .userInitiated) {
                    try PortfolioAnalyticsCalculator.calculate(input)
                }.value
                try Task.checkCancellation()
                guard self.generation == operationGeneration,
                      self.selectedPortfolioID == portfolio.id,
                      self.selectedRange == range,
                      self.annualRiskFreePercentText == riskFreeText else {
                    return
                }
                self.report = calculated
                self.calculationCount += 1
                self.state = .calculated
            } catch is CancellationError {
                guard self.generation == operationGeneration else { return }
                self.state = .cancelled
                self.errorDisclosure = "Calculation cancelled after an input changed. No stale result was shown."
            } catch let error as PortfolioAnalyticsError {
                guard self.generation == operationGeneration else { return }
                self.apply(error)
            } catch {
                guard self.generation == operationGeneration else { return }
                self.state = .unavailable
                self.errorDisclosure = "Analytics are unavailable because local typed inputs could not be loaded."
            }
        }
    }

    func cancelCalculation() {
        calculationTask?.cancel()
        generation = UUID()
        report = nil
        state = portfolios.isEmpty ? .empty : .cancelled
        errorDisclosure = "Calculation cancelled. No partial result was retained."
    }

    private func invalidateForInputChange() {
        calculationTask?.cancel()
        generation = UUID()
        report = nil
        state = portfolios.isEmpty ? .empty : .ready
        errorDisclosure = nil
    }

    private func apply(_ error: PortfolioAnalyticsError) {
        report = nil
        switch error {
        case .noCompleteSnapshots, .insufficientSnapshots:
            state = .insufficientData
            errorDisclosure = "Insufficient complete NAV snapshots for the selected range."
        case .missingValuationBoundary:
            state = .missingValuationBoundary
            errorDisclosure = "A capital-flow date has no complete NAV valuation boundary."
        case .invalidRiskFreeRate:
            state = .invalidRiskFreeRate
            errorDisclosure = "Risk-free rate must be a finite annual percentage greater than -100%."
        case .overflow, .underflow, .lossOfPrecision, .divisionByZero,
             .invalidScale, .invalidRoot, .invalidExponent:
            state = .arithmeticError
            errorDisclosure = "Checked Decimal arithmetic could not produce an authoritative result."
        case .cancelled, .staleGeneration:
            state = .cancelled
            errorDisclosure = "Calculation cancelled after an input changed. No stale result was shown."
        default:
            state = .unavailable
            errorDisclosure = "The selected local observations do not satisfy the metric contract."
        }
    }

    private static func parseRiskFreePercent(_ text: String) throws -> Decimal {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw PortfolioAnalyticsError.invalidRiskFreeRate }
        do {
            let percent = try FixedPointMath.parseCanonical(normalized)
            let annual = try AnalyticsDecimalMath.divide(percent, 100)
            guard annual > -1 else { throw PortfolioAnalyticsError.invalidRiskFreeRate }
            return annual
        } catch let error as PortfolioAnalyticsError {
            throw error
        } catch {
            throw PortfolioAnalyticsError.invalidRiskFreeRate
        }
    }

    private static func syntheticIncompleteSnapshot(
        for portfolio: PortfolioRecord,
        basedOn last: PortfolioNAVSnapshot?
    ) -> PortfolioNAVSnapshot? {
        guard let last else { return nil }
        return PortfolioNAVSnapshot(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000009099")!,
            portfolioID: portfolio.id,
            civilDate: last.civilDate,
            createdAt: last.createdAt,
            totalCNY: last.totalCNY,
            isComplete: false,
            items: []
        )
    }
}

/// Deterministic local-only Stage 9 demo assembly. It uses public Permanent
/// Store commands and stores only Portfolio activities and complete Portfolio
/// NAV snapshots. No Market Provider or session data participates.
enum SyntheticAnalyticsSeeder {
    private static let primaryPortfolioID = UUID(uuidString: "00000000-0000-4000-8000-000000008001")!
    private static let primaryLinkID = UUID(uuidString: "00000000-0000-4000-8000-000000008002")!
    private static let sparsePortfolioID = UUID(uuidString: "00000000-0000-4000-8000-000000009001")!
    private static let sparseLinkID = UUID(uuidString: "00000000-0000-4000-8000-000000009002")!
    private static let wealthContainerID = UUID(uuidString: "00000000-0000-4000-8000-000000003003")!
    private static let rateDecimal = Decimal(string: "7.125", locale: FixedPointMath.canonicalLocale)!
    private static let rate = try! FXRate(decimal: rateDecimal, sourceCurrency: .usd, targetCurrency: .cny)
    private static let recordedAt = UTCInstant(millisecondsSince1970: 1_768_435_200_000)

    static func seed(in store: WealthStore) async throws {
        let portfolios = try await store.fetchPortfolios()
        guard portfolios.contains(where: { $0.id == primaryPortfolioID }) else { return }

        let primaryActivities = try await store.fetchPortfolioActivities(portfolioID: primaryPortfolioID)
        if !primaryActivities.contains(where: { $0.id == UUID(uuidString: "00000000-0000-4000-8000-000000009010")! }) {
            try await seedPrimaryActivities(in: store)
        }
        if try await store.fetchPortfolioNAVSnapshots(portfolioID: primaryPortfolioID).isEmpty {
            try await seedRegularSnapshots(
                in: store,
                portfolioID: primaryPortfolioID,
                linkID: primaryLinkID,
                dates: dailyDates(from: "2025-12-20", through: "2026-01-15"),
                baseUSDCents: 50_000,
                stepUSDCents: 135
            )
        }

        if !portfolios.contains(where: { $0.id == sparsePortfolioID }) {
            try await seedSparsePortfolio(in: store)
        }
    }

    private static func seedPrimaryActivities(in store: WealthStore) async throws {
        let sellDate = try CivilDate(canonical: "2026-01-05")
        let gross = Money(minorUnits: 3_500, currency: .usd)
        let fee = Money(minorUnits: 50, currency: .usd)
        let net = try gross.subtracting(fee)
        let sellFX = try provenance(original: net, date: sellDate)
        let sell = try PortfolioActivity(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000009010")!,
            portfolioID: primaryPortfolioID,
            securityLinkID: primaryLinkID,
            civilDate: sellDate,
            recordedAt: UTCInstant(millisecondsSince1970: recordedAt.millisecondsSince1970 + 10),
            exchangeTimeZoneIdentifier: "America/New_York",
            payload: .sell(
                quantity: AssetQuantity(coefficient: 100_000_000),
                unitPrice: try MarketPrice(coefficient: 3_500_000_000, quoteCurrency: .usd),
                fee: fee,
                fx: sellFX
            )
        )
        try await store.createPortfolioActivity(sell)

        let split = try PortfolioActivity(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000009011")!,
            portfolioID: primaryPortfolioID,
            securityLinkID: primaryLinkID,
            civilDate: try CivilDate(canonical: "2026-01-08"),
            recordedAt: UTCInstant(millisecondsSince1970: recordedAt.millisecondsSince1970 + 11),
            exchangeTimeZoneIdentifier: "America/New_York",
            payload: .manualSplit(
                from: try Ratio(decimal: 1),
                to: try Ratio(decimal: 2)
            )
        )
        try await store.createPortfolioActivity(split)
    }

    private static func seedSparsePortfolio(in store: WealthStore) async throws {
        let portfolio = try PortfolioRecord(
            id: sparsePortfolioID,
            name: "Synthetic Sparse Portfolio",
            createdAt: recordedAt,
            updatedAt: recordedAt,
            sortOrder: 1
        )
        try await store.createPortfolio(portfolio)
        let link = try PortfolioSecurityLink(
            id: sparseLinkID,
            portfolioID: sparsePortfolioID,
            wealthContainerID: wealthContainerID,
            symbol: "SYNX",
            rawMIC: "XSYN",
            currency: .usd,
            assetKind: .stock,
            sortOrder: 0
        )
        try await store.linkPortfolioSecurity(link)

        let openingDate = try CivilDate(canonical: "2025-12-15")
        let openingCost = Money(minorUnits: 15_000, currency: .usd)
        try await store.createPortfolioActivity(try PortfolioActivity(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000009003")!,
            portfolioID: sparsePortfolioID,
            securityLinkID: sparseLinkID,
            civilDate: openingDate,
            recordedAt: recordedAt,
            exchangeTimeZoneIdentifier: "America/New_York",
            payload: .openingLot(
                quantity: AssetQuantity(coefficient: 500_000_000),
                totalCost: openingCost,
                fx: try provenance(original: openingCost, date: openingDate),
                note: "Synthetic sparse opening lot"
            )
        ))

        let sellDate = try CivilDate(canonical: "2025-12-28")
        let sellFee = Money(minorUnits: 25, currency: .usd)
        let sellGross = Money(minorUnits: 3_100, currency: .usd)
        let sellNet = try sellGross.subtracting(sellFee)
        try await store.createPortfolioActivity(try PortfolioActivity(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000009004")!,
            portfolioID: sparsePortfolioID,
            securityLinkID: sparseLinkID,
            civilDate: sellDate,
            recordedAt: UTCInstant(millisecondsSince1970: recordedAt.millisecondsSince1970 + 1),
            exchangeTimeZoneIdentifier: "America/New_York",
            payload: .sell(
                quantity: AssetQuantity(coefficient: 100_000_000),
                unitPrice: try MarketPrice(coefficient: 3_100_000_000, quoteCurrency: .usd),
                fee: sellFee,
                fx: try provenance(original: sellNet, date: sellDate)
            )
        ))

        let buyDate = try CivilDate(canonical: "2026-01-10")
        let buyFee = Money(minorUnits: 30, currency: .usd)
        let buyGross = Money(minorUnits: 3_300, currency: .usd)
        let buyTotal = try buyGross.adding(buyFee)
        try await store.createPortfolioActivity(try PortfolioActivity(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000009005")!,
            portfolioID: sparsePortfolioID,
            securityLinkID: sparseLinkID,
            civilDate: buyDate,
            recordedAt: UTCInstant(millisecondsSince1970: recordedAt.millisecondsSince1970 + 2),
            exchangeTimeZoneIdentifier: "America/New_York",
            payload: .buy(
                quantity: AssetQuantity(coefficient: 100_000_000),
                unitPrice: try MarketPrice(coefficient: 3_300_000_000, quoteCurrency: .usd),
                fee: buyFee,
                fx: try provenance(original: buyTotal, date: buyDate)
            )
        ))

        try await seedRegularSnapshots(
            in: store,
            portfolioID: sparsePortfolioID,
            linkID: sparseLinkID,
            dates: ["2025-12-20", "2025-12-28", "2026-01-10", "2026-02-28", "2026-04-01"].map(CivilDate.init(canonical:)),
            baseUSDCents: 22_000,
            stepUSDCents: -180
        )
    }

    private static func seedRegularSnapshots(
        in store: WealthStore,
        portfolioID: UUID,
        linkID: UUID,
        dates: [CivilDate],
        baseUSDCents: Int64,
        stepUSDCents: Int64
    ) async throws {
        for (index, date) in dates.enumerated() {
            let original = Money(
                minorUnits: baseUSDCents + Int64(index) * stepUSDCents,
                currency: .usd
            )
            let fx = try provenance(original: original, date: date)
            let snapshot = PortfolioNAVSnapshot(
                id: deterministicSnapshotID(portfolioID: portfolioID, index: index),
                portfolioID: portfolioID,
                civilDate: date,
                createdAt: UTCInstant(millisecondsSince1970: recordedAt.millisecondsSince1970 + Int64(100 + index)),
                totalCNY: fx.convertedCNY,
                isComplete: true,
                items: [PortfolioNAVSnapshotItem(
                    id: deterministicSnapshotItemID(portfolioID: portfolioID, index: index),
                    securityLinkID: linkID,
                    quantity: AssetQuantity(coefficient: 1_000_000_000),
                    manualMark: try MarketPrice(coefficient: 5_000_000_000, quoteCurrency: .usd),
                    originalMarketValue: original,
                    fx: fx,
                    convertedCNYValue: fx.convertedCNY,
                    remainingCNYBasis: Money(minorUnits: max(0, fx.convertedCNY.minorUnits - 5_000), currency: .cny),
                    reconciliation: .quantityMismatch
                )]
            )
            try await store.replacePortfolioNAVSnapshot(snapshot)
        }
    }

    private static func provenance(original: Money, date: CivilDate) throws -> PortfolioFXProvenance {
        try PortfolioFXProvenance(
            original: original,
            rate: rate,
            source: "manual.synthetic.stage9",
            referenceDate: date,
            recordedAt: recordedAt,
            isManual: true,
            isStale: false
        )
    }

    private static func dailyDates(from start: String, through end: String) throws -> [CivilDate] {
        let first = try CivilDate(canonical: start)
        let last = try CivilDate(canonical: end)
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard var current = calendar.date(from: DateComponents(year: first.year, month: first.month, day: first.day)),
              let final = calendar.date(from: DateComponents(year: last.year, month: last.month, day: last.day)) else {
            throw PortfolioAnalyticsError.invalidDateOrder
        }
        var result: [CivilDate] = []
        while current <= final {
            let components = calendar.dateComponents([.year, .month, .day], from: current)
            result.append(try CivilDate(year: components.year!, month: components.month!, day: components.day!))
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else {
                throw PortfolioAnalyticsError.invalidDateOrder
            }
            current = next
        }
        return result
    }

    private static func deterministicSnapshotID(portfolioID: UUID, index: Int) -> UUID {
        let prefix = portfolioID == primaryPortfolioID ? "8" : "9"
        return UUID(uuidString: String(format: "00000000-0000-4000-8000-00000000%@%03d", prefix, index))!
    }

    private static func deterministicSnapshotItemID(portfolioID: UUID, index: Int) -> UUID {
        let prefix = portfolioID == primaryPortfolioID ? "6" : "7"
        return UUID(uuidString: String(format: "00000000-0000-4000-8000-00000000%@%03d", prefix, index))!
    }
}
