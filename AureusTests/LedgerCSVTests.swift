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
        #expect(preview.rows.first?.appliedRuleID == rule.id)
        #expect(preview.validEntries.first?.category == category)
        #expect(preview.validEntries.first?.tags == [tag])
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

    @Test("Atomic import rolls back every row on duplicate constraint")
    func atomicImportRollback() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try WealthStore(databaseURL: root.appendingPathComponent("aureus.sqlite"))
        let context = try LedgerTestContext.make(); try await store.createWealthContainer(context.source)
        let fingerprint = "synthetic-duplicate-fingerprint"
        let firstBase = try context.entry(kind: .income)
        let secondBase = try context.entry(kind: .expense)
        func copy(_ entry: LedgerEntry) throws -> LedgerEntry { try LedgerEntry(id: entry.id, kind: entry.kind, civilDate: entry.civilDate, recordedAt: entry.recordedAt, description: entry.description, postings: entry.postings, importFingerprint: fingerprint) }
        await #expect(throws: LedgerPersistenceError.duplicateImport) {
            try await store.importLedgerEntries([try copy(firstBase), try copy(secondBase)], batchID: UUID(), importedAt: context.instant)
        }
        #expect(try await store.ledgerTransactionCount() == 0)
    }
}
