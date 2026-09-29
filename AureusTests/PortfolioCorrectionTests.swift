import Foundation
import GRDB
import Testing
@testable import Aureus

@Suite("Portfolio Activity correction and history", .serialized)
struct PortfolioCorrectionTests {
    @Test("Four typed Activity payloads retain original and FX authority", arguments: ["openingLot", "buy", "sell", "manualSplit"], ["CNY", "USD"])
    func importantCorrectionRoundTrip(kind: String, currency: String) async throws {
        let f = try await PortfolioCorrectionFixture(currency: currency == "CNY" ? .cny : .usd)
        defer { f.remove() }
        let target = try await f.seed(kind: kind)
        let context = try await f.store.readPortfolioActivityEditContext(id: target.id)
        #expect(context.activity == target && context.link == f.link)
        let changed = try f.changed(target)
        let history = try portfolioApplied(await f.store.correctPortfolioActivity(f.request(changed, token: context.token)))
        #expect(history.kind == "correction" && history.reason == "Synthetic Activity correction")
        #expect(history.targetID == target.id && history.payload.before.id == target.id)
        #expect(history.payload.before.portfolioID == f.portfolio.id)
        #expect(history.payload.before.link == f.link)
        #expect(history.payload.after == PortfolioCorrectionProjection(changed, link: f.link))
        #expect(try await f.store.fetchPortfolioActivities(portfolioID: f.portfolio.id).contains(changed))
        #expect(try await f.store.portfolioActivityCorrectionHistory(id: target.id) == [history])
        let reopened = try WealthStore(databaseURL: f.database)
        #expect(try await reopened.portfolioActivityCorrectionHistory(id: target.id) == [history])
        #expect(try await reopened.fetchPortfolioActivities(portfolioID: f.portfolio.id).contains(changed))
        _ = try await reopened.portfolioReplay(portfolioID: f.portfolio.id)
    }

    @Test("No change, opening note-only change and ordinary creation have distinct effects")
    func noChangeMinorAndCreate() async throws {
        let f = try await PortfolioCorrectionFixture(currency: .cny); defer { f.remove() }
        let old = try await f.seed(kind: "openingLot")
        let initial = try await f.store.readPortfolioActivityEditContext(id: old.id)
        #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id).isEmpty)
        let same = try await f.store.correctPortfolioActivity(f.request(old, token: initial.token, reason: ""))
        guard case .noChange = same else { Issue.record("Expected noChange"); return }
        #expect(try await f.store.readPortfolioActivityEditContext(id: old.id).token == initial.token)
        let note = try PortfolioActivity(id: old.id, portfolioID: old.portfolioID,
            securityLinkID: old.securityLinkID, civilDate: old.civilDate, recordedAt: old.recordedAt,
            exchangeTimeZoneIdentifier: old.exchangeTimeZoneIdentifier, ledgerEntryID: old.ledgerEntryID,
            payload: .openingLot(quantity: AssetQuantity(coefficient: 100_000_000),
                totalCost: f.money(1_000), fx: try f.fx(1_000), note: "Synthetic corrected note"))
        let minor = try await f.store.correctPortfolioActivity(f.request(note, token: initial.token, reason: ""))
        guard case .minorUpdate = minor else { Issue.record("Expected minorUpdate"); return }
        #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id).isEmpty)
        #expect(try await f.store.fetchPortfolioActivities(portfolioID: f.portfolio.id) == [note])
    }

