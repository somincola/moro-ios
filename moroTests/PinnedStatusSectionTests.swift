//
//  PinnedStatusSectionTests.swift
//  moroTests
//

import XCTest

@testable import moro

final class PinnedStatusSectionTests: XCTestCase {
    func testDeduplicationPreservesFirstOccurrenceOrder() {
        let result = PinnedStatusSectionState.deduplicated(
            ["a", "b", "a", "c", "b"],
            id: { $0 }
        )

        XCTAssertEqual(result, ["a", "b", "c"])
    }

    func testCollapsedSectionShowsOnlyFirstPinnedStatus() {
        let result = PinnedStatusSectionState.visibleStatuses(
            ["a", "b", "c"],
            showsAll: false
        )

        XCTAssertEqual(result, ["a"])
    }

    func testExpandedSectionShowsEveryPinnedStatusInOrder() {
        let result = PinnedStatusSectionState.visibleStatuses(
            ["a", "b", "c"],
            showsAll: true
        )

        XCTAssertEqual(result, ["a", "b", "c"])
    }

    func testCollapsedSectionReportsRemainingPinnedStatusCount() {
        XCTAssertEqual(
            PinnedStatusSectionState.hiddenCount(totalCount: 3, showsAll: false),
            2
        )
        XCTAssertEqual(
            PinnedStatusSectionState.hiddenCount(totalCount: 1, showsAll: false),
            0
        )
    }

    func testExpandedSectionHasNoHiddenPinnedStatuses() {
        XCTAssertEqual(
            PinnedStatusSectionState.hiddenCount(totalCount: 3, showsAll: true),
            0
        )
    }
}
