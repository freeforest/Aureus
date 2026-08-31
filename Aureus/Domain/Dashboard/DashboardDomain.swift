import Foundation

enum DashboardDomainError: Error, Equatable, Sendable {
    case corruptSnapshot
    case emptySnapshot
    case invalidItem
    case invalidDateRange
    case invalidGoalProjection
}

enum DashboardSnapshotStatus: String, Codable, Equatable, Sendable {
    case complete
    case legacyIncomplete
}

struct DashboardSnapshotItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let snapshotID: UUID
    let containerID: UUID
    let containerName: String
    let containerKind: AssetContainerKind
    let isLiability: Bool
    let originalValue: Money
    let rate: FXRate
    let convertedCNY: Money
    let fxSource: String
    let fxReferenceDate: CivilDate
    let fxRecordedAt: UTCInstant
    let isManualFX: Bool
    let isStaleFX: Bool

    init(
        id: UUID = UUID(),
        snapshotID: UUID,
        containerID: UUID,
        containerName: String,
        containerKind: AssetContainerKind,
        isLiability: Bool,
        originalValue: Money,
        rate: FXRate,
        convertedCNY: Money,
        fxSource: String,
        fxReferenceDate: CivilDate,
        fxRecordedAt: UTCInstant,
        isManualFX: Bool,
        isStaleFX: Bool
    ) throws {
        let name = containerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = fxSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !source.isEmpty,
              isLiability == (containerKind == .liability),
              originalValue.minorUnits >= 0,
              convertedCNY.currency == .cny,
              convertedCNY.minorUnits >= 0,
              rate.sourceCurrency == originalValue.currency,
              rate.targetCurrency == .cny,
              try rate.convert(originalValue) == convertedCNY else {
            throw DashboardDomainError.invalidItem
        }
        self.id = id
        self.snapshotID = snapshotID
        self.containerID = containerID
        self.containerName = name
        self.containerKind = containerKind
        self.isLiability = isLiability
        self.originalValue = originalValue
        self.rate = rate
        self.convertedCNY = convertedCNY
        self.fxSource = source
        self.fxReferenceDate = fxReferenceDate
        self.fxRecordedAt = fxRecordedAt
        self.isManualFX = isManualFX
        self.isStaleFX = isStaleFX
    }
}

struct DashboardSnapshot: Identifiable, Equatable, Sendable {
    static let captureSchema = "aureus.dashboard.snapshot.v1"

    let id: UUID
    let civilDate: CivilDate
    let createdAt: UTCInstant
    let summary: WealthSummary
    let status: DashboardSnapshotStatus
    let isComplete: Bool
    let items: [DashboardSnapshotItem]

    init(
        id: UUID,
        civilDate: CivilDate,
        createdAt: UTCInstant,
        summary: WealthSummary,
        status: DashboardSnapshotStatus = .complete,
        isComplete: Bool = true,
        items: [DashboardSnapshotItem]
    ) throws {
        guard status == .complete, isComplete, !items.isEmpty else {
            throw DashboardDomainError.corruptSnapshot
        }
        var assets = Money(minorUnits: 0, currency: .cny)
        var liabilities = Money(minorUnits: 0, currency: .cny)
        for item in items {
            guard item.snapshotID == id else { throw DashboardDomainError.corruptSnapshot }
            if item.isLiability {
                liabilities = try liabilities.adding(item.convertedCNY)
            } else {
                assets = try assets.adding(item.convertedCNY)
            }
        }
        let calculated = WealthSummary(
            totalAssetsCNY: assets,
            totalLiabilitiesCNY: liabilities,
            netWorthCNY: try assets.subtracting(liabilities)
        )
        guard calculated == summary else { throw DashboardDomainError.corruptSnapshot }
        self.id = id
        self.civilDate = civilDate
        self.createdAt = createdAt
        self.summary = summary
        self.status = status
        self.isComplete = isComplete
        self.items = items.sorted {
            $0.containerID.uuidString < $1.containerID.uuidString
        }
    }

