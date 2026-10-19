//
//  NotificationRowTapHarnessView.swift
//  moro
//
//  Dedicated UI test harness for effective notification status routing.
//

#if DEBUG
import SwiftUI

struct NotificationRowTapHarnessView: View {
    @State private var lastTap: String = "none"

    private let notifications = Self.makeNotifications()

    var body: some View {
        VStack(spacing: 0) {
            Text("tap:\(lastTap)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, MoroLayoutMetrics.contentHorizontalInset)
                .padding(.vertical, 8)
                .accessibilityIdentifier("notification.tapResult")

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(notifications) { notification in
                        let accessibilityIdentifier: String? = switch notification.type {
                        case "favourite": "notification.mainStatusTap"
                        case "quoted_update": "notification.quotedStatusTap"
                        default: nil
                        }

                        NotificationRow(
                            notification: notification,
                            onStatusTap: { status in
                                lastTap = status.id
                            },
                            statusTapAccessibilityIdentifier: accessibilityIdentifier
                        )

                        if notification.id != notifications.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .background(Color(.systemBackground))
    }

    private static func makeNotifications() -> [NotificationDisplayItem] {
        let actors = [
            makeAccount(id: "actor-1", name: "Hanna"),
            makeAccount(id: "actor-2", name: "Albert"),
            makeAccount(id: "actor-3", name: "Noah"),
            makeAccount(id: "actor-4", name: "Mina"),
        ]
        let quotedAuthor = makeAccount(id: "quoted-author", name: "Quoted Author")
        let quotedStatus = makeStatus(
            id: "quoted-status",
            content: "<p>The original quoted status provides context.</p>",
            account: quotedAuthor
        )
        let actionStatus = makeStatus(
            id: "action-status",
            content: "<p>A status with media should keep the content readable beside its preview.</p>",
            account: actors[0],
            attachments: [
                Status.Attachment(
                    id: "media-1",
                    type: "image",
                    url: URL(string: "https://picsum.photos/200")!
                )
            ]
        )
        let actionNotifications = actors.enumerated().map { index, account in
            NotificationItem(
                id: "like-\(index)",
                type: "favourite",
                groupKey: "favourite:action-status",
                createdAt: Date().addingTimeInterval(TimeInterval(-index)),
                account: account,
                status: actionStatus
            )
        }

        let replyStatus = makeStatus(
            id: "reply-status",
            content: "<p>This is a reply shown as a single-person event.</p>",
            account: actors[1],
            inReplyToID: "parent-status"
        )
        let reply = NotificationItem(
            id: "reply-notification",
            type: "mention",
            createdAt: Date().addingTimeInterval(-90),
            account: actors[1],
            status: replyStatus
        )

        let quotedUpdateStatus = makeStatus(
            id: "quoted-update-status",
            content: "<p>Your quote post was updated.</p>",
            account: actors[2],
            quote: Status.Quote(state: .accepted, quotedStatus: quotedStatus)
        )
        let quotedUpdate = NotificationItem(
            id: "quoted-update-notification",
            type: "quoted_update",
            createdAt: Date().addingTimeInterval(-180),
            account: quotedAuthor,
            status: quotedUpdateStatus
        )

        return NotificationDisplayItem.consolidate(actionNotifications)
            + [NotificationDisplayItem(from: reply), NotificationDisplayItem(from: quotedUpdate)]
    }

    private static func makeAccount(id: String, name: String) -> Account {
        Account(
            id: id,
            username: name.lowercased().replacingOccurrences(of: " ", with: ""),
            acct: "\(name.lowercased().replacingOccurrences(of: " ", with: ""))@example.social",
            displayName: name,
            note: "",
            avatar: "",
            avatarStatic: "",
            header: "",
            headerStatic: "",
            followersCount: 1,
            followingCount: 1,
            statusesCount: 1
        )
    }

    private static func makeStatus(
        id: String,
        content: String,
        account: Account,
        attachments: [Status.Attachment] = [],
        quote: Status.Quote? = nil,
        inReplyToID: String? = nil
    ) -> Status {
        Status(
            id: id,
            content: content,
            createdAt: Date(),
            account: account,
            mediaAttachments: attachments,
            favouritesCount: 0,
            reblogsCount: 0,
            repliesCount: 0,
            bookmarked: false,
            favourited: false,
            reblogged: false,
            quote: quote,
            inReplyToID: inReplyToID
        )
    }
}
#endif
