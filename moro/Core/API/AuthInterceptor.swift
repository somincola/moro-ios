//
//  AuthInterceptor.swift
//  moro
//
//  Applies OAuth tokens to requests.
//

import Foundation

protocol AuthTokenProvider: AnyObject {
    var authToken: String? { get }
}

final class AuthInterceptor {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    // Held strongly: one-shot authenticated clients (login / session restore / account
    // switch) pass a short-lived AppState as the provider. A weak ref let ARC release it
    // right after its last syntactic use — before the request ran — so the Bearer token
    // was dropped (a 401 in optimized release builds). AppState never references the
    // client/interceptor back, so a strong ref introduces no retain cycle.
    var tokenProvider: AuthTokenProvider?

    init(tokenProvider: AuthTokenProvider?) {
        self.tokenProvider = tokenProvider
    }

    func apply(to request: inout URLRequest) {
        guard let token = tokenProvider?.authToken else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
}

