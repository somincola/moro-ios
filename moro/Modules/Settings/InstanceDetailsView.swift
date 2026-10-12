//
//  InstanceDetailsView.swift
//  moro
//
//  Displays current instance about information and server rules.
//

import SwiftUI
import Combine

private enum InstanceDetailsSection: String, CaseIterable, Identifiable {
    case about
    case rules

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .about: return MoroL10n.Instance.tabAbout
        case .rules: return MoroL10n.Instance.tabRules
        }
    }
}

@MainActor
private final class InstanceDetailsViewModel: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    @Published var section: InstanceDetailsSection = .about
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var details: InstanceDetailsSnapshot?

    private let apiClient: MastodonAPI
    private let instanceMetadataStore: InstanceMetadataStore
    private var hasLoaded: Bool = false

    init(
        apiClient: MastodonAPI,
        instanceMetadataStore: InstanceMetadataStore? = nil
    ) {
        self.apiClient = apiClient
        self.instanceMetadataStore = instanceMetadataStore ?? .shared
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load(policy: .refreshIfStale)
    }

    func reload() async {
        await load(policy: .forceRefresh)
    }

    private func load(policy: InstanceMetadataStore.RefreshPolicy) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let instance = try await instanceMetadataStore.load(
                apiClient: apiClient,
                policy: policy
            )
            details = InstanceDetailsSnapshot(
                instance: instance,
                fallbackDomain: apiClient.instanceMetadataCacheKey
            )
            errorMessage = nil
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct InstanceDetailsSnapshot {
    let title: String
    let domain: String
    let version: String?
    let statement: String
    let coverURL: URL?
    let contactEmail: String?
    let adminAccount: Account?
    let aboutURL: URL?
    let rulesURL: URL?
    let rules: [MastodonInstanceRule]

    init(instance: MastodonInstanceV2, fallbackDomain: String?) {
        let resolvedDomain = InstanceDetailsSnapshot.normalizedDomain(
            instance.domain
                ?? fallbackDomain
                ?? ""
        )

        self.title = instance.title
        self.domain = resolvedDomain
        self.version = instance.version
        self.coverURL = instance.thumbnail?.bestURL
        self.contactEmail = instance.contact?.email
        self.adminAccount = instance.contact?.account

        let descriptionRaw = instance.description ?? ""
        let strippedStatement = HTMLParser.stripHTML(descriptionRaw)
        self.statement = strippedStatement.isEmpty ? MoroL10n.Instance.noStatement : strippedStatement

        self.aboutURL = URL(string: "https://\(resolvedDomain)/about")
        self.rulesURL = URL(string: "https://\(resolvedDomain)/about/more")

        self.rules = instance.rules ?? []
    }

    private static func normalizedDomain(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutScheme = trimmed
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return withoutScheme.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var mailtoURL: URL? {
        guard let contactEmail, !contactEmail.isEmpty else { return nil }
        return URL(string: "mailto:\(contactEmail)")
    }
}

struct InstanceDetailsView: View {
    @Environment(\.moroTheme) private var theme
    @StateObject private var viewModel: InstanceDetailsViewModel
    @State private var selectedRulesLanguage = "en"

    init(apiClient: MastodonAPI) {
        _viewModel = StateObject(wrappedValue: InstanceDetailsViewModel(apiClient: apiClient))
    }

    var body: some View {
        Group {
            if let details = viewModel.details {
                content(details)
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView {
                    Label(MoroL10n.Instance.loadFailed, systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(MoroL10n.Instance.retry) {
                        Task { await viewModel.reload() }
                    }
                }
            } else {
                ProgressView(MoroL10n.Instance.loading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .moroSettingsPageChrome()
        .navigationTitle(MoroL10n.Instance.navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded()
        }
        .onChange(of: viewModel.details?.rules.map(\.id) ?? []) { _, _ in
            if let details = viewModel.details {
                selectedRulesLanguage = defaultRulesLanguage(for: details.rules)
            }
        }
        .refreshable {
            await viewModel.reload()
        }
    }

    @ViewBuilder
    private func content(_ details: InstanceDetailsSnapshot) -> some View {
        VStack(spacing: 0) {
            Picker(MoroL10n.Instance.pickerLabel, selection: $viewModel.section) {
                ForEach(InstanceDetailsSection.allCases) { section in
                    Text(section.localizedTitle).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, MoroSettingsMetrics.pageHorizontalInset)
            .padding(.vertical, theme.spacing.m)

            if viewModel.section == .about {
                aboutSection(details)
            } else {
                rulesSection(details)
            }
        }
        .overlay(alignment: .top) {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
    }

    private func aboutSection(_ details: InstanceDetailsSnapshot) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MoroSettingsMetrics.sectionSpacing) {
                instanceCover(details.coverURL)
                    .clipShape(
                        RoundedRectangle(cornerRadius: MoroSettingsMetrics.cardCornerRadius, style: .continuous)
                    )
                    .padding(.horizontal, MoroSettingsMetrics.pageHorizontalInset)
                    .padding(.top, theme.spacing.xs)

                VStack(alignment: .leading, spacing: theme.spacing.s) {
                    Text(details.title)
                        .moroScaledFont(size: 24, weight: .semibold, relativeTo: .title3)
                        .foregroundStyle(theme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(details.domain)
                        .moroScaledFont(size: 14, weight: .regular, relativeTo: .subheadline)
                        .foregroundStyle(theme.colors.textTertiary)

                    if let version = details.version, !version.isEmpty {
                        Text(MoroL10n.Instance.version(version))
                            .moroScaledFont(size: 12, weight: .regular, relativeTo: .caption)
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Text lines up with section headers and card content.
                .padding(.horizontal, MoroSettingsMetrics.pageHorizontalInset + theme.spacing.l)

                instanceSection(title: MoroL10n.Instance.statement) {
                    Text(details.statement)
                        .moroScaledFont(size: 14, weight: .regular)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                instanceSection(title: MoroL10n.Instance.admins) {
                    if let admin = details.adminAccount {
                        HStack(spacing: theme.spacing.m) {
                            MoroAvatar(
                                imageURL: admin.avatarAnimatedURL,
                                staticImageURL: admin.avatarURL,
                                initials: admin.displayNameInitials,
                                size: 44
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                AccountDisplayNameView(
                                    account: admin,
                                    typography: .bodyStrong,
                                    textColor: theme.colors.textPrimary
                                )
                                Text("@\(admin.acct)")
                                    .moroScaledFont(size: 13, weight: .regular)
                                    .foregroundStyle(theme.colors.textSecondary)
                            }
                            Spacer(minLength: 0)
                        }

                        let note = admin.notePreviewText.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        if !note.isEmpty {
                            Text(note)
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.textSecondary)
                                .lineLimit(5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text(MoroL10n.Instance.noAdminInfo)
                            .moroScaledFont(size: 13, weight: .regular)
                            .foregroundStyle(theme.colors.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        if let mailtoURL = details.mailtoURL {
                            Link(destination: mailtoURL) {
                                instanceLinkLabel(
                                    MoroL10n.Instance.emailAdmin,
                                    icon: "envelope"
                                )
                            }
                        }

                        if let accountURL = details.adminAccount?.url, let url = URL(string: accountURL) {
                            MoroDivider()
                            Link(destination: url) {
                                instanceLinkLabel(
                                    MoroL10n.Instance.adminProfile,
                                    icon: "person.crop.circle"
                                )
                            }
                        }

                        if let aboutURL = details.aboutURL {
                            MoroDivider()
                            Link(destination: aboutURL) {
                                instanceLinkLabel(MoroL10n.Instance.sitePage, icon: "safari")
                            }
                        }
                    }
                }
            }
            .padding(.bottom, theme.spacing.xxl)
        }
    }

    private func rulesSection(_ details: InstanceDetailsSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.xl) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: theme.spacing.l) {
                        rulesHeader
                        Spacer(minLength: theme.spacing.m)
                        if availableRulesLanguages(details.rules).count > 1 {
                            rulesLanguageMenu(details.rules)
                        }
                    }

                    VStack(alignment: .leading, spacing: theme.spacing.m) {
                        rulesHeader
                        if availableRulesLanguages(details.rules).count > 1 {
                            rulesLanguageMenu(details.rules)
                        }
                    }
                }
                .padding(.horizontal, theme.spacing.l)

                if details.rules.isEmpty {
                    Text(MoroL10n.Instance.noRulesHint)
                        .moroScaledFont(size: 14, weight: .regular, relativeTo: .subheadline)
                        .foregroundStyle(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(theme.spacing.l)
                        .moroSettingsCard()
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(details.rules.enumerated()), id: \.element.id) { index, rule in
                            instanceRuleRow(index: index, rule: rule)

                            if index < details.rules.count - 1 {
                                MoroDivider()
                                    .padding(.leading, 48)
                            }
                        }
                    }
                    .padding(.horizontal, theme.spacing.l)
                    .moroSettingsCard()
                }

                if let rulesURL = details.rulesURL {
                    Link(destination: rulesURL) {
                        Label(MoroL10n.Instance.openRulesPage, systemImage: "safari")
                            .moroScaledFont(size: 14, weight: .semibold)
                            .foregroundStyle(theme.colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, theme.spacing.l)
                }
            }
            .padding(.horizontal, MoroSettingsMetrics.pageHorizontalInset)
            .padding(.top, theme.spacing.s)
            .padding(.bottom, theme.spacing.xxl)
        }
    }

    @ViewBuilder
    private func instanceCover(_ url: URL?) -> some View {
        if let url {
            CachedAsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                instanceCoverPlaceholder
            }
            .aspectRatio(3, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipped()
        } else {
            instanceCoverPlaceholder
                .aspectRatio(3, contentMode: .fit)
        }
    }

    private var instanceCoverPlaceholder: some View {
        Rectangle()
            .fill(theme.colors.groupedSurface)
            .overlay {
                Image(systemName: "building.2")
                    .moroScaledFont(size: 24, weight: .regular)
                    .foregroundStyle(theme.colors.textTertiary)
            }
    }

    /// Same anatomy as a List section: a quiet header above one borderless card.
    private func instanceSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            MoroSettingsSectionHeader(title: title)
                .padding(.horizontal, theme.spacing.l)

            VStack(alignment: .leading, spacing: theme.spacing.m) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(theme.spacing.l)
            .moroSettingsCard()
        }
        .padding(.horizontal, MoroSettingsMetrics.pageHorizontalInset)
    }

    private func instanceLinkLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: MoroSettingsMetrics.iconTitleSpacing) {
            Image(systemName: icon)
                .moroScaledFont(size: MoroSettingsMetrics.iconPointSize, weight: .regular)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: MoroSettingsMetrics.iconColumnWidth)
            Text(title)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textPrimary)
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .moroScaledFont(size: 13, weight: .semibold)
                .foregroundStyle(theme.colors.textTertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var rulesHeader: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            Text(MoroL10n.Login.Info.rulesTitle)
                .moroScaledFont(size: 24, weight: .semibold, relativeTo: .title3)
                .foregroundStyle(theme.colors.textPrimary)
            Text(MoroL10n.Instance.rulesSummary)
                .moroScaledFont(size: 14, weight: .regular, relativeTo: .subheadline)
                .foregroundStyle(theme.colors.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func instanceRuleRow(index: Int, rule: MastodonInstanceRule) -> some View {
        HStack(alignment: .top, spacing: theme.spacing.m) {
            Text(String(format: "%02d", index + 1))
                .moroScaledFont(size: 12, weight: .semibold, relativeTo: .footnote)
                .monospacedDigit()
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: 32, alignment: .leading)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: theme.spacing.s) {
                Text(
                    HTMLParser.stripHTML(
                        rule.localizedText(languageIdentifiers: [selectedRulesLanguage])
                    )
                )
                .moroScaledFont(size: 16, weight: .semibold, relativeTo: .body)
                .foregroundStyle(theme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

                if let hint = ruleHint(rule) {
                    Text(hint)
                        .moroScaledFont(size: 14, weight: .regular, relativeTo: .subheadline)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, theme.spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rulesLanguageMenu(_ rules: [MastodonInstanceRule]) -> some View {
        Menu {
            ForEach(availableRulesLanguages(rules), id: \.self) { language in
                Button {
                    selectedRulesLanguage = language
                } label: {
                    if language == selectedRulesLanguage {
                        Label(rulesLanguageName(language), systemImage: "checkmark")
                    } else {
                        Text(rulesLanguageName(language))
                    }
                }
            }
        } label: {
            HStack(spacing: theme.spacing.xs) {
                Text(rulesLanguageName(selectedRulesLanguage))
                    .moroScaledFont(size: 13, weight: .semibold, relativeTo: .footnote)
                Image(systemName: "chevron.down")
                    .moroScaledFont(size: 10, weight: .semibold)
            }
            .foregroundStyle(theme.colors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(theme.colors.groupedSurface))
        }
    }

    private func availableRulesLanguages(_ rules: [MastodonInstanceRule]) -> [String] {
        var languages = Set<String>()
        for rule in rules {
            languages.formUnion((rule.translations ?? [:]).keys.map { $0.lowercased() })
        }
        languages.insert("en")
        return languages.sorted()
    }

    private func defaultRulesLanguage(for rules: [MastodonInstanceRule]) -> String {
        let available = Set(availableRulesLanguages(rules))
        if let preferred = Locale.preferredLanguages.first {
            let lowercased = preferred.lowercased()
            if available.contains(lowercased) { return lowercased }
            let primary = preferred.split(separator: "-").first.map { String($0).lowercased() }
            if let primary, available.contains(primary) { return primary }
        }
        return available.contains("en") ? "en" : (available.sorted().first ?? "en")
    }

    private func ruleHint(_ rule: MastodonInstanceRule) -> String? {
        guard let hint = rule.localizedHint(languageIdentifiers: [selectedRulesLanguage]) else {
            return nil
        }
        let stripped = HTMLParser.stripHTML(hint).trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }

    private func rulesLanguageName(_ code: String) -> String {
        let key = code.lowercased()
        let overrides: [String: String] = [
            "en": "English",
            "zh": "简体中文", "zh-hans": "简体中文", "zh-cn": "简体中文",
            "zh-sg": "简体中文", "zh-hant": "繁體中文", "zh-tw": "繁體中文",
            "zh-hk": "繁體中文", "zh-mo": "繁體中文",
        ]
        if let override = overrides[key] { return override }
        let locale = Locale(identifier: code)
        return locale.localizedString(forIdentifier: code)
            ?? locale.localizedString(forLanguageCode: code)
            ?? code.uppercased()
    }
}

#Preview {
    NavigationStack {
        InstanceDetailsView(
            apiClient: MastodonClient(authInterceptor: AuthInterceptor(tokenProvider: AppState()))
        )
        .moroTheme(MoroTheme())
    }
}
