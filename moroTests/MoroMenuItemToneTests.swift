//
//  MoroMenuItemToneTests.swift
//  moroTests
//

import XCTest
import SwiftUI
import UIKit

@testable import moro

final class MoroMenuItemToneTests: XCTestCase {
    func testDestructiveToneUsesNativeDestructiveButtonRole() {
        XCTAssertEqual(MoroMenuItemTone.destructive.buttonRole, .destructive)
        XCTAssertNil(MoroMenuItemTone.standard.buttonRole)
    }

    func testDestructiveToneUsesAdaptiveSystemRedInLightAndDarkMode() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let actual = MoroMenuItemTone.destructive.uiColor.resolvedColor(with: traits)
            let expected = UIColor.systemRed.resolvedColor(with: traits)

            XCTAssertEqual(actual, expected)
        }
    }
}
