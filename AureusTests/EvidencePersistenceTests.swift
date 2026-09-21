import Foundation
import GRDB
import Testing
@testable import Aureus

@Suite("Internal Evidence integration", .serialized)
struct EvidencePersistenceTests {
    @Test("Three typed targets import independent originals and retain their receipts", arguments: [0, 1, 2])
    func typedImports(_ kind: Int) async throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        let store = try f.open()
        let graph = try await f.graph(store)
        let target = graph.targets[kind]
        let operation = UUID()
        let result = try await store.importEvidence(source: f.source, operationID: operation, target: target, meaning: "Synthetic proof")
        #expect(result.availability == .available && result.operation.state == .committed)
        let file = try #require(result.operation.file)
        #expect(try Data(contentsOf: f.managed.appendingPathComponent(file.relativeReference)) == f.bytes)
        let moved = f.root.appendingPathComponent("renamed-and-moved.bin")
        try FileManager.default.moveItem(at: f.source, to: moved)
        #expect(try await store.resumeEvidence(operationID: operation).availability == .available)
        try FileManager.default.removeItem(at: moved)
        #expect(try await store.resumeEvidence(operationID: operation) == result)
        #expect(try f.count("evidence_documents") == 1)
        #expect(try f.count(target.linkTable) == 1)
        #expect(try f.count("evidence_import_operations") == 1)
    }

    @Test("Shared material has three real FK links; duplicate linking preserves the first meaning and ID")
    func sharedLinksAndIdentityEdits() async throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        let store = try f.open(), graph = try await f.graph(store)
        let result = try await store.importEvidence(source: f.source, operationID: UUID(), target: graph.targets[0])
        let id = result.operation.documentID
        for target in graph.targets {
            let first = try await store.linkEvidence(documentID: id, target: target, meaning: "first")
            let second = try await store.linkEvidence(documentID: id, target: target, meaning: "ignored replacement")
            #expect(first == second)
        }
        let before = try f.links()
        let edited = try graph.context.entry(kind: .expense, id: graph.entry.id, description: "Synthetic edit")
        try await store.updateLedgerEntry(edited)
        try await store.updatePortfolioActivity(graph.activity)
        #expect(try f.links() == before)
        #expect(try f.count("evidence_documents") == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.managed.path).count == 1)
        await #expect(throws: EvidenceError.targetMissing) {
            _ = try await store.linkEvidence(documentID: id, target: .ledger(UUID()))
        }
    }

    @Test("Each final transaction failure rolls back Document, relation and commit state", arguments: ["document", "link", "operation"])
    func finalTransactionFailures(_ boundary: String) async throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        let store = try f.open(), graph = try await f.graph(store)
        let sql: String
        switch boundary {
        case "document": sql = "BEFORE INSERT ON evidence_documents"
        case "link": sql = "BEFORE INSERT ON evidence_ledger_links"
        default: sql = "BEFORE UPDATE OF state ON evidence_import_operations WHEN NEW.state = 'committed'"
        }
        try f.write("CREATE TRIGGER synthetic_final_failure \(sql) BEGIN SELECT RAISE(ABORT, 'synthetic'); END")
        let operation = UUID()
        let failed = try await store.importEvidence(source: f.source, operationID: operation, target: graph.targets[0])
        #expect(failed.availability == .publishedPendingRecovery && failed.operation.state == .prepared)
        #expect(try f.count("evidence_documents") == 0 && f.count("evidence_ledger_links") == 0)
        let file = try #require(failed.operation.file)
        try ManagedEvidenceFiles(root: f.managed).validate(file, expectedIdentity: failed.operation.identity)
        try f.write("DROP TRIGGER synthetic_final_failure")
        let recovered = try await store.resumeEvidence(operationID: operation)
        #expect(recovered.availability == .available && recovered.operation.documentID == failed.operation.documentID)
        #expect(try await store.resumeEvidence(operationID: operation) == recovered)
        #expect(try f.count("evidence_documents") == 1 && f.count("evidence_ledger_links") == 1)
    }

    @Test("A real FK failure after Document insertion rolls back the whole final transaction")
    func finalForeignKeyFailure() async throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        let store = try f.open(), graph = try await f.graph(store)
        try f.write("CREATE TRIGGER remove_link_target BEFORE INSERT ON evidence_ledger_links BEGIN DELETE FROM ledger_transactions WHERE id = NEW.ledger_entry_id; END")
        let failed = try await store.importEvidence(source: f.source, operationID: UUID(), target: graph.targets[0])
        #expect(failed.availability == .publishedPendingRecovery && failed.operation.state == .prepared)
        #expect(try f.count("evidence_documents") == 0 && f.count("evidence_ledger_links") == 0)
        #expect(try f.count("ledger_transactions") == 1)
        try f.write("DROP TRIGGER remove_link_target")
        #expect(try await store.resumeEvidence(operationID: failed.operation.id).availability == .available)
    }

    @Test("Targets lost after registration or publication cannot produce a valid relationship", arguments: [false, true])
    func deletedTargetDuringImport(_ afterPublish: Bool) async throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        let target = UUID()
        var configuration = ManagedEvidenceFileConfiguration()
        configuration.checkpoint = { point in
            if point == (afterPublish ? .afterPublish : .openedSource) {
                try f.write("DELETE FROM ledger_transactions WHERE id = ?", arguments: [target.uuidString])
            }
        }
        let store = try f.open(files: configuration)
        let context = try LedgerTestContext.make()
        try await store.createWealthContainer(context.source)
        try await store.createLedgerEntry(context.entry(kind: .income, id: target))
        let result = try await store.importEvidence(source: f.source, operationID: UUID(), target: .ledger(target))
        #expect(result.availability == .publishedPendingRecovery)
        #expect(result.operation.state == .prepared)
        #expect(try f.count("evidence_documents") == 0 && f.count("evidence_ledger_links") == 0)
        await #expect(throws: EvidenceError.targetMissing) {
            _ = try await store.importEvidence(source: f.source, operationID: UUID(), target: .ledger(UUID()))
        }
    }

    @Test("Committed history survives deleted targets, missing links and damaged files", arguments: ["target", "link", "file"])
    func committedHistoryIsMonotonic(_ mutation: String) async throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        let store = try f.open(), graph = try await f.graph(store)
        let operation = UUID()
        let initial = try await store.importEvidence(source: f.source, operationID: operation, target: graph.targets[0])
        _ = try await store.linkEvidence(documentID: initial.operation.documentID, target: graph.targets[1])
        switch mutation {
        case "target": try await store.deleteLedgerEntry(id: graph.entry.id)
        case "link": try f.write("DELETE FROM evidence_ledger_links")
        default: try Data([9]).write(to: f.managed.appendingPathComponent(try #require(initial.operation.file).relativeReference))
        }
        let retry = try await store.resumeEvidence(operationID: operation)
        #expect(retry.operation.state == .committed && retry.operation.documentID == initial.operation.documentID)
        #expect(retry.availability == (mutation == "target" ? .targetRemoved : mutation == "link" ? .relationshipChanged : .materialUnavailable))
        #expect(try f.count("evidence_documents") == 1 && f.count("evidence_container_links") == 1)
        #expect(try f.count("evidence_ledger_links") == (mutation == "file" ? 1 : 0))
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.managed.path).count == 1)
    }

    @Test("Owner reconstruction resumes the same prepared or committed operation", arguments: [false, true])
    func storeReconstruction(_ prepared: Bool) async throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        let operation = UUID()
        var store: WealthStore? = try f.open()
        let graph = try await f.graph(try #require(store))
        if prepared { try f.write("CREATE TRIGGER synthetic_commit_failure BEFORE INSERT ON evidence_documents BEGIN SELECT RAISE(ABORT, 'synthetic'); END") }
        let initial = try await store!.importEvidence(source: f.source, operationID: operation, target: graph.targets[0])
        weak var released = store
        store = nil
        try #require(released == nil)
        if prepared { try f.write("DROP TRIGGER synthetic_commit_failure") }
        let reopened = try f.open()
        let resumed = try await reopened.resumeEvidence(operationID: operation)
        #expect(resumed.operation.documentID == initial.operation.documentID && resumed.availability == .available)
        #expect(resumed.operation.state == .committed)
        #expect(try f.count("evidence_documents") == 1)
    }

    @Test("Registered and retained staging do not auto-publish on reconstruction", arguments: [false, true])
    func incompleteReceipts(_ staging: Bool) async throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        var config = ManagedEvidenceFileConfiguration()
        config.checkpoint = { point in
            if point == (staging ? .beforeWrite : .openedSource) || (staging && point == .beforeCleanup) {
                throw ManagedEvidenceFailure.writeFailed
            }
        }
        var store: WealthStore? = try f.open(files: config)
        let graph = try await f.graph(try #require(store))
        let operation = UUID()
        let failed = try await store!.importEvidence(source: f.source, operationID: operation, target: graph.targets[0])
        #expect(failed.operation.state == (staging ? .stagingOwned : .registered))
        weak var released = store; store = nil; try #require(released == nil)
        let reopened = try f.open()
        let result = try await reopened.resumeEvidence(operationID: operation)
        #expect(result.availability == (staging ? .pendingReview : .needsSourceSelection))
        #expect(try f.count("evidence_documents") == 0)
    }

    @Test("Format1 refuses operation-only and committed datasets without making a generation", arguments: [false, true])
    func formatOneGuard(_ committed: Bool) async throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        let store = try f.open(), graph = try await f.graph(store)
        _ = try await store.importEvidence(source: f.source, operationID: UUID(), target: graph.targets[0], cancelled: { !committed })
        await #expect(throws: EvidenceError.legacyFormatUnsupported) {
            _ = try await store.createPermanentBackup(in: f.backups, appVersion: "synthetic", createdAt: graph.entry.recordedAt)
        }
        let queue = try DatabaseQueueFactory.open(at: f.database); defer { try? queue.close() }
        #expect(throws: PermanentBackupError.evidenceRequiresCompleteBackup) {
            _ = try PermanentBackupService.create(from: queue, in: f.backups, appVersion: "synthetic", createdAt: graph.entry.recordedAt, generationID: UUID())
        }
        #expect(!FileManager.default.fileExists(atPath: f.backups.path))
    }

    @Test("Missing root configuration fails closed and does not retain registration")
    func missingConfiguration() async throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        var store: WealthStore? = try f.open()
        let graph = try await f.graph(try #require(store))
        _ = try await store!.importEvidence(source: f.source, operationID: UUID(), target: graph.targets[0])
        weak var released = store; store = nil; try #require(released == nil)
        #expect(throws: EvidenceError.disabled) { _ = try WealthStore(databaseURL: f.database) }
        let reopened = try f.open()
        #expect(try await reopened.schemaVersion() == 7)
    }

    @Test("Database checks reject malformed IDs, references, receipt groups and states")
    func schemaConstraints() async throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        let store = try f.open(), graph = try await f.graph(store)
        let imported = try await store.importEvidence(source: f.source, operationID: UUID(), target: graph.targets[0])
        for assignment in ["document_id = 'bad'", "relative_reference = '../escape'", "root_inode = NULL",
                           "sha256 = NULL", "state = 'invalid'", "file_inode = '18446744073709551616'"] {
            #expect(throws: DatabaseError.self) { try f.write("UPDATE evidence_import_operations SET \(assignment)") }
        }
        #expect(try await store.resumeEvidence(operationID: imported.operation.id).availability == .available)
        try f.write("UPDATE evidence_documents SET original_filename = 'mismatch'")
        await #expect(throws: EvidenceError.inconsistentRegistration) { _ = try await store.resumeEvidence(operationID: imported.operation.id) }
    }
    @Test("Persistent observer DB failure prevents rename", arguments: ["stagingOwned", "prepared"])
    func observerDatabaseFailure(_ state: String) async throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        let store = try f.open(), graph = try await f.graph(store)
        try f.write("CREATE TRIGGER receipt_failure BEFORE UPDATE OF state ON evidence_import_operations WHEN NEW.state = '\(state)' BEGIN SELECT RAISE(ABORT, 'synthetic'); END")
        let result = try await store.importEvidence(source: f.source, operationID: UUID(), target: graph.targets[0])
        #expect(result.availability == .pendingReview)
        #expect(result.operation.state == (state == "prepared" ? .stagingOwned : .registered))
        #expect(try f.count("evidence_documents") == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.managed.path).isEmpty)
        #expect(try Data(contentsOf: f.source) == f.bytes)
    }

    @Test("Prepared is durable before rename and post-publication cancellation retains the result", arguments: [false, true])
    func cancellationBoundary(_ published: Bool) async throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        let flag = IntegrationFlag()
        var config = ManagedEvidenceFileConfiguration()
        config.checkpoint = { (point: ManagedEvidenceIOPoint) throws -> Void in
            if point == .beforePublish {
                #expect(try f.scalar("SELECT COUNT(*) FROM evidence_import_operations WHERE state = 'prepared'") == 1)
                #expect(try FileManager.default.contentsOfDirectory(atPath: f.managed.path).allSatisfy { $0.hasSuffix(".pending") })
                if !published { flag.set() }
            }
            if point == .afterPublish && published { flag.set() }
        }
        let store = try f.open(files: config), graph = try await f.graph(store)
        let result = try await store.importEvidence(source: f.source, operationID: UUID(), target: graph.targets[0], cancelled: { flag.value })
        #expect(result.availability == (published ? .available : .cancelled))
        #expect(result.operation.state == (published ? .committed : .cancelled))
        #expect(try f.count("evidence_documents") == (published ? 1 : 0))
        #expect(try Data(contentsOf: f.source) == f.bytes)
    }

    @Test("Damage after DB commit but before return cannot be reported as usable")
    func damagedBeforeReturn() async throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        let store = try WealthStore(databaseURL: f.database, evidenceConfiguration: .init(root: f.managed, protectedPaths: [f.backups], afterCommit: {
            let files = try FileManager.default.contentsOfDirectory(at: f.managed, includingPropertiesForKeys: nil)
            try #require(files.count == 1)
            try Data([7]).write(to: files[0])
        }))
        let graph = try await f.graph(store)
        let result = try await store.importEvidence(source: f.source, operationID: UUID(), target: graph.targets[0])
        #expect(result.operation.state == .committed && result.availability == .materialUnavailable)
        #expect(try f.count("evidence_documents") == 1 && f.count("evidence_ledger_links") == 1)
        #expect(try await store.resumeEvidence(operationID: result.operation.id) == result)
    }

    @Test("Rebuilt owner preserves unavailable and review states", arguments: ["recoveryRequired", "missing", "replacement", "pending", "unknown"])
    func refusedReconstruction(_ kind: String) async throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        var store: WealthStore? = try f.open()
        let graph = try await f.graph(try #require(store))
        try f.write("CREATE TRIGGER stop_commit BEFORE INSERT ON evidence_documents BEGIN SELECT RAISE(ABORT, 'synthetic'); END")
        let initial = try await store!.importEvidence(source: f.source, operationID: UUID(), target: graph.targets[0])
        try #require(initial.operation.state == .prepared)
        let file = try #require(initial.operation.file)
        let path = f.managed.appendingPathComponent(file.relativeReference)
        switch kind {
        case "recoveryRequired": try f.write("UPDATE evidence_import_operations SET state = 'recoveryRequired'")
        case "missing": try FileManager.default.removeItem(at: path)
        case "replacement":
            let replacement = f.root.appendingPathComponent("replacement")
            try f.bytes.write(to: replacement)
            try FileManager.default.removeItem(at: path)
            try FileManager.default.moveItem(at: replacement, to: path)
        case "pending": try FileManager.default.moveItem(at: path, to: f.managed.appendingPathComponent("." + file.id.uuidString.lowercased() + ".pending"))
        default:
            try f.write("UPDATE evidence_import_operations SET state='registered',root_device=NULL,root_inode=NULL,file_device=NULL,file_inode=NULL,byte_count=NULL,sha256=NULL,copied_at_ms=NULL")
        }
        try f.write("DROP TRIGGER stop_commit")
        weak var released = store; store = nil; try #require(released == nil)
        let before = try FileManager.default.contentsOfDirectory(atPath: f.managed.path)
        let rebuilt = try f.open()
        let retry = try await rebuilt.resumeEvidence(operationID: initial.operation.id)
        #expect(retry.availability == (kind == "recoveryRequired" || kind == "unknown" ? .pendingReview : .materialUnavailable))
        #expect(try f.count("evidence_documents") == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.managed.path) == before)
        await #expect(throws: EvidenceError.operationConflict) { _ = try await rebuilt.resumeEvidence(operationID: UUID()) }
    }

    @Test("Real parent deletes remove only links, preserving shared originals", arguments: ["ledger", "container", "activity", "portfolio", "security"])
    func sharedDeletion(_ kind: String) async throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        let store = try f.open(), graph = try await f.graph(store)
        let independent = try LedgerTestContext.make().target
        try await store.createWealthContainer(independent)
        let result = try await store.importEvidence(source: f.source, operationID: UUID(), target: graph.targets[0])
        _ = try await store.linkEvidence(documentID: result.operation.documentID, target: .container(independent.id))
        _ = try await store.linkEvidence(documentID: result.operation.documentID, target: graph.targets[2])
        switch kind {
        case "ledger": try await store.deleteLedgerEntry(id: graph.entry.id)
        case "container": _ = try await store.deleteWealthContainer(id: independent.id)
        case "activity": try await store.deletePortfolioActivity(id: graph.activity.id)
        case "portfolio": try await store.deletePortfolio(id: graph.activity.portfolioID)
        default: try await store.unlinkPortfolioSecurity(id: graph.activity.securityLinkID)
        }
        #expect(try f.count("evidence_documents") == 1)
        #expect(try f.count("evidence_ledger_links") == (kind == "ledger" ? 0 : 1))
        #expect(try f.count("evidence_container_links") == (kind == "container" ? 0 : 1))
        #expect(try f.count("evidence_portfolio_activity_links") == (["activity", "portfolio", "security"].contains(kind) ? 0 : 1))
        try ManagedEvidenceFiles(root: f.managed).validate(try #require(result.operation.file), expectedIdentity: result.operation.identity)
        #expect(try await store.evidenceOperation(result.operation.id)?.state == .committed)
    }

    @Test("Portfolio payload changes clear nullable fields and failed FIFO rolls back linked identity")
    func portfolioConversions() async throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        let store = try f.open(), graph = try await f.graph(store)
        let result = try await store.importEvidence(source: f.source, operationID: UUID(), target: graph.targets[2])
        let old = graph.activity
        let cost = Money(minorUnits: 10000, currency: .usd)
        let fx = try PortfolioFXProvenance(original: cost, rate: FXRate(decimal: 7, sourceCurrency: .usd, targetCurrency: .cny), source: "synthetic", referenceDate: old.civilDate, recordedAt: old.recordedAt, isManual: true, isStale: false)
        func value(_ payload: PortfolioActivityPayload) throws -> PortfolioActivity {
            try PortfolioActivity(id: old.id, portfolioID: old.portfolioID, securityLinkID: old.securityLinkID, civilDate: old.civilDate, recordedAt: old.recordedAt, exchangeTimeZoneIdentifier: "UTC", ledgerEntryID: old.ledgerEntryID, payload: payload)
        }
        let buy = try value(.buy(quantity: AssetQuantity(coefficient: 100_000_000), unitPrice: MarketPrice(decimal: 100, quoteCurrency: .usd), fee: Money(minorUnits: 0, currency: .usd), fx: fx))
        try await store.updatePortfolioActivity(buy)
        #expect(try f.scalar("SELECT COUNT(*) FROM portfolio_activities WHERE sanitized_note IS NULL AND split_from_coefficient IS NULL AND unit_price_coefficient IS NOT NULL") == 1)
        let before = try f.links()
        let sell = try value(.sell(quantity: AssetQuantity(coefficient: 100_000_000), unitPrice: MarketPrice(decimal: 100, quoteCurrency: .usd), fee: Money(minorUnits: 0, currency: .usd), fx: fx))
        await #expect(throws: PortfolioPersistenceError.invalidHistoricalMutation) { try await store.updatePortfolioActivity(sell) }
        #expect(try await store.fetchPortfolioActivities(portfolioID: old.portfolioID) == [buy])
        #expect(try f.links() == before)
        try await store.updatePortfolioActivity(old)
        #expect(try f.scalar("SELECT COUNT(*) FROM portfolio_activities WHERE unit_price_coefficient IS NULL AND fee_minor IS NULL AND sanitized_note IS NOT NULL") == 1)
        let earlier = try PortfolioActivity(portfolioID: old.portfolioID, securityLinkID: old.securityLinkID,
            civilDate: old.civilDate, recordedAt: UTCInstant(millisecondsSince1970: old.recordedAt.millisecondsSince1970 - 1),
            exchangeTimeZoneIdentifier: "UTC", payload: old.payload)
        try await store.createPortfolioActivity(earlier)
        let split = try value(.manualSplit(from: Ratio(decimal: 1), to: Ratio(decimal: 2)))
        try await store.updatePortfolioActivity(split)
        #expect(try f.scalar("SELECT COUNT(*) FROM portfolio_activities WHERE kind = 'manualSplit' AND quantity_coefficient IS NULL AND total_original_minor IS NULL AND fx_coefficient IS NULL AND sanitized_note IS NULL AND split_from_coefficient IS NOT NULL") == 1)
        try await store.updatePortfolioActivity(old)
        #expect(try f.scalar("SELECT COUNT(*) FROM portfolio_activities WHERE split_from_coefficient IS NOT NULL") == 0)
        #expect(try await store.resumeEvidence(operationID: result.operation.id).availability == .available)
    }

    @Test("Malformed v7 schemas cannot reopen as an empty valid dataset", arguments: ["missing", "constraint", "index"])
    func invalidSchemaReopen(_ kind: String) throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        var store: WealthStore? = try f.open()
        weak var released = store; store = nil; try #require(released == nil)
        switch kind {
        case "missing": try f.write("DROP TABLE evidence_ledger_links")
        case "index": try f.write("DROP INDEX evidence_ledger_links_target")
        default:
            try f.write("DROP TABLE evidence_ledger_links")
            try f.write("CREATE TABLE evidence_ledger_links(document_id TEXT, ledger_entry_id TEXT, link_id TEXT, created_at_ms INTEGER, meaning TEXT)")
        }
        #expect(throws: PermanentMigrationSafetyError.self) { _ = try f.open() }
    }

    @Test("Actual legacy prefixes retain financial bytes and pre-migration safety copies", arguments: [1, 2, 3, 4, 5, 6])
    func legacyFinancialPreservation(_ version: Int) async throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        let queue = try DatabaseQueueFactory.open(at: f.database)
        try DatabaseMigrations.permanentMigrator().migrate(queue, upTo: PermanentDatabaseValidation.migrationIdentifiers[version - 1])
        let account = UUID().uuidString, transaction = UUID().uuidString
        let wealth = try SyntheticWealthSeeder.records()[1]
        try await queue.write { db in
            try db.execute(sql: "INSERT INTO accounts(id,name,kind,currency_code) VALUES (?, 'Synthetic USD', 'other', 'USD')", arguments: [account])
            try db.execute(sql: "INSERT INTO wealth_transactions(id,account_id,civil_date,amount_minor,currency_code,type) VALUES (?,?,'2026-01-15',12345,'USD','income')", arguments: [transaction, account])
            if version >= 2 {
                try AssetContainerPersistenceRow(container: wealth.container).insert(db)
                try WealthRecordPersistenceRow(record: wealth).insert(db)
            }
        }
        let before = try await queue.read { db in try Row.fetchAll(db, sql: "SELECT * FROM wealth_transactions").map(\.description) }
        let fxBefore = try await queue.read { db in version >= 2 ? try Row.fetchAll(db, sql: "SELECT * FROM wealth_records").map(\.description) : [] }
        try queue.close()
        #expect(throws: PermanentMigrationSafetyError.missingBackupConfiguration) { _ = try f.open() }
        let safety = PermanentMigrationSafetyConfiguration(backupRoot: f.backups, appVersion: "synthetic", createdAt: { UTCInstant(millisecondsSince1970: 1_800_000_000_000) }, generationID: { UUID() })
        var store: WealthStore? = try WealthStore(databaseURL: f.database, migrationSafetyConfiguration: safety, evidenceConfiguration: .init(root: f.managed, protectedPaths: [f.backups]))
        #expect(try await store!.schemaVersion() == 7)
        for table in EvidenceSQL.tables { #expect(try f.count(table) == 0) }
        let generations = try PermanentBackupService.inventory(in: f.backups).validGenerations
        try #require(generations.count == 1)
        #expect(generations[0].manifest.schemaVersion == version)
        let oldURL = generations[0].directoryURL.appendingPathComponent("aureus.sqlite")
        var readonly = Configuration(); readonly.readonly = true
        let old = try DatabaseQueue(path: oldURL.path, configuration: readonly)
        #expect(try await old.read { try Row.fetchAll($0, sql: "SELECT * FROM wealth_transactions").map(\.description) } == before)
        try old.close()
        weak var released = store; store = nil; try #require(released == nil)
        let reopened = try f.open()
        #expect(try await reopened.schemaVersion() == 7)
        let current = try DatabaseQueueFactory.open(at: f.database); defer { try? current.close() }
        #expect(try await current.read { try Row.fetchAll($0, sql: "SELECT * FROM wealth_transactions").map(\.description) } == before)
        if version >= 2 {
            #expect(try await current.read { try Row.fetchAll($0, sql: "SELECT * FROM wealth_records").map(\.description) } == fxBefore)
            #expect(try await reopened.fetchWealthContainer(id: wealth.id) == wealth)
        }
    }

    @Test("Live material and operation-only states reject both Restore entrances before staging", arguments: [false, true])
    func restoreProtection(_ committed: Bool) async throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        let store = try f.open(), graph = try await f.graph(store)
        let clean = try await store.createPermanentBackup(in: f.backups, appVersion: "synthetic", createdAt: graph.entry.recordedAt)
        _ = try await store.importEvidence(source: f.source, operationID: UUID(), target: graph.targets[0], cancelled: { !committed })
        let before = try f.links()
        let names = try FileManager.default.contentsOfDirectory(atPath: f.database.deletingLastPathComponent().path).sorted()
        await #expect(throws: PermanentRestoreError.evidenceRequiresCompleteRestore) {
            _ = try await store.restorePermanentBackup(clean.directoryURL, in: f.backups, appVersion: "synthetic", createdAt: graph.entry.recordedAt)
        }
        await #expect(throws: PermanentExternalRestoreError.evidenceRequiresCompleteRestore) {
            _ = try await store.restoreExternalPermanentBackup(clean.directoryURL, configuration: .init(internalBackupRootURL: f.backups, permanentDatabaseURL: f.database, marketCacheDatabaseURL: f.root.appendingPathComponent("Cache/cache.sqlite"), additionalProtectedSourceRoots: []), appVersion: "synthetic", createdAt: graph.entry.recordedAt)
        }
        #expect(try f.links() == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.database.deletingLastPathComponent().path).sorted() == names)
        #expect(try PermanentBackupService.inventory(in: f.backups).validGenerations == [clean])
    }

    @Test("Material-bearing forged generations cannot count or prune clean generations")
    func forgedGenerationProtection() async throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        let store = try f.open(), graph = try await f.graph(store)
        var clean: [PermanentBackupGeneration] = []
        for index in 0..<5 {
            clean.append(try await store.createPermanentBackup(in: f.backups, appVersion: "synthetic", createdAt: UTCInstant(millisecondsSince1970: graph.entry.recordedAt.millisecondsSince1970 + Int64(index))))
        }
        let forged = f.backups.appendingPathComponent("backup-20270101T000000000Z-" + UUID().uuidString.lowercased())
        try FileManager.default.copyItem(at: clean[0].directoryURL, to: forged)
        let dbURL = forged.appendingPathComponent("aureus.sqlite")
        let q = try DatabaseQueueFactory.open(at: dbURL)
        let id = UUID()
        try await q.write { db in
            try db.execute(sql: "INSERT INTO evidence_import_operations(operation_id,document_id,ledger_entry_id,intended_meaning,original_filename,relative_reference,registered_at_ms,updated_at_ms,state) VALUES (?,?,?,'','synthetic',?,0,0,'registered')", arguments: [UUID().uuidString,id.uuidString,graph.entry.id.uuidString,id.uuidString.lowercased()+".original"])
        }
        try q.close()
        let digest = try PermanentBackupService.streamingDigest(of: dbURL)
        let original = clean[0].manifest
        let manifest = PermanentBackupManifest(backupFormatVersion: 1, appVersion: original.appVersion, schemaVersion: 7, createdAt: original.createdAt, databaseByteCount: digest.byteCount, databaseSHA256: digest.sha256)
        try JSONEncoder().encode(manifest).write(to: forged.appendingPathComponent("manifest.json"))
        #expect(throws: PermanentBackupError.evidenceRequiresCompleteBackup) { _ = try PermanentBackupService.validateGeneration(forged, in: f.backups) }
        let inventory = try PermanentBackupService.pruneValidGenerations(in: f.backups)
        #expect(inventory.validGenerations.count == 5 && inventory.invalidGenerations.count == 1)
        for item in clean { #expect(FileManager.default.fileExists(atPath: item.directoryURL.path)) }
        let output = f.root.appendingPathComponent("Export")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        #expect(throws: PermanentBackupExportError.invalidSourceGeneration) {
            _ = try PermanentBackupExportService.export(internalGenerationURL: forged, to: output, configuration: .init(internalBackupRootURL: f.backups, permanentDatabaseURL: f.database, marketCacheDatabaseURL: f.root.appendingPathComponent("Cache/cache.sqlite"), additionalProtectedDestinationRoots: []), operationID: UUID())
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
        await #expect(throws: PermanentRestoreError.candidateValidationFailed) {
            _ = try await store.restorePermanentBackup(forged, in: f.backups, appVersion: "synthetic", createdAt: graph.entry.recordedAt)
        }
        #expect(try f.count("evidence_import_operations") == 0)
    }

    @Test("Export revalidates material-bearing mutations at staged and committed boundaries", arguments: [false, true])
    func exportMutationProtection(_ committed: Bool) async throws {
        let f = try IntegrationFixture(); defer { f.remove() }
        let store = try f.open(), graph = try await f.graph(store)
        let clean = try await store.createPermanentBackup(in: f.backups, appVersion: "synthetic", createdAt: graph.entry.recordedAt)
        let oldOutput = f.root.appendingPathComponent("Export")
        try FileManager.default.createDirectory(at: oldOutput, withIntermediateDirectories: false)
        let protected = [f.backups, f.database.deletingLastPathComponent(), f.database,
            f.root.appendingPathComponent("Cache"), f.root.appendingPathComponent("Cache/cache.sqlite")]
        let diagnostic = try exportDestinationDiagnostics(oldOutput, protected: protected)
        print("Synthetic Export original guards: \(diagnostic)")
        #expect(diagnostic["fileURL"] == true && diagnostic["directory"] == true && diagnostic["writable"] == true)
        #expect(diagnostic["resolvedMatches"] == true && diagnostic["outsideProtected"] == true)
        #expect(diagnostic["directChildURLMatches"] == false)
        let before = MaterialExportMutation(committed: committed, target: graph.entry.id)
        #expect(throws: PermanentBackupExportError.unsafeOrUnsupportedDestination) {
            _ = try PermanentBackupExportService.export(internalGenerationURL: clean.directoryURL, to: oldOutput, configuration: .init(internalBackupRootURL: f.backups, permanentDatabaseURL: f.database, marketCacheDatabaseURL: f.root.appendingPathComponent("Cache/cache.sqlite"), additionalProtectedDestinationRoots: []), operationID: UUID(), fileOperations: before)
        }
        #expect(before.counts.values.allSatisfy { $0 == 0 })
        // Explicit directory semantics make parent URL equality match the existing guard.
        let output = f.root.appendingPathComponent("Export", isDirectory: true)
        let corrected = try exportDestinationDiagnostics(output, protected: protected)
        print("Synthetic Export corrected guards: \(corrected)")
        #expect(corrected.values.allSatisfy { $0 })
        let operations = MaterialExportMutation(committed: committed, target: graph.entry.id)
        #expect(throws: committed ? PermanentBackupExportError.committedRevalidationFailure : .stagingCreationOrCopyFailure) {
            _ = try PermanentBackupExportService.export(internalGenerationURL: clean.directoryURL, to: output, configuration: .init(internalBackupRootURL: f.backups, permanentDatabaseURL: f.database, marketCacheDatabaseURL: f.root.appendingPathComponent("Cache/cache.sqlite"), additionalProtectedDestinationRoots: []), operationID: UUID(), fileOperations: operations)
        }
        #expect(operations.reached.value)
        #expect(operations.counts == ["create": 1, "copyStarted": 2, "copyFinished": 2,
            "moveStarted": committed ? 1 : 0, "moveFinished": committed ? 1 : 0, "mutation": 1])
        print("Synthetic Export reached counters: \(operations.counts)")
        #expect(try PermanentBackupService.validateGeneration(clean.directoryURL, in: f.backups) == clean)
        let names = try FileManager.default.contentsOfDirectory(atPath: output.path)
        #expect(names.count == (committed ? 1 : 0))
    }
}

