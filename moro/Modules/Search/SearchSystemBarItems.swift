//
//  SearchSystemBarItems.swift
//  moro
//
//  iPhone Duo: Explore's search button and scopes in the system bar.
//

import Combine
import SwiftUI

/// The controller's search state, as the system bar shows it.
@MainActor
final class SearchChromeBridge: ObservableObject {
    @Published var isExpanded = false
    @Published var scope: SearchViewModel.Scope = .accounts
    /// A search has been run; its scope's icon is drawn at full weight.
    @Published var hasResults = false
    weak var controller: SearchCoreViewController?

    // iOS 26.0–26.2 crash releasing a main-actor object off the main thread.
    nonisolated deinit {}
}

/// A search button (a close button once open, with the field below in the page), then the
/// scopes: named in a bar across the top, icons in the side bar.
struct SearchSystemBarItems: ToolbarContent {
    @ObservedObject var bridge: SearchChromeBridge
    let isVertical: Bool
    let theme: MoroTheme

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if bridge.isExpanded {
                Button {
                    bridge.controller?.collapseSearchFromBar()
                } label: {
                    Label(MoroL10n.Common.close, systemImage: "xmark")
                }
                .accessibilityIdentifier("search.bar.close")
            } else {
                Button {
                    bridge.controller?.expandSearchFromBar()
                } label: {
                    Label(MoroL10n.Search.placeholder, systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("search.bar.open")
            }
        }
        if isVertical {
            // Custom views stay out of the side bar unless they ask to join it.
            VerticalPreferredToolbarItem(placement: .topBarLeading) { scopeIconButton(.accounts) }
            VerticalPreferredToolbarItem(placement: .topBarLeading) { scopeIconButton(.statuses) }
            VerticalPreferredToolbarItem(placement: .topBarLeading) { scopeIconButton(.hashtags) }
        } else {
            // Named tabs whether or not search is open, like Notifications' filters.
            ToolbarItem(placement: .principal) {
                HStack(spacing: 0) {
                    ForEach(SearchViewModel.Scope.exploreScopes, id: \.self) { scope in
                        scopeTitleButton(scope)
                    }
                }
            }
        }
    }

    private func isSelected(_ scope: SearchViewModel.Scope) -> Bool {
        bridge.scope.exploreScope == scope
    }

    private func scopeTitleButton(_ scope: SearchViewModel.Scope) -> some View {
        let selected = isSelected(scope)
        return Button {
            bridge.controller?.selectScopeFromBar(scope)
        } label: {
            Text(scope.title)
                .font(theme.typography.body)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(selected ? theme.colors.textPrimary : theme.colors.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selected ? theme.colors.textPrimary : .clear)
                        .frame(width: 24, height: 2)
                        .padding(.bottom, 4)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("search.bar.scope.\(scope.rawValue)")
    }

    private func scopeIconButton(_ scope: SearchViewModel.Scope) -> some View {
        let selected = isSelected(scope)
        // The scope searched in reads darkest; before a search the choice is still marked.
        let color = selected
            ? (bridge.hasResults ? theme.colors.textPrimary : theme.colors.textSecondary)
            : theme.colors.textTertiary
        return Button {
            bridge.controller?.selectScopeFromBar(scope)
        } label: {
            Label(scope.title, systemImage: scope.barIcon(filled: selected))
                .labelStyle(.iconOnly)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(color)
                .frame(minWidth: 36, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("search.bar.scope.\(scope.rawValue)")
    }
}

extension SearchViewModel.Scope {
    func barIcon(filled: Bool) -> String {
        switch exploreScope {
        case .statuses: return filled ? "text.bubble.fill" : "text.bubble"
        case .hashtags: return "number"
        default: return filled ? "person.2.fill" : "person.2"
        }
    }
}
