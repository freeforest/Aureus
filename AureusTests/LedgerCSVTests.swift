import Foundation
import Testing
@testable import Aureus

@Suite("Aureus Ledger V1 CSV")
struct LedgerCSVTests {
    @Test("Quoted comma, quote, newline, UTF-8, and formula text round trip")
    func escapedRoundTrip() throws {
        let context = try LedgerTestContext.make()
        let base = try context.entry(kind: .income)
        let entry = try LedgerEntry(
            id: base.id, kind: base.kind, civilDate: base.civilDate, recordedAt: base.recordedAt,
            description: "=Synthetic, \"quoted\"\n中文", payee: "+Formula Payee",
            postings: base.postings, note: "'Leading apostrophe"
        )
        let data = LedgerCSV.export([entry])
        let parsedHeader = try #require(LedgerCSV.parseRecords(String(decoding: data, as: UTF8.self)).first)
        #expect(parsedHeader == LedgerCSV.header)
        let preview = try LedgerCSV.preview(
            data: data, containers: [context.source], categories: [], tags: [], rules: [], existingFingerprints: []
        )
        #expect(preview.canImport)
        #expect(preview.validEntries.first?.description == entry.description)
        #expect(preview.validEntries.first?.payee == entry.payee)
        #expect(preview.validEntries.first?.note == entry.note)
    }

    @Test("Transfer and USD provenance survive export/import")
    func transferRoundTrip() throws {
        let context = try LedgerTestContext.make()
        let entry = try context.transfer(source: "100.00", target: "10.00", targetCurrency: .usd)
        let preview = try LedgerCSV.preview(
            data: LedgerCSV.export([entry]), containers: [context.source, context.target],
            categories: [], tags: [], rules: [], existingFingerprints: []
        )
        #expect(preview.validEntries.first?.kind == .transfer)
        #expect(preview.validEntries.first?.transferTarget?.valuation.original.currency == .usd)
        #expect(preview.validEntries.first?.transferTarget?.valuation.convertedCNY.minorUnits == 7_000)
    }

    @Test("Repeated import is explicitly detected")
    func duplicates() throws {
        let context = try LedgerTestContext.make(); let data = LedgerCSV.export([try context.entry(kind: .expense)])
        let first = try LedgerCSV.preview(data: data, containers: [context.source], categories: [], tags: [], rules: [], existingFingerprints: [])
        let fingerprint = try #require(first.validEntries.first?.importFingerprint)
        let second = try LedgerCSV.preview(data: data, containers: [context.source], categories: [], tags: [], rules: [], existingFingerprints: [fingerprint])
        #expect(second.duplicateCount == 1); #expect(!second.canImport)
    }

    @Test("Import preview exposes deterministic classification before confirmation")
    func classificationPreview() throws {
        let context = try LedgerTestContext.make()
        let category = Category(id: UUID(), parentID: nil, name: "Synthetic Classified")
        let tag = Tag(id: UUID(), name: "Synthetic Rule Tag")
        let rule = ClassificationRule(
            id: UUID(), name: "Synthetic exact rule", priority: 1, isEnabled: true,
            matchMode: .exact, payeePattern: "Synthetic Payee", kind: .expense,
            sourceContainerID: context.source.id, amountDirection: .outflow,
            resultCategory: category, resultTags: [tag]
        )
        let base = try context.entry(kind: .expense)
        let candidate = try LedgerEntry(
            id: base.id, kind: base.kind, civilDate: base.civilDate, recordedAt: base.recordedAt,
            description: base.description, payee: "Synthetic Payee", postings: base.postings
        )
        let preview = try LedgerCSV.preview(
            data: LedgerCSV.export([candidate]), containers: [context.source],
            categories: [category], tags: [tag], rules: [rule], existingFingerprints: []
        )
        #expect(preview.rows.first?.ruleApplication?.ruleID == rule.id)
        #expect(preview.rows.first?.ruleApplication?.ruleName == rule.name)
        #expect(preview.rows.first?.ruleApplication?.finalCategoryName == category.name)
        #expect(preview.rows.first?.ruleApplication?.finalTagNames == [tag.name])
        #expect(preview.rows.first?.ruleApplication?.categorySource == .rule)
        #expect(preview.rows.first?.ruleApplication?.tagsSource == .rule)
        #expect(preview.validEntries.first?.category == category)
        #expect(preview.validEntries.first?.tags == [tag])
    }

