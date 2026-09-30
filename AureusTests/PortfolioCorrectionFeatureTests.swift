import Foundation
import GRDB
import Testing
@testable import Aureus

@MainActor
@Suite("Portfolio Activity edit integration", .serialized)
struct PortfolioCorrectionFeatureTests {
    @Test("F1 exact typed drafts preserve four payloads, metadata and actual Ledger association",
          arguments: ["openingLot", "buy", "sell", "manualSplit"], ["CNY", "USD"])
    func draftRoundTrip(kind: String, currency: String) async throws {
        try await withPortfolioFeatureFixture(currency: currency) { f in
            let original = try await f.seed(kind: kind, precise: true)
            let model = f.model()
            await model.start(); await model.beginActivityEdit(id: original.id)
            #expect(model.activityEditState == .ready)
            #expect(try model.activityCandidate(at: f.later) == original)
            #expect(!model.needsActivityCorrectionReason && model.canSaveActivity)
            if kind == "manualSplit" { model.activityDraft.splitFrom += ".000" }
            else { model.activityDraft.quantity += "0" }
            // The precise quantity has eight decimals; appending a zero is numerically equal.
            await model.saveActivityEdit()
            #expect(model.activitySaveOutcome == "noChange")
            #expect(try await f.current(original.id) == original)
            #expect(try await f.store.portfolioActivityCorrectionHistory(id: original.id).isEmpty)
            #expect(try await f.store.fetchLedgerEntries().contains { $0.id == original.ledgerEntryID })
            let reopened = try WealthStore(databaseURL: f.database)
            #expect(try await reopened.readPortfolioActivityEditContext(id: original.id).activity == original)
            try await reopened.queue.close()
        }
    }

    @Test("F1 editor uses current context, not cached list; cancel does not write")
    func authoritativeContextAndCancel() async throws {
        try await withPortfolioFeatureFixture { f in
            let old = try await f.seed(kind: "buy")
            let model = f.model(); await model.start()
            let other = f.model(); await other.start(); await other.beginActivityEdit(id: old.id)
            other.activityDraft.unitPrice = "15"; other.activityCorrectionReason = "Synthetic newer fact"
            await other.saveActivityEdit()
            #expect(model.activities.contains(old))
            await model.beginActivityEdit(id: old.id)
            #expect(model.activityDraft.unitPrice == "15")
            let current = try await f.current(old.id)
            let rows = try await f.store.portfolioActivityCorrectionHistory(id: old.id)
            model.activityDraft.unitPrice = "20"; model.cancelActivityEdit()
            #expect(model.activityEditID == nil)
            #expect(try await f.current(old.id) == current)
            #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id) == rows)
        }
    }

