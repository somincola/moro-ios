import XCTest

@testable import moro

@MainActor
final class AccountSwitcherLayoutTests: XCTestCase {
    private let safeArea = CGRect(x: 0, y: 40, width: 400, height: 730)
    private let bottomBar = CGRect(x: 0, y: 730, width: 400, height: 60)

    func testCenterTabMirrorsItsNeighborsInRTLAndKeepsTheSameOrigin() {
        let me = CGPoint(x: 200, y: 750)
        let ltr = AccountSwitcherLayout(source: me, bar: bottomBar, column: nil, safeArea: safeArea,
                                        count: 4, rightToLeft: false)
        let rtl = AccountSwitcherLayout(source: me, bar: bottomBar, column: nil, safeArea: safeArea,
                                        count: 4, rightToLeft: true)
        XCTAssertEqual(ltr.source, me)
        XCTAssertEqual(rtl.source, me)
        XCTAssertEqual(ltr.slots, [3, 1, 0, 2])
        XCTAssertEqual(rtl.slots, Array(ltr.slots.reversed()))
        XCTAssertEqual(ltr.frame.minX, safeArea.maxX - rtl.frame.maxX)
    }

    func testTopBarAndMirroredSidebarsOpenTowardContent() {
        let topBar = CGRect(x: 0, y: 40, width: 400, height: 55)
        let top = AccountSwitcherLayout(source: CGPoint(x: 352, y: 60), bar: topBar, column: nil,
                                        safeArea: safeArea, count: 4, rightToLeft: false)
        XCTAssertEqual(top.placement, .belowTabBar)
        XCTAssertGreaterThan(top.frame.minY, topBar.maxY)
        for left in [true, false] {
            let rail = CGRect(x: left ? 0 : 344, y: 120, width: 56, height: 400)
            let me = CGPoint(x: rail.midX, y: 260)
            let layout = AccountSwitcherLayout(source: me, bar: .zero, column: rail, safeArea: safeArea,
                                               count: 4, rightToLeft: !left)
            XCTAssertEqual(layout.frame.midY, me.y)
            XCTAssertEqual(left ? layout.slots.first : layout.slots.last, 0)
            XCTAssertTrue(left ? layout.frame.minX > rail.maxX : layout.frame.maxX < rail.minX)
        }
    }

    func testOverflowKeepsCurrentAccountInTheInitialViewportAndEveryEntryReachable() {
        for x in [CGFloat(40), 200, 360] {
            let layout = AccountSwitcherLayout(source: CGPoint(x: x, y: 750), bar: bottomBar, column: nil,
                                               safeArea: safeArea, count: 14, rightToLeft: false)
            XCTAssertTrue(layout.scrolls)
            XCTAssertTrue(safeArea.contains(layout.frame))
            XCTAssertEqual(layout.slots.sorted(), Array(0..<14))
            let visible = layout.opensRight ? layout.slots.prefix(6) : layout.slots.suffix(6)
            XCTAssertTrue(visible.contains(0))
            XCTAssertTrue(visible.contains(1))
            XCTAssertEqual(layout.entryIndex(at: layout.source), 0)
            XCTAssertNil(layout.entryIndex(at: CGPoint(x: x, y: 100)))
        }
    }
}
