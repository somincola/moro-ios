import SwiftUI

struct SearchEntryView: View {
    @Environment(\.moroTheme) private var theme
    @ObservedObject var library: SearchLibraryStore
    let query: String
    let onSubmit: (String, SearchViewModel.Scope?) -> Void
    let onManage: () -> Void

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var savedMatches: [SearchLibraryItem] { library.saved.filter(matches) }
    private var recentMatches: [SearchLibraryItem] { library.recent.filter(matches) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.l) {
                if !trimmed.isEmpty {
                    Button { onSubmit(trimmed, nil) } label: {
                        Label(MoroL10n.Search.searchFor(trimmed), systemImage: "magnifyingglass")
                            .font(theme.typography.body)
                            .foregroundStyle(theme.colors.primary500)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("search.submitQuery")
                } else {
                    Text(MoroL10n.Search.entryHint)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                }

                if trimmed.isEmpty || !savedMatches.isEmpty {
                    VStack(spacing: 0) {
                        sectionHeader(MoroL10n.Search.savedTitle, action: MoroL10n.Search.manageSaved, id: "search.manageSaved", perform: onManage)
                        let items = savedMatches
                        if items.isEmpty, trimmed.isEmpty {
                            emptyText(MoroL10n.Search.noSaved)
                        }
                        ForEach(items) { item in
                            itemRow(item, symbol: "bookmark", isRecent: false)
                        }
                    }
                }

                if trimmed.isEmpty || !recentMatches.isEmpty {
                    VStack(spacing: 0) {
                        sectionHeader(MoroL10n.Search.recentTitle, action: library.recent.isEmpty ? nil : MoroL10n.Search.clearRecent, id: "search.clearRecent", perform: library.clearRecent)
                        let items = recentMatches
                        if items.isEmpty, trimmed.isEmpty {
                            emptyText(MoroL10n.Search.noRecent)
                        }
                        ForEach(items) { item in
                            itemRow(item, symbol: "clock", isRecent: true)
                        }
                    }
                }
            }
            .padding(.horizontal, SearchLayoutMetrics.contentHorizontalInset)
            .padding(.vertical, theme.spacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.colors.surfaceBase)
        .accessibilityIdentifier("search.entry")
    }

    private func matches(_ item: SearchLibraryItem) -> Bool {
        trimmed.isEmpty || item.query.localizedCaseInsensitiveContains(trimmed)
            || item.name.localizedCaseInsensitiveContains(trimmed)
    }

    private func sectionHeader(_ title: String, action: String?, id: String, perform: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(theme.typography.subtitle)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: theme.spacing.s)
            if let action {
                Button(action, action: perform)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(id)
            }
        }
        .frame(minHeight: 44)
    }

    private func emptyText(_ value: String) -> some View {
        Text(value)
            .font(theme.typography.caption)
            .foregroundStyle(theme.colors.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func itemRow(_ item: SearchLibraryItem, symbol: String, isRecent: Bool) -> some View {
        HStack(spacing: theme.spacing.s) {
            Button { onSubmit(item.query, item.scope) } label: {
                HStack(spacing: theme.spacing.m) {
                    Image(systemName: symbol)
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(theme.typography.body)
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(2)
                        Text(item.scope.title)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("search.\(isRecent ? "recent" : "saved").\(item.query)")
            if isRecent {
                Button { library.removeRecent(id: item.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.colors.textTertiary)
                .accessibilityLabel("\(MoroL10n.Common.delete) \(item.query)")
            }
        }
        .padding(.vertical, theme.spacing.xs)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.colors.borderSubtle).frame(height: 0.5)
        }
    }
}
