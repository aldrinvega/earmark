import XCTest

/// Task 8 UI smoke: Diagnostics → "Align test chapter" opens in the simulator. (The engines need a real iPhone, so
/// the screen shows either the Run button or a clear setup message — never a hang.)
final class DiagnosticsSmokeTests: XCTestCase {
    @MainActor
    func testAlignTestScreenOpens() {
        let app = XCUIApplication()
        app.launch()
        let diagnostics = app.buttons["open-diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 10))
        diagnostics.tap()

        let alignTest = app.buttons["open-align-test"]
        XCTAssertTrue(alignTest.waitForExistence(timeout: 10))
        alignTest.tap()

        XCTAssertTrue(app.navigationBars["Align test chapter"].waitForExistence(timeout: 10))
        let runOrMessage = app.buttons["align-run"].waitForExistence(timeout: 5)
            || app.staticTexts["align-setup-error"].exists
            || app.otherElements["align-setup-error"].exists
            || app.cells.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'speech engine'")).count > 0
        XCTAssertTrue(runOrMessage, "Expected the Run button or a setup message")
    }
}