    @Test("F1 opening note-only edits are minor and preserve nil on untouched drafts", arguments: ["CNY", "USD"])
    func openingNoteMinor(_ currency: String) async throws {
        try await withPortfolioFeatureFixture(currency: currency) { f in
            let original = try await f.seed(kind: "openingLot")
            let model = f.model(); await model.start(); await model.beginActivityEdit(id: original.id)
            #expect(try model.activityCandidate(at: f.later) == original)
            model.activityDraft.note = "Synthetic note only"
            #expect(!model.needsActivityCorrectionReason)
            await model.saveActivityEdit()
            #expect(model.activitySaveOutcome == "minorUpdate")
            let saved = try await f.current(original.id)
            #expect(PortfolioActivityDraft.fx(saved.payload) == PortfolioActivityDraft.fx(original.payload))
            #expect(try await f.store.portfolioActivityCorrectionHistory(id: original.id).isEmpty)
            if case let .openingLot(_, _, _, note) = saved.payload { #expect(note == "Synthetic note only") }
            else { Issue.record("Expected opening lot") }
        }
    }

    @Test("F2 four payload important changes commit through real Store with exact history",
          arguments: ["openingLot", "buy", "sell", "manualSplit"], ["CNY", "USD"])
    func importantEdits(kind: String, currency: String) async throws {
        try await withPortfolioFeatureFixture(currency: currency) { f in
            let old = try await f.seed(kind: kind)
            let model = f.model(); await model.start(); await model.beginActivityEdit(id: old.id)
            if kind == "openingLot" { model.activityDraft.totalCost = "25" }
            else if kind == "manualSplit" { model.activityDraft.splitTo = "4" }
            else { model.activityDraft.unitPrice = "15" }
            #expect(model.needsActivityCorrectionReason && !model.canSaveActivity)
            model.activityCorrectionReason = "  Synthetic important correction  "
            let candidate = try model.activityCandidate(at: f.later)
            await model.saveActivityEdit()
            #expect(model.activitySaveOutcome == "committed" && model.activityEditID == nil)
            let history = try await f.store.portfolioActivityCorrectionHistory(id: old.id)
            #expect(history.count == 1 && history.first?.reason == "Synthetic important correction")
            #expect(history.first?.payload.before == PortfolioCorrectionProjection(old, link: f.link))
            #expect(history.first?.payload.after == PortfolioCorrectionProjection(candidate, link: f.link))
            #expect(try await f.current(old.id) == candidate)
            #expect(candidate.id == old.id && candidate.portfolioID == old.portfolioID)
            #expect(candidate.ledgerEntryID == old.ledgerEntryID && candidate.recordedAt == old.recordedAt)
            #expect(candidate.exchangeTimeZoneIdentifier == old.exchangeTimeZoneIdentifier)
            let replay = try await f.store.portfolioReplay(portfolioID: f.portfolio.id)
            #expect(try replay.quantity(for: f.link.id).decimal == (kind == "sell" ? 9 : kind == "manualSplit" ? 20 : 11))
            if kind == "sell" { #expect(replay.realized.first?.originalPnL.minorUnits == 400) }
            if let prior = PortfolioActivityDraft.fx(old.payload), let fx = PortfolioActivityDraft.fx(candidate.payload) {
                #expect(fx.rate == prior.rate && fx.source == prior.source && fx.referenceDate == prior.referenceDate)
                #expect(fx.recordedAt == prior.recordedAt && fx.isManual == prior.isManual && fx.isStale == prior.isStale)
                #expect(fx.convertedCNY == (try prior.rate.convert(fx.original)))
            }
        }
    }

    @Test("F2 legal kind switches require explicit new financial fields", arguments: ["openingLot", "buy", "sell", "manualSplit"])
    func kindSwitch(_ kind: String) async throws {
        try await withPortfolioFeatureFixture(currency: "USD") { f in
            let old = try await f.seed(kind: kind)
            let model = f.model(); await model.start(); await model.beginActivityEdit(id: old.id)
            switch kind {
            case "openingLot":
                model.activityDraft.kind = .buy
                #expect(!model.canSaveActivity)
                model.activityDraft.unitPrice = "12"; model.activityDraft.fee = "1"
            case "buy": model.activityDraft.kind = .sell
            case "sell":
                model.activityDraft.kind = .manualSplit
                model.activityDraft.splitFrom = "2"; model.activityDraft.splitTo = "3"
            default:
                model.activityDraft.kind = .openingLot
                model.activityDraft.quantity = "1"; model.activityDraft.totalCost = "10"
                #expect(throws: PortfolioActivityEditorError.missingFX) { _ = try model.activityCandidate(at: f.later) }
                model.activityDraft.fxIntent = .manualReset
                model.activityDraft.fxRate = "7.25"; model.activityDraft.fxReferenceDate = "2026-01-15"
            }
            model.activityCorrectionReason = "Synthetic kind change"
            let candidate = try model.activityCandidate(at: f.later)
            await model.saveActivityEdit()
            #expect(model.activitySaveOutcome == "committed")
            #expect(try await f.current(old.id) == candidate)
            #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id).first?.payload.after?.details.domain == candidate.payload)
            #expect(candidate.kind != old.kind && candidate.ledgerEntryID == old.ledgerEntryID)
        }
    }

    @Test("F2 date and same-currency link changes preserve all FX metadata", arguments: ["CNY", "USD"])
    func dateAndLink(_ currency: String) async throws {
        try await withPortfolioFeatureFixture(currency: currency) { f in
            let old = try await f.seed(kind: "buy")
            let other = try await f.addLink(currency: f.currency)
            let model = f.model(); await model.start(); await model.beginActivityEdit(id: old.id)
            model.activityDraft.civilDate = "2026-01-16"; model.activityDraft.securityLinkID = other.id
            model.activityCorrectionReason = "Synthetic date and link"
            await model.saveActivityEdit()
            let saved = try await f.current(old.id)
            #expect(saved.civilDate == (try CivilDate(canonical: "2026-01-16")))
            #expect(saved.payload == old.payload && saved.securityLinkID == other.id)
            let row = try #require(await f.store.portfolioActivityCorrectionHistory(id: old.id).first)
            #expect(row.payload.before.link == f.link && row.payload.after?.link == other)
            let replay = try await f.store.portfolioReplay(portfolioID: f.portfolio.id)
            #expect(try replay.quantity(for: f.link.id).decimal == 10)
            #expect(try replay.quantity(for: other.id).decimal == 1)
            #expect(replay.lots.filter { $0.securityLinkID == other.id }.first?.remainingOriginalBasis.minorUnits == 1300)
        }
    }

    @Test("F3 invalid reasons never submit", arguments: ["", "  ", "bad\0reason", String(repeating: "x", count: 501)])
    func reasonRejected(_ reason: String) async throws {
        try await withPortfolioFeatureFixture { f in
            let old = try await f.seed(kind: "buy")
            let probe = PortfolioFeatureProbe()
            let model = f.model(writer: { try await probe.write($0, store: f.store) })
            await model.start(); await model.beginActivityEdit(id: old.id)
            model.activityDraft.unitPrice = "15"; model.activityCorrectionReason = reason
            #expect(!model.canSaveActivity)
            await model.saveActivityEdit()
            #expect(await probe.requests.isEmpty)
            #expect(model.activityEditFeedback != nil && model.activityDraft.unitPrice == "15")
            #expect(try await f.current(old.id) == old)
            #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id).isEmpty)
        }
    }

    @Test("F3 invalid drafts fail before submission without losing the draft", arguments:
        ["quantity", "price", "fee", "date", "split", "fx", "fxDate", "numericSuffix", "otherPortfolio", "currency", "cost"])
    func invalidDraft(_ fault: String) async throws {
        try await withPortfolioFeatureFixture(currency: "USD") { f in
            let old = try await f.seed(kind: "buy")
            let other = try await f.addLink(currency: fault == "currency" ? .cny : .usd,
                elsewhere: fault == "otherPortfolio")
            let probe = PortfolioFeatureProbe()
            let model = f.model(writer: { try await probe.write($0, store: f.store) })
            await model.start(); await model.beginActivityEdit(id: old.id)
            switch fault {
            case "quantity": model.activityDraft.quantity = "0"
            case "price": model.activityDraft.unitPrice = "-1"
            case "fee": model.activityDraft.fee = "-1"
            case "date": model.activityDraft.civilDate = "2026-02-30"
            case "split": model.activityDraft.kind = .manualSplit; model.activityDraft.splitFrom = "0"; model.activityDraft.splitTo = "2"
            case "fx", "fxDate":
                model.activityDraft.fxIntent = .manualReset
                if fault == "fx" { model.activityDraft.fxRate = "0" }
                else { model.activityDraft.fxReferenceDate = "invalid" }
            case "cost": model.activityDraft.kind = .openingLot; model.activityDraft.totalCost = "-1"
            case "numericSuffix": model.activityDraft.unitPrice = "12oops"
            default: model.activityDraft.securityLinkID = other.id
            }
            model.activityCorrectionReason = "Synthetic rejection"
            let draft = model.activityDraft
            #expect(!model.canSaveActivity)
            await model.saveActivityEdit()
            #expect(model.activityDraft == draft && model.activityEditFeedback != nil)
            #expect(await probe.requests.isEmpty)
            #expect(try await f.current(old.id) == old)
            #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id).isEmpty)
        }
    }

    @Test("F3 real FIFO rejection rolls back the Activity and history")
    func fifoRejected() async throws {
        try await withPortfolioFeatureFixture { f in
            let old = try await f.seed(kind: "sell")
            let before = try await f.store.portfolioReplay(portfolioID: f.portfolio.id)
            let model = f.model(); await model.start(); await model.beginActivityEdit(id: old.id)
            model.activityDraft.quantity = "11"; model.activityCorrectionReason = "Synthetic oversell"
            #expect(model.canSaveActivity)
            await model.saveActivityEdit()
            #expect(model.activityEditFeedback?.contains("FIFO") == true)
            #expect(model.activityDraft.quantity == "11" && !model.requiresActivityReload)
            #expect(try await f.current(old.id) == old)
            #expect(try await f.store.portfolioReplay(portfolioID: f.portfolio.id) == before)
            #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id).isEmpty)
        }
    }

    @Test("F4/F5 explicit FX request remains identical across pre/post-commit unknown results", arguments: [false, true])
    func frozenFXRetry(_ afterCommit: Bool) async throws {
        try await withPortfolioFeatureFixture(currency: "USD") { f in
            let old = try await f.seed(kind: "buy")
            let clock = PortfolioFeatureClock(f.later)
            let probe = PortfolioFeatureProbe(failure: afterCommit ? .after : .before)
            let model = f.model(clock: clock, writer: { try await probe.write($0, store: f.store) })
            await model.start(); await model.beginActivityEdit(id: old.id)
            model.activityDraft.fxIntent = .manualReset; model.activityDraft.fxRate = "7.50"
            model.activityDraft.fxReferenceDate = "2026-02-01"
            model.activityCorrectionReason = " Synthetic FX reset "
            #expect(model.canSaveActivity && model.needsActivityCorrectionReason)
            #expect(clock.calls == 0) // Draft/preview validation must not sample a clock.
            await model.saveActivityEdit()
            #expect(!model.requiresActivityReload && model.activityEditID == old.id)
            clock.set(UTCInstant(millisecondsSince1970: f.later.millisecondsSince1970 + 9999))
            await model.saveActivityEdit()
            let requests = await probe.requests
            #expect(requests.count == 2 && clock.calls == 1)
            let a = try #require(requests.first), b = try #require(requests.last)
            #expect(a.candidate == b.candidate && a.expected == b.expected && a.operationID == b.operationID)
            #expect(a.reason == b.reason && a.occurredAt == b.occurredAt && a.occurredAt == f.later)
            let fx = try #require(PortfolioActivityDraft.fx(a.candidate.payload))
            #expect(fx.source == "manual" && fx.isManual && fx.isStale)
            #expect(fx.rate.decimal == Decimal(string: "7.5") && fx.recordedAt == f.later)
            #expect(fx.referenceDate == (try CivilDate(canonical: "2026-02-01")))
            #expect(fx.original.minorUnits == 1300 && fx.convertedCNY.minorUnits == 9750)
            #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id).count == 1)
            #expect(model.activitySaveOutcome == "committed")
        }
    }

    @Test("F5 pending changes block both a replay and a new operation until explicit reload", arguments: ["draft", "reason", "fxIntent"])
    func pendingMutation(_ branch: String) async throws {
        try await withPortfolioFeatureFixture(currency: "USD") { f in
            let old = try await f.seed(kind: "buy")
            let probe = PortfolioFeatureProbe(failure: .after)
            let model = f.model(writer: { try await probe.write($0, store: f.store) })
            await model.start(); await model.beginActivityEdit(id: old.id)
            model.activityDraft.unitPrice = "15"; model.activityCorrectionReason = "Synthetic pending"
            await model.saveActivityEdit()
            let committed = try await f.current(old.id)
            if branch == "draft" { model.activityDraft.unitPrice = "20" }
            else if branch == "reason" { model.activityCorrectionReason = "Synthetic different" }
            else { model.activityDraft.fxIntent = .manualReset }
            await model.saveActivityEdit()
            #expect(model.requiresActivityReload)
            #expect(await probe.requests.count == 1)
            #expect(try await f.current(old.id) == committed)
            #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id).count == 1)
            await model.reloadActivityEdit()
            #expect(!model.requiresActivityReload && model.activityDraft.fxIntent == .preserve)
            model.activityDraft.unitPrice = "20"; model.activityCorrectionReason = "Synthetic fresh request"
            await model.saveActivityEdit()
            let requests = await probe.requests
            #expect(requests.count == 2 && requests[0].operationID != requests[1].operationID)
        }
    }

    @Test("F5 receipts report later changed/deleted facts without overwrite or revival", arguments: [false, true])
    func replayLaterState(_ deleted: Bool) async throws {
        try await withPortfolioFeatureFixture { f in
            let old = try await f.seed(kind: "buy")
            let probe = PortfolioFeatureProbe(failure: .after)
            let model = f.model(writer: { try await probe.write($0, store: f.store) })
            await model.start(); await model.beginActivityEdit(id: old.id)
            model.activityDraft.unitPrice = "15"; model.activityCorrectionReason = "Synthetic replay"
            await model.saveActivityEdit()
            if deleted { try await f.store.deletePortfolioActivity(id: old.id) }
            else { try await f.store.updatePortfolioActivity(old) }
            await model.saveActivityEdit()
            #expect(model.requiresActivityReload && model.activitySaveOutcome == "committed-later-state")
            let activities = try await f.store.fetchPortfolioActivities(portfolioID: f.portfolio.id)
            #expect(deleted ? !activities.contains { $0.id == old.id } : activities.contains(old))
            #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id).filter { $0.kind == "correction" }.count == 1)
        }
    }

    @Test("F5 minor/no-change unknown results cannot claim a durable receipt", arguments: [false, true])
    func nonDurableUnknown(_ minor: Bool) async throws {
        try await withPortfolioFeatureFixture { f in
            let old = try await f.seed(kind: "openingLot")
            let probe = PortfolioFeatureProbe(failure: .after)
            let model = f.model(writer: { try await probe.write($0, store: f.store) })
            await model.start(); await model.beginActivityEdit(id: old.id)
            if minor { model.activityDraft.note = "Synthetic minor" }
            await model.saveActivityEdit(); await model.saveActivityEdit()
            #expect(model.requiresActivityReload)
            #expect(await probe.requests.count == 1)
            #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id).isEmpty)
            await model.reloadActivityEdit()
            #expect(!model.requiresActivityReload)
            #expect(model.activityDraft.note == (minor ? "Synthetic minor" : ""))
        }
    }

    @Test("F5 acknowledged commit is distinct from failed display refresh")
    func committedRefreshFailure() async throws {
        try await withPortfolioFeatureFixture { f in
            let old = try await f.seed(kind: "buy")
            let readProbe = PortfolioFeatureReadProbe()
            let probe = PortfolioFeatureProbe()
            let model = f.model(writer: { try await probe.write($0, store: f.store) },
                activityLoader: { id in
                    if await readProbe.fail { throw PortfolioFeatureFailure.ambiguous }
                    return try await f.store.fetchPortfolioActivities(portfolioID: id)
                })
            await model.start(); await model.beginActivityEdit(id: old.id)
            model.activityDraft.unitPrice = "15"; model.activityCorrectionReason = "Synthetic confirmed"
            await readProbe.setFailure()
            await model.saveActivityEdit(); await model.saveActivityEdit()
            #expect(model.activityEditID == nil && model.activitySaveOutcome == "committed")
            #expect(model.errorMessage?.contains("save was confirmed") == true)
            #expect(await probe.requests.count == 1)
            #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id).count == 1)
        }
    }

    @Test("F6 save blocks duplicate commands, cancel, new editor and Portfolio switching")
    func savingSessionIsolation() async throws {
        try await withPortfolioFeatureFixture { f in
            let old = try await f.seed(kind: "buy")
            let gate = PortfolioFeatureGate(), probe = PortfolioFeatureProbe()
            let model = f.model(writer: { request in
                await gate.enterAndWait(); return try await probe.write(request, store: f.store)
            })
            await model.start(); await model.beginActivityEdit(id: old.id)
            model.activityDraft.unitPrice = "15"; model.activityCorrectionReason = "Synthetic gated"
            let saving = Task { await model.saveActivityEdit() }
            await gate.waitUntilEntered()
            await model.saveActivityEdit(); model.cancelActivityEdit()
            await model.beginActivityEdit(id: f.base.id)
            let other = UUID()
            model.selectedPortfolioID = other
            await model.select(other)
            #expect(model.selectedPortfolioID == f.portfolio.id && model.activityEditID == old.id)
            await gate.release(); await saving.value
            #expect(await probe.requests.count == 1)
            #expect(model.selectedPortfolioID == f.portfolio.id && model.activityEditID == nil)
            #expect(model.activities.contains { $0.id == old.id })
        }
    }

    @Test("F6 late context reads cannot cross cancel, object reopen or Portfolio selection", arguments: ["cancel", "object", "portfolio"])
    func delayedContext(_ branch: String) async throws {
        try await withPortfolioFeatureFixture { f in
            let old = try await f.seed(kind: "buy")
            let gate = PortfolioFeatureGate()
            let model = f.model(contextLoader: { id in
                if id == old.id { await gate.enterAndWait() }
                return try await f.store.readPortfolioActivityEditContext(id: id)
            })
            await model.start()
            let loading = Task { await model.beginActivityEdit(id: old.id) }
            await gate.waitUntilEntered()
            #expect(model.activityEditState == .loading && !model.canSaveActivity)
            if branch == "object" { await model.beginActivityEdit(id: f.base.id) }
            else if branch == "portfolio" { await model.select(try await f.otherPortfolio().id) }
            else { model.cancelActivityEdit() }
            await gate.release(); await loading.value
            #expect(model.activityEditID == (branch == "object" ? f.base.id : nil))
            #expect(model.activityEditState == (branch == "object" ? .ready : .idle))
        }
    }

    @Test("F6 finite stale/deleted/conflict/maintenance mappings preserve draft", arguments: ["stale", "deleted", "conflict", "maintenance", "epoch", "load"])
    func errorMapping(_ branch: String) async throws {
        try await withPortfolioFeatureFixture { f in
            let old = try await f.seed(kind: "buy")
            let model = f.model(contextLoader: { id in
                if branch == "load" { throw PortfolioFeatureFailure.ambiguous }
                return try await f.store.readPortfolioActivityEditContext(id: id)
            }, writer: { request in
                if branch == "conflict" { throw PortfolioCorrectionError.operationConflict }
                if branch == "maintenance" { throw PortfolioCorrectionError.maintenanceUnavailable }
                return try await f.store.correctPortfolioActivity(request)
            })
            await model.start(); await model.beginActivityEdit(id: old.id)
            if branch == "load" {
                #expect(model.activityEditState == .failed && !model.canSaveActivity); return
            }
            if branch == "stale" {
                let second = f.model(); await second.start(); await second.beginActivityEdit(id: old.id)
                second.activityDraft.unitPrice = "20"; second.activityCorrectionReason = "Synthetic other writer"
                await second.saveActivityEdit()
            }
            if branch == "deleted" { try await f.store.deletePortfolioActivity(id: old.id) }
            if branch == "epoch" { await f.store.invalidatePortfolioEditTokens() }
            model.activityDraft.unitPrice = "15"; model.activityCorrectionReason = "Synthetic stale"
            let rows = try await f.store.fetchPortfolioActivities(portfolioID: f.portfolio.id)
            let history = try await f.store.portfolioActivityCorrectionHistory(id: old.id)
            await model.saveActivityEdit()
            #expect(model.requiresActivityReload == (branch != "maintenance"))
            #expect(model.activityDraft.unitPrice == "15" && model.activityEditFeedback != nil)
            #expect(try await f.store.fetchPortfolioActivities(portfolioID: f.portfolio.id) == rows)
            #expect(try await f.store.portfolioActivityCorrectionHistory(id: old.id) == history)
        }
    }

    @Test("F7 real history is per-target, sequence ordered, financially complete and contextual")
    func historyDisplay() async throws {
        try await withPortfolioFeatureFixture(currency: "USD") { f in
            let old = try await f.seed(kind: "buy")
            let model = f.model(); await model.start()
            await model.showActivityHistory(id: old.id)
            #expect(model.activityHistoryState == .ready && model.activityHistory.isEmpty)
            for price in ["15", "20"] {
                await model.beginActivityEdit(id: old.id)
                model.activityDraft.unitPrice = price; model.activityCorrectionReason = "Synthetic display"
                await model.saveActivityEdit()
            }
            try await f.store.deleteLedgerEntry(id: f.ledgerID)
            await model.showActivityHistory(id: old.id)
            let rows = model.activityHistory
            #expect(rows.count == 3 && Set(rows.map(\.id)).count == 3)
            #expect(rows.map(\.sequence) == rows.map(\.sequence).sorted())
            #expect(rows[0].occurredAt == rows[1].occurredAt)
            let display = rows.map(PortfolioActivityHistoryDisplay.init)
            #expect(display[0].before.contains("USD 13") && display[0].after.contains("USD 16"))
            #expect(display[0].before.contains("CNY 94.25") && display[0].after.contains("CNY 116"))
            #expect(display[0].before.contains("synthetic.nonmanual") && display[0].before.contains("manual false"))
            #expect(display[0].before.contains(f.link.id.uuidString) && display[0].before.contains(f.ledgerID.uuidString))
            #expect(display[2].title.contains("ledgerDetachContext") && display[2].explanation.contains("no user correction reason"))
            #expect(display[2].after.contains("Ledger none"))
            model.closeActivityHistory(); await model.showActivityHistory(id: old.id)
            #expect(model.activityHistory == rows)
            try await f.store.deletePortfolioActivity(id: old.id)
            await model.showActivityHistory(id: old.id)
            let deleted = try #require(model.activityHistory.last)
            #expect(deleted.kind == "deletionContext")
            #expect(PortfolioActivityHistoryDisplay(deleted).before.contains(f.link.symbol))
            #expect(PortfolioActivityHistoryDisplay(deleted).after.contains("Activity deleted"))
        }
    }

    @Test("F7 late history and failure never masquerade as empty or another target", arguments: ["close", "object", "portfolio", "failed"])
    func historySessions(_ branch: String) async throws {
        try await withPortfolioFeatureFixture { f in
            let old = try await f.seed(kind: "buy")
            let gate = PortfolioFeatureGate()
            let model = f.model(historyLoader: { id in
                if branch == "failed" { throw PortfolioFeatureFailure.ambiguous }
                if id == old.id { await gate.enterAndWait() }
                return try await f.store.portfolioActivityCorrectionHistory(id: id)
            })
            await model.start()
            if branch == "failed" {
                await model.showActivityHistory(id: old.id)
                #expect(model.activityHistoryState == .failed && model.activityHistory.isEmpty); return
            }
            let loading = Task { await model.showActivityHistory(id: old.id) }
            await gate.waitUntilEntered()
            #expect(model.activityHistoryState == .loading)
            if branch == "object" { await model.showActivityHistory(id: f.base.id) }
            else if branch == "portfolio" { await model.select(try await f.otherPortfolio().id) }
            else { model.closeActivityHistory() }
            await gate.release(); await loading.value
            #expect(model.activityHistoryID == (branch == "object" ? f.base.id : nil))
            #expect(model.activityHistoryState == (branch == "object" ? .ready : .idle))
        }
    }

    @Test("F8 edit/history leave NAV, Wealth and preferences unchanged and never request Provider")
    func sideEffectBoundary() async throws {
        try await withPortfolioFeatureFixture { f in
            let old = try await f.seed(kind: "buy")
            let model = f.model(); await model.start()
            await model.captureNAV(on: f.date)
            await model.saveBenchmark(symbol: "SYN", rawMIC: "XSYN", range: .oneYear)
            let nav = try await f.store.fetchPortfolioNAVSnapshots(portfolioID: f.portfolio.id)
            let wealth = try await f.store.fetchWealthContainers()
            let preference = model.benchmarkPreference
            await model.beginActivityEdit(id: old.id)
            model.activityDraft.unitPrice = "15"; model.activityCorrectionReason = "Synthetic side effect check"
            await model.saveActivityEdit(); await model.showActivityHistory(id: old.id)
            #expect(try await f.store.fetchPortfolioNAVSnapshots(portfolioID: f.portfolio.id) == nav)
            #expect(try await f.store.fetchWealthContainers() == wealth)
            #expect(model.benchmarkPreference == preference)
            #expect(await f.provider.calls == 0)
            model.closeActivityHistory()
            await model.addActivity(old.payload, to: f.link.id, date: f.date)
            let added = try #require(model.activities.first { $0.id != old.id && $0.id != f.base.id })
            #expect(try await f.store.portfolioActivityCorrectionHistory(id: added.id).isEmpty)
            await model.deleteActivity(added.id)
            #expect(!model.activities.contains { $0.id == added.id })
            #expect(await f.provider.calls == 0)
        }
    }
}

private enum PortfolioFeatureFailure: Error { case ambiguous }

@MainActor
private func withPortfolioFeatureFixture(currency: String = "CNY",
    _ body: (PortfolioFeatureFixture) async throws -> Void) async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await PortfolioFeatureFixture(root: root, currency: CurrencyCode(rawValue: currency)!)
    do { try await body(fixture) }
    catch { try? await fixture.store.queue.close(); throw error }
    try await fixture.store.queue.close()
}

@MainActor
private struct PortfolioFeatureFixture {
    let root: URL, database: URL
    let store: WealthStore
    let currency: CurrencyCode
    let portfolio: PortfolioRecord
    let link: PortfolioSecurityLink
    let base: PortfolioActivity
    let ledgerID: UUID
    let date = try! CivilDate(canonical: "2026-01-15")
    let instant = UTCInstant(millisecondsSince1970: 1_768_435_200_000)
    let later = UTCInstant(millisecondsSince1970: 1_800_000_000_000)
    let provider = PortfolioFeatureProvider()
    let preferences = PortfolioPreferencesStore(suiteName: nil, memoryOnly: true)

