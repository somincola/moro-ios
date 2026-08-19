//
//  ProfileMoreButton.swift
//  moro
//
//  More menu button for user profile actions (Share, Mute, Block, Report).
//

import SwiftUI

/// Circular backed icon for floating controls shown over full-screen media.
struct FloatingNavIconLabel: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .moroScaledFont(size: 15, weight: .semibold)
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Circle().fill(.black.opacity(0.4)))
            .contentShape(Circle())
    }
}

struct ProfileMoreButton: View {
    let account: Account?
    let relationship: Relationship?
    var onShare: () -> Void
    var onEditProfile: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    var onBookmarks: (() -> Void)? = nil
    var onFavourites: (() -> Void)? = nil
    var onCopyLink: (() -> Void)? = nil
    var onOpenInBrowser: (() -> Void)? = nil
    var onAddToList: (() -> Void)? = nil
    var onMute: (() -> Void)? = nil
    var onBlock: (() -> Void)? = nil
    var onReport: (() -> Void)? = nil

    init(
        account: Account?,
        relationship: Relationship?,
        onShare: @escaping () -> Void,
        onEditProfile: (() -> Void)? = nil,
        onSettings: (() -> Void)? = nil,
        onBookmarks: (() -> Void)? = nil,
        onFavourites: (() -> Void)? = nil,
        onCopyLink: (() -> Void)? = nil,
        onOpenInBrowser: (() -> Void)? = nil,
        onAddToList: (() -> Void)? = nil,
        onMute: (() -> Void)? = nil,
        onBlock: (() -> Void)? = nil,
        onReport: (() -> Void)? = nil
    ) {
        self.account = account
        self.relationship = relationship
        self.onShare = onShare
        self.onEditProfile = onEditProfile
        self.onSettings = onSettings
        self.onBookmarks = onBookmarks
        self.onFavourites = onFavourites
        self.onCopyLink = onCopyLink
        self.onOpenInBrowser = onOpenInBrowser
        self.onAddToList = onAddToList
        self.onMute = onMute
        self.onBlock = onBlock
        self.onReport = onReport
    }

    var body: some View {
        Menu {
            if let onEditProfile {
                Button(action: onEditProfile) {
                    MoroMenuItemLabel(
                        title: MoroL10n.AccountMgmt.editProfile,
                        systemImage: "pencil"
                    )
                }
            }

            if let onSettings {
                Button(action: onSettings) {
                    MoroMenuItemLabel(
                        title: MoroL10n.Settings.title,
                        systemImage: "gearshape"
                    )
                }
            }

            if onBookmarks != nil || onFavourites != nil {
                if onEditProfile != nil || onSettings != nil {
                    Divider()
                }

                if let onBookmarks {
                    Button(action: onBookmarks) {
                        MoroMenuItemLabel(
                            title: MoroL10n.Navigation.bookmarks,
                            systemImage: "bookmark"
                        )
                    }
                }

                if let onFavourites {
                    Button(action: onFavourites) {
                        MoroMenuItemLabel(
                            title: MoroL10n.Navigation.favourites,
                            systemImage: "heart"
                        )
                    }
                }
            }

            if onEditProfile != nil || onSettings != nil || onBookmarks != nil
                || onFavourites != nil
            {
                Divider()
            }

            // Share
            Button(action: onShare) {
                MoroMenuItemLabel(title: MoroL10n.Profile.share, systemImage: "square.and.arrow.up")
            }

            if let onCopyLink {
                Button(action: onCopyLink) {
                    MoroMenuItemLabel(title: MoroL10n.Profile.copyLink, systemImage: "link")
                }
            }

            if let onOpenInBrowser {
                Button(action: onOpenInBrowser) {
                    MoroMenuItemLabel(title: MoroL10n.Profile.openInBrowser, systemImage: "safari")
                }
            }

            if let onAddToList {
                Button(action: onAddToList) {
                    MoroMenuItemLabel(
                        title: MoroL10n.Profile.addToList, systemImage: "text.badge.plus")
                }
            }

            if onMute != nil || onBlock != nil {
                Divider()
            }

            if let onMute {
                Button(action: onMute) {
                    MoroMenuItemLabel(
                        title: relationship?.muting == true
                            ? MoroL10n.Profile.unmute
                            : MoroL10n.Profile.mute(account?.username ?? ""),
                        systemImage: relationship?.muting == true ? "bell" : "bell.slash"
                    )
                }
            }

            if let onBlock {
                Button(action: onBlock) {
                    MoroMenuItemLabel(
                        title: relationship?.blocking == true
                            ? MoroL10n.Profile.unblock
                            : MoroL10n.Profile.block(account?.username ?? ""),
                        systemImage: relationship?.blocking == true
                            ? "hand.raised.slash"
                            : "hand.raised",
                        isDestructive: relationship?.blocking != true
                    )
                }
            }

            if let onReport {
                Divider()
                Button(action: onReport) {
                    MoroMenuItemLabel(
                        title: MoroL10n.Profile.report,
                        systemImage: "flag",
                        isDestructive: true
                    )
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .moroScaledFont(size: 17, weight: .semibold)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(MoroL10n.Profile.moreActions))
        .accessibilityIdentifier("profile.moreButton")
    }
}
