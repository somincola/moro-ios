import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import moro

@MainActor
struct SensitiveContentPreferencesTests {
    @Test func mediaDisplayDecidesConcealment() {
        let warnAll = MoroMediaPreferences(sensitiveMediaDisplay: .hideAll)
        #expect(warnAll.concealsMedia(markedSensitive: true))
        #expect(warnAll.concealsMedia(markedSensitive: false))

        let warnSensitive = MoroMediaPreferences(sensitiveMediaDisplay: .default)
        #expect(warnSensitive.concealsMedia(markedSensitive: true))
        #expect(!warnSensitive.concealsMedia(markedSensitive: false))

        let showAll = MoroMediaPreferences(sensitiveMediaDisplay: .showAll)
        #expect(!showAll.concealsMedia(markedSensitive: true))
        #expect(!showAll.concealsMedia(markedSensitive: false))
    }

    @Test func overlayOnlyCallsAuthorMarkedMediaSensitive() {
        let prefs = MoroMediaPreferences(sensitiveMediaDisplay: .hideAll)
        #expect(prefs.concealLabel(markedSensitive: true) == MoroL10n.SensitiveMedia.title)
        #expect(prefs.concealLabel(markedSensitive: false) == MoroL10n.SensitiveMedia.hiddenMedia)
    }

    @Test func mediaDisplayValuesMatchMastodonPreference() {
        #expect(SensitiveMediaDisplay.allCases.map(\.rawValue) == ["hide_all", "default", "show_all"])
    }

    @Test func autoExpandOpensContentWarningsUntilTheReaderCollapses() {
        let viewModel = ContentConcealViewModel(
            statusID: "1", hasContentWarning: true, spoilerText: "CW"
        )
        #expect(viewModel.isContentRevealed(autoExpand: true))
        #expect(!viewModel.isContentRevealed(autoExpand: false))

        viewModel.toggleContentWarning(autoExpand: true)
        #expect(!viewModel.isContentRevealed(autoExpand: true))

        // A different post starts from the reader's default again.
        viewModel.sync(statusID: "2", hasContentWarning: true, hasFilterWarning: false,
            spoilerText: "CW", filterWarningText: nil)
        #expect(viewModel.isContentRevealed(autoExpand: true))
    }

    @Test func autoExpandNeverBypassesFilterWarnings() {
        let viewModel = ContentConcealViewModel(
            statusID: "1", hasContentWarning: true, hasFilterWarning: true,
            spoilerText: "CW", filterWarningText: "Filtered"
        )
        #expect(!viewModel.isContentRevealed(autoExpand: true))
        viewModel.revealFilteredContent()
        #expect(viewModel.isContentRevealed(autoExpand: true))
        #expect(!viewModel.isContentRevealed(autoExpand: false))
    }

    @Test func filterOnlyPostRevealsAfterShowAnyway() {
        let viewModel = ContentConcealViewModel(
            statusID: "1", hasContentWarning: false, hasFilterWarning: true,
            spoilerText: nil, filterWarningText: "Filtered"
        )
        #expect(!viewModel.isContentRevealed)
        viewModel.revealFilteredContent()
        #expect(viewModel.isContentRevealed)
    }

    @Test func exportSniffsRealImageTypeOverURLExtension() {
        let png = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let type = MediaExportService.sniffType(png, url: URL(string: "https://example.com/media/original")!)
        #expect(type == .png)
    }
}
