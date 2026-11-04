//
//  MoroTips.swift
//  moro
//
//  One-time hints for gestures people can't see.
//

import SwiftUI
import TipKit

/// Re-tapping Home at the top refreshes the way a pull does. Nothing on screen says so, so
/// once someone has pulled to refresh a couple of times, the Home tab says it once. Using the
/// gesture retires the hint for good.
struct TabRetapRefreshTip: Tip {
    static let pulledToRefresh = Tips.Event(id: "home.pulledToRefresh")

    var id: String { "home.tabRetapRefresh" }

    var title: Text { Text(MoroL10n.Tips.tabRetapTitle) }

    var message: Text? { Text(MoroL10n.Tips.tabRetapMessage) }

    var image: Image? { Image(systemName: "hand.tap") }

    var rules: [Rule] {
        #Rule(Self.pulledToRefresh) { $0.donations.count >= 2 }
    }

    var options: [any TipOption] {
        [Tips.MaxDisplayCount(1)]
    }

    @MainActor static func notePullToRefresh() {
        Task { await pulledToRefresh.donate() }
    }

    @MainActor static func noteTabRetap() {
        TabRetapRefreshTip().invalidate(reason: .actionPerformed)
    }
}

enum MoroTips {
    /// Call once at launch. UI tests hide every hint (they would cover the controls under
    /// test) unless `UITEST_SHOW_TIPS` asks to see them.
    @MainActor static func configure() {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["UITEST_SHOW_TIPS"] == "1" {
            Tips.showAllTipsForTesting()
            try? Tips.resetDatastore()
        } else if environment["UITEST_USE_FULL_APP"] == "1" || environment["XCTestConfigurationFilePath"] != nil {
            Tips.hideAllTipsForTesting()
        }
        #endif
        do {
            try Tips.configure([.displayFrequency(.immediate)])
        } catch {
            AppLogger.error("[Tips] configure failed: \(error)")
        }
    }
}