    static func capture(
        id: UUID = UUID(),
        civilDate: CivilDate,
        createdAt: UTCInstant,
        records: [WealthContainer],
        itemIDs: [UUID]? = nil
    ) throws -> DashboardSnapshot {
        guard !records.isEmpty else { throw DashboardDomainError.emptySnapshot }
        if let itemIDs, itemIDs.count != records.count {
            throw DashboardDomainError.invalidItem
        }
        let items = try records.enumerated().map { index, record in
            try DashboardSnapshotItem(
                id: itemIDs?[index] ?? UUID(),
                snapshotID: id,
                containerID: record.id,
                containerName: record.container.name,
                containerKind: record.container.kind,
                isLiability: record.isLiability,
                originalValue: record.originalValue,
                rate: record.valuation.rate,
                convertedCNY: record.convertedCNYValue,
                fxSource: record.valuation.providerIdentifier,
                fxReferenceDate: record.valuation.referenceDate,
                fxRecordedAt: record.valuation.fetchedAt,
                isManualFX: record.valuation.isManualOverride,
                isStaleFX: record.valuation.isStale
            )
        }
        return try DashboardSnapshot(
            id: id,
            civilDate: civilDate,
            createdAt: createdAt,
            summary: try WealthValuation.aggregate(records),
            items: items
        )
    }
}

enum DashboardTimeRange: String, CaseIterable, Identifiable, Sendable {
    case oneDay = "1D"
    case oneWeek = "1W"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case oneYear = "1Y"
    case threeYears = "3Y"
    case fiveYears = "5Y"
    case yearToDate = "YTD"
    case maximum = "MAX"

    var id: String { rawValue }

    func startDate(reference: CivilDate, calendar: Calendar) throws -> CivilDate? {
        switch self {
        case .oneDay:
            return reference
        case .oneWeek:
            return try DashboardDateMath.adding(.day, value: -6, to: reference, calendar: calendar)
        case .oneMonth:
            return try DashboardDateMath.adding(.month, value: -1, to: reference, calendar: calendar)
        case .threeMonths:
            return try DashboardDateMath.adding(.month, value: -3, to: reference, calendar: calendar)
        case .oneYear:
            return try DashboardDateMath.adding(.year, value: -1, to: reference, calendar: calendar)
        case .threeYears:
            return try DashboardDateMath.adding(.year, value: -3, to: reference, calendar: calendar)
        case .fiveYears:
            return try DashboardDateMath.adding(.year, value: -5, to: reference, calendar: calendar)
        case .yearToDate:
            return try CivilDate(year: reference.year, month: 1, day: 1)
        case .maximum:
            return nil
        }
    }
}

enum DashboardDateMath {
    static func gregorian(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func date(_ civilDate: CivilDate, calendar: Calendar) throws -> Date {
        guard let value = calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: civilDate.year,
                month: civilDate.month,
                day: civilDate.day,
                hour: 12
            )
        ) else {
            throw TimeValueError.invalidCivilDate
        }
        return value
    }

    static func civilDate(_ date: Date, calendar: Calendar) throws -> CivilDate {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            throw TimeValueError.invalidCivilDate
        }
        return try CivilDate(year: year, month: month, day: day)
    }

    static func adding(
        _ component: Calendar.Component,
        value: Int,
        to civilDate: CivilDate,
        calendar: Calendar
    ) throws -> CivilDate {
        let date = try date(civilDate, calendar: calendar)
        guard let result = calendar.date(byAdding: component, value: value, to: date) else {
            throw TimeValueError.invalidCivilDate
        }
        return try self.civilDate(result, calendar: calendar)
    }

    static func mondayStart(of date: CivilDate, calendar: Calendar) throws -> CivilDate {
        let value = try self.date(date, calendar: calendar)
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: value) else {
            throw TimeValueError.invalidCivilDate
        }
        return try civilDate(interval.start, calendar: calendar)
    }

    static func dates(from start: CivilDate, through end: CivilDate, calendar: Calendar) throws -> [CivilDate] {
        guard start <= end else { throw DashboardDomainError.invalidDateRange }
        var result: [CivilDate] = []
        var current = start
        while current <= end {
            result.append(current)
            current = try adding(.day, value: 1, to: current, calendar: calendar)
        }
        return result
    }
}

