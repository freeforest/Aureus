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

    @Test("Canonical history projection rejects invalid financial state", arguments: [
        "cnyRate", "cnySource", "cnyManual", "usdManual", "usdSource",
        "negativeZeroSecurityPrice", "invalidInsuranceStart", "invalidInsuranceMaturity"
    ])
    func historyProjectionRejectsInvalidFinancialState(_ fault: String) throws {
        let records = try SyntheticWealthSeeder.records()
        let index = fault.hasPrefix("usd") ? 1 : fault == "negativeZeroSecurityPrice" ? 2
            : fault.hasPrefix("invalidInsurance") ? 4 : 0
        let baseline = WealthCorrectionProjection(records[index])
        try baseline.validate()
        let decoded = try wealthProjectionWithJSONChange(baseline) { object in
            var valuation = try #require(object["valuation"] as? [String: Any])
            var rate = try #require(valuation["rate"] as? [String: Any])
            switch fault {
            case "cnyRate":
                rate["coefficient"] = 20_000_000_000 as Int64
                var converted = try #require(valuation["convertedCNY"] as? [String: Any])
                converted["minorUnits"] = records[index].valuation.original.minorUnits * 2
                valuation["convertedCNY"] = converted
            case "cnySource": valuation["providerIdentifier"] = "manual.synthetic"
            case "cnyManual", "usdManual": valuation["isManualOverride"] = fault == "cnyManual"
            case "usdSource": valuation["providerIdentifier"] = "synthetic.provider"
            case "negativeZeroSecurityPrice":
                var details = try #require(object["details"] as? [String: Any])
                var security = try #require(details["security"] as? [String: Any])
                var quantity = try #require(security["quantity"] as? [String: Any])
                var price = try #require(security["manualPrice"] as? [String: Any])
                quantity["coefficient"] = 0
                price["coefficient"] = -1
                security["quantity"] = quantity; security["manualPrice"] = price
                details["security"] = security; object["details"] = details
                var original = try #require(valuation["original"] as? [String: Any])
                var converted = try #require(valuation["convertedCNY"] as? [String: Any])
                original["minorUnits"] = 0; converted["minorUnits"] = 0
                valuation["original"] = original; valuation["convertedCNY"] = converted
            case "invalidInsuranceStart", "invalidInsuranceMaturity":
                var details = try #require(object["details"] as? [String: Any])
                var insurance = try #require(details["insurance"] as? [String: Any])
                let dateKey = fault == "invalidInsuranceStart" ? "startDate" : "maturityDate"
                var date = try #require(insurance[dateKey] as? [String: Any])
                date["month"] = 2; date["day"] = 31
                insurance[dateKey] = date; details["insurance"] = insurance
                object["details"] = details
            default: Issue.record("Unexpected synthetic fault")
            }
            valuation["rate"] = rate; object["valuation"] = valuation
        }
        #expect(decoded.id == baseline.id)
        switch fault {
        case "cnyRate": #expect(decoded.valuation.rate.coefficient == 20_000_000_000)
        case "cnySource", "usdSource": #expect(decoded.valuation.providerIdentifier != baseline.valuation.providerIdentifier)
        case "cnyManual", "usdManual": #expect(decoded.valuation.isManualOverride != baseline.valuation.isManualOverride)
        case "negativeZeroSecurityPrice":
            if case let .security(_, _, quantity, price) = decoded.details {
                #expect(quantity.coefficient == 0 && price.coefficient == -1)
            } else { Issue.record("Security JSON did not reach security projection") }
        case "invalidInsuranceStart", "invalidInsuranceMaturity":
            if case let .insurance(_, _, _, _, _, _, start, maturity) = decoded.details {
                if fault == "invalidInsuranceStart" { #expect(start.description == "2024-02-31") }
                else { #expect(maturity?.description == "2034-02-31") }
            } else { Issue.record("Insurance JSON did not reach insurance projection") }
        default: break
        }
        #expect(throws: (any Error).self) { try decoded.validate() }
    }

    @Test("Canonical corrupt financial payload reaches row decoder and shared validator")
    func historyPayloadValidatorRejectsFinancialCorruption() async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let store = try f.open(), old = try SyntheticWealthSeeder.records()[0]
        try await store.createWealthContainer(old)
        let token = try await store.readWealthEditContext(id: old.id)
        _ = try wealthApplied(await store.correctWealthContainer(f.request(f.changeValue(old), token: token.token)))
        let raw = try f.read { try #require(try String.fetchOne($0,
            sql: "SELECT payload FROM wealth_correction_history LIMIT 1")) }
        let corrupted = try wealthCanonicalJSONChange(raw) { object in
            var before = try #require(object["before"] as? [String: Any])
            var valuation = try #require(before["valuation"] as? [String: Any])
            var rate = try #require(valuation["rate"] as? [String: Any])
            var converted = try #require(valuation["convertedCNY"] as? [String: Any])
            rate["coefficient"] = 20_000_000_000 as Int64
            converted["minorUnits"] = old.valuation.original.minorUnits * 2
            valuation["rate"] = rate; valuation["convertedCNY"] = converted
            before["valuation"] = valuation; object["before"] = before
        }
        let decodedPayload = try JSONDecoder().decode(WealthHistoryPayload.self, from: Data(corrupted.utf8))
        #expect(decodedPayload.before.valuation.rate.coefficient == 20_000_000_000)
        try f.write("DROP TRIGGER wealth_correction_history_no_update")
        try f.write("UPDATE wealth_correction_history SET payload = ?", [corrupted])
        try f.write(WealthCorrectionSQL.declarations[2].1)
        #expect(try f.read { try String.fetchOne($0,
            sql: "SELECT name FROM sqlite_master WHERE name = 'wealth_correction_history_no_update'") }
            == "wealth_correction_history_no_update")
        #expect(throws: (any Error).self) {
            _ = try f.read { db in
                let row = try #require(try Row.fetchOne(db, sql: "SELECT * FROM wealth_correction_history LIMIT 1"))
                return try WealthCorrectionSQL.decode(row)
            }
        }
        #expect(throws: (any Error).self) {
            _ = try f.read { try WealthCorrectionSQL.validateSchema($0) }
        }
    }

    @Test("History UUID, target, FX and operation constraints reject exact faults", arguments: [
        "invalidUUID", "targetMismatch", "fxArithmetic", "fxDirection", "duplicateOperation"
    ])
    func historyIdentityAndOperationConstraints(_ fault: String) async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let store = try f.open(), old = try SyntheticWealthSeeder.records()[1]
        try await store.createWealthContainer(old)
        let token = try await store.readWealthEditContext(id: old.id)
        _ = try wealthApplied(await store.correctWealthContainer(f.request(f.changeValue(old), token: token.token)))
        switch fault {
        case "invalidUUID":
            try f.write("DROP TRIGGER wealth_correction_history_no_update")
            #expect(throws: DatabaseError.self) {
                try f.write("UPDATE wealth_correction_history SET wealth_container_id='invalid-uuid'")
            }
            #expect(try f.count("wealth_correction_history") == 1)
            try f.write(WealthCorrectionSQL.declarations[2].1)
        case "duplicateOperation":
            let secondID = UUID().uuidString
            do {
                try f.write("""
                    INSERT INTO wealth_correction_history(history_id,operation_id,wealth_container_id,
                        kind,occurred_at_ms,reason,request_digest,post_state_digest,payload)
                    SELECT ?,operation_id,wealth_container_id,kind,occurred_at_ms,reason,
                        request_digest,post_state_digest,payload FROM wealth_correction_history
                    """, [secondID])
                Issue.record("Expected operation_id UNIQUE rejection")
            } catch let error as DatabaseError {
                #expect(error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE)
            }
            #expect(try f.count("wealth_correction_history") == 1)
        case "targetMismatch":
            try f.write("DROP TRIGGER wealth_correction_history_no_update")
            try f.write("UPDATE wealth_correction_history SET wealth_container_id=?", [UUID().uuidString])
            try f.write(WealthCorrectionSQL.declarations[2].1)
            #expect(throws: (any Error).self) {
                _ = try f.read { try WealthCorrectionSQL.validateSchema($0) }
            }
        case "fxArithmetic", "fxDirection":
            let raw = try f.read { try #require(try String.fetchOne($0,
                sql: "SELECT payload FROM wealth_correction_history LIMIT 1")) }
            let corrupted = try wealthCanonicalJSONChange(raw) { object in
                var before = try #require(object["before"] as? [String: Any])
                var valuation = try #require(before["valuation"] as? [String: Any])
                if fault == "fxArithmetic" {
                    var converted = try #require(valuation["convertedCNY"] as? [String: Any])
                    converted["minorUnits"] = old.valuation.convertedCNY.minorUnits + 1
                    valuation["convertedCNY"] = converted
                } else {
                    var rate = try #require(valuation["rate"] as? [String: Any])
                    rate["sourceCurrency"] = "CNY"
                    valuation["rate"] = rate
                }
                before["valuation"] = valuation; object["before"] = before
            }
            let decoded = try JSONDecoder().decode(WealthHistoryPayload.self, from: Data(corrupted.utf8))
            #expect(decoded.before.valuation != old.valuation)
            try f.write("DROP TRIGGER wealth_correction_history_no_update")
            try f.write("UPDATE wealth_correction_history SET payload=?", [corrupted])
            try f.write(WealthCorrectionSQL.declarations[2].1)
            #expect(throws: (any Error).self) {
                _ = try f.read { try WealthCorrectionSQL.validateSchema($0) }
            }
        default: Issue.record("Unexpected synthetic fault")
        }
    }

    @Test("Actual v8 Ledger history survives schema9 safety migration and reopen")
    func realV8LedgerHistoryMigrates() async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let context = try LedgerTestContext.make()
        let q = try DatabaseQueueFactory.open(at: f.database)
        try DatabaseMigrations.permanentMigrator().migrate(q, upTo: DatabaseMigrations.permanentV8)
        let original = try LedgerEntry(kind: .income, civilDate: context.date,
            recordedAt: context.instant, description: "Synthetic v8 USD",
            postings: [LedgerPosting(role: .primary, containerID: context.target.id,
                valuation: context.valuation("100.00", currency: .usd))])
        let updated = try LedgerEntry(id: original.id, kind: original.kind,
            civilDate: original.civilDate, recordedAt: original.recordedAt,
            description: "Synthetic v8 corrected USD", postings: original.postings)
        let operationID = UUID()
        let history = try await q.write { db -> LedgerCorrectionHistory in
            try AssetContainerPersistenceRow(container: context.target.container).insert(db)
            try WealthRecordPersistenceRow(record: context.target).insert(db)
            let now = context.instant.millisecondsSince1970
            try LedgerTransactionRow(id: original.id.uuidString, kind: original.kind.rawValue,
                civilDate: original.civilDate.description, recordedAtMS: now,
                description: original.description, payee: nil, categoryID: nil, note: nil,
                importFingerprint: nil, createdAtMS: now, updatedAtMS: now).insert(db)
            try LedgerPostingRow(transactionID: original.id, posting: original.postings[0]).insert(db)
            try db.execute(sql: "UPDATE ledger_transactions SET description=? WHERE id=?",
                arguments: [updated.description, original.id.uuidString])
            return try LedgerCorrectionSQL.append(db, operationID: operationID, kind: "correction",
                occurredAt: context.instant, reason: "Synthetic v8 correction",
                requestDigest: String(repeating: "a", count: 64),
                postState: LedgerCorrectionSQL.stateDigest(db, id: original.id),
                payload: LedgerHistoryPayload(version: 1, before: .init(original),
                    after: .init(updated), deletion: nil))
        }
        #expect(try PermanentDatabaseValidation.inspect(q, expectedSchemaVersion: 8,
            requireCurrentApplicationSchema: false).schemaVersion == 8)
        #expect(try await q.read { db in try LedgerCorrectionSQL.decode(
            #require(try Row.fetchOne(db, sql: "SELECT * FROM ledger_correction_history"))) } == history)
        try q.close()
        let store = try f.open()
        #expect(try await store.schemaVersion() == 9)
        #expect(try await store.fetchLedgerEntries().contains(updated))
        #expect(try await store.ledgerCorrectionHistory(id: original.id) == [history])
        #expect(try f.count("wealth_correction_history") == 0)
        let safety = try #require(PermanentBackupService.inventory(in: f.backups).validGenerations.first)
        #expect(safety.manifest.schemaVersion == 8)
        let safetyDB = safety.directoryURL.appendingPathComponent("aureus.sqlite")
        #expect(try PermanentDatabaseValidation.inspectFile(safetyDB, expectedSchemaVersion: 8,
            requireCurrentApplicationSchema: false).schemaVersion == 8)
        let safetyQueue = try DatabaseQueueFactory.open(at: safetyDB)
        #expect(try await safetyQueue.read { db in try LedgerCorrectionSQL.decode(
            #require(try Row.fetchOne(db, sql: "SELECT * FROM ledger_correction_history"))) } == history)
        let safetyFacts = try await safetyQueue.read { db -> [String] in
            let header = try #require(try Row.fetchOne(db,
                sql: "SELECT id,description FROM ledger_transactions WHERE id=?",
                arguments: [original.id.uuidString]))
            let posting = try #require(try Row.fetchOne(db,
                sql: "SELECT id,container_id,original_minor,original_currency_code,fx_coefficient,converted_cny_minor FROM ledger_postings WHERE transaction_id=?",
                arguments: [original.id.uuidString]))
            return [header["id"] as String, header["description"] as String,
                posting["id"] as String, posting["container_id"] as String,
                String(posting["original_minor"] as Int64), posting["original_currency_code"] as String,
                String(posting["fx_coefficient"] as Int64),
                String(posting["converted_cny_minor"] as Int64)]
        }
        let originalPosting = original.postings[0]
        #expect(safetyFacts == [original.id.uuidString, updated.description,
            originalPosting.id.uuidString, context.target.id.uuidString,
            String(originalPosting.valuation.original.minorUnits), "USD",
            String(originalPosting.valuation.rate.coefficient),
            String(originalPosting.valuation.convertedCNY.minorUnits)])
        let safetyPayload = try await safetyQueue.read { db in
            try #require(try String.fetchOne(db,
                sql: "SELECT payload FROM ledger_correction_history WHERE operation_id=?",
                arguments: [operationID.uuidString]))
        }
        let livePayload = try f.read { db in
            try #require(try String.fetchOne(db,
                sql: "SELECT payload FROM ledger_correction_history WHERE operation_id=?",
                arguments: [operationID.uuidString]))
        }
        #expect(safetyPayload == livePayload)
        #expect(try LedgerCorrectionEncoding.data(history.payload) == Data(safetyPayload.utf8))
        #expect(try await safetyQueue.read { try Int.fetchOne($0,
            sql: "SELECT COUNT(*) FROM wealth_records") } == 1)
        try safetyQueue.close()
        try await store.migrate()
        let reopened = try f.open()
        #expect(try await reopened.ledgerCorrectionHistory(id: original.id) == [history])
        #expect(try f.count("wealth_correction_history") == 0)
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

    @Test("Older internal or external generation never merges later Wealth operation", arguments: [false, true])
    func olderGenerationDoesNotMergeLaterOperation(_ external: Bool) async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let store = try f.open(), original = try SyntheticWealthSeeder.records()[0]
        try await store.createWealthContainer(original)
        let firstToken = try await store.readWealthEditContext(id: original.id)
        let firstValue = try f.changeValue(original)
        let h1 = try wealthApplied(await store.correctWealthContainer(
            f.request(firstValue, token: firstToken.token)))
        let g1 = try await f.backup(store)
        let candidate = external ? try f.export(g1) : g1.directoryURL
        let sourceDB = candidate.appendingPathComponent("aureus.sqlite")
        let sourceDigest = try PermanentBackupService.streamingDigest(of: sourceDB)
        let secondToken = try await store.readWealthEditContext(id: original.id)
        let secondValue = try f.changeValue(firstValue)
        let secondRequest = f.request(secondValue, token: secondToken.token)
        let h2 = try wealthApplied(await store.correctWealthContainer(secondRequest))
        #expect(try await store.fetchWealthContainer(id: original.id) == secondValue)
        #expect(try await store.wealthCorrectionHistory(id: original.id) == [h1, h2])
        let safetyIdentity: String
        if external {
            let result = try await store.restoreExternalPermanentBackup(candidate,
                configuration: .init(internalBackupRootURL: f.backups,
                    permanentDatabaseURL: f.database, marketCacheDatabaseURL: f.cache,
                    additionalProtectedSourceRoots: []),
                appVersion: "synthetic", createdAt: f.instant)
            safetyIdentity = result.safetyGenerationIdentity
        } else {
            safetyIdentity = try await f.restore(store, g1).safetyGenerationIdentity
        }
        #expect(try await store.fetchWealthContainer(id: original.id) == firstValue)
        #expect(try await store.wealthCorrectionHistory(id: original.id) == [h1])
        #expect(try PermanentBackupService.streamingDigest(of: sourceDB) == sourceDigest)
        let safetyURL = f.backups.appendingPathComponent(safetyIdentity, isDirectory: true)
        let safety = try PermanentBackupService.validateGeneration(safetyURL, in: f.backups)
        let safetyQueue = try DatabaseQueueFactory.open(at: safety.directoryURL.appendingPathComponent("aureus.sqlite"))
        let safetyOperationIDs = try await safetyQueue.read { db in
            try String.fetchAll(db, sql: "SELECT operation_id FROM wealth_correction_history ORDER BY sequence")
        }
        #expect(safetyOperationIDs.contains(secondRequest.operationID.uuidString))
        try safetyQueue.close()
        await #expect(throws: WealthCorrectionError.staleDraft) {
            _ = try await store.correctWealthContainer(secondRequest)
        }
        #expect(try await store.wealthCorrectionHistory(id: original.id) == [h1])
        let fresh = try await store.readWealthEditContext(id: original.id)
        let third = try wealthApplied(await store.correctWealthContainer(
            f.request(secondValue, token: fresh.token)))
        #expect(third.operationID != h2.operationID)
        #expect(try await store.wealthCorrectionHistory(id: original.id) == [h1, third])
    }

    @Test("Wealth correction retains Ledger, Portfolio and Evidence relationship identities")
    func correctionRetainsExternalRelations() async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let store = try f.open(evidence: true), original = try SyntheticWealthSeeder.records()[2]
        try await store.createWealthContainer(original)
        let context = try LedgerTestContext.make()
        let ledger = try LedgerEntry(kind: .income, civilDate: context.date,
            recordedAt: context.instant, description: "Synthetic linked USD",
            postings: [LedgerPosting(role: .primary, containerID: original.id,
                valuation: context.valuation("10.00", currency: .usd))])
        try await store.createLedgerEntry(ledger)
        let portfolio = try PortfolioRecord(name: "Synthetic linked portfolio",
            createdAt: f.instant, updatedAt: f.instant, sortOrder: 0)
        try await store.createPortfolio(portfolio)
        let security = try PortfolioSecurityLink(portfolioID: portfolio.id,
            wealthContainerID: original.id, symbol: "SYNX", rawMIC: "XSYN",
            currency: .usd, assetKind: .stock, sortOrder: 0)
        try await store.linkPortfolioSecurity(security)
        let imported = try await store.importEvidence(source: f.source, operationID: UUID(),
            target: .container(original.id))
        #expect(imported.availability == .available)
        let linkIDs = try f.read { db in
            try String.fetchAll(db, sql: "SELECT link_id FROM evidence_container_links WHERE container_id=?",
                arguments: [original.id.uuidString])
        }
        let edit = try await store.readWealthEditContext(id: original.id)
        let corrected = try f.changeValue(original)
        let history = try wealthApplied(await store.correctWealthContainer(
            f.request(corrected, token: edit.token)))
        #expect(history.payload.before == WealthCorrectionProjection(original))
        #expect(history.payload.after == WealthCorrectionProjection(corrected))
        #expect(try await store.fetchLedgerEntries() == [ledger])
        #expect(try await store.fetchPortfolioSecurityLinks(portfolioID: portfolio.id) == [security])
        #expect(try f.read { db in
            try String.fetchAll(db, sql: "SELECT link_id FROM evidence_container_links WHERE container_id=?",
                arguments: [original.id.uuidString]) } == linkIDs)
        #expect(try f.count("evidence_documents") == 1)
        #expect(try await store.resumeEvidence(operationID: imported.operation.id).availability == .available)
        #expect(try await store.wealthSummary() == WealthValuation.aggregate([corrected]))
    }

    @Test("Normal valuation rejects important identity and contract fields", arguments: [
        "quantity", "ticker", "currency", "insuranceContract"
    ])
    func valuationRejectsOutOfScopeFields(_ fault: String) async throws {
        let f = try WealthCorrectionFixture(); defer { f.remove() }
        let old = try SyntheticWealthSeeder.records()[fault == "insuranceContract" ? 4 : 2]
        let store = try f.open()
        try await store.createWealthContainer(old)
        let token = try await store.readWealthEditContext(id: old.id)
        let candidate: WealthContainer
        let intent: WealthFXIntent
        if fault == "insuranceContract" {
            guard case let .insurance(company, _, premium, frequency, coverage, current, start, maturity) = old.details else {
                throw WealthCorrectionError.invalidRequest
            }
            candidate = try WealthContainer(container: old.container,
                details: .insurance(company: company, productName: "Different synthetic contract",
                    premium: premium, paymentFrequency: frequency, coverage: coverage,
                    currentCashValue: current, startDate: start, maturityDate: maturity),
                valuation: old.valuation)
            intent = .preserve
        } else {
            guard case let .security(ticker, mic, quantity, price) = old.details else {
                throw WealthCorrectionError.invalidRequest
            }
            let newDetails: WealthRecordDetails = .security(
                ticker: fault == "ticker" ? "OTHER" : ticker, mic: mic,
                quantity: fault == "quantity" ? AssetQuantity(coefficient: quantity.coefficient + 100_000_000) : quantity,
                manualPrice: fault == "currency"
                    ? try MarketPrice(coefficient: price.coefficient, quoteCurrency: .cny) : price)
            let parent = AssetContainer(id: old.id, accountID: old.container.accountID,
                name: old.container.name, kind: old.container.kind,
                institution: old.container.institution,
                primaryCurrency: fault == "currency" ? .cny : .usd,
                notes: old.container.notes, createdDate: old.container.createdDate,
                updatedDate: old.container.updatedDate)
            let fx = try FXValuation(original: newDetails.currentValue(),
                rate: fault == "currency" ? .cnyIdentity : old.valuation.rate,
                referenceDate: old.valuation.referenceDate,
                fetchedAt: fault == "currency" ? f.instant : old.valuation.fetchedAt,
                providerIdentifier: fault == "currency" ? "identity" : old.valuation.providerIdentifier,
                isManualOverride: fault == "currency" ? false : old.valuation.isManualOverride,
                isStale: old.valuation.isStale)
            candidate = try WealthContainer(container: parent, details: newDetails, valuation: fx)
            intent = fault == "currency" ? .newInput : .preserve
        }
        let beforeDigest = try f.digest(old.id)
        await #expect(throws: WealthCorrectionError.invalidRequest) {
            _ = try await store.recordCurrentValuation(.init(candidate: candidate,
                expected: token.token, occurredAt: f.instant, fxIntent: intent))
        }
        #expect(try f.digest(old.id) == beforeDigest)
        #expect(try await store.fetchWealthContainer(id: old.id) == old)
        #expect(try await store.wealthCorrectionHistory(id: old.id).isEmpty)
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

