import Foundation
import GRDB
import Testing
@testable import Aureus

@Suite("Internal Wealth correction transactions", .serialized)
struct WealthCorrectionTests {
    @Test("All seven Wealth kinds retain current authority and typed before/after history", arguments: [0, 1, 2, 3, 4, 5, 6])
    func correctionRoundTrip(_ index: Int) async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let store = try f.open(), before = try SyntheticWealthSeeder.records()[index]
        try await store.createWealthContainer(before)
        let context = try await store.readWealthEditContext(id: before.id)
        let next = try f.changeValue(before)
        let oldSummary = try await store.wealthSummary()
        let history = try wealthApplied(await store.correctWealthContainer(f.request(next, token: context.token)))
        #expect(history.payload.before == WealthCorrectionProjection(before))
        #expect(history.payload.after == WealthCorrectionProjection(next))
        #expect(try await store.fetchWealthContainer(id: before.id) == next)
        #expect(try await store.wealthCorrectionHistory(id: before.id) == [history])
        #expect(try await store.wealthSummary() != oldSummary)
        let reopened = try f.open()
        #expect(try await reopened.fetchWealthContainer(id: before.id) == next)
        #expect(try await reopened.wealthCorrectionHistory(id: before.id) == [history])
        let currentSummary = try await store.wealthSummary()
        #expect(try await reopened.wealthSummary() == currentSummary)
        #expect(before.container.createdDate == next.container.createdDate && before.id == next.id)
    }

    @Test("Normal valuation is a narrow whitelist; FX-only is explicit")
    func normalValuationAndFX() async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let store = try f.open(), old = try SyntheticWealthSeeder.records()[1]
        try await store.createWealthContainer(old)
        let token = try await store.readWealthEditContext(id: old.id)
        let changed = try f.changeValue(old)
        #expect(try await store.recordCurrentValuation(.init(candidate: changed, expected: token.token,
            occurredAt: f.instant, fxIntent: .preserve)) == .updated)
        #expect(try await store.wealthCorrectionHistory(id: old.id).isEmpty)
        #expect(try await store.fetchWealthContainer(id: old.id)?.valuation.fetchedAt == old.valuation.fetchedAt)
        let fresh = try await store.readWealthEditContext(id: old.id)
        let current = fresh.record
        let rate = try FXRate(decimal: Decimal(string: "7.25")!, sourceCurrency: .usd, targetCurrency: .cny)
        let fx = try FXValuation(original: current.originalValue, rate: rate,
            referenceDate: old.valuation.referenceDate, fetchedAt: f.instant,
            providerIdentifier: "manual.synthetic.new", isManualOverride: true, isStale: false)
        let fxOnly = try WealthContainer(container: current.container, details: current.details, valuation: fx)
        #expect(try await store.recordCurrentValuation(.init(candidate: fxOnly, expected: fresh.token,
            occurredAt: f.instant, fxIntent: .newInput)) == .updated)
        #expect(try await store.fetchWealthContainer(id: old.id)?.valuation == fx)
        let newToken = try await store.readWealthEditContext(id: old.id)
        let illegal = try f.changeParent(newToken.record, institution: "Different institution")
        await #expect(throws: WealthCorrectionError.invalidRequest) {
            _ = try await store.recordCurrentValuation(.init(candidate: illegal, expected: newToken.token,
                occurredAt: f.instant, fxIntent: .preserve))
        }
        #expect(try await store.wealthCorrectionHistory(id: old.id).isEmpty)
    }

    @Test("Only the per-kind current-value field is allowed as a normal valuation", arguments: [0, 1, 2, 3, 4, 5, 6])
    func valuationWhitelistAllKinds(_ index: Int) async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let store = try f.open(), old = try SyntheticWealthSeeder.records()[index]
        try await store.createWealthContainer(old)
        let context = try await store.readWealthEditContext(id: old.id)
        let next = try f.changeValue(old)
        #expect(try await store.recordCurrentValuation(.init(candidate: next, expected: context.token,
            occurredAt: f.instant, fxIntent: .preserve)) == .updated)
        #expect(try await store.fetchWealthContainer(id: old.id) == next)
        #expect(try await store.wealthCorrectionHistory(id: old.id).isEmpty)
    }

    @Test("No change and name/notes-only update do not create important history")
    func noChangeAndMinor() async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let store = try f.open(), old = try SyntheticWealthSeeder.records()[0]
        try await store.createWealthContainer(old)
        let context = try await store.readWealthEditContext(id: old.id)
        let before = try f.digest(old.id)
        if case .noChange = try await store.correctWealthContainer(f.request(old, token: context.token, reason: "")) {}
        else { Issue.record("Expected no change") }
        #expect(try f.digest(old.id) == before)
        let minor = try f.changeParent(old, name: "Synthetic renamed")
        if case .minorUpdate = try await store.correctWealthContainer(f.request(minor, token: context.token, reason: "")) {}
        else { Issue.record("Expected minor update") }
        #expect(try await store.wealthCorrectionHistory(id: old.id).isEmpty)
        await #expect(throws: WealthCorrectionError.staleDraft) {
            _ = try await store.correctWealthContainer(f.request(f.changeValue(old), token: context.token))
        }
    }

    @Test("Important correction requires a bounded explicit reason", arguments: ["   ", "bad\0reason", String(repeating: "x", count: 501)])
    func reasonValidation(_ reason: String) async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let store = try f.open(), old = try SyntheticWealthSeeder.records()[0]
        try await store.createWealthContainer(old)
        let context = try await store.readWealthEditContext(id: old.id)
        await #expect(throws: WealthCorrectionError.invalidRequest) {
            _ = try await store.correctWealthContainer(f.request(f.changeValue(old), token: context.token, reason: reason))
        }
        #expect(try await store.fetchWealthContainer(id: old.id) == old)
        #expect(try await store.wealthCorrectionHistory(id: old.id).isEmpty)
    }

    @Test("Two Core stores, old writers and important A-to-B-to-A reject stale state")
    func staleDraftAndImportantABA() async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let a = try f.open(), b = try f.open(), old = try SyntheticWealthSeeder.records()[0]
        try await a.createWealthContainer(old)
        let first = try await a.readWealthEditContext(id: old.id)
        let second = try await b.readWealthEditContext(id: old.id)
        let changed = try f.changeValue(old)
        _ = try wealthApplied(await a.correctWealthContainer(f.request(changed, token: first.token)))
        await #expect(throws: WealthCorrectionError.staleDraft) {
            _ = try await b.correctWealthContainer(f.request(changed, token: second.token))
        }
        let afterB = try await a.readWealthEditContext(id: old.id)
        _ = try wealthApplied(await a.correctWealthContainer(f.request(old, token: afterB.token,
            occurredAt: UTCInstant(millisecondsSince1970: 0))))
        await #expect(throws: WealthCorrectionError.staleDraft) {
            _ = try await a.correctWealthContainer(f.request(changed, token: first.token))
        }
        let beforeLegacy = try await a.readWealthEditContext(id: old.id)
        try await b.updateWealthContainer(try f.changeParent(old, name: "Legacy changed"))
        await #expect(throws: WealthCorrectionError.staleDraft) {
            _ = try await a.correctWealthContainer(f.request(changed, token: beforeLegacy.token))
        }
        #expect(try await a.wealthCorrectionHistory(id: old.id).count == 2)
    }

    @Test("Durable operation replay checks full intent and never revives later facts")
    func operationReplay() async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let store = try f.open(), old = try SyntheticWealthSeeder.records()[0]
        try await store.createWealthContainer(old)
        let context = try await store.readWealthEditContext(id: old.id)
        let next = try f.changeValue(old), request = f.request(next, token: context.token)
        let first = try wealthApplied(await store.correctWealthContainer(request))
        if case .alreadyApplied(let history, .unchanged) = try await store.correctWealthContainer(request) {
            #expect(history == first)
        } else { Issue.record("Expected unchanged replay") }
        let conflicting = WealthCorrectionRequest(candidate: next, expected: request.expected,
            operationID: request.operationID, reason: "Different reason", occurredAt: request.occurredAt,
            fxIntent: request.fxIntent)
        await #expect(throws: WealthCorrectionError.operationConflict) {
            _ = try await store.correctWealthContainer(conflicting)
        }
        let changedCandidate = WealthCorrectionRequest(candidate: try f.changeParent(next, name: "Other name"),
            expected: request.expected, operationID: request.operationID, reason: request.reason,
            occurredAt: request.occurredAt, fxIntent: request.fxIntent)
        await #expect(throws: WealthCorrectionError.operationConflict) {
            _ = try await store.correctWealthContainer(changedCandidate)
        }
        let changedTime = WealthCorrectionRequest(candidate: next, expected: request.expected,
            operationID: request.operationID, reason: request.reason,
            occurredAt: UTCInstant(millisecondsSince1970: 1), fxIntent: request.fxIntent)
        await #expect(throws: WealthCorrectionError.operationConflict) {
            _ = try await store.correctWealthContainer(changedTime)
        }
        let later = try await store.readWealthEditContext(id: old.id)
        _ = try wealthApplied(await store.correctWealthContainer(f.request(old, token: later.token)))
        if case .alreadyApplied(_, .changed) = try await store.correctWealthContainer(request) {}
        else { Issue.record("Expected changed replay") }
        try await store.deleteWealthContainer(id: old.id)
        let reopened = try f.open()
        if case .alreadyApplied(_, .deleted) = try await reopened.correctWealthContainer(request) {}
        else { Issue.record("Expected deleted replay") }
        #expect(try await reopened.fetchWealthContainer(id: old.id) == nil)
    }

    @Test("Real history INSERT, parent FK and child UPDATE failures roll back both tables", arguments: ["history", "parentFK", "child"])
    func historyFailureRollsBack(_ failure: String) async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let store = try f.open(), old = try SyntheticWealthSeeder.records()[0]
        try await store.createWealthContainer(old)
        let context = try await store.readWealthEditContext(id: old.id)
        let before = try f.digest(old.id)
        var next = try f.changeValue(old)
        switch failure {
        case "history": try f.write("CREATE TRIGGER synthetic_wealth_history_failure BEFORE INSERT ON wealth_correction_history BEGIN SELECT RAISE(ABORT,'wealth-history-reached'); END")
        case "parentFK": next = try f.changeParent(next, accountID: UUID())
        default: try f.write("CREATE TRIGGER synthetic_wealth_child_failure BEFORE UPDATE ON wealth_records BEGIN SELECT RAISE(ABORT,'wealth-child-reached'); END")
        }
        do {
            _ = try await store.correctWealthContainer(f.request(next, token: context.token))
            Issue.record("Expected targeted SQL failure")
        } catch let error as DatabaseError {
            if failure == "history" { #expect(error.message == "wealth-history-reached") }
            else if failure == "parentFK" { #expect(error.extendedResultCode == .SQLITE_CONSTRAINT_FOREIGNKEY) }
            else { #expect(error.message == "wealth-child-reached") }
        }
        #expect(try f.digest(old.id) == before)
        #expect(try f.count("wealth_correction_history") == 0)
        #expect(try await store.fetchWealthContainer(id: old.id) == old)
    }

    @Test("Conditional deletion history is independent of its former parent", arguments: ["history", "ordinary"])
    func deleteContextSurvives(_ variant: String) async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let store = try f.open(), old = try SyntheticWealthSeeder.records()[0]
        try await store.createWealthContainer(old)
        if variant == "history" {
            let token = try await store.readWealthEditContext(id: old.id)
            _ = try wealthApplied(await store.correctWealthContainer(f.request(f.changeValue(old), token: token.token)))
            try f.write("CREATE TRIGGER synthetic_wealth_delete_failure BEFORE INSERT ON wealth_correction_history WHEN NEW.kind='deletionContext' BEGIN SELECT RAISE(ABORT,'wealth-delete-reached'); END")
            do { _ = try await store.deleteWealthContainer(id: old.id); Issue.record("Expected deletion-history failure") }
            catch let error as DatabaseError { #expect(error.message == "wealth-delete-reached") }
            #expect(try await store.fetchWealthContainer(id: old.id) != nil)
            try f.write("DROP TRIGGER synthetic_wealth_delete_failure")
        }
        _ = try await store.deleteWealthContainer(id: old.id)
        #expect(try await store.fetchWealthContainer(id: old.id) == nil)
        let history = try await store.wealthCorrectionHistory(id: old.id)
        #expect(history.count == (variant == "history" ? 2 : 0))
        if variant == "history" { #expect(history.last?.payload.deletion?.origin == "existingDeleteAPI") }
    }

    @Test("Shared Evidence material survives a target deletion with exact link context")
    func materialDeleteContext() async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let store = try f.open(evidence: true)
        let rows = try SyntheticWealthSeeder.records(), old = rows[0], other = rows[1]
        try await store.createWealthContainer(old)
        try await store.createWealthContainer(other)
        let imported = try await store.importEvidence(source: f.source, operationID: UUID(), target: .container(old.id))
        #expect(imported.availability == .available)
        _ = try await store.linkEvidence(documentID: imported.operation.documentID, target: .container(other.id))
        _ = try await store.deleteWealthContainer(id: old.id)
        let history = try await store.wealthCorrectionHistory(id: old.id)
        #expect(history.count == 1)
        #expect(history[0].payload.deletion?.links.count == 1)
        #expect(history[0].payload.deletion?.links[0].documentID == imported.operation.documentID)
        #expect(try f.count("evidence_documents") == 1)
        #expect(try f.count("evidence_container_links") == 1)
        #expect(try await store.resumeEvidence(operationID: imported.operation.id).operation.state == .committed)
    }

    @Test("Actual schema prefixes preserve their own safety generation", arguments: [1, 2, 3, 4, 5, 6, 7, 8])
    func migrationPrefixes(_ version: Int) async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let q = try DatabaseQueueFactory.open(at: f.database)
        try DatabaseMigrations.permanentMigrator().migrate(q,
            upTo: PermanentDatabaseValidation.migrationIdentifiers[version - 1])
        try await q.write { db in
            try db.execute(sql: "INSERT INTO accounts(id,name,kind,currency_code) VALUES ('wealth-legacy','Synthetic Legacy','other','USD')")
        }
        try q.close()
        let store = try f.open()
        #expect(try await store.schemaVersion() == 9)
        #expect(try f.count("wealth_correction_history") == 0)
        let safety = try #require(PermanentBackupService.inventory(in: f.backups).validGenerations.first)
        #expect(safety.manifest.schemaVersion == version)
        #expect(try PermanentDatabaseValidation.inspectFile(
            safety.directoryURL.appendingPathComponent("aureus.sqlite"), expectedSchemaVersion: version,
            requireCurrentApplicationSchema: false).schemaVersion == version)
        try await store.migrate()
        #expect(try f.count("wealth_correction_history") == 0)
    }

    @Test("Typed history and immutable structure reject corrupt rows", arguments: ["table", "index", "trigger", "version", "amount", "kind"])
    func historyValidation(_ fault: String) async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let store = try f.open(), old = try SyntheticWealthSeeder.records()[0]
        try await store.createWealthContainer(old)
        let context = try await store.readWealthEditContext(id: old.id)
        _ = try wealthApplied(await store.correctWealthContainer(f.request(f.changeValue(old), token: context.token)))
        switch fault {
        case "table": try f.write("DROP TABLE wealth_correction_history")
        case "index": try f.write("DROP INDEX wealth_correction_history_target")
        case "trigger": try f.write("DROP TRIGGER wealth_correction_history_no_update")
        default:
            try f.write("DROP TRIGGER wealth_correction_history_no_update")
            let raw = try f.read { try String.fetchOne($0, sql: "SELECT payload FROM wealth_correction_history LIMIT 1")! }
            var object = try #require(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
            if fault == "version" { object["version"] = 99 }
            else if fault == "kind" { object.removeValue(forKey: "after") }
            else {
                var before = try #require(object["before"] as? [String: Any])
                var valuation = try #require(before["valuation"] as? [String: Any])
                var money = try #require(valuation["original"] as? [String: Any])
                money["minorUnits"] = -1
                valuation["original"] = money; before["valuation"] = valuation; object["before"] = before
            }
            let data = try JSONSerialization.data(withJSONObject: object,
                options: [.sortedKeys, .withoutEscapingSlashes])
            try f.write("UPDATE wealth_correction_history SET payload = ?", [String(decoding: data, as: UTF8.self)])
            try f.write(WealthCorrectionSQL.declarations[2].1)
        }
        #expect(throws: (any Error).self) { _ = try f.open() }
    }

    @Test("History-only format1 Backup, internal/external Restore and export retain SQLite history")
    func historyOnlyLifecycle() async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let store = try f.open(), old = try SyntheticWealthSeeder.records()[0]
        try await store.createWealthContainer(old)
        let token = try await store.readWealthEditContext(id: old.id)
        _ = try wealthApplied(await store.correctWealthContainer(f.request(f.changeValue(old), token: token.token)))
        _ = try await store.deleteWealthContainer(id: old.id)
        let history = try await store.wealthCorrectionHistory(id: old.id)
        let generation = try await f.backup(store)
        #expect(try FileManager.default.contentsOfDirectory(atPath: generation.directoryURL.path).sorted()
            == ["aureus.sqlite", "manifest.json"])
        let exported = try f.export(generation)
        _ = try await f.restore(store, generation)
        #expect(try await store.wealthCorrectionHistory(id: old.id) == history)
        _ = try await store.restoreExternalPermanentBackup(exported,
            configuration: .init(internalBackupRootURL: f.backups, permanentDatabaseURL: f.database,
                marketCacheDatabaseURL: f.cache, additionalProtectedSourceRoots: []),
            appVersion: "synthetic", createdAt: f.instant)
        #expect(try await store.wealthCorrectionHistory(id: old.id) == history)
    }

    @Test("Corrupt Wealth history is not a valid generation and cannot prune clean generations")
    func invalidHistoryGenerationNoPrune() async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let store = try f.open(), old = try SyntheticWealthSeeder.records()[0]
        try await store.createWealthContainer(old)
        let token = try await store.readWealthEditContext(id: old.id)
        _ = try wealthApplied(await store.correctWealthContainer(f.request(f.changeValue(old), token: token.token)))
        var clean: [PermanentBackupGeneration] = []
        for _ in 0..<5 { clean.append(try await f.backup(store)) }
        let validBefore = Set(try PermanentBackupService.inventory(in: f.backups).validGenerations.map(\.directoryURL))
        #expect(validBefore.count == 5)
        let first = try #require(clean.first)
        let forged = f.backups.appendingPathComponent("backup-20270101T000000000Z-" + UUID().uuidString.lowercased(), isDirectory: true)
        try FileManager.default.copyItem(at: first.directoryURL, to: forged)
        let dbURL = forged.appendingPathComponent("aureus.sqlite")
        let q = try DatabaseQueueFactory.open(at: dbURL)
        try await q.write { db in
            try db.execute(sql: "DROP TRIGGER wealth_correction_history_no_update")
            try db.execute(sql: "UPDATE wealth_correction_history SET payload='{}'")
            try db.execute(sql: WealthCorrectionSQL.declarations[2].1)
        }
        try q.close()
        let digest = try PermanentBackupService.streamingDigest(of: dbURL)
        let manifest = PermanentBackupManifest(backupFormatVersion: 1,
            appVersion: first.manifest.appVersion, schemaVersion: 9,
            createdAt: first.manifest.createdAt,
            databaseByteCount: digest.byteCount, databaseSHA256: digest.sha256)
        try JSONEncoder().encode(manifest).write(to: forged.appendingPathComponent("manifest.json"))
        #expect(throws: (any Error).self) {
            _ = try PermanentBackupService.validateGeneration(forged, in: f.backups)
        }
        let inventory = try PermanentBackupService.pruneValidGenerations(in: f.backups)
        #expect(Set(inventory.validGenerations.map(\.directoryURL)) == validBefore)
        #expect(inventory.invalidGenerations.count == 1)
        #expect(FileManager.default.fileExists(atPath: forged.path))
    }

    @Test("Restore success and actual rollback invalidate prior instance Wealth drafts", arguments: [false, true])
    func restoreInvalidatesDraft(_ fail: Bool) async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let store = try f.open(), old = try SyntheticWealthSeeder.records()[0]
        try await store.createWealthContainer(old)
        let stale = try await store.readWealthEditContext(id: old.id)
        let generation = try await f.backup(store)
        let operations = WealthCorrectionRestoreOperations(fail: fail)
        if fail {
            await #expect(throws: PermanentRestoreError.restoreFailedRollbackSucceeded(.schema)) {
                _ = try await f.restore(store, generation, operations: operations)
            }
            #expect(operations.replacements == 2)
        } else {
            _ = try await f.restore(store, generation, operations: operations)
            #expect(operations.replacements == 1)
        }
        await #expect(throws: WealthCorrectionError.staleDraft) {
            _ = try await store.correctWealthContainer(f.request(f.changeValue(old), token: stale.token))
        }
        let fresh = try await store.readWealthEditContext(id: old.id)
        _ = try wealthApplied(await store.correctWealthContainer(f.request(f.changeValue(old), token: fresh.token)))
    }

    @Test("Real v8 material, operation and unknown owned artifact remain protected", arguments: ["document", "operation", "unknownRoot"])
    func materialMigrationStillBlocked(_ variant: String) async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let q = try DatabaseQueueFactory.open(at: f.database)
        try DatabaseMigrations.permanentMigrator().migrate(q, upTo: DatabaseMigrations.permanentV8)
        let id = UUID(), op = UUID()
        if variant == "document" {
            let record = try SyntheticWealthSeeder.records()[0]
            var identity: ManagedEvidenceIdentity?
            let file = try ManagedEvidenceFiles(root: f.managed).copy(source: f.source, documentID: id,
                observer: { receipt in
                    switch receipt {
                    case .stagingOwned: break
                    case .prepared(_, let value): identity = value
                    }
                })
            let stamp = try #require(identity)
            try await q.write { db in
                try AssetContainerPersistenceRow(container: record.container).insert(db)
                try WealthRecordPersistenceRow(record: record).insert(db)
                try db.execute(sql: """
                    INSERT INTO evidence_import_operations(operation_id,document_id,container_id,
                        intended_meaning,original_filename,relative_reference,registered_at_ms,updated_at_ms,state,
                        root_device,root_inode,file_device,file_inode,byte_count,sha256,copied_at_ms)
                    VALUES (?,?,?,'',?,?,0,0,'committed',?,?,?,?,?,?,?)
                    """, arguments: [op.uuidString, id.uuidString, record.id.uuidString,
                        file.originalFilename, file.relativeReference, stamp.rootDevice, String(stamp.rootInode),
                        stamp.fileDevice, String(stamp.fileInode), file.byteCount, file.sha256,
                        try EvidenceValue.milliseconds(file.copiedAt)])
                try db.execute(sql: """
                    INSERT INTO evidence_documents(id,original_filename,relative_reference,
                        byte_count,sha256,copied_at_ms,registered_at_ms)
                    VALUES (?,?,?,?,?,?,0)
                    """, arguments: [id.uuidString, file.originalFilename, file.relativeReference,
                        file.byteCount, file.sha256, try EvidenceValue.milliseconds(file.copiedAt)])
            }
        } else if variant == "operation" {
            try await q.write { db in
                try db.execute(sql: """
                    INSERT INTO evidence_import_operations(operation_id,document_id,container_id,
                        intended_meaning,original_filename,relative_reference,registered_at_ms,updated_at_ms,state)
                    VALUES (?,?,?,'','synthetic.bin',?,0,0,'registered')
                    """, arguments: [op.uuidString, id.uuidString, UUID().uuidString,
                        id.uuidString.lowercased() + ".original"])
            }
        } else {
            try Data("synthetic unknown artifact".utf8).write(to: f.managed.appendingPathComponent("unknown.bin"))
        }
        try q.close()
        #expect(throws: (any Error).self) { _ = try f.open(evidence: true) }
        #expect(try f.read { try Int.fetchOne($0,
            sql: "SELECT version FROM schema_metadata WHERE store_kind='permanent'") } == 8)
        #expect(try PermanentBackupService.inventory(in: f.backups).validGenerations.isEmpty)
        if variant == "document" {
            #expect(try f.count("evidence_documents") == 1)
            #expect(FileManager.default.fileExists(atPath: f.managed.appendingPathComponent(id.uuidString.lowercased() + ".original").path))
        }
        if variant == "unknownRoot" {
            #expect(try Data(contentsOf: f.managed.appendingPathComponent("unknown.bin"))
                == Data("synthetic unknown artifact".utf8))
        }
    }
}

