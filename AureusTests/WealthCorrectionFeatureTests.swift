import Foundation
import Testing
@testable import Aureus

@MainActor
@Suite("Wealth correction feature integration", .serialized)
struct WealthCorrectionFeatureTests {
    @Test("Create keeps CNY and USD ordinary, without a correction reason or history",
          arguments: [CurrencyCode.cny, .usd])
    func createAndPreferences(_ currency: CurrencyCode) async throws {
        let f = try WealthFeatureFixture(); defer { f.remove() }
        let model = f.model()
        await model.loadIfNeeded()
        model.beginAdd()
        var draft = try #require(model.editor?.initialDraft)
        draft.name = "Synthetic new Wealth"
        draft.currency = currency
        draft.amount = "100.00"
        if currency == .usd { draft.fxRate = "7.25" }
        await model.save(draft)
        let current = try #require(await f.store.fetchWealthContainers().first)
        #expect(current.container.name == "Synthetic new Wealth")
        #expect(current.container.primaryCurrency == currency)
        #expect(current.convertedCNYValue.minorUnits == (currency == .usd ? 72_500 : 10_000))
        #expect(try await f.store.wealthCorrectionHistory(id: current.id).isEmpty)
        #expect(model.editor == nil)
    }

    @Test("All seven Wealth kinds correct through the real Store and retain historical context",
          arguments: [0, 1, 2, 3, 4, 5, 6, 7])
    func importantEdits(_ index: Int) async throws {
        let f = try WealthFeatureFixture(); defer { f.remove() }
        let original = try await f.seed(index)
        let model = f.model()
        await model.loadIfNeeded()
        model.selection = original.id
        await model.beginEdit()
        #expect(model.editLoadState == .ready)
        var draft = try #require(model.editor?.initialDraft)
        if original.container.kind.isManualSecurity { draft.manualPrice = "50.00" }
        else { draft.amount = "200.00" }
        model.correctionReason = "  Synthetic important correction  "
        #expect(model.needsCorrectionReason(draft))
        await model.save(draft)
        let current = try #require(await f.store.fetchWealthContainer(id: original.id))
        let history = try await f.store.wealthCorrectionHistory(id: original.id)
        #expect(model.editor == nil)
        #expect(current.id == original.id && current.container.createdDate == original.container.createdDate)
        #expect(history.count == 1)
        #expect(history.first?.payload.before == WealthCorrectionProjection(original))
        #expect(history.first?.payload.after == WealthCorrectionProjection(current))
        #expect(history.first?.reason == "Synthetic important correction")
        #expect(try await f.store.wealthSummary().netWorthCNY.minorUnits
            == (current.isLiability ? -current.convertedCNYValue.minorUnits : current.convertedCNYValue.minorUnits))
    }

    @Test("Cross-day no-op and minor edits preserve CNY identity and custom USD provenance",
          arguments: [0, 1])
    func fxAndMinorPreservation(_ index: Int) async throws {
        let f = try WealthFeatureFixture(); defer { f.remove() }
        let original = try await f.seed(index)
        let model = f.model()
        await model.loadIfNeeded()
        model.selection = original.id
        let tokenBefore = try await f.store.readWealthEditContext(id: original.id)
        await model.beginEdit()
        var draft = try #require(model.editor?.initialDraft)
        if index == 1 { draft.fxRate = "7.125000" }
        else { draft.amount = "125000.000" }
        await model.save(draft)
        let afterNoop = try await f.store.readWealthEditContext(id: original.id)
        #expect(afterNoop.token.stateDigest == tokenBefore.token.stateDigest)
        #expect(afterNoop.record.valuation == original.valuation)
        await model.beginEdit()
        draft = try #require(model.editor?.initialDraft)
        draft.notes = "Synthetic changed note"
        await model.save(draft)
        let afterMinor = try #require(await f.store.fetchWealthContainer(id: original.id))
        #expect(afterMinor.valuation == original.valuation)
        #expect(try await f.store.wealthCorrectionHistory(id: original.id).isEmpty)
        await model.beginEdit()
        draft = try #require(model.editor?.initialDraft)
        draft.name = "Synthetic renamed"
        await model.save(draft)
        #expect(try await f.store.fetchWealthContainer(id: original.id)?.valuation == original.valuation)
        #expect(try await f.store.wealthCorrectionHistory(id: original.id).isEmpty)
        await model.beginEdit()
        draft = try #require(model.editor?.initialDraft)
        draft.amount = index == 1 ? "1001.00" : "125001.00"
        model.correctionReason = "Synthetic value correction"
        await model.save(draft)
        #expect(try await f.store.fetchWealthContainer(id: original.id)?.valuation.fetchedAt
            == original.valuation.fetchedAt)
        #expect(try await f.store.wealthCorrectionHistory(id: original.id).count == 1)
    }

    @Test("A new FX input uses the frozen command clock and the entire request survives retry")
    func newFXTimeAndRetry() async throws {
        let f = try WealthFeatureFixture(); defer { f.remove() }
        let original = try await f.seed(1)
        let clock = WealthFeatureMutableClock(f.instant)
        let probe = WealthFeatureWriteProbe(fail: .before)
        let model = f.model(clock: clock,
            correctionWriter: { try await probe.write($0, store: f.store) })
        await model.loadIfNeeded(); model.selection = original.id
        await model.beginEdit()
        var draft = try #require(model.editor?.initialDraft)
        draft.fxRate = "7.50"
        model.correctionReason = "Synthetic FX correction"
        await model.save(draft)
        #expect(model.editor != nil)
        clock.set(UTCInstant(millisecondsSince1970: f.instant.millisecondsSince1970 + 86_400_000))
        await model.save(draft)
        let requests = await probe.requests
        #expect(requests.count == 2)
        let first = try #require(requests.first), second = try #require(requests.last)
        #expect(first.operationID == second.operationID && first.expected == second.expected)
        #expect(first.candidate == second.candidate && first.reason == second.reason)
        #expect(first.fxIntent == .newInput && second.fxIntent == .newInput)
        #expect(first.occurredAt == f.instant && second.occurredAt == f.instant)
        #expect(first.candidate.valuation.fetchedAt == f.instant)
        #expect(try await f.store.fetchWealthContainer(id: original.id)?.valuation.fetchedAt == f.instant)
    }

    @Test("Current valuation updates each allowed value without a correction history",
          arguments: [0, 1, 2, 3, 4, 5, 6, 7])
    func valuationIntent(_ index: Int) async throws {
        let f = try WealthFeatureFixture(); defer { f.remove() }
        let original = try await f.seed(index)
        let model = f.model()
        await model.loadIfNeeded(); model.selection = original.id
        await model.beginEdit()
        model.editIntent = .currentValuation
        var draft = try #require(model.editor?.initialDraft)
        if original.container.kind.isManualSecurity { draft.manualPrice = "50.00" }
        else { draft.amount = "200.00" }
        await model.save(draft)
        let current = try #require(await f.store.fetchWealthContainer(id: original.id))
        #expect(current.originalValue != original.originalValue)
        #expect(current.valuation.fetchedAt == original.valuation.fetchedAt)
        #expect(try await f.store.wealthCorrectionHistory(id: original.id).isEmpty)
        #expect(model.editor == nil)
    }

    @Test("The exercised fixtures cover every distinct Wealth kind, including ETF")
    func allKindsFixtureCoverage() async throws {
        let f = try WealthFeatureFixture(); defer { f.remove() }
        var exercised: Set<AssetContainerKind> = []
        for index in 0...7 {
            let record = try await f.seed(index)
            exercised.insert(record.container.kind)
        }
        #expect(exercised == Set(AssetContainerKind.allCases))
    }

    @Test("Direct draft injection cannot broaden current valuation",
          arguments: ["quantity", "currency", "institution", "contract", "name", "notes"])
    func valuationRejectsOutOfScope(_ fault: String) async throws {
        let f = try WealthFeatureFixture(); defer { f.remove() }
        let index = fault == "quantity" ? 2 : fault == "contract" ? 4 : 0
        let original = try await f.seed(index)
        let token = try await f.store.readWealthEditContext(id: original.id)
        let model = f.model()
        await model.loadIfNeeded(); model.selection = original.id
        await model.beginEdit(); model.editIntent = .currentValuation
        var draft = try #require(model.editor?.initialDraft)
        switch fault {
        case "quantity": draft.quantity = "13"
        case "currency": draft.currency = .usd; draft.fxRate = "7"
        case "institution": draft.institution = "Synthetic changed institution"
        case "name": draft.name = "Synthetic changed name"
        case "notes": draft.notes = "Synthetic changed notes"
        default: draft.insuranceProductName = "Synthetic changed contract"
        }
        await model.save(draft)
        #expect(model.editor != nil)
        #expect(model.editorErrorMessage != nil)
        #expect(try await f.store.readWealthEditContext(id: original.id).token.stateDigest == token.token.stateDigest)
        #expect(try await f.store.wealthCorrectionHistory(id: original.id).isEmpty)
    }

    @Test("Important edits require a bounded user reason", arguments: ["", "  ", "bad\0reason", String(repeating: "x", count: 501)])
    func reasonValidation(_ reason: String) async throws {
        let f = try WealthFeatureFixture(); defer { f.remove() }
        let original = try await f.seed(0)
        let model = f.model()
        await model.loadIfNeeded(); model.selection = original.id
        await model.beginEdit()
        var draft = try #require(model.editor?.initialDraft)
        draft.amount = "200.00"
        model.correctionReason = reason
        await model.save(draft)
        #expect(model.editor != nil)
        #expect(try await f.store.fetchWealthContainer(id: original.id) == original)
        #expect(try await f.store.wealthCorrectionHistory(id: original.id).isEmpty)
    }

    @Test("Two drafts and a legacy writer require explicit reload, retaining the stale draft")
    func staleDraftAndReload() async throws {
        let f = try WealthFeatureFixture(); defer { f.remove() }
        let original = try await f.seed(0)
        let first = f.model(), second = f.model()
        await first.loadIfNeeded(); await second.loadIfNeeded()
        first.selection = original.id; second.selection = original.id
        await first.beginEdit(); await second.beginEdit()
        var a = try #require(first.editor?.initialDraft)
        a.amount = "200.00"; first.correctionReason = "Synthetic first"
        await first.save(a)
        var b = try #require(second.editor?.initialDraft)
        b.amount = "300.00"; second.correctionReason = "Synthetic stale"
        await second.save(b)
        #expect(second.requiresEditReload && second.editor != nil)
        #expect(try await f.store.fetchWealthContainer(id: original.id)?.originalValue.minorUnits == 20_000)
        await second.reloadEdit()
        #expect(!second.requiresEditReload)
        #expect(second.editor?.initialDraft.amount == "200")
        let latest = try #require(await f.store.fetchWealthContainer(id: original.id))
        let renamed = try f.renamed(latest, "Synthetic legacy")
        try await f.store.updateWealthContainer(renamed)
        b = try #require(second.editor?.initialDraft)
        b.amount = "400.00"; second.correctionReason = "Synthetic next"
        await second.save(b)
        #expect(second.requiresEditReload)
        #expect(try await f.store.fetchWealthContainer(id: original.id)?.container.name == "Synthetic legacy")
    }

    @Test("A committed but unacknowledged request cannot carry a changed draft, reason or intent",
          arguments: ["draft", "reason", "intent"])
    func pendingCorrectionReplay(_ branch: String) async throws {
        let f = try WealthFeatureFixture(); defer { f.remove() }
        let original = try await f.seed(0)
        let probe = WealthFeatureWriteProbe(fail: .after)
        let valuationProbe = WealthFeatureValuationProbe()
        let model = f.model(correctionWriter: { try await probe.write($0, store: f.store) },
            valuationWriter: { try await valuationProbe.write($0, store: f.store) })
        await model.loadIfNeeded(); model.selection = original.id; await model.beginEdit()
        var draft = try #require(model.editor?.initialDraft)
        draft.amount = "200.00"; model.correctionReason = "Synthetic first intent"
        await model.save(draft)
        #expect(model.editor != nil)
        #expect(try await f.store.wealthCorrectionHistory(id: original.id).count == 1)
        var changed = draft
        if branch == "draft" { changed.amount = "300.00" }
        else if branch == "reason" { model.correctionReason = "Synthetic changed reason" }
        else { model.editIntent = .currentValuation }
        await model.save(changed)
        #expect(model.requiresEditReload)
        #expect(model.editor != nil)
        #expect(await probe.requests.count == 1)
        #expect(await valuationProbe.calls == 0)
        #expect(try await f.store.fetchWealthContainer(id: original.id)?.originalValue.minorUnits == 20_000)
        #expect(try await f.store.wealthCorrectionHistory(id: original.id).count == 1)
        await model.reloadEdit()
        #expect(!model.requiresEditReload)
        #expect(model.editIntent == .correction)
        #expect(model.editor?.initialDraft.amount == "200")
        changed = try #require(model.editor?.initialDraft)
        changed.amount = "300.00"; model.correctionReason = "Synthetic second intent"
        await model.save(changed)
        #expect(try await f.store.wealthCorrectionHistory(id: original.id).count == 2)
        let requests = await probe.requests
        #expect(requests.count == 2 && requests[0].operationID != requests[1].operationID)
    }

    @Test("Post-commit retry reuses the full request and reads the existing single history")
    func committedRetryIsReadOnly() async throws {
        let f = try WealthFeatureFixture(); defer { f.remove() }
        let original = try await f.seed(0)
        let probe = WealthFeatureWriteProbe(fail: .after)
        let model = f.model(correctionWriter: { try await probe.write($0, store: f.store) })
        await model.loadIfNeeded(); model.selection = original.id; await model.beginEdit()
        var draft = try #require(model.editor?.initialDraft)
        draft.amount = "200.00"; model.correctionReason = "Synthetic durable request"
        await model.save(draft)
        #expect(model.editor != nil && !model.requiresEditReload)
        await model.save(draft)
        #expect(model.editor == nil)
        let requests = await probe.requests
        #expect(requests.count == 2)
        let first = try #require(requests.first), second = try #require(requests.last)
        #expect(first.operationID == second.operationID && first.expected == second.expected)
        #expect(first.candidate == second.candidate && first.reason == second.reason)
        #expect(first.occurredAt == second.occurredAt && first.fxIntent == second.fxIntent)
        #expect(try await f.store.wealthCorrectionHistory(id: original.id).count == 1)
    }

    @Test("Replay after a later change or deletion never overwrites or revives the object",
          arguments: ["changed", "deleted"])
    func replayAfterLaterState(_ branch: String) async throws {
        let f = try WealthFeatureFixture(); defer { f.remove() }
        let original = try await f.seed(0)
        let probe = WealthFeatureWriteProbe(fail: .after)
        let model = f.model(correctionWriter: { try await probe.write($0, store: f.store) })
        await model.loadIfNeeded(); model.selection = original.id; await model.beginEdit()
        var draft = try #require(model.editor?.initialDraft)
        draft.amount = "200.00"; model.correctionReason = "Synthetic earlier request"
        await model.save(draft)
        let committed = try #require(await f.store.fetchWealthContainer(id: original.id))
        if branch == "changed" {
            try await f.store.updateWealthContainer(f.renamed(committed, "Synthetic later writer"))
        } else {
            _ = try await f.store.deleteWealthContainer(id: original.id)
        }
        await model.save(draft)
        #expect(model.requiresEditReload)
        #expect(model.editor != nil)
        #expect(await probe.requests.count == 2)
        if branch == "changed" {
            #expect(try await f.store.fetchWealthContainer(id: original.id)?.container.name == "Synthetic later writer")
        } else {
            #expect(try await f.store.fetchWealthContainer(id: original.id) == nil)
        }
        #expect(try await f.store.wealthCorrectionHistory(id: original.id).filter { $0.kind == "correction" }.count == 1)
    }

    @Test("FX-only normal valuation is explicit and creates no correction history")
    func fxOnlyValuation() async throws {
        let f = try WealthFeatureFixture(); defer { f.remove() }
        let original = try await f.seed(1)
        let model = f.model()
        await model.loadIfNeeded(); model.selection = original.id; await model.beginEdit()
        model.editIntent = .currentValuation
        var draft = try #require(model.editor?.initialDraft)
        draft.fxRate = "7.50"
        await model.save(draft)
        let current = try #require(await f.store.fetchWealthContainer(id: original.id))
        #expect(current.originalValue == original.originalValue)
        #expect(current.valuation.rate.decimal == Decimal(string: "7.5"))
        #expect(current.valuation.fetchedAt == f.instant)
        #expect(try await f.store.wealthCorrectionHistory(id: original.id).isEmpty)
    }

    @Test("History load failure is distinct from an empty history")
    func historyFailureState() async throws {
        let f = try WealthFeatureFixture(); defer { f.remove() }
        let original = try await f.seed(0)
        let model = f.model(historyLoader: { _ in throw WealthFeatureFailure.ambiguous })
        await model.showCorrectionHistory(id: original.id)
        #expect(model.historyLoadState == .failed)
        #expect(model.correctionHistory.isEmpty)
        #expect(model.historyTargetID == original.id)
        model.closeCorrectionHistory()
        #expect(model.historyLoadState == .idle && model.historyTargetID == nil)
    }

    @Test("Duplicate Save is blocked; cancellation and late edit reads cannot revive a form")
    func asyncSessionAndDuplicateSave() async throws {
        let f = try WealthFeatureFixture(); defer { f.remove() }
        let original = try await f.seed(0)
        let gate = WealthFeatureGate()
        let probe = WealthFeatureWriteProbe(fail: .none)
        let model = f.model(correctionWriter: { request in
            await gate.enterAndWait()
            return try await probe.write(request, store: f.store)
        })
        await model.loadIfNeeded(); model.selection = original.id; await model.beginEdit()
        var draft = try #require(model.editor?.initialDraft)
        draft.amount = "200.00"; model.correctionReason = "Synthetic gated"
        let first = Task { await model.save(draft) }
        await gate.waitUntilEntered()
        #expect(model.isSaving)
        await model.save(draft)
        model.cancelEditor()
        #expect(model.editor != nil)
        await gate.release(); await first.value
        #expect(await probe.requests.count == 1)
        #expect(try await f.store.wealthCorrectionHistory(id: original.id).count == 1)

        let readGate = WealthFeatureGate()
        let delayed = f.model(contextLoader: { id in
            await readGate.enterAndWait()
            return try await f.store.readWealthEditContext(id: id)
        })
        await delayed.loadIfNeeded(); delayed.selection = original.id
        let loading = Task { await delayed.beginEdit() }
        await readGate.waitUntilEntered()
        delayed.cancelEditor()
        delayed.beginAdd()
        await readGate.release(); await loading.value
        #expect(delayed.editor?.targetID == nil)
        #expect(delayed.editLoadState == .idle)
    }

    @Test("History is per-object, ordered by sequence and late reads cannot cross selections")
    func historyLoadingAndOrder() async throws {
        let f = try WealthFeatureFixture(); defer { f.remove() }
        let original = try await f.seed(0)
        let other = try await f.seed(1)
        let model = f.model()
        await model.loadIfNeeded(); model.selection = original.id
        for amount in ["200.00", "300.00"] {
            await model.beginEdit()
            var draft = try #require(model.editor?.initialDraft)
            draft.amount = amount; model.correctionReason = "Synthetic sequence"
            await model.save(draft)
        }
        let gate = WealthFeatureGate()
        let reader = f.model(historyLoader: { id in
            if id == original.id { await gate.enterAndWait() }
            return try await f.store.wealthCorrectionHistory(id: id)
        })
        let delayed = Task { await reader.showCorrectionHistory(id: original.id) }
        await gate.waitUntilEntered()
        await reader.showCorrectionHistory(id: other.id)
        await gate.release(); await delayed.value
        #expect(reader.historyTargetID == other.id && reader.correctionHistory.isEmpty)
        reader.closeCorrectionHistory()
        let rows = try await f.store.wealthCorrectionHistory(id: original.id)
        #expect(rows.count == 2 && rows[0].sequence < rows[1].sequence)
        #expect(rows[0].occurredAt == rows[1].occurredAt)
        let before = WealthView.historyProjection(rows[0].payload.before)
        let after = WealthView.historyProjection(try #require(rows[0].payload.after))
        #expect(before.contains("CNY") && after.contains("CNY"))
        #expect(before != after)
        #expect(rows[0].reason == "Synthetic sequence")
    }

    @Test("Uncertain minor and valuation writes require reload rather than a durable replay",
          arguments: [false, true])
    func uncertainNonDurableWrite(_ valuation: Bool) async throws {
        let f = try WealthFeatureFixture(); defer { f.remove() }
        let original = try await f.seed(0)
        let model = f.model(
            correctionWriter: { _ in throw WealthFeatureFailure.ambiguous },
            valuationWriter: { _ in throw WealthFeatureFailure.ambiguous })
        await model.loadIfNeeded(); model.selection = original.id; await model.beginEdit()
        var draft = try #require(model.editor?.initialDraft)
        if valuation {
            model.editIntent = .currentValuation
            draft.amount = "200.00"
        } else { draft.notes = "Synthetic minor" }
        await model.save(draft)
        #expect(model.requiresEditReload)
        #expect(model.editor != nil)
        #expect(try await f.store.fetchWealthContainer(id: original.id) == original)
        await model.reloadEdit()
        #expect(!model.requiresEditReload)
        #expect(model.editor?.initialDraft == WealthEditorDraft(existing: original))
    }
}

