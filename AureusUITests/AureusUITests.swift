import XCTest

final class AureusUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEmptyAppLaunchesAndAllDestinationsNavigateRepeatedly() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--aureus-ui-testing"]
        app.launch()

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
                XCTAssertTrue(
                    app.descendants(matching: .any)["destination.\(destination)"].waitForExistence(timeout: 5),
                    "Missing honest placeholder for \(destination)"
                )
            }
        }
    }

    @MainActor
    func testSyntheticDemoIsVisiblyIdentified() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--aureus-ui-testing", "--aureus-demo"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["mode.demo"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["destination.dashboard"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["mode.empty"].exists)
    }
}
