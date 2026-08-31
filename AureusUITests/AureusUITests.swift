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
