import Combine
import SwiftUI

/// Created on opening a post attachment. Keep the original action destination and observe
/// the same optimistic updates and rollbacks as the timeline while the preview is open.
@MainActor
final class MediaPreviewPost: ObservableObject {
    @Published private(set) var status: Status
    let actions: PostActions
    let isFocused: Bool
    /// The presenting screen opens the composer, report or detail after this preview closes.
    var closeBeforeAction: ((@escaping () -> Void) -> Void)?
    private var subscription: AnyCancellable?

    init?(status: Status, actions: PostActions, isFocused: Bool = false) {
        guard actions.navigation != nil || actions.onTap != nil || actions.onReply != nil else { return nil }
        self.status = status.displayStatus
        self.actions = actions
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
            ZStack {
                FloatingNavIconLabel(systemName: "ellipsis").opacity(isExporting ? 0 : 1)
                if isExporting { ProgressView().tint(.white) }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
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
                button("bubble.left", MoroL10n.StatusAction.reply, count: status.repliesCount) {
                    post.closeBeforeAction? {
                        if let handlers = actions.mediaHandlers { handlers.handleReply(status) }
                        else { reply() }
                    }
                }
            }
            if let boost = actions.onBoost {
                button("arrow.2.squarepath", status.reblogged ? MoroL10n.StatusAction.unboost : MoroL10n.StatusAction.boost,
                       count: status.reblogsCount, color: status.reblogged ? theme.colors.boostActive : .white) {
                    if let handlers = actions.mediaHandlers {
                        if AppSettings.shared.askBeforeBoostingAPost { post.closeBeforeAction? { handlers.handleBoost(status) } }
                        else { handlers.handleBoost(status) }
                    } else { post.closeBeforeAction?(boost) }
                }
                .disabled(!status.allowsReblogAction)
                .opacity(status.allowsReblogAction ? 1 : 0.45)
            }
            if let like = actions.onLike {
                button(status.favourited ? "heart.fill" : "heart", status.favourited ? MoroL10n.StatusAction.unfavourite : MoroL10n.StatusAction.favourite,
                       count: status.favouritesCount, color: status.favourited ? theme.colors.error : .white) {
                    if let handlers = actions.mediaHandlers { handlers.handleLike(status) }
                    else { like() }
                }
            }
            if let bookmark = actions.onBookmark {
                button(status.bookmarked ? "bookmark.fill" : "bookmark", status.bookmarked ? MoroL10n.StatusAction.unbookmark : MoroL10n.StatusAction.bookmark,
                       color: status.bookmarked ? theme.colors.bookmarkActive : .white) {
                    if let handlers = actions.mediaHandlers { handlers.handleBookmark(status) }
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

    private func button(_ symbol: String, _ title: String, count: Int = 0, color: Color = .white,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                if count > 0 { Text(count.formatted(.number.notation(.compactName))).font(.caption.monospacedDigit()) }
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(count > 0 ? String(count) : "")
    }
}
