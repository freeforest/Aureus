import Foundation
import GRDB

enum DashboardPersistenceError: Error, Equatable, Sendable {
    case emptyWealthStore
    case snapshotNotFound
    case corruptSnapshot
    case corruptIdentifier
    case corruptDate
    case corruptCurrency
    case corruptKind
}

struct DashboardSourceRead: Sendable {
    let currentWealthRecords: [WealthContainer]
    let completeSnapshots: [DashboardSnapshot]
    let ledgerEntries: [LedgerEntry]
    let goals: [Goal]
    let legacyIncompleteSnapshotCount: Int
}

struct DashboardSnapshotRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "snapshots"

    let id: String
    let civilDate: String
    let createdAtMS: Int64
    let totalCNYMinor: Int64
    let totalAssetsCNYMinor: Int64?
    let totalLiabilitiesCNYMinor: Int64?
    let netWorthCNYMinor: Int64?
    let captureSchema: String
    let captureStatus: String
    let isComplete: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case civilDate = "civil_date"
        case createdAtMS = "created_at_ms"
        case totalCNYMinor = "total_cny_minor"
        case totalAssetsCNYMinor = "total_assets_cny_minor"
        case totalLiabilitiesCNYMinor = "total_liabilities_cny_minor"
        case netWorthCNYMinor = "net_worth_cny_minor"
        case captureSchema = "capture_schema"
        case captureStatus = "capture_status"
        case isComplete = "is_complete"
    }

    init(snapshot: DashboardSnapshot) {
        id = snapshot.id.uuidString
        civilDate = snapshot.civilDate.description
        createdAtMS = snapshot.createdAt.millisecondsSince1970
        totalCNYMinor = snapshot.summary.netWorthCNY.minorUnits
        totalAssetsCNYMinor = snapshot.summary.totalAssetsCNY.minorUnits
        totalLiabilitiesCNYMinor = snapshot.summary.totalLiabilitiesCNY.minorUnits
        netWorthCNYMinor = snapshot.summary.netWorthCNY.minorUnits
        captureSchema = DashboardSnapshot.captureSchema
        captureStatus = snapshot.status.rawValue
        isComplete = snapshot.isComplete
    }
}