struct DashboardChangeMetric: Equatable, Sendable {
    let baselineDate: CivilDate?
    let absoluteChangeCNY: Money?
    let percentage: Ratio?

    static let insufficientHistory = DashboardChangeMetric(
        baselineDate: nil,
        absoluteChangeCNY: nil,
        percentage: nil
    )

    var hasBaseline: Bool { baselineDate != nil && absoluteChangeCNY != nil }
}

struct DashboardChangeMetrics: Equatable, Sendable {
    let today: DashboardChangeMetric
    let week: DashboardChangeMetric
    let month: DashboardChangeMetric
    let yearToDate: DashboardChangeMetric
    let historicalHighCNY: Money
}

struct DashboardHistoryPoint: Identifiable, Equatable, Sendable {
    var id: UUID { snapshotID }
    let snapshotID: UUID
    let civilDate: CivilDate
    let totalAssetsCNY: Money
    let totalLiabilitiesCNY: Money
    let netWorthCNY: Money
}

struct DashboardAllocationSlice: Identifiable, Equatable, Sendable {
    var id: AssetContainerKind { kind }
    let kind: AssetContainerKind
    let amountCNY: Money
    let ratio: Ratio
}

struct DashboardSubassetValue: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let kind: AssetContainerKind
    let isLiability: Bool
    let amountCNY: Money
    let ratioWithinSection: Ratio?
}

struct DashboardCashFlowPoint: Identifiable, Equatable, Sendable {
    var id: CivilDate { civilDate }
    let civilDate: CivilDate
    let ordinaryIncomeCNY: Money
    let ordinaryExpenseCNY: Money
    let netCashFlowCNY: Money
}

enum DashboardGoalProgressUnavailableReason: Equatable, Sendable {
    case targetCurrencyUnsupportedForCNYProgress
    case currentCNYNetWorthUnavailable
}

enum DashboardGoalProgressState: Equatable, Sendable {
    case available(GoalProgress)
    case unavailable(DashboardGoalProgressUnavailableReason)
}

struct DashboardGoalProjection: Identifiable, Equatable, Sendable {
    var id: UUID { goal.id }

    let goal: Goal
    let progress: DashboardGoalProgressState
}

struct DashboardHeatmapCell: Identifiable, Equatable, Sendable {
    var id: CivilDate { civilDate }
    let civilDate: CivilDate
    let valueCNY: Money?
}

enum DashboardCashFlowHeatmapMode: String, CaseIterable, Identifiable, Sendable {
    case income = "Income"
    case expense = "Expense"
    case netCashFlow = "Net Cash Flow"

    var id: String { rawValue }
}

enum DashboardCalculations {
    static func goalProjections(
        goals: [Goal],
        currentNetWorthCNY: Money?
    ) throws -> [DashboardGoalProjection] {
        try goals.map { goal in
            switch goal.target.currency {
            case .usd:
                return DashboardGoalProjection(
                    goal: goal,
                    progress: .unavailable(.targetCurrencyUnsupportedForCNYProgress)
                )
            case .cny:
                guard let currentNetWorthCNY else {
                    return DashboardGoalProjection(
                        goal: goal,
                        progress: .unavailable(.currentCNYNetWorthUnavailable)
                    )
                }
                switch try GoalPlanning.progress(
                    goal: goal,
                    currentNetWorthCNY: currentNetWorthCNY
                ) {
                case let .available(progress):
                    return DashboardGoalProjection(goal: goal, progress: .available(progress))
                case .unavailable:
                    throw DashboardDomainError.invalidGoalProjection
                }
            }
        }
    }

    static func history(
        snapshots: [DashboardSnapshot],
        range: DashboardTimeRange,
        referenceDate: CivilDate,
        calendar: Calendar
    ) throws -> [DashboardHistoryPoint] {
        let start = try range.startDate(reference: referenceDate, calendar: calendar)
        return snapshots
            .filter { snapshot in
                snapshot.isComplete
                    && snapshot.status == .complete
                    && snapshot.civilDate <= referenceDate
                    && (start == nil || snapshot.civilDate >= start!)
            }
            .sorted { lhs, rhs in
                lhs.civilDate == rhs.civilDate
                    ? lhs.createdAt < rhs.createdAt
                    : lhs.civilDate < rhs.civilDate
            }
            .map {
                DashboardHistoryPoint(
                    snapshotID: $0.id,
                    civilDate: $0.civilDate,
                    totalAssetsCNY: $0.summary.totalAssetsCNY,
                    totalLiabilitiesCNY: $0.summary.totalLiabilitiesCNY,
                    netWorthCNY: $0.summary.netWorthCNY
                )
            }
    }

