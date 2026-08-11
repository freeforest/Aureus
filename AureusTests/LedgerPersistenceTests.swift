import Foundation
import GRDB
import Testing
@testable import Aureus

@Suite("Stage 4 ledger persistence")
struct LedgerPersistenceTests {
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
        #expect(try await store.schemaVersion() == 3)
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
        #expect(state.0 == 3); #expect(state.1 == 1); #expect(state.2 == 1)
    }

    @Test("v2 normalization collisions preserve every ID and legacy reference")
    func normalizationCollisionMigration() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let queue = try DatabaseQueueFactory.open(at: root.appendingPathComponent("collision/aureus.sqlite"))
        let migrator = DatabaseMigrations.permanentMigrator()
        try migrator.migrate(queue, upTo: DatabaseMigrations.permanentV2)
        let categoryIDs = [
            "10000000-0000-4000-8000-000000000001",
            "10000000-0000-4000-8000-000000000002",
            "10000000-0000-4000-8000-000000000003",
            "10000000-0000-4000-8000-000000000004"
        ]
        let tagIDs = [
            "20000000-0000-4000-8000-000000000001",
            "20000000-0000-4000-8000-000000000002",
            "20000000-0000-4000-8000-000000000003",
            "20000000-0000-4000-8000-000000000004"
        ]
        try queue.write { db in
            try db.execute(sql: "INSERT INTO accounts (id, name, kind, currency_code) VALUES ('legacy-account', 'Synthetic Legacy', 'cash', 'CNY')")
            try db.execute(sql: "INSERT INTO wealth_transactions (id, account_id, civil_date, amount_minor, currency_code, type) VALUES ('legacy-transaction', 'legacy-account', '2026-01-01', 100, 'CNY', 'income')")
            let categoryNames = ["Food Place", " food  place ", "FOOD PLACE", "Fóód Place"]
            for (id, name) in zip(categoryIDs, categoryNames) {
                try db.execute(sql: "INSERT INTO categories (id, parent_id, name) VALUES (?, NULL, ?)", arguments: [id, name])
            }
            try db.execute(sql: "INSERT INTO categories (id, parent_id, name) VALUES ('10000000-0000-4000-8000-000000000099', ?, 'Synthetic Child')", arguments: [categoryIDs[1]])
            let tagNames = ["Café", " cafe\u{301} ", "CAFÉ", "CAFE"]
            for (id, name) in zip(tagIDs, tagNames) {
                try db.execute(sql: "INSERT INTO tags (id, name) VALUES (?, ?)", arguments: [id, name])
            }
            try db.execute(sql: "INSERT INTO transaction_tags (transaction_id, tag_id) VALUES ('legacy-transaction', ?)", arguments: [tagIDs[1]])
        }
        try migrator.migrate(queue)
        try migrator.migrate(queue)
        let evidence = try queue.read { db in
            (
                try String.fetchAll(db, sql: "SELECT id FROM categories WHERE id IN (?, ?, ?, ?) ORDER BY id", arguments: StatementArguments(categoryIDs)),
                try String.fetchAll(db, sql: "SELECT id FROM tags WHERE id IN (?, ?, ?, ?) ORDER BY id", arguments: StatementArguments(tagIDs)),
                try String.fetchOne(db, sql: "SELECT parent_id FROM categories WHERE id = '10000000-0000-4000-8000-000000000099'"),
                try String.fetchOne(db, sql: "SELECT tag_id FROM transaction_tags WHERE transaction_id = 'legacy-transaction'"),
                try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT normalized_name) FROM categories WHERE id IN (?, ?, ?, ?)", arguments: StatementArguments(categoryIDs)),
                try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT normalized_name) FROM tags WHERE id IN (?, ?, ?, ?)", arguments: StatementArguments(tagIDs))
            )
        }
        #expect(evidence.0 == categoryIDs)
        #expect(evidence.1 == tagIDs)
        #expect(evidence.2 == categoryIDs[1])
        #expect(evidence.3 == tagIDs[1])
        #expect(evidence.4 == 4)
        #expect(evidence.5 == 4)
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
