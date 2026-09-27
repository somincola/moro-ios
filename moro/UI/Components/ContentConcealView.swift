//
//  ContentConcealView.swift
//  moro
//
//  Content warning and concealment overlay.
//  Supports two-layer concealment: filter warnings and content warnings (CW).
//

import SwiftUI
import Combine

fileprivate enum ContentConcealMetrics {
    static let sectionSpacing: CGFloat = 8
    static let toggleInlineSpacing: CGFloat = 4
    static let bannerHorizontalPadding: CGFloat = 12
    static let bannerVerticalPadding: CGFloat = 8
    static let filterIconSize: CGFloat = 14
    static let chevronSize: CGFloat = 10
}

final class ContentConcealViewModel: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    @Published private(set) var statusID: String
    @Published private(set) var hasContentWarning: Bool
    @Published private(set) var hasFilterWarning: Bool
    @Published private(set) var spoilerText: String?
    @Published private(set) var filterWarningText: String?
    @Published private(set) var isFilterRevealed: Bool
    @Published private(set) var isContentRevealed: Bool

    init(
        statusID: String,
        hasContentWarning: Bool,
        hasFilterWarning: Bool = false,
        spoilerText: String?,
        filterWarningText: String? = nil
    ) {
        self.statusID = statusID
        self.hasContentWarning = hasContentWarning
        self.hasFilterWarning = hasFilterWarning
        self.spoilerText = spoilerText
        self.filterWarningText = filterWarningText
        self.isFilterRevealed = !hasFilterWarning
        self.isContentRevealed = !hasContentWarning && !hasFilterWarning
    }

    func sync(
        statusID: String,
        hasContentWarning: Bool,
        hasFilterWarning: Bool,
        spoilerText: String?,
        filterWarningText: String?
    ) {
        // Different status means a new post cell context: reset conceal state.
        if self.statusID != statusID {
            self.statusID = statusID
            self.hasContentWarning = hasContentWarning
            self.hasFilterWarning = hasFilterWarning
            self.spoilerText = spoilerText
            self.filterWarningText = filterWarningText
            self.isFilterRevealed = !hasFilterWarning
            self.isContentRevealed = !hasContentWarning && !hasFilterWarning
            return
        }

        let previousHasContentWarning = self.hasContentWarning
        let previousHasFilterWarning = self.hasFilterWarning

        self.hasContentWarning = hasContentWarning
        self.hasFilterWarning = hasFilterWarning
        self.spoilerText = spoilerText
        self.filterWarningText = filterWarningText

        // If warnings are removed, reveal content by default.
        if !hasFilterWarning {
            isFilterRevealed = true
        } else if !previousHasFilterWarning {
            // Newly applied filter warning starts concealed.
            isFilterRevealed = false
        }

        if !hasContentWarning && !hasFilterWarning {
            isContentRevealed = true
        } else if hasContentWarning && !previousHasContentWarning {
            // Newly applied CW starts concealed.
            isContentRevealed = false
        }
    }
    
    func revealFilteredContent() {
        isFilterRevealed = true
        if !hasContentWarning {
            isContentRevealed = true
        }
    }

    func toggleContentWarning() {
        isContentRevealed.toggle()
    }
}

struct ContentConcealView<Content: View>: View {
    @ObservedObject var viewModel: ContentConcealViewModel
    let content: () -> Content
    
    @Environment(\.moroTheme) private var theme
    
    var body: some View {
        Group {
            if viewModel.hasFilterWarning && !viewModel.isFilterRevealed {
                filterWarningBanner
            } else if viewModel.hasContentWarning {
                contentWarningSection
            } else {
                content()
            }
        }
    }

    @ViewBuilder
    private var filterWarningBanner: some View {
        HStack {
            Image(systemName: "eye.slash")
                .moroScaledFont(size: ContentConcealMetrics.filterIconSize, weight: .medium)
            Text(viewModel.filterWarningText ?? "Filtered")
                .font(theme.typography.caption)
                .fontWeight(.medium)
            Spacer()
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.revealFilteredContent()
                }
            }) {
                Text(MoroL10n.SensitiveMedia.showAnyway)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.primary500)
            }
        }
        .foregroundStyle(theme.colors.textSecondary)
        .padding(.horizontal, ContentConcealMetrics.bannerHorizontalPadding)
        .padding(.vertical, ContentConcealMetrics.bannerVerticalPadding)
        .background(theme.colors.surfaceSubtle)
    }

    @ViewBuilder
    private var contentWarningSection: some View {
        VStack(alignment: .leading, spacing: ContentConcealMetrics.sectionSpacing) {
            // Fixed title - always visible with bold font (weight 600)
            if let spoilerText = viewModel.spoilerText, !spoilerText.isEmpty {
                Text(spoilerText)
                    .font(theme.typography.body)
                    .fontWeight(.semibold) // SwiftUI semibold is approximately 600
                    .foregroundStyle(theme.colors.textPrimary)
            } else {
                Text(MoroL10n.SensitiveMedia.contentWarning)
                    .font(theme.typography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.colors.textPrimary)
            }

            // Fixed toggle button - always in same position
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.toggleContentWarning()
                }
            }) {
                HStack(spacing: ContentConcealMetrics.toggleInlineSpacing) {
                    Text(viewModel.isContentRevealed ? "Show less" : "Show more")
                        .font(theme.typography.caption)
                        .fontWeight(.medium)
                    Image(systemName: viewModel.isContentRevealed ? "chevron.up" : "chevron.down")
                        .moroScaledFont(size: ContentConcealMetrics.chevronSize, weight: .medium)
                }
                .foregroundStyle(theme.colors.primary500)
            }

            // Content area - animated reveal/conceal
            if viewModel.isContentRevealed {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .animation(.easeInOut(duration: 0.2), value: viewModel.isContentRevealed)
    }
}
