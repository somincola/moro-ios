//
//  NotificationDisplayItem.swift
//  moro
//
//  Consolidated notification model for list display.
//

import Foundation

struct NotificationDisplayItem: Identifiable {
    let id: String
    let type: String
    var createdAt: Date
    var accounts: [Account]
    var status: Status?
    var fallback: NotificationFallback?
    var collection: NotificationCollectionSummary?
    var sourceNotificationIDs: [String]

    var primaryAccount: Account? { accounts.first }
    var actorCount: Int { accounts.count }
    var kind: NotificationKind { NotificationKind(rawValue: type) }
    var effectiveStatusTarget: Status? {
        guard let status else { return nil }
        if kind == .quotedUpdate {
            return status.quote?.displayableStatus?.displayStatus
        }
        return status.displayStatus
    }

    init(from notification: NotificationItem, groupKey: String? = nil) {
        self.id = groupKey ?? notification.id
        self.type = notification.type
        self.createdAt = notification.createdAt
        self.accounts = [notification.account]
        self.status = notification.status
        self.fallback = notification.fallback
        self.collection = notification.collection
        self.sourceNotificationIDs = [notification.id]
    }

    mutating func merge(_ notification: NotificationItem) {
        let isNewest = notification.createdAt > createdAt
        if isNewest {
            createdAt = notification.createdAt
        }
        if status == nil {
            status = notification.status
        }
        if fallback == nil {
            fallback = notification.fallback
        }
        if collection == nil {
            collection = notification.collection
        }

        if let existingIndex = accounts.firstIndex(where: { $0.id == notification.account.id }) {
            if isNewest && existingIndex != 0 {
                let account = accounts.remove(at: existingIndex)
                accounts.insert(account, at: 0)
            }
        } else if isNewest {
            accounts.insert(notification.account, at: 0)
        } else {
            accounts.append(notification.account)
        }

        if !sourceNotificationIDs.contains(notification.id) {
            sourceNotificationIDs.append(notification.id)
        }
    }

    static func consolidate(_ notifications: [NotificationItem]) -> [NotificationDisplayItem] {
        var result: [NotificationDisplayItem] = []
        var groupIndexByKey: [String: Int] = [:]

        for notification in notifications {
            if let groupKey = groupingKey(for: notification) {
                if let existingIndex = groupIndexByKey[groupKey] {
                    result[existingIndex].merge(notification)
                } else {
                    let item = NotificationDisplayItem(from: notification, groupKey: groupKey)
                    groupIndexByKey[groupKey] = result.count
                    result.append(item)
                }
                continue
            }

            result.append(NotificationDisplayItem(from: notification))
        }

        return result
    }

    private static func groupingKey(for notification: NotificationItem) -> String? {
        let kind = NotificationKind(rawValue: notification.type)
        guard kind.descriptor.canGroupActors else {
            return nil
        }

        let dayBucket = Calendar.current.startOfDay(for: notification.createdAt)
            .timeIntervalSince1970
        if let serverGroupKey = notification.groupKey,
            !serverGroupKey.hasPrefix("ungrouped-")
        {
            return "\(notification.type)-group-\(serverGroupKey)-\(Int(dayBucket))"
        }

        guard let statusID = notification.status?.id else { return nil }
        return "\(notification.type)-\(statusID)-\(Int(dayBucket))"
    }
}