    @Test("Every user-controlled text column has reversible spreadsheet formula protection", arguments: ["=", "+", "-", "@", "'"])
    func formulaProtection(_ prefix: String) throws {
        let context = try LedgerTestContext.make()
        let category = Category(id: UUID(), parentID: nil, name: "\(prefix)Category")
        let tag = Tag(id: UUID(), name: "\(prefix)Tag")
        let date = context.date
        let instant = context.instant
        func valuation() throws -> FXValuation {
            try FXValuation(
                original: Money(minorUnits: 1_000, currency: .usd),
                rate: FXRate(decimal: FixedPointMath.parseCanonical("7.00"), sourceCurrency: .usd, targetCurrency: .cny),
                referenceDate: date,
                fetchedAt: instant,
                providerIdentifier: "\(prefix)manual FX source",
                isManualOverride: true,
                isStale: false
            )
        }
        let ordinary = try LedgerEntry(
            kind: .expense,
            civilDate: date,
            recordedAt: instant,
            description: "\(prefix)Description",
            payee: "\(prefix)Payee",
            category: category,
            tags: [tag],
            postings: [try LedgerPosting(role: .primary, containerID: context.source.id, valuation: valuation())],
            note: "\(prefix)Note"
        )
        let transfer = try LedgerEntry(
            kind: .transfer,
            civilDate: date,
            recordedAt: instant,
            description: "\(prefix)Description",
            payee: "\(prefix)Payee",
            tags: [tag],
            postings: [
                try LedgerPosting(role: .transferSource, containerID: context.source.id, valuation: valuation()),
                try LedgerPosting(role: .transferTarget, containerID: context.target.id, valuation: valuation())
            ],
            note: "\(prefix)Note"
        )
        let data = LedgerCSV.export([ordinary, transfer])
        let records = try LedgerCSV.parseRecords(String(decoding: data, as: UTF8.self))
        let dataRows = records.dropFirst().map { Dictionary(uniqueKeysWithValues: zip(LedgerCSV.header, $0)) }
        let ordinaryColumns = try #require(dataRows.first { $0["kind"] == TransactionKind.expense.rawValue })
        let transferColumns = try #require(dataRows.first { $0["kind"] == TransactionKind.transfer.rawValue })
        for name in ["description", "payee", "category", "tags", "note", "source_fx_source"] {
            #expect(ordinaryColumns[name]?.contains("'") == true)
        }
        #expect(transferColumns["target_fx_source"]?.contains("'") == true)
        let preview = try LedgerCSV.preview(
            data: data,
            containers: [context.source, context.target],
            categories: [category],
            tags: [tag],
            rules: [],
            existingFingerprints: []
        )
        let importedOrdinary = try #require(preview.validEntries.first { $0.kind == .expense })
        let importedTransfer = try #require(preview.validEntries.first { $0.kind == .transfer })
        #expect(importedOrdinary.description == ordinary.description)
        #expect(importedOrdinary.payee == ordinary.payee)
        #expect(importedOrdinary.category == category)
        #expect(importedOrdinary.tags.map(\.name) == [tag.name])
        #expect(importedOrdinary.note == ordinary.note)
        #expect(importedOrdinary.primaryPosting?.valuation.providerIdentifier == "\(prefix)manual FX source")
        #expect(importedTransfer.transferSource?.valuation.providerIdentifier == "\(prefix)manual FX source")
        #expect(importedTransfer.transferTarget?.valuation.providerIdentifier == "\(prefix)manual FX source")
    }

