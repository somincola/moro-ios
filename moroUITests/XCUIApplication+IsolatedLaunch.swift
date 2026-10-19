import XCTest

/// One ID per test-bundle run, so a test re-run later still starts from fresh settings.
private let uiTestRunID = UUID().uuidString

extension XCUIApplication {
    /// Launches with the app's settings starting from their defaults for this test.
    ///
    /// The app resets its UserDefaults whenever the session ID differs from the previous
    /// launch's (see `UITestDefaultsIsolation`). The ID is per test method instance, so
    /// relaunching inside one test keeps what that test saved, while the next test never
    /// sees settings an earlier test changed and failed to restore.
    @MainActor func launch(isolatedFor testCase: XCTestCase) {
        let instance = UInt(bitPattern: ObjectIdentifier(testCase).hashValue)
        launchEnvironment["UITEST_DEFAULTS_SESSION"] = "\(uiTestRunID)|\(testCase.name)|\(instance)"
        launch()
    }
}
