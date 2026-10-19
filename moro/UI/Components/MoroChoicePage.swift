//
//  MoroChoicePage.swift
//  moro
//
//  Single-choice settings page: the report flow's large heading and quiet hint
//  above one grouped card of title + detail rows with a monochrome selection mark.
//

import SwiftUI

struct MoroChoiceOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var detail: String? = nil

    var id: Value { value }
}

struct MoroChoicePage<Value: Hashable>: View {
    @Environment(\.moroTheme) private var theme

    let heading: String
    var hint: String? = nil
    var footnote: String? = nil
    var errorMessage: String? = nil
    let options: [MoroChoiceOption<Value>]
    let selection: Value
    var isBusy: Bool = false
    var accessibilityPrefix: String? = nil
    let onSelect: (Value) -> Void

    var body: some View {
        MoroSettingsList {
            Section {
                ForEach(options) { option in
                    MoroChoiceRow(
                        title: option.title,
                        detail: option.detail,
                        isSelected: option.value == selection
                    ) {
                        guard option.value != selection else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        onSelect(option.value)
                    }
                    .accessibilityIdentifier(
                        accessibilityPrefix.map { "\($0).\(String(describing: option.value))" } ?? ""
                    )
                }
                .disabled(isBusy)
            } header: {
                header
            } footer: {
                footer
            }
        }
        .moroSettingsListChrome()
        // The large heading names the page; the bar only carries the back button.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isBusy {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                        .accessibilityIdentifier("choicePage.saving")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading)
                .moroScaledFont(size: 26, weight: .semibold, relativeTo: .title)
                .foregroundStyle(theme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let hint {
                Text(hint)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textCase(nil)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var footer: some View {
        if errorMessage != nil || footnote != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .labelStyle(.titleAndIcon)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("choicePage.error")
                }
                if let footnote {
                    Text(footnote)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 4)
        }
    }
}

/// One selectable card row; shares the report reason card's selection mark.
struct MoroChoiceRow: View {
    @Environment(\.moroTheme) private var theme

    let title: String
    let detail: String?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body)
                        .fontWeight(detail == nil ? .regular : .medium)
                        .foregroundStyle(theme.colors.textPrimary)
                    if let detail {
                        Text(detail)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineSpacing(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                MoroSelectionIndicator(isSelected: isSelected)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, detail == nil ? 4 : 8)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Choice · Dark") {
    @Previewable @State var selected = "filter"
    NavigationStack {
        MoroChoicePage(
            heading: "People you don't follow",
            hint: "Accounts you are not following",
            footnote: "The server applies these rules before notifications reach your inbox.",
            options: [
                .init(value: "accept", title: "Accept", detail: "Show in notifications as usual"),
                .init(value: "filter", title: "Filter", detail: "Hold in Filtered notifications for review"),
                .init(value: "drop", title: "Drop", detail: "Don't create the notification"),
            ],
            selection: selected
        ) { selected = $0 }
    }
    .moroTheme(MoroTheme(colorScheme: .dark))
    .preferredColorScheme(.dark)
}
