//
//  ServerInfoView.swift
//  moro
//
//  Step 2 of sign-up: query and present a server's public info before
//  continuing to the registration form.
//

import SwiftUI

struct ServerInfoView: View {
    @ObservedObject var authService: AuthService
    let domain: String
    let onContinue: () -> Void

    @Environment(\.moroTheme) private var theme

    private enum Phase {
        case loading
        case failed
        case loaded(ServerInfoSnapshot)
    }

    @State private var phase: Phase = .loading
    /// Server's long-form "about this site" page (HTML).
    @State private var aboutHTML: String?

    var body: some View {
        ScrollView {
            switch phase {
            case .loading:
                loadingView
            case .failed:
                errorView
            case .loaded(let snapshot):
                content(for: snapshot)
            }
        }
        .background(theme.colors.surfaceBase)
        .moroReadableListMargins()
        .navigationTitle(domain)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - Loading / Error

    private var loadingView: some View {
        VStack(spacing: theme.spacing.m) {
            ProgressView()
            Text(MoroL10n.Login.Info.loading)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private var errorView: some View {
        VStack(spacing: theme.spacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .moroScaledFont(size: 32)
                .foregroundStyle(theme.colors.textTertiary)
            Text(MoroL10n.Login.Info.errorLoad)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
            MoroButton(title: MoroL10n.Login.retry, kind: .secondary) {
                Task { await load() }
            }
            .frame(maxWidth: 200)
        }
        .frame(maxWidth: .infinity)
        .padding(theme.spacing.xl)
        .padding(.top, 80)
    }

    // MARK: - Content

    private func content(for snapshot: ServerInfoSnapshot) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.l) {
            heroSummarySection(for: snapshot)

            VStack(alignment: .leading, spacing: theme.spacing.l) {
                if !snapshot.registrationsOpen {
                    Text(MoroL10n.Login.registrationClosed)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(theme.spacing.m)
                        .moroCardSurface(cornerRadius: 12, tone: .subtle)
                }

                if snapshot.adminAccount != nil || snapshot.contactEmail != nil {
                    adminSection(
                        admin: snapshot.adminAccount,
                        contactEmail: snapshot.contactEmail,
                        domain: snapshot.domain
                    )
                }

                aboutSection(shortText: snapshot.description)
            }
            .padding(.horizontal, theme.spacing.xl)
            .padding(.bottom, theme.spacing.xl)
        }
    }

    private func heroSummarySection(for snapshot: ServerInfoSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            coverImage(url: snapshot.coverURL, height: 190)

            VStack(alignment: .leading, spacing: theme.spacing.m) {
                header(for: snapshot)
                statusActionRow(for: snapshot)
            }
            .padding(.horizontal, theme.spacing.xl)
            .padding(.top, theme.spacing.l)
            .padding(.bottom, theme.spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surfaceBase)
    }

    private func statusActionRow(for snapshot: ServerInfoSnapshot) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: theme.spacing.m) {
                statusBadge(
                    isOpen: snapshot.registrationsOpen,
                    approvalRequired: snapshot.approvalRequired
                )
                .layoutPriority(1)

                if snapshot.registrationsOpen {
                    Spacer(minLength: theme.spacing.m)
                    compactContinueButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: theme.spacing.s) {
                statusBadge(
                    isOpen: snapshot.registrationsOpen,
                    approvalRequired: snapshot.approvalRequired
                )

                if snapshot.registrationsOpen {
                    compactContinueButton
                }
            }
        }
    }

    private var compactContinueButton: some View {
        Button {
            onContinue()
        } label: {
            Text(MoroL10n.Login.Server.continueButton)
                .moroScaledFont(size: 14, weight: .semibold, relativeTo: .subheadline)
                .foregroundStyle(theme.colors.primaryForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, theme.spacing.m)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.colors.primary500)
                )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func coverImage(url: URL?, height: CGFloat) -> some View {
        if let url {
            CachedAsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Rectangle()
                    .fill(theme.colors.surfaceSubtle)
                    .overlay {
                        Image(systemName: "photo")
                            .moroScaledFont(size: 20, weight: .semibold)
                            .foregroundStyle(theme.colors.textTertiary)
                    }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipped()
        } else {
            LinearGradient(
                colors: [theme.colors.primary500.opacity(0.25), theme.colors.primary500.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: height)
        }
    }

    private func header(for snapshot: ServerInfoSnapshot) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            Text(snapshot.title)
                .moroScaledFont(size: 24, weight: .semibold, relativeTo: .title3)
                .foregroundStyle(theme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(snapshot.domain)
                .moroScaledFont(size: 14, weight: .regular, relativeTo: .footnote)
                .foregroundStyle(theme.colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !snapshot.description.isEmpty {
                Text(snapshot.description)
                    .moroScaledFont(size: 14, weight: .regular, relativeTo: .subheadline)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, theme.spacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusBadge(isOpen: Bool, approvalRequired: Bool) -> some View {
        let label: String
        let color: Color
        if !isOpen {
            label = MoroL10n.Login.Info.statusClosed
            color = theme.colors.textSecondary
        } else if approvalRequired {
            label = MoroL10n.Login.Info.statusApproval
            color = theme.colors.primary600
        } else {
            label = MoroL10n.Login.Info.statusOpen
            color = theme.colors.success
        }

        return HStack(spacing: 6) {
            Image(systemName: isOpen ? (approvalRequired ? "person.badge.clock" : "person.badge.plus") : "lock")
                .moroScaledFont(size: 12, weight: .semibold)
            Text(label)
                .font(theme.typography.caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.12)))
    }

    /// The server's "about this site" content. Prefers the server-rendered long-form HTML
    /// page (`extended_description`); falls back to the short instance description.
    @ViewBuilder
    private func aboutSection(shortText: String) -> some View {
        if let aboutHTML, !aboutHTML.isEmpty {
            section(title: MoroL10n.Login.Info.aboutTitle, icon: "info.circle") {
                // Its own headings carry the structure, so no extra section title.
                HTMLDocumentView(html: aboutHTML)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if !shortText.isEmpty {
            section(title: MoroL10n.Login.Info.aboutTitle, icon: "info.circle") {
                Text(shortText)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func adminSection(admin: Account?, contactEmail: String?, domain: String) -> some View {
        section(title: MoroL10n.Login.Info.adminTitle, icon: "person.crop.circle") {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                if let admin {
                    HStack(spacing: theme.spacing.m) {
                        CachedAsyncImage(url: admin.avatarURL) { image in
                            image.resizable().scaledToFill()
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            // Parse custom emoji in the admin's display name (same as post headers).
                            AccountDisplayNameView(
                                account: admin,
                                typography: .bodyStrong,
                                textColor: theme.colors.textPrimary,
                                lineLimit: 1
                            )
                            Text(accountHandle(admin, domain: domain))
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.textSecondary)
                        }

                        Spacer(minLength: 0)
                    }

                    let note = admin.notePreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !note.isEmpty {
                        Text(note)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let contactEmail {
                    contactEmailRow(contactEmail)
                }
            }
        }
    }

    @ViewBuilder
    private func contactEmailRow(_ email: String) -> some View {
        if let url = URL(string: "mailto:\(email)") {
            Link(destination: url) {
                emailRowContent(email)
            }
        } else {
            emailRowContent(email)
        }
    }

    private func emailRowContent(_ email: String) -> some View {
        HStack(spacing: theme.spacing.s) {
            Image(systemName: "envelope")
                .moroScaledFont(size: 13, weight: .semibold)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 22, height: 22)

            Text(email)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.primary500)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func accountHandle(_ account: Account, domain: String) -> String {
        let acct = account.acct.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !acct.isEmpty else { return "@\(account.username)@\(domain)" }
        if acct.contains("@") {
            return "@\(acct)"
        }
        return "@\(acct)@\(domain)"
    }

    private struct ServerInfoSnapshot {
        let title: String
        let domain: String
        let description: String
        let coverURL: URL?
        let registrationsOpen: Bool
        let approvalRequired: Bool
        let contactEmail: String?
        let adminAccount: Account?

        init(
            instance: MastodonInstance,
            registrationInfo: InstanceRegistrationInfo?,
            fallbackDomain: String
        ) {
            let resolvedDomain = Self.normalizedDomain(
                registrationInfo?.domain
                    ?? instance.uri,
                fallback: fallbackDomain
            )

            self.title = Self.cleanedText(registrationInfo?.title)
                ?? Self.cleanedText(instance.title)
                ?? resolvedDomain
            self.domain = resolvedDomain
            self.description = Self.cleanedText(instance.shortDescription)
                ?? Self.cleanedText(registrationInfo?.description)
                ?? Self.cleanedText(instance.description)
                ?? ""
            self.coverURL = instance.thumbnail?.bestURL
            self.registrationsOpen = registrationInfo?.registrationsOpen
                ?? instance.registrations
                ?? true
            self.approvalRequired = registrationInfo?.approvalRequired
                ?? instance.approvalRequired
                ?? false
            self.contactEmail = Self.cleanedText(instance.email)
            self.adminAccount = instance.contactAccount
        }

        private static func cleanedText(_ value: String?) -> String? {
            guard let value else { return nil }
            let stripped = HTMLParser.stripHTML(value)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return stripped.isEmpty ? nil : stripped
        }

        private static func normalizedDomain(_ value: String?, fallback: String) -> String {
            guard let value = cleanedText(value) else { return fallback }
            if value.contains("://"), let url = URL(string: value), let host = url.host {
                return host
            }
            return value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
    }

    private func section<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            HStack(spacing: theme.spacing.s) {
                Image(systemName: icon)
                    .moroScaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(theme.colors.primary500)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(theme.colors.primary50))

                Text(title)
                    .font(theme.typography.bodyStrong)
                    .foregroundStyle(theme.colors.textPrimary)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.spacing.l)
        .moroCardSurface(cornerRadius: 18, tone: .base)
    }

    // MARK: - Load

    private func load() async {
        phase = .loading
        aboutHTML = nil
        do {
            let instance = try await authService.validateInstance(domain: domain)
            let snapshot = ServerInfoSnapshot(
                instance: instance,
                registrationInfo: authService.currentRegistrationInfo,
                fallbackDomain: domain
            )
            phase = .loaded(snapshot)
            // Best-effort; the section falls back to the short description when absent.
            aboutHTML = await authService.fetchExtendedDescription(domain: domain)
        } catch {
            phase = .failed
        }
    }
}