    static func changeMetrics(
        current: WealthSummary,
        snapshots: [DashboardSnapshot],
        today: CivilDate,
        calendar: Calendar
    ) throws -> DashboardChangeMetrics {
        let complete = snapshots
            .filter { $0.isComplete && $0.status == .complete && $0.civilDate <= today }
            .sorted { $0.civilDate < $1.civilDate }
        let weekStart = try DashboardDateMath.mondayStart(of: today, calendar: calendar)
        let monthStart = try CivilDate(year: today.year, month: today.month, day: 1)
        let yearStart = try CivilDate(year: today.year, month: 1, day: 1)
        let high = historicalHigh(
            snapshots: complete,
            through: today,
            including: current.netWorthCNY
        ) ?? current.netWorthCNY
        return DashboardChangeMetrics(
            today: try metric(current: current.netWorthCNY, latestBefore: today, snapshots: complete),
            week: try metric(current: current.netWorthCNY, latestBefore: weekStart, snapshots: complete),
            month: try metric(current: current.netWorthCNY, latestBefore: monthStart, snapshots: complete),
            yearToDate: try metric(current: current.netWorthCNY, latestBefore: yearStart, snapshots: complete),
            historicalHighCNY: high
        )
    }

    static func historicalHigh(
        snapshots: [DashboardSnapshot],
        through referenceDate: CivilDate,
        including current: Money? = nil
    ) -> Money? {
        snapshots
            .filter {
                $0.isComplete
                    && $0.status == .complete
                    && $0.civilDate <= referenceDate
            }
            .map(\.summary.netWorthCNY)
            .reduce(current) { high, candidate in
                guard let high else { return candidate }
                return candidate.minorUnits > high.minorUnits ? candidate : high
            }
    }

    static func allocation(records: [WealthContainer]) throws -> [DashboardAllocationSlice] {
        let assets = records.filter { !$0.isLiability }
        let total = try assets.reduce(Money(minorUnits: 0, currency: .cny)) {
            try $0.adding($1.convertedCNYValue)
        }
        guard total.minorUnits > 0 else { return [] }
        let grouped = Dictionary(grouping: assets, by: { $0.container.kind })
        return try grouped.map { kind, values in
            let amount = try values.reduce(Money(minorUnits: 0, currency: .cny)) {
                try $0.adding($1.convertedCNYValue)
            }
            return DashboardAllocationSlice(
                kind: kind,
                amountCNY: amount,
                ratio: try Ratio(decimal: amount.decimal / total.decimal)
            )
        }.sorted { lhs, rhs in
            lhs.amountCNY.minorUnits == rhs.amountCNY.minorUnits
                ? lhs.kind.rawValue < rhs.kind.rawValue
                : lhs.amountCNY.minorUnits > rhs.amountCNY.minorUnits
        }
    }

