import Foundation
import GRDB
import Testing
@testable import Aureus

@MainActor
@Suite("Ledger correction edit integration", .serialized)
struct LedgerCorrectionFeatureTests {
    @Test("Create remains an ordinary Ledger insertion without a reason or history")
    func createIsUnchanged() async throws {
        let f = try FeatureFixture(); defer { f.remove() }
        try await f.seedContainers()
        let model = f.model()
        await model.load()
        model.beginCreate()
        model.draft.description = "Synthetic new income"
        model.draft.sourceAmount = "25.00"
        #expect(model.canSaveForm)
        await model.save()
        let entry = try #require(await f.store.fetchLedgerEntries().first)
        #expect(entry.description == "Synthetic new income")
        #expect(try await f.store.ledgerCorrectionHistory(id: entry.id).isEmpty)
        #expect(model.formMode == nil)
    }

    @Test("CNY USD and transfer important edits use the typed transaction", arguments: ["CNY", "USD", "transfer"])
    func importantEditRoundTrip(_ mode: String) async throws {
        let f = try FeatureFixture(); defer { f.remove() }
        let original = try await f.seedEntry(mode: mode)
        let model = f.model()
        await model.load()
        await model.beginEdit(id: original.id)
        #expect(model.editLoadState == .ready)
        model.draft.sourceAmount = "200.00"
        if mode == "transfer" { model.draft.targetAmount = "75.00" }
        #expect(model.needsCorrectionReason)
        #expect(!model.canSaveForm)
        model.correctionReason = "Synthetic amount correction"
        await model.save()
        let current = try #require(await f.store.fetchLedgerEntries().first)
        let history = try await f.store.ledgerCorrectionHistory(id: original.id)
        #expect(current.id == original.id && current.recordedAt == original.recordedAt)
        #expect(current.postings.map(\.id) == original.postings.map(\.id))
        #expect(history.count == 1)
        #expect(history.first?.payload.before == LedgerCorrectionProjection(original))
        #expect(history.first?.payload.after == LedgerCorrectionProjection(current))
        #expect(history.first?.reason == "Synthetic amount correction")
        let summary = try await f.store.ledgerSummary()
        if mode == "transfer" {
            #expect(summary.transferCount == 1 && summary.netCashFlowCNY.minorUnits == 0)
            #expect(current.transferTarget?.valuation.original.minorUnits == 7500)
        } else {
            #expect(summary.ordinaryInflowCNY == current.primaryPosting?.valuation.convertedCNY)
            if mode == "USD" {
                #expect(current.primaryPosting?.valuation.providerIdentifier == original.primaryPosting?.valuation.providerIdentifier)
                #expect(current.primaryPosting?.valuation.referenceDate == original.primaryPosting?.valuation.referenceDate)
                #expect(current.primaryPosting?.valuation.fetchedAt == original.primaryPosting?.valuation.fetchedAt)
            }
        }
    }

    @Test("Reopened nondefault USD FX provenance survives no-op auxiliary and description edits")
    func fxProvenanceSurvives() async throws {
        let f = try FeatureFixture(); defer { f.remove() }
        let original = try await f.seedEntry(mode: "USD")
        let category = try await f.store.createCategory(name: "Synthetic category")
        let tag = try await f.store.createTag(name: "Synthetic tag")
        let model = f.model()
        await model.load()
        for step in ["none", "note", "taxonomy", "description"] {
            await model.beginEdit(id: original.id)
            if step == "note" { model.draft.note = "Synthetic note" }
            if step == "taxonomy" {
                model.draft.categoryID = category.id
                model.draft.tagIDs.insert(tag.id)
            }
            if step == "description" {
                model.draft.description = "Synthetic corrected description"
                model.correctionReason = "Synthetic description correction"
            }
            await model.save()
            let current = try #require(await f.store.fetchLedgerEntries().first)
            #expect(current.primaryPosting?.valuation == original.primaryPosting?.valuation)
            #expect(current.primaryPosting?.id == original.primaryPosting?.id)
            #expect(current.recordedAt == original.recordedAt)
            #expect(try await f.store.ledgerCorrectionHistory(id: original.id).count == (step == "description" ? 1 : 0))
        }
    }

