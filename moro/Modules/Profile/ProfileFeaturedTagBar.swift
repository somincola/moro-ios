import SwiftUI

struct ProfileFeaturedTagBar: View {
    @Environment(\.moroTheme) private var theme
    let tags: [FeaturedTag]
    let selection: String?
    let onSelect: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.id) { (tag: FeaturedTag) in
                    let selected = selection == tag.name
                    Button { onSelect(selected ? nil : tag.name) } label: {
                        Text("#\(tag.name)")
                            .font(theme.typography.caption.weight(.medium))
                            .foregroundStyle(selected ? theme.colors.primaryForeground : theme.colors.textSecondary)
                            .fixedSize()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .frame(minHeight: 30)
                            .background(selected ? theme.colors.primary500 : theme.colors.primary50, in: Capsule())
                            // Keep the compact capsule inside a comfortable tap target.
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                    .accessibilityIdentifier("profile.featuredTag.\(tag.name)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("profile.featuredTags.filters")
    }
}
