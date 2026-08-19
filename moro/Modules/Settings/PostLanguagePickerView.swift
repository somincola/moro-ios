//
//  PostLanguagePickerView.swift
//  moro
//
//  Shared language picker for settings and compose.
//

import SwiftUI

struct PostLanguagePickerView: View {
    @Binding var selectedLanguageCode: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moroTheme) private var theme
    @State private var searchText = ""

    let title: String
    let defaultBehavior: PostLanguageDefaultBehavior
    let showsDismissButton: Bool

    init(
        title: String,
        selectedLanguageCode: Binding<String>,
        defaultBehavior: PostLanguageDefaultBehavior,
        showsDismissButton: Bool = false
    ) {
        self.title = title
        _selectedLanguageCode = selectedLanguageCode
        self.defaultBehavior = defaultBehavior
        self.showsDismissButton = showsDismissButton
    }

    private var filteredOptions: [PostLanguageOption] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return PostLanguageCatalog.options
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return PostLanguageCatalog.options.filter { option in
            option.displayName.localizedCaseInsensitiveContains(query)
                || option.code.localizedCaseInsensitiveContains(query)
                || (option.nativeName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        List {
            Section {
                languageRow(
                    title: PostLanguageCatalog.defaultOptionTitle(for: defaultBehavior),
                    subtitle: nil,
                    code: ""
                )
            }

            Section {
                ForEach(filteredOptions) { option in
                    languageRow(
                        title: option.displayName,
                        subtitle: option.nativeName,
                        code: option.code
                    )
                }
            }
        }
        .moroSettingsListChrome()
        .searchable(text: $searchText, prompt: MoroL10n.Language.searchPrompt)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .navigationBarLeading) {
                    MoroNavigationControlButton(kind: .close) {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func languageRow(title: String, subtitle: String?, code: String) -> some View {
        Button {
            selectedLanguageCode = code
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(theme.colors.textPrimary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }

                Spacer()

                if selectedLanguageCode == code {
                    Image(systemName: "checkmark.circle.fill")
                        .moroScaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(theme.colors.primary500)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
