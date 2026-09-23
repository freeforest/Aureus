import Foundation
import GRDB
import Testing
@testable import Aureus

@Suite("Internal Ledger correction transactions", .serialized)
struct LedgerCorrectionTests {
    @Test("CNY USD and transfer corrections retain original identities and references", arguments: ["CNY", "USD", "transfer"])
    func correctionRoundTrip(_ mode: String) async throws {
        let f = try CorrectionFixture(); defer { f.remove() }
        var store: WealthStore? = try f.open(evidence: true)
        let original = try await f.seed(store!, mode: mode)
        let activity = try await f.activity(store!, entry: original)
        let imported = try await store!.importEvidence(source: f.source, operationID: UUID(), target: .ledger(original.id))
        #expect(imported.availability == .available)
        let token = try await store!.readLedgerEditContext(id: original.id)
        let candidate = try f.changed(original, amount: "200.00", description: "Synthetic corrected")
        let history = try await f.apply(store!, candidate, token: token.token)
        #expect(history.payload.before == LedgerCorrectionProjection(original))
        #expect(history.payload.after == LedgerCorrectionProjection(candidate))
        #expect(try f.created(original.id) == original.recordedAt.millisecondsSince1970)
        #expect(try await store!.fetchLedgerEntries().first == candidate)
        #expect(try await store!.fetchPortfolioActivities(portfolioID: activity.portfolioID).first?.ledgerEntryID == original.id)
        #expect(try f.count("evidence_ledger_links") == 1)
        let summary = try await store!.ledgerSummary()
        #expect(summary.ordinaryInflowCNY.minorUnits == (mode == "transfer" ? 0 : candidate.postings[0].valuation.convertedCNY.minorUnits))
        store = nil
        let reopened = try f.open(evidence: true)
        #expect(try await reopened.ledgerCorrectionHistory(id: original.id) == [history])
        #expect(try await reopened.fetchLedgerEntries().first == candidate)
        try FileManager.default.removeItem(at: f.source)
        #expect(try await reopened.resumeEvidence(operationID: imported.operation.id).availability == .available)
    }

