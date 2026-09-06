//
//  ThreadContext.swift
//  moro
//
//  Models for thread/conversation context and display.
//

import Foundation
import Combine

// MARK: - API Response Model

/// Response from GET /api/v1/statuses/{id}/context
struct StatusContext: Codable {
    let ancestors: [Status]
    let descendants: [Status]
}

// MARK: - Thread Position Context

/// Represents the position of a status within a conversation thread
enum ThreadPosition: Equatable {
    /// Root post of a conversation (no parent, has replies below)
    case root(connectedBelow: Bool)
    
    /// The focused/main post being viewed in detail
    case focused(connectedAbove: Bool, connectedBelow: Bool)
    
    /// Start of a new reply branch (can have line below for self-replies)
    case branchStart(connectedBelow: Bool)
    
    /// Middle of a continuous self-reply chain
    case continuation
    
    /// End of a self-reply branch
    case branchEnd
    
    /// Regular reply without any connection lines (different user)
    case standalone
    
    // MARK: - Connection Line Logic
    
    /// Whether to draw a vertical line above this post
    var drawsLineAbove: Bool {
        switch self {
        case .root, .standalone:
            return false
        case .focused(let connectedAbove, _):
            return connectedAbove
        case .branchStart:
            return false // branchStart only has line below, not above
        case .branchEnd, .continuation:
            return true
        }
    }
    
    /// Whether to draw a vertical line below this post
    var drawsLineBelow: Bool {
        switch self {
        case .root(let connectedBelow):
            return connectedBelow
        case .focused(_, let connectedBelow):
            return connectedBelow
        case .branchStart(let connectedBelow):
            return connectedBelow
        case .continuation:
            return true
        case .branchEnd, .standalone:
            return false
        }
    }
    
    /// Whether this post is part of a contiguous chain (no gap in lines)
    var isContiguous: Bool {
        switch self {
        case .root, .standalone:
            return false
        case .focused(let connectedAbove, let connectedBelow):
            return connectedAbove && connectedBelow
        case .branchStart(let connectedBelow):
            return connectedBelow
        case .continuation:
            return true
        case .branchEnd:
            return false
        }
    }
}

// MARK: - Thread Item

/// A status with its thread context information
struct ThreadItem: Identifiable {
    let status: Status
    let position: ThreadPosition
    let replyDepth: Int
    
    var id: String { status.id }
}

// MARK: - Threaded Conversation Model

/// Manages a complete thread conversation with proper ordering and context
final class ThreadedConversationModel: ObservableObject {
    /// The ID of the focused post
    let focusedID: String
    
    /// All statuses in the thread, in display order
    @Published var threadItems: [ThreadItem] = []
    
    init(focusedStatus: Status, context: StatusContext) {
        self.focusedID = focusedStatus.id
        self.threadItems = Self.buildThread(
            focusedStatus: focusedStatus,
            context: context
        )
    }
    
    // MARK: - Thread Building
    
    /// Build the complete thread with proper context for each item
    private static func buildThread(
        focusedStatus: Status,
        context: StatusContext
    ) -> [ThreadItem] {
        var items: [ThreadItem] = []
        
        // Build ancestors chain (reply chain leading to focused post)
        let ancestors = buildAncestorChain(
            from: context.ancestors,
            leadingTo: focusedStatus
        )
        
        // Process ancestors
        for (index, status) in ancestors.enumerated() {
            let position: ThreadPosition
            if index == 0 {
                // First ancestor is the root
                position = .root(connectedBelow: true)
            } else {
                // Middle ancestors are continuations
                position = .continuation
            }
            items.append(ThreadItem(status: status, position: position, replyDepth: 0))
        }
        
        // Process descendants - show connection lines for OP engagement and self-reply chains
        let descendants = orderedDescendants(
            context.descendants,
            startingAt: focusedStatus.id
        )
        let opID = focusedStatus.account.id // Original Poster's ID
        
        // Build a dictionary for quick status lookup
        var statusDict: [String: Status] = [focusedStatus.id: focusedStatus]
        for status in descendants {
            statusDict[status.id] = status
        }
        
        // Track which statuses should have connection line below
        // A status has connection below if:
        // 1. It's from the OP and has a direct reply below
        // 2. It's a self-reply chain (any user replying to themselves)
        var hasConnectionBelow: Set<String> = []
        
        for status in descendants {
            guard let parentID = status.inReplyToID else { continue }
            
            // Check if this is a self-reply
            let isSelfReply = status.inReplyToAccountID == status.account.id
            
            // Check if this is an OP reply (OP is replying to something)
            let isOPReply = status.account.id == opID
            
            // Check if replying to an OP's reply
            let parentIsOP = statusDict[parentID]?.account.id == opID
            
            // Mark parent as having connection below if:
            // 1. Self-reply (anyone replying to themselves)
            // 2. OP is replying (OP engagement)
            // 3. Someone is replying to OP's reply (continuing OP's thread)
            if isSelfReply || isOPReply || parentIsOP {
                hasConnectionBelow.insert(parentID)
            }
        }
        
        // Focused status never has connection below
        // (direct replies to focused don't have line above, so focused doesn't need line below)
        let focusedPosition: ThreadPosition = .focused(
            connectedAbove: !ancestors.isEmpty,
            connectedBelow: false
        )
        items.append(ThreadItem(status: focusedStatus, position: focusedPosition, replyDepth: 0))

        var replyDepthByStatusID = [focusedStatus.id: -1]
        
        for (index, status) in descendants.enumerated() {
            // Check if this is a direct reply to the focused post
            let isDirectReplyToFocused = status.inReplyToID == focusedStatus.id
            
            // Check if this is a self-reply
            let isSelfReply = status.inReplyToAccountID == status.account.id
            
            // Check if this is an OP reply
            let isOPReply = status.account.id == opID
            
            // Check if the previous item is the direct parent (for non-direct-to-focused replies)
            let isDirectReplyToPrevious: Bool
            let previousItemIsOP: Bool
            if index == 0 {
                isDirectReplyToPrevious = false // First item after focused, no line above
                previousItemIsOP = false
            } else {
                let prevStatus = descendants[index - 1]
                isDirectReplyToPrevious = status.inReplyToID == prevStatus.id
                previousItemIsOP = prevStatus.account.id == opID
            }
            
            // Draw line above if:
            // 1. NOT a direct reply to focused post (those never have line above)
            // 2. AND one of:
            //    - Self-reply and direct reply to previous
            //    - OP is replying and direct reply to previous
            //    - Replying to OP's previous post
            let shouldDrawLineAbove: Bool
            if isDirectReplyToFocused {
                // Direct replies to focused post never have line above
                shouldDrawLineAbove = false
            } else {
                shouldDrawLineAbove = isDirectReplyToPrevious && (isSelfReply || isOPReply || previousItemIsOP)
            }
            
            let shouldDrawLineBelow = hasConnectionBelow.contains(status.id)
            
            let position: ThreadPosition
            if shouldDrawLineAbove && shouldDrawLineBelow {
                position = .continuation
            } else if shouldDrawLineAbove {
                position = .branchEnd
            } else if shouldDrawLineBelow {
                position = .branchStart(connectedBelow: true)
            } else {
                // Regular reply - no connection lines
                position = .standalone
            }

            let replyDepth: Int
            if let parentID = status.inReplyToID,
               let parentDepth = replyDepthByStatusID[parentID] {
                replyDepth = parentDepth + 1
            } else {
                replyDepth = 0
            }
            replyDepthByStatusID[status.id] = replyDepth
            
            items.append(ThreadItem(status: status, position: position, replyDepth: replyDepth))
        }
        
        return items
    }