    @Test("Both transfer postings retain independent FX context when their inputs are unchanged")
    func transferFXPreservedSeparately() async throws {
        let f = try FeatureFixture(); defer { f.remove() }
        let original = try await f.seedEntry(mode: "transfer")
        let model = f.model()
        await model.load()
        await model.beginEdit(id: original.id)
        model.draft.description = "Synthetic transfer description correction"
        model.correctionReason = "Synthetic description correction"
        await model.save()
        let current = try #require(await f.store.fetchLedgerEntries().first)
        #expect(current.transferSource?.valuation == original.transferSource?.valuation)
        #expect(current.transferTarget?.valuation == original.transferTarget?.valuation)
        #expect(current.transferSource?.id == original.transferSource?.id)
        #expect(current.transferTarget?.id == original.transferTarget?.id)
        #expect(try await f.store.ledgerCorrectionHistory(id: original.id).count == 1)
    }

    @Test("Numeric-equivalent input and import fingerprint do not create a false update")
    func fingerprintNoChange() async throws {
        let f = try FeatureFixture(); defer { f.remove() }
        let original = try await f.seedEntry(mode: "CNY", fingerprint: "synthetic-import-fingerprint")
        let before = try await f.store.readLedgerEditContext(id: original.id)
        let model = f.model()
        await model.load()
        await model.beginEdit(id: original.id)
        model.draft.sourceAmount = "100.000"
        await model.save()
        let after = try await f.store.readLedgerEditContext(id: original.id)
        #expect(after.token.stateDigest == before.token.stateDigest)
        #expect(after.entry.importFingerprint == original.importFingerprint)
        #expect(after.entry.recordedAt == original.recordedAt)
        #expect(try await f.store.ledgerCorrectionHistory(id: original.id).isEmpty)
    }

    @Test("Only important changes require a valid user-supplied reason")
    func reasonValidation() async throws {
        let f = try FeatureFixture(); defer { f.remove() }
        let original = try await f.seedEntry()
        let model = f.model()
        await model.load()
        await model.beginEdit(id: original.id)
        model.draft.description = "Synthetic corrected"
        for invalid in ["", "   ", "bad\0reason", String(repeating: "a", count: 501)] {
            model.correctionReason = invalid
            #expect(!model.canSaveForm)
            await model.save()
            #expect(model.formMode == .edit(original.id))
            #expect(try await f.store.ledgerCorrectionHistory(id: original.id).isEmpty)
        }
        model.correctionReason = "  Synthetic reason  "
        #expect(model.canSaveForm)
        await model.save()
        #expect(try await f.store.ledgerCorrectionHistory(id: original.id).first?.reason == "Synthetic reason")
    }

    @Test("Two feature drafts and the legacy writer cannot silently overwrite current facts")
    func staleDraftAndLegacyWriter() async throws {
        let f = try FeatureFixture(); defer { f.remove() }
        let original = try await f.seedEntry()
        let first = f.model(), second = f.model()
        await first.load(); await second.load()
        await first.beginEdit(id: original.id); await second.beginEdit(id: original.id)
        first.draft.description = "Synthetic first"
        first.correctionReason = "Synthetic first reason"
        await first.save()
        second.draft.description = "Synthetic stale"
        second.correctionReason = "Synthetic stale reason"
        await second.save()
        #expect(second.requiresEditReload)
        #expect(second.formMode == .edit(original.id))
        #expect(second.draft.description == "Synthetic stale")
        #expect(try await f.store.fetchLedgerEntries().first?.description == "Synthetic first")
        await second.reloadEdit()
        #expect(second.draft.description == "Synthetic first")
        let live = try #require(await f.store.fetchLedgerEntries().first)
        let legacy = try f.rebuild(live, description: "Synthetic legacy writer")
        try await f.store.updateLedgerEntry(legacy)
        second.draft.description = "Synthetic attempted overwrite"
        second.correctionReason = "Synthetic retry reason"
        await second.save()
        #expect(second.requiresEditReload)
        #expect(try await f.store.fetchLedgerEntries().first?.description == "Synthetic legacy writer")
    }