private func wealthProjectionWithJSONChange(
    _ source: WealthCorrectionProjection,
    change: (inout [String: Any]) throws -> Void
) throws -> WealthCorrectionProjection {
    let sourceBytes = try WealthCorrectionEncoding.data(source)
    var object = try #require(JSONSerialization.jsonObject(with: sourceBytes) as? [String: Any])
    try change(&object)
    let changedBytes = try JSONSerialization.data(withJSONObject: object,
        options: [.sortedKeys, .withoutEscapingSlashes])
    let decoded = try JSONDecoder().decode(WealthCorrectionProjection.self, from: changedBytes)
    #expect(try WealthCorrectionEncoding.data(decoded) == changedBytes)
    return decoded
}

private func wealthCanonicalJSONChange(
    _ source: String,
    change: (inout [String: Any]) throws -> Void
) throws -> String {
    var object = try #require(JSONSerialization.jsonObject(with: Data(source.utf8)) as? [String: Any])
    try change(&object)
    let bytes = try JSONSerialization.data(withJSONObject: object,
        options: [.sortedKeys, .withoutEscapingSlashes])
    let decoded = try JSONDecoder().decode(WealthHistoryPayload.self, from: bytes)
    #expect(try WealthCorrectionEncoding.data(decoded) == bytes)
    return String(decoding: bytes, as: UTF8.self)
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
