import XCTest

/// UI smoke test: the app launches and shows its name (Task 2). Becomes the stub-server happy path in app-shell.
final class LaunchSmokeTests: XCTestCase {
    @MainActor
    func testLaunchShowsAppName() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["launch-title"].waitForExistence(timeout: 10))
    }
}