    @Test("An ambiguous post-commit error retries the frozen request only once")
    func committedRetryReusesRequest() async throws {
        let f = try FeatureFixture(); defer { f.remove() }
        let original = try await f.seedEntry()
        let probe = FeatureWriteProbe()
        let model = LedgerFeatureModel(store: f.store, clock: f.clock,
            correctionWriter: { request in try await probe.writeThenFailOnce(request, store: f.store) })
        await model.load()
        await model.beginEdit(id: original.id)
        model.draft.description = "Synthetic committed"
        model.correctionReason = "Synthetic durable retry"
        await model.save()
        #expect(model.formMode == .edit(original.id))
        #expect(model.editFeedback != nil)
        await model.save()
        #expect(model.formMode == nil)
        let ids = await probe.operationIDs
        #expect(ids.count == 2 && ids.first == ids.last)
        #expect(try await f.store.ledgerCorrectionHistory(id: original.id).count == 1)
    }

    @Test("A second save while the first is blocked cannot submit another operation")
    func duplicateSaveIsBlocked() async throws {
        let f = try FeatureFixture(); defer { f.remove() }
        let original = try await f.seedEntry()
        let gate = FeatureGate()
        let probe = FeatureWriteProbe()
        let model = LedgerFeatureModel(store: f.store, clock: f.clock,
            correctionWriter: { request in
                await gate.enterAndWait()
                return try await probe.write(request, store: f.store)
            })
        await model.load(); await model.beginEdit(id: original.id)
        model.draft.description = "Synthetic one write"
        model.correctionReason = "Synthetic one reason"
        let first = Task { await model.save() }
        await gate.waitUntilEntered()
        #expect(model.isSaving)
        await model.save()
        await gate.release()
        await first.value
        let ids = await probe.operationIDs
        #expect(ids.count == 1)
        #expect(try await f.store.ledgerCorrectionHistory(id: original.id).count == 1)
    }

    @Test("Cancel or switching forms invalidates a delayed edit read")
    func cancelInvalidatesDelayedEdit() async throws {
        let f = try FeatureFixture(); defer { f.remove() }
        let original = try await f.seedEntry()
        let gate = FeatureGate()
        let model = LedgerFeatureModel(store: f.store, clock: f.clock,
            contextLoader: { id in
                await gate.enterAndWait()
                return try await f.store.readLedgerEditContext(id: id)
            })
        await model.load()
        let task = Task { await model.beginEdit(id: original.id) }
        await gate.waitUntilEntered()
        #expect(model.editLoadState == .loading)
        model.cancelForm()
        model.beginCreate()
        await gate.release()
        await task.value
        #expect(model.formMode == .create)
        #expect(model.editLoadState == .idle)
        #expect(model.draft.description.isEmpty)
    }

    @Test("Real history INSERT failure leaves the draft and database intact, then retries identically")
    func databaseFailureAndRetry() async throws {
        let f = try FeatureFixture(); defer { f.remove() }
        let original = try await f.seedEntry()
        let before = try await f.store.readLedgerEditContext(id: original.id)
        let model = f.model()
        await model.load(); await model.beginEdit(id: original.id)
        model.draft.description = "Synthetic failed update"
        model.correctionReason = "Synthetic failure reason"
        try f.write("CREATE TRIGGER synthetic_feature_failure BEFORE INSERT ON ledger_correction_history BEGIN SELECT RAISE(ABORT,'synthetic-feature-reached'); END")
        await model.save()
        #expect(model.formMode == .edit(original.id))
        #expect(model.editFeedback != nil)
        #expect(try await f.store.readLedgerEditContext(id: original.id).token.stateDigest == before.token.stateDigest)
        #expect(try await f.store.ledgerCorrectionHistory(id: original.id).isEmpty)
        try f.write("DROP TRIGGER synthetic_feature_failure")
        await model.save()
        #expect(try await f.store.ledgerCorrectionHistory(id: original.id).count == 1)
    }

