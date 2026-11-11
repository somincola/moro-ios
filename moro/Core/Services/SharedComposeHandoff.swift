import Combine
import Foundation

/// The URL carries only an opaque staging ID. Files and text stay in the App Group.
@MainActor
final class SharedComposeHandoff {
    static let shared = SharedComposeHandoff()
    static let received = Notification.Name("moro.sharedComposeHandoff.received")
    private(set) var requestedItemID: String?
    private var editingSessions: Set<UUID> = []
    private let notificationCenter: NotificationCenter
    var hasPresentedEditor: Bool { !editingSessions.isEmpty }

    init(notificationCenter: NotificationCenter = .default) { self.notificationCenter = notificationCenter }

    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "moro", components.host == "share",
              components.path == "/compose", components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil,
              let items = components.queryItems, items.count == 1,
              items[0].name == "item", let id = items[0].value, UUID(uuidString: id) != nil else { return false }
        requestedItemID = id
        notificationCenter.post(name: Self.received, object: nil)
        return true
    }

    func acknowledge(_ id: String) {
        if requestedItemID == id { requestedItemID = nil }
    }

    func registerEditor(_ id: UUID) { editingSessions.insert(id) }
    func unregisterEditor(_ id: UUID) { editingSessions.remove(id) }
    nonisolated deinit {}
}

/// Owned by the composer's SwiftUI lifetime, including when a child camera/sheet covers it.
@MainActor
final class SharedComposeEditingSession: ObservableObject {
    private let id = UUID()
    private let handoff: SharedComposeHandoff
    private(set) var isActive = false

    init(handoff: SharedComposeHandoff? = nil) { self.handoff = handoff ?? .shared }
    func activate() { isActive = true; handoff.registerEditor(id) }
    func finish() { isActive = false; handoff.unregisterEditor(id) }

    nonisolated deinit {
        let id = id, handoff = handoff
        Task { @MainActor in handoff.unregisterEditor(id) }
    }
}
