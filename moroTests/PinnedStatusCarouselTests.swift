//
//  PinnedStatusCarouselTests.swift
//  moroTests
//

import XCTest

@testable import moro

final class PinnedStatusCarouselTests: XCTestCase {
    func testDeduplicationPreservesFirstOccurrenceOrder() {
        let result = PinnedStatusCarouselState.deduplicated(
            ["a", "b", "a", "c", "b"],
            id: { $0 }
        )

        XCTAssertEqual(result, ["a", "b", "c"])
    }

    func testSelectionSurvivesReordering() {
        let result = PinnedStatusCarouselState.reconciledSelection(
            currentID: "b",
            previousIDs: ["a", "b", "c"],
            newIDs: ["c", "b", "a"]
        )

        XCTAssertEqual(result, "b")
    }

    func testRemovingSelectedPageUsesItsPreviousSlot() {
        let result = PinnedStatusCarouselState.reconciledSelection(
            currentID: "b",
            previousIDs: ["a", "b", "c"],
            newIDs: ["a", "c"]
        )

        XCTAssertEqual(result, "c")
    }

    func testRemovingLastSelectedPageClampsToNewLastPage() {
        let result = PinnedStatusCarouselState.reconciledSelection(
            currentID: "c",
            previousIDs: ["a", "b", "c"],
            newIDs: ["a", "b"]
        )

        XCTAssertEqual(result, "b")
    }

    func testCompleteReplacementStartsAtFirstPage() {
        let result = PinnedStatusCarouselState.reconciledSelection(
            currentID: "b",
            previousIDs: ["a", "b"],
            newIDs: ["x", "y"]
        )

        XCTAssertEqual(result, "x")
    }

    func testEmptyStatusesClearSelection() {
        let result = PinnedStatusCarouselState.reconciledSelection(
            currentID: "a",
            previousIDs: ["a"],
            newIDs: []
        )

        XCTAssertNil(result)
    }

    func testMissingSelectionStartsAtFirstPage() {
        let result = PinnedStatusCarouselState.reconciledSelection(
            currentID: nil,
            previousIDs: [],
            newIDs: ["a", "b"]
        )

        XCTAssertEqual(result, "a")
    }

    func testUniformHeightDoesNotClipTallTimelineCard() {
        let result = PinnedStatusCarouselState.uniformCardHeight(
            measuredHeights: [240, 612],
            fallback: 220,
            minimum: 180
        )

        XCTAssertEqual(result, 612)
    }
}
