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
    case relationship(Relationship)
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
