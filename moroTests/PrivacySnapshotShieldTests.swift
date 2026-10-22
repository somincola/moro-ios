//
//  PrivacySnapshotShieldTests.swift
//  moroTests
//

import UIKit
import XCTest

@testable import moro

@MainActor
final class PrivacySnapshotShieldTests: XCTestCase {
    private let shield = PrivacySnapshotShield.shared

    private func makeWindow() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.isHidden = false
        return window
    }

    private func cover(in window: UIWindow) -> UIVisualEffectView? {
        window.viewWithTag(PrivacySnapshotShield.coverTag) as? UIVisualEffectView
    }

    func testCoverBlursTheWholeWindowAboveTheContent() throws {
        let window = makeWindow()
        shield.cover([window])

        let blur = try XCTUnwrap(cover(in: window))
        XCTAssertEqual(blur.frame, window.bounds, "laid out at once, before the snapshot")
        XCTAssertIdentical(window.subviews.last, blur, "drawn above every screen")
        XCTAssertNotNil(blur.effect as? UIBlurEffect)
        XCTAssertFalse(blur.isUserInteractionEnabled)
    }

    func testCoveringTwiceDoesNotStackBlurs() {
        let window = makeWindow()
        shield.cover([window])
        shield.cover([window])
        XCTAssertEqual(window.subviews.filter { $0.tag == PrivacySnapshotShield.coverTag }.count, 1)
    }

    func testUncoverRestoresTheContent() {
        let window = makeWindow()
        shield.cover([window])
        shield.uncover([window])
        XCTAssertNil(cover(in: window))
    }

    func testHiddenWindowsAreLeftAlone() {
        let window = makeWindow()
        window.isHidden = true
        shield.cover([window])
        XCTAssertNil(cover(in: window))
    }
}