    @Test("Preview distinguishes existing and in-file transaction ID and fingerprint duplicates")
    func duplicateReasons() throws {
        let context = try LedgerTestContext.make()
        let first = try context.entry(kind: .expense, id: UUID(), description: "Synthetic Duplicate")
        let second = try context.entry(kind: .expense, id: UUID(), description: "Synthetic Duplicate")
        let semanticData = LedgerCSV.export([first, second])
        let semanticPreview = try LedgerCSV.preview(
            data: semanticData,
            containers: [context.source], categories: [], tags: [], rules: [],
            existingFingerprints: []
        )
        #expect(semanticPreview.rows[1].duplicateReasons == [.fileFingerprint])

        let records = try LedgerCSV.parseRecords(String(decoding: LedgerCSV.export([first]), as: UTF8.self))
        var combined = records
        var secondIDRow = records[1]
        let descriptionIndex = try #require(LedgerCSV.header.firstIndex(of: "description"))
        secondIDRow[descriptionIndex] = "Different description"
        combined.append(secondIDRow)
        let duplicateIDData = encodedCSV(combined)
        let idPreview = try LedgerCSV.preview(
            data: duplicateIDData,
            containers: [context.source], categories: [], tags: [], rules: [],
            existingFingerprints: []
        )
        #expect(idPreview.rows[1].duplicateReasons == [.fileTransactionID])

        let fingerprint = try #require(semanticPreview.rows[0].entry?.importFingerprint)
        let existingPreview = try LedgerCSV.preview(
            data: LedgerCSV.export([first]),
            containers: [context.source], categories: [], tags: [], rules: [],
            existingFingerprints: [fingerprint], existingTransactionIDs: [first.id]
        )
        #expect(existingPreview.rows[0].duplicateReasons == [.existingFingerprint, .existingTransactionID])
    }

    @Test("Semantic fingerprint canonicalizes fixed-point decimal spelling")
    func semanticAmountEquivalence() throws {
        let context = try LedgerTestContext.make()
        let entry = try entryForFingerprint(context: context)
        var records = try semanticPairRecords(entry)
        set(&records[1], "source_amount", "10.0")
        set(&records[1], "source_converted_cny", "10.00")
        set(&records[2], "source_amount", "10.00")
        set(&records[2], "source_converted_cny", "10.0")
        let preview = try semanticPreview(records, context: context)
        #expect(preview.rows[1].duplicateReasons == [.fileFingerprint])

        let firstOnly = try semanticPreview([records[0], records[1]], context: context)
        let fingerprint = try #require(firstOnly.validEntries.first?.importFingerprint)
        let existing = try LedgerCSV.preview(
            data: encodedCSV([records[0], records[2]]),
            containers: [context.source, context.target], categories: [], tags: [], rules: [],
            existingFingerprints: [fingerprint]
        )
        #expect(existing.rows[0].duplicateReasons == [.existingFingerprint])
    }

    @Test("Semantic fingerprint canonicalizes formula protection")
    func semanticFormulaProtectionEquivalence() throws {
        let context = try LedgerTestContext.make()
        let entry = try entryForFingerprint(context: context, description: "=Synthetic Formula Text")
        var records = try semanticPairRecords(entry)
        set(&records[2], "description", "=Synthetic Formula Text")
        let preview = try semanticPreview(records, context: context)
        #expect(preview.rows[0].entry?.description == preview.rows[1].entry?.description)
        #expect(preview.rows[1].duplicateReasons == [.fileFingerprint])
    }

    @Test("Resolved Category ID and Tag set order define semantic identity")
    func semanticClassificationEquivalence() throws {
        let context = try LedgerTestContext.make()
        let category = Category(id: UUID(), parentID: nil, name: "Synthetic Category")
        let alpha = Tag(id: UUID(), name: "Synthetic Alpha")
        let beta = Tag(id: UUID(), name: "Synthetic Beta")
        let entry = try entryForFingerprint(context: context, category: category, tags: [alpha, beta])
        var records = try semanticPairRecords(entry)
        set(&records[2], "category", " synthetic   category ")
        let reversedNames = [" synthetic  beta ", "SYNTHETIC ALPHA"]
        set(&records[2], "tags", String(decoding: try JSONEncoder().encode(reversedNames), as: UTF8.self))
        let preview = try semanticPreview(
            records,
            context: context,
            categories: [category],
            tags: [alpha, beta]
        )
        #expect(Set(preview.rows[1].entry?.tags.map(\.id) ?? []) == Set([alpha.id, beta.id]))
        #expect(preview.rows[1].duplicateReasons == [.fileFingerprint])
    }