    @Test("Cross-Store state, important ABA and old writer reject stale drafts")
    func staleAndABA() async throws {
        let f = try await PortfolioCorrectionFixture(currency: .usd); defer { f.remove() }
        let old = try await f.seed(kind: "buy")
        let second = try WealthStore(databaseURL: f.database)
        let stale = try await second.readPortfolioActivityEditContext(id: old.id)
        let first = try await f.store.readPortfolioActivityEditContext(id: old.id)
        let next = try f.changed(old)
        _ = try portfolioApplied(await f.store.correctPortfolioActivity(f.request(next, token: first.token)))
        await #expect(throws: PortfolioCorrectionError.staleDraft) {
            _ = try await second.correctPortfolioActivity(f.request(next, token: stale.token))
        }
        let backContext = try await f.store.readPortfolioActivityEditContext(id: old.id)
        _ = try portfolioApplied(await f.store.correctPortfolioActivity(f.request(old, token: backContext.token)))
        await #expect(throws: PortfolioCorrectionError.staleDraft) {
            _ = try await second.correctPortfolioActivity(f.request(next, token: stale.token))
        }
        #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id).count == 2)
    }

    @Test("Durable request replay separates unchanged, changed, deleted and conflict")
    func operationReplay() async throws {
        let f = try await PortfolioCorrectionFixture(currency: .cny); defer { f.remove() }
        let old = try await f.seed(kind: "buy")
        let token = try await f.store.readPortfolioActivityEditContext(id: old.id).token
        let candidate = try f.changed(old)
        let op = UUID()
        let request = f.request(candidate, token: token, operationID: op)
        let first = try portfolioApplied(await f.store.correctPortfolioActivity(request))
        guard case let .alreadyApplied(repeated, .unchanged) = try await f.store.correctPortfolioActivity(request) else {
            Issue.record("Expected unchanged receipt"); return
        }
        #expect(repeated == first)
        await #expect(throws: PortfolioCorrectionError.operationConflict) {
            _ = try await f.store.correctPortfolioActivity(f.request(candidate, token: token,
                operationID: op, reason: "Different synthetic reason"))
        }
        let fresh = try await f.store.readPortfolioActivityEditContext(id: old.id)
        _ = try portfolioApplied(await f.store.correctPortfolioActivity(f.request(old, token: fresh.token)))
        guard case let .alreadyApplied(prior, .changed) = try await f.store.correctPortfolioActivity(request) else {
            Issue.record("Expected changed receipt"); return
        }
        #expect(prior == first)
        try await f.store.deletePortfolioActivity(id: old.id)
        guard case let .alreadyApplied(deleted, .deleted) = try await f.store.correctPortfolioActivity(request) else {
            Issue.record("Expected deleted receipt"); return
        }
        #expect(deleted == first)
        #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id).count == 3)
    }

    @Test("Real SQL UPDATE, FK, FIFO and history INSERT failures roll back Activity and history", arguments: ["update", "foreignKey", "fifo", "history"])
    func atomicFailures(_ fault: String) async throws {
        let f = try await PortfolioCorrectionFixture(currency: .usd); defer { f.remove() }
        let old = try await f.seed(kind: "buy")
        let token = try await f.store.readPortfolioActivityEditContext(id: old.id).token
        let before = try f.rows()
        var candidate = try f.changed(old)
        if fault == "foreignKey" {
            candidate = try PortfolioActivity(id: candidate.id, portfolioID: candidate.portfolioID,
                securityLinkID: candidate.securityLinkID, civilDate: candidate.civilDate,
                recordedAt: candidate.recordedAt,
                exchangeTimeZoneIdentifier: candidate.exchangeTimeZoneIdentifier,
                ledgerEntryID: UUID(),
                payload: candidate.payload)
        }
        if fault == "fifo" {
            let sell = try f.trade(.sell, id: UUID(), quantity: 1, price: 12,
                recordedAt: UTCInstant(millisecondsSince1970: f.instant.millisecondsSince1970 + 1))
            try await f.store.createPortfolioActivity(sell)
            candidate = try f.trade(.buy, id: old.id, quantity: 1, price: 11,
                recordedAt: UTCInstant(millisecondsSince1970: f.instant.millisecondsSince1970 + 2))
        }
        if fault == "update" {
            try f.write("CREATE TRIGGER synthetic_portfolio_update_failure BEFORE UPDATE ON portfolio_activities BEGIN SELECT RAISE(ABORT,'portfolio-update-reached'); END")
        }
        if fault == "history" {
            try f.write("CREATE TRIGGER synthetic_portfolio_history_failure BEFORE INSERT ON portfolio_activity_correction_history WHEN NEW.kind='correction' BEGIN SELECT RAISE(ABORT,'portfolio-history-reached'); END")
        }
        do {
            _ = try await f.store.correctPortfolioActivity(f.request(candidate, token: token))
            Issue.record("Expected targeted failure \(fault)")
        } catch let error as DatabaseError {
            if fault == "update" { #expect(error.message == "portfolio-update-reached") }
            else if fault == "history" { #expect(error.message == "portfolio-history-reached") }
            else { #expect(error.extendedResultCode == .SQLITE_CONSTRAINT_FOREIGNKEY) }
        } catch let error as PortfolioPersistenceError {
            #expect(fault == "fifo" && error == .invalidHistoricalMutation)
        }
        let after = try f.rows()
        if fault == "fifo" {
            #expect(after.filter { $0.contains(old.id.uuidString) }.count == 1)
            #expect(try await f.store.fetchPortfolioActivities(portfolioID: f.portfolio.id).contains(old))
        } else { #expect(after == before) }
        #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id).isEmpty)
    }

    @Test("Single Activity deletion records only necessary context and rolls back failed context", arguments: ["history", "material", "ordinary"])
    func singleDeletionContext(_ variant: String) async throws {
        let f = try await PortfolioCorrectionFixture(currency: .cny, evidence: variant == "material")
        defer { f.remove() }
        let old = try await f.seed(kind: "buy")
        var material: EvidenceImportResult?
        if variant == "history" {
            let token = try await f.store.readPortfolioActivityEditContext(id: old.id).token
            _ = try portfolioApplied(await f.store.correctPortfolioActivity(f.request(f.changed(old), token: token)))
        }
        if variant == "material" {
            material = try await f.store.importEvidence(source: f.source,
                operationID: UUID(), target: .portfolioActivity(old.id))
            _ = try await f.store.linkEvidence(documentID: material!.operation.documentID,
                target: .container(f.wealth.id))
        }
        if variant != "ordinary" {
            try f.write("CREATE TRIGGER synthetic_portfolio_delete_failure BEFORE INSERT ON portfolio_activity_correction_history WHEN NEW.kind='deletionContext' BEGIN SELECT RAISE(ABORT,'portfolio-delete-reached'); END")
            do { try await f.store.deletePortfolioActivity(id: old.id); Issue.record("Expected history failure") }
            catch let error as DatabaseError { #expect(error.message == "portfolio-delete-reached") }
            #expect(try await f.store.fetchPortfolioActivities(portfolioID: f.portfolio.id).count == 1)
            try f.write("DROP TRIGGER synthetic_portfolio_delete_failure")
        }
        try await f.store.deletePortfolioActivity(id: old.id)
        #expect(try await f.store.fetchPortfolioActivities(portfolioID: f.portfolio.id).isEmpty)
        let history = try await f.store.portfolioActivityCorrectionHistory(id: old.id)
        #expect(history.count == (variant == "history" ? 2 : variant == "material" ? 1 : 0))
        if variant != "ordinary" {
            #expect(history.last?.kind == "deletionContext")
            #expect(history.last?.reason == nil)
            #expect(history.last?.payload.deletion?.origin == "existingDeleteActivityAPI")
        }
        if let material {
            #expect(history.last?.payload.deletion?.evidenceLinks.map(\.documentID)
                == [material.operation.documentID])
            #expect(try f.count("evidence_documents") == 1)
            #expect(try f.count("evidence_container_links") == 1)
            #expect(try await f.store.resumeEvidence(operationID: material.operation.id).operation.state == .committed)
            try ManagedEvidenceFiles(root: f.managed).validate(try #require(material.operation.file))
        }
    }

    @Test("Parent cascade retains per-Activity contexts and middle INSERT rollback", arguments: ["security", "portfolio"])
    func parentDeletionContexts(_ parent: String) async throws {
        let f = try await PortfolioCorrectionFixture(currency: .usd, evidence: true); defer { f.remove() }
        let a = try await f.seed(kind: "buy")
        let b = try f.trade(.buy, quantity: 1, price: 9,
            recordedAt: UTCInstant(millisecondsSince1970: f.instant.millisecondsSince1970 + 1))
        try await f.store.createPortfolioActivity(b)
        for activity in [a, b] {
            let token = try await f.store.readPortfolioActivityEditContext(id: activity.id).token
            _ = try portfolioApplied(await f.store.correctPortfolioActivity(f.request(f.changed(activity), token: token)))
        }
        let material = try await f.store.importEvidence(source: f.source,
            operationID: UUID(), target: .portfolioActivity(a.id))
        _ = try await f.store.linkEvidence(documentID: material.operation.documentID,
            target: .container(f.wealth.id))
        try f.write("CREATE TRIGGER synthetic_parent_context_failure BEFORE INSERT ON portfolio_activity_correction_history WHEN NEW.kind='deletionContext' AND NEW.activity_id='\(b.id.uuidString)' BEGIN SELECT RAISE(ABORT,'parent-context-reached'); END")
        do {
            if parent == "security" { try await f.store.unlinkPortfolioSecurity(id: f.link.id) }
            else { try await f.store.deletePortfolio(id: f.portfolio.id) }
            Issue.record("Expected middle context failure")
        } catch let error as DatabaseError { #expect(error.message == "parent-context-reached") }
        #expect(try await f.store.fetchPortfolioActivities(portfolioID: f.portfolio.id).count == 2)
        #expect(try await f.store.portfolioActivityCorrectionHistory(id: a.id).count == 1)
        #expect(try await f.store.portfolioActivityCorrectionHistory(id: b.id).count == 1)
        try f.write("DROP TRIGGER synthetic_parent_context_failure")
        if parent == "security" { try await f.store.unlinkPortfolioSecurity(id: f.link.id) }
        else { try await f.store.deletePortfolio(id: f.portfolio.id) }
        for activity in [a, b] {
            let history = try await f.store.portfolioActivityCorrectionHistory(id: activity.id)
            #expect(history.count == 2)
            #expect(history.last?.payload.deletion?.origin
                == (parent == "security" ? "existingUnlinkSecurityAPI" : "existingDeletePortfolioAPI"))
            #expect(history.last?.payload.before.link == f.link)
        }
        #expect(try f.count("evidence_documents") == 1)
        #expect(try f.count("evidence_container_links") == 1)
        #expect(try await f.store.resumeEvidence(operationID: material.operation.id).operation.state == .committed)
        try ManagedEvidenceFiles(root: f.managed).validate(try #require(material.operation.file))
    }

    @Test("Ledger deletion records exact detach and either history failure rolls back both sides")
    func ledgerDetachContext() async throws {
        let f = try await PortfolioCorrectionFixture(currency: .cny, evidence: true); defer { f.remove() }
        let ledger = try LedgerTestContext.make()
        try await f.store.createWealthContainer(ledger.source)
        let entry = try ledger.entry(kind: .income)
        try await f.store.createLedgerEntry(entry)
        let old = try await f.seed(kind: "buy")
        let linked = try PortfolioActivity(id: old.id, portfolioID: old.portfolioID,
            securityLinkID: old.securityLinkID, civilDate: old.civilDate, recordedAt: old.recordedAt,
            exchangeTimeZoneIdentifier: old.exchangeTimeZoneIdentifier,
            ledgerEntryID: entry.id, payload: old.payload)
        try await f.store.updatePortfolioActivity(linked)
        let material = try await f.store.importEvidence(source: f.source,
            operationID: UUID(), target: .ledger(entry.id))
        try f.write("CREATE TRIGGER synthetic_ledger_detach_failure BEFORE INSERT ON portfolio_activity_correction_history WHEN NEW.kind='ledgerDetachContext' BEGIN SELECT RAISE(ABORT,'ledger-detach-reached'); END")
        do { try await f.store.deleteLedgerEntry(id: entry.id); Issue.record("Expected detach failure") }
        catch let error as DatabaseError { #expect(error.message == "ledger-detach-reached") }
        #expect(try await f.store.fetchLedgerEntries().contains(entry))
        #expect(try await f.store.fetchPortfolioActivities(portfolioID: f.portfolio.id).contains(linked))
        #expect(try await f.store.ledgerCorrectionHistory(id: entry.id).isEmpty)
        try f.write("DROP TRIGGER synthetic_ledger_detach_failure")
        try await f.store.deleteLedgerEntry(id: entry.id)
        let current = try #require(try await f.store.fetchPortfolioActivities(portfolioID: f.portfolio.id).first)
        #expect(current.ledgerEntryID == nil)
        let history = try await f.store.portfolioActivityCorrectionHistory(id: old.id)
        #expect(history.count == 1 && history[0].kind == "ledgerDetachContext")
        #expect(history[0].payload.before.ledgerEntryID == entry.id)
        #expect(history[0].payload.after == PortfolioCorrectionProjection(current, link: f.link))
        #expect(history[0].payload.deletion?.ledgerEntryID == entry.id)
        #expect(try await f.store.ledgerCorrectionHistory(id: entry.id).last?.kind == "deletionContext")
        #expect(try f.count("evidence_documents") == 1)
        #expect(try await f.store.resumeEvidence(operationID: material.operation.id).operation.state == .committed)
    }

    @Test("Restore success and rollback invalidate this Store's Activity token", arguments: [false, true])
    func restoreInvalidatesDraft(_ rollback: Bool) async throws {
        let f = try await PortfolioCorrectionFixture(currency: .usd); defer { f.remove() }
        let old = try await f.seed(kind: "buy")
        let stale = try await f.store.readPortfolioActivityEditContext(id: old.id)
        let generation = try await f.store.createPermanentBackup(in: f.backups,
            appVersion: "synthetic", createdAt: f.instant)
        let operations = PortfolioCorrectionRestoreOperations(rollback: rollback)
        if rollback {
            await #expect(throws: PermanentRestoreError.restoreFailedRollbackSucceeded(.schema)) {
                _ = try await f.store.restorePermanentBackup(generation.directoryURL, in: f.backups,
                    appVersion: "synthetic", createdAt: f.instant, fileOperations: operations)
            }
            #expect(operations.replacements == 2)
        } else {
            _ = try await f.store.restorePermanentBackup(generation.directoryURL, in: f.backups,
                appVersion: "synthetic", createdAt: f.instant, fileOperations: operations)
            #expect(operations.replacements == 1)
        }
        await #expect(throws: PortfolioCorrectionError.staleDraft) {
            _ = try await f.store.correctPortfolioActivity(f.request(f.changed(old), token: stale.token))
        }
        let fresh = try await f.store.readPortfolioActivityEditContext(id: old.id)
        _ = try portfolioApplied(await f.store.correctPortfolioActivity(f.request(f.changed(old), token: fresh.token)))
    }

    @Test("Restoring an older package never merges a later Activity operation", arguments: [false, true])
    func olderGenerationDoesNotMerge(_ externalRestore: Bool) async throws {
        let f = try await PortfolioCorrectionFixture(currency: .usd); defer { f.remove() }
        let old = try await f.seed(kind: "buy")
        let firstToken = try await f.store.readPortfolioActivityEditContext(id: old.id).token
        let middle = try f.changed(old)
        let h1 = try portfolioApplied(await f.store.correctPortfolioActivity(f.request(middle, token: firstToken)))
        let generation = try await f.store.createPermanentBackup(in: f.backups,
            appVersion: "synthetic", createdAt: f.instant)
        let sourceDigest = try PermanentBackupService.streamingDigest(of: generation.directoryURL.appendingPathComponent("aureus.sqlite"))
        let secondToken = try await f.store.readPortfolioActivityEditContext(id: old.id).token
        let later = try f.trade(.buy, id: old.id, quantity: 1, price: 12)
        let oldRequest = f.request(later, token: secondToken)
        let h2 = try portfolioApplied(await f.store.correctPortfolioActivity(oldRequest))
        #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id) == [h1, h2])
        if externalRestore {
            let destination = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: destination) }
            let result = try PermanentBackupExportService.export(internalGenerationURL: generation.directoryURL,
                to: destination, configuration: .init(internalBackupRootURL: f.backups,
                    permanentDatabaseURL: f.database,
                    marketCacheDatabaseURL: f.root.appendingPathComponent("Cache/cache.sqlite"),
                    additionalProtectedDestinationRoots: []), operationID: UUID())
            let source = destination.appendingPathComponent(result.exportedGenerationIdentity)
            _ = try await f.store.restoreExternalPermanentBackup(source,
                configuration: .init(internalBackupRootURL: f.backups,
                    permanentDatabaseURL: f.database,
                    marketCacheDatabaseURL: f.root.appendingPathComponent("Cache/cache.sqlite"),
                    additionalProtectedSourceRoots: []), appVersion: "synthetic", createdAt: f.instant)
        } else {
            _ = try await f.store.restorePermanentBackup(generation.directoryURL, in: f.backups,
                appVersion: "synthetic", createdAt: f.instant)
        }
        #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id) == [h1])
        #expect(try await f.store.fetchPortfolioActivities(portfolioID: f.portfolio.id).contains(middle))
        await #expect(throws: PortfolioCorrectionError.staleDraft) {
            _ = try await f.store.correctPortfolioActivity(oldRequest)
        }
        #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id) == [h1])
        #expect(try PermanentBackupService.streamingDigest(of: generation.directoryURL.appendingPathComponent("aureus.sqlite")) == sourceDigest)
        let fresh = try await f.store.readPortfolioActivityEditContext(id: old.id)
        _ = try portfolioApplied(await f.store.correctPortfolioActivity(f.request(later, token: fresh.token)))
        #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id).count == 2)
    }

    @Test("Real v9 Ledger and Wealth histories survive a validated schema10 safety migration")
    func realV9DualHistoryMigrates() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("Permanent/aureus.sqlite")
        let backups = root.appendingPathComponent("Backups")
        let queue = try DatabaseQueueFactory.open(at: database)
        try DatabaseMigrations.permanentMigrator().migrate(queue, upTo: DatabaseMigrations.permanentV9)
        let ledger = try LedgerTestContext.make()
        let bank = ledger.source
        let stock = try SyntheticWealthSeeder.records()[2]
        let original = try ledger.entry(kind: .income, description: "Synthetic v9 Ledger")
        let edited = try LedgerEntry(id: original.id, kind: original.kind,
            civilDate: original.civilDate, recordedAt: original.recordedAt,
            description: "Synthetic v9 Ledger corrected", postings: original.postings)
        let bankValue = Money(minorUnits: bank.originalValue.minorUnits + 1_000, currency: .cny)
        let correctedBank = try WealthContainer(container: bank.container,
            details: .bankCash(balance: bankValue, interestRate: nil),
            valuation: FXValuation(original: bankValue, rate: .cnyIdentity,
                referenceDate: bank.valuation.referenceDate, fetchedAt: bank.valuation.fetchedAt,
                providerIdentifier: "identity", isStale: bank.valuation.isStale))
        let date = try CivilDate(canonical: "2026-01-15")
        let instant = UTCInstant(millisecondsSince1970: 1_768_435_200_000)
        let portfolio = try PortfolioRecord(name: "Synthetic v9", createdAt: instant,
            updatedAt: instant, sortOrder: 0)
        let link = try PortfolioSecurityLink(portfolioID: portfolio.id,
            wealthContainerID: stock.id, symbol: "SYNX", rawMIC: "XSYN",
            currency: .usd, assetKind: .stock, sortOrder: 0)
        let activityFX = try PortfolioFXProvenance(original: Money(minorUnits: 1_000, currency: .usd),
            rate: FXRate(decimal: 7.25, sourceCurrency: .usd, targetCurrency: .cny),
            source: "synthetic.nonmanual", referenceDate: date, recordedAt: instant,
            isManual: false, isStale: false)
        let activity = try PortfolioActivity(portfolioID: portfolio.id,
            securityLinkID: link.id, civilDate: date, recordedAt: instant,
            exchangeTimeZoneIdentifier: "UTC", payload: .buy(
                quantity: AssetQuantity(coefficient: 100_000_000),
                unitPrice: MarketPrice(decimal: 10, quoteCurrency: .usd),
                fee: Money(minorUnits: 0, currency: .usd), fx: activityFX))
        let histories = try await queue.write { db -> (LedgerCorrectionHistory, WealthCorrectionHistory) in
            for wealth in [bank, stock] {
                try AssetContainerPersistenceRow(container: wealth.container).insert(db)
                try WealthRecordPersistenceRow(record: wealth).insert(db)
            }
            let now = original.recordedAt.millisecondsSince1970
            try LedgerTransactionRow(id: original.id.uuidString, kind: original.kind.rawValue,
                civilDate: original.civilDate.description, recordedAtMS: now,
                description: original.description, payee: nil, categoryID: nil, note: nil,
                importFingerprint: nil, createdAtMS: now, updatedAtMS: now).insert(db)
            try LedgerPostingRow(transactionID: original.id, posting: original.postings[0]).insert(db)
            try db.execute(sql: "UPDATE ledger_transactions SET description=? WHERE id=?",
                arguments: [edited.description, original.id.uuidString])
            let ledgerHistory = try LedgerCorrectionSQL.append(db, operationID: UUID(),
                kind: "correction", occurredAt: instant, reason: "Synthetic v9 ledger correction",
                requestDigest: String(repeating: "a", count: 64),
                postState: LedgerCorrectionSQL.stateDigest(db, id: original.id),
                payload: LedgerHistoryPayload(version: 1, before: .init(original),
                    after: .init(edited), deletion: nil))
            try WealthStore.updateWealthContainer(correctedBank, in: db)
            let wealthHistory = try WealthCorrectionSQL.append(db, operationID: UUID(),
                kind: "correction", occurredAt: instant, reason: "Synthetic v9 wealth correction",
                requestDigest: String(repeating: "b", count: 64),
                postState: WealthCorrectionSQL.stateDigest(db, id: bank.id),
                payload: WealthHistoryPayload(version: 1, before: .init(bank),
                    after: .init(correctedBank), deletion: nil))
            try db.execute(sql: "INSERT INTO portfolio_definitions(id,name,base_currency_code,created_at_ms,updated_at_ms,sort_order) VALUES (?,'Synthetic v9','CNY',?,?,0)",
                arguments: [portfolio.id.uuidString, instant.millisecondsSince1970, instant.millisecondsSince1970])
            try db.execute(sql: "INSERT INTO portfolio_security_links(id,portfolio_id,wealth_container_id,symbol,raw_mic,currency_code,asset_kind,sort_order) VALUES (?,?,?,?,?,?,?,0)",
                arguments: [link.id.uuidString, portfolio.id.uuidString, stock.id.uuidString,
                    link.symbol, link.rawMIC, link.currency.rawValue, link.assetKind.rawValue])
            try WealthStore.insert(activity, in: db)
            return (ledgerHistory, wealthHistory)
        }
        #expect(try PermanentDatabaseValidation.inspect(queue, expectedSchemaVersion: 9,
            requireCurrentApplicationSchema: false).schemaVersion == 9)
        let before = try await queue.read { db -> [String] in
            try ["ledger_correction_history", "wealth_correction_history", "portfolio_activities"]
                .flatMap { try Row.fetchAll(db, sql: "SELECT * FROM \($0) ORDER BY rowid").map(\.description) }
        }
        try queue.close()
        let store = try WealthStore(databaseURL: database,
            migrationSafetyConfiguration: .init(backupRoot: backups, appVersion: "synthetic",
                createdAt: { instant }, generationID: { UUID() }))
        #expect(try await store.schemaVersion() == 10)
        #expect(try await store.ledgerCorrectionHistory(id: original.id) == [histories.0])
        #expect(try await store.wealthCorrectionHistory(id: bank.id) == [histories.1])
        #expect(try await store.fetchPortfolioActivities(portfolioID: portfolio.id) == [activity])
        #expect(try await store.portfolioActivityCorrectionHistory(id: activity.id).isEmpty)
        let safety = try #require(PermanentBackupService.inventory(in: backups).validGenerations.first)
        #expect(safety.manifest.schemaVersion == 9)
        let oldDatabase = safety.directoryURL.appendingPathComponent("aureus.sqlite")
        #expect(try PermanentDatabaseValidation.inspectFile(oldDatabase,
            expectedSchemaVersion: 9, requireCurrentApplicationSchema: false).schemaVersion == 9)
        let oldQueue = try DatabaseQueueFactory.open(at: oldDatabase)
        let safetyRows = try await oldQueue.read { db -> [String] in
            try ["ledger_correction_history", "wealth_correction_history", "portfolio_activities"]
                .flatMap { try Row.fetchAll(db, sql: "SELECT * FROM \($0) ORDER BY rowid").map(\.description) }
        }
        try oldQueue.close()
        #expect(safetyRows == before)
        let liveQueue = try DatabaseQueueFactory.open(at: database)
        let liveRows = try await liveQueue.read { db -> [String] in
            try ["ledger_correction_history", "wealth_correction_history", "portfolio_activities"]
                .flatMap { try Row.fetchAll(db, sql: "SELECT * FROM \($0) ORDER BY rowid").map(\.description) }
        }
        try liveQueue.close()
        #expect(liveRows == before)
        try await store.migrate()
        #expect(try await store.ledgerCorrectionHistory(id: original.id) == [histories.0])
        #expect(try await store.wealthCorrectionHistory(id: bank.id) == [histories.1])
        #expect(try await store.portfolioActivityCorrectionHistory(id: activity.id).isEmpty)
    }

    @Test("History DDL, UUID, operation and typed financial payload are strict", arguments: [
        "table", "index", "trigger", "operation", "uuid", "price", "fxArithmetic", "fxDirection", "date", "version"
    ])
    func historyValidation(_ fault: String) async throws {
        let f = try await PortfolioCorrectionFixture(currency: .usd); defer { f.remove() }
        let old = try await f.seed(kind: "buy")
        let token = try await f.store.readPortfolioActivityEditContext(id: old.id).token
        let history = try portfolioApplied(await f.store.correctPortfolioActivity(f.request(f.changed(old), token: token)))
        let queue = try DatabaseQueueFactory.open(at: f.database); defer { try? queue.close() }
        if fault == "operation" || fault == "uuid" {
            do {
                try await queue.write { db in
                    try db.execute(sql: """
                        INSERT INTO portfolio_activity_correction_history
                        (history_id,operation_id,activity_id,kind,occurred_at_ms,reason,request_digest,post_state_digest,payload)
                        SELECT ?,?, ?,kind,occurred_at_ms,reason,request_digest,post_state_digest,payload
                        FROM portfolio_activity_correction_history WHERE history_id=?
                        """, arguments: [UUID().uuidString,
                            fault == "operation" ? history.operationID.uuidString : UUID().uuidString,
                            fault == "uuid" ? "not-a-uuid" : old.id.uuidString, history.id.uuidString])
                }
                Issue.record("Expected exact SQL constraint")
            } catch let error as DatabaseError {
                #expect(error.extendedResultCode == (fault == "operation"
                    ? .SQLITE_CONSTRAINT_UNIQUE : .SQLITE_CONSTRAINT_CHECK))
            }
            #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id) == [history])
            return
        }
        if fault == "table" { try f.write("DROP TABLE portfolio_activity_correction_history") }
        else if fault == "index" { try f.write("DROP INDEX portfolio_activity_correction_history_target") }
        else if fault == "trigger" { try f.write("DROP TRIGGER portfolio_activity_correction_history_no_update") }
        else {
            try await queue.write { db in
                try db.execute(sql: "DROP TRIGGER portfolio_activity_correction_history_no_update")
                let raw = try #require(try String.fetchOne(db,
                    sql: "SELECT payload FROM portfolio_activity_correction_history WHERE history_id=?",
                    arguments: [history.id.uuidString]))
                var object = try #require(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
                if fault == "version" { object["version"] = 99 }
                else {
                    var before = try #require(object["before"] as? [String: Any])
                    if fault == "date" {
                        var date = try #require(before["civilDate"] as? [String: Any])
                        date["month"] = 2; date["day"] = 31; before["civilDate"] = date
                    } else {
                        var details = try #require(before["details"] as? [String: Any])
                        var buy = try #require(details["buy"] as? [String: Any])
                        if fault == "price" {
                            var price = try #require(buy["unitPrice"] as? [String: Any])
                            price["coefficient"] = -1; buy["unitPrice"] = price
                        } else {
                            var fx = try #require(buy["fx"] as? [String: Any])
                            if fault == "fxArithmetic" {
                                var converted = try #require(fx["convertedCNY"] as? [String: Any])
                                converted["minorUnits"] = -1; fx["convertedCNY"] = converted
                            } else {
                                var rate = try #require(fx["rate"] as? [String: Any])
                                rate["sourceCurrency"] = "CNY"; fx["rate"] = rate
                            }
                            buy["fx"] = fx
                        }
                        details["buy"] = buy; before["details"] = details
                    }
                    object["before"] = before
                }
                let bytes = try JSONSerialization.data(withJSONObject: object,
                    options: [.sortedKeys, .withoutEscapingSlashes])
                let decoded = try JSONDecoder().decode(PortfolioHistoryPayload.self, from: bytes)
                #expect(decoded.before.id == old.id)
                try db.execute(sql: "UPDATE portfolio_activity_correction_history SET payload=? WHERE history_id=?",
                    arguments: [String(decoding: bytes, as: UTF8.self), history.id.uuidString])
                try db.execute(sql: PortfolioCorrectionSQL.declarations[2].1)
            }
            let optionalRow = try await queue.read { db in try Row.fetchOne(db,
                sql: "SELECT * FROM portfolio_activity_correction_history WHERE history_id=?",
                arguments: [history.id.uuidString]) }
            let row = try #require(optionalRow)
            #expect(throws: (any Error).self) { _ = try PortfolioCorrectionSQL.decode(row) }
        }
        #expect(throws: (any Error).self) {
            _ = try PermanentDatabaseValidation.inspectFile(f.database,
                expectedSchemaVersion: 10, requireCurrentApplicationSchema: true)
        }
    }

    @Test("Invalid Portfolio history generation cannot count or prune valid history-only generations")
    func invalidHistoryGenerationNoPrune() async throws {
        let f = try await PortfolioCorrectionFixture(currency: .usd); defer { f.remove() }
        let old = try await f.seed(kind: "buy")
        let token = try await f.store.readPortfolioActivityEditContext(id: old.id).token
        _ = try portfolioApplied(await f.store.correctPortfolioActivity(f.request(f.changed(old), token: token)))
        var clean: [PermanentBackupGeneration] = []
        for index in 0..<5 {
            clean.append(try await f.store.createPermanentBackup(in: f.backups,
                appVersion: "synthetic", createdAt: UTCInstant(
                    millisecondsSince1970: f.instant.millisecondsSince1970 + Int64(index))))
        }
        let validBefore = Set(try PermanentBackupService.inventory(in: f.backups).validGenerations.map(\.directoryURL))
        let first = try #require(clean.first)
        let forged = f.backups.appendingPathComponent("backup-20270101T000000000Z-" + UUID().uuidString.lowercased())
        try FileManager.default.copyItem(at: first.directoryURL, to: forged)
        let dbURL = forged.appendingPathComponent("aureus.sqlite")
        let q = try DatabaseQueueFactory.open(at: dbURL)
        try await q.write { db in
            try db.execute(sql: "DROP TRIGGER portfolio_activity_correction_history_no_update")
            try db.execute(sql: "UPDATE portfolio_activity_correction_history SET payload='{}'")
            try db.execute(sql: PortfolioCorrectionSQL.declarations[2].1)
        }
        try q.close()
        let digest = try PermanentBackupService.streamingDigest(of: dbURL)
        let manifest = PermanentBackupManifest(backupFormatVersion: 1,
            appVersion: first.manifest.appVersion, schemaVersion: 10,
            createdAt: first.manifest.createdAt, databaseByteCount: digest.byteCount,
            databaseSHA256: digest.sha256)
        try JSONEncoder().encode(manifest).write(to: forged.appendingPathComponent("manifest.json"))
        #expect(throws: (any Error).self) {
            _ = try PermanentBackupService.validateGeneration(forged, in: f.backups)
        }
        let inventory = try PermanentBackupService.pruneValidGenerations(in: f.backups)
        #expect(Set(inventory.validGenerations.map(\.directoryURL)) == validBefore)
        #expect(inventory.invalidGenerations.count == 1)
        #expect(FileManager.default.fileExists(atPath: forged.path))
    }

    @Test("Three financial histories survive format1, export and either Restore path", arguments: [false, true])
    func historyOnlyLifecycle(_ externalRestore: Bool) async throws {
        let f = try await PortfolioCorrectionFixture(currency: .usd); defer { f.remove() }
        let old = try await f.seed(kind: "buy")
        let token = try await f.store.readPortfolioActivityEditContext(id: old.id).token
        let first = try portfolioApplied(await f.store.correctPortfolioActivity(f.request(f.changed(old), token: token)))
        let companions = try await f.seedCompanionHistories()
        let generation = try await f.store.createPermanentBackup(in: f.backups,
            appVersion: "synthetic", createdAt: f.instant)
        #expect(try FileManager.default.contentsOfDirectory(atPath: generation.directoryURL.path).sorted()
            == ["aureus.sqlite", "manifest.json"])
        let destination = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let export = try PermanentBackupExportService.export(internalGenerationURL: generation.directoryURL,
            to: destination, configuration: .init(internalBackupRootURL: f.backups,
                permanentDatabaseURL: f.database,
                marketCacheDatabaseURL: f.root.appendingPathComponent("Cache/cache.sqlite"),
                additionalProtectedDestinationRoots: []), operationID: UUID())
        let exported = destination.appendingPathComponent(export.exportedGenerationIdentity)
        #expect(try FileManager.default.contentsOfDirectory(atPath: exported.path).sorted()
            == ["aureus.sqlite", "manifest.json"])
        let sourceBefore = try PermanentBackupService.streamingDigest(of: generation.directoryURL.appendingPathComponent("aureus.sqlite"))
        let nextToken = try await f.store.readPortfolioActivityEditContext(id: old.id).token
        _ = try portfolioApplied(await f.store.correctPortfolioActivity(f.request(
            f.trade(.buy, id: old.id, quantity: 1, price: 12), token: nextToken)))
        if externalRestore {
            _ = try await f.store.restoreExternalPermanentBackup(exported,
                configuration: .init(internalBackupRootURL: f.backups,
                    permanentDatabaseURL: f.database,
                    marketCacheDatabaseURL: f.root.appendingPathComponent("Cache/cache.sqlite"),
                    additionalProtectedSourceRoots: []), appVersion: "synthetic", createdAt: f.instant)
        } else {
            _ = try await f.store.restorePermanentBackup(generation.directoryURL, in: f.backups,
                appVersion: "synthetic", createdAt: f.instant)
        }
        #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id) == [first])
        #expect(try await f.store.ledgerCorrectionHistory(id: companions.ledgerID) == [companions.ledgerHistory])
        #expect(try await f.store.wealthCorrectionHistory(id: companions.wealthID) == [companions.wealthHistory])
        #expect(try PermanentBackupService.streamingDigest(of: generation.directoryURL.appendingPathComponent("aureus.sqlite")) == sourceBefore)
        let inventory = try PermanentBackupService.inventory(in: f.backups)
        #expect(inventory.validGenerations.count >= 2)
        #expect(inventory.validGenerations.contains { $0.directoryURL != generation.directoryURL })
    }

    @Test("Real v9 material and operation states retain fail-closed format1 migration", arguments: ["document", "operation", "unknownRoot"])
    func materialProtection(_ variant: String) async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("Permanent/aureus.sqlite")
        let backups = root.appendingPathComponent("Backups")
        let managed = root.appendingPathComponent("Materials")
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
        let q = try DatabaseQueueFactory.open(at: database)
        try DatabaseMigrations.permanentMigrator().migrate(q, upTo: DatabaseMigrations.permanentV9)
        if variant == "document" || variant == "operation" {
            let documentID = UUID(), operationID = UUID()
            let record = try SyntheticWealthSeeder.records()[0]
            var copied: ManagedEvidenceFile?
            var identity: ManagedEvidenceIdentity?
            if variant == "document" {
                let source = root.appendingPathComponent("synthetic.txt")
                try Data("synthetic material".utf8).write(to: source)
                copied = try ManagedEvidenceFiles(root: managed).copy(source: source,
                    documentID: documentID, observer: { receipt in
                        if case .prepared(_, let value) = receipt { identity = value }
                    })
            }
            let capturedFile = copied
            let capturedIdentity = identity
            try await q.write { db in
                if variant == "document" {
                    let file = try #require(capturedFile)
                    let stamp = try #require(capturedIdentity)
                    try AssetContainerPersistenceRow(container: record.container).insert(db)
                    try WealthRecordPersistenceRow(record: record).insert(db)
                    try db.execute(sql: """
                        INSERT INTO evidence_import_operations(operation_id,document_id,container_id,
                            intended_meaning,original_filename,relative_reference,registered_at_ms,
                            updated_at_ms,state,root_device,root_inode,file_device,file_inode,
                            byte_count,sha256,copied_at_ms)
                        VALUES (?,?,?,'',?,?,0,0,'committed',?,?,?,?,?,?,?)
                        """, arguments: [operationID.uuidString, documentID.uuidString, record.id.uuidString,
                            file.originalFilename, file.relativeReference, stamp.rootDevice,
                            String(stamp.rootInode), stamp.fileDevice, String(stamp.fileInode),
                            file.byteCount, file.sha256, try EvidenceValue.milliseconds(file.copiedAt)])
                    try db.execute(sql: """
                        INSERT INTO evidence_documents(id,original_filename,relative_reference,
                            byte_count,sha256,copied_at_ms,registered_at_ms)
                        VALUES (?,?,?,?,?,?,0)
                        """, arguments: [documentID.uuidString, file.originalFilename,
                            file.relativeReference, file.byteCount, file.sha256,
                            try EvidenceValue.milliseconds(file.copiedAt)])
                } else {
                    try db.execute(sql: """
                        INSERT INTO evidence_import_operations(operation_id,document_id,container_id,
                            intended_meaning,original_filename,relative_reference,registered_at_ms,
                            updated_at_ms,state)
                        VALUES (?,?,?,'','synthetic.txt',?,0,0,'registered')
                        """, arguments: [operationID.uuidString, documentID.uuidString, record.id.uuidString,
                            documentID.uuidString.lowercased() + ".original"])
                }
            }
        } else {
            try Data("synthetic unknown artifact".utf8).write(to: managed.appendingPathComponent("unknown-owned-artifact"))
        }
        try q.close()
        let safety = PermanentMigrationSafetyConfiguration(backupRoot: backups, appVersion: "synthetic",
            createdAt: { UTCInstant(millisecondsSince1970: 1_800_000_000_000) }, generationID: { UUID() })
        #expect(throws: (any Error).self) {
            _ = try WealthStore(databaseURL: database, migrationSafetyConfiguration: safety,
                evidenceConfiguration: .init(root: managed, protectedPaths: [backups]))
        }
        #expect(try PermanentBackupService.inventory(in: backups).validGenerations.isEmpty)
        let unchanged = try DatabaseQueueFactory.open(at: database)
        #expect(try await unchanged.read { try Int.fetchOne($0,
            sql: "SELECT version FROM schema_metadata WHERE store_kind='permanent'") } == 9)
        try unchanged.close()
    }
}

