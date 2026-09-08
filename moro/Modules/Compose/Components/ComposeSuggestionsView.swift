import SwiftUI

struct ComposeSuggestionsView: View {
    let token: ComposeAutocompleteToken
    @ObservedObject var model: ComposeAutocompleteModel
    let onSelect: (ComposeSuggestion) -> Void
    @Environment(\.moroTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 56

    private var suggestions: [ComposeSuggestion] {
        model.token == token ? model.suggestions : []
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            if suggestions.isEmpty {
                HStack(spacing: 10) {
                    if !token.query.isEmpty && (model.token != token || model.isSearching) {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: token.kind == .account ? "at" : "number")
                            .foregroundStyle(theme.colors.primary500)
                            .accessibilityHidden(true)
                    }
                    Text(message)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, theme.spacing.m)
                .padding(.vertical, 14)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(suggestions) { suggestion in
                            Button { onSelect(suggestion) } label: {
                                suggestionRow(suggestion)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("compose.suggestion.\(suggestion.id)")
                            .overlay(alignment: .bottom) {
                                if suggestion.id != suggestions.last?.id {
                                    theme.colors.divider
                                        .frame(height: 0.5)
                                        .padding(.leading, token.kind == .account ? theme.spacing.m + 46 : theme.spacing.m)
                                        .padding(.trailing, theme.spacing.m)
                                }
                            }
                        }
                    }
                }
                .frame(height: min(CGFloat(suggestions.count) * rowHeight, max(rowHeight, 168)))
                .scrollDismissesKeyboard(.never)
            }
        }
        .background(theme.colors.background)
        .accessibilityIdentifier("compose.suggestions")
    }

    private var message: String {
        if token.query.isEmpty {
            return token.kind == .account
                ? MoroL10n.Compose.suggestionAccountHint : MoroL10n.Compose.suggestionHashtagHint
        }
        if model.token != token || model.isSearching { return MoroL10n.Compose.suggestionSearching }
        return model.searchFailed ? MoroL10n.Compose.suggestionFailed : MoroL10n.Compose.suggestionEmpty
    }

    @ViewBuilder
    private func suggestionRow(_ suggestion: ComposeSuggestion) -> some View {
        HStack(spacing: 10) {
            switch suggestion {
            case .account(let account):
                MoroAvatar(
                    imageURL: account.avatarAnimatedURL,
                    staticImageURL: account.avatarURL,
                    initials: account.displayNameInitials,
                    size: 36
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName.isEmpty ? account.username : account.displayName)
                        .font(theme.typography.body).fontWeight(.semibold)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text("@\(account.acct)")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .truncationMode(.middle)
                }
            case .hashtag(let tag):
                VStack(alignment: .leading, spacing: 2) {
                    Text("#\(tag.name)")
                        .font(theme.typography.body).fontWeight(.semibold)
                        .foregroundStyle(theme.colors.textPrimary)
                    if let activity = tag.activitySummary {
                        Text(activity)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                            .accessibilityIdentifier("compose.suggestion.activity.\(tag.id)")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.horizontal, theme.spacing.m)
        .padding(.vertical, 8)
        .frame(minHeight: rowHeight)
        .contentShape(Rectangle())
    }
}
