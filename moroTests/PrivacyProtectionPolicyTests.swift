//
//  PrivacyProtectionPolicyTests.swift
//  moroTests
//

import SwiftUI
import XCTest

@testable import moro

final class PrivacyProtectionPolicyTests: XCTestCase {
    func testPrivacyShieldIsFullyOpaque() {
        XCTAssertEqual(PrivacyProtectionPolicy.shieldBackgroundOpacity, 1)
    }

    func testActiveSceneKeepsContentVisible() {
        XCTAssertFalse(PrivacyProtectionPolicy.shouldObscureContent(for: .active))
    }

    func testInactiveSceneObscuresContentBeforeBackgrounding() {
        XCTAssertTrue(PrivacyProtectionPolicy.shouldObscureContent(for: .inactive))
    }

    func testBackgroundSceneKeepsContentObscured() {
        XCTAssertTrue(PrivacyProtectionPolicy.shouldObscureContent(for: .background))
    }
}
