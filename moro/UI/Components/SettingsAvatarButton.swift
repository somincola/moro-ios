import SwiftUI

struct SettingsAvatarButton: View {
    @Environment(\.moroTheme) private var theme
    let account: Account
    /// In a system toolbar the bar draws the button's backdrop, so only the avatar is drawn.
    var isToolbarItem = false
    let action: () -> Void

    init(account: Account, isToolbarItem: Bool = false, action: @escaping () -> Void) {
        self.account = account
        self.isToolbarItem = isToolbarItem
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if !isToolbarItem {
                    Circle().fill(theme.colors.surfaceSubtle).frame(width: 38, height: 38)
                }
                MoroAvatar(
                    imageURL: account.avatarAnimatedURL,
                    staticImageURL: account.avatarURL,
                    initials: account.displayNameInitials, seed: account.placeholderSeed,
                    size: isToolbarItem ? 30 : 32
                )
            }
            .frame(width: isToolbarItem ? 36 : 44, height: isToolbarItem ? 36 : 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MoroL10n.Navigation.settings)
    }
}
