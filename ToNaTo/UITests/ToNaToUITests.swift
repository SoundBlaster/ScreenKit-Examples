import XCTest

@MainActor
final class ToNaToUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--compare"]
    }

    func testEditSaveHistoryAndBackRetainsDraft() {
        app.launch()
        let price = app.textFields["Price for Product 1"]
        XCTAssertTrue(price.waitForExistence(timeout: 10))
        price.tap()
        price.typeText("4.51")
        let quantity = app.textFields["Weight for Product 1"]
        quantity.tap()
        quantity.typeText("500")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Product 1 ($9.02/kg)")).firstMatch.waitForExistence(timeout: 5))
        app.navigationBars["History"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(price.waitForExistence(timeout: 5))
        XCTAssertEqual(price.value as? String, "4.51")
        XCTAssertEqual(quantity.value as? String, "500")
        app.navigationBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Product 1 ($9.02/kg)")).firstMatch.waitForExistence(timeout: 5))
        attachScreenshot("Saved comparison history")
    }

    func testTypingContinuesAcrossRefreshAndSort() {
        app.launch()
        let price = app.textFields["Price for Product 1"]
        XCTAssertTrue(price.waitForExistence(timeout: 10))
        price.tap()
        price.typeText("12")
        // A sort selection triggers a snapshot while the price field is first responder.
        app.segmentedControls["compare.sort"].buttons["Price"].tap()
        app.typeText(".34")
        XCTAssertEqual(price.value as? String, "12.34")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.toolbars.buttons["Done"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.swipeUp()
        let add = app.buttons["compare.addProduct.button"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        app.swipeUp()
        XCTAssertTrue(app.textFields["Price for Product 3"].waitForExistence(timeout: 5))
        attachScreenshot("Compare with added product")
    }

    func testRootMenuDestinationsAndSplit() {
        app.launchArguments = ["--uitesting"]
        app.launch()
        if app.windows.firstMatch.frame.width > 700 {
            showMenu()
            let menu = app.buttons["menu.About"]
            let price = app.textFields["Price for Product 1"]
            XCTAssertTrue(price.waitForExistence(timeout: 5))
            XCTAssertTrue(menu.isHittable)
            XCTAssertTrue(price.isHittable)
            XCTAssertLessThan(menu.frame.maxX, price.frame.minX)
            attachScreenshot("Expanded iPad comparison")
        }
        for (route, identifier) in [
            ("About", "about.title"),
            ("Detail", "detail.title"),
            ("History", "history.empty"),
            ("Onboarding", "onboarding.page.0.title"),
        ] {
            showMenu()
            app.buttons["menu.\(route)"].tap()
            XCTAssertTrue(app.staticTexts[identifier].waitForExistence(timeout: 5))
            if route == "Onboarding" {
                let firstPageTitle = app.staticTexts["onboarding.page.0.title"]
                firstPageTitle.swipeLeft()
                XCTAssertTrue(app.staticTexts["onboarding.page.1.title"].waitForExistence(timeout: 5))
                app.staticTexts["onboarding.page.1.title"].swipeRight()
                XCTAssertTrue(firstPageTitle.waitForExistence(timeout: 5))
            }
        }
        showMenu()
        app.buttons["menu.Settings"].tap()
        XCTAssertTrue(app.segmentedControls["settings.currency.segmentedControl"].waitForExistence(timeout: 5))
        attachScreenshot("Native root navigation")
    }

    private func showMenu() {
        let about = app.buttons["menu.About"]
        if !about.isHittable {
            let sidebar = app.navigationBars.buttons["ToNaTo"]
            if sidebar.waitForExistence(timeout: 3) { sidebar.tap() }
            else { app.navigationBars.buttons.element(boundBy: 0).tap() }
        }
        XCTAssertTrue(about.waitForExistence(timeout: 5))
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