    @Test("History loading is ordered, empty when absent, and ignores a late prior selection")
    func historyReadAndSwitch() async throws {
        let f = try FeatureFixture(); defer { f.remove() }
        let first = try await f.seedEntry()
        let second = try f.rebuild(first, id: UUID(), description: "Synthetic second")
        try await f.store.createLedgerEntry(second)
        let context = try await f.store.readLedgerEditContext(id: second.id)
        _ = try await f.store.correctLedgerEntry(.init(candidate: f.rebuild(second, description: "Synthetic second correction"),
            expected: context.token, operationID: UUID(), reason: "Synthetic history", occurredAt: f.context.instant))
        let gate = FeatureGate()
        let model = LedgerFeatureModel(store: f.store, clock: f.clock,
            historyLoader: { id in
                if id == first.id { await gate.enterAndWait() }
                return try await f.store.ledgerCorrectionHistory(id: id)
            })
        let delayed = Task { await model.showCorrectionHistory(id: first.id) }
        await gate.waitUntilEntered()
        await model.showCorrectionHistory(id: second.id)
        await gate.release()
        await delayed.value
        #expect(model.historyTargetID == second.id)
        #expect(model.historyLoadState == .ready)
        #expect(model.correctionHistory.count == 1)
        #expect(model.correctionHistory.first?.targetID == second.id)
        model.closeCorrectionHistory()
        #expect(model.correctionHistory.isEmpty)
        await model.showCorrectionHistory(id: first.id)
        #expect(model.historyLoadState == .ready && model.correctionHistory.isEmpty)
    }

    @Test("History read failure is explicit and cannot display a prior selection")
    func historyFailureIsVisible() async throws {
        let f = try FeatureFixture(); defer { f.remove() }
        let original = try await f.seedEntry()
        let model = LedgerFeatureModel(store: f.store, clock: f.clock,
            historyLoader: { _ in throw FeatureSyntheticFailure.afterCommit })
        await model.showCorrectionHistory(id: original.id)
        #expect(model.historyTargetID == original.id)
        #expect(model.historyLoadState == .failed)
        #expect(model.correctionHistory.isEmpty)
    }

    @Test("Edit context taxonomy survives a stale list and explicit clearing still works", arguments: ["none", "note", "description", "clear"])
    func taxonomyFromLatestEditContext(_ branch: String) async throws {
        let f = try FeatureFixture(); defer { f.remove() }
        let original = try await f.seedEntry()
        let model = f.model()
        await model.load() // Deliberately older than the Store edit context.
        let category = try await f.store.createCategory(name: "Synthetic late category")
        let tag = try await f.store.createTag(name: "Synthetic late tag")
        try await f.store.updateLedgerEntry(f.withTaxonomy(original, category: category, tags: [tag]))
        await model.beginEdit(id: original.id)
        #expect(model.editLoadState == .ready)
        #expect(model.draft.categoryID == category.id)
        #expect(model.draft.tagIDs == [tag.id])
        #expect(model.formCategories.contains(where: { $0.id == category.id }))
        #expect(model.formTags.contains(where: { $0.id == tag.id }))
        if branch == "note" { model.draft.note = "Synthetic changed note" }
        if branch == "description" {
            model.draft.description = "Synthetic important description"
            model.correctionReason = "Synthetic reason"
        }
        if branch == "clear" {
            model.draft.categoryID = nil
            model.draft.tagIDs.remove(tag.id)
        }
        await model.save()
        #expect(model.formMode == nil)
        let saved = try #require(await f.store.fetchLedgerEntries().first)
        if branch == "clear" {
            #expect(saved.category == nil && saved.tags.isEmpty)
        } else {
            #expect(saved.category?.id == category.id)
            #expect(saved.tags.map(\.id) == [tag.id])
        }
        #expect(saved.note == (branch == "note" ? "Synthetic changed note" : nil))
        #expect(try await f.store.ledgerCorrectionHistory(id: original.id).count == (branch == "description" ? 1 : 0))
    }

    @Test("A newly entered FX uses the fixed submission clock, not the old transaction time", arguments: ["rate", "currency", "transfer"])
    func newFXUsesSubmissionTime(_ branch: String) async throws {
        let f = try FeatureFixture(); defer { f.remove() }
        let original = try await f.seedEntry(mode: branch == "rate" ? "USD" : branch)
        let model = f.model()
        await model.load(); await model.beginEdit(id: original.id)
        if branch == "transfer" { model.draft.targetFXRate = "7.50" }
        else {
            if branch == "currency" { model.draft.sourceCurrency = .usd }
            model.draft.sourceFXRate = "7.50"
        }
        model.correctionReason = "Synthetic FX correction"
        await model.save()
        #expect(model.formMode == nil)
        let saved = try #require(await f.store.fetchLedgerEntries().first)
        let changed = branch == "transfer" ? saved.transferTarget : saved.primaryPosting
        #expect(saved.recordedAt == original.recordedAt)
        #expect(changed?.valuation.fetchedAt == f.clock.instant)
        #expect(changed?.valuation.fetchedAt != original.recordedAt)
        #expect(try await f.store.ledgerCorrectionHistory(id: original.id).first?.occurredAt == f.clock.instant)
        if branch == "transfer" {
            #expect(saved.transferSource?.valuation == original.transferSource?.valuation)
        }
    }

