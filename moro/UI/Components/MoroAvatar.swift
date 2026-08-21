//
//  MoroAvatar.swift
//  moro
//
//  Circular avatar with CachedAsyncImage caching and fallback initials.
//

import SwiftUI

struct MoroAvatar: View {
    var imageURL: URL?
    var staticImageURL: URL?  // Server-provided static version, preferred in scrolling surfaces
    var initials: String = "MO"  // Kept for backward compatibility but not used by default
    var size: CGFloat = 36

    @Environment(\.moroTheme) private var theme
    @Environment(\.displayScale) private var displayScale

    /// Avatars stay static in scrolling surfaces. Animated avatars create one display link per
    /// visible image and can keep SwiftUI/CA laying out continuously on timeline/profile stacks.
    private var effectiveImageURL: URL? {
        staticImageURL ?? imageURL
    }

    /// Default missing avatar URL from the current instance
    private var defaultAvatarURL: URL? {
        let baseURL = AppEnvironment.apiBaseURL
        return URL(
            string:
                "\(baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/avatars/original/missing.png"
        )
    }

    var body: some View {
        ZStack {
            // Cheap base shown while the image loads (no network).
            theme.colors.primary50

            // One image only: the real avatar, or the instance's missing.png as a
            // fallback. (Previously both were rendered, double-loading every avatar.)
            if let url = effectiveImageURL ?? defaultAvatarURL {
                // Decode at the avatar's on-screen pixel size, not the full ~400px
                // original, so a timeline full of avatars stays light — the decode-time
                // downsampling AlamofireImage's circle filter used to do. The enclosing
                // ZStack handles the frame + circle clip.
                SDWebRemoteImage(
                    url: url,
                    thumbnailPixelSize: size * displayScale,
                    allowsAnimation: false
                )
            } else {
                Text(initials)
                    .font(theme.typography.bodyStrong)
                    .foregroundColor(theme.colors.primary600)
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
