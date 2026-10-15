#if DEBUG
import SwiftUI

/// Shows the onboarding globe or the login page on its own, for tuning their motion.
/// `UITEST_ONBOARDING_VARIANT` = globe | login.
struct OnboardingPreviewHarness: View {
    @State private var result: OnboardingCompletion?
    @State private var run = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var variant: String {
        ProcessInfo.processInfo.environment["UITEST_ONBOARDING_VARIANT"] ?? "globe"
    }

    private var theme: MoroTheme {
        MoroTheme(
            colorScheme: ProcessInfo.processInfo.environment["UITEST_COLOR_SCHEME"] == "dark" ? .dark : .light,
            dynamicTypeSize: dynamicTypeSize)
    }

    var body: some View {
        ZStack {
            if let result {
                VStack(spacing: 16) {
                    Text(result == .registration ? "→ registration" : "→ login")
                        .font(.title3.weight(.semibold))
                    Button("Replay") { self.result = nil; run += 1 }
                        .accessibilityIdentifier("onboarding.replay")
                }
                .foregroundStyle(theme.colors.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.colors.surfaceBase)
            } else {
                variantView.id(run)
            }
        }
        .moroTheme(theme)
    }

    @ViewBuilder private var variantView: some View {
        switch variant {
        case "login":
            LoginView(authService: AuthService()) { _, _, _ in }
        default:
            OnboardingGlobeView(onFinish: { result = $0 })
        }
    }
}
#endif
