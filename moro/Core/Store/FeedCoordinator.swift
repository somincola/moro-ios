//
//  FeedCoordinator.swift
//  moro
//
//  Central coordinator for publishing status updates across the app.
//  All ViewModels listen to updates and incorporate them into their local state.
//

import Foundation
import Combine
import SwiftUI

/// Types of updates that can be published
enum UpdatedElement {
    case deletedPost(String)  // Status ID
    case createdPost(Status)
    case post(Status)
    case hashtag(Status.Tag)
    case relationship(AccountRelationship)
}

/// Simple relationship model for account relationships
struct AccountRelationship: Codable, Equatable {
    let id: String
    let following: Bool
    let followedBy: Bool
    let blocking: Bool
    let blockedBy: Bool
    let muting: Bool
    let mutingNotifications: Bool
    let requested: Bool
    let domainBlocking: Bool
    let showingReblogs: Bool
    let endorsed: Bool
    let notifying: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case following
        case followedBy = "followed_by"
        case blocking
        case blockedBy = "blocked_by"
        case muting
        case mutingNotifications = "muting_notifications"
        case requested
        case domainBlocking = "domain_blocking"
        case showingReblogs = "showing_reblogs"
        case endorsed
        case notifying
    }
}

/// Central coordinator for feed updates
@MainActor
final class FeedCoordinator: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    /// Published property that ViewModels can observe
    @Published var mostRecentUpdate: UpdatedElement?
    let updates = PassthroughSubject<UpdatedElement, Never>()
    
    /// Shared singleton instance
    static let shared = FeedCoordinator()
    
    init() {}
    
    /// Publish an update to all listening ViewModels
    func publishUpdate(_ update: UpdatedElement) {
        mostRecentUpdate = update
        updates.send(update)
    }
}

/// Protocol for ViewModels that can incorporate updates
protocol FeedCoordinatorUpdatable {
    func incorporateUpdate(_ update: UpdatedElement)
}
