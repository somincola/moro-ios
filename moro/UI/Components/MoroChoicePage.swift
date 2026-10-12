//
//  MoroChoicePage.swift
//  moro
//
//  Single-choice settings page in the report flow's visual language:
//  a large heading, a quiet hint, and hairline-separated title + detail rows
//  with a monochrome selection mark.
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
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(heading)
                        .moroScaledFont(size: 28, weight: .semibold, relativeTo: .title)
                        .foregroundStyle(theme.colors.primary500)
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
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 0) {
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
                }
                .disabled(isBusy)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("choicePage.error")
                }

                if let footnote {
                    Text(footnote)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .background(theme.colors.background)
        // The large heading names the page; the bar only carries the back button.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.colors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if isBusy {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                        .accessibilityIdentifier("choicePage.saving")
                }
            }
        }
    }
}

/// One selectable row; shares the report reason card's proportions and selection mark.
struct MoroChoiceRow: View {
    @Environment(\.moroTheme) private var theme

    let title: String
    let detail: String?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .moroScaledFont(size: 17, weight: .medium)
                        .foregroundStyle(theme.colors.primary500)
                    if let detail {
                        Text(detail)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineSpacing(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ReportSelectionIndicator(isSelected: isSelected)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, detail == nil ? 16 : 20)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .overlay(alignment: .bottom) { MoroDivider() }
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
