//
//  LinkPreviewCardView.swift
//  moro
//
//  Link Preview Card component for displaying OpenGraph/oEmbed previews.
//  Shown when a status has no media attachments but contains a link with preview data.
//

import SwiftUI

struct LinkPreviewCardView: View {
    let card: Status.PreviewCard
    var onTap: (() -> Void)? = nil

    @Environment(\.moroTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.appRouter) private var router

    private enum Metrics {
        static let cardCornerRadius: CGFloat = 12
        static let compactVisualSize: CGFloat = 96
        static let maxPreviewHeight: CGFloat = 400
        static let textBlockSpacing: CGFloat = 8
        static let contentHorizontalPadding: CGFloat = 12
        static let contentVerticalPadding: CGFloat = 12
        static let providerInlineSpacing: CGFloat = 4
        static let providerFontSize: CGFloat = 12
        static let authorRowSpacing: CGFloat = 8
        static let authorInlineSpacing: CGFloat = 6
        static let authorAvatarSize: CGFloat = 20
        static let authorChipHorizontalPadding: CGFloat = 6
        static let authorChipVerticalPadding: CGFloat = 4
        static let authorChipCornerRadius: CGFloat = 6
        static let placeholderIconSize: CGFloat = 24
    }

    /// Layout type for card display
    enum Layout: Equatable {
        case noPreviewVisual  // No image, only text
        case compact  // Square-ish image, side-by-side layout
        case large(aspectRatio: CGFloat)  // Wide image, vertical layout (image on top, text below)
    }

    /// Determine layout based on card properties
    private var cardLayout: Layout {
        // Check if we have image or HTML
        let hasImage = card.image != nil
        let hasHTML = card.html != nil && !card.html!.isEmpty

        if !hasImage && !hasHTML {
            return .noPreviewVisual
        }

        // Calculate aspect ratio
        var aspectRatio: CGFloat = 1.0
        if let width = card.width, let height = card.height, height > 0 {
            aspectRatio = CGFloat(width) / CGFloat(height)
            if !aspectRatio.isFinite {
                aspectRatio = 1.0
            }
        }

        // If image is close to square (aspect ratio ~1) or no image, use compact layout
        // Otherwise use large layout (vertical: image on top, text below)
        if (abs(aspectRatio - 1.0) < 0.05 || !hasImage) && !hasHTML {
            return .compact
        } else {
            return .large(aspectRatio: aspectRatio)
        }
    }

