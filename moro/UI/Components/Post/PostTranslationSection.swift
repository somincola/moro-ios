//
//  PostTranslationSection.swift
//  moro
//
//  Inline translation controls and translated content rendering for post bodies.
//

import Combine
import SwiftUI

@MainActor
final class StatusTranslationViewModel: ObservableObject {
    @Published private(set) var translatedResult: TranslationResult?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var availabilityReason: String?
    /// Whether the configured service can translate the current post. Published so
    /// the UI updates the moment `configure(...)` resolves availability. (Deriving
    /// this from the non-published `service` caused a stale-state bug: the control
    /// only appeared after an unrelated re-render, e.g. after liking the post.)
    @Published private(set) var isTranslationAvailable = false

    private var currentStatusID: String?
    private var currentStatusContent: String = ""
    private var currentSourceLanguage: String?
    private var currentTargetLanguage: String = ""
    private var currentMode: AppSettings.ContentTranslationMode = .disabled
    private var service: any TranslationService = UnavailableTranslationService.disabled
    private let translationLanguagesStore: TranslationLanguagesStore
    /// Server-side rules mirrored client-side (visibility + instance language
    /// pairs); when false the translate control never shows, so taps can't hit
    /// the server's 403/422.
    private var passesServerRules = false

    init(translationLanguagesStore: TranslationLanguagesStore? = nil) {
        self.translationLanguagesStore = translationLanguagesStore ?? .shared
    }

    var canOfferTranslation: Bool {
        if translatedResult != nil { return true }
        if isLoading { return true }
        return isTranslationAvailable
    }

    var isTranslated: Bool {
        translatedResult != nil
    }

    var translationSummary: String {
        guard let translatedResult else { return "" }
        let sourceLanguageCode =
            translatedResult.detectedSourceLanguage
            ?? normalizedOptionalLanguageCode(currentSourceLanguage)
        let sourceLanguage = localizedLanguageName(for: sourceLanguageCode)
        let providerName = translatedResult.providerName ?? defaultProviderName(for: translatedResult)
        return MoroL10n.Translation.translatedFrom(sourceLanguage, providerName)
    }

    private var request: TranslationRequest {
        TranslationRequest(
            text: currentStatusContent,
            sourceLanguage: currentSourceLanguage,
            targetLanguage: currentTargetLanguage
        )
    }

    private var availability: TranslationAvailability {
        service.availability(for: request)
    }

    func configure(
        status: Status,
        apiClient: MastodonAPI?,
        mode: AppSettings.ContentTranslationMode,
        targetLanguageCode: String
    ) {
        let displayStatus = status.displayStatus
        // The translate target is the app UI language, passed in raw (e.g.
        // "pt-PT", "zh-Hans") so the server's `lang` parameter preserves the
        // selected locale; canonicalizing it would collapse "pt-PT" to "pt".
        let uiLanguage = targetLanguageCode
        let normalizedSourceLanguage = normalizedOptionalLanguageCode(displayStatus.language)

        let needsReset =
            currentStatusID != displayStatus.id
            || currentStatusContent != displayStatus.content
            || currentSourceLanguage != normalizedSourceLanguage
            || currentTargetLanguage != uiLanguage
            || currentMode != mode

        currentStatusID = displayStatus.id
        currentStatusContent = displayStatus.content
        currentSourceLanguage = normalizedSourceLanguage
        currentTargetLanguage = uiLanguage
        currentMode = mode
        service = makeService(apiClient: apiClient, statusID: displayStatus.id, mode: mode)
        passesServerRules = Self.passesServerTranslationRules(
            visibility: displayStatus.visibility,
            rawSourceLanguage: displayStatus.language,
            uiLanguage: uiLanguage,
            translationLanguagesStore: translationLanguagesStore
        )

        if needsReset {
            translatedResult = nil
            errorMessage = nil
            isLoading = false
        }

        // Resolve availability now (service + request are set above) and publish it,
        // so the translate control reflects it immediately on configure.
        guard passesServerRules else {
            isTranslationAvailable = false
            // A same-language post is intentionally not translatable — surface that specific
            // reason (the VM's published contract) instead of a blank one. Other passesServerRules
            // failures (no language / non-distributable visibility) hide the control silently.
            availabilityReason = Self.isSameLanguage(
                rawSourceLanguage: displayStatus.language, uiLanguage: uiLanguage)
                ? MoroL10n.Translation.sameLanguage : nil
            return
        }

        switch availability {
        case .available:
            isTranslationAvailable = true
            availabilityReason = nil
        case .unavailable(let reason):
            isTranslationAvailable = false
            availabilityReason = reason
        }
    }