private enum WealthFeatureFailure: Error { case ambiguous }

private struct WealthFeatureFixture: @unchecked Sendable {
    let root: URL
    let store: WealthStore
    let instant = UTCInstant(millisecondsSince1970: 1_800_000_000_000)

    init() throws {
        root = try temporaryDirectory()
        store = try WealthStore(databaseURL: root.appendingPathComponent("aureus.sqlite"))
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    func seed(_ index: Int) async throws -> WealthContainer {
        let records = try SyntheticWealthSeeder.records()
        let value: WealthContainer
        if index == 7 {
            let stock = records[2]
            let old = stock.container
            value = try WealthContainer(
                container: AssetContainer(
                    id: UUID(uuidString: "00000000-0000-4000-8000-000000003008")!,
                    accountID: old.accountID,
                    name: "Synthetic ETF fixture",
                    kind: .etf,
                    institution: old.institution,
                    primaryCurrency: old.primaryCurrency,
                    notes: old.notes,
                    createdDate: old.createdDate,
                    updatedDate: old.updatedDate
                ),
                details: stock.details,
                valuation: stock.valuation
            )
        } else {
            value = records[index]
        }
        try await store.createWealthContainer(value)
        return value
    }

    @MainActor
    func model(clock: any Clock = FixedClock(instant: UTCInstant(millisecondsSince1970: 1_800_000_000_000)),
               contextLoader: (@Sendable (UUID) async throws -> WealthEditContext)? = nil,
               historyLoader: (@Sendable (UUID) async throws -> [WealthCorrectionHistory])? = nil,
               correctionWriter: (@Sendable (WealthCorrectionRequest) async throws -> WealthCorrectionResult)? = nil,
               valuationWriter: (@Sendable (WealthCurrentValuationRequest) async throws -> WealthCurrentValuationResult)? = nil)
        -> WealthFeatureModel {
        WealthFeatureModel(store: store, clock: clock, timeZone: TimeZone(secondsFromGMT: 0)!,
            contextLoader: contextLoader, historyLoader: historyLoader,
            correctionWriter: correctionWriter, valuationWriter: valuationWriter)
    }

    func renamed(_ record: WealthContainer, _ name: String) throws -> WealthContainer {
        let c = record.container
        return try WealthContainer(container: AssetContainer(id: c.id, accountID: c.accountID,
            name: name, kind: c.kind, institution: c.institution, primaryCurrency: c.primaryCurrency,
            notes: c.notes, createdDate: c.createdDate, updatedDate: c.updatedDate),
            details: record.details, valuation: record.valuation)
    }
}

private final class WealthFeatureMutableClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: UTCInstant
    init(_ instant: UTCInstant) { self.instant = instant }
    func now() -> UTCInstant { lock.withLock { instant } }
    func set(_ next: UTCInstant) { lock.withLock { instant = next } }
}

