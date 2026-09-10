//
//  AboutView.swift
//  moro
//
//  Product information and support links.
//

import SwiftUI
import UIKit


struct AboutView: View {
    @Environment(\.moroTheme) private var theme
    @ObservedObject var updates: AppUpdateStore = .shared

    private let githubURL = URL(string: "https://github.com/somincola/moro-ios")!
    private let mastodonURL = URL(string: "https://joinmastodon.org")!

    private var appIconName: String {
        AppIconManager.shared.currentChoice.previewAssetName
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                    .padding(.bottom, theme.spacing.xl)

                AppUpdateSection(store: updates)
                    .padding(.bottom, theme.spacing.l)

                divider
                externalLinkRow(
                    title: "Moro",
                    subtitle: "moro.somincola.com",
                    systemImage: "globe",
                    destination: MoroBrand.websiteURL
                )
                divider
                externalLinkRow(
                    title: MoroL10n.Registration.privacyPolicy,
                    subtitle: "moro.somincola.com/privacy",
                    systemImage: "hand.raised",
                    destination: MoroBrand.privacyPolicyURL
                )
                divider
                externalLinkRow(
                    title: MoroL10n.Registration.termsOfService,
                    subtitle: "moro.somincola.com/terms",
                    systemImage: "doc.text",
                    destination: MoroBrand.termsOfUseURL
                )
                divider
                externalLinkRow(
                    title: MoroL10n.About.support,
                    subtitle: "moro.somincola.com/support",
                    systemImage: "questionmark.circle",
                    destination: MoroBrand.supportURL
                )
                divider
                externalLinkRow(
                    title: MoroL10n.About.githubRepo,
                    subtitle: "github.com/somincola/moro-ios",
                    systemImage: "link",
                    destination: githubURL
                )
                divider
                externalLinkRow(
                    title: MoroL10n.About.mastodonOfficial,
                    subtitle: "joinmastodon.org",
                    systemImage: "at",
                    destination: mastodonURL
                )
                divider
                acknowledgementsRow
                divider

                footerSection
                    .padding(.top, theme.spacing.xl)
            }
            .padding(.horizontal, theme.spacing.xl)
            .padding(.vertical, theme.spacing.l)
        }
        .background(theme.colors.background)
        .navigationTitle(MoroL10n.About.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.colors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            updates.markUpdateSeen()
            await updates.check()
            updates.markUpdateSeen()
        }
        .onChange(of: updates.latestRelease) { _, _ in updates.markUpdateSeen() }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            appIconPreview

            Text("Moro")
                .font(theme.typography.title)
                .fontWeight(.bold)
                .foregroundStyle(theme.colors.textPrimary)

            Text(MoroL10n.About.tagline)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var appIconPreview: some View {
        if let image = UIImage(named: appIconName) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(theme.colors.surfaceSubtle)
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "app.fill")
                        .moroScaledFont(size: 28, weight: .medium)
                        .foregroundStyle(theme.colors.textSecondary)
                )
        }
    }

    private var acknowledgementsRow: some View {
        NavigationLink {
            AcknowledgementsView()
        } label: {
            rowLabel(
                title: MoroL10n.About.viewAcknowledgements,
                subtitle: "Mastodon、SwiftUI、SDWebImage、SwiftSoup",
                systemImage: "heart.text.square",
                accessory: "chevron.right"
            )
        }
        .buttonStyle(.plain)
    }

    private var footerSection: some View {
        VStack(spacing: 6) {
            Text(MoroL10n.About.footer)
                .foregroundStyle(theme.colors.textSecondary)
            Text(MoroL10n.About.copyright(currentYear))
                .foregroundStyle(theme.colors.textTertiary)
        }
        .font(theme.typography.caption)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private func externalLinkRow(
        title: String,
        subtitle: String,
        systemImage: String,
        destination: URL
    ) -> some View {
        Link(destination: destination) {
            rowLabel(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                accessory: "arrow.up.right"
            )
        }
        .buttonStyle(.plain)
    }

    private func rowLabel(
        title: String,
        subtitle: String,
        systemImage: String,
        accessory: String
    ) -> some View {
        HStack(spacing: theme.spacing.m) {
            Image(systemName: systemImage)
                .moroScaledFont(size: 17, weight: .medium)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(subtitle)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: theme.spacing.m)

            Image(systemName: accessory)
                .moroScaledFont(size: 12, weight: .semibold)
                .foregroundStyle(theme.colors.textTertiary)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.colors.borderSubtle)
            .frame(height: 1)
    }


}

struct AcknowledgementsView: View {
    @Environment(\.moroTheme) private var theme

    private let acknowledgements: [(name: String, detail: String)] = [
        ("Mastodon", MoroL10n.About.ackMastodon),
        ("SwiftUI", MoroL10n.About.ackSwiftUI),
        ("SDWebImage", MoroL10n.About.ackSDWebImage),
        ("SwiftSoup", """
        The MIT License

        Copyright (c) 2009-2025 Jonathan Hedley <https://jsoup.org/>
        Copyright (c) 2016-2025 Nabil Chatbi (Swift port)

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        """),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(acknowledgements.enumerated()), id: \.offset) { index, item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name)
                            .font(theme.typography.subtitle)
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.colors.textPrimary)

                        Text(item.detail)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    .padding(.vertical, theme.spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if index < acknowledgements.count - 1 {
                        Rectangle()
                            .fill(theme.colors.borderSubtle)
                            .frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, theme.spacing.xl)
            .padding(.vertical, theme.spacing.l)
        }
        .background(theme.colors.background)
        .navigationTitle(MoroL10n.About.acknowledgementsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.colors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

#Preview {
    NavigationStack {
        AboutView()
            .environmentObject(AppState())
            .moroTheme(MoroTheme())
    }
}