    @Test("A hidden unused reason cannot block retrying the same minor write")
    func pendingMinorRetryIgnoresHiddenReason() async throws {
        let f = try FeatureFixture(); defer { f.remove() }
        let original = try await f.seedEntry()
        let probe = FeaturePrecommitProbe()
        let clock = FeatureMutableClock(f.clock.instant)
        let model = LedgerFeatureModel(store: f.store, clock: clock,
            correctionWriter: { request in try await probe.writeFailingFirst(request, store: f.store) })
        await model.load(); await model.beginEdit(id: original.id)
        model.draft.description = "Temporary important change"
        model.correctionReason = "Hidden unused reason"
        model.draft.description = original.description
        model.draft.note = "Synthetic minor change"
        #expect(!model.needsCorrectionReason)
        await model.save() // Synthetic failure before Store commit.
        #expect(model.formMode == .edit(original.id))
        clock.set(UTCInstant(millisecondsSince1970: f.clock.instant.millisecondsSince1970 + 100_000))
        await model.save()
        #expect(model.formMode == nil)
        let requests = await probe.requests
        #expect(requests.count == 2)
        let first = try #require(requests.first), second = try #require(requests.last)
        #expect(first.operationID == second.operationID)
        #expect(first.expected == second.expected)
        #expect(first.reason == second.reason && first.reason.isEmpty)
        #expect(first.occurredAt == second.occurredAt && first.occurredAt == f.clock.instant)
        #expect(try LedgerCorrectionEncoding.data(LedgerCorrectionEncoding.Candidate(first.candidate))
            == LedgerCorrectionEncoding.data(LedgerCorrectionEncoding.Candidate(second.candidate)))
        let saved = try #require(await f.store.fetchLedgerEntries().first)
        #expect(saved.note == "Synthetic minor change")
        #expect(try await f.store.ledgerCorrectionHistory(id: original.id).isEmpty)
    }

    @Test("Changing pending payload or important reason exposes an explicit reload", arguments: ["draft", "reason"])
    func changedPendingIntentRequiresReload(_ branch: String) async throws {
        let f = try FeatureFixture(); defer { f.remove() }
        let original = try await f.seedEntry()
        let probe = FeaturePrecommitProbe()
        let model = LedgerFeatureModel(store: f.store, clock: f.clock,
            correctionWriter: { request in try await probe.writeFailingFirst(request, store: f.store) })
        await model.load(); await model.beginEdit(id: original.id)
        model.draft.description = "Synthetic first intent"
        model.correctionReason = "Synthetic first reason"
        await model.save()
        if branch == "draft" { model.draft.description = "Synthetic changed intent" }
        else { model.correctionReason = "Synthetic changed reason" }
        await model.save()
        #expect(model.requiresEditReload)
        #expect(model.formMode == .edit(original.id))
        #expect(model.draft.description == (branch == "draft" ? "Synthetic changed intent" : "Synthetic first intent"))
        #expect(await probe.requests.count == 1)
        #expect(try await f.store.fetchLedgerEntries().first?.description == original.description)
        await model.reloadEdit() // Explicit discard and fresh Store context.
        #expect(!model.requiresEditReload)
        #expect(model.draft.description == original.description)
        #expect(model.correctionReason.isEmpty)
        model.draft.description = "Synthetic new request"
        model.correctionReason = "Synthetic new reason"
        await model.save()
        let requests = await probe.requests
        #expect(requests.count == 2 && requests[0].operationID != requests[1].operationID)
        #expect(try await f.store.fetchLedgerEntries().first?.description == "Synthetic new request")
    }

    @Test("New FX timestamp and the entire candidate stay fixed across a precommit retry")
    func newFXRequestIsFrozenAcrossRetry() async throws {
        let f = try FeatureFixture(); defer { f.remove() }
        let original = try await f.seedEntry(mode: "USD")
        let probe = FeaturePrecommitProbe()
        let clock = FeatureMutableClock(f.clock.instant)
        let model = LedgerFeatureModel(store: f.store, clock: clock,
            correctionWriter: { request in try await probe.writeFailingFirst(request, store: f.store) })
        await model.load(); await model.beginEdit(id: original.id)
        model.draft.sourceFXRate = "7.50"
        model.correctionReason = "Synthetic new FX retry"
        await model.save()
        clock.set(UTCInstant(millisecondsSince1970: f.clock.instant.millisecondsSince1970 + 100_000))
        await model.save()
        let requests = await probe.requests
        #expect(requests.count == 2)
        let first = try #require(requests.first), second = try #require(requests.last)
        #expect(first.operationID == second.operationID && first.expected == second.expected)
        #expect(first.reason == second.reason && first.occurredAt == second.occurredAt)
        #expect(try LedgerCorrectionEncoding.data(LedgerCorrectionEncoding.Candidate(first.candidate))
            == LedgerCorrectionEncoding.data(LedgerCorrectionEncoding.Candidate(second.candidate)))
        #expect(first.candidate.primaryPosting?.valuation.fetchedAt == f.clock.instant)
        #expect(first.occurredAt == f.clock.instant)
        let current = try #require(await f.store.fetchLedgerEntries().first)
        #expect(current.primaryPosting?.valuation.fetchedAt == f.clock.instant)
        #expect(current.recordedAt == original.recordedAt)
        #expect(try await f.store.ledgerCorrectionHistory(id: original.id).count == 1)
    }

    @Test("The actual read-only history formatter distinguishes a container-only correction")
    func historyFormatterShowsStableContainerIDs() async throws {
        let f = try FeatureFixture(); defer { f.remove() }
        let original = try await f.seedEntry()
        let source = try #require(original.primaryPosting)
        let moved = try LedgerPosting(id: source.id, role: source.role,
            containerID: f.context.target.id, valuation: source.valuation)
        let changed = try LedgerEntry(id: original.id, kind: original.kind,
            civilDate: original.civilDate, recordedAt: original.recordedAt,
            description: original.description, payee: original.payee,
            category: original.category, tags: original.tags, postings: [moved],
            note: original.note, importFingerprint: original.importFingerprint)
        let before = LedgerView.historyProjection(LedgerCorrectionProjection(original))
        let after = LedgerView.historyProjection(LedgerCorrectionProjection(changed))
        #expect(before.contains(f.context.source.id.uuidString))
        #expect(after.contains(f.context.target.id.uuidString))
        #expect(!before.contains(f.context.target.id.uuidString))
        #expect(!after.contains(f.context.source.id.uuidString))
        #expect(before != after)
    }
}

