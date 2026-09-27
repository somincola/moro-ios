//
//  FeedbackMailComposerView.swift
//  moro
//
//  Feedback email helper and in-app mail composer wrapper.
//

import SwiftUI
import UIKit

#if canImport(MessageUI)
import MessageUI
#endif

enum FeedbackMailContext {
    private static let supportEmailInfoKey = "MORO_FEEDBACK_EMAIL"
    private static let fallbackSupportEmail = MoroBrand.supportEmail

    static var supportEmail: String {
        if let configured = Bundle.main.object(forInfoDictionaryKey: supportEmailInfoKey) as? String {
            let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return fallbackSupportEmail
    }

    static var subject: String {
        MoroL10n.Feedback.subject
    }

    static func messageBody(currentAccount: Account?) -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let systemVersion = UIDevice.current.systemVersion
        let model = UIDevice.current.model
        let accountText = currentAccount?.acct ?? MoroL10n.Feedback.notLoggedIn

        return """
        \(MoroL10n.Feedback.bodyPrompt)



        ----
        App: Moro \(version) (\(build))
        Device: \(model)
        iOS: \(systemVersion)
        Account: \(accountText)
        """
    }

    static func mailtoURL(email: String, subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }

    static var canUseInAppComposer: Bool {
        #if canImport(MessageUI)
        MFMailComposeViewController.canSendMail()
        #else
        false
        #endif
    }
}

#if canImport(MessageUI)
struct FeedbackMailComposerView: UIViewControllerRepresentable {
    let to: String
    let subject: String
    let body: String
    let onComplete: (MFMailComposeResult, Error?) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([to])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
        nonisolated deinit {}

        let onComplete: (MFMailComposeResult, Error?) -> Void

        init(onComplete: @escaping (MFMailComposeResult, Error?) -> Void) {
            self.onComplete = onComplete
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onComplete(result, error)
            controller.dismiss(animated: true)
        }
    }
}
#endif
