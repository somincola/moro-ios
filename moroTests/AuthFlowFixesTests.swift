//
//  AuthFlowFixesTests.swift
//  moroTests
//
//  Regression tests for the login/auth robustness fixes:
//  - AuthInterceptor retains its token provider strongly (so one-shot authenticated
//    requests don't lose the Bearer token when the caller's reference goes away).
//  - AppCoordinator caches the login AuthService across renders instead of rebuilding it.
//

import Testing
@testable import moro
import Foundation

struct AuthFlowFixesTests {

    private final class StubTokenProvider: AuthTokenProvider {
        var authToken: String?
        init(authToken: String?) { self.authToken = authToken }
    }

    /// The interceptor must keep its provider alive even after the caller drops its own
    /// reference. With a weak ref the provider would deallocate here and the request would
    /// go out with no Authorization header (the latent release-build login bug).
    @Test func interceptorRetainsTokenProviderStrongly() {
        var provider: AuthTokenProvider? = StubTokenProvider(authToken: "tok-123")
        let interceptor = AuthInterceptor(tokenProvider: provider)
        provider = nil  // drop the only other strong reference

        var request = URLRequest(url: URL(string: "https://example.com")!)
        interceptor.apply(to: &request)

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-123")
    }

    @Test func capturedCredentialsStayWithOriginalAccount() {
        let provider = StubTokenProvider(authToken: "account-a")
        let original = AuthInterceptor(tokenProvider: provider)
        let snapshot = original.snapshot()
        provider.authToken = "account-b"
        var request = URLRequest(url: URL(string: "https://example.com")!)
        snapshot.apply(to: &request)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer account-a")
        original.apply(to: &request)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer account-b")
    }

    /// Repeated calls while the login screen is on-screen must reuse one AuthService
    /// instead of rebuilding it (and a fresh AccountSessionStore) on every render.
    @Test @MainActor func loginAuthServiceIsCachedAcrossCalls() {
        let appState = AppState()
        let interceptor = AuthInterceptor(tokenProvider: appState)
        let client = MastodonClient(authInterceptor: interceptor)
        let coordinator = AppCoordinator(appState: appState, apiClient: client)

        let first = coordinator.getAuthServiceForLogin()
        let second = coordinator.getAuthServiceForLogin()

        #expect(first === second)
    }
}
