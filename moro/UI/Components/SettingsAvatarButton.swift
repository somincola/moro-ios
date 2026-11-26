import SwiftUI

struct SettingsAvatarButton: View {
    @Environment(\.moroTheme) private var theme
    let account: Account
    /// In a system toolbar the bar draws the button's backdrop, so only the avatar is drawn.
    var isToolbarItem = false
    var showsUnreadDot = false
    var accessibilityLabelText: String = MoroL10n.Navigation.openMenu
    let action: () -> Void

    init(
        account: Account,
        isToolbarItem: Bool = false,
        showsUnreadDot: Bool = false,
        accessibilityLabelText: String = MoroL10n.Navigation.openMenu,
        action: @escaping () -> Void
    ) {
        self.account = account
        self.isToolbarItem = isToolbarItem
        self.showsUnreadDot = showsUnreadDot
        self.accessibilityLabelText = accessibilityLabelText
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
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

                if showsUnreadDot {
                    Circle()
                        .fill(theme.colors.error)
                        .frame(width: 8, height: 8)
                        .overlay {
                            Circle()
                                .strokeBorder(theme.colors.surfaceBase, lineWidth: 1.5)
                        }
                        .offset(x: 1, y: 1)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: isToolbarItem ? 36 : 44, height: isToolbarItem ? 36 : 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityIdentifier("home.drawerButton")
    }
}
