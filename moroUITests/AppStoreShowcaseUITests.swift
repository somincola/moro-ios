import XCTest

/// Captures the real screens behind the App Store showcase, with offline fixtures.
/// Opt-in: run with `TEST_RUNNER_CAPTURE_STORE_SHOWCASE=1` and, optionally,
/// `TEST_RUNNER_SHOWCASE_LOCALES=zh-Hans,en-US` and `TEST_RUNNER_SHOWCASE_PAGES=compose,inbox`
/// (groups: onboarding, login, home, thread, explore, inbox, profile, compose, switcher,
/// display, edit-profile; default all). Captures default to all nine app languages;
/// Arabic promotional assets reuse the English captures.
@MainActor
final class AppStoreShowcaseUITests: XCTestCase {
    func testCaptureShowcase() throws {
        guard ProcessInfo.processInfo.environment["CAPTURE_STORE_SHOWCASE"] == "1" else {
            throw XCTSkip("Store showcase capture is opt-in.")
        }
        continueAfterFailure = true
        let locales = (ProcessInfo.processInfo.environment["SHOWCASE_LOCALES"]
            ?? "zh-Hans,en-US,de-DE,es-ES,fr-FR,it,ja,pt-PT,zh-Hant")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let pages = ProcessInfo.processInfo.environment["SHOWCASE_PAGES"].flatMap { list in
            list.isEmpty ? nil : Set(list.split(separator: ",").map(String.init))
        }
        func wants(_ page: String) -> Bool { pages?.contains(page) ?? true }
        for locale in locales {
            for scheme in ["dark", "light"] {
                if wants("onboarding") { captureOnboarding(locale, scheme) }
                if wants("login") { captureLogin(locale, scheme) }
            }
            if wants("home") {
                captureHome(locale, "light")
                captureHome(locale, "dark")
            }
            if wants("thread") { captureScene(locale, "main", page: "thread", environment: ["STORE_THREAD": "0"]) }
            if wants("explore") { captureScene(locale, "main", page: "explore", environment: ["STORE_TAB": "explore"]) }
            if wants("inbox") { captureScene(locale, "main", page: "inbox", environment: ["STORE_TAB": "inbox"]) }
            if wants("profile") { captureScene(locale, "main", page: "profile", environment: ["STORE_TAB": "me"]) }
            if wants("compose") { captureCompose(locale) }
            if wants("switcher") { captureSwitcher(locale) }
            if wants("display") { captureScene(locale, "display", page: "display", theme: "purple") }
            if wants("edit-profile") { captureScene(locale, "editProfile", page: "edit-profile") }
        }
    }

    // MARK: Scenes

