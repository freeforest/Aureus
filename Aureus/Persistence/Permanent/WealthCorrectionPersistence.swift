import Foundation
import GRDB

enum WealthCorrectionSQL {
    static let table = "wealth_correction_history"
    static let declarations: [(String, String)] = [
        (table, """
            CREATE TABLE wealth_correction_history (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                history_id TEXT NOT NULL UNIQUE CHECK (\(LedgerCorrectionSQL.uuidConstraint("history_id"))),
                operation_id TEXT NOT NULL UNIQUE CHECK (\(LedgerCorrectionSQL.uuidConstraint("operation_id"))),
                wealth_container_id TEXT NOT NULL CHECK (\(LedgerCorrectionSQL.uuidConstraint("wealth_container_id"))),
                kind TEXT NOT NULL CHECK (kind IN ('correction','deletionContext')),
                occurred_at_ms INTEGER NOT NULL CHECK (typeof(occurred_at_ms) = 'integer'),
                reason TEXT,
                request_digest TEXT NOT NULL CHECK (length(request_digest) = 64 AND request_digest NOT GLOB '*[^0-9a-f]*'),
                post_state_digest TEXT CHECK (post_state_digest IS NULL OR (length(post_state_digest) = 64 AND post_state_digest NOT GLOB '*[^0-9a-f]*')),
                payload TEXT NOT NULL,
                CHECK ((kind = 'correction' AND reason IS NOT NULL AND length(trim(reason)) BETWEEN 1 AND 500 AND instr(reason,char(0)) = 0 AND post_state_digest IS NOT NULL)
                    OR (kind = 'deletionContext' AND reason IS NULL AND post_state_digest IS NULL))
            )
            """),
        ("wealth_correction_history_target", "CREATE INDEX wealth_correction_history_target ON wealth_correction_history(wealth_container_id, sequence)"),
        ("wealth_correction_history_no_update", "CREATE TRIGGER wealth_correction_history_no_update BEFORE UPDATE ON wealth_correction_history BEGIN SELECT RAISE(ABORT, 'immutable wealth history'); END"),
        ("wealth_correction_history_no_delete", "CREATE TRIGGER wealth_correction_history_no_delete BEFORE DELETE ON wealth_correction_history BEGIN SELECT RAISE(ABORT, 'immutable wealth history'); END")
    ]

    struct State: Encodable {
        let container: AssetContainerPersistenceRow
        let record: WealthRecordPersistenceRow
    }

    static func fetch(_ db: Database, id: UUID) throws -> WealthContainer? {
        guard let parent = try AssetContainerPersistenceRow.fetchOne(db,
            sql: "SELECT * FROM asset_containers WHERE id = ?", arguments: [id.uuidString]) else { return nil }
        guard let child = try WealthRecordPersistenceRow.fetchOne(db,
            sql: "SELECT * FROM wealth_records WHERE container_id = ?", arguments: [id.uuidString]) else {
            throw WealthPersistenceError.corruptRecord
        }
        return try child.domain(container: parent.domain())
    }

    static func stateDigest(_ db: Database, id: UUID) throws -> String {
        guard let parent = try AssetContainerPersistenceRow.fetchOne(db,
            sql: "SELECT * FROM asset_containers WHERE id = ?", arguments: [id.uuidString]),
              let child = try WealthRecordPersistenceRow.fetchOne(db,
            sql: "SELECT * FROM wealth_records WHERE container_id = ?", arguments: [id.uuidString]) else {
            throw WealthPersistenceError.containerNotFound
        }
        return try WealthCorrectionEncoding.digest(State(container: parent, record: child))
    }

    static func latest(_ db: Database, id: UUID) throws -> UUID? {
        guard let raw = try String.fetchOne(db,
            sql: "SELECT history_id FROM wealth_correction_history WHERE wealth_container_id = ? ORDER BY sequence DESC LIMIT 1",
            arguments: [id.uuidString]) else { return nil }
        return try uuid(raw)
    }

