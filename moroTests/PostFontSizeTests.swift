import SwiftUI
import UIKit
import XCTest

@testable import moro

@MainActor
final class PostFontSizeTests: XCTestCase {
    func testRetiredGlobalPreferenceIsRemovedWithoutChangingPostPreference() throws {
        let suite = "PostFontSizeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        for legacyValue in ["extraSmall", "small", "standard", "large", "extraLarge"] {
            defaults.set(legacyValue, forKey: "typographyFontScale")
            XCTAssertEqual(AppSettings(userDefaults: defaults).postFontSize, .standard)
            XCTAssertNil(defaults.object(forKey: "typographyFontScale"))
        }

        defaults.set("extraLarge", forKey: "typographyFontScale")
        defaults.set(20, forKey: "postFontSize")
        XCTAssertEqual(AppSettings(userDefaults: defaults).postFontSize, .extraLarge)
        XCTAssertEqual(defaults.integer(forKey: "postFontSize"), 20)
        XCTAssertNil(defaults.object(forKey: "typographyFontScale"))
    }

    func testEachPostPreferenceSurvivesReloadAndInvalidValuesFallBack() throws {
        let suite = "PostFontSizeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(userDefaults: defaults)
        for size in MoroPostFontSize.allCases {
            settings.postFontSize = size
            XCTAssertEqual(AppSettings(userDefaults: defaults).postFontSize, size)
        }
        for invalid in [-1, 0, 10, 17, 22, 100] {
            defaults.set(invalid, forKey: "postFontSize")
            XCTAssertEqual(AppSettings(userDefaults: defaults).postFontSize, .standard)
        }
        defaults.set("unknown", forKey: "postFontSize")
        XCTAssertEqual(AppSettings(userDefaults: defaults).postFontSize, .standard)
    }

    func testFocusedPostUsesTwoPointDifferenceBeforeDynamicType() {
        for size in MoroPostFontSize.allCases {
            let theme = MoroTheme(postFontSize: size)
            XCTAssertEqual(theme.postUIFont().pointSize, CGFloat(size.rawValue), accuracy: 0.01)
            XCTAssertEqual(theme.postUIFont(sizeAdjustment: 2).pointSize, CGFloat(size.rawValue + 2), accuracy: 0.01)

            let accessible = MoroTheme(postFontSize: size, dynamicTypeSize: .accessibility5)
            let expected = UIFontMetrics(forTextStyle: .body).scaledFont(
                for: .systemFont(ofSize: CGFloat(size.rawValue + 2)),
                compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
            )
            XCTAssertEqual(accessible.postUIFont(sizeAdjustment: 2).pointSize, expected.pointSize, accuracy: 0.01)
            XCTAssertGreaterThan(accessible.postUIFont().pointSize, theme.postUIFont().pointSize)
        }
    }

    func testReadingPreferenceDoesNotChangeInterfaceFontSizes() {
        let small = MoroTheme(postFontSize: .small).uiKitPalette
        let largeTheme = MoroTheme(postFontSize: .extraLarge)
        XCTAssertFalse(small.matches(largeTheme))
        for style in [UIFont.TextStyle.body, .headline, .caption1] {
            XCTAssertEqual(small.font(forTextStyle: style).pointSize, largeTheme.uiKitPalette.font(forTextStyle: style).pointSize)
        }
    }

    func testPreviewCanUseADraftSizeWithoutChangingTheTheme() {
        let theme = MoroTheme(postFontSize: .standard)
        XCTAssertEqual(theme.postUIFont(for: .extraLarge).pointSize, 20, accuracy: 0.01)
        XCTAssertEqual(theme.postUIFont().pointSize, 16, accuracy: 0.01)
        let accessible = MoroTheme(postFontSize: .standard, dynamicTypeSize: .accessibility5)
        XCTAssertEqual(
            accessible.postUIFont(for: .extraLarge).pointSize,
            MoroTheme(postFontSize: .extraLarge, dynamicTypeSize: .accessibility5).postUIFont().pointSize,
            accuracy: 0.01
        )
    }
}
