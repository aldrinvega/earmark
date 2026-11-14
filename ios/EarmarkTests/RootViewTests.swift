import Testing
@testable import Earmark

/// Placeholder app test so the test host is wired up from the start (Task 2). Real app-level tests come with app-shell.
@Suite struct RootViewTests {
    @Test func showsTheAppName() {
        #expect(RootView.title == "Earmark")
        #expect(!RootView.subtitle.isEmpty)
    }
}
