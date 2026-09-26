import AppKit
import XCTest

final class AureusUITests: XCTestCase {
    private enum AnalyticsViewportRelation: String {
        case aboveViewport
        case insideViewport
        case belowViewport
        case outsideScrollRegion
        case notExposed
        case invalidFrame
    }

    private struct AnalyticsViewportSnapshot {
        let relation: AnalyticsViewportRelation
        let midY: CGFloat?
        let height: CGFloat?
    }

    private struct AnalyticsDetailContractEvidence {
        let matchCount: Int
        let labelMatched: Bool
        let viewportRelation: AnalyticsViewportRelation
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testStage11SettingsCacheAuditFieldsCapacityAndReset() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments(demo: true) + ["--aureus-settings-cache-audit"]
        launchApp(app)
        defer { app.terminate() }
        app.descendants(matching: .any)["sidebar.settings"].click()
        assertCacheAuditFields(in: app, checkpoint: "initial", maximumMiB: 512, populated: true,
            cleanup: "sessionOnlyPolicy: removed 0 recoverable entries")
        assertCacheAuditLabel(in: app, checkpoint: "initial.legacy", identifier: "settings.cache.freshness", expected:
            "Authorized Persistent Market Cache: Legacy only. As of 2026-01-15 00:00:00.000 UTC. "
            + "2 total entries; 0 TTL-classified; 0 within TTL; 0 expired; 2 legacy. "
            + "Offline coverage depends on the requested data and existing authorization. "
            + "Legacy entries do not establish Twelve Data V1 offline availability. "
            + "TTL does not prove market real-time freshness or entitlement.")
        selectPicker(app: app, identifier: "settings.cache.maximum", title: "256 MiB")
        app.descendants(matching: .any)["settings.cache.apply"].click()
        assertCacheAuditFields(in: app, checkpoint: "capacity256", maximumMiB: 256, populated: true,
            cleanup: "capacityChange: removed 0 recoverable entries")
        app.descendants(matching: .any)["settings.cache.reset"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.cache.reset.confirm"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["settings.cache.reset.confirm"].click()
        assertCacheAuditFields(in: app, checkpoint: "reset", maximumMiB: 512, populated: false, cleanup: "Not run")
        app.descendants(matching: .any)["sidebar.dashboard"].click()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.content"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["sidebar.settings"].click()
        assertCacheAuditFields(in: app, checkpoint: "returned", maximumMiB: 512, populated: false, cleanup: "Not run")
        XCTAssertFalse(app.descendants(matching: .any)["settings.error"].exists)
    }