private actor WealthFeatureWriteProbe {
    enum Failure { case none, before, after }
    let fail: Failure
    private var first = true
    private(set) var requests: [WealthCorrectionRequest] = []
    init(fail: Failure) { self.fail = fail }
    func write(_ request: WealthCorrectionRequest, store: WealthStore) async throws -> WealthCorrectionResult {
        requests.append(request)
        if first {
            first = false
            if fail == .before { throw WealthFeatureFailure.ambiguous }
        }
        let result = try await store.correctWealthContainer(request)
        if fail == .after && requests.count == 1 { throw WealthFeatureFailure.ambiguous }
        return result
    }
}

private actor WealthFeatureValuationProbe {
    private(set) var calls = 0
    func write(_ request: WealthCurrentValuationRequest, store: WealthStore)
        async throws -> WealthCurrentValuationResult {
        calls += 1
        return try await store.recordCurrentValuation(request)
    }
}

private actor WealthFeatureGate {
    private var entered = false
    private var released = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    func enterAndWait() async {
        entered = true
        enteredWaiter?.resume(); enteredWaiter = nil
        if released { return }
        await withCheckedContinuation { releaseWaiter = $0 }
    }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }
    func release() {
        released = true
        releaseWaiter?.resume(); releaseWaiter = nil
    }
}
