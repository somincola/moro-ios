//
//  TimelinePostRow.swift
//  moro
//
//  A post row wrapper that adds thread connection lines for self-reply chains in timeline.
//

import SwiftUI

/// Represents thread context for a post in the timeline
struct TimelineThreadContext: Equatable {
    /// Whether this status is part of a contiguous self-reply chain in the timeline
    let isContiguousSelfReply: Bool
    
    /// Whether to draw a connection line above this status
    let drawsLineAbove: Bool
    
    /// Whether to draw a connection line below this status
    let drawsLineBelow: Bool
    
    /// Whether this is a non-contiguous self-reply (should show "上接嘟文串")
    let isNonContiguousSelfReply: Bool
    
    static let none = TimelineThreadContext(
        isContiguousSelfReply: false,
        drawsLineAbove: false,
        drawsLineBelow: false,
        isNonContiguousSelfReply: false
    )
}

/// A post row with optional thread connection lines for timeline display
struct TimelinePostRow: View {
    let status: Status
    let threadContext: TimelineThreadContext
    var translationAPIClient: MastodonAPI? = nil
    var accountCache: AccountCache? = nil
    var actions: PostActions = .empty

    @Environment(\.moroTheme) private var theme

    var body: some View {
        PostCard(
            status: status,
            translationAPIClient: translationAPIClient,
            actions: actions,
            accountCache: accountCache
        )
        .contentShape(Rectangle())
        .onTapGesture {
            actions.onTap?()
        }
        .accessibilityIdentifier("timeline.status.\(status.id)")
    }
}

// MARK: - Timeline Thread Detector (Enhanced)

extension TimelineThreadDetector {
    /// Analyze statuses to determine thread contexts for timeline display
    static func analyzeTimeline(
        statuses: [Status],
        currentUserID: String?
    ) -> [String: TimelineThreadContext] {
        var contexts: [String: TimelineThreadContext] = [:]
        
        // Build a map of status IDs to their indices
        var statusIndexMap: [String: Int] = [:]
        for (index, status) in statuses.enumerated() {
            statusIndexMap[status.id] = index
        }
        
        // Track which statuses have replies below them in the timeline
        var hasReplyBelow: Set<String> = []
        
        for status in statuses {
            guard let replyToID = status.inReplyToID,
                  let _ = statusIndexMap[replyToID] else { continue }
            hasReplyBelow.insert(replyToID)
        }
        
        // Process each status
        for (_, status) in statuses.enumerated() {
            let isSelfReply = status.inReplyToAccountID == status.account.id
            
            // Check if parent is in timeline (contiguous)
            let parentInTimeline = status.inReplyToID.flatMap { statusIndexMap[$0] } != nil
            
            // Check if this status has a reply below it in timeline
            let hasReplyBelowInTimeline = hasReplyBelow.contains(status.id)
            
            if isSelfReply {
                if parentInTimeline {
                    // Contiguous self-reply: draw lines
                    contexts[status.id] = TimelineThreadContext(
                        isContiguousSelfReply: true,
                        drawsLineAbove: true,
                        drawsLineBelow: hasReplyBelowInTimeline,
                        isNonContiguousSelfReply: false
                    )
                    
                    // Also update parent to draw line below
                    if let parentID = status.inReplyToID,
                       let parentContext = contexts[parentID] {
                        contexts[parentID] = TimelineThreadContext(
                            isContiguousSelfReply: parentContext.isContiguousSelfReply,
                            drawsLineAbove: parentContext.drawsLineAbove,
                            drawsLineBelow: true,
                            isNonContiguousSelfReply: parentContext.isNonContiguousSelfReply
                        )
                    } else if let parentID = status.inReplyToID {
                        // Parent doesn't have context yet, create one
                        contexts[parentID] = TimelineThreadContext(
                            isContiguousSelfReply: false,
                            drawsLineAbove: false,
                            drawsLineBelow: true,
                            isNonContiguousSelfReply: false
                        )
                    }
                } else {
                    // Non-contiguous self-reply: show "上接嘟文串"
                    contexts[status.id] = TimelineThreadContext(
                        isContiguousSelfReply: false,
                        drawsLineAbove: false,
                        drawsLineBelow: hasReplyBelowInTimeline,
                        isNonContiguousSelfReply: true
                    )
                }
            }
            // Note: We only draw lines for self-reply chains, not for regular replies
            // Regular replies should not have connection lines in timeline view
            // else: no thread context needed (use .none)
        }
        
        return contexts
    }
}

#Preview {
    let sampleAccount = Account(
        id: "1",
        username: "moro",
        acct: "moro@mastodon.social",
        displayName: "Moro User",
        note: "Building a friendly Mastodon client",
        avatar: "",
        avatarStatic: "",
        header: "",
        headerStatic: "",
        followersCount: 100,
        followingCount: 50,
        statusesCount: 200
    )

    let sampleStatus = Status(
        id: "1",
        content: "This is a sample status with some content.",
        createdAt: Date().addingTimeInterval(-3600),
        account: sampleAccount,
        mediaAttachments: [],
        favouritesCount: 12,
        reblogsCount: 3,
        repliesCount: 1,
        bookmarked: false,
        favourited: false,
        reblogged: false
    )

    VStack(spacing: 0) {
        TimelinePostRow(
            status: sampleStatus,
            threadContext: TimelineThreadContext(
                isContiguousSelfReply: false,
                drawsLineAbove: false,
                drawsLineBelow: true,
                isNonContiguousSelfReply: false
            )
        )

        Divider()

        TimelinePostRow(
            status: sampleStatus,
            threadContext: TimelineThreadContext(
                isContiguousSelfReply: true,
                drawsLineAbove: true,
                drawsLineBelow: false,
                isNonContiguousSelfReply: false
            )
        )
    }
    .moroTheme(MoroTheme())
}
