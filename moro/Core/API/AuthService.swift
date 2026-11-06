//
//  AuthService.swift
//  moro
//
//  Handles Mastodon OAuth authentication flow.
//

import Foundation
import UIKit
import Combine
import CryptoKit

@MainActor
final class AuthService: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    struct CachedActiveSession {
        let sessionID: String
        let token: String
        let account: Account
        let instanceURL: URL
    }

    /// A stored session chosen to become active. `isVerified` is false when the server could
    /// not be reached: the stored identity is used and the caller revalidates later.
    struct RestoredSession {
        let token: String
        let account: Account
        let instanceURL: URL
        let isVerified: Bool
    }

    typealias CredentialVerifier = @MainActor (_ instanceURL: URL, _ token: String) async throws -> Account

    enum AuthState {
        case idle
        case validatingInstance
        case instanceValidated(MastodonInstance)
        case creatingApp
        case appCreated(OAuthApp)
        case authorizing
        case authorized
        case error(Error)
    }

    @Published var state: AuthState = .idle
    @Published var currentInstance: MastodonInstance?
    @Published var currentRegistrationInfo: InstanceRegistrationInfo?
    @Published var currentOAuthApp: OAuthApp?

    let keychain: KeychainService
    private let sessionStore: AccountSessionStore
    private var baseURL: URL?
    private var apiClient: MastodonClient?
    private var authenticationController: MastodonAuthenticationController?
    // OAuth CSRF `state` + PKCE verifier, generated per authorize and consumed on the
    // token exchange / callback validation.
    private var pendingOAuthState: String?
    private var pendingCodeVerifier: String?
    private let verifyCredentials: CredentialVerifier

    init(
        keychain: KeychainService = KeychainService(),
        sessionStore: AccountSessionStore? = nil,
        verifyCredentials: CredentialVerifier? = nil
    ) {
        self.keychain = keychain
        self.sessionStore = sessionStore ?? AccountSessionStore(keychain: keychain)
        self.verifyCredentials = verifyCredentials ?? { instanceURL, token in
            try await AuthService.makeAuthenticatedClient(baseURL: instanceURL, token: token)
                .verifyCredentials()
        }
    }

    private static func makeAuthenticatedClient(baseURL: URL, token: String) -> MastodonClient {
        let appState = AppState()
        appState.authToken = token
        return MastodonClient(baseURL: baseURL, authInterceptor: AuthInterceptor(tokenProvider: appState))
    }

    // MARK: - Public API

    func validateInstance(domain: String) async throws -> MastodonInstance {
        state = .validatingInstance

        // Normalize domain (add https:// if missing)
        let normalizedDomain = domain.trimmingCharacters(in: .whitespaces)
        let baseURLString = normalizedDomain.hasPrefix("http") ? normalizedDomain : "https://\(normalizedDomain)"
        guard let url = URL(string: baseURLString) else {
            let error = NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: MoroL10n.Login.errorInvalidFormat])
            state = .error(error)
            throw error
        }

        self.baseURL = url

        // Create a temporary client without auth for instance validation
        let interceptor = AuthInterceptor(tokenProvider: nil)
        let client = MastodonClient(baseURL: url, authInterceptor: interceptor)

        do {
            let instance = try await client.fetchInstance()
            self.currentInstance = instance
            self.currentRegistrationInfo = registrationInfo(from: instance, baseURL: url)
            self.apiClient = client
            state = .instanceValidated(instance)
            return instance
        } catch {
            state = .error(error)
            throw error
        }
    }

    /// Fetch the server's long-form "about this site" page (server-rendered HTML). This is a
    /// public endpoint that needs no auth; returns nil when the server doesn't expose one or
    /// the request fails, so callers can fall back to the short description.
    func fetchExtendedDescription(domain: String) async -> String? {
        let normalized = domain.trimmingCharacters(in: .whitespaces)
        let base = normalized.hasPrefix("http") ? normalized : "https://\(normalized)"
        guard let url = URL(string: "\(base)/api/v1/instance/extended_description") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
            let decoded = try JSONDecoder().decode(ExtendedInstanceDescription.self, from: data)
            let trimmed = decoded.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }

    func startOAuthFlow(redirectURI: String = "moro://oauth/callback", scopes: String = "read write follow push") async throws -> MastodonAuthenticationController {
        guard let baseURL = baseURL else {
            throw NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: MoroL10n.Login.errorValidation])
        }

        state = .creatingApp

        guard let client = apiClient else {
            throw NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: MoroL10n.Login.errorAuth])
        }

        do {
            let app = try await getOrCreateOAuthApp(
                client: client,
                host: baseURL.host ?? baseURL.absoluteString,
                redirectURI: redirectURI,
                scopes: scopes
            )
            self.currentOAuthApp = app
            state = .appCreated(app)

            // CSRF `state` + PKCE (S256). Stored so we can validate the callback and
            // send the verifier on token exchange.
            let oauthState = Self.randomURLSafeToken()
            let codeVerifier = Self.randomURLSafeToken(byteCount: 64)
            let codeChallenge = Self.codeChallengeS256(for: codeVerifier)
            self.pendingOAuthState = oauthState
            self.pendingCodeVerifier = codeVerifier

            // Build authorization URL
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            components?.path = "/oauth/authorize"
            components?.queryItems = [
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "client_id", value: app.clientID),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(name: "scope", value: scopes),
                URLQueryItem(name: "state", value: oauthState),
                URLQueryItem(name: "code_challenge", value: codeChallenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
            ]

            guard let authURL = components?.url else {
                throw NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: MoroL10n.Login.errorAuth])
            }

            state = .authorizing
            let controller = MastodonAuthenticationController(
                authenticateURL: authURL,
                callbackURLScheme: "moro",
                expectedState: oauthState
            )
            self.authenticationController = controller
            return controller
        } catch {
            state = .error(error)
            throw error
        }
    }

    func handleOAuthCode(_ code: String) async throws -> (token: String, account: Account, instanceURL: URL) {
        guard let app = currentOAuthApp, let baseURL = baseURL, let client = apiClient else {
            throw NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: MoroL10n.Login.errorAuth])
        }

        // Exchange code for token (with the PKCE verifier captured at authorize time)
        let redirectURI = "moro://oauth/callback"
        let codeVerifier = pendingCodeVerifier
        pendingCodeVerifier = nil
        pendingOAuthState = nil
        let tokenResponse = try await client.exchangeOAuthToken(
            code: code,
            clientID: app.clientID,
            clientSecret: app.clientSecret,
            redirectURI: redirectURI,
            codeVerifier: codeVerifier
        )

        // Update API client with new token
        let appState = AppState()
        appState.authToken = tokenResponse.accessToken
        let interceptor = AuthInterceptor(tokenProvider: appState)
        let authenticatedClient = MastodonClient(baseURL: baseURL, authInterceptor: interceptor)

        // Get current user account
        let account = try await authenticatedClient.verifyCredentials()

        // Persist account session and mark as active
        _ = try sessionStore.saveSession(
            token: tokenResponse.accessToken,
            account: account,
            instanceURL: baseURL,
            activate: true
        )

        state = .authorized
        return (token: tokenResponse.accessToken, account: account, instanceURL: baseURL)
    }

    // MARK: - PKCE / CSRF helpers

    /// URL-safe random token (base64url, no padding). The system RNG is
    /// cryptographically secure on Apple platforms.
    private static func randomURLSafeToken(byteCount: Int = 32) -> String {
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
        return base64URLEncode(Data(bytes))
    }

    /// S256 code challenge = base64url(SHA256(verifier)).
    private static func codeChallengeS256(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - OAuth App Cache

    /// A per-instance OAuth app registration cached in the keychain, so we don't re-register
    /// a fresh app on `/api/v1/apps` for every login (wasteful; some instances rate-limit it).
    private struct CachedOAuthApp: Codable {
        let app: OAuthApp
        let scopes: String
    }

    private func oauthAppCacheKey(host: String) -> String {
        "oauth_app_v1_\(host.lowercased())"
    }

    /// Reuse the cached registration for `host` when its redirect URI + scopes still match
    /// what we're requesting (so an app-config change forces a fresh registration);
    /// otherwise register a new app and cache it.
    private func getOrCreateOAuthApp(
        client: MastodonClient,
        host: String,
        redirectURI: String,
        scopes: String
    ) async throws -> OAuthApp {
        if let json = try? keychain.get(forKey: oauthAppCacheKey(host: host)),
            let data = json.data(using: .utf8),
            let cached = try? JSONDecoder().decode(CachedOAuthApp.self, from: data),
            cached.app.redirectURI == redirectURI,
            cached.scopes == scopes
        {
            return cached.app
        }

        let app = try await client.createOAuthApp(
            clientName: "Moro",
            redirectURIs: redirectURI,
            scopes: scopes,
            website: nil
        )
        if let data = try? JSONEncoder().encode(CachedOAuthApp(app: app, scopes: scopes)),
            let json = String(data: data, encoding: .utf8)
        {
            try? keychain.save(json, forKey: oauthAppCacheKey(host: host))
        }
        return app
    }

    func registerAccount(request: AccountRegistrationRequest) async throws -> RegistrationResult {
        guard let baseURL = baseURL, let client = apiClient else {
            throw NSError(
                domain: "AuthService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: MoroL10n.Login.errorValidation]
            )
        }

        let oauthApp: OAuthApp
        if let currentOAuthApp {
            oauthApp = currentOAuthApp
        } else {
            state = .creatingApp
            oauthApp = try await getOrCreateOAuthApp(
                client: client,
                host: baseURL.host ?? baseURL.absoluteString,
                redirectURI: "moro://oauth/callback",
                scopes: "read write follow push"
            )
            self.currentOAuthApp = oauthApp
            state = .appCreated(oauthApp)
        }

        let appToken = try await client.requestApplicationAccessToken(
            clientID: oauthApp.clientID,
            clientSecret: oauthApp.clientSecret,
            redirectURI: "moro://oauth/callback"
        )

        let registrationToken = try await client.registerAccount(
            request: request,
            appAccessToken: appToken.accessToken
        )

        let userAccessToken = registrationToken.accessToken
        guard !userAccessToken.isEmpty else {
            throw NSError(
                domain: "AuthService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: MoroL10n.Auth.registeredNoCredentials]
            )
        }

        let appState = AppState()
        appState.authToken = userAccessToken
        let interceptor = AuthInterceptor(tokenProvider: appState)
        let authenticatedClient = MastodonClient(baseURL: baseURL, authInterceptor: interceptor)

        do {
            let account = try await authenticatedClient.verifyCredentials()
            _ = try sessionStore.saveSession(
                token: userAccessToken,
                account: account,
                instanceURL: baseURL,
                activate: true
            )
            state = .authorized
            return .authenticated(token: userAccessToken, account: account, instanceURL: baseURL)
        } catch let apiError as APIError {
            if shouldTreatRegistrationAsPending(error: apiError) {
                return .pending(
                    email: request.email,
                    requiresApproval: currentRegistrationInfo?.approvalRequired ?? false,
                    hint: pendingHint(for: apiError)
                )
            }
            throw apiError
        }
    }

    /// Activates the next usable stored session.
    ///
    /// A session is deleted only when its server rejects the token (401). Offline, timeouts,
    /// 5xx and account-state answers (403) keep every stored account: the stored identity is
    /// returned unverified so removing one account while offline never wipes the others.
    func restoreSession() async throws -> RestoredSession? {
        var attemptedSessionIDs = Set<String>()
        while let payload = try sessionStore.activePayload(),
            attemptedSessionIDs.insert(payload.session.id).inserted
        {
            do {
                let account = try await verifyCredentials(payload.instanceURL, payload.token)
                _ = try sessionStore.saveSession(
                    token: payload.token,
                    account: account,
                    instanceURL: payload.instanceURL,
                    activate: true
                )
                adoptActiveClient(baseURL: payload.instanceURL, token: payload.token)
                return RestoredSession(
                    token: payload.token, account: account,
                    instanceURL: payload.instanceURL, isVerified: true)
            } catch let error as APIError where error.requiresReauthentication {
                // The server says this token is dead: drop it and try the next account.
                try? sessionStore.removeSession(id: payload.session.id)
            } catch {
                adoptActiveClient(baseURL: payload.instanceURL, token: payload.token)
                return RestoredSession(
                    token: payload.token, account: payload.session.account,
                    instanceURL: payload.instanceURL, isVerified: false)
            }
        }

        // Legacy single-session migration fallback.
        if let token = try keychain.get(forKey: "access_token"),
            let instanceURLString = try keychain.get(forKey: "instance_url"),
            let instanceURL = URL(string: instanceURLString)
        {
            do {
                let account = try await verifyCredentials(instanceURL, token)
                _ = try sessionStore.saveSession(
                    token: token,
                    account: account,
                    instanceURL: instanceURL,
                    activate: true
                )
                adoptActiveClient(baseURL: instanceURL, token: token)
                return RestoredSession(
                    token: token, account: account, instanceURL: instanceURL, isVerified: true)
            } catch let error as APIError where error.requiresReauthentication {
                try? keychain.delete(forKey: "access_token")
                try? keychain.delete(forKey: "instance_url")
                AppEnvironment.invalidateInstanceURL()
                return nil
            } catch {
                // No stored identity to fall back on; keep the credentials for the next launch.
                return nil
            }
        }

        return nil
    }

    private func adoptActiveClient(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.apiClient = Self.makeAuthenticatedClient(baseURL: baseURL, token: token)
    }

    func cachedActiveSession() -> CachedActiveSession? {
        guard let payload = try? sessionStore.activePayload() else { return nil }

        return CachedActiveSession(
            sessionID: payload.session.id,
            token: payload.token,
            account: payload.session.account,
            instanceURL: payload.instanceURL
        )
    }

    func persistSession(token: String, account: Account, instanceURL: URL, activate: Bool = true) {
        _ = try? sessionStore.saveSession(
            token: token,
            account: account,
            instanceURL: instanceURL,
            activate: activate
        )
    }

    func storedSessions() -> [StoredAccountSession] {
        sessionStore.allSessions()
    }

    func activeStoredSessionID() -> String? {
        sessionStore.activeSessionID
    }

    func updateActiveSessionAccount(_ account: Account) {
        sessionStore.updateActiveAccount(account)
    }

    func switchToSession(id: String) async throws -> (token: String, account: Account, instanceURL: URL)? {
        guard let payload = try sessionStore.payload(forSessionID: id) else { return nil }

        let appState = AppState()
        appState.authToken = payload.token
        let interceptor = AuthInterceptor(tokenProvider: appState)
        let client = MastodonClient(baseURL: payload.instanceURL, authInterceptor: interceptor)
        let refreshed = try await client.verifyCredentials()

        _ = try sessionStore.saveSession(
            token: payload.token,
            account: refreshed,
            instanceURL: payload.instanceURL,
            activate: true
        )
        self.baseURL = payload.instanceURL
        self.apiClient = client
        return (token: payload.token, account: refreshed, instanceURL: payload.instanceURL)
    }

    func removeStoredSession(id: String) {
        try? sessionStore.removeSession(id: id)
    }

    func clearAllStoredSessions() {
        sessionStore.clearAllSessions()
    }

    func logout() throws {
        sessionStore.clearAllSessions()
        state = .idle
        currentInstance = nil
        currentRegistrationInfo = nil
        currentOAuthApp = nil
        baseURL = nil
        apiClient = nil
    }

    // MARK: - Registration Helpers

    private func registrationInfo(from instance: MastodonInstance, baseURL: URL) -> InstanceRegistrationInfo {
        InstanceRegistrationInfo(
            domain: normalizedHost(instance.uri, fallback: baseURL.host ?? instance.uri),
            title: instance.title,
            description: instance.description,
            registrationsOpen: instance.registrations ?? true,
            approvalRequired: instance.approvalRequired ?? false,
            reasonRequired: instance.approvalRequired ?? false,
            minAge: nil,
            registrationMessage: nil,
            rules: instance.rules ?? []
        )
    }

    private func normalizedHost(_ rawValue: String?, fallback: String) -> String {
        guard let rawValue else { return fallback }
        if rawValue.contains("://"), let url = URL(string: rawValue), let host = url.host {
            return host
        }
        return rawValue.replacingOccurrences(of: "/", with: "")
    }

    private func shouldTreatRegistrationAsPending(error: APIError) -> Bool {
        if error.requiresReauthentication {
            return true
        }
        if let status = error.httpStatusCode, [401, 403].contains(status) {
            return true
        }
        if case .serverError(let serverError) = error {
            let message = serverError.combinedMessage.lowercased()
            if message.contains("confirm your email")
                || message.contains("awaiting")
                || message.contains("approved")
                || message.contains("pending")
            {
                return true
            }
        }
        return false
    }

    private func pendingHint(for error: APIError) -> String? {
        if case .serverError(let serverError) = error {
            let raw = serverError.combinedMessage.lowercased()
            if raw.contains("confirm your email") || raw.contains("confirmation") {
                return MoroL10n.Auth.confirmEmail
            }
            if raw.contains("approved") || raw.contains("awaiting") || raw.contains("pending") {
                return MoroL10n.Auth.pendingApproval
            }
        }
        if currentRegistrationInfo?.approvalRequired == true {
            return MoroL10n.Auth.pendingApproval
        }
        return MoroL10n.Auth.registrationSubmitted
    }
}