private struct FeatureFixture: @unchecked Sendable {
    let root: URL
    let database: URL
    let store: WealthStore
    let context: LedgerTestContext
    let clock: FixedClock

    init() throws {
        root = try temporaryDirectory()
        database = root.appendingPathComponent("aureus.sqlite")
        store = try WealthStore(databaseURL: database)
        let testingContext = try LedgerTestContext.make()
        context = testingContext
        clock = FixedClock(instant: UTCInstant(millisecondsSince1970: testingContext.instant.millisecondsSince1970 + 10_000))
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    @MainActor func model() -> LedgerFeatureModel { LedgerFeatureModel(store: store, clock: clock) }

    func seedContainers() async throws {
        try await store.createWealthContainer(context.source)
        try await store.createWealthContainer(context.target)
    }

    func seedEntry(mode: String = "CNY", fingerprint: String? = nil) async throws -> LedgerEntry {
        try await seedContainers()
        let source = try posting(role: mode == "transfer" ? .transferSource : .primary,
            containerID: context.source.id, currency: mode == "USD" ? .usd : .cny, amount: "100.00",
            provider: mode == "USD" ? "manual.reference.synthetic" : "identity")
        var postings = [source]
        if mode == "transfer" {
            postings.append(try posting(role: .transferTarget, containerID: context.target.id,
                currency: .usd, amount: "50.00", provider: "manual.transfer.synthetic"))
        }
        let entry = try LedgerEntry(kind: mode == "transfer" ? .transfer : .income, civilDate: context.date,
            recordedAt: context.instant, description: "Synthetic original", postings: postings,
            importFingerprint: fingerprint)
        try await store.createLedgerEntry(entry)
        return entry
    }

    func posting(role: LedgerPostingRole, containerID: UUID, currency: CurrencyCode,
                 amount: String, provider: String) throws -> LedgerPosting {
        let money = try Money(decimal: FixedPointMath.parseCanonical(amount), currency: currency)
        let rate = currency == .cny ? FXRate.cnyIdentity
            : try FXRate(decimal: FixedPointMath.parseCanonical("7.25"), sourceCurrency: .usd, targetCurrency: .cny)
        let valuation = try FXValuation(original: money, rate: rate,
            referenceDate: try CivilDate(canonical: "2026-07-01"),
            fetchedAt: UTCInstant(millisecondsSince1970: context.instant.millisecondsSince1970 - 50_000),
            providerIdentifier: provider, isManualOverride: currency == .usd, isStale: currency == .usd)
        return try LedgerPosting(role: role, containerID: containerID, valuation: valuation)
    }

    func rebuild(_ entry: LedgerEntry, id: UUID? = nil, description: String) throws -> LedgerEntry {
        let targetID = id ?? entry.id
        let postings = targetID == entry.id ? entry.postings : try entry.postings.map {
            try LedgerPosting(role: $0.role, containerID: $0.containerID, valuation: $0.valuation)
        }
        return try LedgerEntry(id: targetID, kind: entry.kind, civilDate: entry.civilDate,
            recordedAt: entry.recordedAt, description: description, payee: entry.payee,
            category: entry.category, tags: entry.tags, postings: postings,
            note: entry.note, importFingerprint: entry.importFingerprint)
    }

    func withTaxonomy(_ entry: LedgerEntry, category: Aureus.Category?, tags: [Aureus.Tag]) throws -> LedgerEntry {
        try LedgerEntry(id: entry.id, kind: entry.kind, civilDate: entry.civilDate,
            recordedAt: entry.recordedAt, description: entry.description, payee: entry.payee,
            category: category, tags: tags, postings: entry.postings,
            note: entry.note, importFingerprint: entry.importFingerprint)
    }

    func write(_ sql: String) throws {
        let queue = try DatabaseQueueFactory.open(at: database)
        defer { try? queue.close() }
        try queue.write { try $0.execute(sql: sql) }
    }
}

private enum FeatureSyntheticFailure: Error { case afterCommit }

private final class FeatureMutableClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: UTCInstant
    init(_ instant: UTCInstant) { self.instant = instant }
    func now() -> UTCInstant { lock.withLock { instant } }
    func set(_ next: UTCInstant) { lock.withLock { instant = next } }
}

