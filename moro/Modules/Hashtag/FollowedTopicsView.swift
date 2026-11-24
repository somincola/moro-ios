import SwiftUI

struct FollowedTopicsRouteView: View {
    @Environment(\.activeAccountKey) private var accountKey
    let apiClient: MastodonAPI
    var body: some View { FollowedTopicsView(apiClient: apiClient).id(accountKey) }
}

struct FollowedTopicsView: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.appRouter) private var router
    @StateObject private var model: FollowedTopicsViewModel

    init(apiClient: MastodonAPI) {
        _model = StateObject(wrappedValue: FollowedTopicsViewModel(apiClient: apiClient))
    }

    var body: some View {
        MoroSettingsList {
            Section {
                if model.tags.isEmpty, model.hasLoaded, !model.isLoading, model.error == nil {
                    EmptyStateView(
                        spec: EmptyStateSpec(
                            icon: "number",
                            title: MoroL10n.Topics.empty,
                            message: MoroL10n.Topics.homeHint,
                            mascot: .calm
                        )
                    )
                    .frame(minHeight: 220)
                }
                ForEach(model.tags) { tag in
                    HStack {
                        Button { router.navigate(to: .hashtag(tag.name)) } label: {
                            HStack {
                                Text("#\(tag.name)")
                                    .foregroundStyle(theme.colors.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(theme.typography.caption)
                                    .foregroundStyle(theme.colors.textSecondary)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("topics.open.\(tag.name)")
                        if model.removing.contains(tag.id) { ProgressView() }
                    }
                    .swipeActions {
                        Button(MoroL10n.Topics.unfollow) { Task { await model.unfollow(tag) } }
                            .tint(.gray)
                            .disabled(model.isLoading || model.removing.contains(tag.id))
                    }
                }
                if model.isLoading {
                    HStack {
                        Spacer(minLength: 0)
                        MoroMascotView(expression: .thinking, size: 32)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 56)
                } else if model.error != nil {
                    if model.tags.isEmpty {
                        ErrorStateView(
                            spec: ErrorStateSpec(
                                title: MoroL10n.Topics.loadFailed,
                                message: MoroL10n.AppError.recoveryTryAgain,
                                actionTitle: MoroL10n.Compose.retry,
                                action: { Task { await model.retry() } },
                                actionAccessibilityIdentifier: "topics.retry"
                            )
                        )
                        .frame(minHeight: 220)
                    } else {
                        MoroInlineNoticeBanner(
                            message: MoroL10n.Topics.loadFailed,
                            tone: .error,
                            actionTitle: MoroL10n.Compose.retry,
                            action: { Task { await model.retry() } },
                            actionAccessibilityIdentifier: "topics.retry"
                        )
                        .padding(.vertical, theme.spacing.xs)
                    }
                } else if model.nextMaxID != nil {
                    HStack {
                        Spacer(minLength: 0)
                        MoroStateActionButton(
                            title: MoroL10n.Topics.loadMore,
                            style: .subtle,
                            accessibilityIdentifier: "topics.loadMore"
                        ) {
                            Task { await model.load() }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, theme.spacing.s)
                }
            } footer: {
                if !model.tags.isEmpty {
                    Text(MoroL10n.Topics.homeHint)
                }
            }
            if model.removalError != nil {
                MoroInlineNoticeBanner(
                    message: MoroL10n.Topics.actionFailed,
                    tone: .error
                )
            }
        }
        .moroSettingsListChrome()
        .navigationTitle(MoroL10n.Topics.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load(refresh: true) }
        .task { await model.load(refresh: true) }
    }
}
