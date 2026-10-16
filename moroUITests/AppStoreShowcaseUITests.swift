import XCTest

/// Captures the real screens behind the App Store showcase, with offline fixtures.
/// Opt-in: run with `TEST_RUNNER_CAPTURE_STORE_SHOWCASE=1` and, optionally,
/// `TEST_RUNNER_SHOWCASE_LOCALES=zh-Hans,en-US`.
@MainActor
final class AppStoreShowcaseUITests: XCTestCase {
    func testCaptureShowcase() throws {
        guard ProcessInfo.processInfo.environment["CAPTURE_STORE_SHOWCASE"] == "1" else {
            throw XCTSkip("Store showcase capture is opt-in.")
        }
        continueAfterFailure = true
        let locales = (ProcessInfo.processInfo.environment["SHOWCASE_LOCALES"] ?? "zh-Hans,en-US")
            .split(separator: ",").map(String.init)
        for locale in locales {
            for scheme in ["dark", "light"] {
                captureOnboarding(locale, scheme)
                captureLogin(locale, scheme)
            }
            captureHome(locale, "light")
            captureHome(locale, "dark")
            captureSwitcher(locale)
            captureScene(locale, "display", page: "display", theme: "purple")
            captureScene(locale, "editProfile", page: "edit-profile")
        }
    }

    // MARK: Scenes

    private func captureOnboarding(_ locale: String, _ scheme: String) {
        let app = launch(locale, scheme, arguments: ["UITEST_ONBOARDING_PREVIEW"],
                         environment: ["UITEST_ONBOARDING_VARIANT": "globe"])
        // Let the net settle and a few sparks run before gathering it.
        sleep(4)
        capture(app, locale, "onboarding-net-\(scheme)")
        app.tap()
        XCTAssertTrue(app.buttons["onboarding.start"].waitForExistence(timeout: 10))
        sleep(3)
        capture(app, locale, "onboarding-globe-\(scheme)")
        app.terminate()
    }

    private func captureLogin(_ locale: String, _ scheme: String) {
        let app = launch(locale, scheme, arguments: ["UITEST_ONBOARDING_PREVIEW"],
                         environment: ["UITEST_ONBOARDING_VARIANT": "login"])
        let field = app.textFields["login.domain"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        dismissKeyboardTip(app)
        field.typeText("m")
        sleep(1)
        capture(app, locale, "login-typing-\(scheme)")
        app.terminate()

        // The locked state, without a keyboard in the way.
        let locked = launch(locale, scheme, arguments: ["UITEST_ONBOARDING_PREVIEW"],
                            environment: ["UITEST_ONBOARDING_VARIANT": "login", "UITEST_LOGIN_DOMAIN": "mastodon.social"])
        XCTAssertTrue(locked.textFields["login.domain"].waitForExistence(timeout: 10))
        sleep(3)
        capture(locked, locale, "login-locked-\(scheme)")
        locked.terminate()
    }

    private func captureHome(_ locale: String, _ scheme: String) {
        let app = launchStore(locale, scheme)
        XCTAssertTrue(app.buttons["home.composeButton"].waitForExistence(timeout: 20))
        sleep(2)
        capture(app, locale, "home-\(scheme)")
        app.terminate()
    }

    private func captureSwitcher(_ locale: String) {
        let app = launchStore(locale, "light")
        XCTAssertTrue(app.buttons["home.composeButton"].waitForExistence(timeout: 20))
        sleep(2)
        let me = app.buttons["mainTab.me"]
        XCTAssertTrue(me.waitForExistence(timeout: 10))
        me.press(forDuration: 0.8)
        sleep(2)
        capture(app, locale, "switcher")
        app.terminate()
    }

    private func captureScene(_ locale: String, _ scene: String, page: String, theme: String? = nil) {
        var environment = ["STORE_SCENE": scene]
        if let theme { environment["STORE_THEME_COLOR"] = theme }
        let app = launchStore(locale, "light", environment: environment)
        sleep(4)
        capture(app, locale, page)
        app.terminate()
    }

    // MARK: Helpers

    private func launchStore(_ locale: String, _ scheme: String, environment: [String: String] = [:]) -> XCUIApplication {
        launch(locale, scheme, arguments: ["APP_STORE_SCREENSHOTS"],
               environment: environment.merging(["STORE_SHOWCASE": "1"]) { $1 })
    }

    private func launch(_ locale: String, _ scheme: String, arguments: [String],
                        environment: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-AppleLanguages", "(\(locale))",
                                           "-AppleLocale", locale.replacingOccurrences(of: "-", with: "_")]
        app.launchEnvironment = environment.merging(["UITEST_USE_FULL_APP": "1",
                                                     "UITEST_COLOR_SCHEME": scheme]) { $1 }
        app.launch()
        return app
    }

    private func dismissKeyboardTip(_ app: XCUIApplication) {
        let welcome = app.buttons["Continue"]
        if welcome.waitForExistence(timeout: 1.5) { welcome.tap() }
    }

    private func capture(_ app: XCUIApplication, _ locale: String, _ page: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "showcase__\(locale)__\(page)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
