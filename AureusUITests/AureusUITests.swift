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
        XCTAssertTrue(app.descendants(matching: .any)["destination.dashboard"].exists)

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
                if destination == "wealth" { expectedIdentifier = "wealth.page" }
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
        XCTAssertTrue(app.descendants(matching: .any)["destination.dashboard"].exists)
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

        addLedgerEntry(app: app, kind: "Income", description: "Synthetic UI Income", amount: "100.00")
        assertLedgerSummary(app: app, ordinaryInflow: "100.00", ordinaryOutflow: "0.00", investmentInflow: "0.00", investmentOutflow: "0.00", net: "100.00", transfers: "0")

        addLedgerEntry(app: app, kind: "Expense", description: "Synthetic UI Expense", amount: "30.00")
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
    }

    @MainActor
    func testLedgerNativeCSVImportPreviewConfirmationAndExport() throws {
        let importURL = URL(fileURLWithPath: "/private/tmp/Aureus-Stage4-UI-Import.csv")
        let exportURL = URL(fileURLWithPath: "/private/tmp/Aureus-Stage4-UI-Export.csv")

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
        app.descendants(matching: .any)["ledger.import.confirm"].click()
        XCTAssertTrue(app.staticTexts["Synthetic CSV Income"].waitForExistence(timeout: 10))

        app.descendants(matching: .any)["ledger.export"].click()
        saveFile(exportURL.path, in: app)
        XCTAssertTrue(waitForNonexistence(app.sheets.firstMatch, timeout: 5))
        XCTAssertFalse(app.alerts["Ledger Error"].exists)
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
        targetAmount: String? = nil
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
        field.click(); field.typeKey("a", modifierFlags: .command); field.typeText(value)
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
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5) || app.dialogs.firstMatch.waitForExistence(timeout: 5))
        app.typeKey("g", modifierFlags: [.command, .shift])
        let field = app.textFields["PathTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceText(in: field, with: path)
        app.typeKey(.enter, modifierFlags: [])
        XCTAssertTrue(waitForNonexistence(field, timeout: 5))
        let open = app.buttons["Open"].firstMatch
        if open.waitForExistence(timeout: 3) {
            // The system panel's button may report a stale center after several
            // application launches. Activate its default action from the
            // keyboard so the real user-selected-file path remains exercised.
            app.typeKey(.enter, modifierFlags: [])
        }
    }

    @MainActor
    private func saveFile(_ path: String, in app: XCUIApplication) {
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5) || app.dialogs.firstMatch.waitForExistence(timeout: 5))
        app.typeKey("g", modifierFlags: [.command, .shift])
        let goToField = app.textFields["PathTextField"]
        XCTAssertTrue(goToField.waitForExistence(timeout: 5))
        replaceText(in: goToField, with: URL(fileURLWithPath: path).deletingLastPathComponent().path)
        app.typeKey(.enter, modifierFlags: [])
        XCTAssertTrue(waitForNonexistence(app.sheets["GoToWindow"], timeout: 5))
        let fileNameField = app.textFields["saveAsNameTextField"]
        XCTAssertTrue(fileNameField.waitForExistence(timeout: 5))
        replaceText(in: fileNameField, with: URL(fileURLWithPath: path).lastPathComponent)
        let save = app.sheets.buttons["Export"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5)); save.click()
        let replace = app.sheets.buttons["Replace"].firstMatch
        if replace.waitForExistence(timeout: 2) { replace.click() }
    }

    @MainActor
    private func waitForNonexistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
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