    /// A post is translatable when it has a language tag that differs from the
    /// app UI language and the instance can translate that pair into the UI
    /// language. Public or unlisted visibility is also required because the
    /// server only translates distributable posts, so a
    /// follower-only post would 403 ("this action is not allowed") on tap.
    private static func passesServerTranslationRules(
        visibility: String?,
        rawSourceLanguage: String?,
        uiLanguage: String,
        translationLanguagesStore: TranslationLanguagesStore
    ) -> Bool {
        guard let postLanguage = rawSourceLanguage, !postLanguage.isEmpty else {
            return false
        }
        if let visibility, visibility != "public", visibility != "unlisted" {
            return false
        }
        // Same language as the UI → nothing to translate.
        if isSameLanguage(rawSourceLanguage: postLanguage, uiLanguage: uiLanguage) {
            return false
        }
        return translationLanguagesStore.canTranslate(
            postLanguage: postLanguage,
            into: uiLanguage
        )
    }

    /// True when the post's primary language matches the UI's (e.g. "en-US" vs "en") — such a
    /// post is intentionally not offered for translation.
    private static func isSameLanguage(rawSourceLanguage: String?, uiLanguage: String) -> Bool {
        guard let raw = rawSourceLanguage, !raw.isEmpty else { return false }
        let postPrimary = raw.split(separator: "-").first.map(String.init) ?? raw
        let uiPrimary = uiLanguage.split(separator: "-").first.map(String.init) ?? uiLanguage
        return postPrimary.caseInsensitiveCompare(uiPrimary) == .orderedSame
    }