    @MainActor
    private func assertCacheAuditLabel(in app: XCUIApplication, checkpoint: String,
                                      identifier: String, expected: String) {
        // Diagnostic output is restricted to this synthetic audit's six fields.
        let allowed = ["settings.cache.summary", "settings.cache.oldestEntry",
            "settings.cache.lastCleanupAt", "settings.cache.provider.synthetic.stage2.market",
            "settings.cache.providers.empty", "settings.cache.freshness"]
        precondition(allowed.contains(identifier))
        func bounded(_ text: String) -> [String: Any] {
            let limit = 1_024
            return ["text": String(String.UnicodeScalarView(text.unicodeScalars.prefix(limit))),
                    "truncated": text.unicodeScalars.count > limit,
                    "scalarCount": text.unicodeScalars.count]
        }
        var sequence = 0
        var first: [String: Any]?
        var last: [String: Any]?
        var changes: [[String: Any]] = []
        var discardedChanges = 0
        var priorCount: Int?
        var priorLabel: String?
        var priorEqual: Bool?
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let matches = app.descendants(matching: .any).matching(identifier: identifier)
            let count = matches.count
            let actualLabel = count == 1 ? matches.element.label : nil
            let countIsOne = count == 1
            let labelEqualsExpected = actualLabel.map { $0 == expected }
            let predicateResult = countIsOne && labelEqualsExpected == true
            sequence += 1
            let retainedLabel = actualLabel.map {
                String(String.UnicodeScalarView($0.unicodeScalars.prefix(1_024)))
            }
            let sample: [String: Any] = [
                "source": "predicate", "sequence": sequence, "count": count,
                "label": actualLabel.map(bounded) ?? ["text": "NOT QUERIED",
                    "reason": "nonUniqueOrMissing", "truncated": false],
                "expected": bounded(expected), "countIsOne": countIsOne,
                "labelEqualsExpected": labelEqualsExpected.map { $0 as Any } ?? NSNull(),
                "predicateResult": predicateResult
            ]
            if first == nil {
                first = sample
            } else if priorCount != count || priorLabel != retainedLabel || priorEqual != labelEqualsExpected {
                if changes.count < 6 { changes.append(sample) } else { discardedChanges += 1 }
            }
            last = sample
            priorCount = count
            priorLabel = retainedLabel
            priorEqual = labelEqualsExpected
            return predicateResult
        }, object: app)
        let waitResult = XCTWaiter.wait(for: [expectation], timeout: 5)
        // These are separate, once-only post-wait observations, not predicate samples.
        func supplemental(_ query: XCUIElementQuery) -> [String: Any] {
            let count = query.count
            guard count == 1 else {
                return ["count": count, "label": "NOT QUERIED", "reason": "nonUniqueOrMissing"]
            }
            let element = query.element
            return ["count": count, "identifier": bounded(element.identifier),
                    "elementType": element.elementType.rawValue, "label": bounded(element.label),
                    "stringValue": (element.value as? String).map(bounded)
                        ?? ["text": "NOT STRING", "truncated": false]]
        }
        let originalPostWait = supplemental(app.descendants(matching: .any).matching(identifier: identifier))
        let exactPostWait = supplemental(app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@", identifier)))
        let presence = ["mode.demo", "mode.local", "settings.error"].reduce(into: [String: Int]()) {
            $0[$1] = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", $1)).count
        }
        let record: [String: Any] = [
            "checkpoint": checkpoint, "identifier": identifier, "waitResult": waitResult.rawValue,
            "expected": bounded(expected), "first": first as Any? ?? NSNull(),
            "last": last as Any? ?? NSNull(), "changes": changes,
            "sampleCount": sequence, "discardedChanges": discardedChanges,
            "stateComparisonLimitScalars": 1_024,
            "supplementalSource": "afterWaitBeforeAssertion",
            "originalPostWait": originalPostWait, "exactIdentifierPostWait": exactPostWait,
            "presenceOnly": presence
        ]
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            print("AUREUS_CACHE_AX_OBSERVATION \(json)")
            let attachment = XCTAttachment(string: json)
            attachment.name = "AUREUS_CACHE_AX_OBSERVATION.\(checkpoint).\(identifier)"
            attachment.lifetime = .keepAlways
            add(attachment)
        } else {
            print("AUREUS_CACHE_AX_OBSERVATION {\"serializationFailed\":true}")
        }
        XCTAssertEqual(waitResult, .completed)
        let matches = app.descendants(matching: .any).matching(identifier: identifier)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.element.label, expected)
    }

    @MainActor
    private func assertCacheAuditFields(in app: XCUIApplication, checkpoint: String, maximumMiB: Int64,
                                       populated: Bool, cleanup: String) {
        let bytes = ByteCountFormatter.string(fromByteCount: populated ? 768 : 0, countStyle: .binary)
        let capacity = ByteCountFormatter.string(fromByteCount: maximumMiB * 1_048_576, countStyle: .binary)
        assertCacheAuditLabel(in: app, checkpoint: checkpoint, identifier: "settings.cache.summary", expected:
            "Authorized Persistent Market Cache. Current usage \(bytes). Capacity \(capacity). "
            + "Usage 0 percent. Entries \(populated ? 2 : 0). Last cleanup \(cleanup).")
        assertCacheAuditLabel(in: app, checkpoint: checkpoint, identifier: "settings.cache.oldestEntry", expected:
            populated ? "Oldest cache entry: 2026-01-15 00:00:00.000 UTC" : "Oldest cache entry: None")
        assertCacheAuditLabel(in: app, checkpoint: checkpoint, identifier: "settings.cache.lastCleanupAt", expected:
            populated ? "Last cleanup time: 2026-01-15 00:00:00.000 UTC"
                : "Last cleanup time: No cleanup record available")
        let providerID = "settings.cache.provider.synthetic.stage2.market"
        if populated {
            assertCacheAuditLabel(in: app, checkpoint: checkpoint, identifier: providerID,
                expected: "synthetic.stage2.market: 2 entries, \(bytes)")
            XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH %@", "settings.cache.provider.")).count, 1)
            XCTAssertFalse(app.descendants(matching: .any)["settings.cache.providers.empty"].exists)
        } else {
            assertCacheAuditLabel(in: app, checkpoint: checkpoint, identifier: "settings.cache.providers.empty",
                expected: "Provider breakdown: None")
            XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH %@", "settings.cache.provider.")).count, 0)
        }
        XCTAssertFalse(app.descendants(matching: .any)["settings.error"].exists)
    }

    @MainActor
    func testStage11GeneralPreferencesAffectWealthWithoutChangingValuation() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments(demo: true) + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        launchApp(app)
        defer { dismissResidualNativePanels(in: app); app.terminate() }
        app.descendants(matching: .any)["sidebar.settings"].click()
        XCTAssertTrue(waitForPickerSelection(in: app, identifier: "settings.general.currency", containing: "CNY", timeout: 5))
        XCTAssertTrue(waitForPickerSelection(in: app, identifier: "settings.general.grouping", containing: "On", timeout: 5))
        selectPicker(app: app, identifier: "settings.general.currency", title: "USD")
        selectPicker(app: app, identifier: "settings.general.grouping", title: "Off")
        app.descendants(matching: .any)["sidebar.wealth"].click()
        XCTAssertTrue(app.descendants(matching: .any)["wealth.row.bankCash.usd"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValueOrLabel(app.descendants(matching: .any)["wealth.summary.netWorth"],
            containing: "CNY " + generalSettingsAmount("150672.06", grouping: false), timeout: 5))
        XCTAssertTrue(waitForValueOrLabel(app.descendants(matching: .any)["wealth.row.bankCash.usd"],
            containing: "original USD " + generalSettingsAmount("1000", grouping: false), timeout: 5))
        XCTAssertTrue(waitForValueOrLabel(app.descendants(matching: .any)["wealth.row.bankCash.usd"],
            containing: "converted CNY " + generalSettingsAmount("7125", grouping: false), timeout: 5))
        app.descendants(matching: .any)["wealth.add"].click()
        XCTAssertTrue(app.descendants(matching: .any)["wealth.form.fx.rate"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["wealth.form.currency.cny"].click()
        XCTAssertTrue(waitForNonexistence(app.descendants(matching: .any)["wealth.form.fx.rate"], timeout: 5))
        app.descendants(matching: .any)["wealth.form.cancel"].click()
        selectRow(app: app, kind: "bankCash", currency: "cny")
        app.descendants(matching: .any)["wealth.edit"].click()
        XCTAssertTrue(app.descendants(matching: .any)["wealth.form.intent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["wealth.form.amount"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["wealth.form.fx.rate"].exists)
        XCTAssertTrue(waitForValue(app.descendants(matching: .any)["wealth.form.amount"], containing: "125000", timeout: 5))
        app.descendants(matching: .any)["wealth.form.cancel"].click()
        selectRow(app: app, kind: "bankCash", currency: "usd")
        app.descendants(matching: .any)["wealth.edit"].click()
        XCTAssertTrue(app.descendants(matching: .any)["wealth.form.intent"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(app.descendants(matching: .any)["wealth.form.fx.rate"], containing: "7.125", timeout: 5))
        XCTAssertTrue(waitForValue(app.descendants(matching: .any)["wealth.form.amount"], containing: "1000", timeout: 5))
        app.descendants(matching: .any)["wealth.form.cancel"].click()
        app.descendants(matching: .any)["sidebar.settings"].click()
        XCTAssertTrue(waitForPickerSelection(in: app, identifier: "settings.general.currency", containing: "USD", timeout: 5))
        XCTAssertTrue(waitForPickerSelection(in: app, identifier: "settings.general.grouping", containing: "Off", timeout: 5))
        selectPicker(app: app, identifier: "settings.general.grouping", title: "On")
        app.descendants(matching: .any)["sidebar.wealth"].click()
        XCTAssertTrue(waitForValueOrLabel(app.descendants(matching: .any)["wealth.summary.netWorth"],
            containing: "CNY " + generalSettingsAmount("150672.06", grouping: true), timeout: 5))
        XCTAssertTrue(waitForValueOrLabel(app.descendants(matching: .any)["wealth.row.bankCash.usd"],
            containing: "original USD " + generalSettingsAmount("1000", grouping: true), timeout: 5))
        launchApp(app)
        app.descendants(matching: .any)["sidebar.settings"].click()
        XCTAssertTrue(waitForPickerSelection(in: app, identifier: "settings.general.currency", containing: "CNY", timeout: 5))
        XCTAssertTrue(waitForPickerSelection(in: app, identifier: "settings.general.grouping", containing: "On", timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["settings.error"].exists)
    }

    @MainActor
    func testStage11SettingsCacheStatusTracksSessionAndClear() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments(demo: true)
        launchApp(app)
        defer { app.terminate() }
        app.descendants(matching: .any)["sidebar.settings"].click()
        assertUniqueSettingsDataLifecycleElement(in: app, identifier: "settings.cache.connectivity",
            expectedLabel: "Network connectivity: Not checked")
        assertGeneralSettingsFreshness(in: app, session: true, count: 0)
        assertGeneralSettingsFreshness(in: app, session: false, count: 0)
        app.descendants(matching: .any)["sidebar.markets"].click()
        XCTAssertTrue(app.descendants(matching: .any)["markets.search.field"].waitForExistence(timeout: 5))
        replaceText(in: app.descendants(matching: .any)["markets.search.field"], with: "SYN")
        XCTAssertTrue(waitForEnabled(app.descendants(matching: .any)["markets.search.submit"], timeout: 5))
        app.descendants(matching: .any)["markets.search.submit"].click()
        XCTAssertEqual(waitForMarketsSearchTerminal(in: app, timeout: 8), "Ready")
        XCTAssertTrue(app.descendants(matching: .any)["markets.search.result.SYN-CNY.XSYN"].exists)
        app.descendants(matching: .any)["sidebar.settings"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.cache.refresh"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["settings.cache.refresh"].click()
        assertGeneralSettingsFreshness(in: app, session: true, count: 1)
        assertGeneralSettingsFreshness(in: app, session: false, count: 0)
        app.descendants(matching: .any)["settings.session.clear"].click()
        assertGeneralSettingsFreshness(in: app, session: true, count: 0)
        assertUniqueSettingsDataLifecycleElement(in: app, identifier: "settings.cache.connectivity",
            expectedLabel: "Network connectivity: Not checked")
        XCTAssertTrue(waitForValueOrLabel(app.descendants(matching: .any)["settings.session.disclosure"],
            containing: "only in memory", timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["settings.error"].exists)
    }

    private func generalSettingsAmount(_ value: String, grouping: Bool) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouping
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(string: value))!
    }

    @MainActor
    private func assertGeneralSettingsFreshness(in app: XCUIApplication, session: Bool, count: Int) {
        let title = session ? "Session Market Data" : "Authorized Persistent Market Cache"
        let state = count == 0 ? "Empty" : "Within TTL"
        let limitation = count == 0 ? "No entries are currently available."
            : "Offline coverage depends on the requested data and existing authorization."
        assertUniqueSettingsDataLifecycleElement(in: app,
            identifier: session ? "settings.session.freshness" : "settings.cache.freshness",
            expectedLabel: "\(title): \(state). As of 2026-01-15 00:00:00.000 UTC. "
                + "\(count) total entries; \(count) TTL-classified; \(count) within TTL; 0 expired; 0 legacy. "
                + limitation + " TTL does not prove market real-time freshness or entitlement.")
    }

    @MainActor
    func testEmptyAppLaunchesAndAllDestinationsNavigateRepeatedly() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments()
        launchApp(app)

        XCTAssertTrue(app.descendants(matching: .any)["mode.local"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.empty"].exists)

        let destinations = [
            "dashboard", "wealth", "markets", "portfolio",
            "analytics", "ledger", "goals", "settings"
        ]
        for _ in 0..<2 {
            for destination in destinations {
                let sidebarItem = app.descendants(matching: .any)["sidebar.\(destination)"]
                XCTAssertTrue(sidebarItem.waitForExistence(timeout: 5), "Missing \(destination) sidebar item")
                sidebarItem.click()
                let expectedIdentifier: String
                if destination == "dashboard" { expectedIdentifier = "mode.local" }
                else if destination == "wealth" { expectedIdentifier = "wealth.page" }
                else if destination == "ledger" { expectedIdentifier = "ledger.empty" }
                else if destination == "markets" { expectedIdentifier = "markets.terminal" }
                else if destination == "portfolio" { expectedIdentifier = "portfolio.page" }
                else if destination == "settings" { expectedIdentifier = "settings.content" }
                else if destination == "analytics" { expectedIdentifier = "analytics.page" }
                else if destination == "goals" { expectedIdentifier = "goals.page" }
                else { expectedIdentifier = "destination.\(destination)" }
                XCTAssertTrue(
                    app.descendants(matching: .any)[expectedIdentifier].waitForExistence(timeout: 5),
                    "Missing destination content for \(destination)"
                )
                if destination == "goals" {
                    XCTAssertTrue(
                        app.descendants(matching: .any)["goals.empty"].waitForExistence(timeout: 5),
                        "Production Goals destination did not expose its honest empty state"
                    )
                }
            }
        }
        app.descendants(matching: .any)["sidebar.wealth"].click()
        XCTAssertTrue(app.descendants(matching: .any)["wealth.empty.add"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSyntheticDemoIsVisiblyIdentified() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments(demo: true)
        launchApp(app)

        XCTAssertTrue(app.descendants(matching: .any)["mode.demo"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.content"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["mode.local"].exists)

        app.descendants(matching: .any)["sidebar.wealth"].click()
        XCTAssertTrue(app.descendants(matching: .any)["wealth.page"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForRowCount(7, in: app, timeout: 5))
        XCTAssertTrue(
            waitForValue(
                app.descendants(matching: .any)["wealth.summary.netWorth"],
                containing: "150,672.06",
                timeout: 5
            )
        )
        app.descendants(matching: .any)["sidebar.ledger"].click()
        XCTAssertTrue(app.descendants(matching: .any)["ledger.history"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["ledger.taxonomy"].click()
        XCTAssertTrue(
            app.textFields.matching(NSPredicate(format: "value == %@", "Synthetic Income")).firstMatch.waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.textFields.matching(NSPredicate(format: "value == %@", "synthetic-demo")).firstMatch.waitForExistence(timeout: 5)
        )
        app.buttons["Done"].click()
    }

    @MainActor
    func testStage7MarketsSyntheticSearchWatchlistChartAccessibilityAndClear() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments(demo: true)
        launchApp(app)

        app.descendants(matching: .any)["sidebar.markets"].click()
        XCTAssertTrue(app.descendants(matching: .any)["markets.terminal"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["markets.mode.synthetic"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markets.capability.us"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markets.capability.hong-kong"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markets.capability.mainland-china"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markets.capability.japan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markets.capability.historical-record"].exists)

        let search = app.descendants(matching: .any)["markets.search.field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let initialSearchValue = String(describing: search.value ?? "")
        XCTAssertTrue(
            initialSearchValue.isEmpty || initialSearchValue == "Symbol or company",
            "Search must begin empty; the native field may expose its placeholder as AX value"
        )
        replaceText(in: app.descendants(matching: .any)["markets.search.field"], with: "SYN")
        XCTAssertTrue(waitForValue(app.descendants(matching: .any)["markets.search.field"], containing: "SYN", timeout: 5))
        let submit = app.descendants(matching: .any)["markets.search.submit"]
        XCTAssertTrue(waitForEnabled(submit, timeout: 5))
        submit.click()
        let terminal = waitForMarketsSearchTerminal(in: app, timeout: 8)
        XCTAssertEqual(terminal, "Ready", "Synthetic Search ended with finite state: \(terminal)")
        let result = app.descendants(matching: .any)["markets.search.result.SYN-CNY.XSYN"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        result.click()

        XCTAssertTrue(app.descendants(matching: .any)["markets.stock.detail"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markets.detail.freshness"].exists)
        app.descendants(matching: .any)["markets.watchlist.add"].click()
        XCTAssertTrue(app.descendants(matching: .any)["markets.watchlist.select.SYN-CNY.XSYN"].waitForExistence(timeout: 5))

        let range = app.descendants(matching: .any)["markets.range.selector"]
        XCTAssertTrue(range.exists)
        XCTAssertTrue(app.descendants(matching: .any)["markets.indicator.rsi14"].exists)
        app.descendants(matching: .any)["markets.indicator.rsi14"].click()
        app.descendants(matching: .any)["markets.history.refresh"].click()
        XCTAssertTrue(app.descendants(matching: .any)["markets.chart.webview"].waitForExistence(timeout: 10))
        let chartStatus = app.descendants(matching: .any)["markets.chart.status"]
        XCTAssertTrue(chartStatus.waitForExistence(timeout: 10))
        XCTAssertEqual(chartStatus.label, "Chart ready")
        let visibleRange = app.descendants(matching: .any)["markets.chart.visible-range"]
        XCTAssertTrue(visibleRange.waitForExistence(timeout: 5))
        XCTAssertTrue(visibleRange.label.contains("Visible range"))
        XCTAssertTrue(app.descendants(matching: .any)["markets.chart.render-summary"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["markets.indicator.rsi14"].click()
        app.descendants(matching: .any)["markets.indicator.rsi14"].click()
        XCTAssertEqual(app.descendants(matching: .any)["markets.chart.status"].label, "Chart ready")
        let heatmapTile = app.descendants(matching: .any)["markets.heatmap.SYN-CNY.XSYN"]
        if !heatmapTile.waitForExistence(timeout: 2) {
            let masterScroll = app.descendants(matching: .any)["markets.master.scroll"]
            XCTAssertTrue(masterScroll.waitForExistence(timeout: 3))
            masterScroll.swipeUp()
        }
        XCTAssertTrue(app.descendants(matching: .any)["markets.heatmap.SYN-CNY.XSYN"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markets.accessibility.summary"].exists)

        let accessibleData = app.descendants(matching: .any)["markets.presentation.accessible"]
        XCTAssertTrue(accessibleData.waitForExistence(timeout: 5))
        accessibleData.click()
        XCTAssertTrue(app.descendants(matching: .any)["markets.accessible.table"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markets.chart.attribution"].exists)

        let secondResult = app.descendants(matching: .any)["markets.search.result.SYN-JPY.XJPX"]
        XCTAssertTrue(secondResult.waitForExistence(timeout: 5))
        secondResult.click()
        app.descendants(matching: .any)["markets.watchlist.add"].click()
        let moveSecondUp = app.descendants(matching: .any)["markets.watchlist.move-up.SYN-JPY.XJPX"]
        XCTAssertTrue(moveSecondUp.waitForExistence(timeout: 5))
        XCTAssertTrue(moveSecondUp.isEnabled)
        moveSecondUp.click()
        XCTAssertFalse(app.descendants(matching: .any)["markets.watchlist.move-up.SYN-JPY.XJPX"].isEnabled)

        app.descendants(matching: .any)["markets.session.clear"].click()
        XCTAssertTrue(app.descendants(matching: .any)["markets.detail.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["markets.search.result.SYN-CNY.XSYN"].exists)

        app.terminate()
        let production = XCUIApplication()
        production.launchArguments = uiTestingArguments()
        launchApp(production)
        production.descendants(matching: .any)["sidebar.markets"].click()
        XCTAssertTrue(production.descendants(matching: .any)["markets.mode.production"].waitForExistence(timeout: 5))
        XCTAssertFalse(production.descendants(matching: .any)["markets.mode.synthetic"].exists)
        XCTAssertTrue(production.descendants(matching: .any)["markets.detail.empty"].exists)
        XCTAssertFalse(production.descendants(matching: .any)["markets.search.result.SYN-CNY.XSYN"].exists)
    }

    @MainActor
    func testStage8PortfolioSyntheticCRUDHoldingsSnapshotAndIsolation() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments(demo: true)
        launchApp(app)

        app.descendants(matching: .any)["sidebar.portfolio"].click()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.page"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.summary.nav"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.holding.SYNX|XSYN"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.nav.chart"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.nav.table"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.pnl.heatmap"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.benchmark.load"].exists)
        let providerPolicy = app.descendants(matching: .any)["portfolio.disclosure"]
        XCTAssertTrue(providerPolicy.waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "portfolio.disclosure").count, 1)
        XCTAssertTrue(providerPolicy.label.contains("No Provider request"))
        let benchmarkDisclosure = app.descendants(matching: .any)["portfolio.benchmark.disclosure"]
        XCTAssertTrue(benchmarkDisclosure.waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "portfolio.benchmark.disclosure").count, 1)
        XCTAssertTrue(benchmarkDisclosure.label.contains("Benchmark session data not loaded"))
        let initialPortfolioRowIdentifiers = portfolioRowIdentifiers(in: app)
        XCTAssertEqual(initialPortfolioRowIdentifiers.count, 2)

        let name = app.descendants(matching: .any)["portfolio.create.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeText("Synthetic Second Portfolio")
        app.descendants(matching: .any)["portfolio.create"].click()
        XCTAssertTrue(waitForPortfolioRowCount(3, in: app, timeout: 5))
        let identifiersAfterCreate = portfolioRowIdentifiers(in: app)
        let createdIdentifiers = identifiersAfterCreate.subtracting(initialPortfolioRowIdentifiers)
        XCTAssertEqual(createdIdentifiers.count, 1)
        let createdPortfolioIdentifier = try XCTUnwrap(createdIdentifiers.first)
        XCTAssertTrue(waitForPortfolioSummaryName(in: app, equals: "Synthetic Second Portfolio", timeout: 5))
        XCTAssertTrue(waitForPortfolioOrderStatus(
            in: app,
            portfolioName: "Synthetic Second Portfolio",
            position: 3,
            total: 3,
            timeout: 5
        ))

        XCTAssertTrue(waitForControlState(in: app, identifier: "portfolio.move.up", isEnabled: true, timeout: 5))
        app.descendants(matching: .any)["portfolio.move.up"].click()
        XCTAssertTrue(waitForPortfolioOrderStatus(
            in: app,
            portfolioName: "Synthetic Second Portfolio",
            position: 2,
            total: 3,
            timeout: 5
        ))

        XCTAssertTrue(waitForControlState(in: app, identifier: "portfolio.move.up", isEnabled: true, timeout: 5))
        app.descendants(matching: .any)["portfolio.move.up"].click()
        XCTAssertTrue(waitForPortfolioOrderStatus(
            in: app,
            portfolioName: "Synthetic Second Portfolio",
            position: 1,
            total: 3,
            timeout: 5
        ))
        XCTAssertTrue(waitForControlState(in: app, identifier: "portfolio.move.up", isEnabled: false, timeout: 5))

        // Recreate the feature model against the same temporary Store by
        // navigating away and back. The first persisted row must remain the
        // moved Portfolio, without relying on a List row index.
        reopenPortfolioFromDashboard(in: app)
        XCTAssertTrue(waitForPortfolioSummaryName(in: app, equals: "Synthetic Second Portfolio", timeout: 5))
        XCTAssertTrue(waitForPortfolioOrderStatus(
            in: app,
            portfolioName: "Synthetic Second Portfolio",
            position: 1,
            total: 3,
            timeout: 5
        ))
        XCTAssertTrue(waitForControlState(in: app, identifier: "portfolio.move.up", isEnabled: false, timeout: 5))
        XCTAssertTrue(waitForPortfolioRowCount(3, in: app, timeout: 5))
        XCTAssertEqual(portfolioRowIdentifiers(in: app), identifiersAfterCreate)

        app.descendants(matching: .any)["portfolio.delete"].click()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.delete.confirm"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["portfolio.delete.confirm"].click()
        XCTAssertTrue(waitForIdentifierToDisappear("portfolio.delete.confirm", in: app, timeout: 5))
        XCTAssertTrue(waitForPortfolioRowCount(2, in: app, timeout: 5))
        XCTAssertTrue(waitForPortfolioSummaryName(in: app, equals: "Synthetic Local Portfolio", timeout: 5))
        XCTAssertTrue(waitForIdentifierToDisappear(createdPortfolioIdentifier, in: app, timeout: 5))
        XCTAssertEqual(portfolioRowIdentifiers(in: app), initialPortfolioRowIdentifiers)

        // Recreate the Portfolio surface once more after deletion. The exact
        // captured UUID must stay absent while the original UUID and fallback
        // selection remain stable.
        reopenPortfolioFromDashboard(in: app)
        XCTAssertTrue(waitForPortfolioRowCount(2, in: app, timeout: 5))
        XCTAssertTrue(waitForPortfolioSummaryName(in: app, equals: "Synthetic Local Portfolio", timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)[createdPortfolioIdentifier].exists)
        XCTAssertEqual(portfolioRowIdentifiers(in: app), initialPortfolioRowIdentifiers)

        app.terminate()
        let production = XCUIApplication()
        production.launchArguments = uiTestingArguments()
        launchApp(production)
        production.descendants(matching: .any)["sidebar.portfolio"].click()
        XCTAssertTrue(production.descendants(matching: .any)["portfolio.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(production.descendants(matching: .any)[createdPortfolioIdentifier].exists)
        XCTAssertFalse(production.descendants(matching: .any)["portfolio.summary.name"].exists)
        XCTAssertFalse(production.descendants(matching: .any)["portfolio.holding.SYNX|XSYN"].exists)
        XCTAssertTrue(waitForPortfolioRowCount(0, in: production, timeout: 5))
        XCTAssertFalse(production.descendants(matching: .any)["portfolio.benchmark.chart"].exists)
    }

    @MainActor
    func testStage9AnalyticsSyntheticMetricsAccessibilityAndIsolation() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments(demo: true)
        launchApp(app)

        app.descendants(matching: .any)["sidebar.analytics"].click()
        XCTAssertTrue(app.descendants(matching: .any)["analytics.page"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["analytics.mode.synthetic"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "analytics.portfolio."))
                .count,
            2
        )
        XCTAssertTrue(app.descendants(matching: .any)["analytics.not-calculated"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["analytics.status"].label, "Analytics status: Ready")
        XCTAssertTrue(
            app.descendants(matching: .any)["analytics.disclosure.local-only"]
                .label.contains("No Provider request")
        )
        XCTAssertFalse(app.descendants(matching: .any)["analytics.metrics"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["analytics.navigation.group"].exists)
        XCTAssertTrue(waitForAccessibilityLabel(
            in: app,
            identifier: "analytics.navigation.current",
            equals: "Analytics report section: Overview",
            timeout: 5
        ))
        XCTAssertFalse(app.descendants(matching: .any)["analytics.navigation.previous"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["analytics.navigation.next"].isEnabled)

        app.descendants(matching: .any)["analytics.calculate"].click()
        XCTAssertTrue(waitForAccessibilityLabel(
            in: app,
            identifier: "analytics.status",
            equals: "Analytics status: Calculated",
            timeout: 10
        ))
        XCTAssertTrue(waitForAccessibilityLabel(
            in: app,
            identifier: "analytics.navigation.current",
            equals: "Analytics report section: Overview",
            timeout: 5
        ))
        XCTAssertFalse(app.descendants(matching: .any)["analytics.navigation.previous"].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["analytics.navigation.next"].isEnabled)
        assertAnalyticsOverview(
            in: app,
            portfolioName: "Synthetic Local Portfolio"
        )

        for identifier in [
            "analytics.metric.total-return",
            "analytics.metric.twr",
            "analytics.metric.cagr",
            "analytics.metric.xirr",
            "analytics.metric.volatility",
            "analytics.metric.sharpe",
            "analytics.metric.drawdown",
            "analytics.accessible-data.toggle"
        ] {
            XCTAssertTrue(
                waitForAnalyticsDetailElement(
                    in: app,
                    identifier: identifier,
                    timeout: 5,
                    requireUnique: true
                ),
                "Missing Stage 9 accessibility surface: \(identifier)"
            )
        }
        let fixedRiskFreeDisclosure = app.descendants(matching: .any)["analytics.risk-free.disclosure"]
        let detailScrollView = app.descendants(matching: .any)["analytics.detail.scroll"]
        XCTAssertTrue(
            fixedRiskFreeDisclosure.exists,
            "Missing fixed Analytics control: analytics.risk-free.disclosure"
        )
        XCTAssertEqual(
            analyticsViewportSnapshot(
                of: fixedRiskFreeDisclosure,
                in: detailScrollView
            ).relation.rawValue,
            AnalyticsViewportRelation.outsideScrollRegion.rawValue,
            "Fixed Analytics controls must remain outside the detail scroll region"
        )

        XCTAssertTrue(advanceAnalyticsReportSection(
            in: app,
            to: "Performance",
            anchorIdentifier: "analytics.chart.performance.summary"
        ))
        XCTAssertTrue(waitForAnalyticsDetailElement(
            in: app,
            identifier: "analytics.chart.performance.summary",
            timeout: 5,
            requireUnique: true,
            mustBeInsideViewport: true,
            labelSatisfies: { $0.contains("TWR index chart summary") }
        ))
        XCTAssertTrue(waitForAnalyticsDetailElement(
            in: app,
            identifier: "analytics.chart.performance",
            timeout: 5,
            requireUnique: true,
            mustBeInsideViewport: true
        ), "PARENT_CHART_CONTAINER_NOT_EXPOSED: analytics.chart.performance")
        XCTAssertTrue(waitForAnalyticsTableSummary(
            in: app,
            identifier: "analytics.performance.table",
            labelPrefix: "Accessible wealth index table:",
            timeout: 5
        ))
        XCTAssertTrue(waitForAnalyticsTableRow(
            in: app,
            identifierPrefix: "analytics.performance.row.",
            timeout: 5,
            labelSatisfies: {
                $0.range(of: #"[0-9]{4}-[0-9]{2}-[0-9]{2}"#, options: .regularExpression) != nil
                    && $0.contains("index")
            }
        ))

        XCTAssertTrue(advanceAnalyticsReportSection(
            in: app,
            to: "Drawdown",
            anchorIdentifier: "analytics.drawdown.summary"
        ))
        XCTAssertTrue(waitForAnalyticsDetailElement(
            in: app,
            identifier: "analytics.drawdown.summary",
            timeout: 5,
            requireUnique: true,
            mustBeInsideViewport: true,
            labelSatisfies: { $0.contains("Observed snapshot drawdown summary") }
        ))
        XCTAssertTrue(waitForAnalyticsDetailElement(
            in: app,
            identifier: "analytics.chart.drawdown",
            timeout: 5,
            requireUnique: true,
            mustBeInsideViewport: true
        ), "PARENT_CHART_CONTAINER_NOT_EXPOSED: analytics.chart.drawdown")
        XCTAssertTrue(waitForAnalyticsTableSummary(
            in: app,
            identifier: "analytics.drawdown.table",
            labelPrefix: "Accessible drawdown table:",
            timeout: 5
        ))
        XCTAssertTrue(waitForAnalyticsTableRow(
            in: app,
            identifierPrefix: "analytics.drawdown.row.",
            timeout: 5,
            labelSatisfies: {
                $0.range(of: #"[0-9]{4}-[0-9]{2}-[0-9]{2}"#, options: .regularExpression) != nil
                    && $0.contains("drawdown")
            }
        ))

        XCTAssertTrue(advanceAnalyticsReportSection(
            in: app,
            to: "Observed Returns",
            anchorIdentifier: "analytics.observed.heading"
        ))

        let observedHeading = analyticsDetailContractEvidence(
            in: app,
            identifier: "analytics.observed.heading",
            timeout: 5,
            labelSatisfies: { $0 == "Observed returns section" }
        )
        XCTAssertEqual(observedHeading.matchCount, 1, "OBSERVED_HEADING_COUNT_MISMATCH")
        XCTAssertTrue(observedHeading.labelMatched, "OBSERVED_HEADING_LABEL_MISMATCH")
        XCTAssertEqual(
            observedHeading.viewportRelation.rawValue,
            AnalyticsViewportRelation.insideViewport.rawValue,
            "OBSERVED_HEADING_VIEWPORT_MISMATCH"
        )

        var observedRowCounts: (monthly: Int, annual: Int)?
        let observedTables = analyticsDetailContractEvidence(
            in: app,
            identifier: "analytics.observed.tables",
            timeout: 5,
            labelSatisfies: { label in
                guard label.hasPrefix("Observed returns tables:"),
                      label.contains("monthly rows"),
                      label.contains("annual rows"),
                      let rowCounts = observedReturnsTableRowCounts(from: label),
                      rowCounts.monthly > 0,
                      rowCounts.annual > 0
                else { return false }
                observedRowCounts = rowCounts
                return true
            }
        )
        XCTAssertEqual(observedTables.matchCount, 1, "OBSERVED_TABLES_COUNT_MISMATCH")
        XCTAssertTrue(observedTables.labelMatched, "OBSERVED_TABLES_LABEL_MISMATCH")
        XCTAssertEqual(
            observedTables.viewportRelation.rawValue,
            AnalyticsViewportRelation.insideViewport.rawValue,
            "OBSERVED_TABLES_VIEWPORT_MISMATCH"
        )

        for contract in [
            (
                "analytics.monthly.table",
                "Observed monthly TWR table:",
                "analytics.month.",
                "available",
                observedRowCounts?.monthly,
                "OBSERVED_MONTHLY_RUNTIME_COUNT_MISMATCH"
            ),
            (
                "analytics.annual.table",
                "Observed annual TWR table:",
                "analytics.year.",
                "available",
                observedRowCounts?.annual,
                "OBSERVED_ANNUAL_RUNTIME_COUNT_MISMATCH"
            )
        ] {
            XCTAssertTrue(waitForAnalyticsTableSummary(
                in: app,
                identifier: contract.0,
                labelPrefix: contract.1,
                timeout: 5
            ))
            let detailScrollView = app.descendants(matching: .any)["analytics.detail.scroll"]
            let tableSummaries = detailScrollView.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@", contract.0))
            XCTAssertEqual(tableSummaries.count, 1, contract.5)
            XCTAssertEqual(
                analyticsTableRowCount(from: tableSummaries.firstMatch.label),
                contract.4,
                contract.5
            )
            XCTAssertTrue(waitForAnalyticsTableRow(
                in: app,
                identifierPrefix: contract.2,
                timeout: 5,
                labelSatisfies: {
                    $0.contains(contract.3)
                        && $0.contains("%")
                        && $0.contains("period")
                }
            ))
        }

        XCTAssertTrue(advanceAnalyticsReportSection(
            in: app,
            to: "TWR Subperiods",
            anchorIdentifier: "analytics.subperiod.table"
        ))
        XCTAssertTrue(waitForAnalyticsTableSummary(
            in: app,
            identifier: "analytics.subperiod.table",
            labelPrefix: "Accessible TWR subperiod table:",
            timeout: 5
        ))
        XCTAssertTrue(waitForAnalyticsTableRow(
            in: app,
            identifierPrefix: "analytics.subperiod.row.",
            timeout: 5,
            labelSatisfies: {
                $0.contains("capital flow")
                    && $0.range(
                        of: #"[0-9]{4}-[0-9]{2}-[0-9]{2} to [0-9]{4}-[0-9]{2}-[0-9]{2}"#,
                        options: .regularExpression
                    ) != nil
            }
        ))

        XCTAssertTrue(advanceAnalyticsReportSection(
            in: app,
            to: "XIRR Flows",
            anchorIdentifier: "analytics.xirr-flow.table"
        ))
        XCTAssertTrue(waitForAnalyticsTableSummary(
            in: app,
            identifier: "analytics.xirr-flow.table",
            labelPrefix: "Accessible XIRR cash-flow table:",
            timeout: 5
        ))
        XCTAssertTrue(waitForAnalyticsTableRow(
            in: app,
            identifierPrefix: "analytics.xirr-flow.row.",
            timeout: 5,
            labelSatisfies: {
                $0.contains("CNY") && ($0.contains("invested") || $0.contains("returned"))
            }
        ))

        XCTAssertTrue(advanceAnalyticsReportSection(
            in: app,
            to: "Capital Flows",
            anchorIdentifier: "analytics.cash-flow.table"
        ))
        XCTAssertTrue(waitForAnalyticsTableSummary(
            in: app,
            identifier: "analytics.cash-flow.table",
            labelPrefix: "Portfolio capital-flow table:",
            timeout: 5
        ))
        XCTAssertTrue(waitForAnalyticsTableRow(
            in: app,
            identifierPrefix: "analytics.cash-flow.row.",
            timeout: 5,
            labelSatisfies: {
                $0.contains("CNY") && ($0.contains("contribution") || $0.contains("withdrawal"))
            }
        ))

        XCTAssertTrue(advanceAnalyticsReportSection(
            in: app,
            to: "Calculation Evidence",
            anchorIdentifier: "analytics.evidence.heading"
        ))

        let evidenceHeading = analyticsDetailContractEvidence(
            in: app,
            identifier: "analytics.evidence.heading",
            timeout: 5,
            labelSatisfies: { $0 == "Calculation evidence section" }
        )
        XCTAssertEqual(evidenceHeading.matchCount, 1, "EVIDENCE_HEADING_COUNT_MISMATCH")
        XCTAssertTrue(evidenceHeading.labelMatched, "EVIDENCE_HEADING_LABEL_MISMATCH")
        XCTAssertEqual(
            evidenceHeading.viewportRelation.rawValue,
            AnalyticsViewportRelation.insideViewport.rawValue,
            "EVIDENCE_HEADING_VIEWPORT_MISMATCH"
        )

        let evidenceDisclosure = analyticsDetailContractEvidence(
            in: app,
            identifier: "analytics.evidence",
            timeout: 5,
            labelSatisfies: {
                !$0.isEmpty
                    && $0.contains("No benchmark")
                    && $0.contains("Provider")
                    && $0.contains("Market Cache")
            }
        )
        XCTAssertEqual(evidenceDisclosure.matchCount, 1, "EVIDENCE_DISCLOSURE_COUNT_MISMATCH")
        XCTAssertTrue(evidenceDisclosure.labelMatched, "EVIDENCE_DISCLOSURE_LABEL_MISMATCH")
        XCTAssertEqual(
            evidenceDisclosure.viewportRelation.rawValue,
            AnalyticsViewportRelation.insideViewport.rawValue,
            "EVIDENCE_DISCLOSURE_VIEWPORT_MISMATCH"
        )

        XCTAssertTrue(waitForAccessibilityLabel(
            in: app,
            identifier: "analytics.navigation.current",
            equals: "Analytics report section: Calculation Evidence",
            timeout: 5
        ), "EVIDENCE_CURRENT_SECTION_MISMATCH")
        XCTAssertTrue(
            app.descendants(matching: .any)["analytics.navigation.previous"].waitForExistence(timeout: 5),
            "EVIDENCE_PREVIOUS_NOT_FOUND"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["analytics.navigation.previous"].isEnabled,
            "EVIDENCE_PREVIOUS_DISABLED"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["analytics.navigation.next"].waitForExistence(timeout: 5),
            "EVIDENCE_NEXT_NOT_FOUND"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["analytics.navigation.next"].isEnabled,
            "EVIDENCE_NEXT_ENABLED"
        )

        let sparseIdentifier = "analytics.portfolio.00000000-0000-4000-8000-000000009001"
        XCTAssertTrue(app.descendants(matching: .any)[sparseIdentifier].waitForExistence(timeout: 5))
        app.descendants(matching: .any)[sparseIdentifier].click()
        XCTAssertTrue(waitForAccessibilityLabel(
            in: app,
            identifier: "analytics.status",
            equals: "Analytics status: Ready",
            timeout: 5
        ))
        XCTAssertTrue(waitForAccessibilityLabel(
            in: app,
            identifier: "analytics.navigation.current",
            equals: "Analytics report section: Overview",
            timeout: 5
        ))
        XCTAssertFalse(app.descendants(matching: .any)["analytics.navigation.previous"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["analytics.navigation.next"].isEnabled)
        app.descendants(matching: .any)["analytics.calculate"].click()
        XCTAssertTrue(waitForAccessibilityLabel(
            in: app,
            identifier: "analytics.status",
            equals: "Analytics status: Calculated",
            timeout: 10
        ))
        XCTAssertTrue(waitForAccessibilityLabel(
            in: app,
            identifier: "analytics.navigation.current",
            equals: "Analytics report section: Overview",
            timeout: 5
        ))
        XCTAssertFalse(app.descendants(matching: .any)["analytics.navigation.previous"].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["analytics.navigation.next"].isEnabled)
        assertAnalyticsOverview(
            in: app,
            portfolioName: "Synthetic Sparse Portfolio"
        )
        XCTAssertTrue(waitForAnalyticsDetailElement(
            in: app,
            identifier: "analytics.metric.xirr",
            timeout: 5,
            requireUnique: true,
            labelSatisfies: { $0.contains("non-conventional cash flows") }
        ))
        XCTAssertTrue(waitForAnalyticsDetailElement(
            in: app,
            identifier: "analytics.metric.volatility",
            timeout: 5,
            requireUnique: true,
            labelSatisfies: { $0.contains("irregular daily observations") }
        ))

        app.terminate()
        let production = XCUIApplication()
        production.launchArguments = uiTestingArguments()
        launchApp(production)
        production.descendants(matching: .any)["sidebar.analytics"].click()
        XCTAssertTrue(production.descendants(matching: .any)["analytics.mode.production"].waitForExistence(timeout: 5))
        XCTAssertTrue(production.descendants(matching: .any)["analytics.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(production.descendants(matching: .any)["analytics.mode.synthetic"].exists)
        XCTAssertFalse(production.descendants(matching: .any)[
            "analytics.portfolio.00000000-0000-4000-8000-000000009001"
        ].exists)
        XCTAssertFalse(production.descendants(matching: .any)["analytics.metrics"].exists)
        XCTAssertTrue(waitForAccessibilityLabel(
            in: production,
            identifier: "analytics.navigation.current",
            equals: "Analytics report section: Overview",
            timeout: 5
        ))
        XCTAssertFalse(production.descendants(matching: .any)["analytics.navigation.previous"].isEnabled)
        XCTAssertFalse(production.descendants(matching: .any)["analytics.navigation.next"].isEnabled)
        production.terminate()
    }

    @MainActor
    func testStage10GoalsSyntheticCRUDPlanningAccessibilityAndIsolation() throws {
        let cnyGoalIdentifier = "goals.goal.00000000-0000-4000-8000-000000010001"
        let usdGoalIdentifier = "goals.goal.00000000-0000-4000-8000-000000010002"
        let localOnlyDisclosure = "Goals use permanent local Goals, Wealth, and Ledger records. Planning assumptions are session-only and no Provider, Market Cache, Credential, or Keychain data is read."
        let calculationEvidenceDisclosure = "Calculation evidence: local permanent Goals, Wealth, and Ledger records only. Planning assumptions are session-only. No Provider request was made. No Market Cache, Credential, or Keychain data was read. No automatic FX conversion was performed. Planning assumptions were not persisted. Scenarios are not predictions, guarantees, or recommendations."
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments(demo: true)
        launchApp(app)

        app.descendants(matching: .any)["sidebar.goals"].click()
        assertGoalsHeaderElement(
            in: app,
            identifier: "goals.page",
            expectedLabel: "Goals page"
        )
        assertGoalsHeaderElement(
            in: app,
            identifier: "goals.mode.synthetic",
            expectedLabel: "Goals mode: Synthetic Demo"
        )
        assertGoalsHeaderElementAbsent(in: app, identifier: "goals.mode.production")
        assertGoalsHeaderElement(
            in: app,
            identifier: "goals.disclosure.local-only",
            expectedLabel: localOnlyDisclosure
        )
        XCTAssertTrue(waitForGoalsStatus(in: app, equals: "Goals status: Ready", timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)[cnyGoalIdentifier].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)[usdGoalIdentifier].waitForExistence(timeout: 5))
        let initialGoalIdentifiers = goalRowIdentifiers(in: app)
        XCTAssertEqual(initialGoalIdentifiers.count, 2)
        XCTAssertTrue(waitForGoalsSection(in: app, equals: "Overview", timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["goals.navigation.previous"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["goals.navigation.next"].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["goals.not-calculated"].exists)

        app.descendants(matching: .any)["goals.add"].click()
        XCTAssertTrue(app.descendants(matching: .any)["goals.editor.name"].waitForExistence(timeout: 5))
        replaceText(in: app.descendants(matching: .any)["goals.editor.name"], with: "Synthetic UI Goal")
        replaceText(in: app.descendants(matching: .any)["goals.editor.target"], with: "250000")
        app.descendants(matching: .any)["goals.editor.save"].click()
        XCTAssertTrue(waitForNonexistence(app.descendants(matching: .any)["goals.editor.save"], timeout: 5))
        XCTAssertTrue(waitForGoalRowCount(3, in: app, timeout: 8))
        let identifiersAfterCreate = goalRowIdentifiers(in: app)
        let createdIdentifiers = identifiersAfterCreate.subtracting(initialGoalIdentifiers)
        XCTAssertEqual(createdIdentifiers.count, 1)
        let createdIdentifier = try XCTUnwrap(createdIdentifiers.first)
        XCTAssertTrue(waitForGoalsLabel(
            in: app,
            identifier: createdIdentifier,
            containing: "Synthetic UI Goal",
            timeout: 5
        ))

        app.descendants(matching: .any)[createdIdentifier].click()
        app.descendants(matching: .any)["goals.edit"].click()
        XCTAssertTrue(app.descendants(matching: .any)["goals.editor.name"].waitForExistence(timeout: 5))
        replaceText(
            in: app.descendants(matching: .any)["goals.editor.name"],
            with: "Synthetic UI Goal Updated"
        )
        replaceText(in: app.descendants(matching: .any)["goals.editor.target"], with: "275000")
        app.descendants(matching: .any)["goals.editor.save"].click()
        XCTAssertTrue(waitForNonexistence(app.descendants(matching: .any)["goals.editor.save"], timeout: 5))
        XCTAssertTrue(waitForGoalsLabel(
            in: app,
            identifier: createdIdentifier,
            containing: "Synthetic UI Goal Updated",
            timeout: 8
        ))

        reopenGoalsFromDashboard(in: app)
        XCTAssertTrue(app.descendants(matching: .any)[createdIdentifier].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForGoalsLabel(
            in: app,
            identifier: createdIdentifier,
            containing: "Synthetic UI Goal Updated",
            timeout: 5
        ))
        app.descendants(matching: .any)[createdIdentifier].click()
        app.descendants(matching: .any)["goals.delete"].click()
        let confirmDelete = app.descendants(matching: .any)["goals.delete.confirm"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.click()
        XCTAssertTrue(waitForNonexistence(confirmDelete, timeout: 5))
        XCTAssertTrue(waitForGoalRowCount(2, in: app, timeout: 8))
        XCTAssertTrue(waitForNonexistence(app.descendants(matching: .any)[createdIdentifier], timeout: 5))

        reopenGoalsFromDashboard(in: app)
        XCTAssertTrue(waitForGoalRowCount(2, in: app, timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)[createdIdentifier].exists)
        XCTAssertEqual(goalRowIdentifiers(in: app), initialGoalIdentifiers)

        app.descendants(matching: .any)[cnyGoalIdentifier].click()
        replaceText(
            in: app.descendants(matching: .any)["goals.input.monthly-contribution"],
            with: "2000"
        )
        replaceText(
            in: app.descendants(matching: .any)["goals.input.expected-return"],
            with: "5"
        )
        replaceText(
            in: app.descendants(matching: .any)["goals.input.annual-spending"],
            with: "120000"
        )
        replaceText(
            in: app.descendants(matching: .any)["goals.input.withdrawal-rate"],
            with: "4"
        )
        replaceText(
            in: app.descendants(matching: .any)["goals.input.saving-start"],
            with: "2026-01-01"
        )
        replaceText(
            in: app.descendants(matching: .any)["goals.input.saving-end"],
            with: "2026-01-31"
        )
        replaceText(
            in: app.descendants(matching: .any)["goals.input.as-of"],
            with: "2026-01-15"
        )
        XCTAssertTrue(waitForGoalsStatus(in: app, equals: "Goals status: Ready", timeout: 5))
        app.descendants(matching: .any)["goals.calculate"].click()
        XCTAssertTrue(waitForGoalsStatus(in: app, equals: "Goals status: Calculated", timeout: 15))
        XCTAssertTrue(waitForGoalsSection(in: app, equals: "Overview", timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["goals.navigation.previous"].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["goals.navigation.next"].isEnabled)
        assertGoalsElement(
            in: app,
            identifier: "goals.overview.heading",
            labelSatisfies: { $0 == "Goals report overview" }
        )
        assertGoalsElement(
            in: app,
            identifier: "goals.overview.goal",
            labelSatisfies: { $0.contains("Synthetic Freedom Goal") && $0.contains("CNY 500,000.00") }
        )
        assertGoalsElement(
            in: app,
            identifier: "goals.overview.net-worth",
            labelSatisfies: { $0.contains("CNY 150,672.06") }
        )
        assertGoalsElement(
            in: app,
            identifier: "goals.progress.summary",
            labelSatisfies: { $0.contains("Goal progress") && $0.contains("remaining") }
        )

        advanceGoalsSection(in: app, to: "Trajectory", anchorIdentifier: "goals.trajectory.heading")
        assertGoalsElement(in: app, identifier: "goals.chart.trajectory") { $0 == "Goal trajectory chart" }
        assertGoalsElement(in: app, identifier: "goals.trajectory.summary") {
            $0.contains("points") && $0.contains("2035-12-31") && $0.contains("CNY")
        }
        let trajectoryRows = goalsTableRowCount(
            in: app,
            identifier: "goals.trajectory.table",
            prefix: "Trajectory table:"
        )
        XCTAssertGreaterThan(trajectoryRows, 0)
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "goals.trajectory.row."))
                .count,
            trajectoryRows
        )
        assertGoalsElement(in: app, identifier: "goals.trajectory.row.0") {
            $0.contains("Month 0") && $0.contains("projected CNY")
        }
        assertGoalsElement(in: app, identifier: "goals.trajectory.disclosure") {
            $0.contains("not a prediction") && $0.contains("recommendation")
        }

        advanceGoalsSection(in: app, to: "FIRE", anchorIdentifier: "goals.fire.heading")
        assertGoalsElement(in: app, identifier: "goals.fire.summary") {
            $0.contains("annual spending")
                && $0.contains("user-supplied withdrawal rate 4%")
                && $0.contains("FIRE Number")
        }
        assertGoalsElement(in: app, identifier: "goals.fire.reach") { $0.contains("Estimated reach") }
        assertGoalsElement(in: app, identifier: "goals.fire.disclosure") {
            $0.contains("no withdrawal rate") && $0.contains("preselected")
        }

        advanceGoalsSection(in: app, to: "Saving Rate", anchorIdentifier: "goals.saving-rate.heading")
        assertGoalsElement(in: app, identifier: "goals.chart.saving-rate") { $0 == "Observed Saving Rate chart" }
        assertGoalsElement(in: app, identifier: "goals.saving-rate.summary") {
            $0.contains("CNY 5,000.00")
                && $0.contains("CNY 800.00")
                && $0.contains("CNY 4,200.00")
                && $0.contains("aggregate rate 84%")
                && $0.contains("1 observed months")
        }
        let savingRows = goalsTableRowCount(
            in: app,
            identifier: "goals.saving-rate.table",
            prefix: "Saving Rate table:"
        )
        XCTAssertEqual(savingRows, 1)
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "goals.saving-rate.row."))
                .count,
            savingRows
        )
        assertGoalsElement(in: app, identifier: "goals.saving-rate.row.2026-01") {
            $0.contains("income CNY 5,000.00")
                && $0.contains("expense CNY 800.00")
                && $0.contains("savings CNY 4,200.00")
                && $0.contains("rate 84%")
        }
        assertGoalsElement(in: app, identifier: "goals.saving-rate.disclosure") {
            $0.contains("transfers") && $0.contains("Stored converted-CNY provenance")
        }

        advanceGoalsSection(
            in: app,
            to: "Calculation Evidence",
            anchorIdentifier: "goals.evidence.heading"
        )
        assertGoalsElement(in: app, identifier: "goals.evidence.heading") {
            $0 == "Goals calculation evidence section"
        }
        assertGoalsElement(in: app, identifier: "goals.evidence") {
            $0 == calculationEvidenceDisclosure
        }
        XCTAssertTrue(app.descendants(matching: .any)["goals.navigation.previous"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["goals.navigation.next"].isEnabled)

        app.descendants(matching: .any)[usdGoalIdentifier].click()
        XCTAssertTrue(waitForGoalsStatus(in: app, equals: "Goals status: Ready", timeout: 5))
        XCTAssertTrue(waitForGoalsSection(in: app, equals: "Overview", timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["goals.navigation.previous"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["goals.navigation.next"].isEnabled)
        app.descendants(matching: .any)["goals.calculate"].click()
        XCTAssertTrue(waitForGoalsStatus(in: app, equals: "Goals status: Calculated", timeout: 15))
        assertGoalsElement(in: app, identifier: "goals.overview.goal") {
            $0.contains("Synthetic USD Education Goal") && $0.contains("USD 100,000.00")
        }
        assertGoalsElement(in: app, identifier: "goals.progress.unavailable") {
            $0.contains("target currency unsupported for CNY progress") && !$0.contains("0%")
        }
        advanceGoalsSection(in: app, to: "Trajectory", anchorIdentifier: "goals.trajectory.heading")
        assertGoalsElement(in: app, identifier: "goals.trajectory.unavailable") {
            $0.contains("target currency unsupported for CNY progress")
        }
        XCTAssertFalse(app.descendants(matching: .any)["goals.chart.trajectory"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["goals.trajectory.table"].exists)
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "goals.trajectory.row."))
                .count,
            0
        )

        app.terminate()
        let production = XCUIApplication()
        production.launchArguments = uiTestingArguments()
        launchApp(production)
        production.descendants(matching: .any)["sidebar.goals"].click()
        assertGoalsHeaderElement(
            in: production,
            identifier: "goals.page",
            expectedLabel: "Goals page"
        )
        assertGoalsHeaderElement(
            in: production,
            identifier: "goals.mode.production",
            expectedLabel: "Goals mode: Production Local"
        )
        assertGoalsHeaderElementAbsent(in: production, identifier: "goals.mode.synthetic")
        assertGoalsHeaderElement(
            in: production,
            identifier: "goals.disclosure.local-only",
            expectedLabel: localOnlyDisclosure
        )
        XCTAssertTrue(production.descendants(matching: .any)["goals.empty"].waitForExistence(timeout: 8))
        XCTAssertFalse(production.descendants(matching: .any)[cnyGoalIdentifier].exists)
        XCTAssertFalse(production.descendants(matching: .any)[usdGoalIdentifier].exists)
        XCTAssertFalse(production.descendants(matching: .any)["goals.overview.heading"].exists)
        XCTAssertTrue(waitForGoalsSection(in: production, equals: "Overview", timeout: 5))
        XCTAssertFalse(production.descendants(matching: .any)["goals.navigation.previous"].isEnabled)
        XCTAssertFalse(production.descendants(matching: .any)["goals.navigation.next"].isEnabled)
        for identifier in [
            "goals.input.monthly-contribution",
            "goals.input.expected-return",
            "goals.input.annual-spending",
            "goals.input.withdrawal-rate"
        ] {
            XCTAssertTrue(goalsFieldIsBlank(production.descendants(matching: .any)[identifier]))
        }
        production.terminate()
    }

    @MainActor
    func testDashboardEmptyStoreDoesNotFabricateSnapshot() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments()
        launchApp(app)

        XCTAssertTrue(app.descendants(matching: .any)["dashboard.empty"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.snapshot.status"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.history.chart"].exists)
    }

    @MainActor
    func testDashboardPopulatedLocalThenHistoricalOnlyAfterLastContainerDeletion() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments()
        launchApp(app)

        XCTAssertTrue(app.descendants(matching: .any)["mode.local"].waitForExistence(timeout: 10))
        app.descendants(matching: .any)["sidebar.wealth"].click()
        XCTAssertTrue(app.descendants(matching: .any)["wealth.empty.add"].waitForExistence(timeout: 5))
        addContainer(
            app: app,
            name: "Synthetic Historical-only Cash",
            kind: "Bank / Cash",
            amount: "100.00",
            currency: "CNY",
            fxRate: nil
        )

        app.descendants(matching: .any)["sidebar.dashboard"].click()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.content"].waitForExistence(timeout: 10))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "dashboard.content").count,
            1,
            "dashboard.content must identify only the ready content container"
        )
        XCTAssertTrue(waitForValueOrLabel(app.descendants(matching: .any)["dashboard.current.assets"], containing: "100.00", timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.history.chart"].exists)
        XCTAssertTrue(waitForValueOrLabel(app.descendants(matching: .any)["dashboard.snapshot.historyCount"], containing: "1 complete", timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["mode.demo"].exists)

        app.descendants(matching: .any)["sidebar.wealth"].click()
        selectRow(app: app, kind: "bankCash", currency: "cny")
        deleteSelectedContainer(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["wealth.empty.add"].waitForExistence(timeout: 5))

        app.descendants(matching: .any)["sidebar.dashboard"].click()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.current.empty"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.history.chart"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.historicalHigh"].exists)
        XCTAssertTrue(waitForValueOrLabel(app.descendants(matching: .any)["dashboard.snapshot.historyCount"], containing: "1 complete", timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.current.assets"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["mode.demo"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["mode.local"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.snapshot.refresh"].isEnabled)
    }

    @MainActor
    func testDashboardSyntheticHistoryRangeHeatmapsAndRefresh() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments(demo: true)
        launchApp(app)

        XCTAssertTrue(app.descendants(matching: .any)["dashboard.content"].waitForExistence(timeout: 15))
        XCTAssertTrue(waitForValueOrLabel(app.descendants(matching: .any)["dashboard.current.assets"], containing: "164,922.06", timeout: 5))
        XCTAssertTrue(waitForValueOrLabel(app.descendants(matching: .any)["dashboard.current.liabilities"], containing: "14,250.00", timeout: 5))
        XCTAssertTrue(waitForValueOrLabel(app.descendants(matching: .any)["dashboard.current.netWorth"], containing: "150,672.06", timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.snapshot.status"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.history.chart"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.history.accessibleSummary"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.allocation.chart"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.subassets.assets"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.subassets.liabilities"].exists)

        let oneDay = app.radioButtons["1D"]
        XCTAssertTrue(oneDay.waitForExistence(timeout: 5)); oneDay.click()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.insufficientHistory"].waitForExistence(timeout: 5))
        let maximum = app.radioButtons["MAX"]
        XCTAssertTrue(maximum.waitForExistence(timeout: 5)); maximum.click()
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.insufficientHistory"].waitForExistence(timeout: 2))

        app.descendants(matching: .any)["dashboard.snapshot.refresh"].click()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.content"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.error"].exists)

        let cashFlowSection = app.radioButtons["Cash Flow"]
        XCTAssertTrue(cashFlowSection.waitForExistence(timeout: 5)); cashFlowSection.click()
        let cashFlowChart = app.descendants(matching: .any)["dashboard.cashFlow.chart"]
        XCTAssertTrue(cashFlowChart.waitForExistence(timeout: 5) && cashFlowChart.isHittable)

        let heatmapsSection = app.radioButtons["Heatmaps"]
        XCTAssertTrue(heatmapsSection.waitForExistence(timeout: 5)); heatmapsSection.click()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.heatmap.netWorth"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.heatmap.cashFlow"].exists)

        let incomeMode = app.radioButtons["Income"]
        XCTAssertTrue(incomeMode.waitForExistence(timeout: 5)); incomeMode.click()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.heatmap.cashFlow"].exists)
    }

    @MainActor
    func testStage10DashboardGoalsProgressAndNavigationIsolation() throws {
        let freedomIdentifier =
            "dashboard.goal.00000000-0000-4000-8000-000000010001"
        let educationIdentifier =
            "dashboard.goal.00000000-0000-4000-8000-000000010002"
        let freedomLabel =
            "Dashboard Goal: Synthetic Freedom Goal, target CNY 500,000.00, target date 2035-12-31, current CNY net worth CNY 150,672.06, progress 30.13%, remaining CNY 349,327.94; progress is not clamped."
        let educationLabel =
            "Dashboard Goal: Synthetic USD Education Goal, target USD 100,000.00, target date 2040-06-30, CNY progress unavailable: target currency unsupported for CNY progress; no automatic FX conversion was performed."

        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments(demo: true)
        launchApp(app)

        XCTAssertTrue(app.descendants(matching: .any)["dashboard.content"].waitForExistence(timeout: 15))
        let goalsSection = app.radioButtons["Goals"]
        XCTAssertTrue(goalsSection.waitForExistence(timeout: 5))
        goalsSection.click()

        let heading = app.descendants(matching: .any)["dashboard.goals.heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(identifier: "dashboard.goals.heading").count,
            1
        )
        XCTAssertEqual(heading.label, "Dashboard goals progress")

        let summary = app.descendants(matching: .any)["dashboard.goals.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(identifier: "dashboard.goals.summary").count,
            1
        )
        XCTAssertEqual(
            summary.label,
            "Dashboard goals summary: 2 goals, current CNY net worth CNY 150,672.06."
        )

        let freedom = app.descendants(matching: .any)[freedomIdentifier]
        let education = app.descendants(matching: .any)[educationIdentifier]
        XCTAssertTrue(freedom.waitForExistence(timeout: 5))
        XCTAssertTrue(education.waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "dashboard.goal."))
                .count,
            2
        )
        XCTAssertEqual(freedom.label, freedomLabel)
        XCTAssertEqual(education.label, educationLabel)
        XCTAssertFalse(education.label.contains("0%"))

        let openGoals = app.buttons["dashboard.goals.open"]
        XCTAssertTrue(openGoals.waitForExistence(timeout: 5))
        XCTAssertTrue(openGoals.isEnabled)
        XCTAssertEqual(openGoals.label, "Open Goals")
        openGoals.click()
        XCTAssertTrue(app.descendants(matching: .any)["goals.page"].waitForExistence(timeout: 8))
        XCTAssertEqual(
            app.descendants(matching: .any)["goals.mode.synthetic"].label,
            "Goals mode: Synthetic Demo"
        )

        app.descendants(matching: .any)["sidebar.dashboard"].click()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.content"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.radioButtons["Goals"].waitForExistence(timeout: 5))
        app.radioButtons["Goals"].click()
        XCTAssertTrue(app.descendants(matching: .any)[freedomIdentifier].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)[educationIdentifier].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)[freedomIdentifier].label, freedomLabel)
        XCTAssertEqual(app.descendants(matching: .any)[educationIdentifier].label, educationLabel)

        app.terminate()
        let production = XCUIApplication()
        production.launchArguments = uiTestingArguments()
        launchApp(production)
        XCTAssertTrue(production.descendants(matching: .any)["mode.local"].waitForExistence(timeout: 10))
        XCTAssertTrue(production.descendants(matching: .any)["dashboard.empty"].waitForExistence(timeout: 10))
        XCTAssertFalse(production.descendants(matching: .any)[freedomIdentifier].exists)
        XCTAssertFalse(production.descendants(matching: .any)[educationIdentifier].exists)
        XCTAssertFalse(production.descendants(matching: .any)["dashboard.snapshot.status"].exists)
        XCTAssertFalse(production.descendants(matching: .any)["dashboard.error"].exists)
        production.terminate()
    }

    @MainActor
    func testStage11SettingsInternalBackupRestoreLifecycleAndIsolation() throws {
        let disclosure = "Backup and Restore use Aureus’s private local Backup directory. Backups contain permanent financial records. Market Cache, Provider payloads, Credentials, Keychain data, and session-only planning assumptions are excluded. Aureus does not add application-layer encryption. Restore creates and validates a safety backup before replacing the Permanent Store."
        let freedomIdentifier = "goals.goal.00000000-0000-4000-8000-000000010001"
        let educationIdentifier = "goals.goal.00000000-0000-4000-8000-000000010002"
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments(demo: true)
        launchApp(app)

        app.descendants(matching: .any)["sidebar.settings"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.content"].waitForExistence(timeout: 10))
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.heading",
            expectedLabel: "Settings data lifecycle"
        )
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.disclosure",
            expectedLabel: disclosure
        )
        XCTAssertTrue(waitForSettingsDataLifecycleLabel(
            in: app,
            identifier: "settings.dataLifecycle.summary",
            equals: "Data lifecycle: 0 valid backups, 0 ignored entries",
            timeout: 8
        ))
        XCTAssertTrue(app.descendants(matching: .any)["settings.dataLifecycle.empty"].exists)
        XCTAssertEqual(settingsGenerationRows(in: app).count, 0)
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.restore"].isEnabled)

        let create = app.descendants(matching: .any)["settings.dataLifecycle.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertTrue(create.isEnabled)
        create.click()
        XCTAssertTrue(waitForSettingsDataLifecycleLabel(
            in: app,
            identifier: "settings.dataLifecycle.summary",
            equals: "Data lifecycle: 1 valid backups, 0 ignored entries",
            timeout: 10
        ))
        XCTAssertTrue(waitForSettingsGenerationCount(1, in: app, timeout: 8))
        let originalGeneration = settingsGenerationRows(in: app).firstMatch
        XCTAssertTrue(originalGeneration.exists)
        XCTAssertTrue(originalGeneration.label.contains("not selected"))

        app.descendants(matching: .any)["sidebar.goals"].click()
        XCTAssertTrue(app.descendants(matching: .any)["goals.page"].waitForExistence(timeout: 8))
        let initialGoals = goalRowIdentifiers(in: app)
        XCTAssertEqual(initialGoals, Set([freedomIdentifier, educationIdentifier]))
        app.descendants(matching: .any)["goals.add"].click()
        XCTAssertTrue(app.descendants(matching: .any)["goals.editor.name"].waitForExistence(timeout: 5))
        replaceText(
            in: app.descendants(matching: .any)["goals.editor.name"],
            with: "Synthetic Restore Probe Goal"
        )
        replaceText(
            in: app.descendants(matching: .any)["goals.editor.target"],
            with: "123456"
        )
        app.descendants(matching: .any)["goals.editor.save"].click()
        XCTAssertTrue(waitForNonexistence(
            app.descendants(matching: .any)["goals.editor.save"],
            timeout: 5
        ))
        XCTAssertTrue(waitForGoalRowCount(3, in: app, timeout: 8))
        let probeIdentifiers = goalRowIdentifiers(in: app).subtracting(initialGoals)
        XCTAssertEqual(probeIdentifiers.count, 1)
        let probeIdentifier = try XCTUnwrap(probeIdentifiers.first)
        XCTAssertTrue(waitForSettingsDataLifecycleLabelContaining(
            in: app,
            identifier: probeIdentifier,
            text: "Synthetic Restore Probe Goal",
            timeout: 5
        ))

        app.descendants(matching: .any)["sidebar.settings"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.content"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitForSettingsDataLifecycleLabel(
            in: app,
            identifier: "settings.dataLifecycle.summary",
            equals: "Data lifecycle: 1 valid backups, 0 ignored entries",
            timeout: 8
        ))
        XCTAssertTrue(waitForSettingsGenerationCount(1, in: app, timeout: 5))
        settingsGenerationRows(in: app).firstMatch.click()
        XCTAssertTrue(waitForSettingsControlEnabled(
            in: app,
            identifier: "settings.dataLifecycle.restore",
            timeout: 5
        ))
        app.descendants(matching: .any)["settings.dataLifecycle.restore"].click()
        let restoreTitle = "Restore Selected Internal Backup?"
        let restoreWarning = "Current Permanent records will be replaced. Aureus will create and validate a safety Backup before Restore. Backups contain private permanent financial records."
        let restoreSheetIdentifiers = [
            "settings.dataLifecycle.restore.dialog.heading",
            "settings.dataLifecycle.restore.dialog.warning",
            "settings.dataLifecycle.restore.cancel",
            "settings.dataLifecycle.restore.confirm"
        ]
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.restore.dialog.heading",
            expectedLabel: restoreTitle
        )
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.restore.dialog.warning",
            expectedLabel: restoreWarning
        )
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.restore.cancel",
            expectedLabel: "Cancel"
        )
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.restore.confirm",
            expectedLabel: "Restore Permanent Store"
        )
        XCTAssertTrue(app.descendants(matching: .any)["settings.dataLifecycle.restore.cancel"].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["settings.dataLifecycle.restore.confirm"].isEnabled)
        app.descendants(matching: .any)["settings.dataLifecycle.restore.cancel"].click()
        for identifier in restoreSheetIdentifiers {
            XCTAssertTrue(waitForNonexistence(
                app.descendants(matching: .any)[identifier],
                timeout: 5
            ))
        }
        XCTAssertTrue(waitForSettingsDataLifecycleLabel(
            in: app,
            identifier: "settings.dataLifecycle.summary",
            equals: "Data lifecycle: 1 valid backups, 0 ignored entries",
            timeout: 5
        ))
        XCTAssertTrue(waitForSettingsDataLifecycleLabel(
            in: app,
            identifier: "settings.dataLifecycle.status",
            equals: "Data lifecycle status: Ready",
            timeout: 5
        ))
        XCTAssertTrue(waitForSettingsGenerationCount(1, in: app, timeout: 5))
        XCTAssertFalse(settingsGenerationRows(in: app).firstMatch.label.contains("not selected"))
        XCTAssertTrue(settingsGenerationRows(in: app).firstMatch.label.contains(", selected"))
        XCTAssertTrue(waitForSettingsControlEnabled(
            in: app,
            identifier: "settings.dataLifecycle.restore",
            timeout: 5
        ))

        app.descendants(matching: .any)["settings.dataLifecycle.restore"].click()
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.restore.dialog.heading",
            expectedLabel: restoreTitle
        )
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.restore.dialog.warning",
            expectedLabel: restoreWarning
        )
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.restore.cancel",
            expectedLabel: "Cancel"
        )
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.restore.confirm",
            expectedLabel: "Restore Permanent Store"
        )
        XCTAssertTrue(app.descendants(matching: .any)["settings.dataLifecycle.restore.cancel"].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["settings.dataLifecycle.restore.confirm"].isEnabled)
        app.descendants(matching: .any)["settings.dataLifecycle.restore.confirm"].click()

        XCTAssertTrue(waitForSettingsDataLifecycleLabel(
            in: app,
            identifier: "settings.dataLifecycle.summary",
            equals: "Data lifecycle: 2 valid backups, 0 ignored entries",
            timeout: 15
        ))
        XCTAssertTrue(waitForSettingsDataLifecycleLabel(
            in: app,
            identifier: "settings.dataLifecycle.status",
            equals: "Data lifecycle status: Restore Completed",
            timeout: 5
        ))
        XCTAssertTrue(waitForSettingsGenerationCount(2, in: app, timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.recovery-required"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.error"].exists)

        app.descendants(matching: .any)["sidebar.goals"].click()
        XCTAssertTrue(app.descendants(matching: .any)["goals.page"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitForNonexistence(
            app.descendants(matching: .any)[probeIdentifier],
            timeout: 5
        ))
        XCTAssertTrue(app.descendants(matching: .any)[freedomIdentifier].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)[educationIdentifier].waitForExistence(timeout: 5))
        XCTAssertEqual(goalRowIdentifiers(in: app), initialGoals)

        app.descendants(matching: .any)["sidebar.settings"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.content"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitForSettingsGenerationCount(2, in: app, timeout: 8))
        XCTAssertTrue(settingsGenerationRows(in: app).allElementsBoundByAccessibilityElement.allSatisfy {
            $0.label.contains("not selected")
        })
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.error"].exists)
        app.terminate()

        let production = XCUIApplication()
        production.launchArguments = uiTestingArguments()
        launchApp(production)
        XCTAssertTrue(production.descendants(matching: .any)["mode.local"].waitForExistence(timeout: 10))
        production.descendants(matching: .any)["sidebar.goals"].click()
        XCTAssertTrue(production.descendants(matching: .any)["goals.empty"].waitForExistence(timeout: 8))
        XCTAssertFalse(production.descendants(matching: .any)[freedomIdentifier].exists)
        XCTAssertFalse(production.descendants(matching: .any)[educationIdentifier].exists)
        production.descendants(matching: .any)["sidebar.settings"].click()
        XCTAssertTrue(production.descendants(matching: .any)["settings.content"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitForSettingsDataLifecycleLabel(
            in: production,
            identifier: "settings.dataLifecycle.summary",
            equals: "Data lifecycle: 0 valid backups, 0 ignored entries",
            timeout: 8
        ))
        XCTAssertTrue(production.descendants(matching: .any)["settings.dataLifecycle.empty"].exists)
        XCTAssertEqual(settingsGenerationRows(in: production).count, 0)
        XCTAssertFalse(production.descendants(matching: .any)["settings.dataLifecycle.restore"].isEnabled)
        XCTAssertFalse(production.descendants(matching: .any)["settings.dataLifecycle.import"].exists)
        let productionExport = production.descendants(matching: .any)["settings.dataLifecycle.export"]
        XCTAssertTrue(productionExport.waitForExistence(timeout: 5))
        XCTAssertFalse(productionExport.isEnabled)
        XCTAssertFalse(production.descendants(matching: .any)["settings.dataLifecycle.recovery-required"].exists)
        XCTAssertFalse(production.descendants(matching: .any)["settings.status"].exists)
        XCTAssertTrue(waitForSettingsDataLifecycleLabelContaining(
            in: production,
            identifier: "settings.provider.lastValidation",
            text: "Not verified",
            timeout: 5
        ))
        production.terminate()
    }

    @MainActor
    func testStage11SettingsExternalBackupExportToUserSelectedFolderAndIsolation() throws {
        let warning = "External Backups contain private permanent financial records and are not encrypted by Aureus. Choose a private encrypted storage location you control. Do not choose a source-code repository or public/shared folder."
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AureusSettingsExternalExportUITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = testRoot.appendingPathComponent("SelectedDestination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }

        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments(demo: true)
        launchApp(app)
        app.descendants(matching: .any)["sidebar.settings"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.content"].waitForExistence(timeout: 10))

        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.externalExport.heading",
            expectedLabel: "External Backup Export"
        )
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.externalExport.warning",
            expectedLabel: warning
        )
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.export",
            expectedLabel: "Export Selected Backup…"
        )
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.export"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.externalExport.result"].exists)

        let create = app.descendants(matching: .any)["settings.dataLifecycle.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertTrue(create.isEnabled)
        create.click()
        XCTAssertTrue(waitForSettingsDataLifecycleLabel(
            in: app,
            identifier: "settings.dataLifecycle.summary",
            equals: "Data lifecycle: 1 valid backups, 0 ignored entries",
            timeout: 10
        ))
        XCTAssertTrue(waitForSettingsGenerationCount(1, in: app, timeout: 8))
        settingsGenerationRows(in: app).firstMatch.click()
        XCTAssertTrue(waitForSettingsControlEnabled(
            in: app,
            identifier: "settings.dataLifecycle.export",
            timeout: 5
        ))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), [])

        app.descendants(matching: .any)["settings.dataLifecycle.export"].click()
        XCTAssertTrue(
            app.sheets.firstMatch.waitForExistence(timeout: 5)
                || app.dialogs.firstMatch.waitForExistence(timeout: 5),
            "Native directory-selection panel did not appear"
        )
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNativePanelToDisappear(in: app, timeout: 5))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), [])
        XCTAssertTrue(waitForSettingsGenerationCount(1, in: app, timeout: 5))
        XCTAssertEqual(
            app.descendants(matching: .any)["settings.dataLifecycle.summary"].label,
            "Data lifecycle: 1 valid backups, 0 ignored entries"
        )
        let selectedGeneration = settingsGenerationRows(in: app).firstMatch
        XCTAssertTrue(selectedGeneration.exists)
        XCTAssertTrue(selectedGeneration.label.contains(", selected"))
        XCTAssertFalse(selectedGeneration.label.contains("not selected"))
        XCTAssertTrue(waitForSettingsDataLifecycleLabel(
            in: app,
            identifier: "settings.dataLifecycle.status",
            equals: "Data lifecycle status: Ready",
            timeout: 5
        ))
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.externalExport.result"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.error"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.recovery-required"].exists)
        XCTAssertTrue(waitForSettingsControlEnabled(
            in: app,
            identifier: "settings.dataLifecycle.export",
            timeout: 5
        ))

        app.descendants(matching: .any)["settings.dataLifecycle.export"].click()
        chooseDirectory(destination.path, in: app)
        XCTAssertTrue(waitForSettingsDataLifecycleLabel(
            in: app,
            identifier: "settings.dataLifecycle.status",
            equals: "Data lifecycle status: External Backup Export Completed",
            timeout: 10
        ))

        let externalEntries = try FileManager.default.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        XCTAssertEqual(externalEntries.count, 1)
        let generation = try XCTUnwrap(externalEntries.first)
        let generationValues = try generation.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        XCTAssertEqual(generationValues.isDirectory, true)
        XCTAssertNotEqual(generationValues.isSymbolicLink, true)
        let artifactURLs = try FileManager.default.contentsOfDirectory(
            at: generation,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        XCTAssertEqual(Set(artifactURLs.map(\.lastPathComponent)), Set(["aureus.sqlite", "manifest.json"]))
        for artifact in artifactURLs {
            let values = try artifact.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            XCTAssertEqual(values.isRegularFile, true)
            XCTAssertNotEqual(values.isSymbolicLink, true)
        }
        let databaseURL = generation.appendingPathComponent("aureus.sqlite")
        let manifestURL = generation.appendingPathComponent("manifest.json")
        let databaseBytes = try XCTUnwrap(
            (try FileManager.default.attributesOfItem(atPath: databaseURL.path)[.size] as? NSNumber)?.int64Value
        )
        XCTAssertGreaterThan(databaseBytes, 0)
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        XCTAssertEqual((manifest["backupFormatVersion"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual((manifest["schemaVersion"] as? NSNumber)?.intValue, 6)
        XCTAssertEqual((manifest["databaseByteCount"] as? NSNumber)?.int64Value, databaseBytes)
        let resultLabel = "External Backup export completed: schema 6, \(databaseBytes) bytes."
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.externalExport.result",
            expectedLabel: resultLabel
        )
        XCTAssertTrue(waitForSettingsGenerationCount(1, in: app, timeout: 5))
        XCTAssertTrue(waitForSettingsDataLifecycleLabel(
            in: app,
            identifier: "settings.dataLifecycle.summary",
            equals: "Data lifecycle: 1 valid backups, 0 ignored entries",
            timeout: 5
        ))
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.error"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.recovery-required"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.import"].exists)

        let exportedSnapshot = try externalExportSnapshot(at: destination)
        app.descendants(matching: .any)["sidebar.dashboard"].click()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.content"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["sidebar.settings"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.content"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitForSettingsGenerationCount(1, in: app, timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.externalExport.result"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.export"].isEnabled)
        XCTAssertEqual(try externalExportSnapshot(at: destination), exportedSnapshot)
        app.terminate()

        let production = XCUIApplication()
        production.launchArguments = uiTestingArguments()
        launchApp(production)
        XCTAssertTrue(production.descendants(matching: .any)["mode.local"].waitForExistence(timeout: 10))
        production.descendants(matching: .any)["sidebar.settings"].click()
        XCTAssertTrue(production.descendants(matching: .any)["settings.content"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitForSettingsDataLifecycleLabel(
            in: production,
            identifier: "settings.dataLifecycle.summary",
            equals: "Data lifecycle: 0 valid backups, 0 ignored entries",
            timeout: 8
        ))
        XCTAssertEqual(settingsGenerationRows(in: production).count, 0)
        let productionExport = production.descendants(matching: .any)["settings.dataLifecycle.export"]
        XCTAssertTrue(productionExport.waitForExistence(timeout: 5))
        XCTAssertFalse(productionExport.isEnabled)
        XCTAssertFalse(production.descendants(matching: .any)["settings.dataLifecycle.externalExport.result"].exists)
        XCTAssertFalse(production.descendants(matching: .any)["settings.dataLifecycle.error"].exists)
        XCTAssertFalse(production.descendants(matching: .any)["settings.dataLifecycle.recovery-required"].exists)
        XCTAssertFalse(production.descendants(matching: .any)["settings.dataLifecycle.import"].exists)
        XCTAssertFalse(production.sheets.firstMatch.exists)
        XCTAssertFalse(production.dialogs.firstMatch.exists)
        XCTAssertTrue(waitForSettingsDataLifecycleLabelContaining(
            in: production,
            identifier: "settings.provider.lastValidation",
            text: "Not verified",
            timeout: 5
        ))
        XCTAssertEqual(try externalExportSnapshot(at: destination), exportedSnapshot)
        production.terminate()
    }

    @MainActor
    func testStage11SettingsExternalBackupRestoreFromUserSelectedGenerationAndIsolation() throws {
        let warning = "External Restore will replace current Permanent records. Aureus will validate the selected two-file Backup and create and validate an internal safety Backup before replacement. External Backups contain private permanent financial records and are not encrypted by Aureus."
        let freedomIdentifier = "goals.goal.00000000-0000-4000-8000-000000010001"
        let educationIdentifier = "goals.goal.00000000-0000-4000-8000-000000010002"
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AureusSettingsExternalRestoreUITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = testRoot.appendingPathComponent("SelectedDestination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }

        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments(demo: true)
        launchApp(app)
        app.descendants(matching: .any)["sidebar.settings"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.content"].waitForExistence(timeout: 10))

        let create = app.descendants(matching: .any)["settings.dataLifecycle.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertTrue(create.isEnabled)
        create.click()
        XCTAssertTrue(waitForSettingsDataLifecycleLabel(
            in: app,
            identifier: "settings.dataLifecycle.summary",
            equals: "Data lifecycle: 1 valid backups, 0 ignored entries",
            timeout: 10
        ))
        XCTAssertTrue(waitForSettingsGenerationCount(1, in: app, timeout: 8))
        settingsGenerationRows(in: app).firstMatch.click()
        XCTAssertTrue(waitForSettingsControlEnabled(
            in: app,
            identifier: "settings.dataLifecycle.export",
            timeout: 5
        ))
        app.descendants(matching: .any)["settings.dataLifecycle.export"].click()
        chooseDirectory(destination.path, in: app)
        XCTAssertTrue(waitForSettingsDataLifecycleLabel(
            in: app,
            identifier: "settings.dataLifecycle.status",
            equals: "Data lifecycle status: External Backup Export Completed",
            timeout: 10
        ))

        let externalEntries = try FileManager.default.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        XCTAssertEqual(externalEntries.count, 1)
        let externalGeneration = try XCTUnwrap(externalEntries.first)
        let generationValues = try externalGeneration.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        XCTAssertEqual(generationValues.isDirectory, true)
        XCTAssertNotEqual(generationValues.isSymbolicLink, true)
        let artifactURLs = try FileManager.default.contentsOfDirectory(
            at: externalGeneration,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        XCTAssertEqual(Set(artifactURLs.map(\.lastPathComponent)), Set(["aureus.sqlite", "manifest.json"]))
        for artifact in artifactURLs {
            let values = try artifact.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            XCTAssertEqual(values.isRegularFile, true)
            XCTAssertNotEqual(values.isSymbolicLink, true)
        }
        let databaseURL = externalGeneration.appendingPathComponent("aureus.sqlite")
        let manifestURL = externalGeneration.appendingPathComponent("manifest.json")
        let databaseBytes = try XCTUnwrap(
            (try FileManager.default.attributesOfItem(atPath: databaseURL.path)[.size] as? NSNumber)?.int64Value
        )
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        XCTAssertEqual((manifest["backupFormatVersion"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual((manifest["schemaVersion"] as? NSNumber)?.intValue, 6)
        XCTAssertEqual((manifest["databaseByteCount"] as? NSNumber)?.int64Value, databaseBytes)
        let externalSnapshot = try externalExportSnapshot(at: destination)

        app.descendants(matching: .any)["sidebar.goals"].click()
        XCTAssertTrue(app.descendants(matching: .any)["goals.page"].waitForExistence(timeout: 8))
        let originalGoals = goalRowIdentifiers(in: app)
        XCTAssertEqual(originalGoals, Set([freedomIdentifier, educationIdentifier]))
        app.descendants(matching: .any)["goals.add"].click()
        XCTAssertTrue(app.descendants(matching: .any)["goals.editor.name"].waitForExistence(timeout: 5))
        replaceText(
            in: app.descendants(matching: .any)["goals.editor.name"],
            with: "Synthetic External Restore Probe Goal"
        )
        replaceText(in: app.descendants(matching: .any)["goals.editor.target"], with: "123456")
        app.descendants(matching: .any)["goals.editor.save"].click()
        XCTAssertTrue(waitForNonexistence(
            app.descendants(matching: .any)["goals.editor.save"],
            timeout: 5
        ))
        XCTAssertTrue(waitForGoalRowCount(3, in: app, timeout: 8))
        let probeIdentifiers = goalRowIdentifiers(in: app).subtracting(originalGoals)
        XCTAssertEqual(probeIdentifiers.count, 1)
        let probeIdentifier = try XCTUnwrap(probeIdentifiers.first)
        XCTAssertTrue(waitForSettingsDataLifecycleLabelContaining(
            in: app,
            identifier: probeIdentifier,
            text: "Synthetic External Restore Probe Goal",
            timeout: 5
        ))

        app.descendants(matching: .any)["sidebar.settings"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.content"].waitForExistence(timeout: 8))
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.externalRestore.heading",
            expectedLabel: "External Backup Restore"
        )
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.externalRestore.warning",
            expectedLabel: warning
        )
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.externalRestore",
            expectedLabel: "Restore External Backup…"
        )
        XCTAssertTrue(waitForSettingsControlEnabled(
            in: app,
            identifier: "settings.dataLifecycle.externalRestore",
            timeout: 5
        ))
        XCTAssertTrue(waitForSettingsGenerationCount(1, in: app, timeout: 5))

        app.descendants(matching: .any)["settings.dataLifecycle.externalRestore"].click()
        XCTAssertTrue(
            app.sheets.firstMatch.waitForExistence(timeout: 5)
                || app.dialogs.firstMatch.waitForExistence(timeout: 5),
            "Native External Restore directory-selection panel did not appear"
        )
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNativePanelToDisappear(in: app, timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)[
            "settings.dataLifecycle.externalRestore.dialog.heading"
        ].exists)
        XCTAssertTrue(waitForSettingsGenerationCount(1, in: app, timeout: 5))
        XCTAssertTrue(waitForSettingsDataLifecycleLabel(
            in: app,
            identifier: "settings.dataLifecycle.status",
            equals: "Data lifecycle status: Ready",
            timeout: 5
        ))
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.externalRestore.result"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.error"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.recovery-required"].exists)
        XCTAssertEqual(try externalExportSnapshot(at: destination), externalSnapshot)
        app.descendants(matching: .any)["sidebar.goals"].click()
        XCTAssertTrue(app.descendants(matching: .any)[probeIdentifier].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForGoalRowCount(3, in: app, timeout: 5))

        app.descendants(matching: .any)["sidebar.settings"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.content"].waitForExistence(timeout: 8))
        let confirmationIdentifiers = [
            "settings.dataLifecycle.externalRestore.dialog.heading",
            "settings.dataLifecycle.externalRestore.dialog.warning",
            "settings.dataLifecycle.externalRestore.cancel",
            "settings.dataLifecycle.externalRestore.confirm"
        ]
        app.descendants(matching: .any)["settings.dataLifecycle.externalRestore"].click()
        chooseDirectory(externalGeneration.path, in: app)
        assertExternalRestoreConfirmation(in: app, warning: warning)
        XCTAssertTrue(app.descendants(matching: .any)[
            "settings.dataLifecycle.externalRestore.cancel"
        ].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)[
            "settings.dataLifecycle.externalRestore.confirm"
        ].isEnabled)
        app.descendants(matching: .any)["settings.dataLifecycle.externalRestore.cancel"].click()
        for identifier in confirmationIdentifiers {
            XCTAssertTrue(waitForNonexistence(
                app.descendants(matching: .any)[identifier],
                timeout: 5
            ))
        }
        XCTAssertTrue(waitForSettingsGenerationCount(1, in: app, timeout: 5))
        XCTAssertTrue(waitForSettingsDataLifecycleLabel(
            in: app,
            identifier: "settings.dataLifecycle.status",
            equals: "Data lifecycle status: Ready",
            timeout: 5
        ))
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.externalRestore.result"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.error"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.recovery-required"].exists)
        XCTAssertEqual(try externalExportSnapshot(at: destination), externalSnapshot)
        app.descendants(matching: .any)["sidebar.goals"].click()
        XCTAssertTrue(app.descendants(matching: .any)[probeIdentifier].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForGoalRowCount(3, in: app, timeout: 5))

        app.descendants(matching: .any)["sidebar.settings"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.content"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitForSettingsControlEnabled(
            in: app,
            identifier: "settings.dataLifecycle.externalRestore",
            timeout: 5
        ))
        app.descendants(matching: .any)["settings.dataLifecycle.externalRestore"].click()
        chooseDirectory(externalGeneration.path, in: app)
        assertExternalRestoreConfirmation(in: app, warning: warning)
        app.descendants(matching: .any)["settings.dataLifecycle.externalRestore.confirm"].click()

        XCTAssertTrue(waitForSettingsDataLifecycleLabel(
            in: app,
            identifier: "settings.dataLifecycle.status",
            equals: "Data lifecycle status: External Backup Restore Completed",
            timeout: 15
        ))
        XCTAssertTrue(waitForSettingsDataLifecycleLabel(
            in: app,
            identifier: "settings.dataLifecycle.summary",
            equals: "Data lifecycle: 2 valid backups, 0 ignored entries",
            timeout: 8
        ))
        XCTAssertTrue(waitForSettingsGenerationCount(2, in: app, timeout: 8))
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.externalRestore.result",
            expectedLabel: "External Backup Restore completed: source schema 6, final schema 6, \(databaseBytes) bytes."
        )
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.error"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.recovery-required"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.import"].exists)
        XCTAssertEqual(try externalExportSnapshot(at: destination), externalSnapshot)

        app.descendants(matching: .any)["sidebar.goals"].click()
        XCTAssertTrue(app.descendants(matching: .any)["goals.page"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitForNonexistence(app.descendants(matching: .any)[probeIdentifier], timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)[freedomIdentifier].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)[educationIdentifier].waitForExistence(timeout: 5))
        XCTAssertEqual(goalRowIdentifiers(in: app), originalGoals)

        app.descendants(matching: .any)["sidebar.settings"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.content"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitForSettingsGenerationCount(2, in: app, timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["settings.dataLifecycle.externalRestore.result"].exists)
        XCTAssertFalse(app.sheets.firstMatch.exists)
        XCTAssertFalse(app.dialogs.firstMatch.exists)
        XCTAssertTrue(waitForSettingsControlEnabled(
            in: app,
            identifier: "settings.dataLifecycle.externalRestore",
            timeout: 5
        ))
        XCTAssertEqual(try externalExportSnapshot(at: destination), externalSnapshot)
        app.terminate()

        let production = XCUIApplication()
        production.launchArguments = uiTestingArguments()
        launchApp(production)
        XCTAssertTrue(production.descendants(matching: .any)["mode.local"].waitForExistence(timeout: 10))
        production.descendants(matching: .any)["sidebar.goals"].click()
        XCTAssertTrue(production.descendants(matching: .any)["goals.empty"].waitForExistence(timeout: 8))
        XCTAssertFalse(production.descendants(matching: .any)[freedomIdentifier].exists)
        XCTAssertFalse(production.descendants(matching: .any)[educationIdentifier].exists)
        XCTAssertFalse(production.descendants(matching: .any)[probeIdentifier].exists)
        production.descendants(matching: .any)["sidebar.settings"].click()
        XCTAssertTrue(production.descendants(matching: .any)["settings.content"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitForSettingsDataLifecycleLabel(
            in: production,
            identifier: "settings.dataLifecycle.summary",
            equals: "Data lifecycle: 0 valid backups, 0 ignored entries",
            timeout: 8
        ))
        XCTAssertEqual(settingsGenerationRows(in: production).count, 0)
        let productionExternalRestore = production.descendants(matching: .any)[
            "settings.dataLifecycle.externalRestore"
        ]
        XCTAssertTrue(productionExternalRestore.waitForExistence(timeout: 5))
        XCTAssertTrue(productionExternalRestore.isEnabled)
        XCTAssertFalse(production.descendants(matching: .any)[
            "settings.dataLifecycle.externalRestore.result"
        ].exists)
        XCTAssertFalse(production.descendants(matching: .any)["settings.dataLifecycle.error"].exists)
        XCTAssertFalse(production.descendants(matching: .any)["settings.dataLifecycle.recovery-required"].exists)
        XCTAssertFalse(production.descendants(matching: .any)["settings.dataLifecycle.import"].exists)
        XCTAssertFalse(production.sheets.firstMatch.exists)
        XCTAssertFalse(production.dialogs.firstMatch.exists)
        XCTAssertTrue(waitForSettingsDataLifecycleLabelContaining(
            in: production,
            identifier: "settings.provider.lastValidation",
            text: "Not verified",
            timeout: 5
        ))
        XCTAssertEqual(try externalExportSnapshot(at: destination), externalSnapshot)
        production.terminate()
    }

    @MainActor
    func testWealthCNYUSDLiabilityCRUDAndDynamicTotals() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments() + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        launchApp(app)
        defer { dismissResidualNativePanels(in: app); app.terminate() }
        app.descendants(matching: .any)["sidebar.wealth"].click()
        XCTAssertTrue(app.descendants(matching: .any)["wealth.empty.add"].waitForExistence(timeout: 10))
        assertSummary(app: app, assets: "0.00", liabilities: "0.00", netWorth: "0.00")

        addContainer(
            app: app,
            name: "Synthetic CNY Wallet",
            kind: "Bank / Cash",
            amount: "100.00",
            currency: "CNY",
            fxRate: nil
        )
        XCTAssertTrue(waitForRowCount(1, in: app, timeout: 5))
        assertSummary(app: app, assets: "100.00", liabilities: "0.00", netWorth: "100.00")

        addContainer(
            app: app,
            name: "Synthetic USD Wallet",
            kind: "Bank / Cash",
            amount: "10.00",
            currency: "USD",
            fxRate: "7.00"
        )
        XCTAssertTrue(waitForRowCount(2, in: app, timeout: 5))
        assertSummary(app: app, assets: "170.00", liabilities: "0.00", netWorth: "170.00")

        addContainer(
            app: app,
            name: "Synthetic CNY Liability",
            kind: "Liability",
            amount: "30.00",
            currency: "CNY",
            fxRate: nil
        )
        XCTAssertTrue(waitForRowCount(3, in: app, timeout: 5))
        assertSummary(app: app, assets: "170.00", liabilities: "30.00", netWorth: "140.00")

        selectRow(app: app, kind: "liability", currency: "cny")
        app.descendants(matching: .any)["wealth.edit"].click()
        XCTAssertTrue(app.descendants(matching: .any)["wealth.form.intent"].waitForExistence(timeout: 5))
        wealthAcceptanceChooseIntent(app: app, title: "Record new current valuation")
        let amountField = app.descendants(matching: .any)["wealth.form.amount"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 5))
        amountField.click()
        amountField.typeKey("a", modifierFlags: .command)
        amountField.typeText("40.00")
        app.descendants(matching: .any)["wealth.form.save"].click()
        XCTAssertFalse(app.descendants(matching: .any)["wealth.form.save"].waitForExistence(timeout: 2))
        assertSummary(app: app, assets: "170.00", liabilities: "40.00", netWorth: "130.00")

        selectRow(app: app, kind: "liability", currency: "cny")
        deleteSelectedContainer(app: app)
        XCTAssertTrue(waitForRowCount(2, in: app, timeout: 5))
        assertSummary(app: app, assets: "170.00", liabilities: "0.00", netWorth: "170.00")

        selectRow(app: app, kind: "bankCash", currency: "usd")
        deleteSelectedContainer(app: app)
        XCTAssertTrue(waitForRowCount(1, in: app, timeout: 5))
        assertSummary(app: app, assets: "100.00", liabilities: "0.00", netWorth: "100.00")
    }

    @MainActor
    func testWealthCorrectionReasonCancelAndHistory() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments() + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        launchApp(app)
        defer { dismissResidualNativePanels(in: app); app.terminate() }
        app.descendants(matching: .any)["sidebar.wealth"].click()
        XCTAssertTrue(app.descendants(matching: .any)["wealth.empty.add"].waitForExistence(timeout: 10))
        addContainer(app: app, name: "Synthetic Wealth Correction Cash", kind: "Bank / Cash",
            amount: "100.00", currency: "CNY", fxRate: nil)
        XCTAssertTrue(waitForRowCount(1, in: app, timeout: 5))
        assertSummary(app: app, assets: "100.00", liabilities: "0.00", netWorth: "100.00")
        wealthAcceptanceOpenHistory(app: app, name: "Synthetic Wealth Correction Cash",
            kind: "bankCash", currency: "cny")
        XCTAssertTrue(wealthAcceptanceHistorySheet(app).descendants(matching: .any)
            .matching(identifier: "wealth.history.empty").element.waitForExistence(timeout: 5))
        wealthAcceptanceCloseHistory(app: app)

        wealthAcceptanceOpenEdit(app: app, name: "Synthetic Wealth Correction Cash",
            kind: "bankCash", currency: "cny", amount: "100")
        wealthAcceptanceAssertIntent(app: app, title: "Correct existing record", select: false)
        replaceText(in: app.descendants(matching: .any)["wealth.form.amount"], with: "125.00")
        let reason = app.descendants(matching: .any)["wealth.form.correctionReason"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["wealth.form.save"].isEnabled)
        wealthAcceptanceScreenshot(app, name: "Synthetic Wealth correction reason required")
        replaceText(in: reason, with: "Synthetic first correction")
        XCTAssertTrue(app.descendants(matching: .any)["wealth.form.save"].isEnabled)
        app.descendants(matching: .any)["wealth.form.cancel"].click()
        XCTAssertTrue(waitForNonexistence(app.descendants(matching: .any)["wealth.form.save"], timeout: 5))
        assertSummary(app: app, assets: "100.00", liabilities: "0.00", netWorth: "100.00")
        wealthAcceptanceOpenHistory(app: app, name: "Synthetic Wealth Correction Cash",
            kind: "bankCash", currency: "cny")
        XCTAssertTrue(wealthAcceptanceHistorySheet(app).descendants(matching: .any)
            .matching(identifier: "wealth.history.empty").element.waitForExistence(timeout: 5))
        wealthAcceptanceCloseHistory(app: app)

        wealthAcceptanceOpenEdit(app: app, name: "Synthetic Wealth Correction Cash",
            kind: "bankCash", currency: "cny", amount: "100")
        replaceText(in: app.descendants(matching: .any)["wealth.form.amount"], with: "125.00")
        replaceText(in: app.descendants(matching: .any)["wealth.form.correctionReason"],
            with: "Synthetic first correction")
        wealthAcceptanceSave(app: app)
        assertSummary(app: app, assets: "125.00", liabilities: "0.00", netWorth: "125.00")
        wealthAcceptanceOpenHistory(app: app, name: "Synthetic Wealth Correction Cash",
            kind: "bankCash", currency: "cny")
        let first = try wealthAcceptanceHistoryRows(app: app, expected: 1)[0]
        XCTAssertTrue(first.reason.contains("Synthetic first correction"))
        XCTAssertTrue(first.before.contains("original CNY 100.00"))
        XCTAssertTrue(first.after.contains("original CNY 125.00"))
        XCTAssertTrue(first.before.contains("CNY CNY 100.00"))
        XCTAssertTrue(first.after.contains("CNY CNY 125.00"))
        wealthAcceptanceCloseHistory(app: app)

        wealthAcceptanceOpenEdit(app: app, name: "Synthetic Wealth Correction Cash",
            kind: "bankCash", currency: "cny", amount: "125")
        replaceText(in: app.descendants(matching: .any)["wealth.form.amount"], with: "150.00")
        replaceText(in: app.descendants(matching: .any)["wealth.form.correctionReason"],
            with: "Synthetic second correction")
        wealthAcceptanceSave(app: app)
        assertSummary(app: app, assets: "150.00", liabilities: "0.00", netWorth: "150.00")
        wealthAcceptanceOpenHistory(app: app, name: "Synthetic Wealth Correction Cash",
            kind: "bankCash", currency: "cny")
        let rows = try wealthAcceptanceHistoryRows(app: app, expected: 2)
        XCTAssertEqual(rows[0].id, first.id)
        XCTAssertNotEqual(rows[1].id, first.id)
        XCTAssertLessThan(rows[0].sequence, rows[1].sequence)
        XCTAssertEqual(rows[0].before, first.before)
        XCTAssertEqual(rows[0].after, first.after)
        XCTAssertTrue(rows[1].reason.contains("Synthetic second correction"))
        XCTAssertTrue(rows[1].before.contains("original CNY 125.00"))
        XCTAssertTrue(rows[1].after.contains("original CNY 150.00"))
        XCTAssertTrue(rows[1].before.contains("CNY CNY 125.00"))
        XCTAssertTrue(rows[1].after.contains("CNY CNY 150.00"))
        XCTAssertEqual(wealthAcceptanceHistorySheet(app).buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "Apply", "Edit")).count, 0)
        wealthAcceptanceScreenshot(app, name: "Synthetic Wealth two correction histories")
        wealthAcceptanceCloseHistory(app: app)
        wealthAcceptanceOpenHistory(app: app, name: "Synthetic Wealth Correction Cash",
            kind: "bankCash", currency: "cny")
        let reopened = try wealthAcceptanceHistoryRows(app: app, expected: 2)
        XCTAssertEqual(reopened.map(\.id), rows.map(\.id))
        XCTAssertEqual(reopened.map(\.before), rows.map(\.before))
        XCTAssertEqual(reopened.map(\.after), rows.map(\.after))
        wealthAcceptanceCloseHistory(app: app)
    }

    @MainActor
    func testWealthValuationIntentUSDAndHistory() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments(demo: true)
            + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        launchApp(app)
        defer { dismissResidualNativePanels(in: app); app.terminate() }
        app.descendants(matching: .any)["sidebar.wealth"].click()
        let name = "Synthetic USD Cash Lab"
        XCTAssertTrue(app.descendants(matching: .any)["wealth.row.bankCash.usd"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForValueOrLabel(app.descendants(matching: .any)["wealth.row.bankCash.usd"],
            containing: "original USD 1,000.00", timeout: 5))
        wealthAcceptanceOpenHistory(app: app, name: name, kind: "bankCash", currency: "usd")
        XCTAssertTrue(wealthAcceptanceHistorySheet(app).descendants(matching: .any)
            .matching(identifier: "wealth.history.empty").element.waitForExistence(timeout: 5))
        wealthAcceptanceCloseHistory(app: app)
        wealthAcceptanceOpenEdit(app: app, name: name, kind: "bankCash", currency: "usd", amount: "1000")
        wealthAcceptanceChooseIntent(app: app, title: "Record new current valuation")
        XCTAssertFalse(app.descendants(matching: .any)["wealth.form.name"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["wealth.form.institution"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["wealth.form.currency"].isEnabled)
        replaceText(in: app.descendants(matching: .any)["wealth.form.amount"], with: "1100.00")
        wealthAcceptanceSave(app: app)
        XCTAssertTrue(waitForValueOrLabel(app.descendants(matching: .any)["wealth.row.bankCash.usd"],
            containing: "converted CNY 7,837.50", timeout: 5))
        wealthAcceptanceOpenHistory(app: app, name: name, kind: "bankCash", currency: "usd")
        XCTAssertTrue(wealthAcceptanceHistorySheet(app).descendants(matching: .any)
            .matching(identifier: "wealth.history.empty").element.waitForExistence(timeout: 5))
        wealthAcceptanceCloseHistory(app: app)

        wealthAcceptanceOpenEdit(app: app, name: name, kind: "bankCash", currency: "usd", amount: "1100")
        replaceText(in: app.descendants(matching: .any)["wealth.form.amount"], with: "1200.00")
        replaceText(in: app.descendants(matching: .any)["wealth.form.correctionReason"],
            with: "Synthetic USD amount correction")
        wealthAcceptanceSave(app: app)
        XCTAssertTrue(waitForValueOrLabel(app.descendants(matching: .any)["wealth.row.bankCash.usd"],
            containing: "converted CNY 8,550.00", timeout: 5))
        wealthAcceptanceOpenHistory(app: app, name: name, kind: "bankCash", currency: "usd")
        let first = try wealthAcceptanceHistoryRows(app: app, expected: 1)[0]
        XCTAssertTrue(first.reason.contains("Synthetic USD amount correction"))
        XCTAssertTrue(first.before.contains("original USD 1,100.00"))
        XCTAssertTrue(first.after.contains("original USD 1,200.00"))
        XCTAssertTrue(first.before.contains("CNY CNY 7,837.50"))
        XCTAssertTrue(first.after.contains("CNY CNY 8,550.00"))
        for value in [first.before, first.after] {
            XCTAssertTrue(value.contains("USD→CNY 7.1250000000"))
            XCTAssertTrue(value.contains("FX source manual.synthetic.stage3"))
            XCTAssertTrue(value.contains("reference 2026-01-15"))
            XCTAssertTrue(value.contains("fetched UTC ms 1768435200000"))
            XCTAssertTrue(value.contains("manual true, stale false"))
        }
        wealthAcceptanceCloseHistory(app: app)

        wealthAcceptanceOpenEdit(app: app, name: name, kind: "bankCash", currency: "usd", amount: "1200")
        replaceText(in: app.descendants(matching: .any)["wealth.form.fx.rate"], with: "7.50")
        replaceText(in: app.descendants(matching: .any)["wealth.form.correctionReason"],
            with: "Synthetic USD FX correction")
        wealthAcceptanceSave(app: app)
        XCTAssertTrue(waitForValueOrLabel(app.descendants(matching: .any)["wealth.row.bankCash.usd"],
            containing: "converted CNY 9,000.00", timeout: 5))
        wealthAcceptanceOpenHistory(app: app, name: name, kind: "bankCash", currency: "usd")
        let rows = try wealthAcceptanceHistoryRows(app: app, expected: 2)
        XCTAssertEqual(rows[0].id, first.id)
        XCTAssertNotEqual(rows[1].id, first.id)
        XCTAssertLessThan(rows[0].sequence, rows[1].sequence)
        XCTAssertEqual(rows[0].before, first.before)
        XCTAssertEqual(rows[0].after, first.after)
        XCTAssertTrue(rows[1].reason.contains("Synthetic USD FX correction"))
        XCTAssertTrue(rows[1].before.contains("original USD 1,200.00"))
        XCTAssertTrue(rows[1].after.contains("original USD 1,200.00"))
        XCTAssertTrue(rows[1].before.contains("CNY CNY 8,550.00"))
        XCTAssertTrue(rows[1].after.contains("CNY CNY 9,000.00"))
        XCTAssertTrue(rows[1].before.contains("USD→CNY 7.1250000000"))
        XCTAssertTrue(rows[1].after.contains("USD→CNY 7.5000000000"))
        XCTAssertTrue(rows[1].before.contains("FX source manual.synthetic.stage3"))
        XCTAssertTrue(rows[1].after.contains("FX source manual"))
        XCTAssertTrue(rows[1].after.contains("manual true, stale false"))
        wealthAcceptanceScreenshot(app, name: "Synthetic Wealth USD valuation and FX history")
        wealthAcceptanceCloseHistory(app: app)
        wealthAcceptanceOpenHistory(app: app, name: name, kind: "bankCash", currency: "usd")
        let reopened = try wealthAcceptanceHistoryRows(app: app, expected: 2)
        XCTAssertEqual(reopened.map(\.id), rows.map(\.id))
        XCTAssertEqual(reopened.map(\.before), rows.map(\.before))
        XCTAssertEqual(reopened.map(\.after), rows.map(\.after))
        wealthAcceptanceCloseHistory(app: app)
        XCTAssertTrue(waitForValueOrLabel(app.descendants(matching: .any)["wealth.summary.netWorth"],
            containing: "CNY 152,547.06", timeout: 5))
    }

    @MainActor
    func testLedgerDynamicCashFlowTransferInvestmentEditAndDelete() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments() + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        launchApp(app)
        defer {
            dismissResidualNativePanels(in: app)
            app.terminate()
        }

        app.descendants(matching: .any)["sidebar.wealth"].click()
        XCTAssertTrue(app.descendants(matching: .any)["wealth.empty.add"].waitForExistence(timeout: 10))
        addContainer(app: app, name: "Synthetic Ledger Cash A", kind: "Bank / Cash", amount: "1000.00", currency: "CNY", fxRate: nil)
        addContainer(app: app, name: "Synthetic Ledger Cash B", kind: "Bank / Cash", amount: "500.00", currency: "CNY", fxRate: nil)

        app.descendants(matching: .any)["sidebar.ledger"].click()
        XCTAssertTrue(app.descendants(matching: .any)["ledger.empty"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["ledger.taxonomy"].exists)

        app.descendants(matching: .any)["ledger.taxonomy"].click()
        replaceText(in: app.descendants(matching: .any)["ledger.category.name"], with: "Synthetic UI Category")
        app.descendants(matching: .any)["ledger.category.add"].click()
        replaceText(in: app.descendants(matching: .any)["ledger.tag.name"], with: "Synthetic UI Tag")
        app.descendants(matching: .any)["ledger.tag.add"].click()
        XCTAssertTrue(app.staticTexts["Synthetic UI Category"].waitForExistence(timeout: 5) || app.textFields.matching(NSPredicate(format: "value == %@", "Synthetic UI Category")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].click()

        app.descendants(matching: .any)["ledger.rules"].click()
        app.descendants(matching: .any)["ledger.rule.add"].click()
        replaceText(in: app.descendants(matching: .any)["ledger.rule.name"], with: "Synthetic UI Rule")
        replaceText(in: app.descendants(matching: .any)["ledger.rule.priority"], with: "7")
        replaceText(in: app.descendants(matching: .any)["ledger.rule.pattern"], with: "Synthetic UI Payee")
        selectPicker(app: app, identifier: "ledger.rule.kind", title: "Expense")
        selectPicker(app: app, identifier: "ledger.rule.category", title: "Synthetic UI Category")
        let ruleTag = app.checkBoxes["Synthetic UI Tag"]
        XCTAssertTrue(ruleTag.waitForExistence(timeout: 5)); ruleTag.click()
        app.descendants(matching: .any)["ledger.rule.save"].click()
        XCTAssertTrue(app.staticTexts["Synthetic UI Rule"].waitForExistence(timeout: 5))
        let enabled = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "ledger.rule.enabled."))
            .firstMatch
        XCTAssertTrue(enabled.waitForExistence(timeout: 5)); enabled.click(); enabled.click()
        app.buttons["Edit"].firstMatch.click()
        replaceText(in: app.descendants(matching: .any)["ledger.rule.name"], with: "Synthetic UI Rule Updated")
        app.descendants(matching: .any)["ledger.rule.save"].click()
        XCTAssertTrue(app.staticTexts["Synthetic UI Rule Updated"].waitForExistence(timeout: 5))
        app.buttons["Delete"].firstMatch.click()
        XCTAssertFalse(app.staticTexts["Synthetic UI Rule Updated"].waitForExistence(timeout: 2))
        app.buttons["Done"].click()

        addLedgerEntry(app: app, kind: "Income", description: "Synthetic UI Income", amount: "100.00")
        assertLedgerSummary(app: app, ordinaryInflow: "100.00", ordinaryOutflow: "0.00", investmentInflow: "0.00", investmentOutflow: "0.00", net: "100.00", transfers: "0")

        addLedgerEntry(
            app: app, kind: "Expense", description: "Synthetic UI Expense", amount: "30.00",
            category: "Synthetic UI Category", tag: "Synthetic UI Tag"
        )
        assertLedgerSummary(app: app, ordinaryInflow: "100.00", ordinaryOutflow: "30.00", investmentInflow: "0.00", investmentOutflow: "0.00", net: "70.00", transfers: "0")

        addLedgerEntry(app: app, kind: "Transfer", description: "Synthetic UI Transfer", amount: "50.00", targetAmount: "50.00")
        assertLedgerSummary(app: app, ordinaryInflow: "100.00", ordinaryOutflow: "30.00", investmentInflow: "0.00", investmentOutflow: "0.00", net: "70.00", transfers: "1")

        addLedgerEntry(app: app, kind: "Buy", description: "Synthetic UI Buy", amount: "10.00")
        assertLedgerSummary(app: app, ordinaryInflow: "100.00", ordinaryOutflow: "30.00", investmentInflow: "0.00", investmentOutflow: "10.00", net: "60.00", transfers: "1")

        selectLedgerKindFilter(app: app, title: "Expense")
        let editExpense = app.buttons["Edit Expense transaction"]
        XCTAssertTrue(editExpense.waitForExistence(timeout: 5)); editExpense.click()
        let amount = app.descendants(matching: .any)["ledger.form.sourceAmount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5)); replaceText(in: amount, with: "40.00")
        let correctionReason = app.descendants(matching: .any)["ledger.form.correctionReason"]
        XCTAssertTrue(correctionReason.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["ledger.form.save"].isEnabled)
        replaceText(in: correctionReason, with: "Synthetic UI amount correction")
        app.descendants(matching: .any)["ledger.form.save"].click()
        selectLedgerKindFilter(app: app, title: "All Kinds")
        assertLedgerSummary(app: app, ordinaryInflow: "100.00", ordinaryOutflow: "40.00", investmentInflow: "0.00", investmentOutflow: "10.00", net: "50.00", transfers: "1")

        selectLedgerKindFilter(app: app, title: "Buy")
        deleteLedgerEntry(app: app, kind: "Buy")
        selectLedgerKindFilter(app: app, title: "All Kinds")
        assertLedgerSummary(app: app, ordinaryInflow: "100.00", ordinaryOutflow: "40.00", investmentInflow: "0.00", investmentOutflow: "0.00", net: "60.00", transfers: "1")

        selectPicker(app: app, identifier: "ledger.filter.category", title: "Synthetic UI Category")
        assertLedgerSummary(app: app, ordinaryInflow: "0.00", ordinaryOutflow: "40.00", investmentInflow: "0.00", investmentOutflow: "0.00", net: "-40.00", transfers: "0")
        app.descendants(matching: .any)["ledger.filter.clear"].click()
        selectPicker(app: app, identifier: "ledger.filter.tag", title: "Synthetic UI Tag")
        assertLedgerSummary(app: app, ordinaryInflow: "0.00", ordinaryOutflow: "40.00", investmentInflow: "0.00", investmentOutflow: "0.00", net: "-40.00", transfers: "0")
        app.descendants(matching: .any)["ledger.filter.clear"].click()
        selectPicker(app: app, identifier: "ledger.filter.container", title: "Synthetic Ledger Cash A")
        XCTAssertTrue(app.descendants(matching: .any)["ledger.history"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["ledger.filter.clear"].click()
        replaceText(in: app.descendants(matching: .any)["ledger.filter.startDate"], with: "2026-01-15")
        replaceText(in: app.descendants(matching: .any)["ledger.filter.endDate"], with: "2026-01-15")
        app.descendants(matching: .any)["ledger.filter.applyDates"].click()
        assertLedgerSummary(app: app, ordinaryInflow: "100.00", ordinaryOutflow: "40.00", investmentInflow: "0.00", investmentOutflow: "0.00", net: "60.00", transfers: "1")
        selectLedgerKindFilter(app: app, title: "Expense")
        selectPicker(app: app, identifier: "ledger.filter.category", title: "Synthetic UI Category")
        selectPicker(app: app, identifier: "ledger.filter.tag", title: "Synthetic UI Tag")
        selectPicker(app: app, identifier: "ledger.filter.currency", title: "CNY")
        assertLedgerSummary(app: app, ordinaryInflow: "0.00", ordinaryOutflow: "40.00", investmentInflow: "0.00", investmentOutflow: "0.00", net: "-40.00", transfers: "0")
        app.descendants(matching: .any)["ledger.filter.clear"].click()
        replaceText(in: app.descendants(matching: .any)["ledger.filter.startDate"], with: "2026-02-01")
        replaceText(in: app.descendants(matching: .any)["ledger.filter.endDate"], with: "2026-01-01")
        app.descendants(matching: .any)["ledger.filter.applyDates"].click()
        XCTAssertTrue(app.descendants(matching: .any)["ledger.filter.validation"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["ledger.filter.clear"].click()
        assertLedgerSummary(app: app, ordinaryInflow: "100.00", ordinaryOutflow: "40.00", investmentInflow: "0.00", investmentOutflow: "0.00", net: "60.00", transfers: "1")
    }

    @MainActor
    func testLedgerCorrectionReasonCancelAndHistory() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments() + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        launchApp(app)
        defer { dismissResidualNativePanels(in: app); app.terminate() }

        app.descendants(matching: .any)["sidebar.wealth"].click()
        XCTAssertTrue(app.descendants(matching: .any)["wealth.empty.add"].waitForExistence(timeout: 10))
        addContainer(app: app, name: "Synthetic Correction Cash A", kind: "Bank / Cash", amount: "1000.00", currency: "CNY", fxRate: nil)
        addContainer(app: app, name: "Synthetic Correction Cash B", kind: "Bank / Cash", amount: "500.00", currency: "CNY", fxRate: nil)
        app.descendants(matching: .any)["sidebar.ledger"].click()
        XCTAssertTrue(app.descendants(matching: .any)["ledger.empty"].waitForExistence(timeout: 10))
        addLedgerEntry(app: app, kind: "Expense", description: "Synthetic Correction Expense", amount: "100.00")
        assertLedgerSummary(app: app, ordinaryInflow: "0.00", ordinaryOutflow: "100.00", investmentInflow: "0.00", investmentOutflow: "0.00", net: "-100.00", transfers: "0")
        ledgerCorrectionAXInspect(app: app, description: "Synthetic Correction Expense")
        ledgerCorrectionOpenHistory(app: app, description: "Synthetic Correction Expense")
        XCTAssertTrue(app.descendants(matching: .any)["ledger.corrections.empty"].waitForExistence(timeout: 5))
        ledgerCorrectionCloseHistory(app: app)

        ledgerCorrectionOpenEdit(app: app, description: "Synthetic Correction Expense")
        XCTAssertTrue(app.descendants(matching: .any)["ledger.form.save"].isEnabled)
        app.descendants(matching: .any)["ledger.form.save"].click()
        XCTAssertTrue(waitForNonexistence(app.descendants(matching: .any)["ledger.form.save"], timeout: 5))
        ledgerCorrectionOpenHistory(app: app, description: "Synthetic Correction Expense")
        XCTAssertTrue(app.descendants(matching: .any)["ledger.corrections.empty"].waitForExistence(timeout: 5))
        ledgerCorrectionCloseHistory(app: app)

        ledgerCorrectionOpenEdit(app: app, description: "Synthetic Correction Expense")
        replaceText(in: app.descendants(matching: .any)["ledger.form.note"], with: "Synthetic note only")
        XCTAssertFalse(app.descendants(matching: .any)["ledger.form.correctionReason"].exists)
        app.descendants(matching: .any)["ledger.form.save"].click()
        XCTAssertTrue(waitForNonexistence(app.descendants(matching: .any)["ledger.form.save"], timeout: 5))
        ledgerCorrectionOpenEdit(app: app, description: "Synthetic Correction Expense")
        XCTAssertEqual(app.descendants(matching: .any)["ledger.form.note"].value as? String, "Synthetic note only")
        ledgerCorrectionCancelForm(app: app)
        ledgerCorrectionOpenHistory(app: app, description: "Synthetic Correction Expense")
        XCTAssertTrue(app.descendants(matching: .any)["ledger.corrections.empty"].waitForExistence(timeout: 5))
        ledgerCorrectionCloseHistory(app: app)

        ledgerCorrectionOpenEdit(app: app, description: "Synthetic Correction Expense")
        replaceText(in: app.descendants(matching: .any)["ledger.form.sourceAmount"], with: "125.00")
        let reason = app.descendants(matching: .any)["ledger.form.correctionReason"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["ledger.form.save"].isEnabled)
        ledgerCorrectionAttachAppScreenshot(app, named: "Synthetic amount correction requires a reason")
        replaceText(in: reason, with: "Synthetic amount correction")
        ledgerCorrectionCancelForm(app: app)
        assertLedgerSummary(app: app, ordinaryInflow: "0.00", ordinaryOutflow: "100.00", investmentInflow: "0.00", investmentOutflow: "0.00", net: "-100.00", transfers: "0")
        ledgerCorrectionOpenHistory(app: app, description: "Synthetic Correction Expense")
        XCTAssertTrue(app.descendants(matching: .any)["ledger.corrections.empty"].waitForExistence(timeout: 5))
        ledgerCorrectionCloseHistory(app: app)

        ledgerCorrectionOpenEdit(app: app, description: "Synthetic Correction Expense")
        replaceText(in: app.descendants(matching: .any)["ledger.form.sourceAmount"], with: "125.00")
        replaceText(in: app.descendants(matching: .any)["ledger.form.correctionReason"], with: "Synthetic amount correction")
        XCTAssertTrue(app.descendants(matching: .any)["ledger.form.save"].isEnabled)
        app.descendants(matching: .any)["ledger.form.save"].click()
        XCTAssertTrue(waitForNonexistence(app.descendants(matching: .any)["ledger.form.save"], timeout: 5))
        assertLedgerSummary(app: app, ordinaryInflow: "0.00", ordinaryOutflow: "125.00", investmentInflow: "0.00", investmentOutflow: "0.00", net: "-125.00", transfers: "0")
        ledgerCorrectionOpenHistory(app: app, description: "Synthetic Correction Expense")
        let firstHistory = try ledgerCorrectionHistoryRows(app: app, expected: 1)[0]
        let firstParts = ledgerCorrectionHistoryParts(firstHistory)
        XCTAssertTrue(firstParts.before.contains("CNY 100.00"))
        XCTAssertTrue(firstParts.after.contains("CNY 125.00"))
        XCTAssertTrue(firstParts.reason.contains("Synthetic amount correction"))
        ledgerCorrectionCloseHistory(app: app)

        ledgerCorrectionOpenEdit(app: app, description: "Synthetic Correction Expense")
        selectPicker(app: app, identifier: "ledger.form.sourceContainer", title: "Synthetic Correction Cash B")
        XCTAssertTrue(app.descendants(matching: .any)["ledger.form.correctionReason"].waitForExistence(timeout: 5))
        replaceText(in: app.descendants(matching: .any)["ledger.form.correctionReason"], with: "Synthetic container correction")
        app.descendants(matching: .any)["ledger.form.save"].click()
        XCTAssertTrue(waitForNonexistence(app.descendants(matching: .any)["ledger.form.save"], timeout: 5))
        assertLedgerSummary(app: app, ordinaryInflow: "0.00", ordinaryOutflow: "125.00", investmentInflow: "0.00", investmentOutflow: "0.00", net: "-125.00", transfers: "0")
        ledgerCorrectionOpenHistory(app: app, description: "Synthetic Correction Expense")
        let rows = try ledgerCorrectionHistoryRows(app: app, expected: 2)
        XCTAssertEqual(rows[0].id, firstHistory.id)
        XCTAssertNotEqual(rows[1].id, firstHistory.id)
        let containerParts = ledgerCorrectionHistoryParts(rows[1])
        XCTAssertTrue(containerParts.before.contains("primary, container "))
        XCTAssertTrue(containerParts.after.contains("primary, container "))
        XCTAssertEqual(ledgerCorrectionContainerID(containerParts.before).count, 36)
        XCTAssertEqual(ledgerCorrectionContainerID(containerParts.after).count, 36)
        XCTAssertNotEqual(ledgerCorrectionContainerID(containerParts.before), ledgerCorrectionContainerID(containerParts.after))
        XCTAssertTrue(containerParts.before.contains("CNY 125.00"))
        XCTAssertTrue(containerParts.after.contains("CNY 125.00"))
        XCTAssertTrue(containerParts.reason.contains("Synthetic container correction"))
        XCTAssertEqual(ledgerCorrectionHistorySheet(app).buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "Apply", "Edit")
        ).count, 0)
        ledgerCorrectionAttachAppScreenshot(app, named: "Synthetic container correction history")
        ledgerCorrectionCloseHistory(app: app)
        ledgerCorrectionOpenHistory(app: app, description: "Synthetic Correction Expense")
        XCTAssertEqual(try ledgerCorrectionHistoryRows(app: app, expected: 2).count, 2)
        ledgerCorrectionCloseHistory(app: app)
    }

    @MainActor
    func testLedgerCorrectionUSDAndTransferHistory() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments() + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        launchApp(app)
        defer { dismissResidualNativePanels(in: app); app.terminate() }

        app.descendants(matching: .any)["sidebar.wealth"].click()
        XCTAssertTrue(app.descendants(matching: .any)["wealth.empty.add"].waitForExistence(timeout: 10))
        addContainer(app: app, name: "Synthetic FX Cash A", kind: "Bank / Cash", amount: "1000.00", currency: "CNY", fxRate: nil)
        addContainer(app: app, name: "Synthetic FX Cash B", kind: "Bank / Cash", amount: "500.00", currency: "CNY", fxRate: nil)
        addContainer(app: app, name: "Synthetic FX Cash C", kind: "Bank / Cash", amount: "300.00", currency: "CNY", fxRate: nil)
        app.descendants(matching: .any)["sidebar.ledger"].click()
        XCTAssertTrue(app.descendants(matching: .any)["ledger.empty"].waitForExistence(timeout: 10))

        ledgerCorrectionAddUSDEntry(app: app, kind: "Income", description: "Synthetic USD Income", amount: "100.00", rate: "7.25")
        assertLedgerSummary(app: app, ordinaryInflow: "725.00", ordinaryOutflow: "0.00", investmentInflow: "0.00", investmentOutflow: "0.00", net: "725.00", transfers: "0")
        ledgerCorrectionAXInspect(app: app, description: "Synthetic USD Income")
        ledgerCorrectionOpenEdit(app: app, description: "Synthetic USD Income")
        replaceText(in: app.descendants(matching: .any)["ledger.form.sourceAmount"], with: "110.00")
        replaceText(in: app.descendants(matching: .any)["ledger.form.correctionReason"], with: "Synthetic USD amount correction")
        app.descendants(matching: .any)["ledger.form.save"].click()
        XCTAssertTrue(waitForNonexistence(app.descendants(matching: .any)["ledger.form.save"], timeout: 5))
        assertLedgerSummary(app: app, ordinaryInflow: "797.50", ordinaryOutflow: "0.00", investmentInflow: "0.00", investmentOutflow: "0.00", net: "797.50", transfers: "0")
        ledgerCorrectionOpenHistory(app: app, description: "Synthetic USD Income")
        let firstUSDHistory = try ledgerCorrectionHistoryRows(app: app, expected: 1)[0]
        let usdParts = ledgerCorrectionHistoryParts(firstUSDHistory)
        XCTAssertTrue(usdParts.before.contains("USD 100.00 × 7.25 = CNY 725.00"))
        XCTAssertTrue(usdParts.after.contains("USD 110.00 × 7.25 = CNY 797.50"))
        XCTAssertTrue(usdParts.before.contains("source manual.user.stage4"))
        XCTAssertTrue(usdParts.after.contains("source manual.user.stage4"))
        XCTAssertTrue(usdParts.reason.contains("Synthetic USD amount correction"))
        ledgerCorrectionAttachAppScreenshot(app, named: "Synthetic USD correction history")
        ledgerCorrectionCloseHistory(app: app)

        ledgerCorrectionOpenEdit(app: app, description: "Synthetic USD Income")
        replaceText(in: app.descendants(matching: .any)["ledger.form.sourceAmount"], with: "120.00")
        replaceText(in: app.descendants(matching: .any)["ledger.form.correctionReason"], with: "Synthetic USD follow-up")
        app.descendants(matching: .any)["ledger.form.save"].click()
        XCTAssertTrue(waitForNonexistence(app.descendants(matching: .any)["ledger.form.save"], timeout: 5))
        assertLedgerSummary(app: app, ordinaryInflow: "870.00", ordinaryOutflow: "0.00", investmentInflow: "0.00", investmentOutflow: "0.00", net: "870.00", transfers: "0")
        ledgerCorrectionOpenHistory(app: app, description: "Synthetic USD Income")
        let orderedRows = try ledgerCorrectionHistoryRows(app: app, expected: 2)
        XCTAssertEqual(orderedRows[0].id, firstUSDHistory.id)
        XCTAssertNotEqual(orderedRows[1].id, firstUSDHistory.id)
        let earlier = ledgerCorrectionHistoryParts(orderedRows[0])
        let later = ledgerCorrectionHistoryParts(orderedRows[1])
        XCTAssertTrue(earlier.reason.contains("Synthetic USD amount correction"))
        XCTAssertTrue(later.reason.contains("Synthetic USD follow-up"))
        XCTAssertTrue(later.before.contains("USD 110.00 × 7.25 = CNY 797.50"))
        XCTAssertTrue(later.after.contains("USD 120.00 × 7.25 = CNY 870.00"))
        ledgerCorrectionCloseHistory(app: app)

        ledgerCorrectionAddUSDEntry(app: app, kind: "Transfer", description: "Synthetic USD Transfer", amount: "20.00", rate: "7.25", targetAmount: "145.00")
        assertLedgerSummary(app: app, ordinaryInflow: "870.00", ordinaryOutflow: "0.00", investmentInflow: "0.00", investmentOutflow: "0.00", net: "870.00", transfers: "1")
        ledgerCorrectionOpenEdit(app: app, description: "Synthetic USD Transfer")
        selectPicker(app: app, identifier: "ledger.form.targetContainer", title: "Synthetic FX Cash C")
        replaceText(in: app.descendants(matching: .any)["ledger.form.correctionReason"], with: "Synthetic transfer target correction")
        app.descendants(matching: .any)["ledger.form.save"].click()
        XCTAssertTrue(waitForNonexistence(app.descendants(matching: .any)["ledger.form.save"], timeout: 5))
        assertLedgerSummary(app: app, ordinaryInflow: "870.00", ordinaryOutflow: "0.00", investmentInflow: "0.00", investmentOutflow: "0.00", net: "870.00", transfers: "1")
        ledgerCorrectionOpenHistory(app: app, description: "Synthetic USD Transfer")
        let transferParts = ledgerCorrectionHistoryParts(try ledgerCorrectionHistoryRows(app: app, expected: 1)[0])
        XCTAssertTrue(transferParts.before.contains("transferSource, container "))
        XCTAssertTrue(transferParts.before.contains("transferTarget, container "))
        XCTAssertTrue(transferParts.after.contains("transferSource, container "))
        XCTAssertTrue(transferParts.after.contains("transferTarget, container "))
        XCTAssertTrue(transferParts.before.contains("USD 20.00 × 7.25 = CNY 145.00"))
        XCTAssertTrue(transferParts.after.contains("USD 20.00 × 7.25 = CNY 145.00"))
        XCTAssertTrue(transferParts.before.contains("CNY 145.00 × 1 = CNY 145.00"))
        XCTAssertTrue(transferParts.after.contains("CNY 145.00 × 1 = CNY 145.00"))
        XCTAssertTrue(transferParts.before.contains("source manual.user.stage4"))
        XCTAssertTrue(transferParts.after.contains("source manual.user.stage4"))
        XCTAssertEqual(ledgerCorrectionContainerID(transferParts.before), ledgerCorrectionContainerID(transferParts.after))
        XCTAssertFalse(ledgerCorrectionPosting(transferParts.before, role: "transferSource").isEmpty)
        XCTAssertEqual(ledgerCorrectionPosting(transferParts.before, role: "transferSource"),
                       ledgerCorrectionPosting(transferParts.after, role: "transferSource"))
        XCTAssertEqual(ledgerCorrectionTargetContainerID(transferParts.before).count, 36)
        XCTAssertEqual(ledgerCorrectionTargetContainerID(transferParts.after).count, 36)
        XCTAssertNotEqual(ledgerCorrectionTargetContainerID(transferParts.before), ledgerCorrectionTargetContainerID(transferParts.after))
        ledgerCorrectionAttachAppScreenshot(app, named: "Synthetic transfer correction history")
        ledgerCorrectionCloseHistory(app: app)
        ledgerCorrectionOpenHistory(app: app, description: "Synthetic USD Transfer")
        XCTAssertEqual(try ledgerCorrectionHistoryRows(app: app, expected: 1).count, 1)
        ledgerCorrectionCloseHistory(app: app)
    }

    @MainActor
    func testLedgerNativeCSVImportPreviewConfirmationAndExport() throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("Aureus-Stage6MA-CSV-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let importURL = root.appendingPathComponent("Synthetic-Import.csv")
        let exportURL = root.appendingPathComponent("Aureus-Ledger-V1.csv")
        try syntheticImportCSV(transactionID: UUID()).write(to: importURL, options: .atomic)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: exportURL.path),
            "Synthetic export destination must not exist before export"
        )

        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments(demo: true)
        launchApp(app)
        defer {
            dismissResidualNativePanels(in: app)
            app.terminate()
        }
        app.descendants(matching: .any)["sidebar.ledger"].click()
        XCTAssertTrue(app.descendants(matching: .any)["ledger.history"].waitForExistence(timeout: 10))

        app.descendants(matching: .any)["ledger.import"].click()
        chooseFile(importURL.path, in: app)
        let preview = app.descendants(matching: .any)["ledger.import.preview.summary"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForValueOrLabel(preview, containing: "1 rows", timeout: 5))
        let ruleResult = app.descendants(matching: .any)["ledger.import.ruleResult.2"]
        XCTAssertTrue(ruleResult.waitForExistence(timeout: 5), "Import Preview did not expose the matched rule result")
        XCTAssertTrue(waitForValueOrLabel(ruleResult, containing: "Synthetic exact payee rule", timeout: 5))
        XCTAssertTrue(waitForValueOrLabel(ruleResult, containing: "Synthetic Daily", timeout: 5))
        XCTAssertTrue(waitForValueOrLabel(ruleResult, containing: "synthetic-demo", timeout: 5))
        app.descendants(matching: .any)["ledger.import.confirm"].click()
        XCTAssertTrue(app.staticTexts["Synthetic CSV Expense"].waitForExistence(timeout: 10))

        app.descendants(matching: .any)["ledger.export"].click()
        saveFileUsingDefaultFilename(at: exportURL, in: app)
        XCTAssertTrue(waitForNonexistence(app.sheets.firstMatch, timeout: 5))
        XCTAssertFalse(app.alerts["Ledger Error"].exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
    }

    @MainActor
    func testStage6SettingsCredentialEntitlementAndCacheLifecycle() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments()
        launchApp(app)
        let cleanupTimeLabel = "Last cleanup time: 2026-01-15 00:00:00.000 UTC"
        let noCleanupTimeLabel = "Last cleanup time: No cleanup record available"

        app.descendants(matching: .any)["sidebar.settings"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.content"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForValueOrLabel(
            app.descendants(matching: .any)["settings.mode"],
            containing: "Stage 6MA Session Lifecycle Repair Candidate",
            timeout: 5
        ))
        XCTAssertTrue(waitForValueOrLabel(
            app.descendants(matching: .any)["settings.provider.credentialState"],
            containing: "Missing",
            timeout: 5
        ))
        XCTAssertTrue(app.descendants(matching: .any)["settings.cache.summary"].exists)
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.cache.lastCleanupAt",
            expectedLabel: cleanupTimeLabel
        )
        let sessionSummary = app.descendants(matching: .any)["settings.session.summary"]
        XCTAssertTrue(sessionSummary.waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "settings.session.summary").count,
            1,
            "Session summary accessibility identity must be unique"
        )
        XCTAssertTrue(waitForValueOrLabel(sessionSummary, containing: "Maximum 64 MiB", timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["settings.session.disclosure"].exists)
        XCTAssertTrue(waitForValueOrLabel(sessionSummary, containing: "0 entries", timeout: 5))

        app.descendants(matching: .any)["settings.session.clear"].click()
        XCTAssertTrue(waitForValueOrLabel(
            app.descendants(matching: .any)["settings.status"],
            containing: "Session Market Data",
            timeout: 5
        ))
        XCTAssertTrue(waitForValueOrLabel(
            app.descendants(matching: .any)["settings.session.summary"],
            containing: "0 entries",
            timeout: 5
        ))

        let keyField = app.descendants(matching: .any)["settings.provider.key"]
        XCTAssertTrue(keyField.waitForExistence(timeout: 5))
        replaceText(in: keyField, with: "synthetic-stage6-ui-credential-a")
        app.descendants(matching: .any)["settings.provider.save"].click()
        let credentialState = app.descendants(matching: .any)["settings.provider.credentialState"]
        XCTAssertTrue(credentialState.waitForExistence(timeout: 10))
        let credentialPresentation = "\(credentialState.label) \(String(describing: credentialState.value ?? ""))"
        XCTAssertTrue(credentialPresentation.localizedCaseInsensitiveContains("Configured in Keychain"))
        XCTAssertFalse(String(describing: keyField.value ?? "").contains("synthetic-stage6-ui-credential-a"))

        replaceText(in: keyField, with: "synthetic-stage6-ui-credential-b")
        app.descendants(matching: .any)["settings.provider.save"].click()
        XCTAssertTrue(waitForValueOrLabel(
            app.descendants(matching: .any)["settings.status"],
            containing: "not displayed",
            timeout: 5
        ))
        XCTAssertFalse(String(describing: keyField.value ?? "").contains("synthetic-stage6-ui-credential-b"))

        let validate = app.descendants(matching: .any)["settings.provider.validate"]
        XCTAssertTrue(validate.waitForExistence(timeout: 5))
        XCTAssertTrue(validate.isHittable)
        validate.click()
        XCTAssertTrue(waitForValueOrLabel(
            app.descendants(matching: .any)["settings.provider.observedPlan"],
            containing: "Synthetic",
            timeout: 5
        ))
        XCTAssertTrue(waitForValueOrLabel(
            app.descendants(matching: .any)["settings.provider.entitlement"],
            containing: "basic",
            timeout: 5
        ))
        for market in ["us", "xhkg", "xshg", "xshe", "xjpx"] {
            XCTAssertTrue(app.descendants(matching: .any)["settings.provider.market.\(market)"].exists)
        }
        for (identifier, expected) in [
            ("settings.provider.market.us", "Live: mixed"),
            ("settings.provider.market.xhkg", "Live: succeeded"),
            ("settings.provider.market.xshg", "Live: denied"),
            ("settings.provider.market.xshe", "Live: notVerified"),
            ("settings.provider.endpoint.symbolSearch", "Live: succeeded"),
            ("settings.provider.endpoint.latestQuote", "Live: denied"),
            ("settings.provider.endpoint.historicalOHLCV", "Live: mixed"),
            ("settings.provider.endpoint.splits", "Live: notVerified")
        ] {
            let element = app.descendants(matching: .any)[identifier]
            XCTAssertEqual(
                app.descendants(matching: .any).matching(identifier: identifier).count,
                1,
                "Settings observation accessibility identity must be unique: \(identifier)"
            )
            XCTAssertTrue(waitForValueOrLabel(element, containing: expected, timeout: 5))
        }

        app.descendants(matching: .any)["settings.cache.removeExpired"].click()
        XCTAssertTrue(waitForValueOrLabel(
            app.descendants(matching: .any)["settings.status"],
            containing: "expired recoverable cache",
            timeout: 5
        ))
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.cache.lastCleanupAt",
            expectedLabel: cleanupTimeLabel
        )
        XCTAssertFalse(app.descendants(matching: .any)["settings.error"].exists)

        app.descendants(matching: .any)["settings.cache.reset"].click()
        let reset = app.descendants(matching: .any)["settings.cache.reset.confirm"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5)); reset.click()
        XCTAssertTrue(waitForValueOrLabel(
            app.descendants(matching: .any)["settings.status"],
            containing: "reset and rebuilt",
            timeout: 5
        ))
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.cache.lastCleanupAt",
            expectedLabel: noCleanupTimeLabel
        )
        XCTAssertFalse(app.descendants(matching: .any)["settings.error"].exists)

        // Reconstruct Settings in the same foreground dependency graph. App
        // relaunch would run startup cleanup and would not test reset's nil.
        app.descendants(matching: .any)["sidebar.dashboard"].click()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.empty"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["sidebar.settings"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.content"].waitForExistence(timeout: 5))
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.cache.lastCleanupAt",
            expectedLabel: noCleanupTimeLabel
        )
        app.descendants(matching: .any)["settings.cache.removeExpired"].click()
        XCTAssertTrue(waitForValueOrLabel(
            app.descendants(matching: .any)["settings.status"],
            containing: "expired recoverable cache",
            timeout: 5
        ))
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.cache.lastCleanupAt",
            expectedLabel: cleanupTimeLabel
        )
        XCTAssertFalse(app.descendants(matching: .any)["settings.error"].exists)

        let screenshot = XCUIScreen.main.screenshot().pngRepresentation
        try screenshot.write(
            to: URL(fileURLWithPath: "/private/tmp/Aureus-Stage6MA-Settings-\(UUID().uuidString).png"),
            options: .atomic
        )

        app.descendants(matching: .any)["settings.provider.disconnect"].click()
        let disconnect = app.descendants(matching: .any)["settings.provider.disconnect.confirm"]
        XCTAssertTrue(disconnect.waitForExistence(timeout: 5)); disconnect.click()
        XCTAssertTrue(waitForValueOrLabel(
            app.descendants(matching: .any)["settings.provider.credentialState"],
            containing: "Missing",
            timeout: 5
        ))

        replaceText(
            in: app.descendants(matching: .any)["settings.provider.key"],
            with: "synthetic-stage6-ui-credential-c"
        )
        app.descendants(matching: .any)["settings.provider.save"].click()
        XCTAssertTrue(waitForValueOrLabel(
            app.descendants(matching: .any)["settings.provider.credentialState"],
            containing: "Configured in Keychain",
            timeout: 5
        ))
        app.descendants(matching: .any)["settings.provider.delete"].click()
        let delete = app.descendants(matching: .any)["settings.provider.delete.confirm"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.click()
        XCTAssertTrue(waitForValueOrLabel(
            app.descendants(matching: .any)["settings.provider.credentialState"],
            containing: "Missing",
            timeout: 5
        ))

        app.descendants(matching: .any)["sidebar.markets"].click()
        XCTAssertTrue(app.descendants(matching: .any)["markets.terminal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markets.mode.production"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["markets.mode.synthetic"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["markets.detail.empty"].exists)
    }

    @MainActor
    func testStage6ProductionCredentialConfigurationObservation() throws {
        let app = XCUIApplication()
        // UI automation must never query the user's Production Keychain item.
        // The isolated UI-test dependency path proves that a fresh process does
        // not inherit a Production credential or reveal credential material.
        app.launchArguments = uiTestingArguments()
        launchApp(app)

        app.descendants(matching: .any)["sidebar.settings"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.content"].waitForExistence(timeout: 10))
        let credentialState = app.descendants(matching: .any)["settings.provider.credentialState"]
        XCTAssertTrue(credentialState.waitForExistence(timeout: 10))

        let presentation = "\(credentialState.label) \(String(describing: credentialState.value ?? ""))"
        XCTAssertTrue(presentation.localizedCaseInsensitiveContains("Missing"))
        XCTAssertFalse(presentation.localizedCaseInsensitiveContains("Configured in Keychain"))
        XCTAssertFalse(app.descendants(matching: .any)["settings.provider.key"].value as? String == "synthetic")

        let attachment = XCTAttachment(
            string: "MISSING — isolated UI-test credential store"
        )
        attachment.name = "UI-test Keychain isolation state (Production credential not accessed)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private struct WealthAcceptanceHistoryAXRecord {
        let id: UUID
        let firstIndex: Int
        let sequence: Int
        let reason: String
        let before: String
        let after: String
    }

    private enum WealthAcceptanceAXError: Error { case invalidHistory }

    @MainActor
    private func wealthAcceptanceRow(app: XCUIApplication, name: String,
                                     kind: String, currency: String) -> XCUIElement {
        let identifier = "wealth.row.\(kind).\(currency)"
        let candidates = app.descendants(matching: .any).matching(identifier: identifier)
            .allElementsBoundByIndex
        XCTAssertLessThanOrEqual(candidates.count, 50, "Wealth row lookup exceeded bounded AX scope")
        let matches = candidates.prefix(50).filter { candidate in
            if candidate.label.contains(name) || (candidate.value as? String)?.contains(name) == true {
                return true
            }
            return candidate.descendants(matching: .any).allElementsBoundByIndex.prefix(50)
                .contains { child in
                    child.label.contains(name) || (child.value as? String)?.contains(name) == true
                }
        }
        if matches.count != 1 {
            for (index, candidate) in candidates.prefix(50).enumerated() {
                let value = candidate.value as? String ?? ""
                print("WEALTH_ACCEPTANCE_AX_ROW index=\(index) id=\(candidate.identifier) type=\(candidate.elementType) label=\(String(candidate.label.prefix(4096))) value=\(String(value.prefix(4096))) labelTruncated=\(candidate.label.count > 4096) valueTruncated=\(value.count > 4096)")
            }
        }
        XCTAssertEqual(matches.count, 1, "Expected one named synthetic Wealth row")
        return matches.first ?? app.descendants(matching: .any)["wealth.acceptance.unmatched.row"]
    }

    @MainActor
    private func wealthAcceptanceOpenEdit(app: XCUIApplication, name: String,
                                          kind: String, currency: String, amount: String) {
        let row = wealthAcceptanceRow(app: app, name: name, kind: kind, currency: currency)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        app.descendants(matching: .any)["wealth.edit"].click()
        XCTAssertTrue(app.descendants(matching: .any)["wealth.form.intent"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(app.descendants(matching: .any)["wealth.form.amount"],
            containing: amount, timeout: 5), "Current edit context must be ready")
    }

    @MainActor
    private func wealthAcceptanceChooseIntent(app: XCUIApplication, title: String) {
        wealthAcceptanceAssertIntent(app: app, title: title, select: true)
    }

    @MainActor
    private func wealthAcceptanceAssertIntent(app: XCUIApplication, title: String, select: Bool) {
        let pickers = app.descendants(matching: .any).matching(identifier: "wealth.form.intent")
        XCTAssertEqual(pickers.count, 1, "Expected one Wealth intent container")
        let picker = pickers.element(boundBy: 0)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let otherTitle = title == "Correct existing record"
            ? "Record new current valuation" : "Correct existing record"
        let choices = picker.radioButtons.matching(NSPredicate(format: "label == %@", title))
        let otherChoices = picker.radioButtons.matching(NSPredicate(format: "label == %@", otherTitle))
        XCTAssertEqual(choices.count, 1, "Expected one specified Wealth edit intent")
        XCTAssertEqual(otherChoices.count, 1, "Expected one alternative Wealth edit intent")
        if select { choices.element(boundBy: 0).click() }
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 1 OR value == '1'"),
            object: choices.element(boundBy: 0))
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed,
            "Wealth intent must expose the selected AX value")
        // Re-query after the bounded wait; the AX snapshot before the click is not authoritative.
        let currentChoices = picker.radioButtons.matching(NSPredicate(format: "label == %@", title))
        let currentOther = picker.radioButtons.matching(NSPredicate(format: "label == %@", otherTitle))
        XCTAssertEqual(currentChoices.count, 1)
        XCTAssertEqual(currentOther.count, 1)
        XCTAssertEqual(wealthAcceptanceIntentValue(currentChoices.element(boundBy: 0)), true)
        XCTAssertEqual(wealthAcceptanceIntentValue(currentOther.element(boundBy: 0)), false)
        let valuation = title == "Record new current valuation"
        XCTAssertEqual(app.descendants(matching: .any)["wealth.form.name"].isEnabled, !valuation)
        XCTAssertEqual(app.descendants(matching: .any)["wealth.form.institution"].isEnabled, !valuation)
        XCTAssertEqual(app.descendants(matching: .any)["wealth.form.currency"].isEnabled, !valuation)
    }

    @MainActor
    private func wealthAcceptanceIntentValue(_ element: XCUIElement) -> Bool? {
        if let number = element.value as? NSNumber {
            if number.intValue == 1 { return true }
            if number.intValue == 0 { return false }
        }
        if let text = element.value as? String {
            if text == "1" { return true }
            if text == "0" { return false }
        }
        return nil
    }

    @MainActor
    private func wealthAcceptanceSave(app: XCUIApplication) {
        let save = app.descendants(matching: .any)["wealth.form.save"]
        XCTAssertTrue(save.isEnabled)
        save.click()
        XCTAssertTrue(waitForNonexistence(app.descendants(matching: .any)["wealth.form.save"], timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["wealth.form.error"].exists)
    }

    @MainActor
    private func wealthAcceptanceOpenHistory(app: XCUIApplication, name: String,
                                             kind: String, currency: String) {
        let row = wealthAcceptanceRow(app: app, name: name, kind: kind, currency: currency)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        let open = app.descendants(matching: .any)["wealth.history.open"]
        XCTAssertTrue(open.isEnabled)
        open.click()
        XCTAssertTrue(app.descendants(matching: .any)["wealth.history.close"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func wealthAcceptanceHistorySheet(_ app: XCUIApplication) -> XCUIElement {
        let sheets = app.sheets.containing(.button, identifier: "wealth.history.close")
        XCTAssertEqual(sheets.count, 1, "Expected one selected Wealth history sheet")
        return sheets.element(boundBy: 0)
    }

    @MainActor
    private func wealthAcceptanceCloseHistory(app: XCUIApplication) {
        let buttons = wealthAcceptanceHistorySheet(app).buttons.matching(identifier: "wealth.history.close")
        XCTAssertEqual(buttons.count, 1)
        buttons.element(boundBy: 0).click()
        XCTAssertTrue(waitForNonexistence(app.descendants(matching: .any)["wealth.history.close"], timeout: 5))
    }

    @MainActor
    private func wealthAcceptanceHistoryRows(app: XCUIApplication, expected: Int)
        throws -> [WealthAcceptanceHistoryAXRecord] {
        let lists = wealthAcceptanceHistorySheet(app).descendants(matching: .any)
            .matching(identifier: "wealth.history.list")
        guard lists.count == 1 else {
            XCTFail("Expected one Wealth history list, found \(lists.count)")
            throw WealthAcceptanceAXError.invalidHistory
        }
        let fields = lists.element(boundBy: 0).staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "wealth.history."))
        guard fields.count <= 50 else {
            XCTFail("Wealth history AX candidate limit exceeded: \(fields.count)")
            throw WealthAcceptanceAXError.invalidHistory
        }
        var order: [UUID] = []
        var grouped: [UUID: [(index: Int, role: String, text: String)]] = [:]
        for index in 0..<fields.count {
            let field = fields.element(boundBy: index)
            let parts = field.identifier.split(separator: ".")
            guard parts.count == 4, parts[0] == "wealth", parts[1] == "history",
                  let id = UUID(uuidString: String(parts[2])), id.uuidString == String(parts[2]),
                  ["title", "reason", "before", "after"].contains(String(parts[3])) else {
                wealthAcceptanceHistoryDiagnostic(fields, checkpoint: "invalid-identifier")
                XCTFail("History field at candidate \(index) has no unique UUID and role")
                throw WealthAcceptanceAXError.invalidHistory
            }
            let label = field.label
            let value = field.value as? String ?? ""
            guard label.count <= 4_096, value.count <= 4_096,
                  !label.isEmpty || !value.isEmpty,
                  label.isEmpty || value.isEmpty || label == value else {
                wealthAcceptanceHistoryDiagnostic(fields, checkpoint: "invalid-text")
                XCTFail("History field \(id) \(parts[3]) lacks a complete unambiguous value")
                throw WealthAcceptanceAXError.invalidHistory
            }
            if grouped[id] == nil { order.append(id); grouped[id] = [] }
            let text = value.isEmpty ? label : value
            grouped[id, default: []].append((index, String(parts[3]), text))
            print("WEALTH_HISTORY_AX index=\(index) uuid=\(id.uuidString) role=\(parts[3]) text=\(text) truncated=false")
        }
        guard order.count == expected else {
            wealthAcceptanceHistoryDiagnostic(fields, checkpoint: "count-\(expected)")
            XCTFail("Expected \(expected) logical Wealth histories; found \(order.count)")
            throw WealthAcceptanceAXError.invalidHistory
        }
        return try order.map { id in
            let candidates = grouped[id] ?? []
            @MainActor func single(_ role: String) throws -> String {
                let matches = candidates.filter { $0.role == role }
                guard matches.count == 1 else {
                    wealthAcceptanceHistoryDiagnostic(fields, checkpoint: "duplicate-or-missing-\(role)")
                    XCTFail("History \(id) requires exactly one \(role) field; found \(matches.count)")
                    throw WealthAcceptanceAXError.invalidHistory
                }
                return matches[0].text
            }
            let title = try single("title")
            let titleParts = title.split(separator: " ")
            guard titleParts.count >= 2, titleParts[0] == "Sequence",
                  let sequence = Int(titleParts[1]), let firstIndex = candidates.first?.index else {
                XCTFail("History \(id) has no readable sequence")
                throw WealthAcceptanceAXError.invalidHistory
            }
            return WealthAcceptanceHistoryAXRecord(id: id, firstIndex: firstIndex,
                sequence: sequence, reason: try single("reason"),
                before: try single("before"), after: try single("after"))
        }
    }

    @MainActor
    private func wealthAcceptanceHistoryDiagnostic(_ fields: XCUIElementQuery, checkpoint: String) {
        print("WEALTH_HISTORY_AX_DIAGNOSTIC checkpoint=\(checkpoint) candidates=\(fields.count) truncated=\(fields.count > 50)")
        for index in 0..<min(fields.count, 50) {
            let field = fields.element(boundBy: index)
            let label = field.label, value = field.value as? String ?? ""
            print("WEALTH_HISTORY_AX_DIAGNOSTIC index=\(index) type=\(field.elementType) identifier=\(field.identifier) label=\(String(label.prefix(4_096))) label_truncated=\(label.count > 4_096) value=\(String(value.prefix(4_096))) value_truncated=\(value.count > 4_096)")
        }
    }

    @MainActor
    private func wealthAcceptanceScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func addContainer(
        app: XCUIApplication,
        name: String,
        kind: String,
        amount: String,
        currency: String,
        fxRate: String?
    ) {
        app.descendants(matching: .any)["wealth.add"].click()
        let nameField = app.descendants(matching: .any)["wealth.form.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.click()
        nameField.typeText(name)
        if kind != "Bank / Cash" {
            selectPicker(app: app, identifier: "wealth.form.type", title: kind)
        }
        if currency == "USD" {
            let usd = app.descendants(matching: .any)["wealth.form.currency.usd"]
            if usd.exists {
                usd.click()
            } else {
                app.buttons["USD"].click()
            }
        }
        let amountField = app.descendants(matching: .any)["wealth.form.amount"]
        amountField.click()
        amountField.typeText(amount)
        if let fxRate {
            let fx = app.descendants(matching: .any)["wealth.form.fx.rate"]
            XCTAssertTrue(fx.waitForExistence(timeout: 5))
            fx.click()
            fx.typeText(fxRate)
        }
        app.descendants(matching: .any)["wealth.form.save"].click()
        XCTAssertFalse(app.descendants(matching: .any)["wealth.form.save"].waitForExistence(timeout: 2))
    }

    @MainActor
    private func addLedgerEntry(
        app: XCUIApplication,
        kind: String,
        description: String,
        amount: String,
        targetAmount: String? = nil,
        category: String? = nil,
        tag: String? = nil
    ) {
        app.descendants(matching: .any)["ledger.add"].click()
        let descriptionField = app.descendants(matching: .any)["ledger.form.description"]
        XCTAssertTrue(descriptionField.waitForExistence(timeout: 5))
        replaceText(in: descriptionField, with: description)
        if kind != "Income" {
            selectPicker(app: app, identifier: "ledger.form.kind", title: kind)
        }
        replaceText(in: app.descendants(matching: .any)["ledger.form.sourceAmount"], with: amount)
        if let targetAmount {
            let target = app.descendants(matching: .any)["ledger.form.targetAmount"]
            XCTAssertTrue(target.waitForExistence(timeout: 5)); replaceText(in: target, with: targetAmount)
        }
        if let category { selectPicker(app: app, identifier: "ledger.form.category", title: category) }
        if let tag {
            let toggle = app.checkBoxes[tag]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5)); toggle.click()
        }
        app.descendants(matching: .any)["ledger.form.save"].click()
        XCTAssertFalse(app.descendants(matching: .any)["ledger.form.save"].waitForExistence(timeout: 2))
    }

    @MainActor
    private func ledgerCorrectionAXInspect(app: XCUIApplication, description: String) {
        let predicate = NSPredicate(
            format: "identifier == %@ OR identifier BEGINSWITH %@ OR identifier BEGINSWITH %@ OR identifier BEGINSWITH %@ OR label CONTAINS[c] %@ OR label BEGINSWITH %@",
            "ledger.history", "ledger.row.", "ledger.edit.", "ledger.corrections.open.",
            description, "Edit "
        )
        let queries: [(String, XCUIElementQuery)] = [
            ("app", app.descendants(matching: .any).matching(predicate)),
            ("ledger.history", app.descendants(matching: .any)["ledger.history"]
                .descendants(matching: .any).matching(predicate))
        ]
        for (scope, query) in queries {
            let count = query.count
            print("LEDGER_CORRECTION_AX scope=\(scope) fixture=\(description) count=\(count) truncated=\(count > 50)")
            for index in 0..<min(count, 50) {
                let element = query.element(boundBy: index)
                func bounded(_ value: String) -> String { String(value.prefix(2_048)) }
                print("LEDGER_CORRECTION_AX scope=\(scope) index=\(index) type=\(element.elementType) identifier=\(bounded(element.identifier)) label=\(bounded(element.label)) value=\(bounded(element.value as? String ?? "")) exists=\(element.exists) isHittable=\(element.isHittable)")
            }
        }
    }

    @MainActor
    private func ledgerCorrectionAXInspectHistory(app: XCUIApplication, checkpoint: String) {
        let sheets = app.sheets.containing(.button, identifier: "ledger.corrections.close")
        print("LEDGER_CORRECTION_AX_HISTORY checkpoint=\(checkpoint) sheet_count=\(sheets.count)")
        guard sheets.count == 1 else { return }
        let lists = sheets.element(boundBy: 0).descendants(matching: .any)
            .matching(identifier: "ledger.corrections.list")
        print("LEDGER_CORRECTION_AX_HISTORY checkpoint=\(checkpoint) list_count=\(lists.count)")
        guard lists.count == 1 else { return }
        let query = lists.element(boundBy: 0).staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "ledger.corrections.row.")
        )
        let count = query.count
        print("LEDGER_CORRECTION_AX_HISTORY checkpoint=\(checkpoint) count=\(count) truncated=\(count > 50)")
        for index in 0..<min(count, 50) {
            let element = query.element(boundBy: index)
            let value = element.value as? String ?? ""
            let role = ledgerCorrectionHistoryAXRole(value)
            print("LEDGER_CORRECTION_AX_HISTORY index=\(index) type=\(element.elementType) identifier=\(element.identifier) role=\(role) label=\(String(element.label.prefix(2_048))) value=\(String(value.prefix(2_048))) value_truncated=\(value.count > 2_048) exists=\(element.exists) isHittable=\(element.isHittable)")
        }
    }

    private struct LedgerCorrectionHistoryAXRecord {
        let id: UUID
        let firstIndex: Int
        let before: String
        let after: String
        let reason: String
    }

    private enum LedgerCorrectionHistoryAXError: Error {
        case invalidRecord
    }

    private func ledgerCorrectionHistoryAXRole(_ value: String) -> String {
        if value.hasPrefix("Before: ") { return "before" }
        if value.hasPrefix("After: ") { return "after" }
        if value.hasPrefix("Reason: ") { return "reason" }
        if value == "Important correction" || value == "Deletion context" { return "title" }
        return "time-or-other"
    }

    @MainActor
    private func ledgerCorrectionEntryID(app: XCUIApplication, description: String) -> String {
        let list = app.descendants(matching: .any)["ledger.history"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let descriptions = list.descendants(matching: .any)
            .matching(NSPredicate(format: "value == %@ AND identifier BEGINSWITH %@", description, "ledger.row."))
        XCTAssertEqual(descriptions.count, 1, "Synthetic description must identify one Ledger row value")
        let rowIdentifier = descriptions.element(boundBy: 0).identifier
        XCTAssertTrue(rowIdentifier.hasPrefix("ledger.row."))
        let id = String(rowIdentifier.dropFirst("ledger.row.".count))
        XCTAssertNotNil(UUID(uuidString: id))
        let kind = String(description.split(separator: " ").last ?? "")
        let edits = list.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label == %@", rowIdentifier, "Edit \(kind) transaction"
        ))
        XCTAssertEqual(edits.count, 1, "Edit button must share the identified Ledger row")
        return id
    }

    @MainActor
    private func ledgerCorrectionOpenEdit(app: XCUIApplication, description: String) {
        let id = ledgerCorrectionEntryID(app: app, description: description)
        let list = app.descendants(matching: .any)["ledger.history"]
        let buttons = list.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label == %@", "ledger.row.\(id)",
            "Edit \(String(description.split(separator: " ").last ?? "")) transaction"
        ))
        XCTAssertEqual(buttons.count, 1)
        buttons.element(boundBy: 0).click()
        XCTAssertTrue(app.descendants(matching: .any)["ledger.form.sourceAmount"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func ledgerCorrectionFormSheet(_ app: XCUIApplication) -> XCUIElement {
        let sheets = app.sheets.containing(.textField, identifier: "ledger.form.description")
        XCTAssertEqual(sheets.count, 1, "Expected one Ledger edit sheet")
        return sheets.element(boundBy: 0)
    }

    @MainActor
    private func ledgerCorrectionCancelForm(app: XCUIApplication) {
        let buttons = ledgerCorrectionFormSheet(app).buttons.matching(identifier: "Cancel")
        XCTAssertEqual(buttons.count, 1)
        buttons.element(boundBy: 0).click()
        XCTAssertTrue(waitForNonexistence(app.descendants(matching: .any)["ledger.form.save"], timeout: 5))
    }

    @MainActor
    private func ledgerCorrectionOpenHistory(app: XCUIApplication, description: String) {
        let id = ledgerCorrectionEntryID(app: app, description: description)
        let list = app.descendants(matching: .any)["ledger.history"]
        let buttons = list.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label == %@", "ledger.row.\(id)",
            "Correction history for \(description)"
        ))
        XCTAssertEqual(buttons.count, 1)
        buttons.element(boundBy: 0).click()
        let close = app.descendants(matching: .any)["ledger.corrections.close"]
        let appeared = close.waitForExistence(timeout: 5)
        if !appeared { ledgerCorrectionAXInspectHistory(app: app, checkpoint: "missing-close") }
        XCTAssertTrue(appeared)
    }

    @MainActor
    private func ledgerCorrectionHistorySheet(_ app: XCUIApplication) -> XCUIElement {
        let sheets = app.sheets.containing(.button, identifier: "ledger.corrections.close")
        if sheets.count != 1 { ledgerCorrectionAXInspectHistory(app: app, checkpoint: "history-sheet") }
        XCTAssertEqual(sheets.count, 1, "Expected one correction-history sheet")
        return sheets.element(boundBy: 0)
    }

    @MainActor
    private func ledgerCorrectionCloseHistory(app: XCUIApplication) {
        let buttons = ledgerCorrectionHistorySheet(app).buttons.matching(identifier: "ledger.corrections.close")
        XCTAssertEqual(buttons.count, 1)
        buttons.element(boundBy: 0).click()
        XCTAssertTrue(waitForNonexistence(app.descendants(matching: .any)["ledger.corrections.close"], timeout: 5))
    }

    @MainActor
    private func ledgerCorrectionHistoryRows(app: XCUIApplication, expected: Int) throws -> [LedgerCorrectionHistoryAXRecord] {
        let sheet = ledgerCorrectionHistorySheet(app)
        let lists = sheet.descendants(matching: .any).matching(identifier: "ledger.corrections.list")
        if lists.count != 1 { ledgerCorrectionAXInspectHistory(app: app, checkpoint: "history-list") }
        guard lists.count == 1 else {
            XCTFail("Expected one correction-history list")
            throw LedgerCorrectionHistoryAXError.invalidRecord
        }
        let fields = lists.element(boundBy: 0).staticTexts
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "ledger.corrections.row."))
        guard fields.count <= 50 else {
            ledgerCorrectionAXInspectHistory(app: app, checkpoint: "field-limit")
            XCTFail("History field count exceeds bounded AX evidence")
            throw LedgerCorrectionHistoryAXError.invalidRecord
        }
        var order: [String] = []
        var grouped: [String: [(index: Int, role: String, value: String)]] = [:]
        for index in 0..<fields.count {
            let field = fields.element(boundBy: index)
            let identifier = field.identifier
            let rawID = String(identifier.dropFirst("ledger.corrections.row.".count))
            guard let id = UUID(uuidString: rawID), id.uuidString == rawID,
                  let value = field.value as? String, value.count <= 2_048 else {
                ledgerCorrectionAXInspectHistory(app: app, checkpoint: "invalid-field")
                XCTFail("History field has an invalid UUID or truncated/non-text value at index \(index)")
                throw LedgerCorrectionHistoryAXError.invalidRecord
            }
            if grouped[identifier] == nil { order.append(identifier); grouped[identifier] = [] }
            let role = ledgerCorrectionHistoryAXRole(value)
            grouped[identifier, default: []].append((index, role, value))
            print("LEDGER_CORRECTION_AX_HISTORY_GROUP candidate_index=\(index) uuid=\(id.uuidString) role=\(role) value=\(String(value.prefix(2_048))) value_truncated=false")
        }
        if order.count != expected { ledgerCorrectionAXInspectHistory(app: app, checkpoint: "rows-expected-\(expected)") }
        guard order.count == expected else {
            XCTFail("Expected \(expected) logical history records, found \(order.count)")
            throw LedgerCorrectionHistoryAXError.invalidRecord
        }
        return try order.map { identifier in
            let fields = grouped[identifier] ?? []
            @MainActor func single(_ role: String) throws -> String {
                let matches = fields.filter { $0.role == role }
                guard matches.count == 1 else {
                    ledgerCorrectionAXInspectHistory(app: app, checkpoint: "field-\(role)-count-\(matches.count)")
                    XCTFail("History \(identifier) must have exactly one \(role) field")
                    throw LedgerCorrectionHistoryAXError.invalidRecord
                }
                return matches[0].value
            }
            guard let rawID = identifier.split(separator: ".").last,
                  let id = UUID(uuidString: String(rawID)),
                  let firstIndex = fields.first?.index else {
                throw LedgerCorrectionHistoryAXError.invalidRecord
            }
            return LedgerCorrectionHistoryAXRecord(
                id: id, firstIndex: firstIndex,
                before: try single("before"), after: try single("after"), reason: try single("reason")
            )
        }
    }

    @MainActor
    private func ledgerCorrectionHistoryParts(_ row: LedgerCorrectionHistoryAXRecord) -> (before: String, after: String, reason: String) {
        (row.before, row.after, row.reason)
    }

    private func ledgerCorrectionContainerID(_ projection: String) -> String {
        let pattern = #"(?:primary|transferSource), container ([0-9A-Fa-f-]{36})"#
        let range = NSRange(projection.startIndex..<projection.endIndex, in: projection)
        let match = try? NSRegularExpression(pattern: pattern).firstMatch(in: projection, range: range)
        guard let match, let value = Range(match.range(at: 1), in: projection) else { return "" }
        return String(projection[value])
    }

    private func ledgerCorrectionTargetContainerID(_ projection: String) -> String {
        let pattern = #"transferTarget, container ([0-9A-Fa-f-]{36})"#
        let range = NSRange(projection.startIndex..<projection.endIndex, in: projection)
        let match = try? NSRegularExpression(pattern: pattern).firstMatch(in: projection, range: range)
        guard let match, let value = Range(match.range(at: 1), in: projection) else { return "" }
        return String(projection[value])
    }

    private func ledgerCorrectionPosting(_ projection: String, role: String) -> String {
        projection.components(separatedBy: " · ").first { $0.hasPrefix("\(role), container ") } ?? ""
    }

    @MainActor
    private func ledgerCorrectionAddUSDEntry(
        app: XCUIApplication, kind: String, description: String, amount: String,
        rate: String, targetAmount: String? = nil
    ) {
        app.descendants(matching: .any)["ledger.add"].click()
        let descriptionField = app.descendants(matching: .any)["ledger.form.description"]
        XCTAssertTrue(descriptionField.waitForExistence(timeout: 5))
        replaceText(in: descriptionField, with: description)
        if kind != "Income" { selectPicker(app: app, identifier: "ledger.form.kind", title: kind) }
        selectPicker(app: app, identifier: "ledger.form.sourceCurrency", title: "USD")
        replaceText(in: app.descendants(matching: .any)["ledger.form.sourceAmount"], with: amount)
        let fx = app.descendants(matching: .any)["ledger.form.sourceFX"]
        XCTAssertTrue(fx.waitForExistence(timeout: 5))
        replaceText(in: fx, with: rate)
        if let targetAmount {
            let target = app.descendants(matching: .any)["ledger.form.targetAmount"]
            XCTAssertTrue(target.waitForExistence(timeout: 5))
            replaceText(in: target, with: targetAmount)
        }
        app.descendants(matching: .any)["ledger.form.save"].click()
        XCTAssertTrue(waitForNonexistence(app.descendants(matching: .any)["ledger.form.save"], timeout: 5))
    }

    @MainActor
    private func ledgerCorrectionAttachAppScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func deleteLedgerEntry(app: XCUIApplication, kind: String) {
        let button = app.buttons["Delete \(kind) transaction"]
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.click()
        let confirm = app.descendants(matching: .any)["ledger.delete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.click()
    }

    @MainActor
    private func selectLedgerKindFilter(app: XCUIApplication, title: String) {
        selectPicker(app: app, identifier: "ledger.filter.kind", title: title)
    }

    @MainActor
    private func selectPicker(app: XCUIApplication, identifier: String, title: String) {
        XCTAssertTrue(
            app.descendants(matching: .any)[identifier].waitForExistence(timeout: 5),
            "Missing picker \(identifier)"
        )
        // Re-query immediately before opening and query only the named native
        // menu item after the popup transition. No pre-popup element, menu row
        // index, coordinate, or complete transient menu tree is retained.
        app.descendants(matching: .any)[identifier].click()
        let option = app.menuItems[title]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Missing picker option \(title)")
        option.click()
        XCTAssertTrue(
            waitForPickerSelection(
                in: app,
                identifier: identifier,
                containing: title,
                timeout: 5
            ),
            "Picker \(identifier) did not select \(title)"
        )
    }

    @MainActor
    private func assertUniqueSettingsDataLifecycleElement(
        in app: XCUIApplication,
        identifier: String,
        expectedLabel: String
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let matches = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "identifier == %@", identifier))
                return matches.count == 1 && matches.firstMatch.label == expectedLabel
            },
            object: app
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
        let matches = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier))
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.firstMatch.label, expectedLabel)
    }

    @MainActor
    private func assertExternalRestoreConfirmation(
        in app: XCUIApplication,
        warning: String
    ) {
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.externalRestore.dialog.heading",
            expectedLabel: "Restore Selected External Backup?"
        )
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.externalRestore.dialog.warning",
            expectedLabel: warning
        )
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.externalRestore.cancel",
            expectedLabel: "Cancel"
        )
        assertUniqueSettingsDataLifecycleElement(
            in: app,
            identifier: "settings.dataLifecycle.externalRestore.confirm",
            expectedLabel: "Restore External Backup"
        )
    }

    @MainActor
    private func settingsGenerationRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "settings.dataLifecycle.generation."
            )
        )
    }

    @MainActor
    private func waitForSettingsGenerationCount(
        _ expected: Int,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                self.settingsGenerationRows(in: app).count == expected
            },
            object: app
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForSettingsDataLifecycleLabel(
        in app: XCUIApplication,
        identifier: String,
        equals expected: String,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let element = app.descendants(matching: .any)[identifier]
                return element.exists && element.label == expected
            },
            object: app
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForSettingsDataLifecycleLabelContaining(
        in app: XCUIApplication,
        identifier: String,
        text: String,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let element = app.descendants(matching: .any)[identifier]
                return element.exists && element.label.contains(text)
            },
            object: app
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForSettingsControlEnabled(
        in app: XCUIApplication,
        identifier: String,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let element = app.descendants(matching: .any)[identifier]
                return element.exists && element.isEnabled
            },
            object: app
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForGoalRowCount(
        _ expected: Int,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                self.goalRowIdentifiers(in: app).count == expected
            },
            object: app
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func assertGoalsHeaderElement(
        in app: XCUIApplication,
        identifier: String,
        expectedLabel: String
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let matches = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "identifier == %@", identifier))
                return matches.count == 1 && matches.firstMatch.exists
            },
            object: app
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "GOALS_HEADER_COUNT_MISMATCH: \(identifier)"
        )
        let matches = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier))
        XCTAssertEqual(matches.count, 1, "GOALS_HEADER_COUNT_MISMATCH: \(identifier)")
        XCTAssertEqual(
            matches.firstMatch.label,
            expectedLabel,
            "GOALS_HEADER_LABEL_MISMATCH: \(identifier)"
        )
    }

    @MainActor
    private func assertGoalsHeaderElementAbsent(
        in app: XCUIApplication,
        identifier: String
    ) {
        let matches = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier))
        XCTAssertEqual(matches.count, 0, "GOALS_HEADER_ALTERNATE_MODE_PRESENT: \(identifier)")
    }

    @MainActor
    private func goalRowIdentifiers(in app: XCUIApplication) -> Set<String> {
        Set(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "goals.goal."))
                .allElementsBoundByAccessibilityElement
                .map(\.identifier)
        )
    }

    @MainActor
    private func waitForGoalsStatus(
        in app: XCUIApplication,
        equals expected: String,
        timeout: TimeInterval
    ) -> Bool {
        waitForGoalsLabel(
            in: app,
            identifier: "goals.status",
            equals: expected,
            timeout: timeout
        )
    }

    @MainActor
    private func waitForGoalsSection(
        in app: XCUIApplication,
        equals section: String,
        timeout: TimeInterval
    ) -> Bool {
        waitForGoalsLabel(
            in: app,
            identifier: "goals.navigation.current",
            equals: "Goals report section: \(section)",
            timeout: timeout
        )
    }

    @MainActor
    private func waitForGoalsLabel(
        in app: XCUIApplication,
        identifier: String,
        equals expected: String,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let current = app.descendants(matching: .any)[identifier]
                return current.exists && current.label == expected
            },
            object: app
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForGoalsLabel(
        in app: XCUIApplication,
        identifier: String,
        containing expected: String,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let current = app.descendants(matching: .any)[identifier]
                return current.exists && current.label.contains(expected)
            },
            object: app
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func reopenGoalsFromDashboard(in app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)["sidebar.dashboard"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["sidebar.dashboard"].click()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.content"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["sidebar.goals"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["sidebar.goals"].click()
        XCTAssertTrue(app.descendants(matching: .any)["goals.page"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitForGoalsStatus(in: app, equals: "Goals status: Ready", timeout: 8))
    }

    @MainActor
    private func advanceGoalsSection(
        in app: XCUIApplication,
        to section: String,
        anchorIdentifier: String
    ) {
        let next = app.descendants(matching: .any)["goals.navigation.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(next.isEnabled)
        app.descendants(matching: .any)["goals.navigation.next"].click()
        XCTAssertTrue(waitForGoalsSection(in: app, equals: section, timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)[anchorIdentifier].waitForExistence(timeout: 5),
            "Missing Goals section anchor \(anchorIdentifier)"
        )
    }

    @MainActor
    private func assertGoalsElement(
        in app: XCUIApplication,
        identifier: String,
        labelSatisfies: (String) -> Bool
    ) {
        let matches = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier))
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in matches.count == 1 && matches.firstMatch.exists },
            object: app
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
        XCTAssertEqual(matches.count, 1, "GOALS_ELEMENT_COUNT_MISMATCH: \(identifier)")
        XCTAssertTrue(
            labelSatisfies(matches.firstMatch.label),
            "GOALS_ELEMENT_LABEL_MISMATCH: \(identifier)"
        )
    }

    @MainActor
    private func goalsTableRowCount(
        in app: XCUIApplication,
        identifier: String,
        prefix: String
    ) -> Int {
        let table = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        XCTAssertTrue(table.label.hasPrefix(prefix))
        let pieces = table.label.split(separator: " ")
        guard pieces.count >= 2,
              pieces.last == "rows",
              let count = Int(pieces[pieces.count - 2]) else {
            XCTFail("GOALS_TABLE_SUMMARY_NOT_PARSEABLE: \(identifier)")
            return -1
        }
        return count
    }

    @MainActor
    private func goalsFieldIsBlank(_ field: XCUIElement) -> Bool {
        guard field.waitForExistence(timeout: 5) else { return false }
        let value = String(describing: field.value ?? "")
        return value.isEmpty || [
            "Monthly CNY", "Annual return %", "Annual spending", "Withdrawal %"
        ].contains(value)
    }

    @MainActor
    private func assertLedgerSummary(
        app: XCUIApplication,
        ordinaryInflow: String,
        ordinaryOutflow: String,
        investmentInflow: String,
        investmentOutflow: String,
        net: String,
        transfers: String
    ) {
        let labels = [
            ("ledger.summary.ordinaryInflow", "Ordinary Inflow: CNY \(ordinaryInflow)"),
            ("ledger.summary.ordinaryOutflow", "Ordinary Outflow: CNY \(ordinaryOutflow)"),
            ("ledger.summary.investmentInflow", "Investment Inflow: CNY \(investmentInflow)"),
            ("ledger.summary.investmentOutflow", "Investment Outflow: CNY \(investmentOutflow)"),
            ("ledger.summary.net", "Net Cash Flow: CNY \(net)"),
            ("ledger.summary.transfers", "Transfers: \(transfers), excluded from cash flow")
        ]
        for (identifier, expectedLabel) in labels {
            XCTAssertTrue(
                waitForAccessibilityLabel(
                    in: app,
                    identifier: identifier,
                    equals: expectedLabel,
                    timeout: 5
                ),
                "Expected \(identifier) label to equal \(expectedLabel)"
            )
        }
    }

    @MainActor
    private func replaceText(in field: XCUIElement, with value: String) {
        NSPasteboard.general.clearContents()
        XCTAssertTrue(NSPasteboard.general.setString(value, forType: .string))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeKey("v", modifierFlags: .command)
    }

    @MainActor
    private func selectRow(app: XCUIApplication, kind: String, currency: String) {
        let row = app.descendants(matching: .any)["wealth.row.\(kind).\(currency)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
    }

    @MainActor
    private func deleteSelectedContainer(app: XCUIApplication) {
        app.descendants(matching: .any)["wealth.delete"].click()
        let confirmDelete = app.descendants(matching: .any)["wealth.delete.confirm"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.click()
    }

    @MainActor
    private func assertSummary(
        app: XCUIApplication,
        assets: String,
        liabilities: String,
        netWorth: String
    ) {
        XCTAssertTrue(
            waitForValue(
                app.descendants(matching: .any)["wealth.summary.assets"],
                containing: assets,
                timeout: 5
            )
        )
        XCTAssertTrue(
            waitForValue(
                app.descendants(matching: .any)["wealth.summary.liabilities"],
                containing: liabilities,
                timeout: 5
            )
        )
        XCTAssertTrue(
            waitForValue(
                app.descendants(matching: .any)["wealth.summary.netWorth"],
                containing: netWorth,
                timeout: 5
            )
        )
    }

    @MainActor
    private func wealthRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.outlines.element(boundBy: 1).cells
    }

    @MainActor
    private func waitForRowCount(
        _ expected: Int,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if wealthRows(in: app).count == expected { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return false
    }

    @MainActor
    private func waitForValue(
        _ element: XCUIElement,
        containing text: String,
        timeout: TimeInterval
    ) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        if String(describing: element.value ?? "").localizedCaseInsensitiveContains(text) { return true }
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS[c] %@", text),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForValueOrLabel(
        _ element: XCUIElement,
        containing text: String,
        timeout: TimeInterval
    ) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        if String(describing: element.value ?? "").localizedCaseInsensitiveContains(text)
            || element.label.localizedCaseInsensitiveContains(text) { return true }
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS[c] %@ OR label CONTAINS[c] %@", text, text),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func chooseFile(_ path: String, in app: XCUIApplication) {
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "Synthetic import fixture was not created")
        XCTAssertTrue(
            app.sheets.firstMatch.waitForExistence(timeout: 5)
                || app.dialogs.firstMatch.waitForExistence(timeout: 5),
            "Native Open Panel did not appear"
        )
        app.typeKey("g", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.textFields["PathTextField"].waitForExistence(timeout: 5))
        replaceText(in: app.textFields["PathTextField"], with: path)
        app.typeKey(.return, modifierFlags: [])
        if !waitForNonexistence(app.sheets["GoToWindow"], timeout: 1) {
            // The first Return may accept the selected path-completion row;
            // the second confirms that resolved path in the native panel.
            app.typeKey(.return, modifierFlags: [])
        }
        XCTAssertTrue(
            waitForNonexistence(app.sheets["GoToWindow"], timeout: 5),
            "Open Panel Go To sheet did not dismiss after entering the synthetic CSV path"
        )
        let preview = app.descendants(matching: .any)["ledger.import.preview.summary"]
        if preview.waitForExistence(timeout: 10) { return }
        XCTAssertTrue(
            waitForCurrentPanelControl(
                in: app,
                identifier: "OKButton",
                elementType: .button,
                timeout: 5
            ),
            "Open Panel did not reach file-selection state"
        )
        let open = currentNativePanel(in: app)
            .descendants(matching: .button)["OKButton"].firstMatch
        XCTAssertTrue(waitForEnabled(open, timeout: 5), "Open button never became enabled")
        let currentOpen = currentNativePanel(in: app)
            .descendants(matching: .button)["OKButton"].firstMatch
        if currentOpen.isHittable { currentOpen.click() }
        else { app.typeKey(.enter, modifierFlags: []) }
        XCTAssertTrue(
            waitForNativePanelToDisappear(in: app, timeout: 5),
            "Open Panel did not dismiss after selecting the synthetic CSV"
        )
    }

    @MainActor
    private func saveFileUsingDefaultFilename(at expectedURL: URL, in app: XCUIApplication) {
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: expectedURL.path),
            "Synthetic export destination must not exist before opening the Save Panel"
        )
        XCTAssertTrue(
            app.sheets.firstMatch.waitForExistence(timeout: 5)
                || app.dialogs.firstMatch.waitForExistence(timeout: 5),
            "Native Save Panel did not appear"
        )
        app.typeKey("g", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.textFields["PathTextField"].waitForExistence(timeout: 5))
        replaceText(
            in: app.textFields["PathTextField"],
            with: expectedURL.deletingLastPathComponent().path
        )
        app.typeKey(.return, modifierFlags: [])
        if !waitForNonexistence(app.sheets["GoToWindow"], timeout: 5) {
            app.typeKey(.return, modifierFlags: [])
        }
        XCTAssertTrue(waitForNonexistence(app.sheets["GoToWindow"], timeout: 5))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: expectedURL.path),
            "Save Panel navigation must not create the synthetic export"
        )
        XCTAssertTrue(
            waitForCurrentPanelControl(
                in: app,
                identifier: "OKButton",
                elementType: .button,
                timeout: 5
            ),
            "Save Panel did not reach export state"
        )
        let save = currentNativePanel(in: app)
            .descendants(matching: .button)["OKButton"].firstMatch
        XCTAssertTrue(waitForEnabled(save, timeout: 5), "Export button never became enabled")
        let currentSave = currentNativePanel(in: app)
            .descendants(matching: .button)["OKButton"].firstMatch
        XCTAssertTrue(currentSave.isHittable, "Save button is not hittable")
        currentSave.click()
        XCTAssertTrue(
            waitForNativePanelToDisappear(in: app, timeout: 5),
            "Save Panel did not dismiss after confirming the synthetic export"
        )
        XCTAssertTrue(
            waitForFile(at: expectedURL.path, timeout: 5),
            "Native Save Panel dismissed but the synthetic export was not created"
        )
    }

    @MainActor
    private func chooseDirectory(_ path: String, in app: XCUIApplication) {
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertTrue(
            app.sheets.firstMatch.waitForExistence(timeout: 5)
                || app.dialogs.firstMatch.waitForExistence(timeout: 5),
            "Native directory-selection panel did not appear"
        )
        app.typeKey("g", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.textFields["PathTextField"].waitForExistence(timeout: 5))
        replaceText(in: app.textFields["PathTextField"], with: path)
        app.typeKey(.return, modifierFlags: [])
        if !waitForNonexistence(app.sheets["GoToWindow"], timeout: 5) {
            app.typeKey(.return, modifierFlags: [])
        }
        XCTAssertTrue(
            waitForNonexistence(app.sheets["GoToWindow"], timeout: 5),
            "Directory panel Go To sheet did not dismiss"
        )
        XCTAssertTrue(
            currentNativePanel(in: app).exists,
            "Native directory-selection panel did not remain active after Go To"
        )
        app.typeKey(.enter, modifierFlags: [])
    }

    private func externalExportSnapshot(at destination: URL) throws -> [String: Data] {
        var snapshot: [String: Data] = [:]
        let generations = try FileManager.default.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: nil
        )
        for generation in generations.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            snapshot["directory/\(generation.lastPathComponent)"] = Data()
            let artifacts = try FileManager.default.contentsOfDirectory(
                at: generation,
                includingPropertiesForKeys: nil
            )
            for artifact in artifacts {
                snapshot["file/\(generation.lastPathComponent)/\(artifact.lastPathComponent)"]
                    = try Data(contentsOf: artifact)
            }
        }
        return snapshot
    }

    @MainActor
    private func currentNativePanel(in app: XCUIApplication) -> XCUIElement {
        app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
    }

    @MainActor
    private func waitForCurrentPanelControl(
        in app: XCUIApplication,
        identifier: String,
        elementType: XCUIElement.ElementType,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let panel = currentNativePanel(in: app)
            if panel.exists,
               panel.descendants(matching: elementType)[identifier].firstMatch.exists {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return false
    }

    @MainActor
    private func waitForPickerSelection(
        in app: XCUIApplication,
        identifier: String,
        containing text: String,
        timeout: TimeInterval
    ) -> Bool {
        let pickerAfterPopup = app.descendants(matching: .any)[identifier]
        guard pickerAfterPopup.waitForExistence(timeout: timeout) else { return false }
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "value CONTAINS[c] %@ OR label CONTAINS[c] %@",
                text,
                text
            ),
            object: pickerAfterPopup
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForPortfolioSummaryName(
        in app: XCUIApplication,
        equals expected: String,
        timeout: TimeInterval
    ) -> Bool {
        waitForAccessibilityLabel(
            in: app,
            identifier: "portfolio.summary.name",
            equals: "Portfolio name: \(expected)",
            timeout: timeout
        )
    }

    @MainActor
    private func waitForPortfolioOrderStatus(
        in app: XCUIApplication,
        portfolioName: String,
        position: Int,
        total: Int,
        timeout: TimeInterval
    ) -> Bool {
        waitForAccessibilityLabel(
            in: app,
            identifier: "portfolio.order.status",
            equals: "Portfolio order: \(portfolioName), position \(position) of \(total)",
            timeout: timeout
        )
    }

    @MainActor
    private func reopenPortfolioFromDashboard(in app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)["sidebar.dashboard"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["sidebar.dashboard"].click()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.content"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["sidebar.portfolio"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["sidebar.portfolio"].click()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.page"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func waitForAccessibilityLabel(
        in app: XCUIApplication,
        identifier: String,
        equals expected: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let current = app.descendants(matching: .any)[identifier]
            if current.exists, current.label == expected { return true }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return false
    }

    @MainActor
    private func assertAnalyticsOverview(
        in app: XCUIApplication,
        portfolioName: String
    ) {
        let heading = analyticsDetailContractEvidence(
            in: app,
            identifier: "analytics.overview.heading",
            timeout: 5,
            labelSatisfies: { $0 == "Analytics report overview" }
        )
        XCTAssertEqual(heading.matchCount, 1, "OVERVIEW_HEADING_COUNT_MISMATCH")
        XCTAssertTrue(heading.labelMatched, "OVERVIEW_HEADING_LABEL_MISMATCH")
        XCTAssertEqual(
            heading.viewportRelation.rawValue,
            AnalyticsViewportRelation.insideViewport.rawValue,
            "OVERVIEW_HEADING_VIEWPORT_MISMATCH"
        )

        let portfolioTitle = analyticsDetailContractEvidence(
            in: app,
            identifier: "analytics.report.portfolio",
            timeout: 5,
            labelSatisfies: { $0 == "Portfolio analytics report: \(portfolioName)" }
        )
        XCTAssertEqual(portfolioTitle.matchCount, 1, "PORTFOLIO_TITLE_COUNT_MISMATCH")
        XCTAssertTrue(portfolioTitle.labelMatched, "PORTFOLIO_TITLE_LABEL_MISMATCH")
        XCTAssertEqual(
            portfolioTitle.viewportRelation.rawValue,
            AnalyticsViewportRelation.insideViewport.rawValue,
            "PORTFOLIO_TITLE_VIEWPORT_MISMATCH"
        )

        let coverage = analyticsDetailContractEvidence(
            in: app,
            identifier: "analytics.coverage",
            timeout: 5,
            labelSatisfies: {
                $0.contains("Observation coverage: range")
                    && $0.contains(" through ")
                    && $0.contains("complete snapshots used")
                    && $0.contains("incomplete snapshots excluded")
            }
        )
        XCTAssertEqual(coverage.matchCount, 1, "COVERAGE_COUNT_MISMATCH")
        XCTAssertTrue(coverage.labelMatched, "COVERAGE_LABEL_MISMATCH")
        XCTAssertEqual(
            coverage.viewportRelation.rawValue,
            AnalyticsViewportRelation.insideViewport.rawValue,
            "COVERAGE_VIEWPORT_MISMATCH"
        )
    }

    @MainActor
    private func analyticsDetailContractEvidence(
        in app: XCUIApplication,
        identifier: String,
        timeout: TimeInterval,
        labelSatisfies: (String) -> Bool
    ) -> AnalyticsDetailContractEvidence {
        let deadline = Date().addingTimeInterval(timeout)
        var evidence = AnalyticsDetailContractEvidence(
            matchCount: 0,
            labelMatched: false,
            viewportRelation: .notExposed
        )

        repeat {
            let scrollView = app.descendants(matching: .any)["analytics.detail.scroll"]
            if scrollView.exists {
                let matches = scrollView.descendants(matching: .any)
                    .matching(NSPredicate(format: "identifier == %@", identifier))
                let matchCount = matches.count
                let element = matchCount == 1 ? matches.firstMatch : nil
                evidence = AnalyticsDetailContractEvidence(
                    matchCount: matchCount,
                    labelMatched: element.map { labelSatisfies($0.label) } ?? false,
                    viewportRelation: analyticsViewportSnapshot(
                        of: element,
                        in: scrollView
                    ).relation
                )
                if evidence.matchCount == 1,
                   evidence.labelMatched,
                   evidence.viewportRelation == .insideViewport {
                    break
                }
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline

        XCTContext.runActivity(
            named: "Analytics detail evidence: identifier=\(identifier); matchCount=\(evidence.matchCount); labelMatched=\(evidence.labelMatched); viewportRelation=\(evidence.viewportRelation.rawValue)"
        ) { _ in }
        return evidence
    }

    @MainActor
    private func advanceAnalyticsReportSection(
        in app: XCUIApplication,
        to sectionTitle: String,
        anchorIdentifier: String
    ) -> Bool {
        let nextButton = app.descendants(matching: .any)["analytics.navigation.next"]
        guard nextButton.waitForExistence(timeout: 5), nextButton.isEnabled else { return false }
        nextButton.click()

        guard waitForAccessibilityLabel(
            in: app,
            identifier: "analytics.navigation.current",
            equals: "Analytics report section: \(sectionTitle)",
            timeout: 5
        ) else { return false }

        return waitForAnalyticsDetailElement(
            in: app,
            identifier: anchorIdentifier,
            timeout: 5,
            requireUnique: true,
            mustBeInsideViewport: true
        )
    }

    @MainActor
    private func waitForAnalyticsDetailElement(
        in app: XCUIApplication,
        identifier: String,
        identifierIsPrefix: Bool = false,
        timeout: TimeInterval,
        requireUnique: Bool = false,
        mustBeInsideViewport: Bool = true,
        labelSatisfies: (String) -> Bool = { _ in true }
    ) -> Bool {
        let predicate = identifierIsPrefix
            ? NSPredicate(format: "identifier BEGINSWITH %@", identifier)
            : NSPredicate(format: "identifier == %@", identifier)
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            let scrollView = app.descendants(matching: .any)["analytics.detail.scroll"]
            if scrollView.exists {
                let matches = scrollView.descendants(matching: .any).matching(predicate)
                if !requireUnique || matches.count == 1 {
                    for element in matches.allElementsBoundByAccessibilityElement {
                        guard element.exists, labelSatisfies(element.label) else { continue }
                        if !mustBeInsideViewport
                            || analyticsViewportSnapshot(of: element, in: scrollView).relation == .insideViewport {
                            return true
                        }
                    }
                }
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline

        return false
    }

    @MainActor
    private func analyticsViewportSnapshot(
        of element: XCUIElement?,
        in scrollView: XCUIElement
    ) -> AnalyticsViewportSnapshot {
        guard let element, element.exists, scrollView.exists else {
            return AnalyticsViewportSnapshot(relation: .notExposed, midY: nil, height: nil)
        }
        let elementFrame = element.frame
        let viewportFrame = scrollView.frame
        guard analyticsFrameIsValid(elementFrame), analyticsFrameIsValid(viewportFrame) else {
            return AnalyticsViewportSnapshot(relation: .invalidFrame, midY: nil, height: nil)
        }
        let horizontalOverlap = min(elementFrame.maxX, viewportFrame.maxX)
            - max(elementFrame.minX, viewportFrame.minX)
        guard horizontalOverlap > 0 else {
            return AnalyticsViewportSnapshot(
                relation: .outsideScrollRegion,
                midY: elementFrame.midY,
                height: elementFrame.height
            )
        }
        if elementFrame.maxY <= viewportFrame.minY {
            return AnalyticsViewportSnapshot(
                relation: .aboveViewport,
                midY: elementFrame.midY,
                height: elementFrame.height
            )
        }
        if elementFrame.minY >= viewportFrame.maxY {
            return AnalyticsViewportSnapshot(
                relation: .belowViewport,
                midY: elementFrame.midY,
                height: elementFrame.height
            )
        }
        let verticalOverlap = min(elementFrame.maxY, viewportFrame.maxY)
            - max(elementFrame.minY, viewportFrame.minY)
        return AnalyticsViewportSnapshot(
            relation: verticalOverlap > 0 ? .insideViewport : .invalidFrame,
            midY: elementFrame.midY,
            height: elementFrame.height
        )
    }

    private func analyticsFrameIsValid(_ frame: CGRect) -> Bool {
        !frame.isNull
            && !frame.isInfinite
            && frame.width > 0
            && frame.height > 0
            && frame.minX.isFinite
            && frame.minY.isFinite
            && frame.maxX.isFinite
            && frame.maxY.isFinite
    }

    @MainActor
    private func waitForAnalyticsTableSummary(
        in app: XCUIApplication,
        identifier: String,
        labelPrefix: String,
        timeout: TimeInterval
    ) -> Bool {
        waitForAnalyticsDetailElement(
            in: app,
            identifier: identifier,
            timeout: timeout,
            requireUnique: true,
            mustBeInsideViewport: true,
            labelSatisfies: { label in
                label.hasPrefix(labelPrefix)
                    && analyticsTableRowCount(from: label).map { $0 > 0 } == true
            }
        )
    }

    private func analyticsTableRowCount(from label: String) -> Int? {
        let components = label.split(separator: " ")
        guard components.count >= 2,
              components.last == "rows"
        else { return nil }
        return Int(components[components.count - 2])
    }

    private func observedReturnsTableRowCounts(
        from label: String
    ) -> (monthly: Int, annual: Int)? {
        let components = label.split(separator: " ")
        guard components.count == 9,
              components[0] == "Observed",
              components[1] == "returns",
              components[2] == "tables:",
              components[4] == "monthly",
              components[5] == "rows,",
              components[7] == "annual",
              components[8] == "rows",
              let monthly = Int(components[3]),
              let annual = Int(components[6])
        else { return nil }
        return (monthly, annual)
    }

    @MainActor
    private func waitForAnalyticsTableRow(
        in app: XCUIApplication,
        identifierPrefix: String,
        timeout: TimeInterval,
        labelSatisfies: @escaping (String) -> Bool
    ) -> Bool {
        waitForAnalyticsDetailElement(
            in: app,
            identifier: identifierPrefix,
            identifierIsPrefix: true,
            timeout: timeout,
            mustBeInsideViewport: true,
            labelSatisfies: labelSatisfies
        )
    }

    @MainActor
    private func waitForPortfolioRowCount(
        _ expected: Int,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let rows = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "portfolio.row."))
            if rows.count == expected { return true }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return false
    }

    @MainActor
    private func waitForIdentifierToDisappear(
        _ identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let current = app.descendants(matching: .any)[identifier]
            if !current.exists { return true }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return false
    }

    @MainActor
    private func portfolioRowIdentifiers(in app: XCUIApplication) -> Set<String> {
        Set(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "portfolio.row."))
                .allElementsBoundByIndex
                .map(\.identifier)
        )
    }

    @MainActor
    private func waitForControlState(
        in app: XCUIApplication,
        identifier: String,
        isEnabled expected: Bool,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let current = app.descendants(matching: .any)[identifier]
            if current.exists, current.isEnabled == expected { return true }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return false
    }

    @MainActor
    private func waitForMarketsSearchTerminal(in app: XCUIApplication, timeout: TimeInterval) -> String {
        let status = app.descendants(matching: .any)["markets.search.status"]
        guard status.waitForExistence(timeout: 5) else { return "Status Missing" }
        let terminals = [
            "Ready", "Cancelled", "Invalid Payload", "Provider Error",
            "Missing Credential", "Invalid Credential", "Upgrade Required",
            "Unsupported Entitlement", "Unsupported Market", "Rate Limited",
            "Offline", "Timeout", "Missing", "Insufficient Data"
        ]
        let terminalLabels = terminals.map { "Search status: \($0)" }
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label IN %@", terminalLabels),
            object: status
        )
        _ = XCTWaiter.wait(for: [expectation], timeout: timeout)
        let label = app.descendants(matching: .any)["markets.search.status"].label
        return label.replacingOccurrences(of: "Search status: ", with: "")
    }

    @MainActor
    private func dismissResidualNativePanels(in app: XCUIApplication) {
        for _ in 0..<3 where app.sheets.firstMatch.exists || app.dialogs.firstMatch.exists {
            app.typeKey(.escape, modifierFlags: [])
            _ = waitForNativePanelToDisappear(in: app, timeout: 1)
        }
    }

    @MainActor
    private func waitForNativePanelToDisappear(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if !app.sheets.firstMatch.exists && !app.dialogs.firstMatch.exists { return true }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return false
    }

    @MainActor
    private func waitForNonexistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForFile(at path: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if FileManager.default.fileExists(atPath: path) { return true }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return false
    }

    private func syntheticImportCSV(transactionID: UUID) -> Data {
        let header = [
            "schema_version", "transaction_id", "kind", "civil_date", "recorded_at_ms",
            "description", "payee", "category", "tags", "source_container_id",
            "source_currency", "source_amount", "source_fx_rate", "source_converted_cny",
            "source_fx_source", "source_fx_reference_date", "source_fx_recorded_at_ms",
            "source_fx_manual", "source_fx_stale", "target_container_id", "target_currency",
            "target_amount", "target_fx_rate", "target_converted_cny", "target_fx_source",
            "target_fx_reference_date", "target_fx_recorded_at_ms", "target_fx_manual",
            "target_fx_stale", "note"
        ]
        let row = [
            "AUREUS_LEDGER_V1", transactionID.uuidString, "expense", "2026-01-16", "1768521600000",
            "Synthetic CSV Expense", "Synthetic Payee", "", "", "00000000-0000-4000-8000-000000003001",
            "CNY", "12.34", "1", "12.34", "identity", "2026-01-16", "1768521600000",
            "false", "false", "", "", "", "", "", "", "", "", "", "",
            "Synthetic UI-generated import fixture"
        ]
        func encoded(_ fields: [String]) -> String {
            fields.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",")
        }
        return Data("\(encoded(header))\r\n\(encoded(row))\r\n".utf8)
    }


    private func uiTestingArguments(demo: Bool = false) -> [String] {
        var arguments = [
            "--aureus-ui-testing",
            "-ApplePersistenceIgnoreState", "YES",
            "-NSQuitAlwaysKeepsWindows", "NO"
        ]
        if demo { arguments.append("--aureus-demo") }
        return arguments
    }

    @MainActor
    private func launchApp(_ app: XCUIApplication) {
        // A failed native file panel can leave the prior UI-test process alive
        // without a visible WindowGroup. Start every test from a terminated
        // process instead of relying on macOS state restoration.
        dismissResidualNativePanels(in: app)
        app.terminate()
        app.launch()
        app.activate()
        if !app.descendants(matching: .any)["sidebar.dashboard"].waitForExistence(timeout: 3) {
            // macOS may restore the process without a visible WindowGroup
            // window after repeated UI-test launches. Use the native New
            // Window command without depending on transient menu geometry.
            app.typeKey("n", modifierFlags: [.command])
            XCTAssertTrue(app.descendants(matching: .any)["sidebar.dashboard"].waitForExistence(timeout: 5))
        }
    }
}
