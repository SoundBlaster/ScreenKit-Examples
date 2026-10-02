import XCTest

final class LabTelemetryUITests: XCTestCase {
    func testOriginalMixedScreenStillUpdatesInTelemetryBuild() {
        let app = XCUIApplication()
        // CI need not have a Collector. Actual network delivery has a separate gate.
        app.launchArguments = ["--telemetry-off", "--explicit-updates"]
        app.launch()
        XCTAssertTrue(app.buttons["OTLP off"].waitForExistence(timeout: 10))
        let firstRowText = app.cells["row.0"].staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Item 0 · Update 0")).firstMatch
        XCTAssertTrue(firstRowText.exists)
        XCTAssertTrue(app.staticTexts["Content configuration"].exists)
        XCTAssertTrue(app.staticTexts["SwiftUI island"].exists)
        app.buttons["Actions"].tap()
        XCTAssertTrue(app.buttons["Compare"].waitForExistence(timeout: 5))
        app.buttons["Update"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Item 0 · Update 1")).firstMatch.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Telemetry Lab shares the real mixed-content screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testInvalidCollectorURLHasVisibleDiagnostic() {
        let app = XCUIApplication()
        app.launchEnvironment["SCREENKIT_OTLP_ENDPOINT"] = "not-a-url"
        app.launch()
        XCTAssertTrue(app.staticTexts["Invalid endpoint"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Compare"].exists)
    }
}
