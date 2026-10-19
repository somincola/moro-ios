import XCTest

/// The first-launch globe and the login page under it.
@MainActor
final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ variant: String, environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_ONBOARDING_PREVIEW", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment = environment.merging([
            "UITEST_USE_FULL_APP": "1",
            "UITEST_ONBOARDING_VARIANT": variant,
            "UITEST_COLOR_SCHEME": "dark",
        ]) { $1 }
        app.launch(isolatedFor: self)
        return app
    }

    func testOneTapGathersTheGlobeAndGetStartedFinishes() {
        let app = launch("globe")
        let start = app.buttons["onboarding.start"]
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 10))
        XCTAssertFalse(start.exists, "Get started waits for the globe")

        app.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10), "Get started fades in after the wordmark")
        XCTAssertFalse(app.buttons["onboarding.skip"].exists, "Skipping is moot once the globe has gathered")
        sleep(2) // the button fades in
        start.tap()
        XCTAssertTrue(app.buttons["onboarding.replay"].waitForExistence(timeout: 6))
    }

    func testSkipGoesStraightToLogin() {
        let app = launch("globe")
        let skip = app.buttons["onboarding.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        skip.tap()
        XCTAssertTrue(app.buttons["onboarding.replay"].waitForExistence(timeout: 6))
    }

    func testLoginStartsEmptyAndEnablesOnceADomainIsTyped() {
        let app = launch("login")
        let field = app.textFields["login.domain"]
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String ?? "", field.placeholderValue ?? "", "No server is prefilled")
        XCTAssertFalse(submit.isEnabled)

        field.tap()
        field.typeText("mastodon.social")
        XCTAssertTrue(submit.isEnabled)

        app.buttons["login.clear"].tap()
        XCTAssertFalse(submit.isEnabled)
    }
}