    @Test("Two Core stores and legacy writers invalidate complete-state drafts")
    func staleDraftRejected() async throws {
        let f = try CorrectionFixture(); defer { f.remove() }
        let a = try f.open(), b = try f.open(), original = try await f.seed(a)
        let first = try await a.readLedgerEditContext(id: original.id)
        let second = try await b.readLedgerEditContext(id: original.id)
        _ = try await f.apply(a, f.changed(original, description: "A"), token: first.token)
        await #expect(throws: LedgerCorrectionError.staleDraft) {
            _ = try await f.apply(b, f.changed(original, description: "B"), token: second.token)
        }
        let fresh = try await b.readLedgerEditContext(id: original.id)
        try await a.updateLedgerEntry(f.changed(fresh.entry, description: "legacy writer"))
        await #expect(throws: LedgerCorrectionError.staleDraft) {
            _ = try await f.apply(b, f.changed(fresh.entry, description: "stale"), token: fresh.token)
        }
        #expect(try await a.ledgerCorrectionHistory(id: original.id).count == 1)
    }

    @Test("No-change and auxiliary changes are distinct; identity and refresh noise creates no history")
    func noChangeAndMinorChange() async throws {
        let f = try CorrectionFixture(); defer { f.remove() }
        let store = try f.open(), original = try await f.seed(store)
        let initial = try await store.readLedgerEditContext(id: original.id)
        let before = try f.digest(original.id)
        let noise = try f.changed(original)
        if case .noChange = try await store.correctLedgerEntry(f.request(noise, token: initial.token)) {} else { Issue.record("Expected no-change") }
        #expect(try f.digest(original.id) == before)
        let category = try await store.createCategory(name: "Synthetic Category")
        let tag = try await store.createTag(name: "Synthetic Tag")
        for field in ["note", "category", "tag"] {
            let current = try await store.readLedgerEditContext(id: original.id)
            let candidate = try LedgerEntry(id: original.id, kind: original.kind, civilDate: original.civilDate,
                recordedAt: original.recordedAt, description: original.description,
                category: field == "category" ? category : current.entry.category,
                tags: field == "tag" ? [tag] : current.entry.tags, postings: current.entry.postings,
                note: field == "note" ? "Synthetic note" : current.entry.note)
            if case .minorUpdate = try await store.correctLedgerEntry(f.request(candidate, token: current.token)) {} else { Issue.record("Expected minor update") }
            await #expect(throws: LedgerCorrectionError.staleDraft) {
                _ = try await f.apply(store, f.changed(candidate, description: "old draft"), token: current.token)
            }
        }
        #expect(try await store.ledgerCorrectionHistory(id: original.id).isEmpty)
    }

    @Test("Durable replay compares the complete request and never revives changed or deleted facts")
    func operationReplay() async throws {
        let f = try CorrectionFixture(); defer { f.remove() }
        let store = try f.open(), original = try await f.seed(store)
        let initial = try await store.readLedgerEditContext(id: original.id)
        let candidate = try f.changed(original, description: "B")
        let request = f.request(candidate, token: initial.token)
        let first = try applied(await store.correctLedgerEntry(request))
        if case .alreadyApplied(let history, .unchanged) = try await store.correctLedgerEntry(request) { #expect(history == first) } else { Issue.record("Expected unchanged replay") }
        for variant in ["note", "reason", "time"] {
            let changed = variant == "note" ? try f.changed(candidate, note: "different") : candidate
            let conflict = LedgerCorrectionRequest(candidate: changed, expected: request.expected,
                operationID: request.operationID, reason: variant == "reason" ? "different" : request.reason,
                occurredAt: variant == "time" ? UTCInstant(millisecondsSince1970: 1) : request.occurredAt)
            await #expect(throws: LedgerCorrectionError.operationConflict) { _ = try await store.correctLedgerEntry(conflict) }
        }
        let latest = try await store.readLedgerEditContext(id: original.id)
        _ = try await f.apply(store, original, token: latest.token, time: UTCInstant(millisecondsSince1970: 0))
        await #expect(throws: LedgerCorrectionError.staleDraft) { _ = try await f.apply(store, candidate, token: initial.token) }
        if case .alreadyApplied(_, .changed) = try await store.correctLedgerEntry(request) {} else { Issue.record("Expected changed replay") }
        try await store.deleteLedgerEntry(id: original.id)
        let reopened = try f.open()
        if case .alreadyApplied(_, .deleted) = try await reopened.correctLedgerEntry(request) {} else { Issue.record("Expected deleted replay") }
        #expect(try await reopened.fetchLedgerEntries().isEmpty)
        #expect(try await reopened.ledgerCorrectionHistory(id: original.id).map(\.sequence) == [1, 2, 3])
    }

    @Test("Real history INSERT and child FK failures roll back all owned and external state", arguments: [false, true])
    func historyFailureRollsBack(_ childFailure: Bool) async throws {
        let f = try CorrectionFixture(); defer { f.remove() }
        let store = try f.open(evidence: true), original = try await f.seed(store)
        let activity = try await f.activity(store, entry: original)
        _ = try await store.importEvidence(source: f.source, operationID: UUID(), target: .ledger(original.id))
        let before = try f.digest(original.id), context = try await store.readLedgerEditContext(id: original.id)
        if !childFailure { try f.write("CREATE TRIGGER synthetic_history_failure BEFORE INSERT ON ledger_correction_history BEGIN SELECT RAISE(ABORT,'synthetic-history-reached'); END") }
        let postings = childFailure ? [try f.context.posting(20000, containerID: UUID())] : nil
        let candidate = try f.changed(original, description: "must rollback", postings: postings, note: "rollback note")
        do {
            _ = try await f.apply(store, candidate, token: context.token)
            Issue.record("Expected actual SQL failure")
        } catch let error as DatabaseError {
            if childFailure { #expect(error.extendedResultCode == .SQLITE_CONSTRAINT_FOREIGNKEY) }
            else { #expect(error.message == "synthetic-history-reached") }
        }
        #expect(try f.digest(original.id) == before)
        #expect(try f.count("ledger_correction_history") == 0)
        #expect(try f.count("evidence_ledger_links") == 1)
        #expect(try await store.fetchPortfolioActivities(portfolioID: activity.portfolioID).first?.ledgerEntryID == original.id)
    }

    @Test("Conditional deletion context is atomic and independent of the deleted parent", arguments: ["history", "material", "ordinary"])
    func deleteContextSurvives(_ kind: String) async throws {
        let f = try CorrectionFixture(); defer { f.remove() }
        let store = try f.open(evidence: kind == "material"), original = try await f.seed(store)
        let activity = try await f.activity(store, entry: original)
        if kind == "history" { let token = try await store.readLedgerEditContext(id: original.id); _ = try await f.apply(store, f.changed(original, description: "corrected"), token: token.token) }
        var material: EvidenceImportResult?
        if kind == "material" {
            material = try await store.importEvidence(source: f.source, operationID: UUID(), target: .ledger(original.id))
            _ = try await store.linkEvidence(documentID: material!.operation.documentID, target: .container(f.context.source.id))
        }
        if kind != "ordinary" {
            let before = try f.digest(original.id)
            try f.write("CREATE TRIGGER synthetic_delete_failure BEFORE INSERT ON ledger_correction_history WHEN NEW.kind = 'deletionContext' BEGIN SELECT RAISE(ABORT,'synthetic-delete-reached'); END")
            do { try await store.deleteLedgerEntry(id: original.id); Issue.record("Expected delete history failure") }
            catch let error as DatabaseError { #expect(error.message == "synthetic-delete-reached") }
            #expect(try f.digest(original.id) == before)
            #expect(try await store.fetchPortfolioActivities(portfolioID: activity.portfolioID).first?.ledgerEntryID == original.id)
            try f.write("DROP TRIGGER synthetic_delete_failure")
        }
        try await store.deleteLedgerEntry(id: original.id)
        #expect(try await store.fetchPortfolioActivities(portfolioID: activity.portfolioID).first?.ledgerEntryID == nil)
        let history = try await store.ledgerCorrectionHistory(id: original.id)
        if kind == "ordinary" { #expect(history.isEmpty) }
        else { #expect(history.last?.payload.deletion?.activityIDs == [activity.id]) }
        if let material {
            #expect(history.last?.payload.deletion?.links.count == 1)
            #expect(try f.count("evidence_documents") == 1 && f.count("evidence_container_links") == 1)
            #expect(try await store.resumeEvidence(operationID: material.operation.id).operation.state == .committed)
            try ManagedEvidenceFiles(root: f.managed).validate(try #require(material.operation.file))
        }
        await #expect(throws: LedgerPersistenceError.transactionNotFound) { try await store.deleteLedgerEntry(id: original.id) }
    }

    @Test("Real legacy prefixes preserve IDs USD values and original-schema safety generations", arguments: [1, 2, 3, 4, 5, 6, 7])
    func migrationPrefixes(_ version: Int) async throws {
        let f = try CorrectionFixture(); defer { f.remove() }
        try f.legacy(version)
        let store = try f.open()
        #expect(try await store.schemaVersion() == 8)
        #expect(try f.count("ledger_correction_history") == 0)
        #expect(try f.financialRows() == ["synthetic-account", "synthetic-transaction", "12345", "USD"])
        let safety = try #require(PermanentBackupService.inventory(in: f.backups).validGenerations.first)
        #expect(safety.manifest.schemaVersion == version)
        let check = try PermanentDatabaseValidation.inspectFile(safety.directoryURL.appendingPathComponent("aureus.sqlite"), expectedSchemaVersion: version, requireCurrentApplicationSchema: false)
        #expect(check.schemaVersion == version)
        try await store.migrate()
        #expect(try f.count("ledger_correction_history") == 0)
    }

    @Test("History structure and typed payload corruption are rejected", arguments: ["table", "index", "trigger", "version", "uuid", "amount", "kind", "combination"])
    func historyValidation(_ fault: String) async throws {
        let f = try CorrectionFixture(); defer { f.remove() }
        let store = try f.open(), original = try await f.seed(store)
        let context = try await store.readLedgerEditContext(id: original.id)
        _ = try await f.apply(store, f.changed(original, description: "B"), token: context.token)
        switch fault {
        case "table": try f.write("DROP TABLE ledger_correction_history")
        case "index": try f.write("DROP INDEX ledger_correction_history_target")
        case "trigger": try f.write("DROP TRIGGER ledger_correction_history_no_update")
        default:
            try f.write("DROP TRIGGER ledger_correction_history_no_update")
            let raw = try f.payload()
            var object = try #require(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
            if fault == "version" { object["version"] = 99 }
            else if fault == "combination" { object.removeValue(forKey: "after") }
            else {
                var before = try #require(object["before"] as? [String: Any])
                if fault == "uuid" { before["id"] = "invalid" }
                else if fault == "kind" { before["kind"] = "invalid" }
                else {
                    var posts = try #require(before["postings"] as? [[String: Any]])
                    var valuation = try #require(posts[0]["valuation"] as? [String: Any])
                    var money = try #require(valuation["original"] as? [String: Any]); money["minorUnits"] = -1
                    valuation["original"] = money; posts[0]["valuation"] = valuation; before["postings"] = posts
                }
                object["before"] = before
            }
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
            try f.write("UPDATE ledger_correction_history SET payload = ?", [String(decoding: data, as: UTF8.self)])
            try f.write(LedgerCorrectionSQL.declarations[2].1)
        }
        #expect(throws: (any Error).self) { _ = try f.open() }
    }

    @Test("Immutable history, unique operations and invalid generations retain prior valid backups")
    func historyConstraintsAndRetention() async throws {
        let f = try CorrectionFixture(); defer { f.remove() }
        let store = try f.open(), original = try await f.seed(store)
        let token = try await store.readLedgerEditContext(id: original.id)
        _ = try await f.apply(store, f.changed(original, description: "B"), token: token.token)
        #expect(throws: DatabaseError.self) { try f.write("UPDATE ledger_correction_history SET reason='changed'") }
        #expect(throws: DatabaseError.self) { try f.write("DELETE FROM ledger_correction_history") }
        #expect(throws: DatabaseError.self) { try f.write("INSERT INTO ledger_correction_history(history_id,operation_id,ledger_entry_id,kind,occurred_at_ms,reason,request_digest,post_state_digest,payload) SELECT ?,operation_id,ledger_entry_id,kind,occurred_at_ms,reason,request_digest,post_state_digest,payload FROM ledger_correction_history", [UUID().uuidString]) }
        var generations: [PermanentBackupGeneration] = []
        for _ in 0..<5 { generations.append(try await f.backup(store)) }
        let before = Set(try PermanentBackupService.inventory(in: f.backups).validGenerations.map(\.directoryURL))
        #expect(before.count == 5)
        let sibling = f.backups.appendingPathComponent("synthetic-unknown")
        try Data([7, 8, 9]).write(to: sibling)
        try f.write("DROP TRIGGER ledger_correction_history_no_update")
        try f.write("UPDATE ledger_correction_history SET payload='{}'")
        try f.write(LedgerCorrectionSQL.declarations[2].1)
        await #expect(throws: (any Error).self) { _ = try await f.backup(store) }
        #expect(Set(try PermanentBackupService.inventory(in: f.backups).validGenerations.map(\.directoryURL)) == before)
        #expect(try Data(contentsOf: sibling) == Data([7, 8, 9]))
        let corrupt = try #require(generations.first)
        let url = corrupt.directoryURL.appendingPathComponent("aureus.sqlite")
        let q = try DatabaseQueueFactory.open(at: url)
        try await q.write { db in
            try db.execute(sql: "DROP TRIGGER ledger_correction_history_no_update")
            try db.execute(sql: "UPDATE ledger_correction_history SET payload='{}'")
            try db.execute(sql: LedgerCorrectionSQL.declarations[2].1)
        }
        try q.close()
        let digest = try PermanentBackupService.streamingDigest(of: url)
        let manifest = PermanentBackupManifest(backupFormatVersion: 1, appVersion: corrupt.manifest.appVersion, schemaVersion: 8, createdAt: corrupt.manifest.createdAt, databaseByteCount: digest.byteCount, databaseSHA256: digest.sha256)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var bytes = try encoder.encode(manifest); bytes.append(10)
        try bytes.write(to: corrupt.directoryURL.appendingPathComponent("manifest.json"))
        #expect(throws: (any Error).self) { _ = try f.export(corrupt) }
        #expect(try PermanentBackupService.inventory(in: f.backups).validGenerations.count == 4)
        #expect(FileManager.default.fileExists(atPath: corrupt.directoryURL.path))
    }

    @Test("Legacy v7 Evidence structure remains validated and future v9 remains unknown", arguments: [false, true])
    func legacyEvidenceAndFutureValidation(_ future: Bool) throws {
        let f = try CorrectionFixture(); defer { f.remove() }
        try f.legacy(7)
        if future { try f.write("UPDATE schema_metadata SET version=9 WHERE store_kind='permanent'") }
        else { try f.write("DROP INDEX evidence_ledger_links_target") }
        #expect(throws: (any Error).self) {
            _ = try PermanentDatabaseValidation.inspectFile(f.database, expectedSchemaVersion: future ? 9 : 7, requireCurrentApplicationSchema: false)
        }
        #expect(throws: (any Error).self) { _ = try f.open() }
        #expect(try PermanentBackupService.inventory(in: f.backups).validGenerations.isEmpty)
    }

    @Test("History-only backups export and restore deleted-parent history without merging timelines")
    func historyOnlyLifecycle() async throws {
        let f = try CorrectionFixture(); defer { f.remove() }
        let store = try f.open(), original = try await f.seed(store)
        let token = try await store.readLedgerEditContext(id: original.id)
        _ = try await f.apply(store, f.changed(original, description: "history B"), token: token.token)
        try await store.deleteLedgerEntry(id: original.id)
        let history = try await store.ledgerCorrectionHistory(id: original.id)
        let generation = try await f.backup(store)
        #expect(try FileManager.default.contentsOfDirectory(atPath: generation.directoryURL.path).sorted() == ["aureus.sqlite", "manifest.json"])
        let exported = try f.export(generation)
        _ = try await f.restore(store, generation)
        #expect(try await store.ledgerCorrectionHistory(id: original.id) == history)
        _ = try await store.restoreExternalPermanentBackup(exported, configuration: .init(internalBackupRootURL: f.backups, permanentDatabaseURL: f.database, marketCacheDatabaseURL: f.cache, additionalProtectedSourceRoots: []), appVersion: "synthetic", createdAt: f.context.instant)
        #expect(try await store.ledgerCorrectionHistory(id: original.id) == history)
        #expect(try await store.fetchLedgerEntries().isEmpty)
        let legacy = try CorrectionFixture(); defer { legacy.remove() }
        try legacy.legacy(7)
        let queue = try DatabaseQueueFactory.open(at: legacy.database)
        let old = try PermanentBackupService.create(from: queue, in: f.backups, appVersion: "synthetic", createdAt: f.context.instant, generationID: UUID())
        try queue.close()
        let result = try await f.restore(store, old)
        #expect(try await store.ledgerCorrectionHistory(id: original.id).isEmpty)
        let safe = f.backups.appendingPathComponent(result.safetyGenerationIdentity).appendingPathComponent("aureus.sqlite")
        #expect(try f.historyCount(at: safe) == history.count)
    }

    @Test("Both successful replacement and actual rollback invalidate instance drafts", arguments: [false, true])
    func restoreInvalidatesDraft(_ fail: Bool) async throws {
        let f = try CorrectionFixture(); defer { f.remove() }
        let store = try f.open(), original = try await f.seed(store)
        let token = try await store.readLedgerEditContext(id: original.id)
        let generation = try await f.backup(store)
        let operations = CorrectionRestoreOperations(fail: fail)
        if fail {
            await #expect(throws: PermanentRestoreError.restoreFailedRollbackSucceeded(.schema)) {
                _ = try await f.restore(store, generation, operations: operations)
            }
            #expect(operations.replacements == 2)
        } else { _ = try await f.restore(store, generation, operations: operations); #expect(operations.replacements == 1) }
        await #expect(throws: LedgerCorrectionError.staleDraft) { _ = try await f.apply(store, f.changed(original, description: "stale"), token: token.token) }
        let fresh = try await store.readLedgerEditContext(id: original.id)
        _ = try await f.apply(store, f.changed(original, description: "fresh"), token: fresh.token)
    }

    @Test("Material-bearing real v7 cannot create a false complete migration safety backup", arguments: ["document", "operation", "artifact"])
    func materialMigrationStillBlocked(_ mode: String) throws {
        let f = try CorrectionFixture(); defer { f.remove() }
        try f.legacy(7)
        let id = UUID()
        if mode == "artifact" { try Data("synthetic unknown".utf8).write(to: f.managed.appendingPathComponent("sentinel")) }
        else if mode == "operation" {
            try f.write("INSERT INTO evidence_import_operations(operation_id,document_id,ledger_entry_id,intended_meaning,original_filename,relative_reference,registered_at_ms,updated_at_ms,state) VALUES (?,?,?,'','synthetic',?,0,0,'registered')", [UUID().uuidString, id.uuidString, UUID().uuidString, id.uuidString.lowercased()+".original"])
        } else {
            var stamp: ManagedEvidenceIdentity?
            let file = try ManagedEvidenceFiles(root: f.managed).copy(source: f.source, documentID: id, observer: { receipt in
                if case .prepared(_, let identity) = receipt { stamp = identity }
            })
            let identity = try #require(stamp)
            let copied = Int64(file.copiedAt.timeIntervalSince1970 * 1000)
            try f.write("INSERT INTO evidence_import_operations(operation_id,document_id,ledger_entry_id,intended_meaning,original_filename,relative_reference,registered_at_ms,updated_at_ms,state,root_device,root_inode,file_device,file_inode,byte_count,sha256,copied_at_ms) VALUES (?,?,?,'',?,?,0,0,'committed',?,?,?,?,?,?,?)", [UUID().uuidString, id.uuidString, UUID().uuidString, file.originalFilename, file.relativeReference, identity.rootDevice, String(identity.rootInode), identity.fileDevice, String(identity.fileInode), file.byteCount, file.sha256, copied])
            try f.write("INSERT INTO evidence_documents(id,original_filename,relative_reference,byte_count,sha256,copied_at_ms,registered_at_ms) VALUES (?,?,?,?,?,?,?)", [file.id.uuidString, file.originalFilename, file.relativeReference, file.byteCount, file.sha256, copied, 0])
            try f.read { try EvidenceSQL.validateSchema($0) }
        }
        let before = try f.scalar("SELECT version FROM schema_metadata WHERE store_kind='permanent'")
        let names = try FileManager.default.contentsOfDirectory(atPath: f.managed.path)
        #expect(throws: (any Error).self) { _ = try f.open(evidence: true) }
        #expect(try f.scalar("SELECT version FROM schema_metadata WHERE store_kind='permanent'") == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.managed.path) == names)
        #expect(try PermanentBackupService.inventory(in: f.backups).validGenerations.isEmpty)
        #expect(try f.financialRows() == ["synthetic-account", "synthetic-transaction", "12345", "USD"])
    }

    @Test("CSV semantic duplicate preview follows corrected live facts; legacy update remains usable")
    func csvAndLegacyWriterCompatibility() async throws {
        let f = try CorrectionFixture(); defer { f.remove() }
        let store = try f.open(), original = try await f.seed(store)
        let context = try await store.readLedgerEditContext(id: original.id)
        let corrected = try f.changed(original, description: "CSV corrected")
        _ = try await f.apply(store, corrected, token: context.token)
        let duplicate = try LedgerEntry(kind: corrected.kind, civilDate: corrected.civilDate, recordedAt: corrected.recordedAt, description: corrected.description, postings: corrected.postings)
        let identities = try await store.existingImportIdentities()
        let preview = try LedgerCSV.preview(data: LedgerCSV.export([duplicate]), containers: [f.context.source], categories: [], tags: [], rules: [], existingFingerprints: identities.fingerprints, existingTransactionIDs: identities.transactionIDs)
        #expect(preview.rows.first?.duplicateReasons == [.existingFingerprint])
        #expect(!preview.canImport)
        try await store.updateLedgerEntry(original)
        #expect(try await store.ledgerCorrectionHistory(id: original.id).count == 1)
        #expect(try f.created(original.id) == original.recordedAt.millisecondsSince1970)
    }
}

private func applied(_ result: LedgerCorrectionResult) throws -> LedgerCorrectionHistory {
    guard case .applied(let history) = result else { throw LedgerCorrectionError.invalidHistory }; return history
}

private struct CorrectionFixture: @unchecked Sendable {
    let root: URL, database: URL, backups: URL, managed: URL, source: URL, cache: URL, destination: URL
    let context: LedgerTestContext
    init() throws {
        root = try temporaryDirectory(); context = try LedgerTestContext.make()
        database = root.appendingPathComponent("Permanent/aureus.sqlite"); backups = root.appendingPathComponent("Backups", isDirectory: true)
        managed = root.appendingPathComponent("Materials", isDirectory: true); source = root.appendingPathComponent("synthetic.bin")
        cache = root.appendingPathComponent("Cache/market.sqlite"); destination = root.appendingPathComponent("External", isDirectory: true)
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        try Data([0, 1, 2, 255]).write(to: source)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func open(evidence: Bool = false) throws -> WealthStore {
        try WealthStore(databaseURL: database, migrationSafetyConfiguration: .init(backupRoot: backups, appVersion: "synthetic", createdAt: { context.instant }, generationID: { UUID() }), evidenceConfiguration: evidence ? .init(root: managed, protectedPaths: [backups, cache]) : nil)
    }
    func read<T>(_ body: (Database) throws -> T) throws -> T { let q = try DatabaseQueueFactory.open(at: database); defer { try? q.close() }; return try q.read(body) }
    func write(_ sql: String, _ arguments: StatementArguments = []) throws { let q = try DatabaseQueueFactory.open(at: database); defer { try? q.close() }; try q.write { try $0.execute(sql: sql, arguments: arguments) } }
    func scalar(_ sql: String) throws -> Int { try read { try Int.fetchOne($0, sql: sql)! } }
    func count(_ table: String) throws -> Int { try scalar("SELECT COUNT(*) FROM \(table)") }
    func digest(_ id: UUID) throws -> String { try read { try LedgerCorrectionSQL.stateDigest($0, id: id) } }
    func created(_ id: UUID) throws -> Int64 { try read { try Int64.fetchOne($0, sql: "SELECT created_at_ms FROM ledger_transactions WHERE id=?", arguments: [id.uuidString])! } }
    func payload() throws -> String { try read { try String.fetchOne($0, sql: "SELECT payload FROM ledger_correction_history LIMIT 1")! } }
    func historyCount(at url: URL) throws -> Int { let q = try DatabaseQueueFactory.open(at: url); defer { try? q.close() }; return try q.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM ledger_correction_history")! } }
    func seed(_ store: WealthStore, mode: String = "CNY") async throws -> LedgerEntry {
        try await store.createWealthContainer(context.source); try await store.createWealthContainer(context.target)
        let entry = mode == "transfer" ? try context.transfer(target: "14.28", targetCurrency: .usd) : try LedgerEntry(kind: .income, civilDate: context.date, recordedAt: context.instant, description: "Synthetic A", postings: [.init(role: .primary, containerID: context.source.id, valuation: context.valuation("100.00", currency: mode == "USD" ? .usd : .cny))])
        try await store.createLedgerEntry(entry); return entry
    }
    func changed(_ entry: LedgerEntry, amount: String? = nil, description: String? = nil, postings: [LedgerPosting]? = nil, note: String? = nil) throws -> LedgerEntry {
        let values = try postings ?? entry.postings.map { posting in
            let value = try amount.map { try context.valuation($0, currency: posting.valuation.original.currency) } ?? posting.valuation
            return try LedgerPosting(role: posting.role, containerID: posting.containerID, valuation: value)
        }
        return try LedgerEntry(id: entry.id, kind: entry.kind, civilDate: entry.civilDate, recordedAt: entry.recordedAt, description: description ?? entry.description, payee: entry.payee, category: entry.category, tags: entry.tags, postings: values, note: note ?? entry.note, importFingerprint: entry.importFingerprint)
    }
    func request(_ entry: LedgerEntry, token: LedgerEditToken, time: UTCInstant? = nil) -> LedgerCorrectionRequest { .init(candidate: entry, expected: token, operationID: UUID(), reason: "Synthetic correction", occurredAt: time ?? context.instant) }
    func apply(_ store: WealthStore, _ entry: LedgerEntry, token: LedgerEditToken, time: UTCInstant? = nil) async throws -> LedgerCorrectionHistory { try applied(await store.correctLedgerEntry(request(entry, token: token, time: time))) }
    func activity(_ store: WealthStore, entry: LedgerEntry) async throws -> PortfolioActivity {
        let security = try SyntheticWealthSeeder.records()[2]; try await store.createWealthContainer(security)
        let portfolio = try PortfolioRecord(name: "Synthetic Correction", createdAt: entry.recordedAt, updatedAt: entry.recordedAt, sortOrder: 0); try await store.createPortfolio(portfolio)
        let link = try PortfolioSecurityLink(portfolioID: portfolio.id, wealthContainerID: security.id, symbol: "SYNX", rawMIC: "XSYN", currency: .usd, assetKind: .stock, sortOrder: 0); try await store.linkPortfolioSecurity(link)
        let cost = Money(minorUnits: 10000, currency: .usd)
        let fx = try PortfolioFXProvenance(original: cost, rate: FXRate(decimal: 7, sourceCurrency: .usd, targetCurrency: .cny), source: "synthetic.manual", referenceDate: entry.civilDate, recordedAt: entry.recordedAt, isManual: true, isStale: false)
        let activity = try PortfolioActivity(portfolioID: portfolio.id, securityLinkID: link.id, civilDate: entry.civilDate, recordedAt: entry.recordedAt, exchangeTimeZoneIdentifier: "UTC", ledgerEntryID: entry.id, payload: .openingLot(quantity: AssetQuantity(coefficient: 100_000_000), totalCost: cost, fx: fx, note: "Synthetic"))
        try await store.createPortfolioActivity(activity); return activity
    }
    func legacy(_ version: Int) throws {
        let q = try DatabaseQueueFactory.open(at: database); defer { try? q.close() }
        try DatabaseMigrations.permanentMigrator().migrate(q, upTo: PermanentDatabaseValidation.migrationIdentifiers[version-1])
        try q.write { db in
            try db.execute(sql: "INSERT INTO accounts(id,name,kind,currency_code) VALUES ('synthetic-account','Synthetic USD','other','USD')")
            try db.execute(sql: "INSERT INTO wealth_transactions(id,account_id,civil_date,amount_minor,currency_code,type) VALUES ('synthetic-transaction','synthetic-account','2026-01-15',12345,'USD','income')")
        }
    }
    func financialRows() throws -> [String] { try read { db in let row = try Row.fetchOne(db, sql: "SELECT account_id,id,amount_minor,currency_code FROM wealth_transactions")!; return [row["account_id"],row["id"],String(row["amount_minor"] as Int64),row["currency_code"]] } }
    func backup(_ store: WealthStore) async throws -> PermanentBackupGeneration { try await store.createPermanentBackup(in: backups, appVersion: "synthetic", createdAt: context.instant, generationID: UUID()) }
    func restore(_ store: WealthStore, _ generation: PermanentBackupGeneration, operations: any PermanentRestoreFileOperations = LocalPermanentRestoreFileOperations()) async throws -> PermanentRestoreResult { try await store.restorePermanentBackup(generation.directoryURL, in: backups, appVersion: "synthetic", createdAt: context.instant, fileOperations: operations) }
    func export(_ generation: PermanentBackupGeneration) throws -> URL {
        let result = try PermanentBackupExportService.export(internalGenerationURL: generation.directoryURL, to: destination, configuration: .init(internalBackupRootURL: backups, permanentDatabaseURL: database, marketCacheDatabaseURL: cache, additionalProtectedDestinationRoots: []), operationID: UUID())
        return destination.appendingPathComponent(result.exportedGenerationIdentity, isDirectory: true)
    }
}

private final class CorrectionRestoreOperations: PermanentRestoreFileOperations, @unchecked Sendable {
    let fail: Bool
    private(set) var replacements = 0
    init(fail: Bool) { self.fail = fail }
    func copyValidatedDatabase(from sourceURL: URL, to stagingURL: URL) throws { try LocalPermanentRestoreFileOperations().copyValidatedDatabase(from: sourceURL, to: stagingURL) }
    func atomicallyReplaceDatabase(at databaseURL: URL, with stagingURL: URL) throws {
        try LocalPermanentRestoreFileOperations().atomicallyReplaceDatabase(at: databaseURL, with: stagingURL)
        replacements += 1
        if fail && replacements == 1 {
            let q = try DatabaseQueueFactory.open(at: databaseURL); defer { try? q.close() }
            try q.write { try $0.execute(sql: "UPDATE schema_metadata SET version=9 WHERE store_kind='permanent'") }
        }
    }
}
