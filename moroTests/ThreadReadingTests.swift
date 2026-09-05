import Testing
@testable import moro

@MainActor struct ThreadReadingTests {
    @Test func collapsedBranchKeepsRootAndUnrelatedReplies() {
        let source = ThreadedConversationModel(focusedStatus: ThreadReadingFixtures.focus, context: ThreadReadingFixtures.context)
        let items = Array(source.threadItems.dropFirst(2))
        var state = ThreadReadingState()
        state.toggleBranch("a")
        let projection = ThreadReadingProjection(items: items, authorID: "author", state: state)
        #expect(projection.rows.map(\.id) == ["a", "b", "orphan"])
        #expect(projection.rows.first?.replyCount == 2)
        #expect(source.threadItems.count == 7)
        state.toggleBranch("a")
        #expect(ThreadReadingProjection(items: items, authorID: "author", state: state).rows.count == 5)
    }

    @Test func authorFilterRevealsAuthorRepliesInsideOtherAuthorsBranches() {
        let model = ThreadedConversationModel(focusedStatus: ThreadReadingFixtures.focus, context: ThreadReadingFixtures.context)
        var state = ThreadReadingState()
        state.toggleBranch("a")
        state.setAuthorOnly(true)
        let projection = ThreadReadingProjection(items: Array(model.threadItems.dropFirst(2)), authorID: "author", state: state)
        #expect(projection.rows.map(\.id) == ["a1", "b"])
        #expect(projection.rows.allSatisfy { $0.replyCount == 0 })
        #expect(state.collapsedIDs.isEmpty)
    }

    @Test func cyclicAndDuplicateRepliesDoNotLoopOrDuplicateFocusedPost() {
        let focus = ThreadReadingFixtures.status("focus", parent: "p")
        let context = StatusContext(ancestors: [
            ThreadReadingFixtures.status("p", parent: "q"),
            ThreadReadingFixtures.status("q", parent: "p"),
        ], descendants: [
            focus, ThreadReadingFixtures.status("a", parent: "b"),
            ThreadReadingFixtures.status("b", parent: "a"),
            ThreadReadingFixtures.status("a", parent: "b"),
        ])
        let model = ThreadedConversationModel(focusedStatus: focus, context: context)
        #expect(model.threadItems.map(\.id) == ["q", "p", "focus", "a", "b"])
        let projection = ThreadReadingProjection(items: Array(model.threadItems.suffix(2)), authorID: "author", state: ThreadReadingState())
        #expect(projection.rows.map(\.id) == ["a", "b"])
        #expect(projection.rows.first?.replyCount == 1)
    }

    @Test func longThreadUsesIterativeOrderingAndProjection() {
        let focus = ThreadReadingFixtures.status("focus")
        let replies = (0..<2000).map { index in
            ThreadReadingFixtures.status("\(index)", parent: index == 0 ? "focus" : "\(index - 1)")
        }
        let model = ThreadedConversationModel(focusedStatus: focus, context: StatusContext(ancestors: [], descendants: replies.reversed()))
        #expect(model.threadItems.count == 2001)
        #expect(model.threadItems.last?.id == "1999")
        var state = ThreadReadingState()
        state.toggleBranch("0")
        let projection = ThreadReadingProjection(items: Array(model.threadItems.dropFirst()), authorID: "author", state: state)
        #expect(projection.rows.count == 1)
        #expect(projection.rows.first?.replyCount == 1999)
    }
}