    static func uuid(_ raw: String) throws -> UUID {
        guard let id = UUID(uuidString: raw), id.uuidString == raw else { throw WealthCorrectionError.invalidHistory }
        return id
    }

    static func decode(_ row: Row) throws -> WealthCorrectionHistory {
        let raw: String = row["payload"]
        let bytes = Data(raw.utf8)
        let payload = try JSONDecoder().decode(WealthHistoryPayload.self, from: bytes)
        guard try WealthCorrectionEncoding.data(payload) == bytes else { throw WealthCorrectionError.invalidHistory }
        let kind: String = row["kind"]
        try payload.validate(kind: kind)
        let target = try uuid(row["wealth_container_id"])
        let reason: String? = row["reason"]
        if kind == "correction" {
            guard let reason, try WealthCorrectionEncoding.reason(reason) == reason else {
                throw WealthCorrectionError.invalidHistory
            }
        } else if reason != nil { throw WealthCorrectionError.invalidHistory }
        let sequence: Int64 = row["sequence"]
        guard sequence > 0, payload.before.id == target else { throw WealthCorrectionError.invalidHistory }
        return WealthCorrectionHistory(sequence: sequence, id: try uuid(row["history_id"]),
            operationID: try uuid(row["operation_id"]), targetID: target, kind: kind,
            occurredAt: UTCInstant(millisecondsSince1970: row["occurred_at_ms"]), reason: reason,
            payload: payload)
    }

    static func validateSchema(_ db: Database) throws {
        func normalized(_ sql: String) -> String { sql.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased() }
        for (name, sql) in declarations {
            guard let actual = try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE name = ?", arguments: [name]),
                  normalized(actual) == normalized(sql) else {
                throw PermanentDatabaseValidationFailure.applicationInvariant
            }
        }
        for row in try Row.fetchAll(db, sql: "SELECT * FROM wealth_correction_history ORDER BY sequence") {
            _ = try decode(row)
        }
    }

    static func append(_ db: Database, operationID: UUID, kind: String, occurredAt: UTCInstant,
                       reason: String?, requestDigest: String, postState: String?,
                       payload: WealthHistoryPayload) throws -> WealthCorrectionHistory {
        try payload.validate(kind: kind)
        let id = UUID()
        let text = String(decoding: try WealthCorrectionEncoding.data(payload), as: UTF8.self)
        try db.execute(sql: """
            INSERT INTO wealth_correction_history(history_id, operation_id, wealth_container_id,
                kind, occurred_at_ms, reason, request_digest, post_state_digest, payload)
            VALUES (?,?,?,?,?,?,?,?,?)
            """, arguments: [id.uuidString, operationID.uuidString, payload.before.id.uuidString,
                kind, occurredAt.millisecondsSince1970, reason, requestDigest, postState, text])
        guard let row = try Row.fetchOne(db,
            sql: "SELECT * FROM wealth_correction_history WHERE history_id = ?", arguments: [id.uuidString]) else {
            throw WealthCorrectionError.invalidHistory
        }
        return try decode(row)
    }

    static func deletionContext(_ db: Database, id: UUID) throws {
        let hasHistory = try latest(db, id: id) != nil
        let links = try Row.fetchAll(db,
            sql: "SELECT * FROM evidence_container_links WHERE container_id = ? ORDER BY link_id",
            arguments: [id.uuidString])
        guard hasHistory || !links.isEmpty else { return }
        guard let before = try fetch(db, id: id) else { throw WealthPersistenceError.containerNotFound }
        let context = WealthDeletionContext(origin: "existingDeleteAPI", links: try links.map {
            .init(documentID: try uuid($0["document_id"]), linkID: try uuid($0["link_id"]),
                  createdAt: UTCInstant(millisecondsSince1970: $0["created_at_ms"]), meaning: $0["meaning"])
        })
        let payload = WealthHistoryPayload(version: 1, before: .init(before), after: nil, deletion: context)
        _ = try append(db, operationID: UUID(), kind: "deletionContext", occurredAt: SystemClock().now(),
            reason: nil, requestDigest: WealthCorrectionEncoding.digest(payload), postState: nil, payload: payload)
    }

