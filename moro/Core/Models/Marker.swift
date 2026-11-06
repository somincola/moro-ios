//
//  Marker.swift
//  moro
//
//  Marker model for tracking reading position in timelines.
//

import Foundation

/// Marker content for a specific timeline
nonisolated struct MarkerContent: Codable, Sendable {
    /// The ID of the most recently viewed entity
    let lastReadId: String

    /// The timestamp of when the marker was set
    let updatedAt: Date

    /// The version of the marker (used for optimistic concurrency)
    let version: Int

    nonisolated enum CodingKeys: String, CodingKey {
        case lastReadId = "last_read_id"
        case updatedAt = "updated_at"
        case version
    }
}

/// Container for all timeline markers
nonisolated struct Marker: Codable, Sendable {
    /// Marker for the home timeline
    let home: MarkerContent?

    /// Marker for notifications
    let notifications: MarkerContent?

    nonisolated enum CodingKeys: String, CodingKey {
        case home
        case notifications
    }

    init(home: MarkerContent? = nil, notifications: MarkerContent? = nil) {
        self.home = home
        self.notifications = notifications
    }
}

// MARK: - Marker Timeline Types

nonisolated enum MarkerTimeline: String, Sendable {
    case home
    case notifications

    var queryValue: String { rawValue }
}

// MARK: - Convenience Methods

nonisolated extension Marker {
    /// Get marker content for a specific timeline
    func content(for timeline: MarkerTimeline) -> MarkerContent? {
        switch timeline {
        case .home:
            return home
        case .notifications:
            return notifications
        }
    }
}
