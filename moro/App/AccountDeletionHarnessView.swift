//
//  AccountDeletionHarnessView.swift
//  moro
//
//  Deterministic UI-test and review-screenshot harness for account deletion.
//

#if DEBUG
import SwiftUI

struct AccountDeletionHarnessView: View {
    @StateObject private var appState: AppState

    private let session: StoredAccountSession

    init() {
        let account = Account(
            id: "app-review",
            username: "appreview",
            acct: "appreview@m.somincola.org",
            displayName: "App Review",
            note: "",
            avatar: "",
            avatarStatic: "",
            header: "",
            headerStatic: "",
            followersCount: 0,
            followingCount: 0,
            statusesCount: 0
        )
        _appState = StateObject(wrappedValue: AppState())
        session = StoredAccountSession(
            id: "app-review-session",
            account: account,
            instanceURLString: "https://m.somincola.org",
            tokenStorageKey: "unused-ui-test-token",
            lastUsedAt: Date()
        )
    }

    var body: some View {
        NavigationStack {
            ServerAccountActionsView(session: session)
        }
        .environmentObject(appState)
    }
}
#endif
