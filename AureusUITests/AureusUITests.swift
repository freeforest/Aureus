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

        XCTAssertTrue(app.descendants(matching: .any)["mode.empty"].waitForExistence(timeout: 10))
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
                if destination == "dashboard" { expectedIdentifier = "mode.empty" }
                else if destination == "wealth" { expectedIdentifier = "wealth.page" }
                else if destination == "ledger" { expectedIdentifier = "ledger.empty" }
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
        XCTAssertFalse(app.descendants(matching: .any)["mode.empty"].exists)

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
    func testDashboardEmptyStoreDoesNotFabricateSnapshot() throws {
        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments()
        launchApp(app)

        XCTAssertTrue(app.descendants(matching: .any)["dashboard.empty"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.snapshot.status"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.history.chart"].exists)
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
            .appendingPathComponent("Aureus-Stage4A-CSV-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let importURL = root.appendingPathComponent("Synthetic-Import.csv")
        let exportURL = root.appendingPathComponent("Synthetic-Export.csv")
        try syntheticImportCSV(transactionID: UUID()).write(to: importURL, options: .atomic)

        let app = XCUIApplication()
        app.launchArguments = uiTestingArguments(demo: true)
        launchApp(app)
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
            let typePicker = app.descendants(matching: .any)["wealth.form.type"]
            XCTAssertTrue(typePicker.waitForExistence(timeout: 5))
            typePicker.click()
            let kindItem = app.menuItems[kind]
            XCTAssertTrue(kindItem.waitForExistence(timeout: 5))
            kindItem.click()
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
            let picker = app.descendants(matching: .any)["ledger.form.kind"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5)); picker.click()
            let item = app.menuItems[kind]
            XCTAssertTrue(item.waitForExistence(timeout: 5)); item.click()
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
        let picker = app.descendants(matching: .any)["ledger.filter.kind"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5)); picker.click()
        let item = app.menuItems[title]
        XCTAssertTrue(item.waitForExistence(timeout: 5)); item.click()
    }

    @MainActor
    private func selectPicker(app: XCUIApplication, identifier: String, title: String) {
        let picker = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Missing picker \(identifier)")
        picker.click()
        let item = app.menuItems[title]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Missing picker item \(title) for \(identifier)")
        item.click()
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
        let panel = app.sheets.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5) || app.dialogs.firstMatch.waitForExistence(timeout: 5))
        app.typeKey("g", modifierFlags: [.command, .shift])
        let field = app.textFields["PathTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceText(in: field, with: path)
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
        if app.descendants(matching: .any)["ledger.import.preview.summary"].waitForExistence(timeout: 10) {
            return
        }
        let open = app.buttons["OKButton"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5), "Open Panel did not reach file-selection state")
        XCTAssertTrue(waitForEnabled(open, timeout: 5), "Open button never became enabled")
        if open.isHittable { open.click() } else { app.typeKey(.enter, modifierFlags: []) }
        XCTAssertTrue(waitForNonexistence(open, timeout: 5), "Open Panel did not dismiss after selecting the synthetic CSV")
    }

    @MainActor
    private func saveFile(_ path: String, in app: XCUIApplication) {
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5) || app.dialogs.firstMatch.waitForExistence(timeout: 5))
        app.typeKey("g", modifierFlags: [.command, .shift])
        let goToField = app.textFields["PathTextField"]
        XCTAssertTrue(goToField.waitForExistence(timeout: 5))
        replaceText(in: goToField, with: URL(fileURLWithPath: path).deletingLastPathComponent().path)
        app.typeKey(.return, modifierFlags: [])
        if !waitForNonexistence(app.sheets["GoToWindow"], timeout: 5) {
            app.typeKey(.return, modifierFlags: [])
        }
        XCTAssertTrue(waitForNonexistence(app.sheets["GoToWindow"], timeout: 5))
        if FileManager.default.fileExists(atPath: path) {
            return
        }
        let fileNameField = app.textFields["saveAsNameTextField"]
        XCTAssertTrue(fileNameField.waitForExistence(timeout: 5))
        replaceText(in: fileNameField, with: URL(fileURLWithPath: path).lastPathComponent)
        let save = app.buttons["OKButton"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Save Panel did not reach export state")
        XCTAssertTrue(waitForEnabled(save, timeout: 5), "Export button never became enabled")
        if save.isHittable { save.click() } else { app.typeKey(.enter, modifierFlags: []) }
        let replace = app.sheets.buttons["Replace"].firstMatch
        if replace.waitForExistence(timeout: 1) {
            XCTAssertTrue(replace.isHittable); replace.click()
        }
        XCTAssertTrue(waitForNonexistence(save, timeout: 5), "Save Panel did not dismiss after export")
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
