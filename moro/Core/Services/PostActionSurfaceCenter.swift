//
//  PostActionSurfaceCenter.swift
//  moro
//
//  Shared state center for post action surfaces (boost/quote, compose, report, delete).
//

import Combine

struct PostDeleteRequest {
    enum Mode: Equatable {
        case delete
        case redraft
    }

    let status: Status
    let mode: Mode

    var shouldRedraft: Bool {
        mode == .redraft
    }
}

@MainActor
final class PostActionSurfaceCenter: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    @Published var boostDialogStatus: Status?
    @Published var composeContext: ComposeContextWrapper?
    @Published var reportStatus: Status?
    @Published private(set) var deleteRequest: PostDeleteRequest?

    func presentBoostOrToggle(
        for status: Status,
        currentUserID: String?,
        onDirectToggle: @escaping () -> Void
    ) {
        // When the user has turned off "ask before boosting" in settings, tap
        // means "just boost" — skip the boost-or-quote choice sheet entirely.
        // Quote is still reachable from the "more" menu for power users.
        guard AppSettings.shared.askBeforeBoostingAPost else {
            onDirectToggle()
            return
        }
        let quoteInfo = QuoteButtonInfo.forStatus(status, currentUserID: currentUserID)
        if quoteInfo.isEnabled {
            boostDialogStatus = status
        } else {
            onDirectToggle()
        }
    }

    func dismissBoostDialog() {
        boostDialogStatus = nil
    }

    func startReply(to status: Status) {
        composeContext = ComposeContextWrapper(context: .reply(to: status))
    }

    func startQuote(from status: Status) {
        composeContext = ComposeContextWrapper(context: .quote(original: status.displayStatus))
        boostDialogStatus = nil
    }

    func startEdit(_ status: Status) {
        composeContext = ComposeContextWrapper(context: .edit(status: status.displayStatus))
    }

    func startRedraft(from status: Status, accountID: String?) {
        let draft = ComposeDraft.redraft(from: status, accountID: accountID)
        composeContext = ComposeContextWrapper(
            context: draft.target.composeContext,
            draft: draft
        )
    }

    func presentReport(for status: Status) {
        reportStatus = status
    }

    func dismissReport() {
        reportStatus = nil
    }

    func requestDelete(_ status: Status) {
        deleteRequest = PostDeleteRequest(status: status, mode: .delete)
    }

    func requestDeleteAndRedraft(_ status: Status) {
        deleteRequest = PostDeleteRequest(status: status, mode: .redraft)
    }

    func clearDeleteRequest() {
        deleteRequest = nil
    }
}
