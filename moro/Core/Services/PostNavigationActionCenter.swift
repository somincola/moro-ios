//
//  PostNavigationActionCenter.swift
//  moro
//
//  Stateless dispatcher for status-related navigation actions.
//

import Foundation

@MainActor
enum PostNavigationActionCenter {
    struct Handlers {
        let onAvatarTap: () -> Void
        let onUsernameTap: () -> Void
        let onImageTap: (URL) -> Void
        /// Returns false when the renderer should open the original URL.
        let onMentionTap: (String, URL) -> Bool
        let onHashtagTap: (String, URL) -> Void
        let onQuotedStatusTap: (Status) -> Void
        let onBoostUserTap: () -> Void
        let onReplyToUserTap: (Status.Mention) -> Void
        let onTapDetail: () -> Void
    }

    static func handlers(
        for status: Status,
        router: AppRouter,
        detailStatus: Status? = nil
    ) -> Handlers {
        handlers(
            for: status,
            detailStatus: detailStatus,
            navigate: { route in
                router.navigate(to: route)
            }
        )
    }

    static func handlers(
        for status: Status,
        detailStatus: Status? = nil,
        navigate: @escaping (Route) -> Void
    ) -> Handlers {
        let targetStatus = detailStatus ?? status.displayStatus

        return Handlers(
            onAvatarTap: {
                navigate(.userProfile(status.account))
            },
            onUsernameTap: {
                navigate(.userProfile(status.account))
            },
            onImageTap: { url in
                navigate(mediaRoute(for: url, in: targetStatus))
            },
            onMentionTap: { _, url in
                guard let mention = status.displayStatus.mentions?.first(where: { $0.url == url }) else {
                    return false
                }
                navigate(.mentionUser(mention))
                return true
            },
            onHashtagTap: { tag, _ in
                navigate(.hashtag(tag))
            },
            onQuotedStatusTap: { quotedStatus in
                navigate(.statusDetail(quotedStatus.displayStatus))
            },
            onBoostUserTap: {
                navigate(.userProfile(status.account))
            },
            onReplyToUserTap: { mention in
                navigate(.mentionUser(mention))
            },
            onTapDetail: {
                navigate(.statusDetail(targetStatus))
            }
        )
    }

    private static func mediaRoute(for tappedURL: URL, in status: Status) -> Route {
        let imageAttachments = status.mediaAttachments.filter { $0.type == "image" }
        guard !imageAttachments.isEmpty else {
            return .mediaPreview(url: tappedURL)
        }

        guard let tappedIndex = imageAttachments.firstIndex(where: { $0.url == tappedURL }) else {
            return .mediaPreview(url: tappedURL)
        }

        return .mediaGallery(
            items: imageAttachments.map {
                RouteMediaGalleryItem(
                    id: $0.id,
                    url: $0.url,
                    altText: $0.description
                )
            },
            initialIndex: tappedIndex
        )
    }
}
