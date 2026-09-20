import Foundation

enum PushNotificationDestination {
    case notifications
    case messages
    case status(Status)
    case profile(Account)
    case conversation(Conversation)
}

@MainActor
enum PushNotificationResolver {
    static func resolve(
        _ payload: PushNotificationPayload,
        apiClient: MastodonAPI
    ) async -> PushNotificationDestination {
        guard !Task.isCancelled else { return .notifications }
        if let id = payload.notificationID {
            do {
                let notification = try await apiClient.fetchNotification(id: id)
                guard !Task.isCancelled, notification.id == id else { return .notifications }
                if let status = NotificationDisplayItem(from: notification).effectiveStatusTarget {
                    if status.visibility?.lowercased() == "direct" {
                        // A participant can belong to multiple conversations. Only open an
                        // exact match; otherwise let the user choose from the message list.
                        let conversations = try? await apiClient.fetchConversations(
                            maxID: nil, sinceID: nil, limit: 80)
                        guard !Task.isCancelled else { return .messages }
                        if let conversation = conversations?.first(where: { $0.lastStatus?.id == status.id }) {
                            return .conversation(conversation)
                        }
                        return .messages
                    }
                    return .status(status)
                }
                if notification.type == "follow" {
                    return .profile(notification.account)
                }
                return .notifications
            } catch {
                guard !Task.isCancelled else { return .notifications }
                // Missing, expired, or unsupported notifications leave the Inbox usable.
            }
        }

        if let url = payload.statusURL,
            case .statusLink = URLHandler.shared.parseMastodonURL(url),
            case .statusDetail(let status) = await URLHandler.shared.resolveStatusLink(url, apiClient: apiClient),
            !Task.isCancelled
        {
            return status.visibility?.lowercased() == "direct" ? .messages : .status(status)
        }
        return .notifications
    }
}