    func translate() async {
        guard !isLoading else { return }
        // Unreachable from the UI (the control is hidden), but keeps any other
        // caller from hitting the server's 403/422.
        guard passesServerRules else { return }

        switch availability {
        case .available:
            break
        case .unavailable(let reason):
            errorMessage = reason
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            translatedResult = try await service.translate(request)
        } catch let error as TranslationServiceError {
            errorMessage = error.errorDescription ?? MoroL10n.Translation.failed
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? MoroL10n.Translation.failed
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func showOriginal() {
        translatedResult = nil
        errorMessage = nil
        isLoading = false
    }

    func toggleFromToolbar() async {
        if isTranslated {
            showOriginal()
        } else {
            await translate()
        }
    }

    private func makeService(
        apiClient: MastodonAPI?,
        statusID: String,
        mode: AppSettings.ContentTranslationMode
    ) -> any TranslationService {
        switch mode {
        case .disabled:
            return UnavailableTranslationService(reason: MoroL10n.Translation.modeDisabled)
        case .remote:
            guard let apiClient else {
                return UnavailableTranslationService(reason: MoroL10n.Translation.notConfigured)
            }
            return RemoteStatusTranslationService(apiClient: apiClient, statusID: statusID)
        }
    }

    private func localizedLanguageName(for code: String?) -> String {
        guard let code, !code.isEmpty else { return MoroL10n.Translation.original }
        return PostLanguageCatalog.displayName(for: code)
    }

    private func defaultProviderName(for result: TranslationResult) -> String {
        switch result.provider {
        case .remote:
            return MoroL10n.Translation.providerRemoteName
        case .system:
            return MoroL10n.Translation.system
        case .unavailable:
            return MoroL10n.Translation.modeDisabled
        }
    }

    private func normalizedOptionalLanguageCode(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        let normalized = PostLanguageCatalog.canonicalLanguageCode(for: code)
        return normalized.isEmpty ? nil : normalized
    }
}

struct PostTranslationSection: View {
    private static let translatedEmojiSize: CGFloat = 20

    let status: Status
    let apiClient: MastodonAPI?
    @ObservedObject var viewModel: StatusTranslationViewModel
    var onMentionTap: ((String, URL) -> Void)? = nil
    var onHashtagTap: ((String, URL) -> Void)? = nil
    var onLinkTap: ((URL) -> Void)? = nil

    @StateObject private var settings = AppSettings.shared
    @Environment(\.moroTheme) private var theme
    @Environment(\.mastodonAPIClient) private var environmentAPIClient

    /// The threaded `apiClient` takes precedence (timeline / detail pass it
    /// explicitly); otherwise fall back to the session client from the
    /// environment, so surfaces that don't thread it (profile, hashtag,
    /// favourites, …) still get a working translate control.
    private var resolvedAPIClient: MastodonAPI? {
        apiClient ?? environmentAPIClient
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            if let translatedResult = viewModel.translatedResult {
                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    Text(viewModel.translationSummary)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LinkedTextView(
                        html: translatedResult.translatedText,
                        mentions: status.mentions,
                        tags: status.tags,
                        emojis: status.emojis,
                        parsingOptions: .statusBody,
                        emojiSize: Self.translatedEmojiSize,
                        onMentionTap: onMentionTap,
                        onHashtagTap: onHashtagTap,
                        onLinkTap: onLinkTap
                    )
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.colors.surfaceSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(theme.colors.borderSubtle, lineWidth: 1)
                )
            }

            // Translate / Show original control (lives with the content, not the
            // action toolbar, so it only appears for translatable posts and never
            // disturbs the action bar layout).
            translateControl

            if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            } else if viewModel.translatedResult == nil,
                let availabilityReason = viewModel.availabilityReason,
                settings.contentTranslationMode == .remote,
                availabilityReason == MoroL10n.Translation.unavailableOnInstance
            {
                Text(availabilityReason)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            configureTranslation()
        }
        .task {
            // Resolve the instance's supported pairs once per session, then
            // re-run configure so pair gating applies to this post.
            guard let resolvedAPIClient, settings.contentTranslationMode == .remote else { return }
            await TranslationLanguagesStore.shared.loadIfNeeded(apiClient: resolvedAPIClient)
            configureTranslation()
        }
        .onChange(of: status.id) { _, _ in
            configureTranslation()
        }
        .onChange(of: status.content) { _, _ in
            configureTranslation()
        }
        .onChange(of: status.language) { _, _ in
            configureTranslation()
        }
        .onChange(of: settings.contentTranslationMode) { _, _ in
            configureTranslation()
        }
    }

    @ViewBuilder
    private var translateControl: some View {
        if viewModel.isLoading {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .tint(theme.colors.textMuted)
                Text(MoroL10n.Translation.actionTranslate)
                    .moroScaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .padding(.vertical, 2)
        } else if viewModel.isTranslated {
            translateLinkButton(
                title: MoroL10n.Translation.actionShowOriginal,
                icon: "arrow.uturn.backward"
            ) {
                viewModel.showOriginal()
            }
        } else if viewModel.canOfferTranslation {
            translateLinkButton(
                title: MoroL10n.Translation.actionTranslate,
                icon: "character.bubble"
            ) {
                Task { await viewModel.translate() }
            }
        }
    }

    private func translateLinkButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .moroScaledFont(size: 14, weight: .semibold)
                Text(title)
                    .moroScaledFont(size: 14, weight: .semibold)
            }
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func configureTranslation() {
        viewModel.configure(
            status: status,
            apiClient: resolvedAPIClient,
            mode: settings.contentTranslationMode,
            targetLanguageCode: MoroAppLanguage.current
        )
    }
}
