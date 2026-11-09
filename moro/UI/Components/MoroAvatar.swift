//
//  MoroAvatar.swift
//  moro
//
//  Circular avatar (SDWebImage, decoded at on-screen size) with fallback initials.
//

import SwiftUI

struct MoroAvatar: View {
    var imageURL: URL?
    var staticImageURL: URL?  // Server-provided static version, preferred in scrolling surfaces
    var initials: String = "MO"
    /// Picks the placeholder tone; pass `account.placeholderSeed` so one person keeps
    /// one colour everywhere. Falls back to the initials.
    var seed: String? = nil
    var size: CGFloat = 36
    /// Explicit opt-in on supported scrolling surfaces; other avatars stay static.
    var allowsAnimation = false

    @Environment(\.moroTheme) private var theme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.moroPlaybackScope) private var playbackScope

    /// Keep a static base even when a timeline grants the optional animation layer a lease.
    private var effectiveImageURL: URL? {
        staticImageURL ?? imageURL
    }

    /// No avatar, or the instance's stock `missing.png` (which differs per server):
    /// draw Moro's own placeholder instead.
    private var realImageURL: URL? {
        guard let url = effectiveImageURL, url.lastPathComponent.lowercased() != "missing.png" else { return nil }
        return url
    }

    var body: some View {
        ZStack {
            if let url = realImageURL {
                // Cheap base shown while the image loads (no network).
                theme.colors.primary50
                // Decode at the avatar's on-screen pixel size, not the full ~400px
                // original, so a timeline full of avatars stays light.
                SDWebRemoteImage(
                    url: url,
                    thumbnailPixelSize: size * displayScale,
                    allowsAnimation: false
                )
                if allowsAnimation, playbackScope.allowsAnimatedAvatars, let animatedURL = imageURL,
                   animatedURL != staticImageURL || ["gif", "apng", "webp"].contains(animatedURL.pathExtension.lowercased()) {
                    TimelineAnimatedAvatar(url: animatedURL, size: size)
                }
            } else {
                GeneratedAvatar(initials: initials, seed: seed ?? initials, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(theme.colors.primary300, lineWidth: 1)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        MoroAvatar(initials: "NO", size: 36)
        MoroAvatar(
            imageURL: URL(
                string:
                    "https://files.mastodon.social/accounts/avatars/000/000/001/original/d96d39a0abb45b92.jpg"
            ),
            initials: "MO",
            size: 48
        )
    }
}
