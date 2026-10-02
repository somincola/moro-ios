import SwiftUI

struct OpenSourceLicensesView: View {
    @Environment(\.moroTheme) private var theme

    var body: some View {
        List(ThirdPartyLicense.all) { license in
            NavigationLink {
                OpenSourceLicenseDetailView(license: license)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: license.name)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(MoroL10n.About.mitLicense)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .padding(.vertical, 6)
            }
            .accessibilityIdentifier("about.license.\(license.name)")
        }
        .moroSettingsListChrome()
        .navigationTitle(MoroL10n.About.openSourceLicenses)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OpenSourceLicenseDetailView: View {
    @Environment(\.moroTheme) private var theme
    let license: ThirdPartyLicense

    private var noticeText: String {
        // Reflow source-file line wrapping while keeping notices and paragraphs intact.
        license.notice.components(separatedBy: "\n\n")
            .map { paragraph in
                paragraph.hasPrefix("Copyright")
                    ? paragraph : paragraph.replacingOccurrences(of: "\n", with: " ")
            }
            .joined(separator: "\n\n")
    }

    var body: some View {
        ScrollView {
            Text(verbatim: noticeText)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(theme.spacing.xl)
        }
        .background(theme.colors.background)
        .navigationTitle(license.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.colors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
