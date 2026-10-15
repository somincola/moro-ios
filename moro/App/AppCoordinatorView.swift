//
//  AppCoordinatorView.swift
//  moro
//
//  Root view that switches based on coordinator destination.
//

import SwiftUI

struct AppCoordinatorView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject private var feedbackCenter = AppFeedbackCenter.shared
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var revealsLoginUnderOnboarding = false

    private var effectiveTheme: MoroTheme {
        MoroTheme(
            colorScheme: colorScheme,
            accent: settings.accentStyle,
            themeColor: settings.themeColor,
            customThemeColor: settings.customThemeColor,
            postFontSize: settings.postFontSize,
            colorSchemeContrast: colorSchemeContrast,
            dynamicTypeSize: dynamicTypeSize
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch coordinator.destination {
                case .launch:
                    LaunchScreenView()
                case .onboarding:
                    ZStack {
                        if revealsLoginUnderOnboarding {
                            NavigationStack {
                                LoginView(authService: coordinator.getAuthServiceForLogin()) {
                                    token, account, instanceURL in
                                    coordinator.handleLoginSuccess(
                                        token: token,
                                        account: account,
                                        instanceURL: instanceURL
                                    )
                                }
                            }
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        }

                        OnboardingGlobeView(
                            onExitStart: {
                                revealsLoginUnderOnboarding = true
                            },
                            onFinish: coordinator.completeOnboarding
                        )
                    }
                case .login:
                    NavigationStack {
                        LoginView(
                            authService: coordinator.getAuthServiceForLogin(),
                            startsInRegistration: coordinator.opensRegistrationAfterOnboarding
                        ) { token, account, instanceURL in
                            coordinator.handleLoginSuccess(
                                token: token,
                                account: account,
                                instanceURL: instanceURL
                            )
                        }
                        .onAppear {
                            coordinator.consumeRegistrationAfterOnboarding()
                        }
                    }
                case .main:
                    MainTabView(
                        apiClient: coordinator.apiClient,
                        onLogout: coordinator.logout,
                        accountSessions: coordinator.accountSessions,
                        activeSessionID: coordinator.activeSessionID,
                        onSwitchAccount: coordinator.switchAccount,
                        onRemoveAccount: coordinator.removeAccount,
                        onAccountAuthenticated: coordinator.handleLoginSuccess
                    )
                    .id(coordinator.activeSessionID ?? "no-active-session")
                        .environmentObject(coordinator.appState)
                        .environment(\.mastodonAPIClient, coordinator.apiClient)
                }
            }

            if let message = feedbackCenter.currentMessage {
                MoroNoticePill(
                    icon: iconName(for: message.kind),
                    text: message.text
                )
                .frame(maxWidth: 420)
                .padding(.horizontal, MoroLayoutMetrics.contentHorizontalInset)
                .padding(.top, 8)
                .onTapGesture {
                    feedbackCenter.dismiss()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(999)
            }
        }
        .moroTheme(effectiveTheme)
        .environment(
            \.moroMediaPrefs,
            MoroMediaPreferences(settings: settings)
        )
    }

    private func iconName(for kind: AppFeedbackKind) -> String {
        switch kind {
        case .success:
            return "checkmark"
        case .error:
            return "exclamationmark"
        case .info:
            return "info"
        }
    }
}

#Preview {
    let appState = AppState()
    let interceptor = AuthInterceptor(tokenProvider: appState)
    let client = MastodonClient(authInterceptor: interceptor)
    let coordinator = AppCoordinator(appState: appState, apiClient: client)
    return AppCoordinatorView(coordinator: coordinator)
}
