//
//  MoroUIKitThemePaletteTests.swift
//  moroTests
//


import SwiftUI
import UIKit
import XCTest

@testable import moro

#if os(iOS)
    @MainActor
    final class MoroUIKitThemePaletteTests: XCTestCase {
        func testPaletteProjectsSemanticThemeColors() {
            let theme = MoroTheme(colorScheme: .light)
            let palette = theme.uiKitPalette

            XCTAssertTrue(palette.surfaceBase.isEqual(UIColor(theme.colors.surfaceBase)))
            XCTAssertTrue(palette.canvasBackground.isEqual(UIColor(theme.colors.surfaceBase)))
            XCTAssertTrue(palette.divider.isEqual(UIColor(theme.colors.divider)))
            XCTAssertEqual(palette.interfaceStyle, .light)
            XCTAssertTrue(palette.matches(theme))
        }

        func testPaletteReflectsDarkAppearance() {
            let dark = MoroTheme(colorScheme: .dark).uiKitPalette
            XCTAssertEqual(dark.interfaceStyle, .dark)
            XCTAssertFalse(dark.matches(MoroTheme(colorScheme: .light)))
        }

        func testUIKitFontUsesTheSameDynamicTypeSizeAsSwiftUITheme() {
            let regular = MoroTheme(dynamicTypeSize: .large).uiKitPalette
            let accessibleTheme = MoroTheme(dynamicTypeSize: .accessibility5)
            let accessible = accessibleTheme.uiKitPalette
            XCTAssertGreaterThan(accessible.font(forTextStyle: .body).pointSize, regular.font(forTextStyle: .body).pointSize)
            XCTAssertFalse(regular.matches(accessibleTheme))
            XCTAssertEqual(
                accessible.font(forTextStyle: .body).pointSize,
                UIFont.preferredFont(forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)).pointSize
            )
        }
    }
#endif
