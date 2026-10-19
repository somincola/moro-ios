//
//  ProfilePlaceholder.swift
//  moro
//
//  What Moro draws for an account that has no avatar or cover of its own. Both come
//  from the same per-account tone, so an empty profile still looks like one person's
//  page instead of a shared pattern.
//

import SDWebImage
import SwiftUI

enum ProfilePlaceholderPalette {
    struct Tone {
        let avatarFill: Color
        let avatarInk: Color
        let headerColors: [Color]
        let highlight: Color
    }

    /// Hues chosen by hand: muted enough to sit beside the monochrome UI, apart
    /// enough that neighbours in a timeline read as different people.
    private static let hues: [Double] = [212, 168, 138, 44, 22, 352, 282, 246]

    static func tone(for seed: String, scheme: ColorScheme) -> Tone {
        let hue = hues[Int(stableHash(seed) % UInt64(hues.count))] / 360
        let shifted = (hue + 0.07).truncatingRemainder(dividingBy: 1)
        switch scheme {
        case .dark:
            return Tone(
                avatarFill: Color(hue: hue, saturation: 0.32, brightness: 0.34),
                avatarInk: Color(hue: hue, saturation: 0.22, brightness: 0.93),
                headerColors: [Color(hue: hue, saturation: 0.38, brightness: 0.30),
                               Color(hue: shifted, saturation: 0.42, brightness: 0.19)],
                highlight: .white.opacity(0.07))
        default:
            return Tone(
                avatarFill: Color(hue: hue, saturation: 0.20, brightness: 0.93),
                avatarInk: Color(hue: hue, saturation: 0.55, brightness: 0.42),
                headerColors: [Color(hue: hue, saturation: 0.12, brightness: 0.97),
                               Color(hue: shifted, saturation: 0.20, brightness: 0.90)],
                highlight: .white.opacity(0.45))
        }
    }

    /// FNV-1a. `String.hashValue` is reseeded every launch, so it can't pick colours.
    static func stableHash(_ seed: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// One CJK character or emoji, or up to two Latin letters.
    static func glyph(from initials: String) -> String {
        let trimmed = initials.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        let pair = trimmed.prefix(2)
        if pair.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
            return pair.uppercased()
        }
        return String(first)
    }
}

extension Account {
    /// Stable across instances: the profile URL names one person everywhere.
    var placeholderSeed: String {
        if let url, !url.isEmpty { return url }
        return acct
    }
}

/// First letter on the account's tone.
struct GeneratedAvatar: View {
    let initials: String
    let seed: String
    let size: CGFloat
    @Environment(\.moroTheme) private var theme

    var body: some View {
        let tone = ProfilePlaceholderPalette.tone(for: seed, scheme: theme.colorScheme)
        let glyph = ProfilePlaceholderPalette.glyph(from: initials)
        Circle()
            .fill(tone.avatarFill)
            .frame(width: size, height: size)
            .overlay {
                Text(glyph)
                    .font(.system(size: size * (glyph.count > 1 ? 0.36 : 0.42), weight: .semibold, design: .rounded))
                    .foregroundStyle(tone.avatarInk)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(size * 0.12)
            }
            .accessibilityHidden(true)
    }
}

/// Cover for an account without one: the avatar, blurred into a wash of its own
/// colours; or, with no avatar either, a soft gradient on the account's tone.
struct ProfileGeneratedHeader: View {
    var avatarURL: URL?
    /// An avatar picked in the editor but not saved yet.
    var avatarImage: UIImage?
    let seed: String
    @Environment(\.moroTheme) private var theme
    @State private var loadedAvatar: UIImage?

    private var avatar: UIImage? { avatarImage ?? loadedAvatar }

    var body: some View {
        let tone = ProfilePlaceholderPalette.tone(for: seed, scheme: theme.colorScheme)
        ZStack {
            LinearGradient(colors: tone.headerColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [tone.highlight, .clear], center: .topLeading, startRadius: 0, endRadius: 320)
            if let avatar {
                // Fixed frame first; the scaled-up image fills it without driving layout.
                Color.clear
                    .overlay {
                        Image(uiImage: avatar)
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 36, opaque: true)
                            .saturation(1.1)
                    }
                    .clipped()
                    .overlay(theme.colorScheme == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.16))
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: avatar != nil)
        .task(id: avatarURL) { await loadAvatar() }
        .accessibilityHidden(true)
    }

    private func loadAvatar() async {
        guard avatarImage == nil, let avatarURL,
              avatarURL.lastPathComponent.lowercased() != "missing.png" else {
            loadedAvatar = nil
            return
        }
        // A small decode is plenty: the image is blurred to a wash anyway.
        let image: UIImage? = await withCheckedContinuation { continuation in
            SDWebImageManager.shared.loadImage(
                with: avatarURL, options: [],
                context: [.imageThumbnailPixelSize: CGSize(width: 96, height: 96)],
                progress: nil
            ) { image, _, _, _, _, _ in
                continuation.resume(returning: image)
            }
        }
        guard !Task.isCancelled else { return }
        loadedAvatar = image
    }
}
