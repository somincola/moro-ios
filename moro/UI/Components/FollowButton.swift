//
//  FollowButton.swift
//  moro
//
//  Follow/Unfollow button component for user profiles.
//

import SwiftUI

enum RelationshipControlSurfaceTone {
    case primary
    case secondary

    func backgroundColor(theme: MoroTheme) -> Color {
        switch self {
        case .primary:
            return theme.colors.primary500
        case .secondary:
            return theme.colors.surfaceBase
        }
    }

    func borderColor(theme: MoroTheme) -> Color {
        switch self {
        case .primary:
            return .clear
        case .secondary:
            return theme.colors.textTertiary.opacity(0.45)
        }
    }
}

extension View {
    func moroRelationshipControlSurface(
        _ tone: RelationshipControlSurfaceTone,
        theme: MoroTheme
    ) -> some View {
        background(tone.backgroundColor(theme: theme))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(tone.borderColor(theme: theme), lineWidth: 1)
            }
    }
}

struct FollowButton: View {
    let relationship: Relationship?
    let isLoading: Bool
    let isInteractionDisabled: Bool
    var onFollow: () -> Void
    var onUnfollow: () -> Void
    var onCancelRequest: () -> Void
    var onUnblock: () -> Void
    
    @Environment(\.moroTheme) private var theme
    @State private var showCancelRequestConfirmation = false
    
    private var buttonState: ButtonState {
        ButtonState.resolve(relationship: relationship)
    }
    
    var body: some View {
        Button(action: {
            switch buttonState {
            case .notFollowing:
                onFollow()
            case .following:
                onUnfollow()
            case .requested:
                showCancelRequestConfirmation = true
            case .blocked:
                onUnblock()
            case .domainBlocked:
                break
            }
        }) {
            ZStack {
                HStack(spacing: 6) {
                    if buttonState == .requested {
                        Image(systemName: "clock")
                            .moroScaledFont(size: 13, weight: .semibold)
                    }

                    Text(buttonState.title)
                        .font(theme.typography.body)
                        .fontWeight(.semibold)
                }
                .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(buttonState.foregroundColor(theme: theme))
                }
            }
            .foregroundStyle(buttonState.foregroundColor(theme: theme))
            .padding(.horizontal, 20)
            .frame(height: 36)
            .moroRelationshipControlSurface(buttonState.surfaceTone, theme: theme)
        }
        .disabled(buttonState == .domainBlocked || isLoading || isInteractionDisabled)
        .accessibilityLabel(buttonState.title)
        .confirmationDialog(
            MoroL10n.Profile.followRequested,
            isPresented: $showCancelRequestConfirmation,
            titleVisibility: .visible
        ) {
            Button(MoroL10n.Profile.cancelFollowRequest, role: .destructive) {
                onCancelRequest()
            }
            Button(MoroL10n.Common.cancel, role: .cancel) {}
        }
    }
    
    enum ButtonState: Equatable {
        case notFollowing
        case following
        case requested
        case blocked
        case domainBlocked

        static func resolve(relationship: Relationship?) -> ButtonState {
            if relationship?.blocking == true {
                return .blocked
            }
            if relationship?.domainBlocking == true {
                return .domainBlocked
            }
            if relationship?.requested == true {
                return .requested
            }
            if relationship?.following == true {
                return .following
            }
            return .notFollowing
        }
        
        var title: String {
            switch self {
            case .notFollowing:
                return MoroL10n.Profile.follow
            case .following:
                return MoroL10n.Profile.following
            case .requested:
                return MoroL10n.Profile.followRequested
            case .blocked:
                return MoroL10n.Profile.unblock
            case .domainBlocked:
                return MoroL10n.Profile.blocked
            }
        }
        
        func foregroundColor(theme: MoroTheme) -> Color {
            switch self {
            case .notFollowing:
                return theme.colors.primaryForeground
            case .following:
                return theme.colors.textPrimary
            case .requested:
                return theme.colors.textSecondary
            case .blocked:
                return theme.colors.textPrimary
            case .domainBlocked:
                return theme.colors.textSecondary
            }
        }
        
        var surfaceTone: RelationshipControlSurfaceTone {
            switch self {
            case .notFollowing:
                return .primary
            case .following, .requested, .blocked, .domainBlocked:
                return .secondary
            }
        }
    }
}
