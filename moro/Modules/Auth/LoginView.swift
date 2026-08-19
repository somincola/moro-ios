//
//  LoginView.swift
//  moro
//
//  Mastodon instance login screen with OAuth flow.
//

import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @ObservedObject var authService: AuthService
    @State private var instanceDomain: String = RecommendedServers.primary
    @State private var isLoading = false
    @State private var showingRegistration: Bool
    @State private var feedbackMessage: String?
    @State private var feedbackKind: AppFeedbackKind = .info
    @State private var retryAction: (() -> Void)?

    let onAuthSuccess: (String, Account, URL) -> Void
    @Environment(\.moroTheme) private var theme

    init(
        authService: AuthService,
        startsInRegistration: Bool = false,
        onAuthSuccess: @escaping (String, Account, URL) -> Void
    ) {
        _authService = ObservedObject(wrappedValue: authService)
        _showingRegistration = State(initialValue: startsInRegistration)
        self.onAuthSuccess = onAuthSuccess
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: theme.spacing.xxxl) {
                        loginHeader

                        VStack(spacing: theme.spacing.xl) {
                            domainField

                            if let feedbackMessage {
                                InlineFeedbackCard(
                                    kind: feedbackKind,
                                    message: feedbackMessage,
                                    actionTitle: retryAction != nil ? MoroL10n.Login.retry : nil,
                                    action: retryAction
                                )
                            }
                        }
                    }

                    Spacer(minLength: 72)

                    actionGroup
                }
                .padding(.horizontal, theme.spacing.xl)
                .padding(.top, 76)
                .padding(.bottom, 64)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .background(theme.colors.surfaceBase)
        }
        .animation(.default, value: feedbackMessage)
        .fullScreenCover(isPresented: $showingRegistration) {
            RegistrationCoordinatorView(
                authService: authService,
                onAuthenticated: { token, account, instanceURL in
                    showingRegistration = false
                    onAuthSuccess(token, account, instanceURL)
                },
                onClose: { showingRegistration = false }
            )
        }
    }

    // MARK: - Subviews

    private var loginHeader: some View {
        VStack(spacing: theme.spacing.l) {
            Image("AppIconPreviewDefault")
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(theme.colors.borderSubtle, lineWidth: 1)
                }
                .shadow(color: theme.colors.textPrimary.opacity(0.08), radius: 14, y: 8)
                .accessibilityHidden(true)

            VStack(spacing: theme.spacing.s) {
                Text(MoroL10n.Login.title)
                    .font(theme.typography.title)
                    .foregroundStyle(theme.colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(MoroL10n.Login.subtitle)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var domainField: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            Text(MoroL10n.Login.instanceAddress)
                .font(theme.typography.bodyStrong)
                .foregroundStyle(theme.colors.textPrimary)

            HStack(spacing: theme.spacing.s) {
                Image(systemName: "globe")
                    .moroScaledFont(size: 16, weight: .regular)
                    .foregroundStyle(theme.colors.textSecondary)

                TextField(RecommendedServers.primary, text: $instanceDomain)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .disabled(isLoading)
                    .onSubmit { login() }
                    .onChange(of: instanceDomain) { _, _ in
                        feedbackMessage = nil
                        retryAction = nil
                    }

                if !instanceDomain.isEmpty && !isLoading {
                    Button {
                        instanceDomain = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .moroScaledFont(size: 16)
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, theme.spacing.m)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.colors.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(theme.colors.borderSubtle, lineWidth: 1)
            )
        }
    }

    private var actionGroup: some View {
        VStack(spacing: theme.spacing.m) {
            loginButton
            registerLink
        }
        .frame(maxWidth: .infinity)
    }

    private var loginButton: some View {
        Button {
            login()
        } label: {
            ZStack {
                Text(MoroL10n.Login.login)
                    .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(theme.colors.primaryForeground)
                }
            }
            .font(theme.typography.subtitle)
            .foregroundStyle(theme.colors.primaryForeground)
            .frame(width: 220, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.colors.primary500)
            )
        }
        .buttonStyle(.plain)
        .disabled(sanitizedDomain.isEmpty || isLoading)
        .opacity(sanitizedDomain.isEmpty ? 0.55 : 1)
        .frame(maxWidth: .infinity)
    }

    private var registerLink: some View {
        Button {
            showingRegistration = true
        } label: {
            Text(MoroL10n.Login.registerNewAccount)
                .font(theme.typography.bodyStrong)
                .foregroundStyle(theme.colors.textPrimary)
                .padding(.vertical, theme.spacing.s)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .opacity(isLoading ? 0.55 : 1)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Login (one tap: validate + authorize)

    private func login() {
        let domain = sanitizedDomain
        guard !domain.isEmpty else { return }
        guard isLikelyDomain(domain) else {
            setFeedback(MoroL10n.Login.errorInvalidFormat, kind: .error, retry: nil)
            return
        }

        dismissKeyboard()
        isLoading = true
        feedbackMessage = nil
        retryAction = nil

        Task {
            do {
                _ = try await authService.validateInstance(domain: domain)
            } catch {
                await MainActor.run {
                    isLoading = false
                    setFeedback(userFriendlyValidationError(error), kind: .error, retry: login)
                }
                return
            }

            do {
                let controller = try await authService.startOAuthFlow()
                for try await code in controller.start() {
                    let result = try await authService.handleOAuthCode(code)
                    await MainActor.run {
                        isLoading = false
                        onAuthSuccess(result.token, result.account, result.instanceURL)
                    }
                    return
                }
                await MainActor.run { isLoading = false }
            } catch {
                await MainActor.run {
                    isLoading = false
                    if let authError = error as? ASWebAuthenticationSessionError,
                        authError.code == .canceledLogin {
                        setFeedback(MoroL10n.Login.errorAuthCancelled, kind: .info, retry: login)
                    } else {
                        setFeedback(userFriendlyAuthorizationError(error), kind: .error, retry: login)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var sanitizedDomain: String {
        AuthDomainUtility.sanitize(instanceDomain)
    }

    private func isLikelyDomain(_ domain: String) -> Bool {
        AuthDomainUtility.isLikelyDomain(domain)
    }

    private func setFeedback(_ message: String, kind: AppFeedbackKind, retry: (() -> Void)?) {
        feedbackMessage = message
        feedbackKind = kind
        retryAction = retry
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func userFriendlyValidationError(_ error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("offline") || raw.contains("network") {
            return MoroL10n.Login.errorNetworkValidation
        }
        return MoroL10n.Login.errorValidation
    }

    private func userFriendlyAuthorizationError(_ error: Error) -> String {
        let raw = ((error as? APIError)?.localizedDescription ?? error.localizedDescription).lowercased()
        if raw.contains("network") {
            return MoroL10n.Login.errorNetworkAuth
        }
        return MoroL10n.Login.errorAuth
    }
}

#Preview {
    NavigationStack {
        LoginView(authService: AuthService()) { _, _, _ in }
    }
    .moroTheme(MoroTheme())
}
