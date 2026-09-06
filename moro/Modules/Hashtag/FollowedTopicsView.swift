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
        List {
            Section {
                if model.tags.isEmpty, model.hasLoaded, !model.isLoading, model.error == nil {
                    Text(MoroL10n.Topics.empty)
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.vertical, theme.spacing.m)
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
                    HStack { Spacer(); ProgressView(); Spacer() }.frame(minHeight: 44)
                } else if model.error != nil {
                    VStack(alignment: .leading) {
                        Text(MoroL10n.Topics.loadFailed).foregroundStyle(theme.colors.textSecondary)
                        Button(MoroL10n.Compose.retry) { Task { await model.retry() } }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("topics.retry")
                    }
                } else if model.nextMaxID != nil {
                    Button(MoroL10n.Topics.loadMore) { Task { await model.load() } }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("topics.loadMore")
                }
            } footer: {
                Text(MoroL10n.Topics.homeHint)
            }
            if model.removalError != nil {
                Text(MoroL10n.Topics.actionFailed)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .moroSettingsListChrome()
        .navigationTitle(MoroL10n.Topics.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load(refresh: true) }
        .task { await model.load(refresh: true) }
    }
}
