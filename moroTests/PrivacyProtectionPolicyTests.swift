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

    func testOwnSystemPromptDoesNotRaiseTheShield() {
        XCTAssertFalse(PrivacyProtectionPolicy.shouldObscureContent(for: .inactive, isPresentingSystemPrompt: true))
        XCTAssertFalse(PrivacyProtectionPolicy.shouldObscureContent(for: .active, isPresentingSystemPrompt: true))
    }

    func testLeavingTheAppFromASystemPromptStillObscuresTheSnapshot() {
        XCTAssertTrue(PrivacyProtectionPolicy.shouldObscureContent(for: .background, isPresentingSystemPrompt: true))
    }

    @MainActor
    func testPromptExemptionEndsShortlyAfterThePrompt() async throws {
        let center = PrivacyProtectionCenter.shared
        let seenDuringPrompt = await center.whilePresentingSystemPrompt { center.isPresentingSystemPrompt }
        XCTAssertTrue(seenDuringPrompt)
        XCTAssertTrue(center.isPresentingSystemPrompt, "stays exempt while the scene settles back to active")
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertFalse(center.isPresentingSystemPrompt)
    }
}
