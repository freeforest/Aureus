import Foundation
import GRDB
import Testing
@testable import Aureus

@Suite("Stage 4 ledger persistence")
struct LedgerPersistenceTests {
    @Test("Editing preserves a real Portfolio activity's Ledger reference")
    func editingPreservesPortfolioLedgerReference() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("aureus.sqlite"))
        let context = try LedgerTestContext.make()
        try await store.createWealthContainer(context.source)
        let original = try context.entry(kind: .income)
        try await store.createLedgerEntry(original)
        let activity = try await linkedActivity(in: store, entry: original)
        let before = try #require(try await store.fetchPortfolioActivities(portfolioID: activity.portfolioID).first)
        try #require(before == activity)
        try #require(before.ledgerEntryID == original.id)

        let edited = try context.entry(kind: .expense, id: original.id, description: "Synthetic Identity Edit")
        try await store.updateLedgerEntry(edited)
        let after = try #require(try await store.fetchPortfolioActivities(portfolioID: activity.portfolioID).first)
        #expect(after.ledgerEntryID == original.id)
        #expect(after == activity)
        let reopened = try WealthStore(databaseURL: root.appendingPathComponent("aureus.sqlite"))
        #expect(try await reopened.fetchPortfolioActivities(portfolioID: activity.portfolioID) == [activity])
        #expect(try await reopened.fetchLedgerEntries() == [edited])
    }

    @Test("Editing replaces owned children and headers, preserves creation time, and survives reopen")
    func editingChildrenAndTimesSurviveReopen() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("aureus.sqlite")
        let store = try WealthStore(databaseURL: url)
        let context = try LedgerTestContext.make()
        try await store.createWealthContainer(context.source)
        try await store.createWealthContainer(context.target)
        let oldTag = try await store.createTag(name: "Synthetic Old Tag")
        let newTag = try await store.createTag(name: "Synthetic New Tag")
        let category = try await store.createCategory(name: "Synthetic Edited Category")
        let transfer = try context.transfer()
        let original = try LedgerEntry(id: transfer.id, kind: .transfer, civilDate: context.date,
            recordedAt: context.instant, description: "Synthetic Original Transfer", payee: "Synthetic Old Payee",
            tags: [oldTag], postings: transfer.postings, note: "Synthetic Old Note", importFingerprint: "synthetic.original.identity")
        try await store.createLedgerEntry(original)
        let unrelated = try context.entry(kind: .income, description: "Synthetic Unrelated Entry")
        try await store.createLedgerEntry(unrelated)
        let activity = try await linkedActivity(in: store, entry: original)
        try #require(try await store.fetchPortfolioActivities(portfolioID: activity.portfolioID) == [activity])
        let portfolios = try await store.fetchPortfolios()
        let links = try await store.fetchPortfolioSecurityLinks(portfolioID: activity.portfolioID)
        let wealth = try await store.fetchWealthContainers()
        let t1 = UTCInstant(millisecondsSince1970: context.instant.millisecondsSince1970 + 86_400_000)
        let valuation = try FXValuation(original: Money(minorUnits: 25_123, currency: .usd),
            rate: FXRate(decimal: FixedPointMath.parseCanonical("7.125"), sourceCurrency: .usd, targetCurrency: .cny),
            referenceDate: CivilDate(canonical: "2026-08-12"), fetchedAt: t1,
            providerIdentifier: "manual.synthetic.identity.edited", isManualOverride: true, isStale: true)
        let edited = try LedgerEntry(id: original.id, kind: .expense,
            civilDate: CivilDate(canonical: "2026-08-12"), recordedAt: t1,
            description: "Synthetic Edited USD Expense", payee: "Synthetic New Payee", category: category,
            tags: [newTag], postings: [LedgerPosting(role: .primary, containerID: context.target.id, valuation: valuation)],
            note: "Synthetic New Note")
        try await store.updateLedgerEntry(edited)

        for reader in [store, try WealthStore(databaseURL: url)] {
            let entries = try await reader.fetchLedgerEntries()
            #expect(entries.count == 2)
            #expect(entries.first { $0.id == original.id } == edited)
            #expect(entries.first { $0.id == unrelated.id } == unrelated)
            #expect(try await reader.fetchPortfolioActivities(portfolioID: activity.portfolioID) == [activity])
            #expect(try await reader.fetchPortfolios() == portfolios)
            #expect(try await reader.fetchPortfolioSecurityLinks(portfolioID: activity.portfolioID) == links)
            #expect(try await reader.fetchWealthContainers() == wealth)
        }
        let queue = try identityReadQueue(url)
        let timestamps = try await queue.read { db in
            let row = try #require(try Row.fetchOne(db, sql: "SELECT created_at_ms, recorded_at_ms, updated_at_ms FROM ledger_transactions WHERE id = ?", arguments: [original.id.uuidString]))
            return [row["created_at_ms"] as Int64, row["recorded_at_ms"] as Int64, row["updated_at_ms"] as Int64]
        }
        #expect(timestamps == [context.instant.millisecondsSince1970, t1.millisecondsSince1970, t1.millisecondsSince1970])
        let childIDs = try await queue.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM ledger_postings WHERE transaction_id = ?", arguments: [original.id.uuidString])
        }
        #expect(childIDs == edited.postings.map { $0.id.uuidString })
        #expect(Set(childIDs).isDisjoint(with: original.postings.map { $0.id.uuidString }))
    }

    @Test("Child FK failures roll back the header, times, fingerprint, all children, and external links")
    func editingChildFailureIsAtomic() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("aureus.sqlite")
        let store = try WealthStore(databaseURL: url)
        let context = try LedgerTestContext.make()
        try await store.createWealthContainer(context.source)
        try await store.createWealthContainer(context.target)
        let tag = try await store.createTag(name: "Synthetic Original Tag")
        let newTag = try await store.createTag(name: "A Synthetic Valid Replacement")
        let base = try context.transfer()
        let original = try LedgerEntry(id: base.id, kind: .transfer, civilDate: base.civilDate,
            recordedAt: base.recordedAt, description: base.description, payee: "Synthetic Original Payee",
            tags: [tag], postings: base.postings, note: "Synthetic Original Note", importFingerprint: "synthetic.rollback.fingerprint")
        try await store.createLedgerEntry(original)
        let activity = try await linkedActivity(in: store, entry: original)
        try #require(try await store.fetchPortfolioActivities(portfolioID: activity.portfolioID) == [activity])
        let before = try identitySnapshot(url)

        // First fail on the second posting; then fail on a tag after both postings and a valid tag were inserted.
        for failOnTag in [false, true] {
            let edited = try LedgerEntry(id: original.id, kind: .transfer,
                civilDate: CivilDate(canonical: "2026-08-12"),
                recordedAt: UTCInstant(millisecondsSince1970: context.instant.millisecondsSince1970 + 86_400_000),
                description: "Synthetic Rejected Edit", payee: "Synthetic Changed Payee",
                tags: failOnTag ? [newTag, Aureus.Tag(id: UUID(), name: "Z Synthetic Missing Tag")] : [newTag],
                postings: [
                    context.posting(22_000, role: .transferSource),
                    context.posting(22_000, role: .transferTarget, containerID: failOnTag ? context.target.id : UUID())
                ], note: "Synthetic Changed Note")
            // Construction above succeeded; the failure must come from the actual Store database write.
            do {
                try await store.updateLedgerEntry(edited)
                Issue.record("Expected a database child foreign-key failure")
            } catch let error as DatabaseError {
                #expect(error.extendedResultCode == .SQLITE_CONSTRAINT_FOREIGNKEY)
            }
            #expect(try identitySnapshot(url) == before)
            #expect(try await store.fetchLedgerEntries() == [original])
            #expect(try await store.fetchPortfolioActivities(portfolioID: activity.portfolioID) == [activity])
        }
        let reopened = try WealthStore(databaseURL: url)
        #expect(try await reopened.fetchLedgerEntries() == [original])
        #expect(try await reopened.fetchPortfolioActivities(portfolioID: activity.portfolioID) == [activity])
    }

    @Test("Editing an absent identity remains not-found and cannot upsert or mutate existing rows")
    func editingMissingIdentityDoesNotInsert() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("aureus.sqlite")
        let store = try WealthStore(databaseURL: url)
        let context = try LedgerTestContext.make()
        try await store.createWealthContainer(context.source)
        let original = try context.entry(kind: .income)
        try await store.createLedgerEntry(original)
        _ = try await linkedActivity(in: store, entry: original)
        let before = try identitySnapshot(url)
        let missing = try context.entry(kind: .expense)
        await #expect(throws: LedgerPersistenceError.transactionNotFound) {
            try await store.updateLedgerEntry(missing)
        }
        #expect(try identitySnapshot(url) == before)
        #expect(try await store.fetchLedgerEntries() == [original])
    }

    @Test("Actual Ledger deletion still nulls the reference while retaining Portfolio and Wealth")
    func deletingLedgerStillNullsPortfolioReference() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("aureus.sqlite")
        let store = try WealthStore(databaseURL: url)
        let context = try LedgerTestContext.make()
        try await store.createWealthContainer(context.source)
        let original = try context.entry(kind: .income)
        try await store.createLedgerEntry(original)
        let activity = try await linkedActivity(in: store, entry: original)
        try #require(try await store.fetchPortfolioActivities(portfolioID: activity.portfolioID) == [activity])
        let portfolios = try await store.fetchPortfolios()
        let links = try await store.fetchPortfolioSecurityLinks(portfolioID: activity.portfolioID)
        let wealth = try await store.fetchWealthContainers()
        try await store.deleteLedgerEntry(id: original.id)
        let reader = try WealthStore(databaseURL: url)
        #expect(try await reader.fetchLedgerEntries().isEmpty)
        let remaining = try #require(try await reader.fetchPortfolioActivities(portfolioID: activity.portfolioID).first)
        let expected = try PortfolioActivity(id: activity.id, portfolioID: activity.portfolioID,
            securityLinkID: activity.securityLinkID, civilDate: activity.civilDate, recordedAt: activity.recordedAt,
            exchangeTimeZoneIdentifier: activity.exchangeTimeZoneIdentifier, ledgerEntryID: nil, payload: activity.payload)
        #expect(remaining == expected)
        #expect(try await reader.fetchPortfolios() == portfolios)
        #expect(try await reader.fetchPortfolioSecurityLinks(portfolioID: activity.portfolioID) == links)
        #expect(try await reader.fetchWealthContainers() == wealth)
    }

    private func identityReadQueue(_ url: URL) throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.readonly = true
        return try DatabaseQueue(path: url.path, configuration: configuration)
    }

    private func identitySnapshot(_ url: URL) throws -> [String: [String]] {
        try identityReadQueue(url).read { db in
            var result: [String: [String]] = [:]
            for table in ["ledger_transactions", "ledger_postings", "ledger_transaction_tags", "categories", "tags",
                          "portfolio_definitions", "portfolio_security_links", "portfolio_activities", "asset_containers", "wealth_records"] {
                result[table] = try Row.fetchAll(db, sql: "SELECT * FROM \(table) ORDER BY rowid").map(\.description)
            }
            return result
        }
    }

    private func linkedActivity(in store: WealthStore, entry: LedgerEntry) async throws -> PortfolioActivity {
        let security = try SyntheticWealthSeeder.records()[2]
        try await store.createWealthContainer(security)
        let portfolio = try PortfolioRecord(name: "Synthetic Ledger Identity", createdAt: entry.recordedAt, updatedAt: entry.recordedAt, sortOrder: 0)
        try await store.createPortfolio(portfolio)
        let link = try PortfolioSecurityLink(portfolioID: portfolio.id, wealthContainerID: security.id,
            symbol: "SYNX", rawMIC: "XSYN", currency: .usd, assetKind: .stock, sortOrder: 0)
        try await store.linkPortfolioSecurity(link)
        let cost = Money(minorUnits: 10_000, currency: .usd)
        let fx = try PortfolioFXProvenance(original: cost,
            rate: FXRate(decimal: FixedPointMath.parseCanonical("7.00"), sourceCurrency: .usd, targetCurrency: .cny),
            source: "manual.synthetic.identity", referenceDate: entry.civilDate, recordedAt: entry.recordedAt,
            isManual: true, isStale: false)
        let activity = try PortfolioActivity(portfolioID: portfolio.id, securityLinkID: link.id,
            civilDate: entry.civilDate, recordedAt: entry.recordedAt, exchangeTimeZoneIdentifier: "UTC",
            ledgerEntryID: entry.id,
            payload: .openingLot(quantity: AssetQuantity(coefficient: 100_000_000), totalCost: cost, fx: fx, note: "Synthetic identity fixture"))
        try await store.createPortfolioActivity(activity)
        return activity
    }

    @Test("Fresh v3, reopen, CRUD, atomic transfer, and INTEGER storage")
    func crudAndReopen() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("permanent/aureus.sqlite")
        let store = try WealthStore(databaseURL: url)
        for record in try SyntheticWealthSeeder.records().prefix(2) { try await store.createWealthContainer(record) }
        let context = try LedgerTestContext.make()
        let income = try context.entry(kind: .income)
        let transfer = try context.transfer()
        try await store.createLedgerEntry(income)
        try await store.createLedgerEntry(transfer)
        #expect(try await store.schemaVersion() == 9)
        #expect(try await store.ledgerTransactionCount() == 2)
        #expect(try await store.ledgerFinancialStorageClasses() == ["integer"])

        let updated = try context.entry(kind: .expense, id: income.id, description: "Synthetic Edited Expense")
        try await store.updateLedgerEntry(updated)
        let reopened = try WealthStore(databaseURL: url)
        #expect(try await reopened.fetchLedgerEntries().contains(updated))
        try await reopened.deleteLedgerEntry(id: transfer.id)
        #expect(try await reopened.ledgerTransactionCount() == 1)
        #expect(try await reopened.fetchWealthContainers().count == 2)
    }

    @Test("Transfer failure rolls back header and both sides")
    func transferFailureRollback() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("aureus.sqlite"))
        let context = try LedgerTestContext.make()
        try await store.createWealthContainer(context.source)
        let invalid = try LedgerEntry(
            kind: .transfer, civilDate: context.date, recordedAt: context.instant, description: "Synthetic Invalid Transfer",
            postings: [
                try context.posting(10_000, role: .transferSource),
                try context.posting(10_000, role: .transferTarget, containerID: UUID())
            ]
        )
        await #expect(throws: (any Error).self) { try await store.createLedgerEntry(invalid) }
        #expect(try await store.ledgerTransactionCount() == 0)
    }

    @Test("Category and tag normalization and in-use deletion protection")
    func taxonomySafety() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("aureus.sqlite"))
        let context = try LedgerTestContext.make(); try await store.createWealthContainer(context.source)
        let category = try await store.createCategory(name: "  Synthetic   Food ")
        let tag = try await store.createTag(name: "Synthetic Tag")
        await #expect(throws: LedgerPersistenceError.duplicateName) { _ = try await store.createCategory(name: "synthetic food") }
        let renamedCategory = try await store.updateCategory(id: category.id, name: "Synthetic Dining")
        let renamedTag = try await store.updateTag(id: tag.id, name: "Synthetic Reviewed")
        #expect(renamedCategory.name == "Synthetic Dining")
        #expect(renamedTag.name == "Synthetic Reviewed")
        let base = try context.entry(kind: .expense)
        let entry = try LedgerEntry(
            id: base.id, kind: base.kind, civilDate: base.civilDate, recordedAt: base.recordedAt,
            description: base.description, category: renamedCategory, tags: [renamedTag], postings: base.postings
        )
        try await store.createLedgerEntry(entry)
        await #expect(throws: LedgerPersistenceError.categoryInUse) { try await store.deleteCategory(id: category.id) }
        await #expect(throws: LedgerPersistenceError.tagInUse) { try await store.deleteTag(id: tag.id) }
        try await store.deleteLedgerEntry(id: entry.id)
        try await store.deleteCategory(id: category.id)
        try await store.deleteTag(id: tag.id)
    }

    @Test("Classification rule CRUD, enable state, links, and protected taxonomy are transactional")
    func classificationRuleLifecycle() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("aureus.sqlite"))
        let context = try LedgerTestContext.make(); try await store.createWealthContainer(context.source)
        let category = try await store.createCategory(name: "Synthetic Rule Category")
        let tag = try await store.createTag(name: "Synthetic Rule Tag")
        let id = UUID()
        let initial = ClassificationRule(
            id: id, name: " Synthetic  Import Rule ", priority: 20, isEnabled: true,
            matchMode: .contains, payeePattern: "Synthetic Payee", kind: .expense,
            sourceContainerID: context.source.id, amountDirection: .outflow,
            resultCategory: category, resultTags: [tag]
        )
        try await store.createClassificationRule(initial)
        var fetched = try await store.fetchClassificationRules()
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "Synthetic Import Rule")
        #expect(fetched[0].resultTags == [tag])
        await #expect(throws: LedgerPersistenceError.categoryInUse) { try await store.deleteCategory(id: category.id) }
        await #expect(throws: LedgerPersistenceError.tagInUse) { try await store.deleteTag(id: tag.id) }

        try await store.setClassificationRuleEnabled(id: id, enabled: false)
        #expect(try await store.fetchClassificationRules().first?.isEnabled == false)
        let updated = ClassificationRule(
            id: id, name: "Synthetic Updated Rule", priority: 5, isEnabled: true,
            matchMode: .exact, payeePattern: nil, kind: .income,
            sourceContainerID: nil, amountDirection: .inflow,
            resultCategory: category, resultTags: []
        )
        try await store.updateClassificationRule(updated)
        fetched = try await store.fetchClassificationRules()
        #expect(fetched == [try updated.validated()])
        try await store.deleteClassificationRule(id: id)
        #expect(try await store.fetchClassificationRules().isEmpty)
        try await store.deleteCategory(id: category.id)
        try await store.deleteTag(id: tag.id)
    }

    @Test("Filtered CNY and USD cash-flow aggregation reproduces after reopen")
    func filteredSummaryAfterReopen() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("aureus.sqlite")
        let store = try WealthStore(databaseURL: url)
        let context = try LedgerTestContext.make()
        try await store.createWealthContainer(context.source)
        try await store.createWealthContainer(context.target)
        let income = try context.entry(kind: .income)
        let usdBase = try context.entry(kind: .expense)
        let usdExpense = try LedgerEntry(
            id: usdBase.id, kind: .expense, civilDate: usdBase.civilDate, recordedAt: usdBase.recordedAt,
            description: "Synthetic USD Expense",
            postings: [try LedgerPosting(role: .primary, containerID: context.target.id, valuation: context.valuation("10.00", currency: .usd))]
        )
        let transfer = try context.transfer()
        try await store.createLedgerEntry(income)
        try await store.createLedgerEntry(usdExpense)
        try await store.createLedgerEntry(transfer)

        let reopened = try WealthStore(databaseURL: url)
        let summary = try await reopened.ledgerSummary()
        #expect(summary.ordinaryInflowCNY.minorUnits == 10_000)
        #expect(summary.ordinaryOutflowCNY.minorUnits == 7_000)
        #expect(summary.netCashFlowCNY.minorUnits == 3_000)
        #expect(summary.transferCount == 1)
        let expenses = try await reopened.fetchLedgerEntries(filter: LedgerFilter(kind: .expense))
        #expect(expenses.map(\.id) == [usdExpense.id])
        let usdOnly = try await reopened.fetchLedgerEntries(filter: LedgerFilter(currency: .usd))
        #expect(usdOnly.map(\.id) == [usdExpense.id])
    }

    @Test("Ledger posting protects Container and deleting Ledger never deletes Container")
    func containerProtection() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("aureus.sqlite"))
        let context = try LedgerTestContext.make(); try await store.createWealthContainer(context.source)
        let entry = try context.entry(kind: .income); try await store.createLedgerEntry(entry)
        let impact = try await store.deletionImpact(for: context.source.id)
        #expect(impact.linkedLedgerPostingCount == 1)
        await #expect(throws: WealthPersistenceError.protectedPermanentDependents) { _ = try await store.deleteWealthContainer(id: context.source.id) }
        #expect(try await store.ledgerTransactionCount() == 1)
        #expect(try await store.fetchWealthContainer(id: context.source.id) != nil)
        try await store.deleteLedgerEntry(id: entry.id)
        #expect(try await store.fetchWealthContainer(id: context.source.id) != nil)
    }

    @Test("v1 to v2 to v3 preserves Stage 3 and legacy foundation rows")
    func migrationPreservesData() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("migration/aureus.sqlite")
        let queue = try DatabaseQueueFactory.open(at: url)
        let migrator = DatabaseMigrations.permanentMigrator()
        try migrator.migrate(queue, upTo: DatabaseMigrations.permanentV2)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO asset_containers (id, name, kind, primary_currency_code, created_date, updated_date) VALUES ('legacy-stage3', 'Synthetic Preserved', 'bankCash', 'CNY', '2026-01-01', '2026-01-01')")
            try db.execute(sql: "INSERT INTO wealth_records (container_id, record_kind, original_minor, original_currency_code, converted_cny_minor, fx_coefficient, fx_source_currency_code, fx_target_currency_code, fx_source, fx_reference_date, fx_recorded_at_ms, fx_is_manual, fx_is_stale) VALUES ('legacy-stage3', 'bankCash', 100, 'CNY', 100, 10000000000, 'CNY', 'CNY', 'identity', '2026-01-01', 0, 0, 0)")
        }
        try migrator.migrate(queue)
        try migrator.migrate(queue)
        let state = try queue.read { db in (
            try Int.fetchOne(db, sql: "SELECT version FROM schema_metadata WHERE store_kind = 'permanent'"),
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM wealth_records WHERE container_id = 'legacy-stage3'"),
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='wealth_transactions'")
        ) }
        #expect(state.0 == 9); #expect(state.1 == 1); #expect(state.2 == 1)
    }

    @Test("v2 normalization collisions and occupied legacy fallbacks preserve every ID and reference")
    func normalizationCollisionMigration() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let queue = try DatabaseQueueFactory.open(at: root.appendingPathComponent("collision/aureus.sqlite"))
        let migrator = DatabaseMigrations.permanentMigrator()
        try migrator.migrate(queue, upTo: DatabaseMigrations.permanentV2)
        let categoryIDs = [
            "10000000-0000-4000-8000-000000000001",
            "10000000-0000-4000-8000-000000000002",
            "10000000-0000-4000-8000-000000000003",
            "10000000-0000-4000-8000-000000000004",
            "10000000-0000-4000-8000-000000000005"
        ]
        let tagIDs = [
            "20000000-0000-4000-8000-000000000001",
            "20000000-0000-4000-8000-000000000002",
            "20000000-0000-4000-8000-000000000003",
            "20000000-0000-4000-8000-000000000004"
        ]
        let categoryNames = [
            "food place\u{1f}legacy:\(categoryIDs[2])",
            "Food Place",
            " food  place ",
            "FOOD PLACE",
            "Fóód Place"
        ]
        let tagNames = [
            "cafe\u{1f}legacy:\(tagIDs[2])",
            "Café",
            " cafe\u{301} ",
            "CAFE"
        ]
        try queue.write { db in
            try db.execute(sql: "INSERT INTO accounts (id, name, kind, currency_code) VALUES ('legacy-account', 'Synthetic Legacy', 'cash', 'CNY')")
            try db.execute(sql: "INSERT INTO wealth_transactions (id, account_id, civil_date, amount_minor, currency_code, type) VALUES ('legacy-transaction', 'legacy-account', '2026-01-01', 100, 'CNY', 'income')")
            for (id, name) in zip(categoryIDs, categoryNames) {
                try db.execute(sql: "INSERT INTO categories (id, parent_id, name) VALUES (?, NULL, ?)", arguments: [id, name])
            }
            try db.execute(sql: "INSERT INTO categories (id, parent_id, name) VALUES ('10000000-0000-4000-8000-000000000099', ?, 'Synthetic Child')", arguments: [categoryIDs[2]])
            for (id, name) in zip(tagIDs, tagNames) {
                try db.execute(sql: "INSERT INTO tags (id, name) VALUES (?, ?)", arguments: [id, name])
            }
            try db.execute(sql: "INSERT INTO transaction_tags (transaction_id, tag_id) VALUES ('legacy-transaction', ?)", arguments: [tagIDs[2]])
        }
        try migrator.migrate(queue)
        let firstNormalizedState = try queue.read { db in (
            try String.fetchAll(db, sql: "SELECT normalized_name FROM categories ORDER BY id"),
            try String.fetchAll(db, sql: "SELECT normalized_name FROM tags ORDER BY id")
        ) }
        try migrator.migrate(queue)
        let evidence = try queue.read { db in
            (
                try String.fetchAll(db, sql: "SELECT id FROM categories WHERE id != '10000000-0000-4000-8000-000000000099' ORDER BY id"),
                try String.fetchAll(db, sql: "SELECT id FROM tags ORDER BY id"),
                try String.fetchOne(db, sql: "SELECT parent_id FROM categories WHERE id = '10000000-0000-4000-8000-000000000099'"),
                try String.fetchOne(db, sql: "SELECT tag_id FROM transaction_tags WHERE transaction_id = 'legacy-transaction'"),
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories"),
                try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT normalized_name) FROM categories"),
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags"),
                try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT normalized_name) FROM tags"),
                try String.fetchAll(db, sql: "SELECT name FROM categories WHERE id != '10000000-0000-4000-8000-000000000099' ORDER BY id"),
                try String.fetchAll(db, sql: "SELECT name FROM tags ORDER BY id"),
                try String.fetchAll(db, sql: "SELECT normalized_name FROM categories ORDER BY id"),
                try String.fetchAll(db, sql: "SELECT normalized_name FROM tags ORDER BY id")
            )
        }
        #expect(evidence.0 == categoryIDs)
        #expect(evidence.1 == tagIDs)
        #expect(evidence.2 == categoryIDs[2])
        #expect(evidence.3 == tagIDs[2])
        #expect(evidence.4 == evidence.5)
        #expect(evidence.6 == evidence.7)
        #expect(evidence.8 == categoryNames)
        #expect(evidence.9 == tagNames)
        #expect(evidence.10 == firstNormalizedState.0)
        #expect(evidence.11 == firstNormalizedState.1)
    }

    @Test("Migrated taxonomy collisions resolve safely through production fetch and CSV Preview")
    func migratedTaxonomyCollisionPreviewSafety() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("taxonomy-preview/aureus.sqlite")
        let queue = try DatabaseQueueFactory.open(at: url)
        let migrator = DatabaseMigrations.permanentMigrator()
        try migrator.migrate(queue, upTo: DatabaseMigrations.permanentV2)

        let categoryRows: [(String, String, String?)] = [
            ("71000000-0000-4000-8000-000000000001", "Synthetic Café", nil),
            ("71000000-0000-4000-8000-000000000002", "synthetic cafe", nil),
            ("71000000-0000-4000-8000-000000000003", "Synthetic  Space", nil),
            ("71000000-0000-4000-8000-000000000004", " synthetic space ", nil),
            ("71000000-0000-4000-8000-000000000005", "Synthetic Exact Duplicate", nil),
            ("71000000-0000-4000-8000-000000000006", "Synthetic Exact Duplicate", nil),
            ("71000000-0000-4000-8000-000000000007", "   ", nil),
            ("71000000-0000-4000-8000-000000000008", "Synthetic Child", "71000000-0000-4000-8000-000000000001"),
            ("71000000-0000-4000-8000-000000000009", "Synthetic Legal", nil)
        ]
        let tagRows: [(String, String)] = [
            ("72000000-0000-4000-8000-000000000001", "Synthetic Café Tag"),
            ("72000000-0000-4000-8000-000000000002", "synthetic cafe tag"),
            ("72000000-0000-4000-8000-000000000003", "Synthetic  Space Tag"),
            ("72000000-0000-4000-8000-000000000004", " synthetic space tag "),
            ("72000000-0000-4000-8000-000000000005", "Synthetic Exact Café"),
            ("72000000-0000-4000-8000-000000000006", "Synthetic Exact Cafe\u{301}"),
            ("72000000-0000-4000-8000-000000000007", "   "),
            ("72000000-0000-4000-8000-000000000008", "Synthetic Legal Tag")
        ]
        try await queue.write { db in
            try db.execute(sql: "INSERT INTO accounts (id, name, kind, currency_code) VALUES ('taxonomy-account', 'Synthetic Taxonomy Account', 'cash', 'CNY')")
            try db.execute(sql: "INSERT INTO wealth_transactions (id, account_id, civil_date, amount_minor, currency_code, type) VALUES ('taxonomy-transaction', 'taxonomy-account', '2026-01-01', 100, 'CNY', 'expense')")
            for (id, name, parentID) in categoryRows {
                try db.execute(
                    sql: "INSERT INTO categories (id, parent_id, name) VALUES (?, ?, ?)",
                    arguments: [id, parentID, name]
                )
            }
            for (id, name) in tagRows {
                try db.execute(sql: "INSERT INTO tags (id, name) VALUES (?, ?)", arguments: [id, name])
            }
            try db.execute(
                sql: "INSERT INTO transaction_tags (transaction_id, tag_id) VALUES ('taxonomy-transaction', ?)",
                arguments: [tagRows[0].0]
            )
        }
        try migrator.migrate(queue)
        let store = try WealthStore(databaseURL: url)
        let categories = try await store.fetchCategories()
        let tags = try await store.fetchTags()
        let context = try LedgerTestContext.make()

        func category(_ id: String) throws -> Aureus.Category {
            try #require(categories.first { $0.id.uuidString.lowercased() == id.lowercased() })
        }
        func tag(_ id: String) throws -> Aureus.Tag {
            try #require(tags.first { $0.id.uuidString.lowercased() == id.lowercased() })
        }
        func entry(category: Aureus.Category?, tags: [Aureus.Tag], description: String) throws -> LedgerEntry {
            let base = try context.entry(kind: .expense, description: description)
            return try LedgerEntry(
                id: base.id, kind: base.kind, civilDate: base.civilDate, recordedAt: base.recordedAt,
                description: base.description, category: category, tags: tags, postings: base.postings
            )
        }
        func preview(_ data: Data) throws -> LedgerImportPreview {
            try LedgerCSV.preview(
                data: data, containers: [context.source], categories: categories, tags: tags,
                rules: [], existingFingerprints: []
            )
        }
        func csv(category categoryName: String = "", tags tagNames: [String] = []) throws -> Data {
            var records = try LedgerCSV.parseRecords(String(decoding: LedgerCSV.export([
                try context.entry(kind: .expense, description: "Synthetic Resolver Input")
            ]), as: UTF8.self))
            records[1][try #require(LedgerCSV.header.firstIndex(of: "category"))] = categoryName
            records[1][try #require(LedgerCSV.header.firstIndex(of: "tags"))] = String(
                decoding: try JSONEncoder().encode(tagNames), as: UTF8.self
            )
            return encodedLedgerCSV(records)
        }

        let exactCategory = try category(categoryRows[0].0)
        let exactTag = try tag(tagRows[0].0)
        let exactRoundTrip = try preview(LedgerCSV.export([
            try entry(category: exactCategory, tags: [exactTag], description: "Synthetic Exact Round Trip")
        ]))
        #expect(exactRoundTrip.canImport)
        #expect(exactRoundTrip.validEntries.first?.category?.id == exactCategory.id)
        #expect(exactRoundTrip.validEntries.first?.tags.map(\.id) == [exactTag.id])

        let normalizedCategory = try preview(csv(category: "SYNTHETIC CAFE"))
        #expect(normalizedCategory.rows.first?.error == LedgerCSVError.ambiguousCategory("SYNTHETIC CAFE").description)
        #expect(!normalizedCategory.canImport)
        let exactDuplicateCategory = try preview(csv(category: "Synthetic Exact Duplicate"))
        #expect(exactDuplicateCategory.rows.first?.error == LedgerCSVError.ambiguousCategory("Synthetic Exact Duplicate").description)
        #expect(!exactDuplicateCategory.canImport)

        let normalizedTag = try preview(csv(tags: ["SYNTHETIC CAFE TAG"]))
        #expect(normalizedTag.rows.first?.error == LedgerCSVError.ambiguousTag("SYNTHETIC CAFE TAG").description)
        #expect(!normalizedTag.canImport)
        let exactDuplicateTag = try preview(csv(tags: ["Synthetic Exact Café"]))
        #expect(exactDuplicateTag.rows.first?.error == LedgerCSVError.ambiguousTag("Synthetic Exact Café").description)
        #expect(!exactDuplicateTag.canImport)

        let legacyInvalid = try preview(LedgerCSV.export([
            try entry(
                category: try category(categoryRows[6].0),
                tags: [try tag(tagRows[6].0)],
                description: "Synthetic Invalid Legacy Name Round Trip"
            )
        ]))
        #expect(legacyInvalid.canImport)
        #expect(legacyInvalid.validEntries.first?.category?.id == UUID(uuidString: categoryRows[6].0))
        #expect(legacyInvalid.validEntries.first?.tags.first?.id == UUID(uuidString: tagRows[6].0))

        let legal = try preview(LedgerCSV.export([
            try entry(
                category: try category(categoryRows[8].0),
                tags: [try tag(tagRows[7].0)],
                description: "Synthetic Unreferenced Collision Isolation"
            )
        ]))
        #expect(legal.canImport)
        #expect(legal.errorCount == 0)

        let preserved = try await queue.read { db in (
            try Row.fetchAll(db, sql: "SELECT id, name, parent_id FROM categories ORDER BY id").map { row in
                let id: String = row["id"]
                let name: String = row["name"]
                let parent: String? = row["parent_id"]
                return "\(id)|\(name)|\(parent ?? "nil")"
            },
            try Row.fetchAll(db, sql: "SELECT id, name FROM tags ORDER BY id").map { row in
                let id: String = row["id"]
                let name: String = row["name"]
                return "\(id)|\(name)"
            },
            try String.fetchOne(db, sql: "SELECT tag_id FROM transaction_tags WHERE transaction_id = 'taxonomy-transaction'"),
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories"),
            try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT normalized_name) FROM categories"),
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags"),
            try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT normalized_name) FROM tags")
        ) }
        #expect(preserved.0 == categoryRows.map { "\($0.0)|\($0.1)|\($0.2 ?? "nil")" })
        #expect(preserved.1 == tagRows.map { "\($0.0)|\($0.1)" })
        #expect(preserved.2 == tagRows[0].0)
        #expect(preserved.3 == preserved.4)
        #expect(preserved.5 == preserved.6)
    }

    @Test("v3 candidate semantic fingerprint repair preserves colliding transactions")
    func candidateFingerprintRepairMigration() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let queue = try DatabaseQueueFactory.open(at: root.appendingPathComponent("fingerprint-repair/aureus.sqlite"))
        let migrator = DatabaseMigrations.permanentMigrator()
        try migrator.migrate(queue, upTo: DatabaseMigrations.permanentV3)
        let containerID = "30000000-0000-4000-8000-000000000001"
        let transactionIDs = [
            "40000000-0000-4000-8000-000000000001",
            "40000000-0000-4000-8000-000000000002"
        ]
        try queue.write { db in
            try db.execute(sql: "INSERT INTO asset_containers (id, name, kind, primary_currency_code, created_date, updated_date) VALUES (?, 'Synthetic Repair Container', 'bankCash', 'CNY', '2026-01-01', '2026-01-01')", arguments: [containerID])
            for (offset, transactionID) in transactionIDs.enumerated() {
                try db.execute(
                    sql: "INSERT INTO ledger_transactions (id, kind, civil_date, recorded_at_ms, description, import_fingerprint, created_at_ms, updated_at_ms) VALUES (?, 'expense', '2026-01-15', 1768435200000, 'Synthetic Candidate Duplicate', ?, 1768435200000, 1768435200000)",
                    arguments: [transactionID, "legacy-raw-fingerprint-\(offset)"]
                )
                try db.execute(
                    sql: "INSERT INTO ledger_postings (id, transaction_id, role, container_id, original_minor, original_currency_code, converted_cny_minor, fx_coefficient, fx_source_currency_code, fx_target_currency_code, fx_source, fx_reference_date, fx_recorded_at_ms, fx_is_manual, fx_is_stale) VALUES (?, ?, 'primary', ?, 1000, 'CNY', 1000, 10000000000, 'CNY', 'CNY', 'identity', '2026-01-15', 1768435200000, 0, 0)",
                    arguments: ["50000000-0000-4000-8000-00000000000\(offset + 1)", transactionID, containerID]
                )
            }
        }
        try migrator.migrate(queue)
        let firstState = try queue.read { db in (
            try Int.fetchOne(db, sql: "SELECT version FROM schema_metadata WHERE store_kind = 'permanent'"),
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ledger_transactions"),
            try String.fetchAll(db, sql: "SELECT id FROM ledger_transactions ORDER BY id"),
            try Row.fetchAll(db, sql: "SELECT id, import_fingerprint FROM ledger_transactions ORDER BY id")
                .map { row in
                    let id: String = row["id"]
                    let fingerprint: String? = row["import_fingerprint"]
                    return "\(id)|\(fingerprint ?? "nil")"
                }
        ) }
        try migrator.migrate(queue)
        let secondState = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, import_fingerprint FROM ledger_transactions ORDER BY id")
                .map { row in
                    let id: String = row["id"]
                    let fingerprint: String? = row["import_fingerprint"]
                    return "\(id)|\(fingerprint ?? "nil")"
                }
        }
        #expect(firstState.0 == 9)
        #expect(firstState.1 == 2)
        #expect(firstState.2 == transactionIDs)
        #expect(firstState.3.filter { !$0.hasSuffix("|nil") }.count == 1)
        #expect(secondState == firstState.3)
    }

    @Test("v3 candidate fingerprint repair failure leaves candidate data unchanged")
    func candidateFingerprintRepairRollback() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let queue = try DatabaseQueueFactory.open(at: root.appendingPathComponent("fingerprint-rollback/aureus.sqlite"))
        let migrator = DatabaseMigrations.permanentMigrator()
        try migrator.migrate(queue, upTo: DatabaseMigrations.permanentV3)
        let transactionID = "60000000-0000-4000-8000-000000000001"
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO ledger_transactions (id, kind, civil_date, recorded_at_ms, description, import_fingerprint, created_at_ms, updated_at_ms) VALUES (?, 'expense', '2026-01-15', 1768435200000, 'Synthetic Incomplete Candidate', 'legacy-fingerprint', 1768435200000, 1768435200000)",
                arguments: [transactionID]
            )
        }
        #expect(throws: (any Error).self) { try migrator.migrate(queue) }
        let state = try queue.read { db in (
            try Int.fetchOne(db, sql: "SELECT version FROM schema_metadata WHERE store_kind = 'permanent'"),
            try String.fetchOne(db, sql: "SELECT import_fingerprint FROM ledger_transactions WHERE id = ?", arguments: [transactionID]),
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ledger_transactions")
        ) }
        #expect(state.0 == 3)
        #expect(state.1 == "legacy-fingerprint")
        #expect(state.2 == 1)
    }

    @Test("Cache reset leaves Ledger and wealth unchanged")
    func cacheIsolation() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let wealth = try WealthStore(databaseURL: root.appendingPathComponent("permanent/aureus.sqlite"))
        let cache = try MarketCacheStore(databaseURL: root.appendingPathComponent("cache/market.sqlite"))
        let context = try LedgerTestContext.make(); try await wealth.createWealthContainer(context.source)
        try await wealth.createLedgerEntry(context.entry(kind: .dividend)); try await cache.seedSyntheticCache()
        try await cache.reset()
        #expect(try await wealth.ledgerTransactionCount() == 1)
        #expect(try await wealth.fetchWealthContainer(id: context.source.id) != nil)
        #expect(try await cache.cachedRowCount() == 0)
    }
}

private func encodedLedgerCSV(_ records: [[String]]) -> Data {
    let text = records.map { record in
        record.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",")
    }.joined(separator: "\r\n") + "\r\n"
    return Data(text.utf8)
}
