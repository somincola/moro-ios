import Testing
@testable import moro

@MainActor struct ThreadReadingTests {
    @Test func collapsedBranchKeepsRootAndUnrelatedReplies() {
        let source = ThreadedConversationModel(focusedStatus: ThreadReadingFixtures.focus, context: ThreadReadingFixtures.context)
        let items = Array(source.threadItems.dropFirst(2))
        var state = ThreadReadingState()
        state.toggleBranch("a")
        let projection = ThreadReadingProjection(items: items, authorID: "author", state: state)
        #expect(projection.rows.map(\.id) == ["b", "a", "orphan"])
        #expect(projection.rows.first(where: { $0.id == "a" })?.replyCount == 2)
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
        #expect(projection.rows.map(\.id) == ["b", "a1"])
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
            ThreadReadingFixtures.status("\(index)", parent: index == 0 ? "focus" : "\(index - 1)", own: index % 2 != 0)
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

    @Test func onlyRootConnectedAuthorRepliesBecomeContinuations() {
        let focus = ThreadReadingFixtures.status("focus")
        let replies = [
            ThreadReadingFixtures.status("reader", parent: "focus", own: false),
            ThreadReadingFixtures.status("author-to-reader", parent: "reader"),
            ThreadReadingFixtures.status("author-in-discussion", parent: "author-to-reader"),
            ThreadReadingFixtures.status("addition", parent: "focus"),
            ThreadReadingFixtures.status("reader-to-addition", parent: "addition", own: false),
            ThreadReadingFixtures.status("addition2", parent: "addition"),
        ]
        let model = ThreadedConversationModel(focusedStatus: focus, context: StatusContext(ancestors: [], descendants: replies))
        let items = Array(model.threadItems.dropFirst())
        #expect(items.map(\.id) == ["addition", "addition2", "reader", "author-to-reader", "author-in-discussion", "reader-to-addition"])
        #expect(items.filter(\.isAuthorContinuation).map(\.id) == ["addition", "addition2"])
        #expect(items.first(where: { $0.id == "author-in-discussion" })?.replyBranchID == "reader")
        #expect(items.last?.replyBranchID == "reader-to-addition")
        let rows = ThreadReadingProjection(items: items, authorID: "author", state: ThreadReadingState()).rows
        #expect(rows.filter { $0.replyCount > 0 }.map(\.id) == ["reader"])
    }

    @Test func apiSiblingOrderIsPreservedWhileParentsStayBeforeChildren() {
        let focus = ThreadReadingFixtures.status("focus")
        let replies = [
            ThreadReadingFixtures.status("z", parent: "focus", own: false),
            ThreadReadingFixtures.status("a", parent: "focus", own: false),
            ThreadReadingFixtures.status("child", parent: "z", own: false),
        ]
        let model = ThreadedConversationModel(focusedStatus: focus, context: StatusContext(ancestors: [], descendants: replies))
        #expect(model.threadItems.map(\.id) == ["focus", "z", "child", "a"])
    }

    @Test func collapsingNestedIDDoesNotCreateAnotherCollapseBoundary() {
        let model = ThreadedConversationModel(focusedStatus: ThreadReadingFixtures.focus, context: ThreadReadingFixtures.context)
        let items = Array(model.threadItems.dropFirst(2))
        var state = ThreadReadingState()
        state.toggleBranch("a1")
        let rows = ThreadReadingProjection(items: items, authorID: "author", state: state).rows
        #expect(rows.count == 5)
        #expect(rows.filter { $0.replyCount > 0 }.map(\.id) == ["a"])
    }

    @Test func suppliedThreadKeepsAllRepliesAndPromotesOnlyFourAuthorContinuations() {
        let model = ThreadedConversationModel(focusedStatus: ThreadReadingSample.focus, context: ThreadReadingSample.context)
        let items = Array(model.threadItems.dropFirst())
        let continuationIDs = ["117117597063812357", "117117605197160447", "117118126512386830", "117125384303241460"]
        #expect(items.count == 58)
        #expect(Set(items.map(\.id)).count == 58)
        #expect(items.prefix(4).map(\.id) == continuationIDs)
        #expect(items.filter(\.isAuthorContinuation).map(\.id) == continuationIDs)
        #expect(items.filter { $0.status.account.id == ThreadReadingSample.focus.account.id && !$0.isAuthorContinuation }.count == 17)

        let rows = ThreadReadingProjection(items: items, authorID: ThreadReadingSample.focus.account.id, state: ThreadReadingState()).rows
        #expect(rows.filter { $0.replyCount > 0 }.count == 11)
        #expect(rows.filter { $0.item.replyBranchID == $0.id }.count == 22)
        #expect(rows.filter(\.isNestedReply).allSatisfy { $0.replyCount == 0 })
        // The server count is direct replies, not the number that a branch will hide.
        #expect(ThreadReadingSample.focus.repliesCount == 11)
        #expect(rows.first(where: { $0.id == "117116945719580606" })?.replyCount == 7)
        #expect(rows.first(where: { $0.id == "117125569431675905" })?.replyCount == 4)
    }

    @Test func suppliedThreadCollapsesEntireDiscussionAndPreservesAuthorContinuations() {
        let model = ThreadedConversationModel(focusedStatus: ThreadReadingSample.focus, context: ThreadReadingSample.context)
        let items = Array(model.threadItems.dropFirst())
        let root = "117116945719580606"
        var state = ThreadReadingState()
        state.toggleBranch(root)
        let rows = ThreadReadingProjection(items: items, authorID: ThreadReadingSample.focus.account.id, state: state).rows
        #expect(rows.count == 51)
        #expect(rows.filter { $0.item.replyBranchID == root }.map(\.id) == [root])
        #expect(rows.filter { $0.item.isAuthorContinuation }.count == 4)
        #expect(rows.first(where: { $0.id == root })?.replyCount == 7)
        state.expandAll()
        #expect(ThreadReadingProjection(items: items, authorID: ThreadReadingSample.focus.account.id, state: state).rows.count == 58)
        state.setAuthorOnly(true)
        let authorRows = ThreadReadingProjection(items: items, authorID: ThreadReadingSample.focus.account.id, state: state).rows
        #expect(authorRows.count == 21)
        #expect(authorRows.allSatisfy { $0.replyCount == 0 })
    }
}