struct DashboardSnapshotItemRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "snapshot_items"

    let id: String
    let snapshotID: String
    let containerID: String
    let containerName: String
    let containerKind: String
    let isLiability: Bool
    let originalMinor: Int64
    let originalCurrencyCode: String
    let fxCoefficient: Int64
    let fxSourceCurrencyCode: String
    let fxTargetCurrencyCode: String
    let convertedCNYMinor: Int64
    let fxSource: String
    let fxReferenceDate: String
    let fxRecordedAtMS: Int64
    let fxIsManual: Bool
    let fxIsStale: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case snapshotID = "snapshot_id"
        case containerID = "container_id"
        case containerName = "container_name"
        case containerKind = "container_kind"
        case isLiability = "is_liability"
        case originalMinor = "original_minor"
        case originalCurrencyCode = "original_currency_code"
        case fxCoefficient = "fx_coefficient"
        case fxSourceCurrencyCode = "fx_source_currency_code"
        case fxTargetCurrencyCode = "fx_target_currency_code"
        case convertedCNYMinor = "converted_cny_minor"
        case fxSource = "fx_source"
        case fxReferenceDate = "fx_reference_date"
        case fxRecordedAtMS = "fx_recorded_at_ms"
        case fxIsManual = "fx_is_manual"
        case fxIsStale = "fx_is_stale"
    }

    init(item: DashboardSnapshotItem) {
        id = item.id.uuidString
        snapshotID = item.snapshotID.uuidString
        containerID = item.containerID.uuidString
        containerName = item.containerName
        containerKind = item.containerKind.rawValue
        isLiability = item.isLiability
        originalMinor = item.originalValue.minorUnits
        originalCurrencyCode = item.originalValue.currency.rawValue
        fxCoefficient = item.rate.coefficient
        fxSourceCurrencyCode = item.rate.sourceCurrency.rawValue
        fxTargetCurrencyCode = item.rate.targetCurrency.rawValue
        convertedCNYMinor = item.convertedCNY.minorUnits
        fxSource = item.fxSource
        fxReferenceDate = item.fxReferenceDate.description
        fxRecordedAtMS = item.fxRecordedAt.millisecondsSince1970
        fxIsManual = item.isManualFX
        fxIsStale = item.isStaleFX
    }

    func domain() throws -> DashboardSnapshotItem {
        guard let id = UUID(uuidString: id),
              let snapshotID = UUID(uuidString: snapshotID),
              let containerID = UUID(uuidString: containerID) else {
            throw DashboardPersistenceError.corruptIdentifier
        }
        guard let kind = AssetContainerKind(rawValue: containerKind) else {
            throw DashboardPersistenceError.corruptKind
        }
        guard let currency = CurrencyCode(rawValue: originalCurrencyCode),
              let sourceCurrency = CurrencyCode(rawValue: fxSourceCurrencyCode),
              let targetCurrency = CurrencyCode(rawValue: fxTargetCurrencyCode) else {
            throw DashboardPersistenceError.corruptCurrency
        }
        guard let referenceDate = try? CivilDate(canonical: fxReferenceDate) else {
            throw DashboardPersistenceError.corruptDate
        }
        let rate = try FXRate(
            coefficient: fxCoefficient,
            sourceCurrency: sourceCurrency,
            targetCurrency: targetCurrency
        )
        return try DashboardSnapshotItem(
            id: id,
            snapshotID: snapshotID,
            containerID: containerID,
            containerName: containerName,
            containerKind: kind,
            isLiability: isLiability,
            originalValue: Money(minorUnits: originalMinor, currency: currency),
            rate: rate,
            convertedCNY: Money(minorUnits: convertedCNYMinor, currency: .cny),
            fxSource: fxSource,
            fxReferenceDate: referenceDate,
            fxRecordedAt: UTCInstant(millisecondsSince1970: fxRecordedAtMS),
            isManualFX: fxIsManual,
            isStaleFX: fxIsStale
        )
    }
}

extension WealthStore {
    func readDashboardSource(
        for civilDate: CivilDate,
        createdAt: UTCInstant
    ) throws -> DashboardSourceRead {
        try queue.write { db in
            let records = try Self.fetchDashboardWealthRecords(in: db)
            if !records.isEmpty,
               try Self.fetchCompleteSnapshot(in: db, civilDate: civilDate) == nil {
                _ = try Self.captureDashboardSnapshot(
                    records: records,
                    civilDate: civilDate,
                    createdAt: createdAt,
                    existingID: nil,
                    in: db
                )
            }

            return DashboardSourceRead(
                currentWealthRecords: records,
                completeSnapshots: try Self.fetchDashboardSnapshots(
                    in: db,
                    from: nil,
                    through: civilDate
                ),
                ledgerEntries: try Self.fetchLedgerEntries(in: db),
                goals: try Self.fetchGoals(in: db),
                legacyIncompleteSnapshotCount: try Self.legacyIncompleteSnapshotCount(in: db)
            )
        }
    }

    func ensureDashboardSnapshot(
        for civilDate: CivilDate,
        createdAt: UTCInstant
    ) throws -> DashboardSnapshot? {
        try queue.write { db in
            if let existing = try Self.fetchCompleteSnapshot(in: db, civilDate: civilDate) {
                return existing
            }
            let records = try Self.fetchDashboardWealthRecords(in: db)
            guard !records.isEmpty else { return nil }
            return try Self.captureDashboardSnapshot(
                records: records,
                civilDate: civilDate,
                createdAt: createdAt,
                existingID: nil,
                in: db
            )
        }
    }

