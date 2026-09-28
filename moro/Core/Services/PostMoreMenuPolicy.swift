//
//  PostMoreMenuPolicy.swift
//  moro
//
//  Centralized policy for post "more" menu visibility and ownership checks.
//

import Foundation

struct PostMoreMenuVisibility: Equatable {
    let showShare: Bool
    let showCopyLink: Bool
    let showCopyText: Bool
    let showOpenInBrowser: Bool
    let showEdit: Bool
    let showMuteUser: Bool
    let showBlockUser: Bool
    let showBlockAndReport: Bool
    let showReport: Bool
    let showPin: Bool
    let showDeleteAndRedraft: Bool
    let showDelete: Bool

    var hasCommonActions: Bool {
        showShare || showCopyLink || showCopyText || showOpenInBrowser
    }

    var hasOwnActions: Bool {
        showEdit || showPin || showDeleteAndRedraft || showDelete
    }

    var hasOtherActions: Bool {
        showMuteUser || showBlockUser || showBlockAndReport || showReport
    }
}

enum PostMoreMenuPolicy {
    static func isOwnPost(_ status: Status, currentUserID: String?) -> Bool {
        guard let currentUserID else { return false }
        return status.displayStatus.account.id == currentUserID
    }

    static func canEditPost(_ status: Status, currentUserID: String?) -> Bool {
        guard isOwnPost(status, currentUserID: currentUserID) else { return false }
        return status.displayStatus.poll == nil
    }

    static func visibility(
        isOwnPost: Bool,
        isBlockingUser: Bool?,
        hasShare: Bool,
        hasCopyLink: Bool,
        hasCopyText: Bool,
        hasOpenInBrowser: Bool,
        hasEdit: Bool,
        hasMuteUser: Bool,
        hasBlockUser: Bool,
        hasBlockAndReport: Bool,
        hasReport: Bool,
        hasPin: Bool,
        hasDeleteAndRedraft: Bool,
        hasDelete: Bool
    ) -> PostMoreMenuVisibility {
        let showOwnActions = isOwnPost
        let showOtherActions = !isOwnPost

        return PostMoreMenuVisibility(
            showShare: hasShare,
            showCopyLink: hasCopyLink,
            showCopyText: hasCopyText,
            showOpenInBrowser: hasOpenInBrowser,
            showEdit: showOwnActions && hasEdit,
            showMuteUser: showOtherActions && hasMuteUser,
            showBlockUser: showOtherActions && hasBlockUser,
            showBlockAndReport: showOtherActions && hasBlockAndReport && isBlockingUser != true,
            showReport: showOtherActions && hasReport,
            showPin: showOwnActions && hasPin,
            showDeleteAndRedraft: showOwnActions && hasDeleteAndRedraft,
            showDelete: showOwnActions && hasDelete
        )
    }
}
