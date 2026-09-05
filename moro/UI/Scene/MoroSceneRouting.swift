//
//  MoroSceneRouting.swift
//  moro
//
//  Scene semantics for the current tab and route model.
//

import Foundation

extension MainTab {
    var rootSceneDescriptor: MoroSceneDescriptor {
        switch self {
        case .home:
            return MoroSceneDescriptor(
                identity: "root.home",
                kind: .stream,
                presentation: .root,
                surface: .continuous
            )
        case .explore:
            return MoroSceneDescriptor(
                identity: "root.explore",
                kind: .discovery,
                presentation: .root,
                surface: .continuous
            )
        case .inbox:
            return MoroSceneDescriptor(
                identity: "root.inbox",
                kind: .stream,
                presentation: .root,
                surface: .continuous
            )
        case .me:
            return MoroSceneDescriptor(
                identity: "root.me",
                kind: .hero,
                presentation: .root,
                surface: .hero
            )
        }
    }
}

extension Route {
    var sceneDescriptor: MoroSceneDescriptor {
        switch self {
        case .statusDetail, .announcementDetail, .webPreview, .instanceDetails:
            return MoroSceneDescriptor(kind: .detail)

        case .announcements:
            return MoroSceneDescriptor(kind: .stream)

        case .conversationDetail:
            return MoroSceneDescriptor(
                kind: .detail,
                canvas: .grouped,
                topBar: .content,
                surface: .input
            )

        case .hashtag, .search, .accountLookup:
            return MoroSceneDescriptor(kind: .discovery)

        case .mentionUser, .userProfile:
            return MoroSceneDescriptor(kind: .hero)

        case .mediaPreview, .mediaGallery:
            return MoroSceneDescriptor(
                kind: .detail,
                presentation: .immersive,
                canvas: .immersive,
                topBar: .hidden,
                scrollBehavior: []
            )

        case .bookmarks, .favourites, .scheduledStatuses, .profileConnections:
            return MoroSceneDescriptor(kind: .stream)

        case .lists, .savedSearches:
            return MoroSceneDescriptor(kind: .grouped)

        case .editProfile:
            return MoroSceneDescriptor(kind: .task)
        }
    }
}
