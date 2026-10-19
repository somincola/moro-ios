//
//  AboutView.swift
//  moro
//
//  Product information, links, and third-party licenses.
//

import SwiftUI
import UIKit

struct AboutView: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.settingsContext) private var settingsContext
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .body) private var iconColumnWidth = MoroSettingsMetrics.iconColumnWidth

    private let githubURL = URL(string: "https://github.com/somincola/moro-ios")!

    private var appTitle: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            !version.isEmpty
        else { return "Moro" }
        return "Moro (\(version))"
    }

    var body: some View {
        MoroSettingsList {
            Section {
                hero
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowSeparator(.hidden)
            }

            Section {
                Button {
                    if let openAccount = settingsContext.onOpenAccount {
                        openAccount(MoroBrand.authorAcct)
                    } else {
                        openURL(MoroBrand.authorProfileURL)
                    }
                } label: {
                    rowLabel(
                        title: MoroL10n.About.followAuthor,
                        systemImage: "person.crop.circle.badge.plus",
                        accessory: "chevron.right",
                        value: "@acacius"
                    )
                }
                .accessibilityIdentifier("about.followAuthor")
                externalLinkRow(
                    title: MoroL10n.AppSupport.rate,
                    systemImage: "star",
                    destination: MoroAppStore.reviewURL
                )
                .accessibilityIdentifier("about.rate")
                externalLinkRow(
                    title: MoroL10n.About.versionHistory,
                    systemImage: "clock.arrow.circlepath",
                    destination: MoroAppStore.productURL
                )
                .accessibilityIdentifier("about.versionHistory")
            }

            Section {
                externalLinkRow(
                    title: MoroL10n.About.website,
                    systemImage: "globe",
                    destination: MoroBrand.websiteURL
                )
                externalLinkRow(
                    title: MoroL10n.About.githubRepo,
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    destination: githubURL
                )
            }

            Section {
                externalLinkRow(
                    title: MoroL10n.Registration.privacyPolicy,
                    systemImage: "hand.raised",
                    destination: MoroBrand.privacyPolicyURL
                )
                externalLinkRow(
                    title: MoroL10n.Registration.termsOfService,
                    systemImage: "doc.text",
                    destination: MoroBrand.termsOfUseURL
                )
                NavigationLink {
                    OpenSourceLicensesView()
                } label: {
                    rowLabel(title: MoroL10n.About.openSourceLicenses, systemImage: "doc.plaintext")
                }
                .accessibilityIdentifier("about.licenses")
            }
        }
        .moroSettingsListChrome()
        .navigationTitle(MoroL10n.About.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(spacing: 8) {
            appIconPreview
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .padding(.bottom, 6)

            Text(verbatim: appTitle)
                .font(theme.typography.title)
                .fontWeight(.semibold)
                .foregroundStyle(theme.colors.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("about.appVersion")

            Text(MoroL10n.About.tagline)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var appIconPreview: some View {
        if let image = UIImage(named: AppIconManager.shared.currentChoice.previewAssetName) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        } else {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .foregroundStyle(theme.colors.textPrimary)
                .frame(width: 80, height: 80)
                .background(theme.colors.groupedSurface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
    }

    private func externalLinkRow(
        title: String,
        systemImage: String,
        destination: URL
    ) -> some View {
        Link(destination: destination) {
            rowLabel(title: title, systemImage: systemImage, accessory: "arrow.up.right")
        }
    }

    /// Same anatomy as the Settings home rows: gray icon column, primary title,
    /// optional secondary value and a quiet trailing accessory. NavigationLink rows
    /// pass no accessory and get the system chevron.
    private func rowLabel(
        title: String,
        systemImage: String,
        accessory: String? = nil,
        value: String? = nil
    ) -> some View {
        HStack(spacing: MoroSettingsMetrics.iconTitleSpacing) {
            Image(systemName: systemImage)
                .moroScaledFont(size: MoroSettingsMetrics.iconPointSize, weight: .regular)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: iconColumnWidth)

            Text(title)
                .font(.body)
                .foregroundStyle(theme.colors.textPrimary)

            Spacer(minLength: 8)

            if let value {
                Text(verbatim: value)
                    .font(.body)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
            }

            if let accessory {
                Image(systemName: accessory)
                    .moroScaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            dimensions[.leading] + iconColumnWidth + MoroSettingsMetrics.iconTitleSpacing
        }
    }
}

#Preview {
    NavigationStack {
        AboutView()
            .moroTheme(MoroTheme())
    }
}
