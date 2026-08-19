//
//  AltTextOverlay.swift
//  moro
//
//  Modal overlay for displaying full image alt text.
//

import SwiftUI

struct AltTextOverlay: View {
    let altText: String
    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.moroTheme) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack(spacing: 8) {
                        Image(systemName: "text.below.photo")
                            .moroScaledFont(size: 20, weight: .medium)
                            .foregroundStyle(theme.colors.primary500)

                        Text(MoroL10n.AltOverlay.title)
                            .font(theme.typography.title)
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.colors.textPrimary)
                    }
                    .padding(.bottom, 8)
                    
                    // Alt text content
                    Text(altText)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                    
                    Spacer(minLength: 20)
                }
                .padding(20)
            }
            .background(theme.colors.background)
            .navigationTitle(MoroL10n.AltOverlay.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        dismiss()
                        onDismiss?()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .moroScaledFont(size: 24)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
            }
        }
    }
}

// Alternative compact overlay for inline display
struct AltTextCompactOverlay: View {
    let altText: String
    var onDismiss: (() -> Void)? = nil
    
    @Environment(\.moroTheme) private var theme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with close button
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "text.below.photo")
                        .moroScaledFont(size: 14, weight: .medium)
                    Text(MoroL10n.ImagePreview.altBadge)
                        .font(theme.typography.caption)
                        .fontWeight(.bold)
                }
                .foregroundStyle(.white)
                
                Spacer()
                
                Button(action: { onDismiss?() }) {
                    Image(systemName: "xmark")
                        .moroScaledFont(size: 12, weight: .bold)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(6)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            
            // Alt text
            Text(altText)
                .font(theme.typography.body)
                .foregroundStyle(.white)
                .lineSpacing(4)
                .lineLimit(10)
        }
        .padding(16)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    VStack {
        AltTextOverlay(
            altText: "A beautiful sunset over the ocean, with vibrant orange and pink hues reflecting off the calm water. Several seagulls can be seen flying in the distance against the colorful sky. The silhouette of a lighthouse is visible on the horizon."
        )
    }
    .moroTheme(MoroTheme())
}
