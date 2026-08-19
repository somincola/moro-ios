//
//  PostActions.swift
//  moro
//
//  Aggregates all post action callbacks into a single value type.
//

import Foundation

struct PostActions {
    var navigation: PostNavigationActionCenter.Handlers?
    var menu: PostMenuActionCenter.Handlers?
    var onLike: (() -> Void)?
    var onBoost: (() -> Void)?
    var onBookmark: (() -> Void)?
    var onReply: (() -> Void)?
    var onPollVote: ((String, [Int]) async -> Bool)?
    var onLinkTap: ((URL) -> Void)?
    var onEdit: (() -> Void)?
    var onPin: (() -> Void)?
    var onDelete: (() -> Void)?
    var onTap: (() -> Void)?
    var isOwnPost: Bool = false

    static let empty = PostActions()
}