    var body: some View {
        Button(action: {
            if let handler = onTap {
                handler()
            } else {
                openURL(card.url)
            }
        }) {
            cardContent
        }
        .buttonStyle(.plain)
        // Collapse the title/desc/host stack into one element so VoiceOver
        // announces "Title, Provider" once and identifies it as a link, instead
        // of swiping through each text fragment.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(MoroL10n.LinkPreview.cardLabel(
            card.title,
            card.providerName ?? card.url.host ?? ""
        )))
        .accessibilityAddTraits(.isLink)
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(spacing: 0) {
            // Main content area
            switch cardLayout {
            case .large(let aspectRatio):
                largeLayout(aspectRatio: aspectRatio)
            case .compact:
                compactLayout
            case .noPreviewVisual:
                textContentStack
                    .frame(maxWidth: .infinity)
            }

            // Author information (if available)
            if shouldShowAuthor {
                Divider()
                authorMolecule
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(theme.colors.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardCornerRadius)
                .stroke(theme.colors.divider, lineWidth: 1)
        )
    }

    // MARK: - Large Layout (Vertical: Image on top, text below)

    @ViewBuilder
    private func largeLayout(aspectRatio: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image on top
            if let imageURL = card.image {
                previewVisual(imageURL: imageURL, aspectRatio: aspectRatio)
                    .frame(maxWidth: .infinity)  // Ensure image doesn't exceed container width

                // Divider between image and text
                Divider()
            }

            // Text content below
            textContentStack
        }
        .frame(maxWidth: .infinity, alignment: .leading)  // Ensure entire layout doesn't exceed container
    }

    // MARK: - Compact Layout (Horizontal: Image on left, text on right)

    @ViewBuilder
    private var compactLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            // Image on left
            if let imageURL = card.image {
                previewVisual(
                    imageURL: imageURL,
                    aspectRatio: 1.0,
                    compactHeight: Metrics.compactVisualSize
                )
                    .frame(width: Metrics.compactVisualSize, height: Metrics.compactVisualSize)
                    .clipped()  // Ensure image doesn't overflow
            }

            // Divider between image and text
            if card.image != nil {
                Divider()
            }

            // Text content on right (no description in compact layout)
            compactTextContent
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)  // Ensure layout doesn't exceed container
    }

    // MARK: - Preview Visual

    @ViewBuilder
    private func previewVisual(imageURL: URL, aspectRatio: CGFloat, compactHeight: CGFloat? = nil)
        -> some View
    {
        if let compactHeight = compactHeight {
            // Compact layout: fixed size
            MoroNetworkImage(url: imageURL)
                .frame(width: compactHeight, height: compactHeight)
                .clipped()
        } else {
            // Large layout: use aspect ratio with max height limit
            // Keep large previews bounded so they do not dominate the timeline.
            let validAspectRatio = aspectRatio > 0 ? aspectRatio : 1.0

            MoroNetworkImage(url: imageURL)
                .aspectRatio(validAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: Metrics.maxPreviewHeight)
                .clipped()
        }
    }

    // MARK: - Text Content Stack

    @ViewBuilder
    private var textContentStack: some View {
        VStack(alignment: .leading, spacing: Metrics.textBlockSpacing) {
            // Provider name and published date
            publisherAttributionMolecule

            // Title
            if !card.title.isEmpty {
                Text(card.title)
                    .font(theme.typography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)  // Limit title to 3 lines
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Description (only for large and noPreviewVisual layouts)
            if case .large = cardLayout, !card.description.isEmpty {
                Text(card.description)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else if case .noPreviewVisual = cardLayout, !card.description.isEmpty {
                Text(card.description)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Metrics.contentHorizontalPadding)
        .padding(.vertical, Metrics.contentVerticalPadding)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Compact Text Content (no description)

    @ViewBuilder
    private var compactTextContent: some View {
        VStack(alignment: .leading, spacing: Metrics.textBlockSpacing) {
            // Provider name and published date
            publisherAttributionMolecule

            // Title only (no description in compact layout)
            if !card.title.isEmpty {
                Text(card.title)
                    .font(theme.typography.subtitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Metrics.contentHorizontalPadding)
        .padding(.vertical, Metrics.contentVerticalPadding)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Publisher Attribution

    @ViewBuilder
    private var publisherAttributionMolecule: some View {
        if let providerName = card.providerName, !providerName.isEmpty {
            HStack(spacing: Metrics.providerInlineSpacing) {
                Text(providerName)
                    .moroScaledFont(size: Metrics.providerFontSize, weight: .medium)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)

                if let formattedDate = card.formattedPublishedDate {
                    Text("·")
                        .moroScaledFont(size: Metrics.providerFontSize)
                        .foregroundStyle(theme.colors.textSecondary)
                    Text(formattedDate)
                        .moroScaledFont(size: Metrics.providerFontSize)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Author Molecule

    private var shouldShowAuthor: Bool {
        if let authors = card.authors, !authors.isEmpty {
            return authors.first?.account != nil
                || (authors.first?.name != nil && !authors.first!.name!.isEmpty)
        }
        return card.authorName != nil && !card.authorName!.isEmpty
    }

    @ViewBuilder
    private var authorMolecule: some View {
        HStack(spacing: Metrics.authorRowSpacing) {
            if let author = card.authors?.first, let account = author.account {
                // Author has a Mastodon account
                HStack(spacing: Metrics.authorInlineSpacing) {
                    MoroAvatar(
                        imageURL: account.avatarAnimatedURL,
                        staticImageURL: account.avatarURL,
                        initials: account.displayNameInitials,
                        size: Metrics.authorAvatarSize
                    )

                    AccountDisplayNameView(
                        account: account,
                        typography: .caption,
                        textColor: theme.colors.textPrimary,
                        lineLimit: 1
                    )
                }
                .padding(.horizontal, Metrics.authorChipHorizontalPadding)
                .padding(.vertical, Metrics.authorChipVerticalPadding)
                .background(theme.colors.surfaceSubtle.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: Metrics.authorChipCornerRadius))
                .onTapGesture {
                    router.navigate(to: .userProfile(account))
                }
            } else if let author = card.authors?.first, let authorName = author.name,
                !authorName.isEmpty
            {
                // Author name only (no account)
                Text(MoroL10n.LinkPreview.byAuthor(authorName))
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
            } else if let authorName = card.authorName, !authorName.isEmpty {
                // Fallback to deprecated authorName field
                Text(MoroL10n.LinkPreview.byAuthor(authorName))
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
            } else if let host = card.url.host {
                // Fallback to URL host
                Text(host)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, Metrics.contentHorizontalPadding)
        .padding(.vertical, Metrics.textBlockSpacing)
    }

    // MARK: - Placeholder

    private var imagePlaceholder: some View {
        Rectangle()
            .fill(theme.colors.surfaceSubtle)
            .overlay {
                Image(systemName: "link")
                    .moroScaledFont(size: Metrics.placeholderIconSize)
                    .foregroundStyle(theme.colors.textSecondary.opacity(0.5))
            }
    }
}

// MARK: - Compact Link Preview (for smaller spaces)

struct CompactLinkPreviewView: View {
    let card: Status.PreviewCard
    var onTap: (() -> Void)? = nil

    @Environment(\.moroTheme) private var theme
    @Environment(\.openURL) private var openURL
    
    private enum Metrics {
        static let rowSpacing: CGFloat = 8
        static let linkIconSize: CGFloat = 14
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 8
        static let cornerRadius: CGFloat = 8
    }

    var body: some View {
        Button(action: {
            if let handler = onTap {
                handler()
            } else {
                openURL(card.url)
            }
        }) {
            HStack(spacing: Metrics.rowSpacing) {
                Image(systemName: "link")
                    .moroScaledFont(size: Metrics.linkIconSize, weight: .medium)
                    .foregroundStyle(theme.colors.primary500)

                Text(card.displayProviderName)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)

                if !card.title.isEmpty {
                    Text("·")
                        .foregroundStyle(theme.colors.textSecondary)

                    Text(card.title)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, Metrics.horizontalPadding)
            .padding(.vertical, Metrics.verticalPadding)
            .background(theme.colors.surfaceSubtle)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(MoroL10n.LinkPreview.cardLabel(
            card.title,
            card.providerName ?? card.url.host ?? ""
        )))
        .accessibilityAddTraits(.isLink)
    }
}

#Preview {
    let sampleCard = Status.PreviewCard(
        url: URL(string: "https://apple.com")!,
        title: "Apple - Official Site",
        description:
            "Discover the innovative world of Apple and shop everything iPhone, iPad, Apple Watch, Mac, and Apple TV.",
        type: .link,
        authorName: nil,
        authorURL: nil,
        providerName: "apple.com",
        providerURL: nil,
        html: nil,
        width: 728,
        height: 317,
        image: URL(string: "https://www.apple.com/ac/structured-data/images/open_graph_logo.png"),
        embedURL: nil,
        blurhash: nil
    )

    return VStack(spacing: 20) {
        LinkPreviewCardView(card: sampleCard)

        CompactLinkPreviewView(card: sampleCard)
    }
    .padding()
    .moroTheme(MoroTheme())
}
