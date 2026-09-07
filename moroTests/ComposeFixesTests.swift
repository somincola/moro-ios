//
//  ComposeFixesTests.swift
//  moroTests
//
//  Regression tests for the compose robustness fixes:
//  - Media sensitivity follows the content warning (A).
//  - File-extension → MIME resolution produces valid MIME types (D).
//

import Testing
@testable import moro
import Foundation
import CoreGraphics
import UIKit

@MainActor
struct ComposeFixesTests {

    // MARK: - Composer input mode

    @Test func composerInputModeKeepsTextFocusedForBothInputSources() {
        #expect(ComposeInputMode.idle.requestsTextFocus == false)
        #expect(ComposeInputMode.idle.showsEmojiPicker == false)
        #expect(ComposeInputMode.keyboard.requestsTextFocus)
        #expect(ComposeInputMode.keyboard.showsEmojiPicker == false)
        #expect(ComposeInputMode.emoji.requestsTextFocus)
        #expect(ComposeInputMode.emoji.showsEmojiPicker)
    }

    @Test func composerEmojiToggleSwitchesInputSourceWithoutIdleState() {
        #expect(ComposeInputMode.idle.togglingEmojiPicker() == .emoji)
        #expect(ComposeInputMode.keyboard.togglingEmojiPicker() == .emoji)
        #expect(ComposeInputMode.emoji.togglingEmojiPicker() == .keyboard)
    }

