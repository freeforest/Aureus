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
        let link = try PortfolioSecurityLink(portfolioID: portfolio.id, wealthContainerID: security.id, symbol: "SYN", rawMIC: "XSYN", currency: .usd, assetKind: .stock, sortOrder: 0)
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