    static func subassets(records: [WealthContainer], summary: WealthSummary) throws -> [DashboardSubassetValue] {
        try records.map { record in
            let denominator = record.isLiability
                ? summary.totalLiabilitiesCNY
                : summary.totalAssetsCNY
            let ratio = denominator.minorUnits > 0
                ? try Ratio(decimal: record.convertedCNYValue.decimal / denominator.decimal)
                : nil
            return DashboardSubassetValue(
                id: record.id,
                name: record.container.name,
                kind: record.container.kind,
                isLiability: record.isLiability,
                amountCNY: record.convertedCNYValue,
                ratioWithinSection: ratio
            )
        }.sorted { lhs, rhs in
            if lhs.isLiability != rhs.isLiability { return !lhs.isLiability }
            if lhs.amountCNY.minorUnits != rhs.amountCNY.minorUnits {
                return lhs.amountCNY.minorUnits > rhs.amountCNY.minorUnits
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func cashFlow(
        entries: [LedgerEntry],
        range: DashboardTimeRange,
        referenceDate: CivilDate,
        calendar: Calendar
    ) throws -> [DashboardCashFlowPoint] {
        let start = try range.startDate(reference: referenceDate, calendar: calendar)
        let filtered = entries.filter {
            $0.civilDate <= referenceDate && (start == nil || $0.civilDate >= start!)
        }
        return try Dictionary(grouping: filtered, by: \LedgerEntry.civilDate)
            .map { date, values in
                let summary = try LedgerCashFlow.summarize(values)
                return DashboardCashFlowPoint(
                    civilDate: date,
                    ordinaryIncomeCNY: summary.ordinaryInflowCNY,
                    ordinaryExpenseCNY: summary.ordinaryOutflowCNY,
                    netCashFlowCNY: summary.netCashFlowCNY
                )
            }
            .sorted { $0.civilDate < $1.civilDate }
    }

    static func netWorthHeatmap(
        snapshots: [DashboardSnapshot],
        range: DashboardTimeRange,
        referenceDate: CivilDate,
        calendar: Calendar
    ) throws -> [DashboardHeatmapCell] {
        let all = try history(
            snapshots: snapshots,
            range: .maximum,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let start = try heatmapStart(
            requestedRange: range,
            referenceDate: referenceDate,
            earliest: all.first?.civilDate,
            calendar: calendar
        )
        guard let start else { return [] }
        var deltas: [CivilDate: Money] = [:]
        for index in all.indices where index > all.startIndex {
            let current = all[index]
            let previous = all[all.index(before: index)]
            deltas[current.civilDate] = try current.netWorthCNY.subtracting(previous.netWorthCNY)
        }
        return try DashboardDateMath.dates(from: start, through: referenceDate, calendar: calendar).map {
            DashboardHeatmapCell(civilDate: $0, valueCNY: deltas[$0])
        }
    }

    static func cashFlowHeatmap(
        points: [DashboardCashFlowPoint],
        mode: DashboardCashFlowHeatmapMode,
        range: DashboardTimeRange,
        referenceDate: CivilDate,
        calendar: Calendar
    ) throws -> [DashboardHeatmapCell] {
        let start = try heatmapStart(
            requestedRange: range,
            referenceDate: referenceDate,
            earliest: points.first?.civilDate,
            calendar: calendar
        )
        guard let start else { return [] }
        let values = Dictionary(uniqueKeysWithValues: points.map { point in
            let value: Money
            switch mode {
            case .income: value = point.ordinaryIncomeCNY
            case .expense: value = point.ordinaryExpenseCNY
            case .netCashFlow: value = point.netCashFlowCNY
            }
            return (point.civilDate, value)
        })
        return try DashboardDateMath.dates(from: start, through: referenceDate, calendar: calendar).map {
            DashboardHeatmapCell(civilDate: $0, valueCNY: values[$0])
        }
    }

    private static func metric(
        current: Money,
        latestBefore threshold: CivilDate,
        snapshots: [DashboardSnapshot]
    ) throws -> DashboardChangeMetric {
        guard let baseline = snapshots.last(where: { $0.civilDate < threshold }) else {
            return .insufficientHistory
        }
        let absolute = try current.subtracting(baseline.summary.netWorthCNY)
        let percentage = baseline.summary.netWorthCNY.minorUnits > 0
            ? try Ratio(decimal: absolute.decimal / baseline.summary.netWorthCNY.decimal)
            : nil
        return DashboardChangeMetric(
            baselineDate: baseline.civilDate,
            absoluteChangeCNY: absolute,
            percentage: percentage
        )
    }

    private static func heatmapStart(
        requestedRange: DashboardTimeRange,
        referenceDate: CivilDate,
        earliest: CivilDate?,
        calendar: Calendar
    ) throws -> CivilDate? {
        if let requested = try requestedRange.startDate(reference: referenceDate, calendar: calendar) {
            return requested
        }
        return earliest
    }
}