    static func normalizedCandidate(_ candidate: WealthContainer, before: WealthContainer,
                                    fxIntent: WealthFXIntent, occurredAt: UTCInstant) throws -> WealthContainer {
        guard candidate.id == before.id,
              candidate.container.createdDate == before.container.createdDate else {
            throw WealthCorrectionError.invalidRequest
        }
        let old = before.valuation, next = candidate.valuation
        switch fxIntent {
        case .preserve:
            guard old.rate == next.rate, old.referenceDate == next.referenceDate,
                  old.providerIdentifier == next.providerIdentifier,
                  old.isManualOverride == next.isManualOverride, old.isStale == next.isStale else {
                throw WealthCorrectionError.invalidRequest
            }
            let original = try candidate.details.currentValue()
            let preserved = try FXValuation(original: original, rate: old.rate,
                referenceDate: old.referenceDate, fetchedAt: old.fetchedAt,
                providerIdentifier: old.providerIdentifier,
                isManualOverride: old.isManualOverride, isStale: old.isStale)
            return try WealthContainer(container: candidate.container, details: candidate.details, valuation: preserved)
        case .newInput:
            guard next.fetchedAt == occurredAt,
                  old.rate != next.rate || old.referenceDate != next.referenceDate
                    || old.providerIdentifier != next.providerIdentifier
                    || old.isManualOverride != next.isManualOverride || old.isStale != next.isStale else {
                throw WealthCorrectionError.invalidRequest
            }
            return candidate
        }
    }
}

extension WealthStore {
    func readWealthEditContext(id: UUID) throws -> WealthEditContext {
        guard maintenanceState == .ready else { throw WealthCorrectionError.maintenanceUnavailable }
        return try queue.read { db in
            guard let record = try WealthCorrectionSQL.fetch(db, id: id) else {
                throw WealthPersistenceError.containerNotFound
            }
            return WealthEditContext(record: record, token: WealthEditToken(targetID: id,
                stateDigest: try WealthCorrectionSQL.stateDigest(db, id: id),
                latestHistoryID: try WealthCorrectionSQL.latest(db, id: id),
                storeID: wealthEditStoreID, epoch: wealthEditEpoch))
        }
    }

    func wealthCorrectionHistory(id: UUID) throws -> [WealthCorrectionHistory] {
        guard maintenanceState == .ready else { throw WealthCorrectionError.maintenanceUnavailable }
        return try queue.read { db in
            try Row.fetchAll(db,
                sql: "SELECT * FROM wealth_correction_history WHERE wealth_container_id = ? ORDER BY sequence",
                arguments: [id.uuidString]).map(WealthCorrectionSQL.decode)
        }
    }

    func recordCurrentValuation(_ request: WealthCurrentValuationRequest) throws -> WealthCurrentValuationResult {
        guard maintenanceState == .ready else { throw WealthCorrectionError.maintenanceUnavailable }
        guard request.candidate.id == request.expected.targetID else { throw WealthCorrectionError.invalidRequest }
        return try queue.write { db in
            let before = try checkedBefore(db, token: request.expected)
            let next = try WealthCorrectionSQL.normalizedCandidate(request.candidate, before: before,
                fxIntent: request.fxIntent, occurredAt: request.occurredAt)
            let a = WealthCorrectionProjection(before), b = WealthCorrectionProjection(next)
            let oldParent = before.container, newParent = next.container
            guard oldParent.id == newParent.id, oldParent.accountID == newParent.accountID,
                  oldParent.name == newParent.name, oldParent.kind == newParent.kind,
                  oldParent.institution == newParent.institution,
                  oldParent.primaryCurrency == newParent.primaryCurrency,
                  oldParent.notes == newParent.notes,
                  oldParent.createdDate == newParent.createdDate,
                  a.details.permitsCurrentValuationChange(to: b.details) else {
                throw WealthCorrectionError.invalidRequest
            }
            guard !a.hasSameImportantValues(as: b) else { return .noChange }
            try Self.updateWealthContainer(next, in: db)
            return .updated
        }
    }

