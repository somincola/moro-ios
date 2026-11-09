import UIKit

/// Keeps a shared-photo import running for the limited extra time iOS grants after the app
/// moves to the background. It is a best-effort extension, not a background upload session:
/// when the time expires the in-flight request is suspended and the editor resumes the batch
/// on returning to the foreground.
@MainActor
final class SharedImportBackgroundAssertion {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "moro.sharedComposeImport") { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
