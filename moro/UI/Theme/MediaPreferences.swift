//
//  MediaPreferences.swift
//  moro
//
//  Environment carrier for timeline media preferences. Injected at the theme
//  boundaries so media rows do not each observe AppSettings.
//

import SwiftUI

/// When to put images and videos behind a warning. Mirrors Mastodon's
/// `reading:expand:media` values so a later server sync maps one-to-one.
enum SensitiveMediaDisplay: String, CaseIterable {
    /// Warn before every attachment.
    case hideAll = "hide_all"
    /// Warn only before attachments the author marked sensitive.
    case `default` = "default"
    /// Never warn, including attachments marked sensitive.
    case showAll = "show_all"

    var title: String {
        switch self {
        case .hideAll: return MoroL10n.SensitiveMedia.displayHideAll
        case .default: return MoroL10n.SensitiveMedia.displayDefault
        case .showAll: return MoroL10n.SensitiveMedia.displayShowAll
        }
    }

    var detail: String {
        switch self {
        case .hideAll: return MoroL10n.SensitiveMedia.displayHideAllDetail
        case .default: return MoroL10n.SensitiveMedia.displayDefaultDetail
        case .showAll: return MoroL10n.SensitiveMedia.displayShowAllDetail
        }
    }
}

struct MoroMediaPreferences: Equatable {
    var autoplayGIFs: Bool = true
    var videoAutoplayMode: AppSettings.VideoAutoplayMode = .wifi
    var sensitiveMediaDisplay: SensitiveMediaDisplay = .default
    /// Open content-warning posts by default. Media inside still follows
    /// `sensitiveMediaDisplay`; server filter warnings are never bypassed.
    var expandContentWarnings: Bool = false

    /// Whether an attachment starts behind a warning.
    func concealsMedia(markedSensitive: Bool) -> Bool {
        switch sensitiveMediaDisplay {
        case .hideAll: return true
        case .default: return markedSensitive
        case .showAll: return false
        }
    }

    /// Overlay label: "Sensitive content" only when the author said so.
    func concealLabel(markedSensitive: Bool) -> String {
        markedSensitive ? MoroL10n.SensitiveMedia.title : MoroL10n.SensitiveMedia.hiddenMedia
    }

    @MainActor
    init(settings: AppSettings) {
        autoplayGIFs = settings.autoplayGIFs
        videoAutoplayMode = settings.videoAutoplayMode
        sensitiveMediaDisplay = settings.sensitiveMediaDisplay
        expandContentWarnings = settings.expandContentWarnings
    }

    init(
        autoplayGIFs: Bool = true,
        videoAutoplayMode: AppSettings.VideoAutoplayMode = .wifi,
        sensitiveMediaDisplay: SensitiveMediaDisplay = .default,
        expandContentWarnings: Bool = false
    ) {
        self.autoplayGIFs = autoplayGIFs
        self.videoAutoplayMode = videoAutoplayMode
        self.sensitiveMediaDisplay = sensitiveMediaDisplay
        self.expandContentWarnings = expandContentWarnings
    }
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