    func correctWealthContainer(_ request: WealthCorrectionRequest) throws -> WealthCorrectionResult {
        guard maintenanceState == .ready else { throw WealthCorrectionError.maintenanceUnavailable }
        guard request.candidate.id == request.expected.targetID else { throw WealthCorrectionError.invalidRequest }
        let reason = request.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reason.count <= 500, !reason.contains("\0") else { throw WealthCorrectionError.invalidRequest }
        let requestDigest = try WealthCorrectionEncoding.digest(WealthCorrectionEncoding.Request(
            candidate: .init(request.candidate), expected: request.expected, reason: reason,
            occurredAt: request.occurredAt, fxIntent: request.fxIntent))
        return try queue.write { db in
            if let row = try Row.fetchOne(db,
                sql: "SELECT * FROM wealth_correction_history WHERE operation_id = ?",
                arguments: [request.operationID.uuidString]) {
                guard row["request_digest"] as String == requestDigest,
                      row["wealth_container_id"] as String == request.candidate.id.uuidString,
                      row["kind"] as String == "correction" else {
                    throw WealthCorrectionError.operationConflict
                }
                let history = try WealthCorrectionSQL.decode(row)
                guard try WealthCorrectionSQL.fetch(db, id: request.candidate.id) != nil else {
                    return .alreadyApplied(history, .deleted)
                }
                let committed: String? = row["post_state_digest"]
                let current = try WealthCorrectionSQL.stateDigest(db, id: request.candidate.id)
                let latest = try WealthCorrectionSQL.latest(db, id: request.candidate.id)
                return .alreadyApplied(history,
                    current == committed && latest == history.id ? .unchanged : .changed)
            }
            let before = try checkedBefore(db, token: request.expected)
            let next = try WealthCorrectionSQL.normalizedCandidate(request.candidate, before: before,
                fxIntent: request.fxIntent, occurredAt: request.occurredAt)
            let old = WealthCorrectionProjection(before), after = WealthCorrectionProjection(next)
            let important = !old.hasSameImportantValues(as: after)
            let minor = before.container.name != next.container.name
                || before.container.notes != next.container.notes
            guard important || minor else { return .noChange }
            if important { _ = try WealthCorrectionEncoding.reason(reason) }
            try Self.updateWealthContainer(next, in: db)
            guard important else { return .minorUpdate }
            let history = try WealthCorrectionSQL.append(db, operationID: request.operationID,
                kind: "correction", occurredAt: request.occurredAt, reason: reason,
                requestDigest: requestDigest,
                postState: WealthCorrectionSQL.stateDigest(db, id: request.candidate.id),
                payload: WealthHistoryPayload(version: 1, before: old, after: after, deletion: nil))
            return .applied(history)
        }
    }

    private func checkedBefore(_ db: Database, token: WealthEditToken) throws -> WealthContainer {
        guard token.storeID == wealthEditStoreID, token.epoch == wealthEditEpoch else {
            throw WealthCorrectionError.staleDraft
        }
        guard let before = try WealthCorrectionSQL.fetch(db, id: token.targetID) else {
            throw WealthPersistenceError.containerNotFound
        }
        guard try WealthCorrectionSQL.stateDigest(db, id: token.targetID) == token.stateDigest,
              try WealthCorrectionSQL.latest(db, id: token.targetID) == token.latestHistoryID else {
            throw WealthCorrectionError.staleDraft
        }
        return before
    }
}