    func refreshDashboardSnapshot(
        for civilDate: CivilDate,
        createdAt: UTCInstant
    ) throws -> DashboardSnapshot {
        try queue.write { db in
            let records = try Self.fetchDashboardWealthRecords(in: db)
            guard !records.isEmpty else { throw DashboardPersistenceError.emptyWealthStore }
            let existingID = try String.fetchOne(
                db,
                sql: "SELECT id FROM snapshots WHERE civil_date = ? AND is_complete = 1",
                arguments: [civilDate.description]
            ).flatMap(UUID.init(uuidString:))
            return try Self.captureDashboardSnapshot(
                records: records,
                civilDate: civilDate,
                createdAt: createdAt,
                existingID: existingID,
                in: db
            )
        }
    }

    func fetchDashboardSnapshots(
        from startDate: CivilDate? = nil,
        through endDate: CivilDate? = nil
    ) throws -> [DashboardSnapshot] {
        try queue.read { db in
            try Self.fetchDashboardSnapshots(in: db, from: startDate, through: endDate)
        }
    }

    func completeDashboardSnapshotCount(on date: CivilDate? = nil) throws -> Int {
        try queue.read { db in
            if let date {
                return try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM snapshots WHERE is_complete = 1 AND civil_date = ?",
                    arguments: [date.description]
                ) ?? 0
            }
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM snapshots WHERE is_complete = 1") ?? 0
        }
    }

    func legacyIncompleteSnapshotCount() throws -> Int {
        try queue.read { db in
            try Self.legacyIncompleteSnapshotCount(in: db)
        }
    }

    func dashboardSnapshotStorageClasses() throws -> Set<String> {
        try queue.read { db in
            var types = Set<String>()
            if let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT typeof(total_assets_cny_minor) AS assets,
                           typeof(total_liabilities_cny_minor) AS liabilities,
                           typeof(net_worth_cny_minor) AS net
                    FROM snapshots WHERE is_complete = 1 LIMIT 1
                    """
            ) {
                types.formUnion([row["assets"], row["liabilities"], row["net"]] as [String])
            }
            if let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT typeof(original_minor) AS original,
                           typeof(fx_coefficient) AS fx,
                           typeof(converted_cny_minor) AS converted
                    FROM snapshot_items LIMIT 1
                    """
            ) {
                types.formUnion([row["original"], row["fx"], row["converted"]] as [String])
            }
            return types
        }
    }

    func dashboardSnapshotSentinel() throws -> (complete: Int, items: Int, legacy: Int) {
        try queue.read { db in
            (
                complete: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM snapshots WHERE is_complete = 1") ?? 0,
                items: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM snapshot_items") ?? 0,
                legacy: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM snapshots WHERE is_complete = 0") ?? 0
            )
        }
    }

    func insertSyntheticDashboardSnapshot(_ snapshot: DashboardSnapshot) throws {
        try queue.write { db in
            let existing = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM snapshots WHERE civil_date = ? AND is_complete = 1",
                arguments: [snapshot.civilDate.description]
            ) ?? 0
            guard existing == 0 else { return }
            try Self.insertDashboardSnapshot(snapshot, in: db)
        }
    }

    private static func captureDashboardSnapshot(
        records: [WealthContainer],
        civilDate: CivilDate,
        createdAt: UTCInstant,
        existingID: UUID?,
        in db: Database
    ) throws -> DashboardSnapshot {
        let id = existingID ?? UUID()
        let snapshot = try DashboardSnapshot.capture(
            id: id,
            civilDate: civilDate,
            createdAt: createdAt,
            records: records
        )
        if existingID != nil {
            try db.execute(sql: "DELETE FROM snapshot_items WHERE snapshot_id = ?", arguments: [id.uuidString])
            let row = DashboardSnapshotRow(snapshot: snapshot)
            try row.update(db)
        } else {
            try DashboardSnapshotRow(snapshot: snapshot).insert(db)
        }
        for item in snapshot.items {
            try DashboardSnapshotItemRow(item: item).insert(db)
        }
        return snapshot
    }

    private static func insertDashboardSnapshot(_ snapshot: DashboardSnapshot, in db: Database) throws {
        try DashboardSnapshotRow(snapshot: snapshot).insert(db)
        for item in snapshot.items {
            try DashboardSnapshotItemRow(item: item).insert(db)
        }
    }

    private static func fetchCompleteSnapshot(
        in db: Database,
        civilDate: CivilDate
    ) throws -> DashboardSnapshot? {
        guard let row = try DashboardSnapshotRow.fetchOne(
            db,
            sql: "SELECT * FROM snapshots WHERE civil_date = ? AND is_complete = 1",
            arguments: [civilDate.description]
        ) else {
            return nil
        }
        return try dashboardSnapshot(row: row, in: db)
    }

    private static func fetchDashboardSnapshots(
        in db: Database,
        from startDate: CivilDate?,
        through endDate: CivilDate?
    ) throws -> [DashboardSnapshot] {
        var predicates = ["is_complete = 1", "capture_status = 'complete'"]
        var arguments = StatementArguments()
        if let startDate {
            predicates.append("civil_date >= ?")
            arguments += [startDate.description]
        }
        if let endDate {
            predicates.append("civil_date <= ?")
            arguments += [endDate.description]
        }
        let rows = try DashboardSnapshotRow.fetchAll(
            db,
            sql: "SELECT * FROM snapshots WHERE \(predicates.joined(separator: " AND ")) ORDER BY civil_date, created_at_ms, id",
            arguments: arguments
        )
        return try rows.map { try dashboardSnapshot(row: $0, in: db) }
    }

    private static func legacyIncompleteSnapshotCount(in db: Database) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM snapshots WHERE is_complete = 0 AND capture_status = 'legacyIncomplete'"
        ) ?? 0
    }

    private static func dashboardSnapshot(
        row: DashboardSnapshotRow,
        in db: Database
    ) throws -> DashboardSnapshot {
        guard let id = UUID(uuidString: row.id) else {
            throw DashboardPersistenceError.corruptIdentifier
        }
        guard let date = try? CivilDate(canonical: row.civilDate) else {
            throw DashboardPersistenceError.corruptDate
        }
        guard row.captureSchema == DashboardSnapshot.captureSchema,
              row.captureStatus == DashboardSnapshotStatus.complete.rawValue,
              row.isComplete,
              let assets = row.totalAssetsCNYMinor,
              let liabilities = row.totalLiabilitiesCNYMinor,
              let net = row.netWorthCNYMinor,
              row.totalCNYMinor == net else {
            throw DashboardPersistenceError.corruptSnapshot
        }
        let items = try DashboardSnapshotItemRow.fetchAll(
            db,
            sql: "SELECT * FROM snapshot_items WHERE snapshot_id = ? ORDER BY container_id, id",
            arguments: [row.id]
        ).map { try $0.domain() }
        return try DashboardSnapshot(
            id: id,
            civilDate: date,
            createdAt: UTCInstant(millisecondsSince1970: row.createdAtMS),
            summary: WealthSummary(
                totalAssetsCNY: Money(minorUnits: assets, currency: .cny),
                totalLiabilitiesCNY: Money(minorUnits: liabilities, currency: .cny),
                netWorthCNY: Money(minorUnits: net, currency: .cny)
            ),
            items: items
        )
    }

    private static func fetchDashboardWealthRecords(in db: Database) throws -> [WealthContainer] {
        let containerRows = try AssetContainerPersistenceRow.fetchAll(
            db,
            sql: """
                SELECT asset_containers.*
                FROM asset_containers
                INNER JOIN wealth_records
                    ON wealth_records.container_id = asset_containers.id
                ORDER BY updated_date DESC, name COLLATE NOCASE, asset_containers.id
                """
        )
        let recordRows = try WealthRecordPersistenceRow.fetchAll(db)
        let recordsByContainer = Dictionary(
            uniqueKeysWithValues: recordRows.map { ($0.containerID, $0) }
        )
        return try containerRows.map { containerRow in
            guard let recordRow = recordsByContainer[containerRow.id] else {
                throw WealthPersistenceError.corruptRecord
            }
            return try recordRow.domain(container: containerRow.domain())
        }
    }
}