private func exportDestinationDiagnostics(_ url: URL, protected: [URL]) throws -> [String: Bool] {
    let destination = url.standardizedFileURL
    let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
    let overlaps = protected.map { other -> Bool in
        let a = destination.path, b = other.standardizedFileURL.path
        return a == b || a.hasPrefix(b + "/") || b.hasPrefix(a + "/")
    }
    var result = ["fileURL": url.isFileURL, "absolute": url.path.hasPrefix("/"),
        "resolvedMatches": destination.resolvingSymlinksInPath().path == destination.path,
        "directory": attributes[.type] as? FileAttributeType == .typeDirectory,
        "writable": FileManager.default.isWritableFile(atPath: destination.path),
        "outsideProtected": !overlaps.contains(true),
        "directChildURLMatches": destination.appendingPathComponent("synthetic-child", isDirectory: true).standardizedFileURL.deletingLastPathComponent() == destination]
    for (index, overlap) in overlaps.enumerated() { result["outsideProtectedRole\(index)"] = !overlap }
    return result
}

private final class MaterialExportMutation: PermanentBackupExportFileOperations, @unchecked Sendable {
    let committed: Bool
    let target: UUID
    let reached = IntegrationFlag()
    private let lock = NSLock()
    private var recorded = ["create": 0, "copyStarted": 0, "copyFinished": 0, "moveStarted": 0, "moveFinished": 0, "mutation": 0]
    init(committed: Bool, target: UUID) { self.committed = committed; self.target = target }
    var counts: [String: Int] { lock.withLock { recorded } }
    private func count(_ key: String) { lock.withLock { recorded[key, default: 0] += 1 } }
    func createDirectory(at url: URL) throws { count("create"); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
    func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        count("copyStarted")
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        count("copyFinished")
        if !committed && destinationURL.lastPathComponent == "manifest.json" { try mutate(destinationURL.deletingLastPathComponent()) }
    }
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        count("moveStarted")
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        count("moveFinished")
        if committed { try mutate(destinationURL) }
    }
    private func mutate(_ root: URL) throws {
        let url = root.appendingPathComponent("aureus.sqlite")
        let queue = try DatabaseQueueFactory.open(at: url)
        let id = UUID()
        try queue.write { db in
            try db.execute(sql: "INSERT INTO evidence_import_operations(operation_id,document_id,ledger_entry_id,intended_meaning,original_filename,relative_reference,registered_at_ms,updated_at_ms,state) VALUES (?,?,?,'','synthetic',?,0,0,'registered')", arguments: [UUID().uuidString,id.uuidString,target.uuidString,id.uuidString.lowercased()+".original"])
        }
        try queue.close()
        let manifestURL = root.appendingPathComponent("manifest.json")
        let old = try JSONDecoder().decode(PermanentBackupManifest.self, from: Data(contentsOf: manifestURL))
        let digest = try PermanentBackupService.streamingDigest(of: url)
        try JSONEncoder().encode(PermanentBackupManifest(backupFormatVersion: 1, appVersion: old.appVersion, schemaVersion: 7, createdAt: old.createdAt, databaseByteCount: digest.byteCount, databaseSHA256: digest.sha256)).write(to: manifestURL)
        reached.set()
        count("mutation")
    }
}