    init(root: URL, currency: CurrencyCode) async throws {
        self.root = root; database = root.appendingPathComponent("Permanent/aureus.sqlite")
        self.currency = currency
        store = try WealthStore(databaseURL: database)
        portfolio = try PortfolioRecord(name: "Synthetic feature Portfolio", createdAt: instant, updatedAt: instant, sortOrder: 0)
        try await store.createPortfolio(portfolio)
        let wealth = try Self.security(currency: currency, symbol: "SYNA", date: date, instant: instant)
        try await store.createWealthContainer(wealth)
        link = try PortfolioSecurityLink(portfolioID: portfolio.id, wealthContainerID: wealth.id,
            symbol: "SYNA", rawMIC: "XSYN", currency: currency, assetKind: .stock, sortOrder: 0)
        try await store.linkPortfolioSecurity(link)
        let ledger = try LedgerTestContext.make()
        try await store.createWealthContainer(ledger.source)
        let entry = try ledger.entry(kind: .income)
        ledgerID = entry.id; try await store.createLedgerEntry(entry)
        let money = Money(minorUnits: 10_000, currency: currency)
        let fx = try Self.fx(money, date: date, instant: instant)
        base = try PortfolioActivity(portfolioID: portfolio.id, securityLinkID: link.id,
            civilDate: try CivilDate(canonical: "2026-01-14"), recordedAt: instant,
            exchangeTimeZoneIdentifier: "America/New_York",
            payload: .openingLot(quantity: AssetQuantity(decimal: 10), totalCost: money, fx: fx, note: nil))
        try await store.createPortfolioActivity(base)
    }

