// A content-sized reading sheet for image descriptions.

import SwiftUI

struct AltTextOverlay: View {
    let altText: String
    let maximumInitialHeight: CGFloat

    @Environment(\.dismiss) private var dismiss
    @Environment(\.moroTheme) private var theme
    @State private var headerHeight: CGFloat = 72
    @State private var contentHeight: CGFloat = 0

    private var detents: Set<PresentationDetent> {
        // The floor only keeps a one-word description from becoming a sliver; above it,
        // the sheet hugs its text so short descriptions don't leave empty space below.
        let limit = max(140, maximumInitialHeight)
        let fittedHeight = ceil(max(120, headerHeight + contentHeight))
        if fittedHeight > limit {
            return [.height(limit), .large]
        }
        return [.height(fittedHeight)]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }

            ScrollView {
                Text(altText)
                    .moroScaledFont(size: 17, relativeTo: .body)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("imagePreview.altText")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("imagePreview.altScroll")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("imagePreview.altSheet")
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
        .presentationBackground(theme.colors.surfaceBase)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(MoroL10n.AltOverlay.title)
                .moroScaledFont(size: 17, weight: .semibold, relativeTo: .headline)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("imagePreview.altTitle")

            Spacer(minLength: 0)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(theme.colors.textSecondary.opacity(0.12), in: Circle())
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(MoroNavigationControlKind.close.accessibilityLabel)
            .accessibilityIdentifier("imagePreview.altClose")
        }
        .padding(.leading, 20)
        .padding(.trailing, 11)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

#Preview {
    AltTextOverlay(
        altText: "夕阳映在海面上，几只海鸥掠过粉橙色的天空，远处是灯塔的剪影。",
        maximumInitialHeight: 480
    )
    .moroTheme(MoroTheme())
}
