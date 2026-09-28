//
//  AppCoordinator.swift
//  moro
//
//  Coordinates the root navigation flows and handles OAuth callbacks.
//

import Combine
import SwiftUI

/// Coordinates the root navigation flows for the Moro app.
@MainActor
final class AppCoordinator: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    enum Destination {
        case launch
        case onboarding
        case login
        case main
    }

    @Published private(set) var destination: Destination
    @Published private(set) var accountSessions: [StoredAccountSession] = []
    @Published private(set) var activeSessionID: String?
    @Published private(set) var opensRegistrationAfterOnboarding = false
    let appState: AppState
    @Published private(set) var apiClient: MastodonAPI
    private let authService = AuthService()
    private var authServiceForLogin: AuthService?
    private var lastIdentityRefreshAt: Date?
    private var startupSessionValidationTask: Task<Void, Never>?
    private var hasStarted = false
    private var cancellables = Set<AnyCancellable>()
    private let startupIdentityValidationDelayAfterFirstContent: TimeInterval = 8
    private let startupIdentityValidationWaitForTimelineTimeout: TimeInterval = 25
    private let startupIdentityValidationCooldown: TimeInterval = 15 * 60
    private let identityValidationTimestampPrefix = "identity_validation_last_success_at_"

    init(appState: AppState, apiClient: MastodonAPI) {
        self.appState = appState
        self.apiClient = apiClient
        self.destination = .launch
        bindCurrentAccountUpdates()
        reloadSessions()
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        StartupPerformanceTracker.shared.markLaunchStartIfNeeded(reason: "coordinator-start")

        // Fast path: use persisted active session snapshot first, then validate in background.
        if let cached = authService.cachedActiveSession() {
            applyAuthenticatedState(
                token: cached.token,
                account: cached.account,
                instanceURL: cached.instanceURL,
                persistSession: false,
                identityValidated: false
            )
            StartupPerformanceTracker.shared.markCachedSessionApplied(sessionID: cached.sessionID)
            let seedToken = cached.token
            scheduleStartupSessionValidation(
                seedToken: seedToken,
                sessionID: cached.sessionID
            )
            return
        }

        if let session = try? await authService.restoreSession() {
            applyAuthenticatedState(
                token: session.token,
                account: session.account,
                instanceURL: session.instanceURL,
                persistSession: false,
                identityValidated: true
            )
        } else {
            let hasOnboarded = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
            destination = hasOnboarded ? .login : .onboarding
        }
        reloadSessions()
    }

    func handleLoginSuccess(token: String, account: Account, instanceURL: URL) {
        startupSessionValidationTask?.cancel()
        applyAuthenticatedState(
            token: token,
            account: account,
            instanceURL: instanceURL,
            persistSession: true,
            identityValidated: true
        )
        // Release the login-screen AuthService; a later return to .login builds a fresh one.
        authServiceForLogin = nil
    }

    func refreshCurrentAccountIfNeeded(force: Bool = false) async {
        guard appState.isAuthenticated else { return }

        if !force, let lastIdentityRefreshAt,
            Date().timeIntervalSince(lastIdentityRefreshAt) < 30
        {
            return
        }

        do {
            StartupPerformanceTracker.shared.markIdentityRefreshStarted(trigger: "foreground")
            let refreshed = try await apiClient.verifyCredentials()
            appState.currentAccount = refreshed
            CacheManager.shared.accountCache.set(refreshed)
            lastIdentityRefreshAt = Date()
            authService.updateActiveSessionAccount(refreshed)
            markIdentityValidationSuccess()
            StartupPerformanceTracker.shared.markIdentityRefreshFinished(
                trigger: "foreground",
                success: true
            )
            reloadSessions()
        } catch {
            StartupPerformanceTracker.shared.markIdentityRefreshFinished(
                trigger: "foreground",
                success: false
            )
            // Keep existing account state on refresh failure.
        }
    }

    func completeOnboarding(_ completion: OnboardingCompletion) {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        opensRegistrationAfterOnboarding = completion == .registration
        destination = .login
    }

    func consumeRegistrationAfterOnboarding() {
        opensRegistrationAfterOnboarding = false
    }

    func getAuthServiceForLogin() -> AuthService {
        // Cached so AppCoordinatorView re-renders (toasts, color-scheme changes) reuse a
        // single instance instead of spinning up a fresh AuthService — and a fresh
        // AccountSessionStore, which does keychain + UserDefaults work in its init — on
        // every render. Cleared in handleLoginSuccess so a later return to .login is fresh.
        if let authServiceForLogin {
            return authServiceForLogin
        }
        let service = AuthService()
        authServiceForLogin = service
        return service
    }

    func switchAccount(to sessionID: String) {
        guard sessionID != activeSessionID else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            startupSessionValidationTask?.cancel()
            do {
                guard let session = try await authService.switchToSession(id: sessionID) else {
                    AppFeedbackCenter.shared.showError(MoroL10n.AppCoord.switchFailed)
                    return
                }

                CacheManager.shared.clearAll()
                handleLoginSuccess(
                    token: session.token,
                    account: session.account,
                    instanceURL: session.instanceURL
                )
                AppFeedbackCenter.shared.showSuccess(MoroL10n.AppCoord.switchedTo(session.account.acct))
            } catch {
                AppFeedbackCenter.shared.showError(MoroL10n.AppCoord.switchFailed)
                reloadSessions()
            }
        }
    }

    func removeAccount(sessionID: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            startupSessionValidationTask?.cancel()

            let removingActive = (sessionID == activeSessionID)
            authService.removeStoredSession(id: sessionID)
            reloadSessions()

            if !removingActive {
                AppFeedbackCenter.shared.showInfo(MoroL10n.AppCoord.accountRemoved)
                return
            }

            CacheManager.shared.clearAll()

            if let restored = try? await authService.restoreSession() {
                handleLoginSuccess(
                    token: restored.token,
                    account: restored.account,
                    instanceURL: restored.instanceURL
                )
                AppFeedbackCenter.shared.showInfo(MoroL10n.AppCoord.switchedToNext)
            } else {
                appState.reset()
                destination = .login
                StartupPerformanceTracker.shared.reset()
                AppFeedbackCenter.shared.showInfo(MoroL10n.AppCoord.loggedOut)
            }

            reloadSessions()
        }
    }

    func logout() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            startupSessionValidationTask?.cancel()
            guard let activeSessionID else {
                authService.clearAllStoredSessions()
                appState.reset()
                CacheManager.shared.clearAll()
                destination = .login
                StartupPerformanceTracker.shared.reset()
                reloadSessions()
                return
            }

            authService.removeStoredSession(id: activeSessionID)
            CacheManager.shared.clearAll()

            if let restored = try? await authService.restoreSession() {
                handleLoginSuccess(
                    token: restored.token,
                    account: restored.account,
                    instanceURL: restored.instanceURL
                )
                AppFeedbackCenter.shared.showInfo(MoroL10n.AppCoord.currentLoggedOut)
            } else {
                appState.reset()
                destination = .login
                StartupPerformanceTracker.shared.reset()
                AppFeedbackCenter.shared.showInfo(MoroL10n.AppCoord.loggedOut)
            }

            reloadSessions()
        }
    }

    private func reloadSessions() {
        accountSessions = authService.storedSessions()
        activeSessionID = authService.activeStoredSessionID()
    }

    private func applyAuthenticatedState(
        token: String,
        account: Account,
        instanceURL: URL,
        persistSession: Bool,
        identityValidated: Bool
    ) {
        if persistSession {
            authService.persistSession(
                token: token,
                account: account,
                instanceURL: instanceURL,
                activate: true
            )
        }

        appState.authToken = token
        appState.currentAccount = account
        appState.isAuthenticated = true
        appState.unreadAnnouncementsCount = 0
        CacheManager.shared.accountCache.set(account)
        if identityValidated {
            lastIdentityRefreshAt = Date()
            markIdentityValidationSuccess(sessionID: authService.activeStoredSessionID())
        } else {
            // Seed a short cooldown to avoid foreground refresh racing initial timeline requests.
            lastIdentityRefreshAt = Date()
        }

        let interceptor = AuthInterceptor(tokenProvider: appState)
        apiClient = MastodonClient(baseURL: instanceURL, authInterceptor: interceptor)

        destination = .main
        StartupPerformanceTracker.shared.markMainDestinationShownIfNeeded()
        reloadSessions()

        // Standard push onboarding: permission prompt on first arrival at the
        // main UI, then automatic relay subscription for this session.
        PushSubscriptionCoordinator.shared.activate(
            apiClient: apiClient,
            sessionKey: authService.activeStoredSessionID()
        )
    }

    private func reconcileStartupSession(seedToken: String) async {
        guard !Task.isCancelled else { return }
        guard appState.authToken == seedToken else { return }
        StartupPerformanceTracker.shared.markIdentityRefreshStarted(trigger: "startup")

        do {
            let refreshed = try await apiClient.verifyCredentials()
            guard !Task.isCancelled else { return }
            guard appState.authToken == seedToken else { return }

            if shouldPublishCurrentAccountUpdate(current: appState.currentAccount, refreshed: refreshed) {
                appState.currentAccount = refreshed
                CacheManager.shared.accountCache.set(refreshed)
                authService.updateActiveSessionAccount(refreshed)
                reloadSessions()
            } else {
                // Keep cache/session warm without triggering redundant @Published updates.
                CacheManager.shared.accountCache.set(refreshed)
            }
            lastIdentityRefreshAt = Date()
            markIdentityValidationSuccess()
            StartupPerformanceTracker.shared.markIdentityRefreshFinished(
                trigger: "startup",
                success: true
            )
        } catch {
            StartupPerformanceTracker.shared.markIdentityRefreshFinished(
                trigger: "startup",
                success: false
            )

            guard appState.authToken == seedToken else { return }
            if let apiError = error as? APIError, apiError.requiresReauthentication {
                await handleStartupAuthenticationInvalidation()
            }
            // Keep cached account state for transient network errors.
        }
    }

    private func bindCurrentAccountUpdates() {
        appState.$currentAccount
            .sink { [weak self] account in
                guard let self, let account else { return }
                authService.updateActiveSessionAccount(account)
                reloadSessions()
            }
            .store(in: &cancellables)
    }

    private func handleStartupAuthenticationInvalidation() async {
        if let activeSessionID {
            authService.removeStoredSession(id: activeSessionID)
        }

        if let restored = try? await authService.restoreSession() {
            applyAuthenticatedState(
                token: restored.token,
                account: restored.account,
                instanceURL: restored.instanceURL,
                persistSession: false,
                identityValidated: true
            )
            return
        }

        appState.reset()
        CacheManager.shared.clearAll()
        let hasOnboarded = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        destination = hasOnboarded ? .login : .onboarding
        StartupPerformanceTracker.shared.reset()
        reloadSessions()
    }

    private func scheduleStartupSessionValidation(seedToken: String, sessionID: String) {
        startupSessionValidationTask?.cancel()

        let recentValidation = lastIdentityValidationSuccessDate(for: sessionID)
        if let recentValidation,
            Date().timeIntervalSince(recentValidation) < startupIdentityValidationCooldown
        {
            // Recently validated identity does not need another delayed startup request.
            // This avoids adding verify_credentials traffic during active timeline interactions.
            return
        }
        let delay = startupIdentityValidationDelayAfterFirstContent

        startupSessionValidationTask = Task { [weak self] in
            guard let self else { return }
            if !StartupPerformanceTracker.shared.hasTimelineFirstContentReady {
                await StartupPerformanceTracker.shared.waitForTimelineFirstContentReady(
                    timeout: startupIdentityValidationWaitForTimelineTimeout
                )
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self.reconcileStartupSession(seedToken: seedToken)
            await MainActor.run {
                self.startupSessionValidationTask = nil
            }
        }
    }

    private func markIdentityValidationSuccess(sessionID: String? = nil) {
        let resolvedSessionID = sessionID ?? activeSessionID ?? authService.activeStoredSessionID()
        guard let resolvedSessionID else { return }
        let key = "\(identityValidationTimestampPrefix)\(resolvedSessionID)"
        UserDefaults.standard.set(Date(), forKey: key)
    }

    private func lastIdentityValidationSuccessDate(for sessionID: String) -> Date? {
        let key = "\(identityValidationTimestampPrefix)\(sessionID)"
        return UserDefaults.standard.object(forKey: key) as? Date
    }

    private func shouldPublishCurrentAccountUpdate(current: Account?, refreshed: Account) -> Bool {
        guard let current else { return true }

        return current.id != refreshed.id
            || current.username != refreshed.username
            || current.acct != refreshed.acct
            || current.displayName != refreshed.displayName
            || current.note != refreshed.note
            || current.avatar != refreshed.avatar
            || current.avatarStatic != refreshed.avatarStatic
            || current.header != refreshed.header
            || current.headerStatic != refreshed.headerStatic
            || current.followersCount != refreshed.followersCount
            || current.followingCount != refreshed.followingCount
            || current.statusesCount != refreshed.statusesCount
            || current.createdAt != refreshed.createdAt
            || current.locked != refreshed.locked
            || current.bot != refreshed.bot
            || current.fields != refreshed.fields
            || current.url != refreshed.url
            || current.suspended != refreshed.suspended
            || current.limited != refreshed.limited
            || current.movedAccount?.id != refreshed.movedAccount?.id
    }
}
