import SwiftUI

/// Equal-width page tabs with a short accent underline under the selected title.
struct MoroSectionTabBar<Tab: Hashable>: View {
    @Environment(\.moroTheme) private var theme

    let tabs: [Tab]
    let selection: Tab
    let title: (Tab) -> String
    let accessibilityIdentifier: (Tab) -> String
    let onSelect: (Tab) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                let selected = selection == tab
                Button {
                    onSelect(tab)
                } label: {
                    VStack(spacing: 0) {
                        Text(verbatim: title(tab))
                            .font(theme.typography.body)
                            .fontWeight(selected ? .semibold : .regular)
                            .foregroundStyle(selected ? theme.colors.textPrimary : theme.colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, theme.spacing.sm)

                        Capsule()
                            .fill(selected ? theme.colors.primary500 : .clear)
                            .frame(width: 36, height: 2.5)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .bottom)
                    .padding(.top, theme.spacing.m)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier(accessibilityIdentifier(tab))
            }
        }
        .padding(.horizontal, theme.spacing.contentHorizontalInset)
        .background(theme.colors.surfaceBase)
    }
}
