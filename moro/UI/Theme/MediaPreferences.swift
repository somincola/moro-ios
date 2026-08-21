//
//  MediaPreferences.swift
//  moro
//
//  Environment carrier for timeline media playback preferences. Injected at
//  the theme boundaries so media rows do not each observe AppSettings.
//

import SwiftUI

struct MoroMediaPreferences: Equatable {
    var autoplayGIFs: Bool = true
}

private struct MoroMediaPreferencesKey: EnvironmentKey {
    static let defaultValue = MoroMediaPreferences()
}

extension EnvironmentValues {
    var moroMediaPrefs: MoroMediaPreferences {
        get { self[MoroMediaPreferencesKey.self] }
        set { self[MoroMediaPreferencesKey.self] = newValue }
    }
}
