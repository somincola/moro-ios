//
//  AppState.swift
//  moro
//
//  Global observable state container.
//

import SwiftUI
import Combine
import UIKit

@MainActor
final class AppState: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentAccount: Account? {
        didSet {
            syncAccountPreferences(currentAccount)
        }
    }
    @Published var authToken: String?
    @Published var unreadAnnouncementsCount: Int = 0

    private func syncAccountPreferences(_ account: Account?) {
        let settings = AppSettings.shared
        settings.serverDefaultPostLanguage = account?.defaultPostingLanguage ?? ""
        guard let account else { return }

        settings.manuallyApproveFollowRequests = account.locked
        if let discoverable = account.credentialDiscoverable {
            settings.suggestMyAccountToOthers = discoverable
        }
        if let indexable = account.credentialIndexable {
            settings.appearInSearchEngines = indexable
        }
        if let hideCollections = account.credentialHideCollections {
            settings.showFollowersAndFollowing = !hideCollections
        }

        switch account.source?.privacy {
        case "public":
            settings.defaultPostVisibility = .public
        case "unlisted":
            settings.defaultPostVisibility = .unlisted
        case "private", "followers":
            settings.defaultPostVisibility = .followersOnly
        case "direct":
            settings.defaultPostVisibility = .mentionedOnly
        default:
            break
        }
    }

    func reset() {
        isAuthenticated = false
        currentAccount = nil
        authToken = nil
        unreadAnnouncementsCount = 0
    }
}

extension AppState: AuthTokenProvider {}

enum AppFeedbackKind {
    case success
    case error
    case info
}

struct AppFeedbackMessage: Identifiable, Equatable {
    let id = UUID()
    let kind: AppFeedbackKind
    let text: String
}

@MainActor
final class AppFeedbackCenter: ObservableObject {
    static let shared = AppFeedbackCenter()

    @Published var currentMessage: AppFeedbackMessage?
    private var dismissTask: Task<Void, Never>?

    func showSuccess(_ text: String, autoDismissAfter seconds: TimeInterval = 2.0) {
        show(.success, text, autoDismissAfter: seconds)
    }

    func showError(_ text: String, autoDismissAfter seconds: TimeInterval = 3.0) {
        show(.error, text, autoDismissAfter: seconds)
    }

    func showInfo(_ text: String, autoDismissAfter seconds: TimeInterval = 2.0) {
        show(.info, text, autoDismissAfter: seconds)
    }

    func show(_ kind: AppFeedbackKind, _ text: String, autoDismissAfter seconds: TimeInterval = 2.0) {
        dismissTask?.cancel()

        let message = AppFeedbackMessage(kind: kind, text: text)
        withAnimation(.easeInOut(duration: 0.2)) {
            currentMessage = message
        }
        UIAccessibility.post(notification: .announcement, argument: text)

        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if currentMessage?.id == message.id {
                withAnimation(.easeInOut(duration: 0.2)) {
                    currentMessage = nil
                }
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            currentMessage = nil
        }
    }
}
