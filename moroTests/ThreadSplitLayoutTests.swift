import CoreGraphics
import Testing
@testable import moro

/// Where iPhone Duo's two columns meet (inner display held landscape, about 951 pt wide).
@Suite
struct ThreadSplitLayoutTests {
    private let root: CGFloat = 951
    private let fold: CGFloat = 475.5

    @Test func halfOpenTheColumnsStayAtTheFoldWhateverTheReaderChose() {
        let width = ThreadSplitLayout.listWidth(rootWidth: root, foldX: fold, isFoldActive: true,
            preferredFraction: 0.35)
        #expect(width == fold)
        #expect(!ThreadSplitLayout.isResizable(rootWidth: root, foldX: fold, isFoldActive: true))
    }

    @Test func fullyOpenTheReadersWidthWins() {
        let width = ThreadSplitLayout.listWidth(rootWidth: root, foldX: fold, isFoldActive: false,
            preferredFraction: 0.4)
        #expect(abs(width - root * 0.4) < 0.01)
        #expect(ThreadSplitLayout.isResizable(rootWidth: root, foldX: fold, isFoldActive: false))
    }

    @Test func withoutAChoiceItSplitsAtTheFoldOrAFixedShare() {
        #expect(ThreadSplitLayout.listWidth(rootWidth: root, foldX: fold, isFoldActive: false,
            preferredFraction: 0) == fold)
        let noFold = ThreadSplitLayout.listWidth(rootWidth: root, foldX: nil, isFoldActive: false,
            preferredFraction: nil)
        #expect(noFold == min(max(root * 0.42, 360), 460))
        // A fold too near an edge is not a place to split.
        #expect(ThreadSplitLayout.listWidth(rootWidth: root, foldX: 100, isFoldActive: true,
            preferredFraction: nil) == noFold)
        #expect(ThreadSplitLayout.isResizable(rootWidth: root, foldX: 100, isFoldActive: true))
    }

    @Test func bothColumnsStayReadable() {
        #expect(ThreadSplitLayout.clamp(100, rootWidth: root) == ThreadSplitLayout.listMinimumWidth)
        #expect(ThreadSplitLayout.clamp(900, rootWidth: root) == root - ThreadSplitLayout.threadMinimumWidth)
        #expect(ThreadSplitLayout.listWidth(rootWidth: root, foldX: nil, isFoldActive: false,
            preferredFraction: 0.95) == root - ThreadSplitLayout.threadMinimumWidth,
            "A width saved on a wider screen still leaves the thread column room")
    }
}
