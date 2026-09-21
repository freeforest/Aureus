import Foundation
import Darwin
import GRDB

enum EvidenceSQL {
    static let tables = ["evidence_documents", "evidence_ledger_links", "evidence_container_links", "evidence_portfolio_activity_links", "evidence_import_operations"]

    static func containsEvidence(_ db: Database) throws -> Bool {
        for table in tables where try db.tableExists(table) {
            if try Int.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM \(table))") == 1 { return true }
        }
        return false
    }

    static func targetExists(_ target: EvidenceTarget, in db: Database) throws -> Bool {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(target.table) WHERE id = ?", arguments: [target.id.uuidString]) == 1
    }

    static func document(_ row: Row) throws -> EvidenceDocument {
        let file = ManagedEvidenceFile(id: try EvidenceValue.uuid(row["id"]), originalFilename: row["original_filename"],
            relativeReference: row["relative_reference"], byteCount: row["byte_count"], sha256: row["sha256"],
            copiedAt: Date(timeIntervalSince1970: Double(row["copied_at_ms"] as Int64) / 1_000))
        try EvidenceValue.file(file)
        return EvidenceDocument(file: file, registeredAt: row["registered_at_ms"])
    }

    static func operation(_ row: Row) throws -> EvidenceImportOperation {
        let choices: [EvidenceTarget] = try ["ledger_entry_id", "container_id", "portfolio_activity_id"].enumerated().compactMap { index, column in
            guard let text: String = row[column] else { return nil }
            let id = try EvidenceValue.uuid(text)
            return index == 0 ? .ledger(id) : index == 1 ? .container(id) : .portfolioActivity(id)
        }
        guard choices.count == 1, let state = EvidenceImportState(rawValue: row["state"]) else { throw EvidenceError.inconsistentRegistration }
        let id = try EvidenceValue.uuid(row["document_id"])
        guard row["relative_reference"] as String == id.uuidString.lowercased() + ".original" else { throw EvidenceError.inconsistentRegistration }
        let identity: ManagedEvidenceIdentity?
        if let rootDevice: Int32 = row["root_device"] {
            guard let root: String = row["root_inode"], let rootInode = UInt64(root), String(rootInode) == root,
                  let fileDevice: Int32 = row["file_device"], let file: String = row["file_inode"],
                  let fileInode = UInt64(file), String(fileInode) == file else { throw EvidenceError.inconsistentRegistration }
            identity = .init(rootDevice: rootDevice, rootInode: rootInode, fileDevice: fileDevice, fileInode: fileInode)
        } else { identity = nil }
        let file: ManagedEvidenceFile?
        if let bytes: Int64 = row["byte_count"] {
            guard let hash: String = row["sha256"], let time: Int64 = row["copied_at_ms"] else { throw EvidenceError.inconsistentRegistration }
            file = .init(id: id, originalFilename: row["original_filename"], relativeReference: row["relative_reference"],
                byteCount: bytes, sha256: hash, copiedAt: Date(timeIntervalSince1970: Double(time) / 1_000))
            try EvidenceValue.file(file!)
        } else { file = nil }
        return EvidenceImportOperation(id: try EvidenceValue.uuid(row["operation_id"]), documentID: id, target: choices[0],
            meaning: row["intended_meaning"], originalFilename: row["original_filename"], registeredAt: row["registered_at_ms"],
            state: state, identity: identity, file: file,
            lastError: (row["last_error"] as String?).flatMap(EvidenceError.init(rawValue:)))
    }

    static func validateSchema(_ db: Database) throws {
        func normalized(_ sql: String) -> String { sql.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
        for table in DatabaseMigrations.evidenceTables {
            guard let actual = try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?", arguments: [table.name]),
                  normalized(actual) == normalized(table.sql) else { throw PermanentDatabaseValidationFailure.applicationInvariant }
        }
        for target in [EvidenceTarget.ledger(UUID()), .container(UUID()), .portfolioActivity(UUID())] {
            let foreign = try Row.fetchAll(db, sql: "PRAGMA foreign_key_list(\(target.linkTable))")
            guard foreign.count == 2,
                  foreign.contains(where: { ($0["from"] as String) == "document_id" && ($0["on_delete"] as String) == "RESTRICT" }),
                  foreign.contains(where: { ($0["from"] as String) == target.column && ($0["on_delete"] as String) == "CASCADE" }),
                  try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = ?", arguments: [target.linkTable + "_target"]) == "CREATE INDEX \(target.linkTable)_target ON \(target.linkTable)(\(target.column))" else {
                throw PermanentDatabaseValidationFailure.applicationInvariant
            }
        }
        for row in try Row.fetchAll(db, sql: "SELECT * FROM evidence_documents") {
            let doc = try document(row)
            guard let receipt = try Row.fetchOne(db, sql: "SELECT * FROM evidence_import_operations WHERE document_id = ? AND state = 'committed'", arguments: [doc.id.uuidString]),
                  try operation(receipt).file == doc.file,
                  try operation(receipt).registeredAt == doc.registeredAt else { throw EvidenceError.inconsistentRegistration }
        }
        for row in try Row.fetchAll(db, sql: "SELECT * FROM evidence_import_operations") {
            let op = try operation(row)
            let stored = try Row.fetchOne(db, sql: "SELECT * FROM evidence_documents WHERE id = ?", arguments: [op.documentID.uuidString])
            if op.state == .committed {
                guard let stored, try document(stored).file == op.file else { throw EvidenceError.inconsistentRegistration }
            } else if stored != nil { throw EvidenceError.inconsistentRegistration }
        }
    }
}

