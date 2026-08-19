//
//  ComposeFeatureAvailability.swift
//  moro
//
//  Central capability switches for temporarily unavailable compose features.
//

enum ComposeFeatureAvailability {
    /// Scheduled publishing is intentionally disabled while product fit is reassessed.
    /// Keep this single boundary so the UI, restored drafts, and API payload cannot drift.
    static let scheduledPublishing = false
}
