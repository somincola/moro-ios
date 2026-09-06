import SwiftUI

struct ProfileEditorLoadingView: View {
    @Environment(\.moroTheme) private var theme
    let error: String?
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            if let error {
                Text(error).font(theme.typography.body)
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                Button(MoroL10n.Timeline.retry, action: retry)
                    .buttonStyle(.bordered)
            } else {
                ProgressView()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.groupedBackground)
    }
}

private struct ProfileEditorExitGuard: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var confirmDiscard = false
    let hasChanges: Bool
    let isSaving: Bool

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(hasChanges || isSaving)
            .interactiveDismissDisabled(hasChanges || isSaving)
            .onChange(of: appState.authToken) { _, _ in dismiss() }
            .toolbar {
                if hasChanges || isSaving {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            confirmDiscard = true
                        } label: {
                            Image(systemName: "chevron.left")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .disabled(isSaving)
                        .accessibilityLabel(MoroL10n.EditProfile.back)
                    }
                }
            }
            .confirmationDialog(MoroL10n.EditProfile.discardTitle, isPresented: $confirmDiscard,
                                titleVisibility: .visible) {
                Button(MoroL10n.EditProfile.discardAction, role: .destructive) { dismiss() }
                Button(MoroL10n.EditProfile.discardContinue, role: .cancel) {}
            } message: {
                Text(MoroL10n.EditProfile.discardMessage)
            }
    }
}

extension View {
    func profileEditorChrome() -> some View {
        moroSettingsListChrome()
            .contentMargins(.top, 12, for: .scrollContent)
            .contentMargins(.bottom, 24, for: .scrollContent)
    }

    func profileEditorExitGuard(hasChanges: Bool, isSaving: Bool) -> some View {
        modifier(ProfileEditorExitGuard(hasChanges: hasChanges, isSaving: isSaving))
    }
}
