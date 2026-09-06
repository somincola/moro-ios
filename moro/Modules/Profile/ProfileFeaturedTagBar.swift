import SwiftUI

struct ProfileFeaturedTagBar: View {
    @Environment(\.moroTheme) private var theme
    let tags: [FeaturedTag]
    let selection: String?
    let onSelect: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.id) { (tag: FeaturedTag) in
                    let selected = selection == tag.name
                    Button { onSelect(selected ? nil : tag.name) } label: {
                        HStack(spacing: 5) {
                            Text("#\(tag.name)")
                            if selected { Image(systemName: "checkmark").font(.caption.weight(.semibold)) }
                        }
                        .font(theme.typography.caption)
                        .foregroundStyle(selected ? theme.colors.textPrimary : theme.colors.textSecondary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(selected ? theme.colors.surfaceSubtle : Color.clear, in: Capsule())
                        .overlay(Capsule().stroke(selected ? theme.colors.textSecondary : theme.colors.borderSubtle, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                    .accessibilityIdentifier("profile.featuredTag.\(tag.name)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("profile.featuredTags.filters")
    }
}
