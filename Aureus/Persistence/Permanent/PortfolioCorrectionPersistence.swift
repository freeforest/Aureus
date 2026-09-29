import Foundation
import GRDB

enum PortfolioCorrectionSQL {
    static let table = "portfolio_activity_correction_history"
    static let declarations: [(String, String)] = [
        (table, """
            CREATE TABLE portfolio_activity_correction_history (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                history_id TEXT NOT NULL UNIQUE CHECK (\(LedgerCorrectionSQL.uuidConstraint("history_id"))),
                operation_id TEXT NOT NULL UNIQUE CHECK (\(LedgerCorrectionSQL.uuidConstraint("operation_id"))),
                activity_id TEXT NOT NULL CHECK (\(LedgerCorrectionSQL.uuidConstraint("activity_id"))),
                kind TEXT NOT NULL CHECK (kind IN ('correction','deletionContext','ledgerDetachContext')),
                occurred_at_ms INTEGER NOT NULL CHECK (typeof(occurred_at_ms) = 'integer'),
                reason TEXT,
                request_digest TEXT NOT NULL CHECK (length(request_digest) = 64 AND request_digest NOT GLOB '*[^0-9a-f]*'),
                post_state_digest TEXT CHECK (post_state_digest IS NULL OR (length(post_state_digest) = 64 AND post_state_digest NOT GLOB '*[^0-9a-f]*')),
                payload TEXT NOT NULL,
                CHECK ((kind = 'correction' AND reason IS NOT NULL AND length(trim(reason)) BETWEEN 1 AND 500 AND instr(reason,char(0)) = 0 AND post_state_digest IS NOT NULL)
                    OR (kind IN ('deletionContext','ledgerDetachContext') AND reason IS NULL AND post_state_digest IS NULL))
            )
            """),
        ("portfolio_activity_correction_history_target", "CREATE INDEX portfolio_activity_correction_history_target ON portfolio_activity_correction_history(activity_id, sequence)"),
        ("portfolio_activity_correction_history_no_update", "CREATE TRIGGER portfolio_activity_correction_history_no_update BEFORE UPDATE ON portfolio_activity_correction_history BEGIN SELECT RAISE(ABORT, 'immutable portfolio history'); END"),
        ("portfolio_activity_correction_history_no_delete", "CREATE TRIGGER portfolio_activity_correction_history_no_delete BEFORE DELETE ON portfolio_activity_correction_history BEGIN SELECT RAISE(ABORT, 'immutable portfolio history'); END")
    ]

    // Every persisted Activity and bound Link column participates in the CAS digest.
    private struct ActivityState: Encodable {
        let id: String, portfolioID: String, securityLinkID: String, kind: String
        let civilDate: String, recordedAtMS: Int64, exchangeTimeZoneID: String
        let ledgerEntryID: String?, quantity: Int64?, unitPrice: Int64?, fee: Int64?
        let totalOriginal: Int64?, currency: String?, convertedCNY: Int64?, fxCoefficient: Int64?
        let fxSource: String?, fxReferenceDate: String?, fxRecordedAtMS: Int64?
        let fxIsManual: Bool?, fxIsStale: Bool?, splitFrom: Int64?, splitTo: Int64?
        let note: String?

        init(_ row: Row) {
            id = row["id"]; portfolioID = row["portfolio_id"]
            securityLinkID = row["security_link_id"]; kind = row["kind"]
            civilDate = row["civil_date"]; recordedAtMS = row["recorded_at_ms"]
            exchangeTimeZoneID = row["exchange_time_zone_id"]
            ledgerEntryID = row["ledger_entry_id"]
            quantity = row["quantity_coefficient"]; unitPrice = row["unit_price_coefficient"]
            fee = row["fee_minor"]; totalOriginal = row["total_original_minor"]
            currency = row["currency_code"]; convertedCNY = row["converted_cny_minor"]
            fxCoefficient = row["fx_coefficient"]; fxSource = row["fx_source"]
            fxReferenceDate = row["fx_reference_date"]; fxRecordedAtMS = row["fx_recorded_at_ms"]
            fxIsManual = row["fx_is_manual"]; fxIsStale = row["fx_is_stale"]
            splitFrom = row["split_from_coefficient"]; splitTo = row["split_to_coefficient"]
            note = row["sanitized_note"]
        }
    }

    private struct LinkState: Encodable {
        let id: String, portfolioID: String, wealthContainerID: String
        let symbol: String, rawMIC: String, currency: String, assetKind: String
        let sortOrder: Int
        init(_ row: Row) {
            id = row["id"]; portfolioID = row["portfolio_id"]
            wealthContainerID = row["wealth_container_id"]
            symbol = row["symbol"]; rawMIC = row["raw_mic"]
            currency = row["currency_code"]; assetKind = row["asset_kind"]
            sortOrder = row["sort_order"]
        }
    }

