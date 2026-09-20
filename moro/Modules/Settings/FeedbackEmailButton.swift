import SwiftUI
import MessageUI

/// One email flow shared by About and the dedicated feedback entry.
struct FeedbackEmailButton<Label: View>: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appState: AppState
    @State private var showFeedbackMethodPicker = false
    @State private var showFeedbackMailComposer = false
    @ViewBuilder let label: () -> Label

    private var feedbackBody: String {
        FeedbackMailContext.messageBody(currentAccount: appState.currentAccount)
    }

    var body: some View {
        Button { showFeedbackMethodPicker = true } label: { label() }
            .buttonStyle(.plain)
        .confirmationDialog(
            MoroL10n.Settings.feedbackDialogTitle,
            isPresented: $showFeedbackMethodPicker,
            titleVisibility: .visible
        ) {
            if FeedbackMailContext.canUseInAppComposer {
                Button(MoroL10n.Settings.feedbackInApp) {
                    showFeedbackMailComposer = true
                }
            }
            Button(MoroL10n.Settings.feedbackMailApp) {
                openFeedbackInMailApp()
            }
            Button(MoroL10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(MoroL10n.Settings.feedbackDestination(FeedbackMailContext.supportEmail))
        }
        #if canImport(MessageUI)
            .sheet(isPresented: $showFeedbackMailComposer) {
                FeedbackMailComposerView(
                    to: FeedbackMailContext.supportEmail,
                    subject: FeedbackMailContext.subject,
                    body: feedbackBody
                ) { result, error in
                    handleFeedbackMailResult(result: result, error: error)
                }
            }
        #endif
    }

    private func openFeedbackInMailApp() {
        guard let url = FeedbackMailContext.mailtoURL(
            email: FeedbackMailContext.supportEmail,
            subject: FeedbackMailContext.subject,
            body: feedbackBody
        ) else {
            AppFeedbackCenter.shared.showError(MoroL10n.Settings.feedbackMailLinkError)
            return
        }

        openURL(url) { accepted in
            if !accepted {
                AppFeedbackCenter.shared.showError(MoroL10n.Settings.feedbackMailAppError)
            }
        }
    }

    #if canImport(MessageUI)
        private func handleFeedbackMailResult(result: MFMailComposeResult, error: Error?) {
            if error != nil {
                AppFeedbackCenter.shared.showError(MoroL10n.Settings.feedbackMailFailed)
                return
            }

            switch result {
            case .sent:
                AppFeedbackCenter.shared.showSuccess(MoroL10n.Settings.feedbackMailSent)
            case .saved:
                AppFeedbackCenter.shared.showInfo(MoroL10n.Settings.feedbackMailSaved)
            case .cancelled:
                break
            case .failed:
                AppFeedbackCenter.shared.showError(MoroL10n.Settings.feedbackMailFailed)
            @unknown default:
                break
            }
        }
    #endif
}
