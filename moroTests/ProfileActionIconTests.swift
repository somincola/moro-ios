//
//  ProfileActionIconTests.swift
//  moroTests
//

import UIKit
import XCTest

@testable import moro

final class ProfileActionIconTests: XCTestCase {
    func testNotificationToggleShowsTheCurrentStateAsABell() {
        // Off: a plain bell. On: a ringing bell. Neither reads as follow/unfollow, and
        // neither is the slashed bell that already means "mute".
        XCTAssertEqual(NotificationToggleButton.systemImage(isNotifying: false), "bell")
        XCTAssertEqual(
            NotificationToggleButton.systemImage(isNotifying: true),
            "bell.and.waves.left.and.right.fill"
        )
    }

    func testNotificationToggleSymbolsExistInUIKit() {
        for isNotifying in [false, true] {
            let name = NotificationToggleButton.systemImage(isNotifying: isNotifying)
            XCTAssertNotNil(UIImage(systemName: name), name)
        }
    }
}
