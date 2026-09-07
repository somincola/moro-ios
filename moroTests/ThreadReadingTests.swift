import Testing
@testable import moro

@MainActor struct ThreadReadingTests {
    @Test func branchControlRequiresThreeLoadedSubsequentReplies() {
        let focus = ThreadReadingFixtures.status("focus")
        for count in 0...4 {
            let replies = [ThreadReadingFixtures.status("branch", parent: "focus", own: false)]
                + (0..<count).map { index in
                    ThreadReadingFixtures.status("child\(index)", parent: index == 0 ? "branch" : "child\(index - 1)")
                }
            let model = ThreadedConversationModel(focusedStatus: focus, context: StatusContext(ancestors: [], descendants: replies))
            let rows = ThreadReadingProjection(items: Array(model.threadItems.dropFirst()), authorID: "author", state: ThreadReadingState()).rows
            let branch = rows.first { $0.id == "branch" }
            // Count all loaded descendants, excluding the opening reply and its server count.
            #expect(branch?.replyCount == count)
            #expect(branch?.showsBranchControl(isCollapsed: false) == (count >= 3))
            #expect(rows.dropFirst().allSatisfy { !$0.showsBranchControl(isCollapsed: false) })
            #expect(rows.count == count + 1)
        }
    }

    @Test func shortenedCollapsedDiscussionCanStillExpand() {
        let focus = ThreadReadingFixtures.status("focus")
        let replies = [
            ThreadReadingFixtures.status("branch", parent: "focus", own: false),
            ThreadReadingFixtures.status("child1", parent: "branch"),
            ThreadReadingFixtures.status("child2", parent: "child1"),
            ThreadReadingFixtures.status("child3", parent: "child2"),
        ]
        var state = ThreadReadingState()
        state.toggleBranch("branch")
        // Simulate refreshed context losing replies while this discussion remains collapsed.
        for remaining in [3, 2, 1, 0] {
            let model = ThreadedConversationModel(focusedStatus: focus,
                context: StatusContext(ancestors: [], descendants: Array(replies.prefix(remaining + 1))))
            let items = Array(model.threadItems.dropFirst())
            let rows = ThreadReadingProjection(items: items, authorID: "author", state: state).rows
            #expect(rows.map(\.id) == ["branch"])
            #expect(rows.first?.showsBranchControl(isCollapsed: true) == (remaining > 0))
            var expanded = state
            expanded.toggleBranch("branch")
            let revealed = ThreadReadingProjection(items: items, authorID: "author", state: expanded).rows
            #expect(revealed.count == remaining + 1)
            #expect(revealed.first?.showsBranchControl(isCollapsed: false) == (remaining >= 3))
        }
    }

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
        #expect(rows.filter { $0.showsBranchControl(isCollapsed: false) }.count == 6)
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

    @Test func suppliedAuthorRepliesKeepSiblingForksAndSeparateRootReplies() {
        let model = ThreadedConversationModel(focusedStatus: ThreadReadingSample.focus, context: ThreadReadingSample.context)
        let rows = ThreadReadingProjection(
            items: Array(model.threadItems.dropFirst()),
            authorID: ThreadReadingSample.focus.account.id,
            state: ThreadReadingState()
        ).rows.filter { $0.item.isAuthorContinuation }
        let first = "117117597063812357" // 因为太震撼了…
        let separate = "117125384303241460" // 我这个砖…
        #expect(rows.map { $0.item.status.inReplyToID } == [ThreadReadingSample.focus.id, first, first, ThreadReadingSample.focus.id])
        #expect(rows.map { $0.item.replyGroupRootID } == [first, first, first, separate])
        #expect(rows.map { $0.item.replyDepth } == [0, 1, 1, 0])
        #expect(rows.map(\.isNestedReply) == [false, true, true, false])
        #expect(rows.allSatisfy { $0.item.replyBranchID == nil && $0.replyCount == 0 })
    }

    @Test func suppliedReaderDiscussionIncludesTheAuthorsFirstReplyInItsCollapseCount() {
        let model = ThreadedConversationModel(focusedStatus: ThreadReadingSample.focus, context: ThreadReadingSample.context)
        let items = Array(model.threadItems.dropFirst())
        let root = "117117689679969635" // 我的有些表亲…
        let replies = [
            "117117695638809878", // 1. 作者：我们家小孩…
            "117118009864271692", // 2. 伊丽莎白猫：我们家也是迄今无人生娃…
            "117118175009985659", // 3. 白石京：我们家也是…
        ]
        var state = ThreadReadingState()
        let expanded = ThreadReadingProjection(items: items, authorID: ThreadReadingSample.focus.account.id, state: state).rows
        let discussion = expanded.filter { $0.item.replyBranchID == root }
        #expect(discussion.map(\.id) == [root] + replies)
        #expect(discussion.map { $0.item.status.inReplyToID } == ["117117597063812357", root, replies[0], replies[1]])
        #expect(discussion.map(\.replyCount) == [3, 0, 0, 0])
        #expect(discussion.allSatisfy { !$0.item.isAuthorContinuation })
        #expect(discussion.filter { $0.showsBranchControl(isCollapsed: false) }.map(\.id) == [root])

        state.toggleBranch(root)
        let collapsed = ThreadReadingProjection(items: items, authorID: ThreadReadingSample.focus.account.id, state: state).rows
        #expect(collapsed.map(\.id) == expanded.map(\.id).filter { !replies.contains($0) })
        #expect(collapsed.first { $0.id == root }?.replyCount == 3)
        state.toggleBranch(root)
        #expect(ThreadReadingProjection(items: items, authorID: ThreadReadingSample.focus.account.id, state: state).rows.map(\.id) == expanded.map(\.id))
    }
}