    /// Keep every parent before its children and sort sibling replies oldest first.
    private static func orderedDescendants(
        _ descendants: [Status],
        startingAt focusedID: String
    ) -> [Status] {
        let uniqueStatuses = Dictionary(
            descendants.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var childrenByParent: [String: [Status]] = [:]

        for status in uniqueStatuses.values {
            guard let parentID = status.inReplyToID else { continue }
            childrenByParent[parentID, default: []].append(status)
        }

        func sorted(_ statuses: [Status]) -> [Status] {
            statuses.sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.id < $1.id
                }
                return $0.createdAt < $1.createdAt
            }
        }

        var ordered: [Status] = []
        var visited: Set<String> = []

        func appendBranch(startingWith roots: [Status]) {
            var pending = Array(roots.reversed())
            while let status = pending.popLast() {
                guard status.id != focusedID, visited.insert(status.id).inserted else { continue }
                ordered.append(status)
                pending.append(contentsOf: sorted(childrenByParent[status.id] ?? []).reversed())
            }
        }

        appendBranch(startingWith: sorted(childrenByParent[focusedID] ?? []))
        // Preserve replies whose parent is unavailable, while bounding malformed cycles.
        appendBranch(startingWith: sorted(Array(uniqueStatuses.values)))

        return ordered
    }
    
    /// Build the ancestor chain by following inReplyToID
    private static func buildAncestorChain(
        from ancestors: [Status],
        leadingTo focusedStatus: Status
    ) -> [Status] {
        guard let replyToID = focusedStatus.inReplyToID else { return [] }
        
        // Build a dictionary for quick lookup
        var statusDict: [String: Status] = [:]
        for status in ancestors {
            statusDict[status.id] = status
        }
        
        // Chain backwards from focused post
        var chain: [Status] = []
        var nextID: String? = replyToID
        var visited: Set<String> = [focusedStatus.id]

        while let currentID = nextID, visited.insert(currentID).inserted,
            let status = statusDict[currentID] {
            chain.append(status)
            nextID = status.inReplyToID
        }

        return chain.reversed()
    }
    
    // MARK: - Index Finding
    
    /// Find the index of the focused post for scrolling
    var focusedIndex: Int? {
        threadItems.firstIndex { $0.status.id == focusedID }
    }

}

// MARK: - Timeline Thread Detection

/// Helper to detect self-reply threads in a timeline
struct TimelineThreadDetector {
    /// Group statuses by their thread relationships in a timeline
    /// Returns statuses with optional thread context (for self-reply chains)
    static func detectThreads(in statuses: [Status], currentUserID: String?) -> [(Status, ThreadPosition?)] {
        var result: [(Status, ThreadPosition?)] = []
        var processedIDs: Set<String> = []
        
        for (index, status) in statuses.enumerated() {
            guard !processedIDs.contains(status.id) else { continue }
            
            // Check if this is a self-reply chain
            if let userID = currentUserID,
               status.account.id == userID,
               status.inReplyToAccountID == userID {
                // This is a self-reply, check if parent is in timeline
                if let parentIndex = statuses.firstIndex(where: { $0.id == status.inReplyToID }),
                   parentIndex < index {
                    // Parent exists before this status in timeline
                    let nextIsReply = index < statuses.count - 1 && 
                                      statuses[index + 1].inReplyToID == status.id
                    
                    result.append((status, nextIsReply ? .continuation : .branchEnd))
                    processedIDs.insert(status.id)
                    continue
                }
            }
            
            // Regular status without thread context
            result.append((status, nil))
            processedIDs.insert(status.id)
        }
        
        return result
    }
}
