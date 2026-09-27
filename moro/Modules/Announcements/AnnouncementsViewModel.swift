//
//  AnnouncementsViewModel.swift
//  moro
//
//  ViewModel for server announcements.
//

import Foundation
import Combine

@MainActor
final class AnnouncementsViewModel: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    enum LoadingState {
        case idle
        case loading
        case error(Error)
    }

    @Published private(set) var announcements: [Announcement] = []
    @Published private(set) var loadingState: LoadingState = .idle
    @Published private(set) var transientErrorMessage: String?
    @Published private(set) var isUnsupported: Bool = false
    @Published private(set) var mutatingAnnouncementIDs: Set<String> = []

    private let apiClient: MastodonAPI

    init(apiClient: MastodonAPI, initialAnnouncement: Announcement? = nil) {
        self.apiClient = apiClient
        if let initialAnnouncement {
            self.announcements = [initialAnnouncement]
        }
    }

    var unreadCount: Int {
        announcements.reduce(into: 0) { total, item in
            if !item.read {
                total += 1
            }
        }
    }

    func loadInitial() async {
        guard announcements.isEmpty else { return }
        await refresh()
    }

    func refresh() async {
        if announcements.isEmpty {
            loadingState = .loading
        }
        transientErrorMessage = nil

        do {
            let fetched = try await apiClient.fetchAnnouncements()
            announcements = fetched.sorted { lhs, rhs in
                lhs.publishedAt > rhs.publishedAt
            }
            loadingState = .idle
            isUnsupported = false
        } catch {
            if isCancellation(error) {
                loadingState = .idle
                return
            }

            if isUnsupportedError(error) {
                isUnsupported = true
                announcements = []
                loadingState = .idle
                return
            }

            if announcements.isEmpty {
                loadingState = .error(error)
            } else {
                transientErrorMessage = error.localizedDescription
            }
        }
    }

    func dismissAnnouncement(_ announcement: Announcement) async {
        guard !announcement.read else { return }
        guard !mutatingAnnouncementIDs.contains(announcement.id) else { return }

        mutatingAnnouncementIDs.insert(announcement.id)
        defer { mutatingAnnouncementIDs.remove(announcement.id) }

        do {
            try await apiClient.dismissAnnouncement(id: announcement.id)
            await refresh()
        } catch {
            transientErrorMessage = MoroL10n.AnnouncementsVM.markFailed
        }
    }

    func toggleReaction(
        for announcement: Announcement,
        reaction: AnnouncementReaction
    ) async {
        let currentAnnouncement = currentAnnouncement(for: announcement)
        let currentReaction = currentAnnouncement.reactions.first {
            reactionNameMatches($0.name, reaction.name)
        } ?? reaction

        guard !mutatingAnnouncementIDs.contains(currentAnnouncement.id) else { return }

        mutatingAnnouncementIDs.insert(currentAnnouncement.id)
        defer { mutatingAnnouncementIDs.remove(currentAnnouncement.id) }

        do {
            if currentReaction.me {
                try await apiClient.removeAnnouncementReaction(
                    id: currentAnnouncement.id,
                    name: currentReaction.name
                )
            } else {
                try await apiClient.addAnnouncementReaction(
                    id: currentAnnouncement.id,
                    name: currentReaction.name
                )
            }
            await refresh()
        } catch {
            await refresh()
            if reactionMutationMatchesFinalState(
                announcementID: currentAnnouncement.id,
                reactionName: currentReaction.name,
                shouldBeReacted: !currentReaction.me
            ) {
                return
            }
            transientErrorMessage = MoroL10n.AnnouncementsVM.reactionFailed
        }
    }

    func addReaction(
        for announcement: Announcement,
        name: String
    ) async {
        let currentAnnouncement = currentAnnouncement(for: announcement)

        if let existingReaction = currentAnnouncement.reactions.first(where: {
            reactionNameMatches($0.name, name)
        }) {
            await toggleReaction(for: currentAnnouncement, reaction: existingReaction)
            return
        }

        guard !mutatingAnnouncementIDs.contains(currentAnnouncement.id) else { return }

        mutatingAnnouncementIDs.insert(currentAnnouncement.id)
        defer { mutatingAnnouncementIDs.remove(currentAnnouncement.id) }

        do {
            try await apiClient.addAnnouncementReaction(
                id: currentAnnouncement.id,
                name: name
            )
            await refresh()
        } catch {
            await refresh()
            if reactionMutationMatchesFinalState(
                announcementID: currentAnnouncement.id,
                reactionName: name,
                shouldBeReacted: true
            ) {
                return
            }
            transientErrorMessage = MoroL10n.AnnouncementsVM.reactionFailed
        }
    }

    func isMutating(announcementID: String) -> Bool {
        mutatingAnnouncementIDs.contains(announcementID)
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if case APIError.cancelled = error {
            return true
        }

        if case APIError.underlying(let underlyingError) = error,
           (underlyingError as? URLError)?.code == .cancelled {
            return true
        }

        return false
    }

    private func currentAnnouncement(for announcement: Announcement) -> Announcement {
        announcements.first(where: { $0.id == announcement.id }) ?? announcement
    }

    private func reactionMutationMatchesFinalState(
        announcementID: String,
        reactionName: String,
        shouldBeReacted: Bool
    ) -> Bool {
        guard let announcement = announcements.first(where: { $0.id == announcementID }) else {
            return false
        }

        let reaction = announcement.reactions.first {
            reactionNameMatches($0.name, reactionName)
        }

        if shouldBeReacted {
            return reaction?.me == true
        }

        return reaction?.me != true
    }

    private func reactionNameMatches(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || normalizedReactionName(lhs) == normalizedReactionName(rhs)
    }

    private func normalizedReactionName(_ name: String) -> String {
        name.unicodeScalars
            .filter { $0.value != 0xFE0F }
            .map(String.init)
            .joined()
    }

    private func isUnsupportedError(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else { return false }
        guard let statusCode = apiError.httpStatusCode else { return false }
        return [404, 405, 501].contains(statusCode)
    }
}
