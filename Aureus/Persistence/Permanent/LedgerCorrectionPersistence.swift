import Foundation
import GRDB

enum LedgerCorrectionSQL {
    static let table = "ledger_correction_history"
    static func uuidConstraint(_ column: String) -> String {
        "length(\(column)) = 36 AND \(column) = upper(\(column)) AND substr(\(column),9,1) = '-' AND substr(\(column),14,1) = '-' AND substr(\(column),19,1) = '-' AND substr(\(column),24,1) = '-' AND length(replace(\(column),'-','')) = 32 AND replace(\(column),'-','') NOT GLOB '*[^0-9A-F]*'"
    }
    static let declarations: [(String, String)] = [
        (table, """
            CREATE TABLE ledger_correction_history (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                history_id TEXT NOT NULL UNIQUE CHECK (\(uuidConstraint("history_id"))),
                operation_id TEXT NOT NULL UNIQUE CHECK (\(uuidConstraint("operation_id"))),
                ledger_entry_id TEXT NOT NULL CHECK (\(uuidConstraint("ledger_entry_id"))),
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
        ("ledger_correction_history_target", "CREATE INDEX ledger_correction_history_target ON ledger_correction_history(ledger_entry_id, sequence)"),
        ("ledger_correction_history_no_update", "CREATE TRIGGER ledger_correction_history_no_update BEFORE UPDATE ON ledger_correction_history BEGIN SELECT RAISE(ABORT, 'immutable ledger history'); END"),
        ("ledger_correction_history_no_delete", "CREATE TRIGGER ledger_correction_history_no_delete BEFORE DELETE ON ledger_correction_history BEGIN SELECT RAISE(ABORT, 'immutable ledger history'); END")
    ]

    struct State: Encodable {
        let parent: LedgerTransactionRow
        let postings: [LedgerPostingRow]
        let tags: [String]
    }
    static func stateDigest(_ db: Database, id: UUID) throws -> String {
        guard let parent = try LedgerTransactionRow.fetchOne(db, sql: "SELECT * FROM ledger_transactions WHERE id = ?", arguments: [id.uuidString]) else {
            throw LedgerPersistenceError.transactionNotFound
        }
        return try LedgerCorrectionEncoding.digest(State(parent: parent,
            postings: LedgerPostingRow.fetchAll(db, sql: "SELECT * FROM ledger_postings WHERE transaction_id = ? ORDER BY role, id", arguments: [id.uuidString]),
            tags: String.fetchAll(db, sql: "SELECT tag_id FROM ledger_transaction_tags WHERE transaction_id = ? ORDER BY tag_id", arguments: [id.uuidString])))
    }
    static func latest(_ db: Database, id: UUID) throws -> UUID? {
        guard let value = try String.fetchOne(db, sql: "SELECT history_id FROM ledger_correction_history WHERE ledger_entry_id = ? ORDER BY sequence DESC LIMIT 1", arguments: [id.uuidString]) else { return nil }
        return try uuid(value)
    }
    static func uuid(_ raw: String) throws -> UUID {
        guard let id = UUID(uuidString: raw), id.uuidString == raw else { throw LedgerCorrectionError.invalidHistory }
        return id
    }
    static func decode(_ row: Row) throws -> LedgerCorrectionHistory {
        let raw: String = row["payload"]
        let bytes = Data(raw.utf8)
        let payload = try JSONDecoder().decode(LedgerHistoryPayload.self, from: bytes)
        guard try LedgerCorrectionEncoding.data(payload) == bytes else { throw LedgerCorrectionError.invalidHistory }
        let kind: String = row["kind"]
        try payload.validate(kind: kind)
        let target = try uuid(row["ledger_entry_id"])
        let reason: String? = row["reason"]
        if kind == "correction" {
            guard let reason, try LedgerCorrectionEncoding.reason(reason) == reason else { throw LedgerCorrectionError.invalidHistory }
        } else if reason != nil { throw LedgerCorrectionError.invalidHistory }
        let sequence: Int64 = row["sequence"]
        guard sequence > 0, payload.before.id == target else { throw LedgerCorrectionError.invalidHistory }
        return LedgerCorrectionHistory(sequence: sequence, id: try uuid(row["history_id"]),
            operationID: try uuid(row["operation_id"]), targetID: target, kind: kind,
            occurredAt: UTCInstant(millisecondsSince1970: row["occurred_at_ms"]), reason: reason, payload: payload)
    }
    static func validateSchema(_ db: Database) throws {
        func normalized(_ sql: String) -> String { sql.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased() }
        for (name, sql) in declarations {
            guard let actual = try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE name = ?", arguments: [name]),
                  normalized(actual) == normalized(sql) else { throw PermanentDatabaseValidationFailure.applicationInvariant }
        }
        for row in try Row.fetchAll(db, sql: "SELECT * FROM ledger_correction_history ORDER BY sequence") { _ = try decode(row) }
    }
    static func append(_ db: Database, operationID: UUID, kind: String, occurredAt: UTCInstant,
                       reason: String?, requestDigest: String, postState: String?, payload: LedgerHistoryPayload) throws -> LedgerCorrectionHistory {
        try payload.validate(kind: kind)
        let id = UUID()
        let text = String(decoding: try LedgerCorrectionEncoding.data(payload), as: UTF8.self)
        try db.execute(sql: """
            INSERT INTO ledger_correction_history(history_id, operation_id, ledger_entry_id, kind, occurred_at_ms, reason, request_digest, post_state_digest, payload)
            VALUES (?,?,?,?,?,?,?,?,?)
            """, arguments: [id.uuidString, operationID.uuidString, payload.before.id.uuidString, kind,
                occurredAt.millisecondsSince1970, reason, requestDigest, postState, text])
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM ledger_correction_history WHERE history_id = ?", arguments: [id.uuidString]) else { throw LedgerCorrectionError.invalidHistory }
        return try decode(row)
    }
    static func deletionContext(_ db: Database, id: UUID) throws {
        let hasHistory = try latest(db, id: id) != nil
        let links = try Row.fetchAll(db, sql: "SELECT * FROM evidence_ledger_links WHERE ledger_entry_id = ? ORDER BY link_id", arguments: [id.uuidString])
        guard hasHistory || !links.isEmpty else { return }
        guard let before = try WealthStore.fetchLedgerEntries(in: db).first(where: { $0.id == id }) else { throw LedgerPersistenceError.transactionNotFound }
        let context = LedgerDeletionContext(origin: "existingDeleteAPI", links: try links.map {
            .init(documentID: try uuid($0["document_id"]), linkID: try uuid($0["link_id"]),
                  createdAt: UTCInstant(millisecondsSince1970: $0["created_at_ms"]), meaning: $0["meaning"])
        }, activityIDs: try String.fetchAll(db, sql: "SELECT id FROM portfolio_activities WHERE ledger_entry_id = ? ORDER BY id", arguments: [id.uuidString]).map(uuid))
        let payload = LedgerHistoryPayload(version: 1, before: .init(before), after: nil, deletion: context)
        _ = try append(db, operationID: UUID(), kind: "deletionContext", occurredAt: SystemClock().now(),
            reason: nil, requestDigest: LedgerCorrectionEncoding.digest(payload), postState: nil, payload: payload)
    }
}

extension WealthStore {
    func readLedgerEditContext(id: UUID) throws -> LedgerEditContext {
        guard maintenanceState == .ready else { throw LedgerCorrectionError.maintenanceUnavailable }
        return try queue.read { db in
            guard let entry = try Self.fetchLedgerEntries(in: db).first(where: { $0.id == id }) else { throw LedgerPersistenceError.transactionNotFound }
            return LedgerEditContext(entry: entry, token: LedgerEditToken(targetID: id,
                stateDigest: try LedgerCorrectionSQL.stateDigest(db, id: id), latestHistoryID: try LedgerCorrectionSQL.latest(db, id: id),
                storeID: ledgerEditStoreID, epoch: ledgerEditEpoch))
        }
    }
    func ledgerCorrectionHistory(id: UUID) throws -> [LedgerCorrectionHistory] {
        guard maintenanceState == .ready else { throw LedgerCorrectionError.maintenanceUnavailable }
        return try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM ledger_correction_history WHERE ledger_entry_id = ? ORDER BY sequence", arguments: [id.uuidString]).map(LedgerCorrectionSQL.decode)
        }
    }
    func correctLedgerEntry(_ request: LedgerCorrectionRequest) throws -> LedgerCorrectionResult {
        guard maintenanceState == .ready else { throw LedgerCorrectionError.maintenanceUnavailable }
        let candidate = request.candidate, token = request.expected
        guard candidate.id == token.targetID else { throw LedgerCorrectionError.invalidRequest }
        let reason = request.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reason.count <= 500, !reason.contains("\0") else { throw LedgerCorrectionError.invalidRequest }
        let requestDigest = try LedgerCorrectionEncoding.digest(LedgerCorrectionEncoding.Request(
            candidate: .init(candidate), expected: token, reason: reason, occurredAt: request.occurredAt))
        return try queue.write { db in
            if let row = try Row.fetchOne(db, sql: "SELECT * FROM ledger_correction_history WHERE operation_id = ?", arguments: [request.operationID.uuidString]) {
                guard row["request_digest"] as String == requestDigest, row["ledger_entry_id"] as String == candidate.id.uuidString else { throw LedgerCorrectionError.operationConflict }
                let history = try LedgerCorrectionSQL.decode(row)
                guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ledger_transactions WHERE id = ?", arguments: [candidate.id.uuidString]) == 1 else { return .alreadyApplied(history, .deleted) }
                let committedDigest: String? = row["post_state_digest"]
                let currentDigest = try LedgerCorrectionSQL.stateDigest(db, id: candidate.id)
                let currentHistory = try LedgerCorrectionSQL.latest(db, id: candidate.id)
                let unchanged = currentDigest == committedDigest && currentHistory == history.id
                return .alreadyApplied(history, unchanged ? .unchanged : .changed)
            }
            guard token.storeID == ledgerEditStoreID, token.epoch == ledgerEditEpoch else { throw LedgerCorrectionError.staleDraft }
            guard let before = try Self.fetchLedgerEntries(in: db).first(where: { $0.id == candidate.id }) else { throw LedgerPersistenceError.transactionNotFound }
            guard try LedgerCorrectionSQL.stateDigest(db, id: candidate.id) == token.stateDigest,
                  try LedgerCorrectionSQL.latest(db, id: candidate.id) == token.latestHistoryID else { throw LedgerCorrectionError.staleDraft }
            let old = LedgerCorrectionProjection(before), next = LedgerCorrectionProjection(candidate)
            try next.validate()
            let important = !old.hasSameImportantValues(as: next)
            let minor = before.note != candidate.note || before.category?.id != candidate.category?.id
                || Set(before.tags.map(\.id)) != Set(candidate.tags.map(\.id)) || before.importFingerprint != candidate.importFingerprint
            guard important || minor else { return .noChange }
            if important { _ = try LedgerCorrectionEncoding.reason(reason) }
            try Self.updateLedgerEntry(candidate, in: db)
            guard important else { return .minorUpdate }
            let history = try LedgerCorrectionSQL.append(db, operationID: request.operationID, kind: "correction",
                occurredAt: request.occurredAt, reason: reason, requestDigest: requestDigest,
                postState: LedgerCorrectionSQL.stateDigest(db, id: candidate.id),
                payload: LedgerHistoryPayload(version: 1, before: old, after: next, deletion: nil))
            return .applied(history)
        }
    }
}
