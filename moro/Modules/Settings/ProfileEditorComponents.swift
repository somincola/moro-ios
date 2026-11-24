import SwiftUI

struct ProfileEditorLoadingView: View {
    @Environment(\.moroTheme) private var theme
    let error: String?
    let retry: () -> Void

    var body: some View {
        Group {
            if let error {
                ErrorStateView(
                    spec: ErrorStateSpec(
                        title: MoroL10n.Timeline.loadFailed,
                        message: error,
                        actionTitle: MoroL10n.Timeline.retry,
                        action: retry
                    )
                )
            } else {
                MoroLoadingStateView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.surfaceBase)
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
                        .accessibilityIdentifier("profile.editor.back")
                    }
                }
            }
            .confirmationDialog(MoroL10n.EditProfile.discardTitle, isPresented: $confirmDiscard,
                                titleVisibility: .visible) {
                Button(MoroL10n.EditProfile.discardAction, role: .destructive) { dismiss() }
                    .accessibilityIdentifier("profile.editor.discard")
                Button(MoroL10n.EditProfile.discardContinue, role: .cancel) {}
            } message: {
                Text(MoroL10n.EditProfile.discardMessage)
            }
    }
}

extension View {
    func profileEditorChrome() -> some View {
        moroSettingsListChrome()
    }

    func profileEditorExitGuard(hasChanges: Bool, isSaving: Bool) -> some View {
        modifier(ProfileEditorExitGuard(hasChanges: hasChanges, isSaving: isSaving))
    }
}