    static func fx(_ original: Money, date: CivilDate, instant: UTCInstant, manual: Bool = false) throws -> PortfolioFXProvenance {
        try PortfolioFXProvenance(original: original,
            rate: original.currency == .cny ? .cnyIdentity : FXRate(decimal: 7.25, sourceCurrency: .usd, targetCurrency: .cny),
            source: original.currency == .cny ? "identity" : (manual ? "manual.synthetic" : "synthetic.nonmanual"),
            referenceDate: date, recordedAt: instant, isManual: original.currency == .usd && manual, isStale: true)
    }
    static func security(currency: CurrencyCode, symbol: String, date: CivilDate, instant: UTCInstant) throws -> WealthContainer {
        let container = AssetContainer(id: UUID(), accountID: nil, name: "Synthetic \(symbol)", kind: .stock,
            institution: nil, primaryCurrency: currency, notes: nil, createdDate: date, updatedDate: date)
        let details = WealthRecordDetails.security(ticker: symbol, mic: "XSYN",
            quantity: try AssetQuantity(decimal: 10), manualPrice: try MarketPrice(decimal: 20, quoteCurrency: currency))
        let fx = try Self.fx(details.currentValue(), date: date, instant: instant, manual: true)
        return try WealthContainer(container: container, details: details,
            valuation: FXValuation(original: fx.original, rate: fx.rate, referenceDate: date,
                fetchedAt: instant, providerIdentifier: fx.source, isManualOverride: currency == .usd, isStale: true))
    }
    func seed(kind: String, precise: Bool = false) async throws -> PortfolioActivity {
        let q = try AssetQuantity(decimal: precise ? FixedPointMath.parseCanonical("1.12345678") : 1)
        let price = try MarketPrice(decimal: precise ? FixedPointMath.parseCanonical("12.12345678") : 12, quoteCurrency: currency)
        let fee = Money(minorUnits: 100, currency: currency)
        let payload: PortfolioActivityPayload
        switch kind {
        case "openingLot":
            let cost = Money(minorUnits: 1000, currency: currency)
            payload = .openingLot(quantity: q, totalCost: cost, fx: try Self.fx(cost, date: date, instant: instant), note: nil)
        case "manualSplit": payload = .manualSplit(from: try Ratio(decimal: 2), to: try Ratio(decimal: 3))
        default:
            let gross = try PortfolioCheckedMath.moneyProduct(quantity: q, price: price)
            let total = kind == "sell" ? try gross.subtracting(fee) : try gross.adding(fee)
            let fx = try Self.fx(total, date: date, instant: instant, manual: precise)
            payload = kind == "sell" ? .sell(quantity: q, unitPrice: price, fee: fee, fx: fx)
                : .buy(quantity: q, unitPrice: price, fee: fee, fx: fx)
        }
        let activity = try PortfolioActivity(portfolioID: portfolio.id, securityLinkID: link.id,
            civilDate: date, recordedAt: instant, exchangeTimeZoneIdentifier: "America/New_York",
            ledgerEntryID: ledgerID, payload: payload)
        try await store.createPortfolioActivity(activity)
        return activity
    }
    func otherPortfolio() async throws -> PortfolioRecord {
        let p = try PortfolioRecord(name: "Synthetic other", createdAt: instant, updatedAt: instant, sortOrder: 1)
        try await store.createPortfolio(p); return p
    }
    func addLink(currency: CurrencyCode, elsewhere: Bool = false) async throws -> PortfolioSecurityLink {
        let p = elsewhere ? try await otherPortfolio().id : portfolio.id
        let wealth = try Self.security(currency: currency, symbol: "SYNB", date: date, instant: instant)
        try await store.createWealthContainer(wealth)
        let link = try PortfolioSecurityLink(portfolioID: p, wealthContainerID: wealth.id,
            symbol: "SYNB", rawMIC: "XSYN", currency: currency, assetKind: .stock, sortOrder: 1)
        try await store.linkPortfolioSecurity(link); return link
    }
    func current(_ id: UUID) async throws -> PortfolioActivity { try await store.readPortfolioActivityEditContext(id: id).activity }
    func model(clock: (any Clock)? = nil,
        contextLoader: (@Sendable (UUID) async throws -> PortfolioActivityEditContext)? = nil,
        historyLoader: (@Sendable (UUID) async throws -> [PortfolioCorrectionHistory])? = nil,
        writer: (@Sendable (PortfolioCorrectionRequest) async throws -> PortfolioCorrectionResult)? = nil,
        activityLoader: (@Sendable (UUID) async throws -> [PortfolioActivity])? = nil) -> PortfolioFeatureModel {
        let clock = clock ?? FixedClock(instant: later)
        let session = TransientMarketSessionStore()
        let service = MarketDataService(marketProvider: provider, fxProvider: provider,
            cache: try! MarketCacheStore(databaseURL: root.appendingPathComponent("Cache/market.sqlite")),
            sessionStore: session, clock: clock)
        return PortfolioFeatureModel(store: store, marketDataService: service, marketSessionStore: session,
            preferences: preferences, clock: clock, mode: .syntheticDemo, contextLoader: contextLoader,
            historyLoader: historyLoader, correctionWriter: writer, activityLoader: activityLoader)
    }
}

private actor PortfolioFeatureProbe {
    enum Failure { case none, before, after }
    let failure: Failure
    private(set) var requests: [PortfolioCorrectionRequest] = []
    init(failure: Failure = .none) { self.failure = failure }
    func write(_ request: PortfolioCorrectionRequest, store: WealthStore) async throws -> PortfolioCorrectionResult {
        requests.append(request)
        if requests.count == 1 && failure == .before { throw PortfolioFeatureFailure.ambiguous }
        let result = try await store.correctPortfolioActivity(request)
        if requests.count == 1 && failure == .after { throw PortfolioFeatureFailure.ambiguous }
        return result
    }
}
private actor PortfolioFeatureReadProbe {
    private(set) var fail = false
    func setFailure() { fail = true }
}
private final class PortfolioFeatureClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: UTCInstant
    private var count = 0
    init(_ instant: UTCInstant) { self.instant = instant }
    var calls: Int { lock.withLock { count } }
    func now() -> UTCInstant { lock.withLock { count += 1; return instant } }
    func set(_ value: UTCInstant) { lock.withLock { instant = value } }
}
private actor PortfolioFeatureGate {
    private var entered = false, released = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func enterAndWait() async {
        entered = true; arrival?.resume(); arrival = nil
        if released { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { arrival = $0 }
    }
    func release() { released = true; waiter?.resume(); waiter = nil }
}
private actor PortfolioFeatureProvider: MarketDataProvider, FXRateProvider {
    nonisolated let descriptor = ProviderDescriptor(identifier: "synthetic.portfolio.feature", displayName: "Synthetic", kind: .synthetic)
    private(set) var calls = 0
    func capabilities() -> MarketProviderCapabilities {
        calls += 1
        return MarketProviderCapabilities(provider: descriptor, entitlement: .unknown, observedPlanName: nil,
            markets: [], supportsSearch: false, supportsHistoricalPrices: false,
            supportsCorporateActions: false, endpointCapabilities: [], observedAt: UTCInstant(millisecondsSince1970: 0))
    }
    func search(query: String) throws -> [MarketInstrument] { calls += 1; throw ProviderBoundaryError.missing }
    func latestQuote(for instrument: MarketInstrument) throws -> MarketQuote { calls += 1; throw ProviderBoundaryError.missing }
    func historicalBars(_ request: MarketHistoryRequest) throws -> MarketHistoryPage { calls += 1; throw ProviderBoundaryError.missing }
    func corporateActions(for instrument: MarketInstrument, from startDate: CivilDate?, through endDate: CivilDate?) throws -> [MarketCorporateAction] { calls += 1; throw ProviderBoundaryError.missing }
    func rate(source: CurrencyCode, target: CurrencyCode, on date: CivilDate) throws -> ExchangeRate { calls += 1; throw ProviderBoundaryError.missing }
}