private actor FeaturePrecommitProbe {
    private(set) var requests: [LedgerCorrectionRequest] = []
    private var failFirst = true
    func writeFailingFirst(_ request: LedgerCorrectionRequest, store: WealthStore) async throws -> LedgerCorrectionResult {
        requests.append(request)
        if failFirst {
            failFirst = false
            throw FeatureSyntheticFailure.afterCommit
        }
        return try await store.correctLedgerEntry(request)
    }
}

private actor FeatureWriteProbe {
    private(set) var operationIDs: [UUID] = []
    private var shouldFailAfterCommit = true

    func write(_ request: LedgerCorrectionRequest, store: WealthStore) async throws -> LedgerCorrectionResult {
        operationIDs.append(request.operationID)
        return try await store.correctLedgerEntry(request)
    }

    func writeThenFailOnce(_ request: LedgerCorrectionRequest, store: WealthStore) async throws -> LedgerCorrectionResult {
        let result = try await write(request, store: store)
        if shouldFailAfterCommit {
            shouldFailAfterCommit = false
            throw FeatureSyntheticFailure.afterCommit
        }
        return result
    }
}

private actor FeatureGate {
    private var entered = false
    private var released = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func enterAndWait() async {
        entered = true
        enteredWaiter?.resume()
        enteredWaiter = nil
        if released { return }
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
