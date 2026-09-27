//
//  NotificationRequestsView.swift
//  moro
//
//  Review notifications held by the server notification policy.
//

import SwiftUI

struct NotificationRequestsView: View {
    @Environment(\.moroTheme) private var theme

    let apiClient: MastodonAPI
    let onResolved: (ServerNotificationRequest) -> Void

    @State private var requests: [ServerNotificationRequest] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMore = false
    @State private var loadError: String?
    @State private var resolvingIDs: Set<String> = []

    var body: some View {
        Group {
            if isLoading, requests.isEmpty {
                ProgressView()
            } else if let loadError, requests.isEmpty {
                ContentUnavailableView {
                    Label(
                        MoroL10n.Notifications.loadFailed,
                        systemImage: "wifi.exclamationmark"
                    )
                } description: {
                    Text(loadError)
                } actions: {
                    Button(MoroL10n.Notifications.retryAction) {
                        Task { await load(reset: true) }
                    }
                }
            } else if requests.isEmpty {
                ContentUnavailableView(
                    MoroL10n.Notifications.emptyTitle,
                    systemImage: "tray",
                    description: Text(MoroL10n.NotificationSettings.requestsEmptyMessage)
                )
            } else {
                requestsList
            }
        }
        .navigationTitle(MoroL10n.NotificationSettings.requestsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load(reset: true) }
    }

    private var requestsList: some View {
        List {
            ForEach(requests) { request in
                requestRow(request)
            }

            if hasMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .onAppear {
                    Task { await load(reset: false) }
                }
            } else if let loadError {
                Button(MoroL10n.Notifications.retryAction) {
                    Task { await load(reset: false) }
                }
                .frame(maxWidth: .infinity)
                .accessibilityHint(loadError)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load(reset: true) }
    }

    private func requestRow(_ request: ServerNotificationRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                MoroAvatar(
                    imageURL: request.account.avatarAnimatedURL,
                    staticImageURL: request.account.avatarURL,
                    initials: request.account.displayNameInitials,
                    size: 44
                )
                VStack(alignment: .leading, spacing: 2) {
                    AccountDisplayNameView(
                        account: request.account,
                        typography: .subtitle,
                        textColor: theme.colors.textPrimary
                    )
                    Text("@\(request.account.acct)")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                }
                Spacer()
                Text("\(request.notificationsCount)")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.colors.borderSubtle.opacity(0.5), in: Capsule())
                    .accessibilityLabel(
                        "\(request.notificationsCount), \(MoroL10n.NotificationSettings.requestsTitle)")
            }

            if let status = request.lastStatus {
                let plainText = HTMLParser.stripHTML(status.content)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !plainText.isEmpty {
                    Text(plainText)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(3)
                }
            }

            HStack(spacing: 10) {
                Button {
                    Task { await resolve(request, accepting: true) }
                } label: {
                    Label(MoroL10n.Notifications.accept, systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await resolve(request, accepting: false) }
                } label: {
                    Label(MoroL10n.Notifications.reject, systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .disabled(resolvingIDs.contains(request.id))
            .overlay {
                if resolvingIDs.contains(request.id) {
                    ProgressView()
                        .padding(8)
                        .background(.regularMaterial, in: Circle())
                }
            }
        }
        .padding(.vertical, 6)
    }

    @MainActor
    private func load(reset: Bool) async {
        guard !isLoadingMore else { return }
        if reset {
            isLoading = true
        } else {
            guard hasMore else { return }
            isLoadingMore = true
        }
        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            let page = try await apiClient.fetchNotificationRequests(
                maxID: reset ? nil : requests.last?.id,
                limit: 40
            )
            guard !Task.isCancelled else { return }
            if reset {
                requests = page
            } else {
                var existing = Set(requests.map(\.id))
                requests.append(contentsOf: page.filter { existing.insert($0.id).inserted })
            }
            hasMore = page.count >= 40
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func resolve(_ request: ServerNotificationRequest, accepting: Bool) async {
        guard resolvingIDs.insert(request.id).inserted else { return }
        defer { resolvingIDs.remove(request.id) }
        do {
            if accepting {
                try await apiClient.acceptNotificationRequest(id: request.id)
            } else {
                try await apiClient.dismissNotificationRequest(id: request.id)
            }
            requests.removeAll { $0.id == request.id }
            onResolved(request)
        } catch {
            AppFeedbackCenter.shared.showError(
                accepting
                    ? MoroL10n.Notifications.toastAcceptFailed
                    : MoroL10n.Notifications.toastRejectFailed
            )
        }
    }
}