    private struct State: Encodable {
        let activity: ActivityState
        let link: LinkState
    }

    static func fetch(_ db: Database, id: UUID) throws -> (PortfolioActivity, PortfolioSecurityLink)? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM portfolio_activities WHERE id = ?",
            arguments: [id.uuidString]) else { return nil }
        guard let link = try Row.fetchOne(db, sql: "SELECT * FROM portfolio_security_links WHERE id = ?",
            arguments: [row["security_link_id"] as String]) else {
            throw PortfolioPersistenceError.corruptRecord
        }
        return try (WealthStore.activityDomain(row), WealthStore.securityLinkDomain(link))
    }

    static func stateDigest(_ db: Database, id: UUID) throws -> String {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM portfolio_activities WHERE id = ?",
            arguments: [id.uuidString]),
              let link = try Row.fetchOne(db, sql: "SELECT * FROM portfolio_security_links WHERE id = ?",
            arguments: [row["security_link_id"] as String]) else {
            throw PortfolioPersistenceError.notFound
        }
        return try PortfolioCorrectionEncoding.digest(State(activity: ActivityState(row), link: LinkState(link)))
    }

    static func latest(_ db: Database, id: UUID) throws -> UUID? {
        guard let raw = try String.fetchOne(db,
            sql: "SELECT history_id FROM portfolio_activity_correction_history WHERE activity_id = ? ORDER BY sequence DESC LIMIT 1",
            arguments: [id.uuidString]) else { return nil }
        return try uuid(raw)
    }

    static func uuid(_ raw: String) throws -> UUID {
        guard let id = UUID(uuidString: raw), id.uuidString == raw else {
            throw PortfolioCorrectionError.invalidHistory
        }
        return id
    }

    static func decode(_ row: Row) throws -> PortfolioCorrectionHistory {
        let raw: String = row["payload"]
        let bytes = Data(raw.utf8)
        let payload = try JSONDecoder().decode(PortfolioHistoryPayload.self, from: bytes)
        guard try PortfolioCorrectionEncoding.data(payload) == bytes else {
            throw PortfolioCorrectionError.invalidHistory
        }
        let kind: String = row["kind"]
        try payload.validate(kind: kind)
        let target = try uuid(row["activity_id"])
        let reason: String? = row["reason"]
        if kind == "correction" {
            guard let reason, try PortfolioCorrectionEncoding.reason(reason) == reason else {
                throw PortfolioCorrectionError.invalidHistory
            }
        } else if reason != nil { throw PortfolioCorrectionError.invalidHistory }
        let sequence: Int64 = row["sequence"]
        guard sequence > 0, payload.before.id == target else {
            throw PortfolioCorrectionError.invalidHistory
        }
        return PortfolioCorrectionHistory(sequence: sequence, id: try uuid(row["history_id"]),
            operationID: try uuid(row["operation_id"]), targetID: target, kind: kind,
            occurredAt: UTCInstant(millisecondsSince1970: row["occurred_at_ms"]),
            reason: reason, payload: payload)
    }

    static func validateSchema(_ db: Database) throws {
        func normalized(_ sql: String) -> String {
            sql.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        }
        for (name, sql) in declarations {
            guard let actual = try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE name = ?",
                arguments: [name]), normalized(actual) == normalized(sql) else {
                throw PermanentDatabaseValidationFailure.applicationInvariant
            }
        }
        for row in try Row.fetchAll(db, sql: "SELECT * FROM portfolio_activity_correction_history ORDER BY sequence") {
            _ = try decode(row)
        }
    }

    @discardableResult
    static func append(_ db: Database, operationID: UUID, kind: String, occurredAt: UTCInstant,
                       reason: String?, requestDigest: String, postState: String?,
                       payload: PortfolioHistoryPayload) throws -> PortfolioCorrectionHistory {
        try payload.validate(kind: kind)
        let id = UUID()
        let text = String(decoding: try PortfolioCorrectionEncoding.data(payload), as: UTF8.self)
        try db.execute(sql: """
            INSERT INTO portfolio_activity_correction_history(history_id,operation_id,activity_id,
                kind,occurred_at_ms,reason,request_digest,post_state_digest,payload)
            VALUES (?,?,?,?,?,?,?,?,?)
            """, arguments: [id.uuidString, operationID.uuidString, payload.before.id.uuidString,
                kind, occurredAt.millisecondsSince1970, reason, requestDigest, postState, text])
        guard let row = try Row.fetchOne(db,
            sql: "SELECT * FROM portfolio_activity_correction_history WHERE history_id = ?",
            arguments: [id.uuidString]) else { throw PortfolioCorrectionError.invalidHistory }
        return try decode(row)
    }

    private static func evidenceLinks(_ db: Database, id: UUID) throws -> [PortfolioDeletionContext.EvidenceLink] {
        try Row.fetchAll(db, sql: "SELECT * FROM evidence_portfolio_activity_links WHERE portfolio_activity_id = ? ORDER BY link_id",
            arguments: [id.uuidString]).map { row in
            .init(documentID: try uuid(row["document_id"]), linkID: try uuid(row["link_id"]),
                createdAt: UTCInstant(millisecondsSince1970: row["created_at_ms"]), meaning: row["meaning"])
        }
    }

    static func deletionContext(_ db: Database, id: UUID, origin: String) throws {
        guard let (activity, link) = try fetch(db, id: id) else { throw PortfolioPersistenceError.notFound }
        let links = try evidenceLinks(db, id: id)
        guard try latest(db, id: id) != nil || !links.isEmpty || activity.ledgerEntryID != nil else { return }
        let payload = PortfolioHistoryPayload(version: 1,
            before: .init(activity, link: link), after: nil,
            deletion: .init(origin: origin, evidenceLinks: links, ledgerEntryID: activity.ledgerEntryID))
        try append(db, operationID: UUID(), kind: "deletionContext", occurredAt: SystemClock().now(),
            reason: nil, requestDigest: PortfolioCorrectionEncoding.digest(payload),
            postState: nil, payload: payload)
    }

    static func ledgerDetachContexts(_ db: Database, ledgerID: UUID) throws -> [UUID: PortfolioCorrectionProjection] {
        let ids = try String.fetchAll(db,
            sql: "SELECT id FROM portfolio_activities WHERE ledger_entry_id = ? ORDER BY id",
            arguments: [ledgerID.uuidString])
        var afterByID: [UUID: PortfolioCorrectionProjection] = [:]
        for raw in ids {
            let id = try uuid(raw)
            guard let (before, link) = try fetch(db, id: id) else { throw PortfolioPersistenceError.notFound }
            let after = try PortfolioActivity(id: before.id, portfolioID: before.portfolioID,
                securityLinkID: before.securityLinkID, civilDate: before.civilDate,
                recordedAt: before.recordedAt, exchangeTimeZoneIdentifier: before.exchangeTimeZoneIdentifier,
                ledgerEntryID: nil, payload: before.payload)
            let projection = PortfolioCorrectionProjection(after, link: link)
            let payload = PortfolioHistoryPayload(version: 1,
                before: .init(before, link: link), after: projection,
                deletion: .init(origin: "existingDeleteLedgerAPI", evidenceLinks: [], ledgerEntryID: ledgerID))
            try append(db, operationID: UUID(), kind: "ledgerDetachContext", occurredAt: SystemClock().now(),
                reason: nil, requestDigest: PortfolioCorrectionEncoding.digest(payload),
                postState: nil, payload: payload)
            afterByID[id] = projection
        }
        return afterByID
    }

    static func verifyLedgerDetach(_ db: Database, expected: [UUID: PortfolioCorrectionProjection]) throws {
        for (id, projection) in expected {
            guard let (actual, link) = try fetch(db, id: id),
                  PortfolioCorrectionProjection(actual, link: link) == projection else {
                throw PortfolioCorrectionError.invalidHistory
            }
        }
    }
}