private final class IntegrationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool { lock.withLock { stored } }
    func set() { lock.withLock { stored = true } }
}

private struct IntegrationFixture: Sendable {
    let root: URL, database: URL, managed: URL, source: URL, backups: URL
    let bytes = Data("synthetic managed original\n".utf8)
    init() throws {
        root = try temporaryDirectory()
        database = root.appendingPathComponent("Permanent/aureus.sqlite")
        managed = root.appendingPathComponent("Materials")
        backups = root.appendingPathComponent("Backups")
        source = root.appendingPathComponent("synthetic.txt")
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: false)
        try bytes.write(to: source, options: .withoutOverwriting)
    }
    func open(files: ManagedEvidenceFileConfiguration = .init()) throws -> WealthStore {
        try WealthStore(databaseURL: database, evidenceConfiguration: .init(root: managed, protectedPaths: [backups], files: files))
    }
    func write(_ sql: String, arguments: StatementArguments = []) throws {
        let queue = try DatabaseQueueFactory.open(at: database); defer { try? queue.close() }
        try queue.write { try $0.execute(sql: sql, arguments: arguments) }
    }
    func count(_ table: String) throws -> Int {
        let queue = try DatabaseQueueFactory.open(at: database); defer { try? queue.close() }
        return try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)")! }
    }
    func scalar(_ sql: String) throws -> Int {
        let queue = try DatabaseQueueFactory.open(at: database); defer { try? queue.close() }
        return try queue.read { try Int.fetchOne($0, sql: sql)! }
    }
    func links() throws -> [String] {
        let queue = try DatabaseQueueFactory.open(at: database); defer { try? queue.close() }
        return try queue.read { db in
            try ["evidence_ledger_links", "evidence_container_links", "evidence_portfolio_activity_links"].flatMap {
                try Row.fetchAll(db, sql: "SELECT * FROM \($0) ORDER BY link_id").map(\.description)
            }
        }
    }
    func graph(_ store: WealthStore) async throws -> IntegrationGraph {
        let context = try LedgerTestContext.make()
        try await store.createWealthContainer(context.source)
        let entry = try context.entry(kind: .income)
        try await store.createLedgerEntry(entry)
        let security = try SyntheticWealthSeeder.records()[2]
        try await store.createWealthContainer(security)
        let portfolio = try PortfolioRecord(name: "Synthetic Evidence", createdAt: entry.recordedAt, updatedAt: entry.recordedAt, sortOrder: 0)
        try await store.createPortfolio(portfolio)
        let link = try PortfolioSecurityLink(portfolioID: portfolio.id, wealthContainerID: security.id, symbol: "SYNX", rawMIC: "XSYN", currency: .usd, assetKind: .stock, sortOrder: 0)
        try await store.linkPortfolioSecurity(link)
        let cost = Money(minorUnits: 10000, currency: .usd)
        let fx = try PortfolioFXProvenance(original: cost, rate: FXRate(decimal: 7, sourceCurrency: .usd, targetCurrency: .cny), source: "synthetic.manual", referenceDate: entry.civilDate, recordedAt: entry.recordedAt, isManual: true, isStale: false)
        let activity = try PortfolioActivity(portfolioID: portfolio.id, securityLinkID: link.id, civilDate: entry.civilDate,
            recordedAt: entry.recordedAt, exchangeTimeZoneIdentifier: "UTC", ledgerEntryID: entry.id,
            payload: .openingLot(quantity: AssetQuantity(coefficient: 100_000_000), totalCost: cost, fx: fx, note: "Synthetic"))
        try await store.createPortfolioActivity(activity)
        return .init(context: context, entry: entry, activity: activity)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private struct IntegrationGraph {
    let context: LedgerTestContext
    let entry: LedgerEntry
    let activity: PortfolioActivity
    var targets: [EvidenceTarget] { [.ledger(entry.id), .container(context.source.id), .portfolioActivity(activity.id)] }
}
