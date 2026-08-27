import AppKit
import XCTest

final class AureusUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
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
                else { expectedIdentifier = "destination.\(destination)" }
                XCTAssertTrue(
                    app.descendants(matching: .any)[expectedIdentifier].waitForExistence(timeout: 5),
                    "Missing destination content for \(destination)"
                )
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

        let name = app.descendants(matching: .any)["portfolio.create.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeText("Synthetic Second Portfolio")
        app.descendants(matching: .any)["portfolio.create"].click()
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "portfolio.row.")).count, 2)
        XCTAssertTrue(assertPortfolioSummaryName(in: app, equals: "Synthetic Second Portfolio"))
        XCTAssertEqual(app.descendants(matching: .any)["portfolio.summary.name"].label, "Portfolio name")
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.move.up"].isEnabled)
        app.descendants(matching: .any)["portfolio.move.up"].click()
        XCTAssertFalse(app.descendants(matching: .any)["portfolio.move.up"].isEnabled)

        // Recreate the feature model against the same temporary Store by
        // navigating away and back. The first persisted row must remain the
        // moved Portfolio, without relying on a List row index.
        app.descendants(matching: .any)["sidebar.dashboard"].click()
        app.descendants(matching: .any)["sidebar.portfolio"].click()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.page"].waitForExistence(timeout: 5))
        XCTAssertTrue(assertPortfolioSummaryName(in: app, equals: "Synthetic Second Portfolio"))
        XCTAssertFalse(app.descendants(matching: .any)["portfolio.move.up"].isEnabled)
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "portfolio.row.")).count, 2)

        app.descendants(matching: .any)["portfolio.delete"].click()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.delete.confirm"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["portfolio.delete.confirm"].click()
        XCTAssertTrue(app.descendants(matching: .any)["portfolio.summary.name"].waitForExistence(timeout: 5))
        XCTAssertTrue(assertPortfolioSummaryName(in: app, equals: "Synthetic Local Portfolio"))
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "portfolio.row.")).count, 1)

        app.terminate()
        let production = XCUIApplication()
        production.launchArguments = uiTestingArguments()
        launchApp(production)
        production.descendants(matching: .any)["sidebar.portfolio"].click()
        XCTAssertTrue(production.descendants(matching: .any)["portfolio.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(production.descendants(matching: .any)["portfolio.holding.SYNX|XSYN"].exists)
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
    func testWealthCNYUSDLiabilityCRUDAndDynamicTotals() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments()
        launchApp(app)
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
    func testLedgerDynamicCashFlowTransferInvestmentEditAndDelete() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments()
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
    func testLedgerNativeCSVImportPreviewConfirmationAndExport() throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("Aureus-Stage6MA-CSV-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let importURL = root.appendingPathComponent("Synthetic-Import.csv")
        let exportURL = root.appendingPathComponent("Synthetic-Export.csv")
        try syntheticImportCSV(transactionID: UUID()).write(to: importURL, options: .atomic)

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
        saveFile(exportURL.path, in: app)
        XCTAssertTrue(waitForNonexistence(app.sheets.firstMatch, timeout: 5))
        XCTAssertFalse(app.alerts["Ledger Error"].exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
    }

    @MainActor
    func testStage6SettingsCredentialEntitlementAndCacheLifecycle() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments()
        launchApp(app)

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

        app.descendants(matching: .any)["settings.cache.reset"].click()
        let reset = app.descendants(matching: .any)["settings.cache.reset.confirm"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5)); reset.click()
        XCTAssertTrue(waitForValueOrLabel(
            app.descendants(matching: .any)["settings.status"],
            containing: "reset and rebuilt",
            timeout: 5
        ))

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
    private func assertLedgerSummary(
        app: XCUIApplication,
        ordinaryInflow: String,
        ordinaryOutflow: String,
        investmentInflow: String,
        investmentOutflow: String,
        net: String,
        transfers: String
    ) {
        let values = [
            ("ledger.summary.ordinaryInflow", ordinaryInflow),
            ("ledger.summary.ordinaryOutflow", ordinaryOutflow),
            ("ledger.summary.investmentInflow", investmentInflow),
            ("ledger.summary.investmentOutflow", investmentOutflow),
            ("ledger.summary.net", net),
            ("ledger.summary.transfers", transfers)
        ]
        for (identifier, expected) in values {
            XCTAssertTrue(waitForValue(app.descendants(matching: .any)[identifier], containing: expected, timeout: 5), "Expected \(identifier) to contain \(expected)")
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
    private func saveFile(_ path: String, in app: XCUIApplication) {
        XCTAssertTrue(
            app.sheets.firstMatch.waitForExistence(timeout: 5)
                || app.dialogs.firstMatch.waitForExistence(timeout: 5),
            "Native Save Panel did not appear"
        )
        app.typeKey("g", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.textFields["PathTextField"].waitForExistence(timeout: 5))
        replaceText(
            in: app.textFields["PathTextField"],
            with: URL(fileURLWithPath: path).deletingLastPathComponent().path
        )
        app.typeKey(.return, modifierFlags: [])
        if !waitForNonexistence(app.sheets["GoToWindow"], timeout: 5) {
            app.typeKey(.return, modifierFlags: [])
        }
        XCTAssertTrue(waitForNonexistence(app.sheets["GoToWindow"], timeout: 5))
        if FileManager.default.fileExists(atPath: path) {
            return
        }
        XCTAssertTrue(
            waitForCurrentPanelControl(
                in: app,
                identifier: "saveAsNameTextField",
                elementType: .textField,
                timeout: 8
            ),
            "Save Panel did not expose its current filename field"
        )
        replaceText(
            in: currentNativePanel(in: app)
                .descendants(matching: .textField)["saveAsNameTextField"],
            with: URL(fileURLWithPath: path).lastPathComponent
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
        if currentSave.isHittable { currentSave.click() }
        else { app.typeKey(.enter, modifierFlags: []) }
        if waitForCurrentPanelControl(
            in: app,
            identifier: "Replace",
            elementType: .button,
            timeout: 1
        ) {
            let replace = currentNativePanel(in: app)
                .descendants(matching: .button)["Replace"].firstMatch
            XCTAssertTrue(replace.isHittable)
            replace.click()
        }
        XCTAssertTrue(
            waitForFile(at: path, timeout: 5),
            "Native Save Panel dismissed but the synthetic export was not created"
        )
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
    private func assertPortfolioSummaryName(in app: XCUIApplication, equals expected: String) -> Bool {
        let summary = app.descendants(matching: .any)["portfolio.summary.name"]
        guard summary.waitForExistence(timeout: 5), summary.label == "Portfolio name" else { return false }
        return String(describing: summary.value ?? "").contains(expected)
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
