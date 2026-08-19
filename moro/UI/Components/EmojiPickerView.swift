//
//  EmojiPickerView.swift
//  moro
//
//  Custom emoji picker for composing posts.
//

import SwiftUI

struct EmojiPickerView: View {
    @ObservedObject var emojiViewModel: CustomEmojiViewModel
    let onEmojiSelected: (String) -> Void

    @State private var searchText: String = ""
    @Environment(\.moroTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.colors.textSecondary)
                TextField(MoroL10n.EmojiPicker.search, text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(theme.spacing.m)
            .background(theme.colors.surfaceSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(theme.spacing.m)

            // Emoji grid
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 50), spacing: theme.spacing.m)
                    ], spacing: theme.spacing.m
                ) {
                    ForEach(filteredEmojis) { emoji in
                        Button(action: {
                            onEmojiSelected(":\(emoji.shortcode): ")
                        }) {
                            MoroNetworkImage(url: emoji.staticURL)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(theme.spacing.m)
            }
        }
        .background(theme.colors.background)
    }

    private var filteredEmojis: [CustomEmoji] {
        guard let emojis = emojiViewModel.emojis else { return [] }

        if searchText.isEmpty {
            return emojis
        }

        // Use trie for autocomplete if available
        if let trie = emojiViewModel.emojiTrie {
            return trie.search(searchText)
        }

        // Fallback to simple filtering
        return emojis.filter { $0.shortcode.localizedCaseInsensitiveContains(searchText) }
    }
}

#Preview {
    // This would need a real emoji view model for preview
    EmojiPickerView(
        emojiViewModel: CustomEmojiViewModel(domain: "example.com", service: EmojiService.shared),
        onEmojiSelected: { _ in }
    )
    .moroTheme(MoroTheme())
}
