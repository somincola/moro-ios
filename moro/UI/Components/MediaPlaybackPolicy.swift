import Observation
import SwiftUI

nonisolated enum MediaPlaybackPolicy {
    /// Shared by supported list avatars, animated images and video attachments.
    static let visibleFraction = 0.6
    static let settleDelay: Duration = .milliseconds(150)

    static func canPlay(isVisible: Bool, isActive: Bool, isSceneActive: Bool,
                        isCovered: Bool, isConcealed: Bool = false) -> Bool {
        isVisible && isActive && isSceneActive && !isCovered && !isConcealed
    }
}

/// A retained list page updates this small scope rather than invalidating all row data.
@MainActor @Observable
final class MediaPlaybackScope {
    // Avoid the isolated-deinit back-deployment crash on iOS 26.2 and earlier.
    nonisolated deinit {}

    static let unrestricted = MediaPlaybackScope(isActive: true)
    var isActive: Bool
    var isScrolling = false
    /// UIKit-hosted rows receive the owning SwiftUI scene's read-only accessibility policy.
    var systemAllowsAnimatedAvatars = true
    let allowsAnimatedAvatars: Bool

    init(isActive: Bool = false, allowsAnimatedAvatars: Bool = false) {
        self.isActive = isActive
        self.allowsAnimatedAvatars = allowsAnimatedAvatars
    }
}

private struct MediaPlaybackScopeKey: EnvironmentKey {
    static let defaultValue = MediaPlaybackScope.unrestricted
}

extension EnvironmentValues {
    var moroPlaybackScope: MediaPlaybackScope {
        get { self[MediaPlaybackScopeKey.self] }
        set { self[MediaPlaybackScopeKey.self] = newValue }
    }
}

/// Fullscreen media owns playback until its last presentation ends. Inline players release
/// their leases during the handoff, so they cannot pause the shared fullscreen player.
@MainActor @Observable
final class MediaPlaybackPresentation {
    // Avoid the isolated-deinit back-deployment crash on iOS 26.2 and earlier.
    nonisolated deinit {}

    static let shared = MediaPlaybackPresentation()
    private(set) var dockedURL: URL?
    private var dockedToken: UUID?
    private var presentations: Set<UUID> = []
    var coversInlinePlayback: Bool { presentations.count > (dockedToken == nil ? 0 : 1) }
    var coversInlineVideoPlayback: Bool { !presentations.isEmpty }

    func begin() -> UUID {
        let token = UUID()
        presentations.insert(token)
        return token
    }

    func dock(_ token: UUID, url: URL) {
        guard presentations.contains(token) else { return }
        dockedToken = token
        dockedURL = url
    }

    func undock(_ token: UUID) {
        guard dockedToken == token else { return }
        dockedToken = nil
        dockedURL = nil
    }

    func end(_ token: UUID) {
        undock(token)
        presentations.remove(token)
    }
}
