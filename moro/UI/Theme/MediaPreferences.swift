//
//  MediaPreferences.swift
//  moro
//
//  Environment carrier for media playback preferences. Injected at the theme
//  injection points (which already observe AppSettings), so row-level views —
//  avatars, media grids, emoji-bearing text — read these without each
//  attaching their own AppSettings observer.
//

import SwiftUI

struct MoroMediaPreferences: Equatable {
    var playAnimations: Bool = true
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
