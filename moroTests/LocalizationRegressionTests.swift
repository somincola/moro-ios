import XCTest

@testable import moro

final class LocalizationRegressionTests: XCTestCase {
    func testServerAndNetworkErrorsUseLocalizedCopyWithoutLosingServerDetails() throws {
        let data = Data(#"{"error":"validation_failed","error_description":"Server detail in English"}"#.utf8)
        var server = try JSONDecoder().decode(MastodonServerError.self, from: data)
        XCTAssertEqual(server.serverDescription, "Server detail in English")
        for code in [400, 401, 403, 404, 422, 429, 500] {
            server.httpCode = code
            let direct: Error = server
            let wrapped: Error = APIError.serverError(server)
            XCTAssertEqual(direct.localizedDescription, MoroL10n.AppError.http(code))
            XCTAssertEqual(wrapped.localizedDescription, MoroL10n.AppError.http(code))
            XCTAssertEqual(server.failureReason, "validation_failed")
        }
        XCTAssertEqual(APIError.underlying(URLError(.timedOut)).localizedDescription, MoroL10n.AppError.timeout)
        XCTAssertEqual(APIError.underlying(URLError(.notConnectedToInternet)).localizedDescription, MoroL10n.AppError.networkUnavailable)
        XCTAssertEqual(APIError.underlying(NSError(domain: "test", code: 1)).localizedDescription, MoroL10n.AppError.unknown)
        let keychain: Error = KeychainError.invalidData
        XCTAssertEqual(keychain.localizedDescription, MoroL10n.AppError.decoding)
    }

    func testExtensionAndIntentResourcesCoverAllAppLanguages() throws {
        let plugins = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        let widget = try XCTUnwrap(Bundle(url: plugins.appendingPathComponent("moroWidgets.appex")))
        let share = try XCTUnwrap(Bundle(url: plugins.appendingPathComponent("moroShareExtension.appex")))
        for (bundle, table, keys) in [
            (widget, "Localizable", ["widget.action.search", "widget.profile.followers", "widget.comfort.message"]),
            (share, "Localizable", ["share.state.loading", "share.state.opening", "share.action.open", "share.action.retry",
                "share.error.openFailed", "share.error.tooManyImages", "share.error.unreadableImage",
                "share.error.videoMustBeAlone", "share.error.unreadableVideo"]),
            (widget, "AppIntents", ["Open Moro", "Destination", "Profile"]),
            (Bundle.main, "AppIntents", ["Open Moro", "Destination", "Profile"]),
        ] {
            for locale in ["de", "en", "es", "fr", "it", "ja", "pt-PT", "zh-Hans", "zh-Hant"] {
                let url = try XCTUnwrap(bundle.url(forResource: table, withExtension: "strings", subdirectory: nil, localization: locale), "\(table) [\(locale)]")
                XCTAssertTrue(url.path.contains("/\(locale).lproj/"), url.path)
                let strings = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
                for key in keys { XCTAssertFalse(try XCTUnwrap(strings[key], "\(table): \(key) [\(locale)]").isEmpty) }
                if locale.hasPrefix("zh") && table == "Localizable" && bundle == share {
                    XCTAssertFalse(try XCTUnwrap(strings["share.error.openFailed"]).contains("Compose"))
                }
            }
        }
    }
}