private func portfolioApplied(_ result: PortfolioCorrectionResult) throws -> PortfolioCorrectionHistory {
    guard case let .applied(history) = result else { throw PortfolioCorrectionError.invalidRequest }
    return history
}

private struct PortfolioCorrectionFixture {
    let root: URL, database: URL, backups: URL, external: URL, managed: URL, source: URL
    let store: WealthStore
    let wealth: WealthContainer
    let portfolio: PortfolioRecord
    let link: PortfolioSecurityLink
    let currency: CurrencyCode
    let date: CivilDate
    let instant: UTCInstant

    init(currency: CurrencyCode, evidence: Bool = false) async throws {
        root = try temporaryDirectory()
        database = root.appendingPathComponent("Permanent/aureus.sqlite")
        backups = root.appendingPathComponent("Backups")
        external = root.appendingPathComponent("External")
        managed = root.appendingPathComponent("Materials")
        source = root.appendingPathComponent("synthetic.txt")
        if evidence {
            try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
            try Data("synthetic portfolio evidence\n".utf8).write(to: source)
        }
        store = try WealthStore(databaseURL: database,
            migrationSafetyConfiguration: .init(backupRoot: backups, appVersion: "synthetic",
                createdAt: { UTCInstant(millisecondsSince1970: 1_800_000_000_000) }, generationID: { UUID() }),
            evidenceConfiguration: evidence ? .init(root: managed, protectedPaths: [backups]) : nil)
        self.currency = currency
        date = try CivilDate(canonical: "2026-01-15")
        instant = UTCInstant(millisecondsSince1970: 1_768_435_200_000)
        let wealthID = UUID()
        let container = AssetContainer(id: wealthID, accountID: nil, name: "Synthetic Security",
            kind: .stock, institution: nil, primaryCurrency: currency, notes: nil,
            createdDate: date, updatedDate: date)
        let price = try MarketPrice(decimal: 10, quoteCurrency: currency)
        let details = WealthRecordDetails.security(ticker: "SYNX", mic: "XSYN",
            quantity: AssetQuantity(coefficient: 1_000_000_000), manualPrice: price)
        let total = try details.currentValue()
        let rate = currency == .cny ? FXRate.cnyIdentity : try FXRate(decimal: 7.25,
            sourceCurrency: .usd, targetCurrency: .cny)
        let valuation = try FXValuation(original: total, rate: rate, referenceDate: date,
            fetchedAt: instant, providerIdentifier: currency == .cny ? "identity" : "manual.synthetic",
            isManualOverride: currency == .usd, isStale: false)
        wealth = try WealthContainer(container: container, details: details, valuation: valuation)
        try await store.createWealthContainer(wealth)
        portfolio = try PortfolioRecord(name: "Synthetic Portfolio", createdAt: instant,
            updatedAt: instant, sortOrder: 0)
        try await store.createPortfolio(portfolio)
        link = try PortfolioSecurityLink(portfolioID: portfolio.id, wealthContainerID: wealthID,
            symbol: "SYNX", rawMIC: "XSYN", currency: currency, assetKind: .stock, sortOrder: 0)
        try await store.linkPortfolioSecurity(link)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
    func money(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: currency) }
    func fx(_ minor: Int64) throws -> PortfolioFXProvenance {
        try PortfolioFXProvenance(original: money(minor),
            rate: currency == .cny ? .cnyIdentity : FXRate(decimal: 7.25,
                sourceCurrency: .usd, targetCurrency: .cny),
            source: currency == .cny ? "identity" : "synthetic.nonmanual",
            referenceDate: date, recordedAt: instant, isManual: false, isStale: true)
    }
    func trade(_ kind: PortfolioActivity.Kind, id: UUID = UUID(), quantity: Int64,
               price: Int64, recordedAt: UTCInstant? = nil) throws -> PortfolioActivity {
        let q = AssetQuantity(coefficient: quantity * 100_000_000)
        let p = try MarketPrice(decimal: Decimal(price), quoteCurrency: currency)
        let total = quantity * price * 100
        let payload: PortfolioActivityPayload = kind == .sell
            ? .sell(quantity: q, unitPrice: p, fee: money(0), fx: try fx(total))
            : .buy(quantity: q, unitPrice: p, fee: money(0), fx: try fx(total))
        return try PortfolioActivity(id: id, portfolioID: portfolio.id,
            securityLinkID: link.id, civilDate: date, recordedAt: recordedAt ?? instant,
            exchangeTimeZoneIdentifier: "UTC", payload: payload)
    }
    func seed(kind: String) async throws -> PortfolioActivity {
        if kind == "sell" || kind == "manualSplit" {
            try await store.createPortfolioActivity(trade(.buy, quantity: 2, price: 10,
                recordedAt: UTCInstant(millisecondsSince1970: instant.millisecondsSince1970 - 1)))
        }
        let target: PortfolioActivity
        switch kind {
        case "openingLot": target = try PortfolioActivity(portfolioID: portfolio.id,
            securityLinkID: link.id, civilDate: date, recordedAt: instant,
            exchangeTimeZoneIdentifier: "UTC", payload: .openingLot(
                quantity: AssetQuantity(coefficient: 100_000_000), totalCost: money(1_000),
                fx: fx(1_000), note: "Synthetic original note"))
        case "sell": target = try trade(.sell, quantity: 1, price: 12)
        case "manualSplit": target = try PortfolioActivity(portfolioID: portfolio.id,
            securityLinkID: link.id, civilDate: date, recordedAt: instant,
            exchangeTimeZoneIdentifier: "UTC", payload: .manualSplit(from: Ratio(decimal: 1), to: Ratio(decimal: 2)))
        default: target = try trade(.buy, quantity: 1, price: 10)
        }
        try await store.createPortfolioActivity(target)
        return target
    }
    func changed(_ old: PortfolioActivity) throws -> PortfolioActivity {
        let payload: PortfolioActivityPayload
        switch old.payload {
        case .openingLot: payload = .openingLot(quantity: AssetQuantity(coefficient: 200_000_000),
            totalCost: money(1_000), fx: try fx(1_000), note: "Synthetic original note")
        case .buy: payload = .buy(quantity: AssetQuantity(coefficient: 100_000_000),
            unitPrice: try MarketPrice(decimal: 11, quoteCurrency: currency),
            fee: money(0), fx: try fx(1_100))
        case .sell: payload = .sell(quantity: AssetQuantity(coefficient: 100_000_000),
            unitPrice: try MarketPrice(decimal: 13, quoteCurrency: currency),
            fee: money(0), fx: try fx(1_300))
        case .manualSplit: payload = .manualSplit(from: try Ratio(decimal: 1), to: try Ratio(decimal: 3))
        }
        return try PortfolioActivity(id: old.id, portfolioID: old.portfolioID,
            securityLinkID: old.securityLinkID, civilDate: old.civilDate, recordedAt: old.recordedAt,
            exchangeTimeZoneIdentifier: old.exchangeTimeZoneIdentifier,
            ledgerEntryID: old.ledgerEntryID, payload: payload)
    }
    func request(_ candidate: PortfolioActivity, token: PortfolioActivityEditToken,
                 operationID: UUID = UUID(), reason: String = "Synthetic Activity correction") -> PortfolioCorrectionRequest {
        .init(candidate: candidate, expected: token, operationID: operationID,
            reason: reason, occurredAt: instant)
    }
    func write(_ sql: String) throws {
        let q = try DatabaseQueueFactory.open(at: database); defer { try? q.close() }
        try q.write { try $0.execute(sql: sql) }
    }
    func rows() throws -> [String] {
        let q = try DatabaseQueueFactory.open(at: database); defer { try? q.close() }
        return try q.read { db in try Row.fetchAll(db,
            sql: "SELECT * FROM portfolio_activities ORDER BY id").map(\.description) }
    }
    func count(_ table: String) throws -> Int {
        let q = try DatabaseQueueFactory.open(at: database); defer { try? q.close() }
        return try q.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)") ?? 0 }
    }

    func seedCompanionHistories() async throws -> (ledgerID: UUID,
        ledgerHistory: LedgerCorrectionHistory, wealthID: UUID,
        wealthHistory: WealthCorrectionHistory) {
        let context = try LedgerTestContext.make()
        try await store.createWealthContainer(context.source)
        let entry = try context.entry(kind: .income)
        try await store.createLedgerEntry(entry)
        let bank = context.source
        let value = Money(minorUnits: bank.originalValue.minorUnits + 100,
            currency: bank.container.primaryCurrency)
        let corrected = try WealthContainer(container: bank.container,
            details: .bankCash(balance: value, interestRate: nil),
            valuation: FXValuation(original: value, rate: .cnyIdentity,
                referenceDate: bank.valuation.referenceDate,
                fetchedAt: bank.valuation.fetchedAt, providerIdentifier: "identity",
                isStale: bank.valuation.isStale))
        let changedEntry = try LedgerEntry(id: entry.id, kind: entry.kind,
            civilDate: entry.civilDate, recordedAt: entry.recordedAt,
            description: "Synthetic lifecycle ledger correction", postings: entry.postings)
        let q = try DatabaseQueueFactory.open(at: database); defer { try? q.close() }
        let histories = try await q.write { db -> (LedgerCorrectionHistory,
            WealthCorrectionHistory) in
            try db.execute(sql: "UPDATE ledger_transactions SET description=? WHERE id=?",
                arguments: [changedEntry.description, entry.id.uuidString])
            let ledger = try LedgerCorrectionSQL.append(db, operationID: UUID(),
                kind: "correction", occurredAt: instant,
                reason: "Synthetic lifecycle ledger reason",
                requestDigest: String(repeating: "c", count: 64),
                postState: LedgerCorrectionSQL.stateDigest(db, id: entry.id),
                payload: LedgerHistoryPayload(version: 1, before: .init(entry),
                    after: .init(changedEntry), deletion: nil))
            try WealthStore.updateWealthContainer(corrected, in: db)
            let wealthHistory = try WealthCorrectionSQL.append(db,
                operationID: UUID(), kind: "correction", occurredAt: instant,
                reason: "Synthetic lifecycle wealth reason",
                requestDigest: String(repeating: "d", count: 64),
                postState: WealthCorrectionSQL.stateDigest(db, id: bank.id),
                payload: WealthHistoryPayload(version: 1, before: .init(bank),
                    after: .init(corrected), deletion: nil))
            return (ledger, wealthHistory)
        }
        return (entry.id, histories.0, bank.id, histories.1)
    }
}

private final class PortfolioCorrectionRestoreOperations: PermanentRestoreFileOperations,
    @unchecked Sendable {
    let rollback: Bool
    private(set) var replacements = 0
    init(rollback: Bool) { self.rollback = rollback }
    func copyValidatedDatabase(from sourceURL: URL, to stagingURL: URL) throws {
        try LocalPermanentRestoreFileOperations().copyValidatedDatabase(
            from: sourceURL, to: stagingURL)
    }
    func atomicallyReplaceDatabase(at databaseURL: URL, with stagingURL: URL) throws {
        try LocalPermanentRestoreFileOperations().atomicallyReplaceDatabase(
            at: databaseURL, with: stagingURL)
        replacements += 1
        if rollback && replacements == 1 {
            let q = try DatabaseQueueFactory.open(at: databaseURL); defer { try? q.close() }
            try q.write { try $0.execute(sql: "UPDATE schema_metadata SET version=11 WHERE store_kind='permanent'") }
        }
    }
}