private func wealthApplied(_ result: WealthCorrectionResult) throws -> WealthCorrectionHistory {
    guard case let .applied(history) = result else { throw WealthCorrectionError.invalidHistory }
    return history
}

private struct WealthCorrectionFixture: @unchecked Sendable {
    let root: URL, database: URL, backups: URL, destination: URL, cache: URL, managed: URL, source: URL
    let instant = UTCInstant(millisecondsSince1970: 1_800_000_000_000)

    init() throws {
        root = try temporaryDirectory()
        database = root.appendingPathComponent("Permanent/aureus.sqlite")
        backups = root.appendingPathComponent("Backups", isDirectory: true)
        destination = root.appendingPathComponent("External", isDirectory: true)
        cache = root.appendingPathComponent("Cache/market.sqlite")
        managed = root.appendingPathComponent("Materials", isDirectory: true)
        source = root.appendingPathComponent("synthetic.bin")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: false)
        try Data([0, 1, 2, 255]).write(to: source)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func open(evidence: Bool = false) throws -> WealthStore {
        try WealthStore(databaseURL: database,
            migrationSafetyConfiguration: .init(backupRoot: backups, appVersion: "synthetic",
                createdAt: { instant }, generationID: { UUID() }),
            evidenceConfiguration: evidence ? .init(root: managed, protectedPaths: [backups, cache]) : nil)
    }
    func read<T>(_ body: (Database) throws -> T) throws -> T {
        let q = try DatabaseQueueFactory.open(at: database); defer { try? q.close() }
        return try q.read(body)
    }
    func write(_ sql: String, _ args: StatementArguments = []) throws {
        let q = try DatabaseQueueFactory.open(at: database); defer { try? q.close() }
        try q.write { try $0.execute(sql: sql, arguments: args) }
    }
    func count(_ table: String) throws -> Int { try read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)")! } }
    func digest(_ id: UUID) throws -> String { try read { try WealthCorrectionSQL.stateDigest($0, id: id) } }
    func request(_ record: WealthContainer, token: WealthEditToken, reason: String = "Synthetic correction",
                 occurredAt: UTCInstant? = nil) -> WealthCorrectionRequest {
        .init(candidate: record, expected: token, operationID: UUID(), reason: reason,
              occurredAt: occurredAt ?? instant, fxIntent: .preserve)
    }
    func changeParent(_ record: WealthContainer, name: String? = nil,
                      institution: String? = nil, accountID: UUID? = nil) throws -> WealthContainer {
        let old = record.container
        let parent = AssetContainer(id: old.id, accountID: accountID ?? old.accountID,
            name: name ?? old.name, kind: old.kind, institution: institution ?? old.institution,
            primaryCurrency: old.primaryCurrency, notes: old.notes,
            createdDate: old.createdDate, updatedDate: old.updatedDate)
        return try WealthContainer(container: parent, details: record.details, valuation: record.valuation)
    }
    func changeValue(_ record: WealthContainer) throws -> WealthContainer {
        let value: WealthRecordDetails
        switch record.details {
        case let .bankCash(balance, rate):
            value = .bankCash(balance: Money(minorUnits: balance.minorUnits + 100, currency: balance.currency), interestRate: rate)
        case let .security(ticker, mic, quantity, price):
            value = .security(ticker: ticker, mic: mic, quantity: quantity,
                manualPrice: try MarketPrice(coefficient: price.coefficient + 100_000_000, quoteCurrency: price.quoteCurrency))
        case let .insurance(company, name, premium, frequency, coverage, current, start, maturity):
            value = .insurance(company: company, productName: name, premium: premium,
                paymentFrequency: frequency, coverage: coverage,
                currentCashValue: Money(minorUnits: current.minorUnits + 100, currency: current.currency),
                startDate: start, maturityDate: maturity)
        case let .otherAsset(description, current):
            value = .otherAsset(categoryDescription: description,
                currentValue: Money(minorUnits: current.minorUnits + 100, currency: current.currency))
        case let .liability(balance, rate):
            value = .liability(outstandingBalance: Money(minorUnits: balance.minorUnits + 100, currency: balance.currency), interestRate: rate)
        }
        let fx = record.valuation
        let rebuilt = try FXValuation(original: value.currentValue(), rate: fx.rate,
            referenceDate: fx.referenceDate, fetchedAt: fx.fetchedAt,
            providerIdentifier: fx.providerIdentifier,
            isManualOverride: fx.isManualOverride, isStale: fx.isStale)
        return try WealthContainer(container: record.container, details: value, valuation: rebuilt)
    }
    func backup(_ store: WealthStore) async throws -> PermanentBackupGeneration {
        try await store.createPermanentBackup(in: backups, appVersion: "synthetic",
            createdAt: instant, generationID: UUID())
    }
    func restore(_ store: WealthStore, _ generation: PermanentBackupGeneration,
                 operations: any PermanentRestoreFileOperations = LocalPermanentRestoreFileOperations()) async throws -> PermanentRestoreResult {
        try await store.restorePermanentBackup(generation.directoryURL, in: backups,
            appVersion: "synthetic", createdAt: instant, fileOperations: operations)
    }
    func export(_ generation: PermanentBackupGeneration) throws -> URL {
        let result = try PermanentBackupExportService.export(internalGenerationURL: generation.directoryURL,
            to: destination, configuration: .init(internalBackupRootURL: backups,
                permanentDatabaseURL: database, marketCacheDatabaseURL: cache,
                additionalProtectedDestinationRoots: []), operationID: UUID())
        return destination.appendingPathComponent(result.exportedGenerationIdentity, isDirectory: true)
    }
}

private final class WealthCorrectionRestoreOperations: PermanentRestoreFileOperations, @unchecked Sendable {
    let fail: Bool
    private(set) var replacements = 0
    init(fail: Bool) { self.fail = fail }
    func copyValidatedDatabase(from sourceURL: URL, to stagingURL: URL) throws {
        try LocalPermanentRestoreFileOperations().copyValidatedDatabase(from: sourceURL, to: stagingURL)
    }
    func atomicallyReplaceDatabase(at databaseURL: URL, with stagingURL: URL) throws {
        try LocalPermanentRestoreFileOperations().atomicallyReplaceDatabase(at: databaseURL, with: stagingURL)
        replacements += 1
        if fail && replacements == 1 {
            let q = try DatabaseQueueFactory.open(at: databaseURL); defer { try? q.close() }
            try q.write { try $0.execute(sql: "UPDATE schema_metadata SET version=10 WHERE store_kind='permanent'") }
        }
    }
}