    @Test func composerEmojiPickerHeightTracksKeyboardWithinSafeBounds() {
        #expect(ComposeInputLayout.defaultEmojiPickerHeight == 300)
        #expect(
            ComposeInputLayout.emojiPickerHeight(
                from: CGRect(x: 0, y: 500, width: 430, height: 346)
            ) == 346
        )
        #expect(
            ComposeInputLayout.emojiPickerHeight(
                from: CGRect(x: 0, y: 300, width: 430, height: 500)
            ) == 500
        )
        #expect(
            ComposeInputLayout.emojiPickerHeight(
                from: CGRect(x: 0, y: 600, width: 430, height: 180)
            ) == 240
        )
        #expect(ComposeInputLayout.emojiPickerHeight(from: .zero) == nil)
    }

    @Test func composerUtilityControlsMeetMinimumTouchTarget() {
        #expect(MoroUtilityButtonMetrics.visualSize == 34)
        #expect(MoroUtilityButtonMetrics.hitTargetSize >= 44)
    }

    @Test func composerPhotoSelectionNeverExceedsFourTotalAttachments() {
        #expect(ComposeMediaSelectionPolicy.maximumAttachmentCount == 4)
        #expect(ComposeMediaSelectionPolicy.maximumConcurrentImports == 2)
        #expect(ComposeMediaSelectionPolicy.remainingSlots(existingCount: 0) == 4)
        #expect(ComposeMediaSelectionPolicy.remainingSlots(existingCount: 3) == 1)
        #expect(ComposeMediaSelectionPolicy.remainingSlots(existingCount: 4) == 0)
        #expect(
            ComposeMediaSelectionPolicy.acceptedSelectionCount(
                requestedCount: 4,
                existingCount: 2
            ) == 2
        )
    }

    @Test func composerEmojiAnimationUsesOriginalMediaAndHonorsRuntimePauses() throws {
        let animatedURL = try #require(URL(string: "https://example.test/emoji-original.png"))
        let staticURL = try #require(URL(string: "https://example.test/emoji-static.png"))

        #expect(
            ComposeEmojiAnimationPolicy.imageURL(
                animatedURL: animatedURL,
                staticURL: staticURL,
                reduceMotion: false
            ) == animatedURL
        )
        #expect(
            ComposeEmojiAnimationPolicy.imageURL(
                animatedURL: animatedURL,
                staticURL: staticURL,
                animationsEnabled: false,
                reduceMotion: false
            ) == staticURL
        )
        #expect(
            ComposeEmojiAnimationPolicy.imageURL(
                animatedURL: animatedURL,
                staticURL: staticURL,
                reduceMotion: true
            ) == staticURL
        )
        #expect(
            ComposeEmojiAnimationPolicy.imageURL(
                animatedURL: animatedURL,
                staticURL: staticURL,
                reduceMotion: false,
                usesStaticFallback: true
            ) == staticURL
        )
        // The composer emoji surface is hosted as UITextView.inputView. Its detached
        // UIHostingController may not inherit scenePhase, so visibility gates loading while
        // scene activity only gates playback.
        #expect(ComposeEmojiAnimationPolicy.shouldLoadImage(isVisible: true))
        #expect(!ComposeEmojiAnimationPolicy.shouldLoadImage(isVisible: false))
        #expect(
            ComposeEmojiAnimationPolicy.shouldAnimate(
                isVisible: true,
                isSceneActive: true,
                animationsEnabled: true,
                reduceMotion: false
            )
        )
        #expect(
            !ComposeEmojiAnimationPolicy.shouldAnimate(
                isVisible: true,
                isSceneActive: false,
                animationsEnabled: true,
                reduceMotion: false
            )
        )
        #expect(
            !ComposeEmojiAnimationPolicy.shouldAnimate(
                isVisible: true,
                isSceneActive: true,
                animationsEnabled: true,
                reduceMotion: false,
                usesStaticFallback: true
            )
        )
        #expect(
            !ComposeEmojiAnimationPolicy.shouldAnimate(
                isVisible: true,
                isSceneActive: true,
                animationsEnabled: false,
                reduceMotion: false
            )
        )
        #expect(
            !ComposeEmojiAnimationPolicy.shouldAnimate(
                isVisible: true,
                isSceneActive: true,
                animationsEnabled: true,
                reduceMotion: true
            )
        )
        #expect(
            ComposeEmojiAnimationPolicy.shouldFallbackAfterLoadFailure(
                animationsEnabled: true,
                reduceMotion: false,
                usesStaticFallback: false
            )
        )
        #expect(
            !ComposeEmojiAnimationPolicy.shouldFallbackAfterLoadFailure(
                animationsEnabled: false,
                reduceMotion: false,
                usesStaticFallback: false
            )
        )
        #expect(
            !ComposeEmojiAnimationPolicy.shouldFallbackAfterLoadFailure(
                animationsEnabled: true,
                reduceMotion: false,
                usesStaticFallback: true
            )
        )
    }

    @Test func composerAnimatedDecodePipelineIsExplicitlyScopedAwayFromTimelineMedia() throws {
        let url = try #require(URL(string: "https://example.test/animated.gif"))

        let sharedDefault = SDWebRemoteImage(
            url: url,
            thumbnailPixelSize: 320,
            allowsAnimation: true
        )
        let composerPreview = SDWebRemoteImage(
            url: url,
            thumbnailPixelSize: 80,
            allowsAnimation: true,
            animationLoadingMode: .boundedPreview,
            maximumAnimatedBufferSize: 2 * 1024 * 1024
        )

        #expect(sharedDefault.animationLoadingMode == .standard)
        #expect(composerPreview.animationLoadingMode == .boundedPreview)
        #expect(composerPreview.maximumAnimatedBufferSize == 2 * 1024 * 1024)
    }

    @Test func scheduledPublishingHasOneDisabledCapabilityBoundary() {
        #expect(ComposeFeatureAvailability.scheduledPublishing == false)
    }

    @Test func composerDestinationsUseOneExplicitPresentationChannel() {
        let sheetDestinations: [ComposeDestination] = [
            .drafts,
            .preview,
            .mediaOrder,
            .camera,
            .altText(attachmentID: "media-0"),
            .language,
            .schedule,
        ]
        #expect(sheetDestinations.allSatisfy { $0.presentation == .sheet })
        #expect(ComposeDestination.photoLibrary.presentation == .photosPicker)
        #expect(ComposeDestination.fileImporter.presentation == .fileImporter)
        #expect(ComposeDestination.missingAltTextConfirmation.presentation == .alert)
        #expect(ComposeDestination.discardConfirmation.presentation == .alert)
    }

    @Test func composerDestinationIdentityKeepsAltEditorsDistinct() {
        let destinations: [ComposeDestination] = [
            .drafts,
            .preview,
            .mediaOrder,
            .photoLibrary,
            .camera,
            .fileImporter,
            .altText(attachmentID: "media-0"),
            .altText(attachmentID: "media-1"),
            .language,
            .schedule,
            .missingAltTextConfirmation,
            .discardConfirmation,
        ]

        #expect(Set(destinations.map(\.id)).count == destinations.count)
    }

    @Test func composerFocusCallbacksPreserveTheActiveInputSource() {
        #expect(ComposeInputMode.idle.updatingTextFocus(true) == .keyboard)
        #expect(ComposeInputMode.keyboard.updatingTextFocus(true) == .keyboard)
        #expect(ComposeInputMode.emoji.updatingTextFocus(true) == .emoji)
        #expect(ComposeInputMode.keyboard.updatingTextFocus(false) == .idle)
        #expect(ComposeInputMode.emoji.updatingTextFocus(false) == .idle)
    }

    @Test func composerEmojiInsertionUsesCurrentCaret() {
        let result = ComposeTextEditing.insertingEmoji(
            shortcode: "cat",
            into: "hello world",
            selection: NSRange(location: 5, length: 0)
        )

        #expect(result.text == "hello :cat: world")
        #expect(result.selection == NSRange(location: 11, length: 0))
    }

    @Test func composerEmojiInsertionReplacesSelectionAndNormalizesSpacing() {
        let result = ComposeTextEditing.insertingEmoji(
            shortcode: "wave",
            into: "hello friend",
            selection: NSRange(location: 6, length: 6)
        )

        #expect(result.text == "hello :wave: ")
        #expect(result.selection == NSRange(location: 13, length: 0))
    }

    @Test func emojiPickerExcludesServerHiddenEmoji() {
        let visible = makeEmoji(shortcode: "visible", visibleInPicker: true)
        let hidden = makeEmoji(shortcode: "hidden", visibleInPicker: false)

        let result = CustomEmojiViewModel.emojisVisibleInPicker(from: [hidden, visible])

        #expect(result.map(\.shortcode) == ["visible"])
    }

    // MARK: - A: media sensitivity follows the content warning

    @Test func mediaSensitivityIsNilWithoutVisualMedia() {
        #expect(ComposeViewModel.resolveMediaSensitivity(
            hasVisualMedia: false, contentWarningActive: true, contentWarning: "cw") == nil)
        #expect(ComposeViewModel.resolveMediaSensitivity(
            hasVisualMedia: false, contentWarningActive: false, contentWarning: "") == nil)
    }

    @Test func mediaSensitivityIsTrueWithActiveContentWarning() {
        #expect(ComposeViewModel.resolveMediaSensitivity(
            hasVisualMedia: true, contentWarningActive: true, contentWarning: "spoiler") == true)
    }

    @Test func mediaSensitivityIsFalseWithoutContentWarning() {
        #expect(ComposeViewModel.resolveMediaSensitivity(
            hasVisualMedia: true, contentWarningActive: false, contentWarning: "") == false)
        // CW toggled on but blank text is not a real warning.
        #expect(ComposeViewModel.resolveMediaSensitivity(
            hasVisualMedia: true, contentWarningActive: true, contentWarning: "   ") == false)
    }

    // MARK: - D: file extension → MIME

    @Test func mediaTypeResolvesJpgToProperMime() {
        #expect(ComposeMediaType.resolve(fileExtension: "jpg").mimeType == "image/jpeg")
        #expect(ComposeMediaType.resolve(fileExtension: "JPG").mimeType == "image/jpeg")
        #expect(ComposeMediaType.resolve(fileExtension: "jpeg").mimeType == "image/jpeg")
    }

    @Test func mediaTypeResolvesImagesAndVideos() {
        #expect(ComposeMediaType.resolve(fileExtension: "png").mediaKind == "image")
        #expect(ComposeMediaType.resolve(fileExtension: "gif").mimeType == "image/gif")

        let mp4 = ComposeMediaType.resolve(fileExtension: "mp4")
        #expect(mp4.mimeType == "video/mp4")
        #expect(mp4.mediaKind == "video")
        #expect(ComposeMediaType.resolve(fileExtension: "mov").mediaKind == "video")
    }

    @Test func mediaProcessorDownsamplesLargePhotosAndBuildsPreviewOnce() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 3200, height: 2400))
        let sourceData = try #require(renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3200, height: 2400))
        }.jpegData(compressionQuality: 0.95))

        let prepared = try await ComposeMediaProcessor.shared.preparePhotoData(sourceData)

        #expect(prepared.uploadMimeType == "image/jpeg")
        #expect(prepared.mediaType == "image")
        let uploadImage = try #require(UIImage(data: prepared.uploadData))
        #expect(max(uploadImage.size.width, uploadImage.size.height) <= 1920)
        let previewImage = try #require(prepared.previewImage)
        #expect(max(previewImage.size.width, previewImage.size.height) <= 720)
    }

    @Test func mediaProcessorPreservesImportedPayloadAndMimeType() async throws {
        let sourceData = Data([0x00, 0x01, 0x02, 0x03])
        let prepared = try await ComposeMediaProcessor.shared.prepareImportedData(
            sourceData,
            mimeType: "video/mp4",
            mediaType: "video"
        )

        #expect(prepared.uploadData == sourceData)
        #expect(prepared.uploadMimeType == "video/mp4")
        #expect(prepared.mediaType == "video")
        #expect(prepared.previewImage == nil)
    }

    // MARK: - Mastodon character counting

    @Test func mastodonCounterCountsAUrlAsTwentyThree() {
        let longURL = "https://example.com/" + String(repeating: "a", count: 100)
        #expect(MastodonTextCounter.count(longURL) == 23)
        #expect(MastodonTextCounter.count("hi " + longURL) == 26)  // "hi " (3) + url (23)
    }

    @Test func mastodonCounterExcludesRemoteMentionDomain() {
        #expect(MastodonTextCounter.count("@bob@mastodon.social") == 4)  // only "@bob" counts
        #expect(MastodonTextCounter.count("@bob") == 4)                  // local mention counts fully
    }

    @Test func mastodonCounterPlainText() {
        #expect(MastodonTextCounter.count("hello world") == 11)
    }

    // MARK: - Media upload (processing / HTTP 202)

    @Test func attachmentDecodesProcessingMediaWithNullURL() throws {
        // A still-processing upload (HTTP 202) returns url: null plus a preview_url;
        // decoding must not fail (the old non-optional url crashed the upload).
        let json = #"{"id":"m1","type":"video","url":null,"preview_url":"https://example.test/p.jpg"}"#
        let attachment = try JSONDecoder().decode(Status.Attachment.self, from: Data(json.utf8))
        #expect(attachment.id == "m1")
        #expect(attachment.url.absoluteString == "https://example.test/p.jpg")
        #expect(attachment.previewURL?.absoluteString == "https://example.test/p.jpg")
    }

    private func makeEmoji(shortcode: String, visibleInPicker: Bool) -> CustomEmoji {
        CustomEmoji(
            shortcode: shortcode,
            url: URL(string: "https://example.test/\(shortcode).png")!,
            staticURL: URL(string: "https://example.test/\(shortcode)-static.png")!,
            visibleInPicker: visibleInPicker,
            category: "Test"
        )
    }
}
