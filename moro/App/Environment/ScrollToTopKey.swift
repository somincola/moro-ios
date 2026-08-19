//
//  ScrollToTopKey.swift
//  moro
//
//  Environment key for communicating tab scroll-to-top events.
//

import SwiftUI

// MARK: - Environment Key

private struct SelectedTabScrollToTopKey: EnvironmentKey {
    static let defaultValue: Int = -1
}

extension EnvironmentValues {
    /// ID of the tab that should scroll to top.
    /// -1 means no scroll event. Set to tab hashValue and reset to -1 after short delay.
    var selectedTabScrollToTop: Int {
        get { self[SelectedTabScrollToTopKey.self] }
        set { self[SelectedTabScrollToTopKey.self] = newValue }
    }
}
