//
//  MastodonAuthenticationController.swift
//  moro
//
//  Handles OAuth authentication session using ASWebAuthenticationSession.
//

import Foundation
import AuthenticationServices

final class MastodonAuthenticationController: NSObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    private var authenticationSession: ASWebAuthenticationSession?
    private let authenticateURL: URL
    private let callbackURLScheme: String
    private var resultContinuation: AsyncThrowingStream<String, Error>.Continuation?
    private let expectedState: String?

    init(authenticateURL: URL, callbackURLScheme: String = "moro", expectedState: String? = nil) {
        self.authenticateURL = authenticateURL
        self.callbackURLScheme = callbackURLScheme
        self.expectedState = expectedState
        super.init()
    }

    func start() -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            self.resultContinuation = continuation

            authenticationSession = ASWebAuthenticationSession(
                url: authenticateURL,
                callbackURLScheme: callbackURLScheme
            ) { [weak self] callbackURL, error in
                guard let self = self else { return }

                if let error = error {
                    if let authError = error as? ASWebAuthenticationSessionError,
                       authError.code == .canceledLogin {
                        // User canceled, don't report as error
                        self.resultContinuation?.finish()
                        return
                    }
                    self.resultContinuation?.finish(throwing: error)
                    return
                }

                guard let url = callbackURL,
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let codeQueryItem = components.queryItems?.first(where: { $0.name == "code" }),
                      let code = codeQueryItem.value else {
                    self.resultContinuation?.finish()
                    return
                }

                // Validate CSRF state when one was sent with the authorize request.
                if let expectedState = self.expectedState {
                    let returnedState = components.queryItems?
                        .first(where: { $0.name == "state" })?.value
                    guard returnedState == expectedState else {
                        self.resultContinuation?.finish(
                            throwing: NSError(
                                domain: "MastodonAuthenticationController",
                                code: -2,
                                userInfo: [NSLocalizedDescriptionKey: MoroL10n.Login.errorAuth]
                            ))
                        return
                    }
                }

                self.resultContinuation?.yield(code)
                self.resultContinuation?.finish()
            }

            authenticationSession?.prefersEphemeralWebBrowserSession = true
            authenticationSession?.presentationContextProvider = self
            authenticationSession?.start()
        }
    }

    func cancel() {
        authenticationSession?.cancel()
        resultContinuation?.finish()
    }
}

extension MastodonAuthenticationController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Prefer the active foreground key window; fall back to any window, then a
        // fresh one — never crash just to present the auth sheet.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeWindow = scenes
            .first { $0.activationState == .foregroundActive }?
            .windows.first { $0.isKeyWindow }
        if let window = activeWindow
            ?? scenes.flatMap({ $0.windows }).first
            ?? scenes.first.map({ UIWindow(windowScene: $0) })
        {
            return window
        }
        // Unreachable in practice: the system only requests an anchor while the app
        // is foreground, so a window scene always exists and one of the branches
        // above returns. UIWindow() is deprecated on iOS 26 but is the only
        // scene-less initializer, and the contract here is to never crash.
        return ASPresentationAnchor()
    }
}