    @Test("Business-semantic changes do not collide")
    func semanticDifferencesRemainDistinct() throws {
        let context = try LedgerTestContext.make()
        let categoryA = Category(id: UUID(), parentID: nil, name: "Synthetic Category A")
        let categoryB = Category(id: UUID(), parentID: nil, name: "Synthetic Category B")
        let entry = try entryForFingerprint(context: context, currency: .usd, category: categoryA)
        let mutations: [(inout [String]) -> Void] = [
            { row in self.set(&row, "source_amount", "11.00"); self.set(&row, "source_converted_cny", "77.00") },
            { row in self.set(&row, "civil_date", "2026-08-12") },
            { row in self.set(&row, "source_container_id", context.target.id.uuidString) },
            { row in self.set(&row, "kind", TransactionKind.income.rawValue) },
            { row in self.set(&row, "source_fx_rate", "8.00"); self.set(&row, "source_converted_cny", "80.00") },
            { row in self.set(&row, "category", categoryB.name) }
        ]
        for mutate in mutations {
            var records = try semanticPairRecords(entry)
            mutate(&records[2])
            let preview = try semanticPreview(
                records,
                context: context,
                categories: [categoryA, categoryB]
            )
            #expect(preview.errorCount == 0)
            #expect(preview.rows[1].duplicateReasons.isEmpty)
        }
    }

