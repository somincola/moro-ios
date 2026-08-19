//
//  AboutView.swift
//  moro
//
//  Product information and support links.
//

import SwiftUI
import UIKit

#if canImport(MessageUI)
    import MessageUI
#endif

struct AboutView: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appState: AppState

    private let githubURL = URL(string: "https://github.com/somincola/moro-ios")!
    private let mastodonURL = URL(string: "https://joinmastodon.org")!
    @State private var showFeedbackMethodPicker = false
    @State private var showFeedbackMailComposer = false

    private var appIconName: String {
        AppIconManager.shared.currentChoice.previewAssetName
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? MoroL10n.About.unknown
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var feedbackBody: String {
        FeedbackMailContext.messageBody(currentAccount: appState.currentAccount)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                    .padding(.bottom, theme.spacing.xl)

                divider
                feedbackRow
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
        .confirmationDialog(
            MoroL10n.Settings.feedbackDialogTitle,
            isPresented: $showFeedbackMethodPicker,
            titleVisibility: .visible
        ) {
            if FeedbackMailContext.canUseInAppComposer {
                Button(MoroL10n.Settings.feedbackInApp) {
                    showFeedbackMailComposer = true
                }
            }
            Button(MoroL10n.Settings.feedbackMailApp) {
                openFeedbackInMailApp()
            }
            Button(MoroL10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(MoroL10n.Settings.feedbackDestination(FeedbackMailContext.supportEmail))
        }
        #if canImport(MessageUI)
            .sheet(isPresented: $showFeedbackMailComposer) {
                FeedbackMailComposerView(
                    to: FeedbackMailContext.supportEmail,
                    subject: FeedbackMailContext.subject,
                    body: feedbackBody
                ) { result, error in
                    handleFeedbackMailResult(result: result, error: error)
                }
            }
        #endif
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

            Text("\(MoroL10n.About.version) \(appVersion)")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textTertiary)
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

    private var feedbackRow: some View {
        Button {
            showFeedbackMethodPicker = true
        } label: {
            rowLabel(
                title: MoroL10n.About.feedbackEmail,
                subtitle: FeedbackMailContext.supportEmail,
                systemImage: "envelope",
                accessory: "paperplane"
            )
        }
        .buttonStyle(.plain)
    }

    private var acknowledgementsRow: some View {
        NavigationLink {
            AcknowledgementsView()
        } label: {
            rowLabel(
                title: MoroL10n.About.viewAcknowledgements,
                subtitle: "Mastodon、SwiftUI、SDWebImage",
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

    private func openFeedbackInMailApp() {
        guard let url = FeedbackMailContext.mailtoURL(
            email: FeedbackMailContext.supportEmail,
            subject: FeedbackMailContext.subject,
            body: feedbackBody
        ) else {
            AppFeedbackCenter.shared.showError(MoroL10n.Settings.feedbackMailLinkError)
            return
        }

        openURL(url) { accepted in
            if !accepted {
                AppFeedbackCenter.shared.showError(MoroL10n.Settings.feedbackMailAppError)
            }
        }
    }

    #if canImport(MessageUI)
        private func handleFeedbackMailResult(result: MFMailComposeResult, error: Error?) {
            if error != nil {
                AppFeedbackCenter.shared.showError(MoroL10n.Settings.feedbackMailFailed)
                return
            }

            switch result {
            case .sent:
                AppFeedbackCenter.shared.showSuccess(MoroL10n.Settings.feedbackMailSent)
            case .saved:
                AppFeedbackCenter.shared.showInfo(MoroL10n.Settings.feedbackMailSaved)
            case .cancelled:
                break
            case .failed:
                AppFeedbackCenter.shared.showError(MoroL10n.Settings.feedbackMailFailed)
            @unknown default:
                break
            }
        }
    #endif
}

struct AcknowledgementsView: View {
    @Environment(\.moroTheme) private var theme

    private let acknowledgements: [(name: String, detail: String)] = [
        ("Mastodon", MoroL10n.About.ackMastodon),
        ("SwiftUI", MoroL10n.About.ackSwiftUI),
        ("SDWebImage", MoroL10n.About.ackSDWebImage),
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
