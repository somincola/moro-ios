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

    private let githubURL = URL(string: "https://github.com/somincola/moro-ios")!

    private var appTitle: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            !version.isEmpty
        else { return "Moro" }
        return "Moro (\(version))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                    .padding(.bottom, theme.spacing.xl)

                divider
                externalLinkRow(
                    title: MoroL10n.About.versionHistory,
                    systemImage: "clock.arrow.circlepath",
                    destination: MoroAppStore.productURL
                )
                .accessibilityIdentifier("about.versionHistory")
                divider
                externalLinkRow(
                    title: MoroL10n.AppSupport.rate,
                    systemImage: "star",
                    destination: MoroAppStore.reviewURL
                )
                .accessibilityIdentifier("about.rate")
                divider
                externalLinkRow(
                    title: MoroL10n.About.website,
                    systemImage: "globe",
                    destination: MoroBrand.websiteURL
                )
                divider
                externalLinkRow(
                    title: MoroL10n.About.githubRepo,
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    destination: githubURL
                )
                divider
                externalLinkRow(
                    title: MoroL10n.Registration.privacyPolicy,
                    systemImage: "hand.raised",
                    destination: MoroBrand.privacyPolicyURL
                )
                divider
                externalLinkRow(
                    title: MoroL10n.Registration.termsOfService,
                    systemImage: "doc.text",
                    destination: MoroBrand.termsOfUseURL
                )
                divider
                NavigationLink {
                    OpenSourceLicensesView()
                } label: {
                    rowLabel(
                        title: MoroL10n.About.openSourceLicenses,
                        systemImage: "doc.plaintext",
                        accessory: "chevron.right"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("about.licenses")
                divider
            }
            .padding(.horizontal, theme.spacing.xl)
            .padding(.vertical, theme.spacing.l)
        }
        .background(theme.colors.background)
        .navigationTitle(MoroL10n.About.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.colors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var hero: some View {
        VStack(spacing: 10) {
            appIconPreview

            Text(verbatim: appTitle)
                .font(theme.typography.title)
                .fontWeight(.bold)
                .foregroundStyle(theme.colors.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("about.appVersion")

            Text(MoroL10n.About.tagline)
                .font(theme.typography.body)
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
                .background(theme.colors.surfaceSubtle, in: RoundedRectangle(cornerRadius: 19))
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
        .buttonStyle(.plain)
    }

    private func rowLabel(title: String, systemImage: String, accessory: String) -> some View {
        HStack(spacing: theme.spacing.m) {
            Image(systemName: systemImage)
                .moroScaledFont(size: 17, weight: .medium)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 24, height: 24)

            Text(title)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textPrimary)

            Spacer(minLength: theme.spacing.m)

            Image(systemName: accessory)
                .moroScaledFont(size: 12, weight: .semibold)
                .foregroundStyle(theme.colors.textTertiary)
        }
        .padding(.vertical, 14)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.colors.borderSubtle)
            .frame(height: 1)
    }
}

#Preview {
    NavigationStack {
        AboutView()
            .moroTheme(MoroTheme())
    }
}
