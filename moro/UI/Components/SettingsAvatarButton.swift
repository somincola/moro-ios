import SwiftUI

struct SettingsAvatarButton: View {
    @Environment(\.moroTheme) private var theme
    let account: Account
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(theme.colors.surfaceSubtle).frame(width: 38, height: 38)
                MoroAvatar(
                    imageURL: account.avatarAnimatedURL,
                    staticImageURL: account.avatarURL,
                    initials: account.displayNameInitials, seed: account.placeholderSeed,
                    size: 32
                )
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MoroL10n.Navigation.settings)
    }
}