extension WealthStore {
    func readPortfolioActivityEditContext(id: UUID) throws -> PortfolioActivityEditContext {
        guard maintenanceState == .ready else { throw PortfolioCorrectionError.maintenanceUnavailable }
        return try queue.read { db in
            guard let (activity, link) = try PortfolioCorrectionSQL.fetch(db, id: id) else {
                throw PortfolioPersistenceError.notFound
            }
            let token = try PortfolioActivityEditToken(targetID: id,
                stateDigest: PortfolioCorrectionSQL.stateDigest(db, id: id),
                latestHistoryID: PortfolioCorrectionSQL.latest(db, id: id),
                storeID: portfolioEditStoreID, epoch: portfolioEditEpoch)
            return PortfolioActivityEditContext(activity: activity, link: link, token: token)
        }
    }

    func portfolioActivityCorrectionHistory(id: UUID) throws -> [PortfolioCorrectionHistory] {
        try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM portfolio_activity_correction_history WHERE activity_id = ? ORDER BY sequence",
                arguments: [id.uuidString]).map(PortfolioCorrectionSQL.decode)
        }
    }

    func correctPortfolioActivity(_ request: PortfolioCorrectionRequest) throws -> PortfolioCorrectionResult {
        guard maintenanceState == .ready else { throw PortfolioCorrectionError.maintenanceUnavailable }
        guard request.candidate.id == request.expected.targetID else { throw PortfolioCorrectionError.invalidRequest }
        let reason = request.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reason.count <= 500, !reason.contains("\0") else { throw PortfolioCorrectionError.invalidRequest }
        let requestDigest = try PortfolioCorrectionEncoding.digest(PortfolioCorrectionEncoding.Request(
            candidate: .init(request.candidate), expected: request.expected,
            operationID: request.operationID, reason: reason, occurredAt: request.occurredAt))
        return try queue.write { db in
            if let row = try Row.fetchOne(db,
                sql: "SELECT * FROM portfolio_activity_correction_history WHERE operation_id = ?",
                arguments: [request.operationID.uuidString]) {
                guard row["request_digest"] as String == requestDigest,
                      row["activity_id"] as String == request.candidate.id.uuidString,
                      row["kind"] as String == "correction" else {
                    throw PortfolioCorrectionError.operationConflict
                }
                let history = try PortfolioCorrectionSQL.decode(row)
                guard try PortfolioCorrectionSQL.fetch(db, id: request.candidate.id) != nil else {
                    return .alreadyApplied(history, .deleted)
                }
                let committed: String? = row["post_state_digest"]
                let current = try PortfolioCorrectionSQL.stateDigest(db, id: request.candidate.id)
                let latest = try PortfolioCorrectionSQL.latest(db, id: request.candidate.id)
                return .alreadyApplied(history,
                    current == committed && latest == history.id ? .unchanged : .changed)
            }
            let (before, oldLink) = try checkedPortfolioBefore(db, token: request.expected)
            guard request.candidate.portfolioID == before.portfolioID else {
                throw PortfolioCorrectionError.invalidRequest
            }
            guard let targetLinkRow = try Row.fetchOne(db,
                sql: "SELECT * FROM portfolio_security_links WHERE id = ?",
                arguments: [request.candidate.securityLinkID.uuidString]) else {
                throw PortfolioCorrectionError.invalidRequest
            }
            let targetLink = try Self.securityLinkDomain(targetLinkRow)
            guard targetLink.portfolioID == before.portfolioID,
                  try Self.wealthSecurityMatches(targetLink, in: db) else {
                throw PortfolioCorrectionError.invalidRequest
            }
            let old = PortfolioCorrectionProjection(before, link: oldLink)
            let after = PortfolioCorrectionProjection(request.candidate, link: targetLink)
            try after.validate()
            let important = !old.hasSameImportantValues(as: after)
            let minor = old.details != after.details
            guard important || minor else { return .noChange }
            if important { _ = try PortfolioCorrectionEncoding.reason(reason) }
            try Self.insert(request.candidate, in: db, updating: true)
            do { try Self.validatePortfolioReplay(before.portfolioID, in: db) }
            catch { throw PortfolioPersistenceError.invalidHistoricalMutation }
            guard important else { return .minorUpdate }
            guard let (actual, actualLink) = try PortfolioCorrectionSQL.fetch(db, id: before.id) else {
                throw PortfolioPersistenceError.notFound
            }
            let submitted = PortfolioCorrectionProjection(actual, link: actualLink)
            guard submitted == after else { throw PortfolioCorrectionError.invalidHistory }
            let history = try PortfolioCorrectionSQL.append(db, operationID: request.operationID,
                kind: "correction", occurredAt: request.occurredAt, reason: reason,
                requestDigest: requestDigest,
                postState: PortfolioCorrectionSQL.stateDigest(db, id: before.id),
                payload: PortfolioHistoryPayload(version: 1, before: old,
                    after: submitted, deletion: nil))
            return .applied(history)
        }
    }

    private func checkedPortfolioBefore(_ db: Database, token: PortfolioActivityEditToken) throws
        -> (PortfolioActivity, PortfolioSecurityLink) {
        guard token.storeID == portfolioEditStoreID, token.epoch == portfolioEditEpoch else {
            throw PortfolioCorrectionError.staleDraft
        }
        guard let before = try PortfolioCorrectionSQL.fetch(db, id: token.targetID) else {
            throw PortfolioPersistenceError.notFound
        }
        guard try PortfolioCorrectionSQL.stateDigest(db, id: token.targetID) == token.stateDigest,
              try PortfolioCorrectionSQL.latest(db, id: token.targetID) == token.latestHistoryID else {
            throw PortfolioCorrectionError.staleDraft
        }
        return before
    }
}