extension WealthStore {
    func evidenceOperation(_ id: UUID) throws -> EvidenceImportOperation? {
        try requireEvidence()
        return try queue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM evidence_import_operations WHERE operation_id = ?", arguments: [id.uuidString]).map(EvidenceSQL.operation)
        }
    }

    func importEvidence(source: URL, operationID: UUID, target: EvidenceTarget, meaning: String = "",
                        cancelled: @Sendable () -> Bool = { false }) throws -> EvidenceImportResult {
        try requireEvidence()
        try EvidenceValue.text(meaning)
        try EvidenceValue.text(source.lastPathComponent, nonempty: true)
        if let prior = try evidenceOperation(operationID) {
            guard prior.target == target, prior.meaning == meaning, prior.originalFilename == source.lastPathComponent else { throw EvidenceError.operationConflict }
            return try resumeEvidence(operationID: operationID)
        }
        let documentID = UUID()
        let time = try EvidenceValue.milliseconds(Date())
        try queue.write { db in
            guard try EvidenceSQL.targetExists(target, in: db) else { throw EvidenceError.targetMissing }
            try db.execute(sql: """
                INSERT INTO evidence_import_operations
                (operation_id,document_id,\(target.column),intended_meaning,original_filename,relative_reference,registered_at_ms,updated_at_ms,state)
                VALUES (?,?,?,?,?,?,?,?,'registered')
                """, arguments: [operationID.uuidString, documentID.uuidString, target.id.uuidString, meaning,
                    source.lastPathComponent, documentID.uuidString.lowercased() + ".original", time, time])
        }
        let files = try evidenceFiles()
        let database = queue
        do {
            _ = try files.copy(source: source, documentID: documentID, observer: { receipt in
                try database.write { db in
                    let identity: ManagedEvidenceIdentity
                    let file: ManagedEvidenceFile?
                    switch receipt {
                    case .stagingOwned(let value): identity = value; file = nil
                    case .prepared(let value, let stamp): identity = stamp; file = value; try EvidenceValue.file(value)
                    }
                    try db.execute(sql: """
                        UPDATE evidence_import_operations SET state = ?, root_device = ?, root_inode = ?, file_device = ?, file_inode = ?,
                        byte_count = ?, sha256 = ?, copied_at_ms = ?, updated_at_ms = ?
                        WHERE operation_id = ? AND state = ?
                        """, arguments: [file == nil ? "stagingOwned" : "prepared", identity.rootDevice, String(identity.rootInode),
                            identity.fileDevice, String(identity.fileInode), file?.byteCount, file?.sha256,
                            try file.map { try EvidenceValue.milliseconds($0.copiedAt) }, time, operationID.uuidString,
                            file == nil ? "registered" : "stagingOwned"])
                    guard db.changesCount == 1 else { throw EvidenceError.operationConflict }
                }
            }, cancelled: cancelled)
        } catch let error as ManagedEvidenceFileError {
            // A prepared receipt is retained even when publication or post-publication verification fails.
            if error.reason == .cancelled && error.artifact == nil {
                try queue.write { db in
                    try db.execute(sql: "UPDATE evidence_import_operations SET state = 'cancelled' WHERE operation_id = ? AND state != 'committed'", arguments: [operationID.uuidString])
                }
            }
            guard let op = try evidenceOperation(operationID) else { throw EvidenceError.inconsistentRegistration }
            return .init(operation: op, availability: op.state == .cancelled ? .cancelled : error.artifact?.state == .published ? .publishedPendingRecovery : .pendingReview)
        }
        return try resumeEvidence(operationID: operationID)
    }

    func resumeEvidence(operationID: UUID) throws -> EvidenceImportResult {
        try requireEvidence()
        guard var op = try evidenceOperation(operationID) else { throw EvidenceError.operationConflict }
        if op.state == .registered {
            // Exact owned namespace only; never discover or adopt a source or an unknown file.
            guard let root = datasetAccess.evidence?.root else { throw EvidenceError.disabled }
            let name = op.documentID.uuidString.lowercased()
            let occupied = [name + ".original", "." + name + ".pending"].contains {
                var info = stat()
                // Never follow a dangling link and misclassify its occupied name as absent.
                return lstat(root.appendingPathComponent($0).path, &info) == 0 || errno != ENOENT
            }
            return .init(operation: op, availability: occupied ? .pendingReview : .needsSourceSelection)
        }
        if op.state == .cancelled { return .init(operation: op, availability: .cancelled) }
        guard op.state == .prepared || op.state == .committed,
              let file = op.file, let identity = op.identity else { return .init(operation: op, availability: .pendingReview) }
        let files = try evidenceFiles()
        if op.state == .committed {
            try queue.read { db in
                guard let row = try Row.fetchOne(db, sql: "SELECT * FROM evidence_documents WHERE id = ?", arguments: [op.documentID.uuidString]),
                      try EvidenceSQL.document(row).file == file,
                      try EvidenceSQL.document(row).registeredAt == op.registeredAt else { throw EvidenceError.inconsistentRegistration }
            }
        }
        do { try files.validate(file, expectedIdentity: identity) }
        catch { return .init(operation: op, availability: .materialUnavailable) }
        if op.state == .prepared {
            do {
                try queue.write { db in
                    guard let row = try Row.fetchOne(db, sql: "SELECT * FROM evidence_import_operations WHERE operation_id = ?", arguments: [operationID.uuidString]),
                          try EvidenceSQL.operation(row) == op else { throw EvidenceError.operationConflict }
                    guard try Row.fetchOne(db, sql: "SELECT id FROM evidence_documents WHERE id = ?", arguments: [op.documentID.uuidString]) == nil else { throw EvidenceError.inconsistentRegistration }
                    guard try EvidenceSQL.targetExists(op.target, in: db) else { throw EvidenceError.targetMissing }
                    try db.execute(sql: "INSERT INTO evidence_documents (id,original_filename,relative_reference,byte_count,sha256,copied_at_ms,registered_at_ms) VALUES (?,?,?,?,?,?,?)", arguments: [file.id.uuidString,file.originalFilename,file.relativeReference,file.byteCount,file.sha256,try EvidenceValue.milliseconds(file.copiedAt),op.registeredAt])
                    _ = try Self.insertEvidenceLink(documentID: file.id, target: op.target, meaning: op.meaning, at: op.registeredAt, db: db)
                    try db.execute(sql: "UPDATE evidence_import_operations SET state = 'committed', last_error = NULL WHERE operation_id = ? AND state = 'prepared'", arguments: [op.id.uuidString])
                    guard db.changesCount == 1 else { throw EvidenceError.operationConflict }
                }
            } catch let error as EvidenceError where error == .inconsistentRegistration || error == .operationConflict { throw error }
            catch { return .init(operation: op, availability: .publishedPendingRecovery) }
            guard let committed = try evidenceOperation(operationID) else { throw EvidenceError.inconsistentRegistration }
            op = committed
            do { try datasetAccess.evidence?.afterCommit() }
            catch { return .init(operation: op, availability: .materialUnavailable) }
        }
        let available: EvidenceImportResult.Availability = try queue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM evidence_documents WHERE id = ?", arguments: [op.documentID.uuidString]),
                  try EvidenceSQL.document(row).file == file else { throw EvidenceError.inconsistentRegistration }
            if try !EvidenceSQL.targetExists(op.target, in: db) { return .targetRemoved }
            let relation = try Self.readEvidenceLink(documentID: op.documentID, target: op.target, db: db)
            guard relation?.meaning == op.meaning else { return .relationshipChanged }
            return .available
        }
        do { try files.validate(file, expectedIdentity: identity) }
        catch { return .init(operation: op, availability: .materialUnavailable) }
        return .init(operation: op, availability: available)
    }

    func linkEvidence(documentID: UUID, target: EvidenceTarget, meaning: String = "") throws -> EvidenceRelation {
        try requireEvidence()
        try EvidenceValue.text(meaning)
        let (doc, identity) = try queue.read { db -> (EvidenceDocument, ManagedEvidenceIdentity) in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM evidence_documents WHERE id = ?", arguments: [documentID.uuidString]) else { throw EvidenceError.inconsistentRegistration }
            let doc = try EvidenceSQL.document(row)
            guard let receipt = try Row.fetchOne(db, sql: "SELECT * FROM evidence_import_operations WHERE document_id = ? AND state = 'committed'", arguments: [documentID.uuidString]) else { throw EvidenceError.inconsistentRegistration }
            let operation = try EvidenceSQL.operation(receipt)
            guard operation.file == doc.file, let identity = operation.identity else { throw EvidenceError.inconsistentRegistration }
            return (doc, identity)
        }
        try evidenceFiles().validate(doc.file, expectedIdentity: identity)
        let result = try queue.write { db in
            guard try EvidenceSQL.targetExists(target, in: db) else { throw EvidenceError.targetMissing }
            return try Self.insertEvidenceLink(documentID: documentID, target: target, meaning: meaning, at: EvidenceValue.milliseconds(Date()), db: db)
        }
        try evidenceFiles().validate(doc.file, expectedIdentity: identity)
        return result
    }

    private nonisolated static func readEvidenceLink(documentID: UUID, target: EvidenceTarget, db: Database) throws -> EvidenceRelation? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM \(target.linkTable) WHERE document_id = ? AND \(target.column) = ?", arguments: [documentID.uuidString,target.id.uuidString]) else { return nil }
        return .init(id: try EvidenceValue.uuid(row["link_id"]), documentID: documentID, target: target, createdAt: row["created_at_ms"], meaning: row["meaning"])
    }

    private nonisolated static func insertEvidenceLink(documentID: UUID, target: EvidenceTarget, meaning: String, at: Int64, db: Database) throws -> EvidenceRelation {
        if let existing = try readEvidenceLink(documentID: documentID, target: target, db: db) { return existing }
        let id = UUID()
        try db.execute(sql: "INSERT INTO \(target.linkTable) (document_id,\(target.column),link_id,created_at_ms,meaning) VALUES (?,?,?,?,?)", arguments: [documentID.uuidString,target.id.uuidString,id.uuidString,at,meaning])
        return .init(id: id, documentID: documentID, target: target, createdAt: at, meaning: meaning)
    }

    private func requireEvidence() throws {
        guard maintenanceState == .ready else { throw EvidenceError.maintenanceUnavailable }
        try datasetAccess.validateRoot()
    }

    private func evidenceFiles() throws -> ManagedEvidenceFiles {
        guard let evidenceFilesService else { throw EvidenceError.disabled }
        return evidenceFilesService
    }

    func requireFormatOneEligible() throws {
        guard maintenanceState == .ready else { throw EvidenceError.maintenanceUnavailable }
        try datasetAccess.requireEmptyEvidenceRoot()
        try queue.read { db in
            guard try !EvidenceSQL.containsEvidence(db) else { throw EvidenceError.legacyFormatUnsupported }
        }
    }
}
