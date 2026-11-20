import Combine
import SwiftUI

/// Created on opening a post attachment. Keep the original action destination and observe
/// the same optimistic updates and rollbacks as the timeline while the preview is open.
@MainActor
final class MediaPreviewPost: ObservableObject {
    @Published private(set) var status: Status
    let actions: PostActions
    let interactions: PostInteractionHandlers?
    let theme: MoroTheme
    let isFocused: Bool
    /// Navigation and reporting belong to the screen that opened this preview.
    var closeBeforeAction: ((@escaping () -> Void) -> Void)?
    private var subscription: AnyCancellable?

    init?(status: Status, actions: PostActions, theme: MoroTheme, isFocused: Bool = false) {
        guard actions.navigation != nil || actions.onTap != nil || actions.onReply != nil else { return nil }
        self.status = status.displayStatus
        self.actions = actions
        self.theme = theme
        interactions = actions.mediaHandlers?.forMediaPreview()
        self.isFocused = isFocused
        subscription = FeedCoordinator.shared.updates.sink { [weak self] update in
            guard let self, case .post(let updated) = update, updated.displayStatus.id == self.status.id else { return }
            self.status = self.status.incorporatingDisplayStatusUpdate(updated.displayStatus)
        }
    }

    nonisolated deinit {}
}

extension EnvironmentValues {
    @Entry var mediaPreviewHandlers: PostInteractionHandlers? = nil
}

struct MediaPreviewPostSheets: ViewModifier {
    let post: MediaPreviewPost?
    var video: NativeVideoSession?

    func body(content: Content) -> some View {
        if let post, let handlers = post.interactions {
            content
                .modifier(PostInteractionSheets(actionSurface: handlers.actionSurface,
                    interactionService: handlers.interactionService, apiClient: handlers.apiClient,
                    composeAsSheet: true, onComposeDismiss: { video?.resumeAfterComposer() }))
                .environmentObject(handlers.appState)
                .moroTheme(post.theme)
                .onReceive(handlers.actionSurface.$composeContext) { context in
                    if context != nil { video?.pauseForComposer() }
                }
        } else {
            content
        }
    }
}

struct MediaPreviewNavigationBar<Trailing: View>: View {
    let close: () -> Void
    let closeIdentifier: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 6) { controls }
        } else {
            controls
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            MoroFloatingNavButton(kind: .close, action: close)
                .accessibilityIdentifier(closeIdentifier)
            Spacer()
            trailing()
        }
    }
}

struct MediaPreviewMoreMenu: View {
    let post: MediaPreviewPost?
    let attachment: Status.Attachment
    let isExporting: Bool
    let export: (MediaExportAction) -> Void

    var body: some View {
        Menu {
            ForEach(MediaExportAction.available(for: attachment), id: \.self) { action in
                Button(action.title, systemImage: action.systemImage) { export(action) }
                    .disabled(isExporting)
            }
            if let post {
                Divider()
                Button {
                    post.closeBeforeAction? {
                        if !post.isFocused { (post.actions.onTap ?? post.actions.navigation?.onTapDetail)?() }
                    }
                } label: { Label(MoroL10n.Profile.viewOriginalPost, systemImage: "text.bubble") }
                .accessibilityIdentifier("mediaPreview.openPost")
                if !post.actions.isOwnPost, let report = post.actions.menu?.onReport {
                    Button(role: .destructive) { post.closeBeforeAction?(report) } label: {
                        Label(MoroL10n.Profile.report, systemImage: "flag")
                    }
                    .accessibilityIdentifier("mediaPreview.report")
                }
            }
        } label: {
            FloatingNavIconLabel(systemName: "ellipsis", isLoading: isExporting)
        }
        .accessibilityLabel(MoroL10n.StatusAction.more)
        .accessibilityIdentifier("mediaPreview.more")
    }
}

struct MediaPreviewPostBar: View {
    @ObservedObject var post: MediaPreviewPost
    let shareMedia: () -> Void
    @Environment(\.moroTheme) private var theme

    var body: some View {
        let status = post.status
        let actions = post.actions
        HStack(spacing: 4) {
            if let reply = actions.onReply {
                button(.reply, "bubble.left", title: MoroL10n.StatusAction.reply, count: status.repliesCount) {
                    if let handlers = post.interactions { handlers.handleReply(status) }
                    else { reply() }
                }
            }
            if let boost = actions.onBoost {
                button(.boost, "arrow.2.squarepath", title: status.reblogged ? MoroL10n.StatusAction.unboost : MoroL10n.StatusAction.boost,
                       active: status.reblogged, color: theme.colors.boostActive, count: status.reblogsCount,
                       disabled: !status.allowsReblogAction) {
                    if let handlers = post.interactions { handlers.handleBoost(status) }
                    else { boost() }
                }
            }
            if let like = actions.onLike {
                button(.like, "heart", selectedIcon: "heart.fill",
                       title: status.favourited ? MoroL10n.StatusAction.unfavourite : MoroL10n.StatusAction.favourite,
                       active: status.favourited, color: theme.colors.error, count: status.favouritesCount) {
                    if let handlers = post.interactions { handlers.handleLike(status) }
                    else { like() }
                }
            }
            if let bookmark = actions.onBookmark {
                button(.bookmark, "bookmark", selectedIcon: "bookmark.fill",
                       title: status.bookmarked ? MoroL10n.StatusAction.unbookmark : MoroL10n.StatusAction.bookmark,
                       active: status.bookmarked, color: theme.colors.bookmarkActive) {
                    if let handlers = post.interactions { handlers.handleBookmark(status) }
                    else { bookmark() }
                }
            }
            Group {
                if status.url != nil, let sharePost = actions.menu?.onShare {
                    Menu {
                        Button(MoroL10n.VideoPreview.sharePost, systemImage: "link", action: sharePost)
                        Button(MediaExportAction.share.title, systemImage: MediaExportAction.share.systemImage, action: shareMedia)
                    } label: { shareIcon }
                } else {
                    Button(action: shareMedia) { shareIcon }
                }
            }
            .accessibilityLabel(MoroL10n.Profile.share)
            .accessibilityIdentifier("mediaPreview.share")
        }
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var shareIcon: some View {
        Image(systemName: "square.and.arrow.up")
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }

    private func button(_ role: PostActionRole, _ icon: String, selectedIcon: String? = nil, title: String,
                        active: Bool = false, color: Color = .white, count: Int = 0, disabled: Bool = false,
                        action: @escaping () -> Void) -> some View {
        AnimatedActionButton(role: role, activeIcon: selectedIcon ?? icon, inactiveIcon: icon, isActive: active,
                             activeColor: color, inactiveColor: .white, count: count, isDisabled: disabled,
                             action: action, accessibilityLabel: title, iconSize: 18, minHitHeight: 44, fillsLane: true)
    }
}
