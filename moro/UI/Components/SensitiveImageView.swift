//
//  SensitiveImageView.swift
//  moro
//
//  Image view with blur effect for sensitive content, with tap to reveal.
//

import SwiftUI

struct SensitiveImageView: View {
    let imageURL: URL?
    let previewURL: URL?
    let isSensitive: Bool
    let maxHeight: CGFloat
    var onTap: (() -> Void)? = nil
    
    @State private var isRevealed: Bool = false
    @Environment(\.moroTheme) private var theme
    @Environment(\.moroMediaPrefs) private var mediaPrefs

    private var isConcealed: Bool {
        mediaPrefs.concealsMedia(markedSensitive: isSensitive) && !isRevealed
    }
    
    init(imageURL: URL?, previewURL: URL?, isSensitive: Bool, maxHeight: CGFloat = 400, onTap: (() -> Void)? = nil) {
        self.imageURL = imageURL
        self.previewURL = previewURL
        self.isSensitive = isSensitive
        self.maxHeight = maxHeight
        self.onTap = onTap
    }
    
    var body: some View {
        ZStack {
            CachedAsyncImage(url: previewURL ?? imageURL) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .blur(radius: isConcealed ? 25 : 0)
                    .clipped()
            } placeholder: {
                Rectangle()
                    .fill(theme.colors.surfaceSubtle)
            }
            
            // Overlay for sensitive content
            if isConcealed {
                VStack(spacing: 12) {
                    Image(systemName: "eye.slash.fill")
                        .moroScaledFont(size: 36, weight: .medium)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                    
                    VStack(spacing: 4) {
                        Text(mediaPrefs.concealLabel(markedSensitive: isSensitive))
                            .font(theme.typography.subtitle)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 2)
                        
                        Text(MoroL10n.SensitiveMedia.tapToView)
                            .font(theme.typography.caption)
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.3), radius: 2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.5))
                .contentShape(Rectangle())
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: maxHeight)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            if isConcealed {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isRevealed = true
                }
                UIAccessibility.post(
                    notification: .announcement,
                    argument: MoroL10n.SensitiveMedia.valueRevealed
                )
            } else {
                onTap?()
            }
        }
        // Collapse the inner ZStack into one tappable element so VoiceOver
        // announces "Sensitive content, hidden, button" instead of reading the
        // overlay's eye-slash icon and labels separately.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(mediaPrefs.concealLabel(markedSensitive: isSensitive)))
        .accessibilityValue(Text(isConcealed ? MoroL10n.SensitiveMedia.valueHidden
                                             : MoroL10n.SensitiveMedia.valueRevealed))
        .accessibilityHint(isConcealed
                           ? Text(MoroL10n.SensitiveMedia.revealHint)
                           : Text(""))
        .accessibilityAddTraits(.isButton)
    }
}

