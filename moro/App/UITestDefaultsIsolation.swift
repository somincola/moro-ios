#if DEBUG
import Foundation

/// Gives every UI test its own settings.
///
/// UI tests share one simulator, and the app's UserDefaults outlive each test. A test that
/// changed a setting and stopped before changing it back (a failed assertion, an XCTest
/// crash) left it changed for every later test: one switched-off new-posts banner broke ten
/// timeline tests. The UI tests pass a session ID per test; when it differs from the last
/// launch's, the app's defaults start from scratch. Relaunches inside one test keep the same
/// ID, so a test can still check that a setting persists across a relaunch.
enum UITestDefaultsIsolation {
    static let environmentKey = "UITEST_DEFAULTS_SESSION"
    static let sessionKey = "uitest.defaultsSession"

    /// Returns true when it reset the defaults.
    @discardableResult
    nonisolated static func applyIfRequested(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard,
        domain: String? = Bundle.main.bundleIdentifier
    ) -> Bool {
        guard let session = environment[environmentKey], !session.isEmpty, let domain,
            defaults.string(forKey: sessionKey) != session
        else { return false }
        defaults.removePersistentDomain(forName: domain)
        defaults.set(session, forKey: sessionKey)
        return true
    }
}
#endif