    @Test("Malformed rows, locale decimals, invalid currency, and FX are rejected", arguments: [
        "not,csv\n", "1,23", "USD-without-fx"
    ])
    func invalidInput(_ variant: String) throws {
        let context = try LedgerTestContext.make()
        if variant == "not,csv\n" {
            #expect(throws: LedgerCSVError.invalidHeader) { _ = try LedgerCSV.preview(data: Data(variant.utf8), containers: [context.source], categories: [], tags: [], rules: [], existingFingerprints: []) }
            return
        }
        var records = try LedgerCSV.parseRecords(
            String(decoding: LedgerCSV.export([try context.entry(kind: .income)]), as: UTF8.self)
        )
        let sourceCurrency = try #require(records[0].firstIndex(of: "source_currency"))
        let sourceAmount = try #require(records[0].firstIndex(of: "source_amount"))
        let sourceRate = try #require(records[0].firstIndex(of: "source_fx_rate"))
        if variant == "1,23" {
            records[1][sourceAmount] = "1,23"
        } else {
            records[1][sourceCurrency] = "USD"
            records[1][sourceRate] = "0"
        }
        let text = records.map { record in
            record.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
        let preview = try LedgerCSV.preview(data: Data(text.utf8), containers: [context.source], categories: [], tags: [], rules: [], existingFingerprints: [])
        #expect(preview.errorCount == 1)
        #expect(!preview.canImport)
    }

    @Test("Atomic import derives canonical fingerprints and rolls back a semantic duplicate batch")
    func atomicImportRollback() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("aureus.sqlite"))
        let context = try LedgerTestContext.make(); try await store.createWealthContainer(context.source)
        let first = try entryForFingerprint(context: context)
        let second = try semanticCopy(first, id: UUID(), importFingerprint: "caller-stale-fingerprint")
        await #expect(throws: LedgerPersistenceError.duplicateFingerprint) {
            try await store.importLedgerEntries([first, second], batchID: UUID(), importedAt: context.instant)
        }
        #expect(try await store.ledgerTransactionCount() == 0)
    }

    @Test("Preview-confirm race reports typed ID conflict and rolls back the whole batch")
    func previewConfirmRace() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("aureus.sqlite"))
        let context = try LedgerTestContext.make(); try await store.createWealthContainer(context.source)
        let racing = try context.entry(kind: .income)
        let other = try context.entry(kind: .expense)
        let preview = try LedgerCSV.preview(
            data: LedgerCSV.export([racing, other]), containers: [context.source],
            categories: [], tags: [], rules: [], existingFingerprints: []
        )
        #expect(preview.canImport)
        try await store.createLedgerEntry(racing)
        await #expect(throws: LedgerPersistenceError.duplicateTransactionID) {
            try await store.importLedgerEntries(preview.validEntries, batchID: UUID(), importedAt: context.instant)
        }
        #expect(try await store.ledgerTransactionCount() == 1)
        #expect(try await store.fetchLedgerEntries().map(\.id) == [racing.id])
    }

    @Test("Preview-confirm semantic race reports typed fingerprint conflict and rolls back")
    func semanticPreviewConfirmRace() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("aureus.sqlite"))
        let context = try LedgerTestContext.make(); try await store.createWealthContainer(context.source)
        let racing = try entryForFingerprint(context: context)
        let other = try context.entry(kind: .income, description: "Synthetic Other Batch Row")
        let preview = try LedgerCSV.preview(
            data: LedgerCSV.export([racing, other]), containers: [context.source],
            categories: [], tags: [], rules: [], existingFingerprints: []
        )
        #expect(preview.canImport)
        let intervening = try semanticCopy(racing, id: UUID())
        try await store.createLedgerEntry(intervening)
        #expect(try await store.fetchLedgerEntries().first?.importFingerprint == nil)
        await #expect(throws: LedgerPersistenceError.duplicateFingerprint) {
            try await store.importLedgerEntries(preview.validEntries, batchID: UUID(), importedAt: context.instant)
        }
        #expect(try await store.ledgerTransactionCount() == 1)
        #expect(try await store.fetchLedgerEntries().map(\.id) == [intervening.id])
    }

    @Test("Preview includes manual entries whose persisted import fingerprint is nil")
    func manualEntryParticipatesInPreviewDeduplication() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("aureus.sqlite"))
        let context = try LedgerTestContext.make(); try await store.createWealthContainer(context.source)
        let manual = try entryForFingerprint(context: context)
        try await store.createLedgerEntry(manual)
        let identities = try await store.existingImportIdentities()
        #expect(identities.transactionIDs == Set([manual.id]))
        #expect(identities.fingerprints == Set([try LedgerCSV.semanticFingerprint(for: manual)]))

        let candidate = try semanticCopy(manual, id: UUID())
        let preview = try LedgerCSV.preview(
            data: LedgerCSV.export([candidate]),
            containers: [context.source], categories: [], tags: [], rules: [],
            existingFingerprints: identities.fingerprints,
            existingTransactionIDs: identities.transactionIDs
        )
        #expect(preview.rows.first?.duplicateReasons == [.existingFingerprint])
        #expect(!preview.canImport)
        #expect(try await store.fetchLedgerEntries().first?.importFingerprint == nil)
    }

    @Test("An edited transaction with a cleared fingerprint still participates in Preview deduplication")
    func editedEntryParticipatesInPreviewDeduplication() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("aureus.sqlite"))
        let context = try LedgerTestContext.make(); try await store.createWealthContainer(context.source)
        let imported = try entryForFingerprint(context: context, description: "Synthetic Before Edit")
        try await store.importLedgerEntries([imported], batchID: UUID(), importedAt: context.instant)
        #expect(try await store.fetchLedgerEntries().first?.importFingerprint != nil)

        let editedBase = try entryForFingerprint(context: context, description: "Synthetic After Edit")
        let edited = try semanticCopy(editedBase, id: imported.id)
        try await store.updateLedgerEntry(edited)
        #expect(try await store.fetchLedgerEntries().first?.importFingerprint == nil)

        let identities = try await store.existingImportIdentities()
        let candidate = try semanticCopy(edited, id: UUID())
        let preview = try LedgerCSV.preview(
            data: LedgerCSV.export([candidate]), containers: [context.source],
            categories: [], tags: [], rules: [],
            existingFingerprints: identities.fingerprints,
            existingTransactionIDs: identities.transactionIDs
        )
        #expect(preview.rows.first?.duplicateReasons == [.existingFingerprint])
        #expect(!preview.canImport)
    }

    @Test("Existing semantic duplicate groups are preserved and block another import")
    func existingDuplicateGroupIsPreserved() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("aureus.sqlite"))
        let context = try LedgerTestContext.make(); try await store.createWealthContainer(context.source)
        let first = try entryForFingerprint(context: context)
        let second = try semanticCopy(first, id: UUID())
        try await store.createLedgerEntry(first)
        try await store.createLedgerEntry(second)

        let identities = try await store.existingImportIdentities()
        #expect(identities.transactionIDs == Set([first.id, second.id]))
        #expect(identities.fingerprints.count == 1)
        let incoming = try semanticCopy(first, id: UUID(), importFingerprint: "untrusted-caller-value")
        await #expect(throws: LedgerPersistenceError.duplicateFingerprint) {
            try await store.importLedgerEntries([incoming], batchID: UUID(), importedAt: context.instant)
        }
        #expect(try await store.ledgerTransactionCount() == 2)
        #expect(Set(try await store.fetchLedgerEntries().map(\.id)) == Set([first.id, second.id]))
    }

    @Test("Import persistence replaces a stale caller fingerprint with the canonical value")
    func persistenceCanonicalizesIncomingFingerprint() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("aureus.sqlite"))
        let context = try LedgerTestContext.make(); try await store.createWealthContainer(context.source)
        let base = try entryForFingerprint(context: context, description: "Synthetic Canonical Import")
        let incoming = try semanticCopy(base, id: base.id, importFingerprint: "stale-caller-fingerprint")
        let expected = try LedgerCSV.semanticFingerprint(for: incoming)
        try await store.importLedgerEntries([incoming], batchID: UUID(), importedAt: context.instant)
        let stored = try #require(try await store.fetchLedgerEntries().first)
        #expect(stored.importFingerprint == expected)
        #expect(stored.importFingerprint != "stale-caller-fingerprint")
    }

    private func entryForFingerprint(
        context: LedgerTestContext,
        description: String = "Synthetic Semantic Expense",
        currency: CurrencyCode = .cny,
        category: Aureus.Category? = nil,
        tags: [Aureus.Tag] = []
    ) throws -> LedgerEntry {
        try LedgerEntry(
            kind: .expense,
            civilDate: context.date,
            recordedAt: context.instant,
            description: description,
            payee: "Synthetic Payee",
            category: category,
            tags: tags,
            postings: [try LedgerPosting(
                role: .primary,
                containerID: context.source.id,
                valuation: context.valuation("10.00", currency: currency)
            )],
            note: "Synthetic semantic fingerprint fixture"
        )
    }

    private func semanticPairRecords(_ entry: LedgerEntry) throws -> [[String]] {
        let exported = try LedgerCSV.parseRecords(String(decoding: LedgerCSV.export([entry]), as: UTF8.self))
        var second = exported[1]
        set(&second, "transaction_id", UUID().uuidString)
        return [exported[0], exported[1], second]
    }

    private func semanticCopy(
        _ entry: LedgerEntry,
        id: UUID,
        importFingerprint: String? = nil
    ) throws -> LedgerEntry {
        let postings = try entry.postings.map {
            try LedgerPosting(role: $0.role, containerID: $0.containerID, valuation: $0.valuation)
        }
        return try LedgerEntry(
            id: id,
            kind: entry.kind,
            civilDate: entry.civilDate,
            recordedAt: entry.recordedAt,
            description: entry.description,
            payee: entry.payee,
            category: entry.category,
            tags: entry.tags,
            postings: postings,
            note: entry.note,
            importFingerprint: importFingerprint
        )
    }

    private func semanticPreview(
        _ records: [[String]],
        context: LedgerTestContext,
        categories: [Aureus.Category] = [],
        tags: [Aureus.Tag] = []
    ) throws -> LedgerImportPreview {
        try LedgerCSV.preview(
            data: encodedCSV(records),
            containers: [context.source, context.target],
            categories: categories,
            tags: tags,
            rules: [],
            existingFingerprints: []
        )
    }

    private func set(_ row: inout [String], _ column: String, _ value: String) {
        row[LedgerCSV.header.firstIndex(of: column)!] = value
    }

    private func encodedCSV(_ records: [[String]]) -> Data {
        let text = records.map { record in
            record.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
        return Data(text.utf8)
    }
}