    private func captureOnboarding(_ locale: String, _ scheme: String) {
        let app = launch(locale, scheme, arguments: ["UITEST_ONBOARDING_PREVIEW"],
                         environment: ["UITEST_ONBOARDING_VARIANT": "globe"])
        // The store shows the gathered globe with the title, not the opening net.
        sleep(2)
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

    /// A new post with a poll, typed into the real composer.
    private func captureCompose(_ locale: String) {
        let copy = composeCopy(for: locale)
        let app = launchStore(locale, "light")
        let compose = app.buttons["home.composeButton"]
        XCTAssertTrue(compose.waitForExistence(timeout: 20))
        compose.tap()
        let input = app.textViews["compose.textInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        dismissKeyboardTip(app)
        input.typeText(copy.text)
        let poll = app.buttons["compose.pollToggle"]
        XCTAssertTrue(poll.waitForExistence(timeout: 5))
        poll.tap()
        let fields = app.scrollViews["compose.contentScroll"].textFields
        XCTAssertTrue(fields.firstMatch.waitForExistence(timeout: 5), "poll options: \(app.debugDescription)")
        for (index, option) in copy.options.enumerated() {
            if index >= fields.count { app.buttons[copy.addOptionTitle].firstMatch.tap() }
            let field = fields.element(boundBy: index)
            guard field.waitForExistence(timeout: 5) else { break }
            field.tap()
            field.typeText(option)
        }
        // Return closes the keyboard, so the whole poll (length, multiple choice) shows.
        app.typeText("\n")
        sleep(2)
        capture(app, locale, "compose")
        app.terminate()
    }

    private func captureScene(_ locale: String, _ scene: String, page: String, theme: String? = nil,
                              environment extra: [String: String] = [:]) {
        var environment = extra.merging(["STORE_SCENE": scene]) { $1 }
        if let theme { environment["STORE_THEME_COLOR"] = theme }
        let app = launchStore(locale, "light", environment: environment)
        sleep(4)
        capture(app, locale, page)
        app.terminate()
    }

    // MARK: Helpers

    private struct ComposeCopy {
        let text: String
        let options: [String]
        let addOptionTitle: String
    }

    private func composeCopy(for locale: String) -> ComposeCopy {
        // Button titles match compose.poll.addOption in Moro.xcstrings.
        switch appLanguage(for: locale) {
        case "zh-Hans":
            return ComposeCopy(text: "这个周末想去海边走走，你们更想做哪件事？🌊",
                options: ["看日出", "海边咖啡", "拍晚霞"], addOptionTitle: "添加选项")
        case "zh-Hant":
            return ComposeCopy(text: "這個週末想去海邊走走，你們比較想做哪件事？🌊",
                options: ["看日出", "海邊喝咖啡", "拍晚霞"], addOptionTitle: "新增選項")
        case "de":
            return ComposeCopy(text: "Wie wäre es mit einem Wochenende am Meer? Was würdet ihr am liebsten machen? 🌊",
                options: ["Sonnenaufgang erleben", "Kaffee am Meer", "Abendrot fotografieren"], addOptionTitle: "Option hinzufügen")
        case "es":
            return ComposeCopy(text: "Estoy pensando en pasar el fin de semana junto al mar. ¿Qué plan os apetece más? 🌊",
                options: ["Paseo al amanecer", "Café junto al mar", "Fotos del atardecer"], addOptionTitle: "Añadir opción")
        case "fr":
            return ComposeCopy(text: "Et si on passait le week-end au bord de la mer ? Vous choisiriez quoi ? 🌊",
                options: ["Balade à l’aube", "Café face à la mer", "Photos du couchant"], addOptionTitle: "Ajouter une option")
        case "it":
            return ComposeCopy(text: "Pensavo a un fine settimana al mare. Voi cosa preferireste fare? 🌊",
                options: ["Passeggiata all’alba", "Caffè sul mare", "Foto al tramonto"], addOptionTitle: "Aggiungi opzione")
        case "ja":
            return ComposeCopy(text: "週末は海辺で過ごしたいな。みんななら何をしたい？🌊",
                options: ["朝日を見に散歩", "海辺のカフェ", "夕焼けを撮る"], addOptionTitle: "選択肢を追加")
        case "pt-PT":
            return ComposeCopy(text: "Estava a pensar passar o fim de semana à beira-mar. O que vos apetecia mais? 🌊",
                options: ["Passeio ao nascer do sol", "Café à beira-mar", "Fotografar o pôr do sol"], addOptionTitle: "Adicionar opção")
        default:
            return ComposeCopy(text: "Thinking about a weekend by the sea. Which would you pick? 🌊",
                options: ["Sunrise walk", "Seaside café", "Sunset photos"], addOptionTitle: "Add option")
        }
    }

    private func appLanguage(for locale: String) -> String {
        let languages = ["de-DE": "de", "es-ES": "es", "fr-FR": "fr", "it": "it", "ja": "ja",
                         "pt-PT": "pt-PT", "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant", "ar-SA": "en"]
        return languages[locale] ?? locale
    }

    private func launchStore(_ locale: String, _ scheme: String, environment: [String: String] = [:]) -> XCUIApplication {
        launch(locale, scheme, arguments: ["APP_STORE_SCREENSHOTS"],
               environment: environment.merging(["STORE_SHOWCASE": "1"]) { $1 })
    }

    private func launch(_ locale: String, _ scheme: String, arguments: [String],
                        environment: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        let captureLocale = locale == "ar-SA" ? "en-US" : locale
        app.launchArguments = arguments + ["-AppleLanguages", "(\(appLanguage(for: locale)))",
                                           "-AppleLocale", captureLocale.replacingOccurrences(of: "-", with: "_")]
        app.launchEnvironment = environment.merging(["UITEST_USE_FULL_APP": "1",
                                                     "UITEST_COLOR_SCHEME": scheme]) { $1 }
        app.launch(isolatedFor: self)
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
