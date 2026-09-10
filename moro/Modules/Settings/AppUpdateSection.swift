import SwiftUI

struct AppUpdateSection: View {
    @ObservedObject var store: AppUpdateStore
    @Environment(\.moroTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent(MoroL10n.AppSupport.currentVersion, value: store.currentVersion)
            if let release = store.latestRelease {
                LabeledContent(MoroL10n.AppSupport.latestVersion, value: release.version)
            }
            if store.state == .failed {
                Text(MoroL10n.AppSupport.checkFailed).foregroundStyle(theme.colors.textSecondary)
            } else if store.state == .unavailable {
                Text(MoroL10n.AppSupport.unavailable).foregroundStyle(theme.colors.textSecondary)
            } else if store.state == .checked && !store.hasUpdate {
                Label(MoroL10n.AppSupport.upToDate, systemImage: "checkmark.circle")
                    .foregroundStyle(theme.colors.textSecondary)
            }
            HStack {
                Button {
                    Task { await store.check(force: true) }
                } label: {
                    if store.state == .checking {
                        ProgressView().accessibilityLabel(MoroL10n.AppSupport.checking)
                    } else { Text(MoroL10n.AppSupport.checkUpdates) }
                }
                .disabled(store.state == .checking)
                .accessibilityIdentifier("about.checkUpdates")
                Spacer()
                if store.hasUpdate {
                    Link(destination: MoroAppStore.productURL) {
                        Label(MoroL10n.AppSupport.update, systemImage: "arrow.up.right")
                    }
                    .accessibilityIdentifier("about.update")
                }
            }
            .padding(.top, 4)
        }
        .font(.subheadline)
        .padding(16)
        .background(theme.colors.surfaceSubtle, in: RoundedRectangle(cornerRadius: 14))
    }
}
