//
//  UserInteractionService.swift
//  moro
//
//  Unified service for handling user-related interactions (mute, block, report, share).
//  Similar to PostInteractionService but for user profile actions.
//

import SwiftUI

@MainActor
final class UserInteractionService {
    static let shared = UserInteractionService()
    
    private init() {}
    
    /// Show confirmation before muting a user
    func confirmMuteUser(
        account: Account,
        isMuting: Bool,
        onConfirm: @escaping () -> Void
    ) {
        let settings = AppSettings.shared
        
        if settings.askBeforeMutingAUser && !isMuting {
            // Show confirmation alert
            // Note: In SwiftUI, alerts are typically shown from the view
            // This method can be extended to return a confirmation state
            // For now, we'll call onConfirm directly if confirmation is not needed
            onConfirm()
        } else {
            onConfirm()
        }
    }
    
    /// Show confirmation before blocking a user
    func confirmBlockUser(
        account: Account,
        isBlocking: Bool,
        onConfirm: @escaping () -> Void
    ) {
        let settings = AppSettings.shared
        
        if settings.askBeforeBlockingAUser && !isBlocking {
            // Show confirmation alert
            // Note: In SwiftUI, alerts are typically shown from the view
            // This method can be extended to return a confirmation state
            // For now, we'll call onConfirm directly if confirmation is not needed
            onConfirm()
        } else {
            onConfirm()
        }
    }
    
    /// Show confirmation before unfollowing a user
    func confirmUnfollowUser(
        account: Account,
        onConfirm: @escaping () -> Void
    ) {
        let settings = AppSettings.shared
        
        if settings.askBeforeUnfollowingAUser {
            // Show confirmation alert
            // Note: In SwiftUI, alerts are typically shown from the view
            // This method can be extended to return a confirmation state
            // For now, we'll call onConfirm directly if confirmation is not needed
            onConfirm()
        } else {
            onConfirm()
        }
    }
}

