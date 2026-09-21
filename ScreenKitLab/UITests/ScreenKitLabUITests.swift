import XCTest

final class ScreenKitLabUITests: XCTestCase {
    @MainActor
    func testExternalScreenMacroCreatesCollectionScreen() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Examples"].tap()
        app.buttons["Macro"].tap()

        XCTAssertTrue(app.navigationBars["External #screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Rendered by ScreenKit macro"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Compiled in the consuming app target"].exists)
    }

    @MainActor
    func testContainersComposeNavigationPagesAndSplit() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Examples"].tap()
        app.buttons["Containers"].tap()
        XCTAssertTrue(app.staticTexts["Screens compose"].waitForExistence(timeout: 5))
        app.buttons["container.openDetail"].tap()
        XCTAssertTrue(app.navigationBars["Detail"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["container.openDetail"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Native navigation and tabs")
        app.tabBars.buttons["Pages"].tap()
        XCTAssertTrue(app.staticTexts["Page 1"].waitForExistence(timeout: 5))
        app.collectionViews.firstMatch.swipeLeft()
        XCTAssertTrue(app.staticTexts["Page 2"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Native pages swipe")
        app.collectionViews.firstMatch.swipeRight()
        XCTAssertTrue(app.staticTexts["Page 1"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Split"].tap()
        XCTAssertTrue(app.navigationBars["Secondary"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Adaptive split compact column")
        app.tabBars.buttons["Navigation"].tap()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Examples"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLegacyControllerOwnsUpdatesAndReordering() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Examples"].tap()
        app.buttons["Legacy"].tap()
        XCTAssertTrue(app.collectionViews["legacy.collection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["legacy.row.1"].exists || app.staticTexts["legacy.row.1"].exists)
        app.buttons["legacy.update"].tap()
        XCTAssertTrue(app.staticTexts["legacy.row.0"].label.contains("Update 1"))
        app.buttons["legacy.reverse"].tap()
        XCTAssertTrue(app.collectionViews["legacy.collection"].cells.element(boundBy: 0).staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Item 7 · Update 1")).firstMatch.exists)
        app.buttons["legacy.update"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Item 7 · Update 2")).firstMatch.exists)
        attachScreenshot(app, name: "Legacy controller owns mixed collection")
    }

    @MainActor
    func testDraftSurvivesMovingAcrossSections() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Examples"].tap()
        app.buttons["Sections"].tap()
        let collection = app.collectionViews["screen.collection"]
        XCTAssertTrue(collection.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Featured carousel"].exists)
        XCTAssertTrue(app.staticTexts["Catalog grid"].exists)
        attachScreenshot(app, name: "Carousel grid and list sections")
        let draft = app.textFields["draft.6"]
        for _ in 0..<4 {
            if draft.isHittable { break }
            collection.swipeUp()
        }
        XCTAssertTrue(draft.isHittable)
        draft.tap()
        draft.typeText("Move this draft")
        app.buttons["Density"].tap()
        app.buttons["Move draft"].tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, "Move this draft")
        app.buttons["Reorder"].tap()
        app.buttons["Move draft"].tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, "Move this draft")
        attachScreenshot(app, name: "Draft retained after section moves")
        app.buttons["Headers"].tap()
        let metadata = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "metadata 1")).firstMatch
        XCTAssertTrue(metadata.waitForExistence(timeout: 5))
        app.buttons["Changes"].tap()
        app.buttons["Burst updates"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "3 applied")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, "Move this draft")
        attachScreenshot(app, name: "Animated burst and supplementary refresh")
    }

    @MainActor
    func testMixedContentObservationAndDraftSurviveLayoutAndReorder() {
        checkMixedContent(explicitUpdates: false)
    }

    @MainActor
    func testExplicitUpdatesAndDraftSurviveLayoutAndReorder() {
        checkMixedContent(explicitUpdates: true)
    }

    @MainActor
    private func checkMixedContent(explicitUpdates: Bool) {
        let app = XCUIApplication()
        if explicitUpdates { app.launchArguments = ["--explicit-updates"] }
        app.launch()
        let draft = app.textFields["draft.2"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Content configuration"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "UIKit cell")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Existing UIView")).firstMatch.exists)
        attachScreenshot(app, name: "Mixed content list")
        let listWidth = app.collectionViews.cells.element(boundBy: 0).frame.width
        draft.tap()
        draft.typeText("Keep this draft")
        app.buttons["Update"].tap()
        let updated = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Item 0 · Update 1")).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, "Keep this draft")
        app.buttons["Layout"].tap()
        let grid = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.collectionViews.cells.element(boundBy: 0).frame.width < listWidth * 0.75
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [grid], timeout: 5), .completed, "Layout must actually switch to two columns")
        for id in 0..<4 {
            let content = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Item \(id) · Update 1")).firstMatch
            XCTAssertTrue(content.waitForExistence(timeout: 5), "Renderer \(id) must update its content")
        }
        attachScreenshot(app, name: "Mixed content expanded grid")
        app.buttons["Reverse"].tap()
        app.buttons["Restore"].tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, "Keep this draft")
        app.buttons["Update"].tap()
        for id in 0..<4 {
            let content = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Item \(id) · Update 2")).firstMatch
            XCTAssertTrue(content.waitForExistence(timeout: 5), "Renderer \(id) must keep tracking after reuse")
        }
        XCTAssertTrue(app.navigationBars["Mixed · 2"].exists)
        attachScreenshot(app, name: "Mixed content grid after updates and reorder")
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
