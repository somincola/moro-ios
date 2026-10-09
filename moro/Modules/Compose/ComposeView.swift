//
//  ComposeView.swift
//  moro
//
//  Compose view for creating new posts, replies, quotes, and editing statuses.
//

import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

enum ComposeInputMode: Equatable {
    case idle
    case keyboard
    case emoji

    var requestsTextFocus: Bool {
        self != .idle
    }

    var showsEmojiPicker: Bool {
        self == .emoji
    }

    func togglingEmojiPicker() -> ComposeInputMode {
        self == .emoji ? .keyboard : .emoji
    }

    func updatingTextFocus(_ isFocused: Bool) -> ComposeInputMode {
        if isFocused {
            return self == .idle ? .keyboard : self
        }

        return .idle
    }
}

enum ComposeInputLayout {
    static let defaultEmojiPickerHeight: CGFloat = 300
    static let minimumEmojiPickerHeight: CGFloat = 240
    static let maximumEmojiPickerHeight: CGFloat = 500

    static func emojiPickerHeight(from keyboardFrame: CGRect) -> CGFloat? {
        let height = keyboardFrame.height
        guard height.isFinite, height > 0 else { return nil }
        return min(max(height, minimumEmojiPickerHeight), maximumEmojiPickerHeight)
    }
}

enum ComposeEmojiAnimationPolicy {
    static func shouldLoadImage(isVisible: Bool) -> Bool {
        isVisible
    }

    static func imageURL(
        animatedURL: URL,
        staticURL: URL,
        animationsEnabled: Bool = true,
        reduceMotion: Bool,
        usesStaticFallback: Bool = false
    ) -> URL {
        if animationsEnabled, !reduceMotion, !usesStaticFallback {
            return animatedURL
        }
        return staticURL
    }

    static func shouldAnimate(
        isVisible: Bool,
        isSceneActive: Bool,
        animationsEnabled: Bool,
        reduceMotion: Bool,
        usesStaticFallback: Bool = false
    ) -> Bool {
        isVisible
            && isSceneActive
            && animationsEnabled
            && !reduceMotion
            && !usesStaticFallback
    }

    static func shouldFallbackAfterLoadFailure(
        animationsEnabled: Bool,
        reduceMotion: Bool,
        usesStaticFallback: Bool
    ) -> Bool {
        animationsEnabled && !reduceMotion && !usesStaticFallback
    }
}

struct ComposeTextInsertionResult: Equatable {
    let text: String
    let selection: NSRange
}

struct ComposeTextSelectionCommand: Equatable {
    let id = UUID()
    let range: NSRange
    let scrollsToSelection: Bool
}

enum ComposeTextEditing {
    static func insertingEmoji(
        shortcode: String,
        into text: String,
        selection: NSRange
    ) -> ComposeTextInsertionResult {
        let source = text as NSString
        let safeSelection = clamped(selection, in: source.length)
        let replacedEnd = NSMaxRange(safeSelection)

        var insertion = ":\(shortcode):"
        if safeSelection.location > 0,
           !isWhitespace(in: source, at: safeSelection.location - 1) {
            insertion.insert(" ", at: insertion.startIndex)
        }
        if replacedEnd == source.length || !isWhitespace(in: source, at: replacedEnd) {
            insertion.append(" ")
        }

        let updated = NSMutableString(string: text)
        updated.replaceCharacters(in: safeSelection, with: insertion)
        let caretLocation = safeSelection.location + (insertion as NSString).length
        return ComposeTextInsertionResult(
            text: updated as String,
            selection: NSRange(location: caretLocation, length: 0)
        )
    }

    private static func clamped(_ range: NSRange, in length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        let remaining = max(length - location, 0)
        return NSRange(location: location, length: min(max(range.length, 0), remaining))
    }

    private static func isWhitespace(in text: NSString, at location: Int) -> Bool {
        guard location >= 0, location < text.length else { return false }
        let character = text.substring(with: NSRange(location: location, length: 1))
        return character.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
    }
}

struct ComposeView: View {
    @StateObject private var viewModel: ComposeViewModel
    @StateObject private var autocomplete: ComposeAutocompleteModel
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.moroTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var destination: ComposeDestination?
    @State private var isExpandedEditor = false
    @State private var inputMode: ComposeInputMode = .keyboard
    @State private var emojiPickerHeight = ComposeInputLayout.defaultEmojiPickerHeight
    @State private var textSelection: NSRange
    @State private var textSelectionCommand: ComposeTextSelectionCommand?
    @State private var editingAltText: String = ""
    @State private var hasMarkedText = false
    @State private var completedAutocompleteToken: ComposeAutocompleteToken?
    @State private var emojiViewModel: CustomEmojiViewModel?
    @State private var pendingScheduledDate = ComposeViewModel.defaultScheduledDate()
    @State private var hasProcessedSharedImport = false
    @State private var isCompletingPublish = false
    @State private var publishFailureMessage: String?
    @State private var publishDraftSaved: Bool?
    
    private let draftStore: ComposeDraftStore
    private let sharedImport: SharedComposeAttachmentImportPayload?
    private let onDismiss: (() -> Void)?
    let onPublish: ((Status) -> Void)?
    
    init(
        context: ComposeViewModel.ComposeContext,
        apiClient: MastodonAPI,
        currentUserID: String? = nil,
        draftStore: ComposeDraftStore? = nil,
        initialDraft: ComposeDraft? = nil,
        accountCache: AccountCache? = nil,
        sharedImport: SharedComposeAttachmentImportPayload? = nil,
        onDismiss: (() -> Void)? = nil,
        onPublish: ((Status) -> Void)? = nil
    ) {
        let resolvedDraftStore = draftStore ?? ComposeDraftStore.shared
        let resolvedViewModel = ComposeViewModel(
            context: context,
            apiClient: apiClient,
            currentUserID: currentUserID,
            accountCache: accountCache,
            initialDraft: initialDraft
        )
        self.draftStore = resolvedDraftStore
        self.sharedImport = sharedImport
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: resolvedViewModel)
        _autocomplete = StateObject(wrappedValue: ComposeAutocompleteModel(apiClient: apiClient))
        _textSelection = State(
            initialValue: NSRange(
                location: (resolvedViewModel.content as NSString).length,
                length: 0
            )
        )
        _textSelectionCommand = State(initialValue: nil)
        self.onPublish = onPublish
    }
    
    // Current user avatar info
    private var currentUserAvatar: (url: URL?, staticURL: URL?, initials: String) {
        if let account = appState.currentAccount {
            return (
                url: account.avatarAnimatedURL,
                staticURL: account.avatarURL,
                initials: account.displayNameInitials
            )
        }
        return (url: nil, staticURL: nil, initials: "ME")
    }

    private var sheetDestination: Binding<ComposeDestination?> {
        Binding(
            get: {
                guard destination?.presentation == .sheet else { return nil }
                return destination
            },
            set: { newValue in
                if let newValue {
                    destination = newValue
                } else if destination?.presentation == .sheet {
                    destination = nil
                }
            }
        )
    }

    private var isPublishingOrClosing: Bool {
        viewModel.isPublishing || viewModel.hasPublished
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isExpandedEditor && viewModel.isEditingSourceReady {
                    VStack(spacing: theme.spacing.s) {
                        if viewModel.isContentWarningActive { contentWarningSection }
                        textInputSection
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(theme.spacing.m)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            if let originalStatus = viewModel.originalStatus {
                                ComposeOriginalPostSection(
                                    originalStatus: originalStatus,
                                    presentationStyle: originalPostPresentationStyle
                                )
                            }

                            if viewModel.isEditingSourceReady {
                                inputSection
                            } else {
                                editSourcePlaceholder
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .contentShape(Rectangle())
                    .scrollDismissesKeyboard(.interactively)
                    .accessibilityIdentifier("compose.contentScroll")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                publishFailureNotice

                if let token = autocompleteToken {
                    ComposeSuggestionsView(token: token, model: autocomplete) { suggestion in
                        insertSuggestion(suggestion, for: token)
                    }
                }

                bottomSection
                    .disabled(!viewModel.isEditingSourceReady)
            }
            .disabled(isPublishingOrClosing)
            .background(theme.colors.background)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            // Block swipe-to-dismiss while there's unsaved content so the user is routed
            // through the Cancel button's save-draft / discard confirmation instead of
            // silently losing the post.
            .interactiveDismissDisabled(viewModel.hasDraftableContent)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(MoroL10n.Common.cancel) {
                        if viewModel.hasDraftableContent {
                            destination = .discardConfirmation
                        } else {
                            dismissComposer()
                        }
                    }
                    .disabled(isPublishingOrClosing)
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            let selection = textSelection
                            isExpandedEditor.toggle()
                            textSelectionCommand = ComposeTextSelectionCommand(
                                range: selection, scrollsToSelection: true
                            )
                        } label: {
                            Label(isExpandedEditor ? MoroL10n.ComposeReading.collapse : MoroL10n.ComposeReading.expand,
                                systemImage: isExpandedEditor ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        }
                        .accessibilityIdentifier("compose.expandEditor")
                        Button {
                            inputMode = .idle
                            destination = .preview
                        } label: {
                            Label(MoroL10n.ComposeReading.preview, systemImage: "eye")
                        }
                        .accessibilityIdentifier("compose.preview")
                        Button {
                            inputMode = .idle
                            destination = .mediaOrder
                        } label: {
                            Label(MoroL10n.ComposeReading.mediaOrder, systemImage: "arrow.up.arrow.down")
                        }
                        .disabled(viewModel.mediaAttachments.count < 2)
                        .accessibilityIdentifier("compose.mediaOrder")
                    } label: {
                        Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(!viewModel.isEditingSourceReady || isPublishingOrClosing)
                    .accessibilityLabel(MoroL10n.ComposeReading.options)
                    .accessibilityIdentifier("compose.editorOptions")

                    Button {
                        Task {
                            await publish()
                        }
                    } label: {
                        ZStack {
                            Text(primaryActionTitle)
                                .opacity(isPublishingOrClosing ? 0 : 1)
                            if isPublishingOrClosing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(!viewModel.canPublish)
                    .accessibilityIdentifier("compose.postButton")
                    .fontWeight(.semibold)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(primaryActionTitle))
                    .accessibilityValue(Text(isPublishingOrClosing ? publishingButtonText : ""))
                }
            }
            .alert(
                MoroL10n.Compose.missingAltTitle,
                isPresented: destinationBinding(for: .missingAltTextConfirmation)
            ) {
                Button(MoroL10n.Common.cancel, role: .cancel) { }
                Button(MoroL10n.Compose.continuePublish) {
                    Task {
                        await performPublish()
                    }
                }
            } message: {
                Text(MoroL10n.Compose.missingAltMessage)
            }
            .alert(
                MoroL10n.ComposeDrafts.discardTitle,
                isPresented: destinationBinding(for: .discardConfirmation)
            ) {
                Button(MoroL10n.ComposeDrafts.saveDraftAction) {
                    saveDraftAndDismiss()
                }
                Button(MoroL10n.ComposeDrafts.discardAction, role: .destructive) {
                    discardDraftAndDismiss()
                }
                Button(MoroL10n.Common.cancel, role: .cancel) { }
            }
            .sheet(item: sheetDestination) { destination in
                composeSheet(for: destination)
            }
            .photosPicker(
                isPresented: destinationBinding(for: .photoLibrary),
                selection: $selectedPhotos,
                maxSelectionCount: max(viewModel.remainingMediaAttachmentSlots, 1),
                selectionBehavior: .ordered,
                matching: .images,
                preferredItemEncoding: .current
            )
            .fileImporter(
                isPresented: destinationBinding(for: .fileImporter),
                allowedContentTypes: [.image, .movie],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        Task {
                            await handleFileSelection(url)
                        }
                    }
                case .failure:
                    break
                }
            }
            .onChange(of: selectedPhotos) { _, newValue in
                guard !newValue.isEmpty else { return }

                let acceptedItems = Array(
                    newValue.prefix(viewModel.remainingMediaAttachmentSlots)
                )
                selectedPhotos = []
                let reservationIDs = viewModel.reservePhotoImports(count: acceptedItems.count)
                guard !reservationIDs.isEmpty else { return }

                Task {
                    await handlePhotoSelections(
                        acceptedItems,
                        reservationIDs: reservationIDs
                    )
                }
            }
            .onAppear {
                if let sharedImport, !hasProcessedSharedImport {
                    hasProcessedSharedImport = true
                    Task {
                        await importSharedAttachments(from: sharedImport)
                    }
                }
            }
            .onDisappear {
                if isCompletingPublish {
                    AppLogger.debug("[Compose] Published composer disappeared")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { notification in
                updateEmojiPickerHeight(from: notification)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    autosaveDraftIfNeeded()
                }
            }
            .task(priority: .utility) {
                await viewModel.loadInstanceLimits()
            }
            .task {
                await loadEditingSource()
            }
            .task(id: autocompleteToken) {
                await autocomplete.load(for: autocompleteToken)
            }
        }
    }

    private var editSourcePlaceholder: some View {
        VStack(spacing: theme.spacing.m) {
            if viewModel.editSourceState == .failed {
                Image(systemName: "exclamationmark.triangle")
                    .font(theme.typography.title)
                    .foregroundStyle(theme.colors.textSecondary)
                    .accessibilityHidden(true)
                Text(MoroL10n.Compose.editSourceFailed)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await loadEditingSource() }
                } label: {
                    Text(MoroL10n.Compose.retry)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .tint(theme.colors.primary500)
                .accessibilityIdentifier("compose.retryEditSource")
            } else {
                ProgressView(MoroL10n.Compose.editSourceLoading)
                    .accessibilityIdentifier("compose.editSourceLoading")
            }
        }
        .frame(maxWidth: .infinity, minHeight: fixedTextInputHeight)
        .padding(theme.spacing.m)
    }

    private func loadEditingSource() async {
        await viewModel.loadEditingSourceIfNeeded()
        if case .edit = viewModel.context, viewModel.isEditingSourceReady {
            textSelection = NSRange(location: (viewModel.content as NSString).length, length: 0)
        }
    }

    private func destinationBinding(for target: ComposeDestination) -> Binding<Bool> {
        Binding(
            get: { destination == target },
            set: { isPresented in
                if isPresented {
                    destination = target
                } else if destination == target {
                    destination = nil
                }
            }
        )
    }

    @ViewBuilder
    private func composeSheet(for destination: ComposeDestination) -> some View {
        switch destination {
        case .preview:
            ComposePreviewSheet(viewModel: viewModel, account: appState.currentAccount)
                .moroSheetSurface(detents: [.large])
        case .mediaOrder:
            ComposeMediaOrderSheet(viewModel: viewModel)
                .moroSheetSurface(detents: [.large])
        case .drafts:
            ComposeDraftsSheet(
                accountID: appState.currentAccount?.id,
                draftStore: draftStore
            ) { draft in
                self.destination = nil
                viewModel.applyRestoredDraft(draft)
                AppFeedbackCenter.shared.showInfo(MoroL10n.ComposeDrafts.restored)
            }
            .accessibilityIdentifier("compose.draftsSheet")
        case .camera:
            CameraView { image in
                self.destination = nil
                Task {
                    await handleImageSelection(image)
                }
            }
        case .altText(let attachmentID):
            if let attachment = viewModel.mediaAttachment(id: attachmentID) {
                AltTextEditorView(
                    altText: $editingAltText,
                    imageURL: attachment.previewURL ?? attachment.url,
                    onSave: {
                        viewModel.updateMediaAltText(id: attachmentID, altText: editingAltText)
                        self.destination = nil
                    },
                    onCancel: {
                        self.destination = nil
                    }
                )
            }
        case .language:
            NavigationStack {
                PostLanguagePickerView(
                    title: MoroL10n.Language.composePickerTitle,
                    selectedLanguageCode: $viewModel.selectedLanguageCode,
                    defaultBehavior: settings.defaultPostLanguageBehavior,
                    showsDismissButton: true
                )
            }
        case .schedule:
            schedulePickerSheet
                .moroSheetSurface(detents: [.large])
                .accessibilityIdentifier("compose.scheduleSheet")
        case .photoLibrary, .fileImporter, .missingAltTextConfirmation, .discardConfirmation:
            EmptyView()
        }
    }

    // MARK: - Navigation Title
    
    private var navigationTitle: String {
        switch viewModel.context {
        case .newPost:
            return MoroL10n.Compose.navigationNewPost
        case .reply:
            return MoroL10n.Compose.navigationReply
        case .quote:
            return MoroL10n.Compose.navigationQuote
        case .edit:
            return MoroL10n.Compose.navigationEdit
        }
    }

    private var originalPostPresentationStyle: ComposeOriginalPostView.PresentationStyle {
        switch viewModel.context {
        case .quote:
            return .quote
        case .newPost, .reply, .edit:
            return .reply
        }
    }
    
    // MARK: - Content Warning Section
    
    @ViewBuilder
    private var contentWarningSection: some View {
        TextField(
            "",
            text: $viewModel.contentWarning,
            prompt: Text(MoroL10n.Compose.contentWarningPlaceholder)
                .foregroundStyle(theme.colors.textSecondary),
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(theme.typography.body)
        .foregroundStyle(theme.colors.textPrimary)
        .tint(theme.colors.primary500)
        .lineLimit(1...3)
        .padding(.horizontal, theme.spacing.m + 5)
        .padding(.vertical, theme.spacing.s)
        .frame(minHeight: 44)
        .accessibilityIdentifier("compose.contentWarningInput")
        .accessibilityLabel(MoroL10n.Compose.contentWarningPlaceholder)
        .background(theme.colors.surfaceSubtle)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.colors.borderSubtle, lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            Image("ContentWarningHazardStripe")
                .resizable(resizingMode: .tile)
                .frame(width: 5)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .trailing) {
            Image("ContentWarningHazardStripe")
                .resizable(resizingMode: .tile)
                .frame(width: 5)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    
    // MARK: - Input Section
    
    @ViewBuilder
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: usesCompactReplyComposerLayout ? theme.spacing.xs : theme.spacing.s) {
            composeIdentityHeader

            if viewModel.isContentWarningActive {
                contentWarningSection
            }

            textInputSection

            if !viewModel.mediaAttachments.isEmpty {
                mediaAttachmentsSection
            }

            if viewModel.isPollActive {
                pollSection
            }
        }
        .padding(.horizontal, theme.spacing.m)
        .padding(.top, usesCompactReplyComposerLayout ? theme.spacing.xs : theme.spacing.s)
        .padding(.bottom, usesCompactReplyComposerLayout ? theme.spacing.s : theme.spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composeIdentityHeader: some View {
        HStack(spacing: theme.spacing.s) {
            MoroAvatar(
                imageURL: currentUserAvatar.url,
                staticImageURL: currentUserAvatar.staticURL,
                initials: currentUserAvatar.initials,
                size: usesCompactReplyComposerLayout ? 36 : 40
            )

            if supportsAudienceConfiguration {
                Menu {
                    audienceMenuContent
                } label: {
                    audienceHeaderControl
                }
                .menuStyle(.borderlessButton)
                .accessibilityIdentifier("compose.audienceMenu")
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: MoroUtilityButtonMetrics.hitTargetSize)
    }

    private var audienceHeaderControl: some View {
        let isActive = isAudienceConfigurationCustomized
        let color = isActive ? theme.colors.primary500 : theme.colors.textSecondary

        return HStack(spacing: 6) {
            Image(systemName: visibilityIcon)
                .moroScaledFont(size: 13, weight: .semibold)

            Text(audienceConfigurationSummary)
                .font(theme.typography.caption)
                .fontWeight(.semibold)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Image(systemName: "chevron.down")
                .moroScaledFont(size: 9, weight: .bold)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .frame(minHeight: 34)
        .background(
            Capsule(style: .continuous)
                .fill(isActive ? color.opacity(0.10) : theme.colors.surfaceSubtle)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(isActive ? color.opacity(0.24) : theme.colors.borderSubtle, lineWidth: 1)
        )
        .frame(minHeight: MoroUtilityButtonMetrics.hitTargetSize)
        .contentShape(Capsule(style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(audienceConfigurationSummary))
    }
    
    // MARK: - Reply Context Hint
    
    @ViewBuilder
    private func replyContextHint(originalStatus: Status) -> some View {
        HStack(spacing: 4) {
            Text(MoroL10n.Compose.replyHint)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
            Text("@\(originalStatus.account.username)")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.primary500)
        }
        .padding(.bottom, theme.spacing.xs)
    }
    
    // MARK: - Text Input Section

    private var textEditorFocus: Binding<Bool> {
        Binding(
            get: { inputMode.requestsTextFocus },
            set: { isFocused in
                inputMode = inputMode.updatingTextFocus(isFocused)
            }
        )
    }

    private func toggleEmojiPicker() {
        let nextMode = inputMode.togglingEmojiPicker()
        if nextMode == .emoji {
            loadEmojiViewModelIfNeeded()
        }
        inputMode = nextMode
    }

    private func updateEmojiPickerHeight(from notification: Notification) {
        guard
            inputMode == .keyboard,
            let value = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue,
            let height = ComposeInputLayout.emojiPickerHeight(from: value.cgRectValue),
            abs(emojiPickerHeight - height) >= 1
        else { return }
        emojiPickerHeight = height
    }
    
    // Computed property for placeholder text
    private var placeholderText: String {
        switch viewModel.context {
        case .newPost:
            return MoroL10n.Compose.placeholderNewPost
        case .reply:
            return MoroL10n.Compose.placeholderReply
        case .quote:
            return MoroL10n.Compose.placeholderQuote
        case .edit:
            return MoroL10n.Compose.placeholderEdit
        }
    }
    
    @ViewBuilder
    private var textInputSection: some View {
        ComposeTextViewRepresentable(
            text: $viewModel.content,
            selection: $textSelection,
            selectionCommand: $textSelectionCommand,
            isFocused: textEditorFocus,
            hasMarkedText: $hasMarkedText,
            isExpanded: isExpandedEditor,
            minimumHeight: usesCompactReplyComposerLayout ? 120 : 180,
            inputMode: inputMode,
            emojiPickerHeight: emojiPickerHeight,
            emojiViewModel: emojiViewModel,
            hasEmojiHost: accountHost != nil,
            isSceneActive: scenePhase == .active,
            playAnimations: settings.playAnimations,
            theme: theme,
            textColor: UIColor(theme.colors.textPrimary),
            placeholder: placeholderText,
            placeholderColor: UIColor(theme.colors.textSecondary),
            onEmojiSelected: insertEmoji
        )
    }

    private var inlineCharacterCounter: some View {
        Text(inlineCharacterCounterText)
            .moroScaledFont(size: 12, weight: .medium)
            .monospacedDigit()
            .foregroundStyle(inlineCharacterCounterColor)
            .fixedSize()
            .accessibilityIdentifier("compose.characterCounter")
            .accessibilityLabel(MoroL10n.Compose.accessibilityCharacterProgress)
            .accessibilityValue("\(viewModel.characterCount)/\(viewModel.maxCharacters)")
            .allowsHitTesting(false)
    }
    
    // MARK: - Media Attachments Section
    
    @ViewBuilder
    private var mediaAttachmentsSection: some View {
        ComposeMediaGridView(
            attachments: viewModel.mediaAttachments,
            onRemove: { attachmentID in
                viewModel.removeMedia(id: attachmentID)
            },
            onEditAlt: { attachmentID in
                guard let attachment = viewModel.mediaAttachment(id: attachmentID) else {
                    return
                }
                editingAltText = attachment.description ?? ""
                destination = .altText(attachmentID: attachmentID)
            },
            onRetry: { attachmentID in
                Task {
                    await retryMediaUpload(attachmentID: attachmentID)
                }
            }
        )
    }

    @ViewBuilder
    private var publishValidationBanner: some View {
        if let reason = nonMediaPublishDisabledReason {
            HStack(spacing: theme.spacing.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .moroScaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(theme.colors.warning)

                Text(reason)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.colors.surfaceSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(theme.colors.warning.opacity(0.25), lineWidth: 1)
            )
            .padding(.horizontal, theme.spacing.m)
            .padding(.bottom, theme.spacing.s)
        }
    }

    private var nonMediaPublishDisabledReason: String? {
        switch viewModel.publishBlocker {
        case .mediaUploading, .mediaUploadFailed:
            return nil
        default:
            return viewModel.publishDisabledReason
        }
    }

    // MARK: - Poll Section
    
    @ViewBuilder
    private var pollSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            HStack {
                Text(MoroL10n.Compose.pollTitle)
                    .font(theme.typography.subtitle)
                Spacer()
                Button(action: {
                    withAnimation(AnimationTokens.easing.springSoft) {
                        viewModel.isPollActive = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            
            ForEach(Array(viewModel.pollOptions.enumerated()), id: \.offset) { index, option in
                TextField(MoroL10n.Compose.pollOptionPlaceholder(index + 1), text: Binding(
                    get: { viewModel.pollOptions[index] },
                    set: { viewModel.pollOptions[index] = $0 }
                ))
                .textFieldStyle(.plain)
                .padding(theme.spacing.m)
                .background(theme.colors.surfaceSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            if viewModel.pollOptions.count < 4 {
                Button(action: {
                    withAnimation(AnimationTokens.easing.springSoft) {
                        viewModel.pollOptions.append("")
                    }
                }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text(MoroL10n.Compose.pollAddOption)
                    }
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.primary500)
                }
            }
            
            Toggle(MoroL10n.Compose.pollAllowMultiple, isOn: $viewModel.pollMultiple)
                .font(theme.typography.body)
                .moroSettingsSwitchStyle()
            
            Divider()
            
            // Poll expiration time
            VStack(alignment: .leading, spacing: theme.spacing.s) {
                Text(MoroL10n.Compose.pollDuration)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                
                Menu {
                    ForEach(PollExpirationOption.allCases, id: \.self) { option in
                        Button(action: {
                            viewModel.pollExpiresIn = option.seconds
                        }) {
                            HStack {
                                Text(option.displayName)
                                if viewModel.pollExpiresIn == option.seconds {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(PollExpirationOption(seconds: viewModel.pollExpiresIn)?.displayName ?? MoroL10n.Compose.pollDurationFallback)
                            .foregroundStyle(theme.colors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    .padding(theme.spacing.m)
                    .background(theme.colors.surfaceSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(theme.spacing.m)
        .background(theme.colors.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Bottom Section
    
    @ViewBuilder
    private var bottomSection: some View {
        VStack(spacing: 0) {
            Divider()
            publishValidationBanner
            composeToolbar
        }
        .background(theme.colors.background)
    }

    @ViewBuilder
    private func configurationChip(
        icon: String,
        title: String,
        isActive: Bool
    ) -> some View {
        let color = isActive ? theme.colors.primary500 : theme.colors.textSecondary
        HStack(spacing: 6) {
            Image(systemName: icon)
                .moroScaledFont(size: 11, weight: .semibold)
            Text(title)
                .font(theme.typography.caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill((isActive ? color : theme.colors.surfaceSubtle).opacity(isActive ? 0.12 : 1))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke((isActive ? color.opacity(0.24) : theme.colors.borderSubtle), lineWidth: 1)
        )
        .frame(minHeight: MoroUtilityButtonMetrics.hitTargetSize)
    }

    @ViewBuilder
    private var composeToolbar: some View {
        HStack(spacing: usesCompactReplyComposerLayout ? theme.spacing.s : theme.spacing.m) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing.s) {
                    Menu {
                        Button(action: {
                            destination = .photoLibrary
                        }) {
                            HStack(spacing: theme.spacing.s) {
                                Image(systemName: "photo.on.rectangle")
                                    .moroScaledFont(size: 14)
                                    .frame(width: 16)
                                Text(MoroL10n.Compose.mediaPhotoLibrary)
                                    .font(theme.typography.caption)
                            }
                        }

                        Button(action: {
                            // iPad and the Simulator can be camera-less; presenting
                            // .camera anyway raises an exception.
                            guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
                            destination = .camera
                        }) {
                            HStack(spacing: theme.spacing.s) {
                                Image(systemName: "camera")
                                    .moroScaledFont(size: 14)
                                    .frame(width: 16)
                                Text(MoroL10n.Compose.mediaTakePhotoOrVideo)
                                    .font(theme.typography.caption)
                            }
                        }

                        Button(action: {
                            destination = .fileImporter
                        }) {
                            HStack(spacing: theme.spacing.s) {
                                Image(systemName: "folder")
                                    .moroScaledFont(size: 14)
                                    .frame(width: 16)
                                Text(MoroL10n.Compose.mediaBrowseFiles)
                                    .font(theme.typography.caption)
                            }
                        }
                    } label: {
                        toolbarIcon(
                            symbol: "photo",
                            isActive: false,
                            isDisabled: viewModel.isPollActive || !viewModel.canAddMedia
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(viewModel.isPollActive || !viewModel.canAddMedia)
                    .accessibilityLabel(Text(MoroL10n.Compose.toolbarMedia))
                    .accessibilityIdentifier("compose.mediaMenu")

                    Button(action: {
                        toggleEmojiPicker()
                    }) {
                        toolbarIcon(
                            symbol: inputMode.showsEmojiPicker ? "keyboard" : "face.smiling",
                            isActive: inputMode.showsEmojiPicker,
                            isDisabled: false
                        )
                    }
                    .accessibilityIdentifier("compose.emojiToggle")
                    .accessibilityLabel(Text(MoroL10n.Compose.toolbarEmoji))
                    .accessibilityAddTraits(inputMode.showsEmojiPicker ? [.isSelected] : [])

                    Button(action: {
                        withAnimation(AnimationTokens.easing.springSoft) {
                            viewModel.isContentWarningActive.toggle()
                        }
                    }) {
                        toolbarIcon(
                            symbol: viewModel.isContentWarningActive ? "exclamationmark.triangle.fill" : "exclamationmark.triangle",
                            isActive: viewModel.isContentWarningActive,
                            isDisabled: false,
                            activeColor: theme.colors.error
                        )
                    }
                    .accessibilityIdentifier("compose.contentWarningToggle")
                    .accessibilityLabel(Text(MoroL10n.Compose.toolbarContentWarning))
                    .accessibilityAddTraits(viewModel.isContentWarningActive ? [.isSelected] : [])

                    if supportsPollConfiguration {
                        Button(action: {
                            if !viewModel.isPollActive && !viewModel.mediaAttachments.isEmpty {
                                AppFeedbackCenter.shared.showInfo(MoroL10n.Compose.toastPollMediaConflict)
                                return
                            }
                            withAnimation(AnimationTokens.easing.springSoft) {
                                isExpandedEditor = false
                                viewModel.isPollActive.toggle()
                            }
                        }) {
                            toolbarIcon(
                                symbol: viewModel.isPollActive ? "chart.bar.fill" : "chart.bar",
                                isActive: viewModel.isPollActive,
                                isDisabled: false
                            )
                        }
                        .accessibilityIdentifier("compose.pollToggle")
                        .accessibilityLabel(Text(MoroL10n.Compose.toolbarPoll))
                        .accessibilityAddTraits(viewModel.isPollActive ? [.isSelected] : [])
                    }

                    Button {
                        openDrafts()
                    } label: {
                        toolbarIcon(
                            symbol: "doc.text",
                            isActive: false,
                            isDisabled: false
                        )
                    }
                    .padding(.leading, theme.spacing.xs)
                    .accessibilityLabel(Text(MoroL10n.Compose.toolbarDrafts))
                    .accessibilityIdentifier("compose.destination.drafts")

                    if supportsScheduling, viewModel.isSchedulingEnabled {
                        Button {
                            openSchedulePicker()
                        } label: {
                            configurationChip(
                                icon: "calendar.badge.clock",
                                title: scheduledPublishSummary(for: viewModel.scheduledAt),
                                isActive: true
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if supportsLanguageSelection {
                        Menu {
                            languageQuickMenuContent
                        } label: {
                            toolbarLanguageControl
                        }
                        .menuStyle(.borderlessButton)
                        .accessibilityLabel(Text(MoroL10n.Compose.toolbarLanguage))
                        .accessibilityValue(toolbarLanguageBadgeText ?? "")
                        .accessibilityIdentifier("compose.languageMenu")
                    }

                }
            }
            inlineCharacterCounter
        }
        .padding(.horizontal, theme.spacing.m)
        .padding(.vertical, usesCompactReplyComposerLayout ? theme.spacing.xs : theme.spacing.s)
        // Keep fixed-size toolbar chrome readable without allowing scaled SF Symbols
        // to overflow their 44pt controls. The editor above still receives the
        // user's full Dynamic Type preference.
        .dynamicTypeSize(.xSmall ... .xxxLarge)
    }

    @ViewBuilder
    private var toolbarLanguageControl: some View {
        if let languageBadge = toolbarLanguageBadgeText {
            toolbarBadge(
                title: languageBadge,
                isActive: isExplicitLanguageSelection
            )
        } else {
            toolbarIcon(
                symbol: "character.bubble",
                isActive: false,
                isDisabled: false
            )
        }
    }

    @ViewBuilder
    private func toolbarBadge(title: String, isActive: Bool) -> some View {
        let color = isActive ? theme.colors.primary500 : theme.colors.textSecondary
        Text(title)
            .moroScaledFont(size: 11, weight: .bold)
            .monospaced()
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill((isActive ? color : theme.colors.surfaceSubtle).opacity(isActive ? 0.12 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.colors.borderSubtle, lineWidth: 1)
            )
            .frame(minWidth: MoroUtilityButtonMetrics.hitTargetSize, minHeight: MoroUtilityButtonMetrics.hitTargetSize)
    }

    @ViewBuilder
    private var audienceMenuContent: some View {
        Section(MoroL10n.Compose.optionVisibility) {
            audienceMenuButton(title: MoroL10n.Compose.visibilityPublic, isSelected: viewModel.visibility == .public) {
                viewModel.visibility = .public
            }
            audienceMenuButton(title: MoroL10n.Compose.visibilityUnlisted, isSelected: viewModel.visibility == .unlisted) {
                viewModel.visibility = .unlisted
            }
            audienceMenuButton(title: MoroL10n.Compose.visibilityFollowersOnly, isSelected: viewModel.visibility == .followers) {
                viewModel.visibility = .followers
            }
            audienceMenuButton(title: MoroL10n.Compose.visibilityMentionedOnly, isSelected: viewModel.visibility == .direct) {
                viewModel.visibility = .direct
            }
        }

        if showsQuotePolicyOption {
            Section(MoroL10n.Compose.optionQuote) {
                audienceMenuButton(title: MoroL10n.Compose.quotePolicyAnyone, isSelected: viewModel.quotePolicy == .anyone) {
                    viewModel.quotePolicy = .anyone
                }
                audienceMenuButton(title: MoroL10n.Compose.quotePolicyFollowers, isSelected: viewModel.quotePolicy == .followers) {
                    viewModel.quotePolicy = .followers
                }
                audienceMenuButton(title: MoroL10n.Compose.quotePolicySelfOnly, isSelected: viewModel.quotePolicy == .none) {
                    viewModel.quotePolicy = .none
                }
            }
        }
    }

    @ViewBuilder
    private func audienceMenuButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    @ViewBuilder
    private var languageQuickMenuContent: some View {
        let defaultTitle = PostLanguageCatalog.defaultOptionTitle(
            for: settings.defaultPostLanguageBehavior
        )
        let explicitCode = PostLanguageCatalog.canonicalLanguageCode(for: viewModel.selectedLanguageCode)
        let defaultCode = PostLanguageCatalog.canonicalLanguageCode(for: settings.effectiveDefaultPostLanguageCode)

        Section(MoroL10n.Compose.langCurrentDefault) {
            audienceMenuButton(
                title: defaultTitle,
                isSelected: viewModel.selectedLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                viewModel.selectedLanguageCode = ""
            }
        }

        if !explicitCode.isEmpty && explicitCode != defaultCode && !recentLanguageOptions.contains(explicitCode) {
            Section(MoroL10n.Compose.langCurrentSelection) {
                audienceMenuButton(
                    title: PostLanguageCatalog.displayName(for: explicitCode),
                    isSelected: true
                ) {
                    viewModel.selectedLanguageCode = explicitCode
                }
            }
        }

        if !recentLanguageOptions.isEmpty {
            Section(MoroL10n.Compose.langRecentlyUsed) {
                ForEach(recentLanguageOptions, id: \.self) { code in
                    audienceMenuButton(
                        title: PostLanguageCatalog.displayName(for: code),
                        isSelected: PostLanguageCatalog.canonicalLanguageCode(for: viewModel.selectedLanguageCode) == code
                    ) {
                        viewModel.selectedLanguageCode = code
                    }
                }
            }
        }

        Section(MoroL10n.Compose.langMore) {
            Button(MoroL10n.Compose.langMoreLanguages) {
                destination = .language
            }
        }
    }

    @ViewBuilder
    private var schedulePickerSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: theme.spacing.l) {
                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    Text(MoroL10n.Compose.scheduleTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.colors.textPrimary)

                    Text(viewModel.isSchedulingEnabled ? scheduledPublishSummary(for: pendingScheduledDate) : MoroL10n.Compose.schedulePublishNow)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textSecondary)
                }

                DatePicker(
                    MoroL10n.Compose.optionScheduleDate,
                    selection: $pendingScheduledDate,
                    in: viewModel.minimumScheduledDate...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .tint(theme.colors.primary500)

                Text(MoroL10n.Compose.minimumScheduleHint)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)

                Spacer(minLength: 0)

                VStack(spacing: theme.spacing.s) {
                    Button {
                        applyScheduledDate()
                    } label: {
                        Text(MoroL10n.Compose.scheduleConfirm)
                            .font(theme.typography.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.colors.primaryForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, theme.spacing.m)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(theme.colors.primary500)
                            )
                    }
                    .buttonStyle(.plain)

                    if viewModel.isSchedulingEnabled {
                        Button {
                            clearScheduledDate()
                        } label: {
                            Text(MoroL10n.Compose.scheduleClear)
                                .font(theme.typography.body)
                                .foregroundStyle(theme.colors.error)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, theme.spacing.m)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            destination = nil
                        } label: {
                            Text(MoroL10n.Common.cancel)
                                .font(theme.typography.body)
                                .foregroundStyle(theme.colors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, theme.spacing.m)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("compose.schedule.cancel")
                    }
                }
            }
            .padding(theme.spacing.l)
            .background(theme.colors.background)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func toolbarIcon(
        symbol: String,
        isActive: Bool,
        isDisabled: Bool,
        activeColor: Color? = nil
    ) -> some View {
        let color =
            isDisabled
            ? theme.colors.textTertiary
            : (isActive ? (activeColor ?? theme.colors.primary500) : theme.colors.textSecondary)

        MoroUtilityIconSurface(
            systemImage: symbol,
            isActive: isActive,
            isDisabled: isDisabled,
            activeColor: activeColor,
            inactiveColor: color
        )
    }

    private var visibilityOptionLabel: String {
        switch viewModel.visibility {
        case .public:
            return MoroL10n.Compose.visibilityPublic
        case .unlisted:
            return MoroL10n.Compose.visibilityUnlisted
        case .followers:
            return MoroL10n.Compose.visibilityFollowersOnly
        case .direct:
            return MoroL10n.Compose.visibilityMentionedOnly
        case ._other(let value):
            return value
        }
    }

    private var inlineCharacterCounterText: String {
        "\(rawRemainingCharacterCount)"
    }

    private var rawRemainingCharacterCount: Int {
        viewModel.maxCharacters - viewModel.characterCount
    }

    private var inlineCharacterCounterColor: Color {
        if rawRemainingCharacterCount < 0 {
            return theme.colors.error
        }
        if rawRemainingCharacterCount <= 20 {
            return theme.colors.warning
        }
        return theme.colors.textSecondary
    }

    private var supportsScheduling: Bool {
        guard ComposeFeatureAvailability.scheduledPublishing else { return false }
        switch viewModel.context {
        case .edit:
            return false
        case .newPost, .reply, .quote:
            return true
        }
    }

    private var supportsPollConfiguration: Bool {
        switch viewModel.context {
        case .edit:
            return false
        case .newPost, .reply, .quote:
            return true
        }
    }

    private var supportsLanguageSelection: Bool {
        switch viewModel.context {
        case .edit:
            return false
        case .newPost, .reply, .quote:
            return true
        }
    }

    private var supportsAudienceConfiguration: Bool {
        switch viewModel.context {
        case .edit:
            return false
        case .newPost, .reply, .quote:
            return true
        }
    }

    private var showsQuotePolicyOption: Bool {
        switch viewModel.context {
        case .newPost, .reply, .quote:
            return viewModel.visibility == .public || viewModel.visibility == .unlisted
        case .edit:
            return false
        }
    }

    private var usesCompactReplyComposerLayout: Bool {
        switch viewModel.context {
        case .reply, .quote:
            return true
        case .newPost, .edit:
            return false
        }
    }

    private var fixedTextInputHeight: CGFloat {
        switch viewModel.context {
        case .reply, .quote:
            return 132
        case .newPost:
            return 190
        case .edit:
            return 210
        }
    }

    private var primaryActionTitle: String {
        viewModel.isScheduledPublishingActive ? MoroL10n.Compose.actionSchedulePublish : MoroL10n.Compose.actionPublish
    }

    private var publishingButtonText: String {
        viewModel.isScheduledPublishingActive ? MoroL10n.Compose.actionScheduling : MoroL10n.Compose.actionPublishing
    }

    private var toolbarLanguageBadgeText: String? {
        let currentCode = viewModel.selectedLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentCode.isEmpty {
            return compactLanguageBadge(for: currentCode)
        }

        let defaultCode = settings.effectiveDefaultPostLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !defaultCode.isEmpty else { return nil }
        return compactLanguageBadge(for: defaultCode)
    }

    private var recentLanguageOptions: [String] {
        let selectedCode = PostLanguageCatalog.canonicalLanguageCode(for: viewModel.selectedLanguageCode)
        let defaultCode = PostLanguageCatalog.canonicalLanguageCode(for: settings.effectiveDefaultPostLanguageCode)
        return settings.recentPostLanguageCodes.filter { code in
            !code.isEmpty && code != defaultCode && code != selectedCode
        }
    }

    private var isExplicitLanguageSelection: Bool {
        !viewModel.selectedLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var audienceConfigurationSummary: String {
        if showsQuotePolicyOption {
            return "\(visibilityOptionLabel) · \(quotePolicyAudienceLabel)"
        }
        return visibilityOptionLabel
    }

    private var isAudienceConfigurationCustomized: Bool {
        if showsQuotePolicyOption {
            return isVisibilityCustomized || isQuotePolicyCustomized
        }
        return isVisibilityCustomized
    }

    private var isVisibilityCustomized: Bool {
        viewModel.visibility != defaultVisibilityBaseline
    }

    private var isQuotePolicyCustomized: Bool {
        showsQuotePolicyOption && viewModel.quotePolicy != .anyone
    }

    private var visibilityIcon: String {
        switch viewModel.visibility {
        case .public:
            return "globe"
        case .unlisted:
            return "lock.open"
        case .followers:
            return "lock"
        case .direct:
            return "at"
        case ._other:
            return "questionmark.circle"
        }
    }

    private var defaultVisibilityBaseline: MastodonVisibility {
        switch viewModel.context {
        case .reply(let status):
            if let rawVisibility = status?.displayStatus.visibility {
                return MastodonVisibility(rawValue: rawVisibility) ?? appDefaultVisibility
            }
            return appDefaultVisibility
        case .newPost, .quote:
            return appDefaultVisibility
        case .edit:
            return viewModel.visibility
        }
    }

    private var appDefaultVisibility: MastodonVisibility {
        switch settings.defaultPostVisibility {
        case .public:
            return .public
        case .unlisted:
            return .unlisted
        case .followersOnly:
            return .followers
        case .mentionedOnly:
            return .direct
        }
    }

    private var quotePolicyAudienceLabel: String {
        switch viewModel.quotePolicy {
        case .anyone:
            return MoroL10n.Compose.quotePolicyLabelAllow
        case .followers:
            return MoroL10n.Compose.quotePolicyLabelFollowers
        case .none:
            return MoroL10n.Compose.quotePolicyLabelNone
        }
    }

    private func compactLanguageBadge(for code: String) -> String {
        let canonical = PostLanguageCatalog.canonicalLanguageCode(for: code)
        let compact = canonical.split(separator: "-").first.map(String.init) ?? canonical
        return compact.uppercased()
    }
    
    // Computed property to extract account host domain
    private var accountHost: String? {
        guard let account = appState.currentAccount,
              let urlString = account.url,
              let url = URL(string: urlString) else {
            return nil
        }
        return url.host
    }

    private func insertEmoji(shortcode: String) {
        let result = ComposeTextEditing.insertingEmoji(
            shortcode: shortcode,
            into: viewModel.content,
            selection: textSelection
        )
        viewModel.content = result.text
        textSelection = result.selection
        textSelectionCommand = ComposeTextSelectionCommand(
            range: result.selection,
            scrollsToSelection: true
        )
    }

    private var autocompleteToken: ComposeAutocompleteToken? {
        guard inputMode == .keyboard, destination == nil, viewModel.isEditingSourceReady else { return nil }
        let token = ComposeAutocompleteToken.active(
            in: viewModel.content, selection: textSelection, isComposing: hasMarkedText
        )
        // Selecting a suggestion before existing whitespace or punctuation keeps that
        // suffix intact, so the caret can still sit at a token boundary. Close its panel.
        return token == completedAutocompleteToken ? nil : token
    }

    private func insertSuggestion(_ suggestion: ComposeSuggestion, for token: ComposeAutocompleteToken) {
        guard !hasMarkedText, autocompleteToken == token,
              let result = token.inserting(suggestion.completion, into: viewModel.content, selection: textSelection)
        else { return }
        viewModel.content = result.text
        textSelection = result.selection
        textSelectionCommand = ComposeTextSelectionCommand(range: result.selection, scrollsToSelection: true)
        completedAutocompleteToken = ComposeAutocompleteToken.active(in: result.text, selection: result.selection)
    }
    
    private func loadEmojiViewModelIfNeeded() {
        guard let host = accountHost else { return }
        let fetchedViewModel = EmojiService.shared.dequeueCustomEmojiViewModel(for: host, apiClient: viewModel.apiClient)
        if emojiViewModel?.domain != host || emojiViewModel == nil {
            emojiViewModel = fetchedViewModel
        }
    }
    
    private func openSchedulePicker() {
        if viewModel.isSchedulingEnabled {
            pendingScheduledDate = max(viewModel.scheduledAt, viewModel.minimumScheduledDate)
        } else {
            pendingScheduledDate = ComposeViewModel.defaultScheduledDate()
            if pendingScheduledDate < viewModel.minimumScheduledDate {
                pendingScheduledDate = ComposeViewModel.defaultScheduledDate(
                    from: viewModel.minimumScheduledDate
                )
            }
        }
        destination = .schedule
    }

    private func applyScheduledDate() {
        viewModel.isSchedulingEnabled = true
        viewModel.scheduledAt = pendingScheduledDate
        destination = nil
    }

    private func clearScheduledDate() {
        viewModel.isSchedulingEnabled = false
        pendingScheduledDate = ComposeViewModel.defaultScheduledDate()
        destination = nil
    }

    private func openDrafts() {
        if let blocker = viewModel.draftPersistenceBlocker {
            AppFeedbackCenter.shared.showError(blocker)
            return
        }

        if viewModel.hasDraftableContent {
            let draft = viewModel.makeDraft(category: .auto)
            guard draftStore.save(draft) else {
                AppFeedbackCenter.shared.showError(MoroL10n.ComposeDrafts.saveFailed)
                return
            }
        }

        destination = .drafts
    }

    private func autosaveDraftIfNeeded() {
        guard viewModel.hasDraftableContent else { return }
        let draft = viewModel.makeDraft(category: .auto)
        guard draft.payload.hasSubstantivePayload else { return }
        if !draftStore.save(draft) {
            AppLogger.error("Failed to autosave compose draft while entering background")
        }
    }

    private func saveDraftAndDismiss() {
        if let blocker = viewModel.draftPersistenceBlocker {
            AppFeedbackCenter.shared.showError(blocker)
            return
        }

        let draft = viewModel.makeDraft(category: .manual)
        guard draftStore.save(draft) else {
            AppFeedbackCenter.shared.showError(MoroL10n.ComposeDrafts.saveFailed)
            return
        }

        AppFeedbackCenter.shared.showSuccess(MoroL10n.ComposeDrafts.saved)
        dismissComposer()
    }

    private func discardDraftAndDismiss() {
        if let draftID = viewModel.activeDraftID {
            _ = draftStore.removeDraft(id: draftID)
        }
        viewModel.clearActiveDraftReference()
        dismissComposer()
    }
    
    // MARK: - Actions
    
    private func handlePhotoSelections(
        _ items: [PhotosPickerItem],
        reservationIDs: [String]
    ) async {
        let imports = Array(zip(items, reservationIDs))
        let viewModel = viewModel
        var firstFailure: ComposeViewModel.MediaImportOutcome?

        // Loading several ProRAW/full-resolution assets as Data at once can create a large
        // transient memory spike. Process at most two selections concurrently while the
        // reservation placeholders keep all four chosen positions visible and stable.
        for batchStart in stride(
            from: 0,
            to: imports.count,
            by: ComposeMediaSelectionPolicy.maximumConcurrentImports
        ) {
            let batchEnd = min(
                batchStart + ComposeMediaSelectionPolicy.maximumConcurrentImports,
                imports.count
            )
            let batch = imports[batchStart..<batchEnd]

            await withTaskGroup(of: ComposeViewModel.MediaImportOutcome.self) { group in
                for (item, reservationID) in batch {
                    group.addTask {
                        do {
                            guard let data = try await item.loadTransferable(type: Data.self) else {
                                await viewModel.cancelPhotoImportReservation(id: reservationID)
                                return .failed(.imageProcessing)
                            }
                            return await viewModel.importPhotoData(
                                data,
                                reservationID: reservationID
                            )
                        } catch is CancellationError {
                            await viewModel.cancelPhotoImportReservation(id: reservationID)
                            return .cancelled
                        } catch {
                            await viewModel.cancelPhotoImportReservation(id: reservationID)
                            return .failed(.imageProcessing)
                        }
                    }
                }

                for await outcome in group {
                    if case .failed = outcome, firstFailure == nil {
                        firstFailure = outcome
                    }
                }
            }
        }

        if let firstFailure {
            showMediaImportFeedback(firstFailure)
        }
    }
    
    private func handleImageSelection(_ image: UIImage) async {
        showMediaImportFeedback(await viewModel.importCameraImage(image))
    }
    
    private func retryMediaUpload(attachmentID: String) async {
        showMediaImportFeedback(
            await viewModel.retryMediaUpload(attachmentID: attachmentID)
        )
    }

    private func importSharedAttachments(
        from sharedImport: SharedComposeAttachmentImportPayload
    ) async {
        let outcome = await viewModel.importSharedAttachments(from: sharedImport, draftStore: draftStore)
        if outcome == .complete || outcome == .partial {
            let draft = viewModel.makeDraft(category: .manual)
            if !draftStore.save(draft) {
                AppFeedbackCenter.shared.showError(MoroL10n.ComposeDrafts.saveFailed)
            }
        }

        switch outcome {
        case .complete:
            AppFeedbackCenter.shared.showInfo(MoroL10n.Compose.toastImportComplete)
        case .partial:
            AppFeedbackCenter.shared.showInfo(MoroL10n.Compose.toastImportPartial)
        case .failed:
            AppFeedbackCenter.shared.showError(MoroL10n.Compose.toastImportFailed)
        case .cancelled:
            break
        }
    }

    private func scheduledPublishSummary(for date: Date) -> String {
        MoroL10n.Compose.scheduleSummary(scheduledDateText(date))
    }

    private func scheduledDateText(_ date: Date) -> String {
        date.formatted(.dateTime.month().day().hour().minute())
    }
    
    private func handleFileSelection(_ url: URL) async {
        showMediaImportFeedback(await viewModel.importFile(at: url))
    }

    private func showMediaImportFeedback(_ outcome: ComposeViewModel.MediaImportOutcome) {
        guard case .failed(let failure) = outcome else { return }
        switch failure {
        case .imageProcessing:
            AppFeedbackCenter.shared.showError(MoroL10n.Compose.toastImageProcessFailed)
        case .fileAccess:
            AppFeedbackCenter.shared.showError(MoroL10n.Compose.toastFileAccessFailed)
        case .fileRead:
            AppFeedbackCenter.shared.showError(MoroL10n.Compose.toastFileReadFailed)
        case .upload:
            AppFeedbackCenter.shared.showError(MoroL10n.Compose.toastMediaUploadFailed)
        case .retryUnavailable:
            AppFeedbackCenter.shared.showInfo(MoroL10n.Compose.toastMediaCannotRetry)
        }
    }
    
    private func publish() async {
        // Check if we need to ask before posting without alt text
        if AppSettings.shared.askBeforePostingWithoutAltText {
            let hasMediaWithoutAltText = viewModel.mediaAttachments.contains { attachment in
                (attachment.type == "image" || attachment.type == "video") && 
                (attachment.description?.isEmpty ?? true)
            }
            
            if hasMediaWithoutAltText {
                destination = .missingAltTextConfirmation
                return
            }
        }
        
        await performPublish()
    }
    
    private func performPublish() async {
        guard !viewModel.isPublishing, !isCompletingPublish else { return }
        publishFailureMessage = nil
        publishDraftSaved = nil
        AppLogger.debug("[Compose] Publish started")
        do {
            let result = try await viewModel.publish()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isCompletingPublish = true
            // The presentation owner clears its binding before any refresh callback.
            // Keep the progress indicator active until the composer has disappeared.
            AppLogger.debug("[Compose] Publish succeeded; requesting dismissal")
            dismissComposer()
            switch result {
            case .posted(let status):
                AppFeedbackCenter.shared.showSuccess(MoroL10n.Compose.successPosted)
                onPublish?(status)
            case .scheduled(let scheduledStatus):
                AppFeedbackCenter.shared.showSuccess(
                    MoroL10n.Compose.scheduleSuccess(
                        scheduledDateText(scheduledStatus.scheduledAt)
                    )
                )
            }
            if let draftID = viewModel.activeDraftID {
                _ = draftStore.removeDraft(id: draftID)
                viewModel.clearActiveDraftReference()
            }
        } catch {
            publishFailureMessage = ComposePublishFailure.message(for: error)
            if viewModel.hasDraftableContent {
                let draft = viewModel.makeDraft(category: .auto)
                publishDraftSaved = draftStore.save(draft)
            }
            AppLogger.error("Failed to publish: \(error)")
        }
    }

    private func dismissComposer() {
        inputMode = .idle
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    @ViewBuilder private var publishFailureNotice: some View {
        if let publishFailureMessage {
            HStack(alignment: .top, spacing: theme.spacing.s) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(theme.colors.error)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(publishFailureMessage)
                        .foregroundStyle(theme.colors.textPrimary)
                    if let publishDraftSaved {
                        Text(publishDraftSaved ? MoroL10n.ComposeDrafts.saved : MoroL10n.ComposeDrafts.saveFailed)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .font(theme.typography.caption)
            .padding(theme.spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.surfaceSubtle)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("compose.publishError")
        }
    }
    
}

// MARK: - Camera View

struct CameraView: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        // Stills only — video recording would also require NSMicrophoneUsageDescription.
        // Users can still attach videos via the Photos picker (PHPicker).
        picker.mediaTypes = ["public.image"]
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
        nonisolated deinit {}

        let onImageCaptured: (UIImage) -> Void
        
        init(onImageCaptured: @escaping (UIImage) -> Void) {
            self.onImageCaptured = onImageCaptured
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImageCaptured(image)
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

private struct ComposeTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    @Binding var selectionCommand: ComposeTextSelectionCommand?
    @Binding var isFocused: Bool
    @Binding var hasMarkedText: Bool

    let isExpanded: Bool
    let minimumHeight: CGFloat
    let inputMode: ComposeInputMode
    let emojiPickerHeight: CGFloat
    let emojiViewModel: CustomEmojiViewModel?
    let hasEmojiHost: Bool
    let isSceneActive: Bool
    let playAnimations: Bool
    let theme: MoroTheme
    let textColor: UIColor
    let placeholder: String
    let placeholderColor: UIColor
    let onEmojiSelected: (String) -> Void

    func makeUIView(context: Context) -> ComposeUIKitTextView {
        let textView = ComposeUIKitTextView()
        textView.backgroundColor = .clear
        textView.isOpaque = false
        textView.textColor = textColor
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = isExpanded
        textView.alwaysBounceVertical = isExpanded
        textView.showsVerticalScrollIndicator = isExpanded
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 12, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        textView.setContentHuggingPriority(.defaultLow, for: .vertical)
        textView.accessibilityIdentifier = "compose.textInput"
        textView.text = text
        textView.updatePlaceholder(text: placeholder, color: placeholderColor)
        textView.selectedRange = clampedRange(selection, in: textView.textStorage.length)
        context.coordinator.updateHighlighting(textView)
        textView.delegate = context.coordinator
        textView.updateFocusRequest(isFocused)
        return textView
    }

    func updateUIView(_ textView: ComposeUIKitTextView, context: Context) {
        context.coordinator.parent = self
        textView.isScrollEnabled = isExpanded
        textView.alwaysBounceVertical = isExpanded
        textView.showsVerticalScrollIndicator = isExpanded
        if textView.text != text, textView.markedTextRange == nil {
            let preservedSelection = clampedRange(
                textView.selectedRange,
                in: (text as NSString).length
            )
            context.coordinator.isUpdatingFromSwiftUI = true
            textView.text = text
            textView.selectedRange = preservedSelection
            context.coordinator.isUpdatingFromSwiftUI = false
            textView.requestSelectionReveal()
        }
        textView.updatePlaceholder(text: placeholder, color: placeholderColor)

        if let command = selectionCommand,
           command.id != context.coordinator.lastAppliedSelectionCommandID,
           textView.markedTextRange == nil {
            let desiredSelection = clampedRange(command.range, in: textView.textStorage.length)
            context.coordinator.isUpdatingFromSwiftUI = true
            textView.selectedRange = desiredSelection
            context.coordinator.isUpdatingFromSwiftUI = false
            context.coordinator.lastAppliedSelectionCommandID = command.id
            context.coordinator.finishSelectionCommand(command.id)

            if command.scrollsToSelection,
               textView.isFirstResponder,
               !textView.isDragging {
                textView.requestSelectionReveal()
            }
        }

        context.coordinator.updateHighlighting(textView)
        textView.updateInputMode(
            inputMode,
            emojiPickerHeight: emojiPickerHeight,
            emojiRootView: {
                AnyView(
                    ComposeEmojiInputSurface(
                        emojiViewModel: emojiViewModel,
                        hasEmojiHost: hasEmojiHost,
                        isSceneActive: isSceneActive,
                        playAnimations: playAnimations,
                        onEmojiSelected: { [weak coordinator = context.coordinator] shortcode in
                            coordinator?.parent.onEmojiSelected(shortcode)
                        }
                    )
                    .environment(\.moroTheme, theme)
                )
            }
        )

        textView.updateFocusRequest(isFocused)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ComposeUIKitTextView, context: Context) -> CGSize? {
        guard !isExpanded, let width = proposal.width, width > 0 else { return nil }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(minimumHeight, ceil(fitted.height)))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func clampedRange(_ range: NSRange, in length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        let remaining = max(length - location, 0)
        let rangeLength = min(max(range.length, 0), remaining)
        return NSRange(location: location, length: rangeLength)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
        nonisolated deinit {}

        var parent: ComposeTextViewRepresentable
        var isUpdatingFromSwiftUI = false
        var lastAppliedSelectionCommandID: UUID?

        init(parent: ComposeTextViewRepresentable) {
            self.parent = parent
        }

        func finishSelectionCommand(_ id: UUID) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.parent.selectionCommand?.id == id else { return }
                self.parent.selectionCommand = nil
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            updateHighlighting(textView)
            updateSelectionIfNeeded(textView.selectedRange)
            updateFocusIfNeeded(true)
            (textView as? ComposeUIKitTextView)?.requestSelectionReveal()
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdatingFromSwiftUI else { return }
            updateMarkedText(textView)
            updateHighlighting(textView)
            if parent.text != textView.text {
                parent.text = textView.text
            }
            updateSelectionIfNeeded(textView.selectedRange)
            textView.invalidateIntrinsicContentSize()
            (textView as? ComposeUIKitTextView)?.requestSelectionReveal()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdatingFromSwiftUI else { return }
            updateMarkedText(textView)
            updateHighlighting(textView)
            updateSelectionIfNeeded(textView.selectedRange)
            (textView as? ComposeUIKitTextView)?.requestSelectionReveal()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            updateHighlighting(textView)
            updateSelectionIfNeeded(textView.selectedRange)
            updateFocusIfNeeded(false)
            updateMarkedText(textView)
        }

        func updateHighlighting(_ textView: UITextView) {
            guard !isUpdatingFromSwiftUI else { return }
            isUpdatingFromSwiftUI = true
            defer { isUpdatingFromSwiftUI = false }
            ComposeTextHighlighter.apply(
                to: textView,
                textColor: parent.textColor,
                tokenColor: UIColor(parent.theme.colors.contentLink)
            )
        }

        private func updateMarkedText(_ textView: UITextView) {
            let isComposing = textView.markedTextRange != nil
            if parent.hasMarkedText != isComposing { parent.hasMarkedText = isComposing }
        }

        private func updateSelectionIfNeeded(_ selection: NSRange) {
            guard parent.selection != selection else { return }
            parent.selection = selection
        }

        private func updateFocusIfNeeded(_ focused: Bool) {
            guard parent.isFocused != focused else { return }
            parent.isFocused = focused
        }
    }
}

private final class ComposeUIKitTextView: UITextView {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    private var requestsFocus = false
    private var needsSelectionReveal = false
    private var emojiInputView: ComposeEmojiInputView?
    private let placeholderLabel = UILabel()
    private var placeholderNeedsMeasurement = true
    private var placeholderMeasurementWidth: CGFloat = -1
    private var placeholderMeasuredSize: CGSize = .zero

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // The initial focus request can arrive before UIKit attaches the editor.
        // Apply it here once attached; normal resigning still updates ComposeInputMode.
        if window != nil, requestsFocus, !isFirstResponder { becomeFirstResponder() }
    }

    func updateFocusRequest(_ requested: Bool) {
        requestsFocus = requested
        if requested, window != nil, !isFirstResponder { becomeFirstResponder() }
        if !requested, isFirstResponder { resignFirstResponder() }
    }

    func requestSelectionReveal() {
        needsSelectionReveal = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let leftInset = textContainerInset.left + textContainer.lineFragmentPadding
        let rightInset = textContainerInset.right + textContainer.lineFragmentPadding
        let availableWidth = max(bounds.width - leftInset - rightInset, 0)

        if let font, placeholderLabel.font != font {
            placeholderLabel.font = font
            placeholderNeedsMeasurement = true
        }
        if placeholderNeedsMeasurement || abs(placeholderMeasurementWidth - availableWidth) >= 0.5 {
            placeholderMeasuredSize = placeholderLabel.sizeThatFits(
                CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
            )
            placeholderMeasurementWidth = availableWidth
            placeholderNeedsMeasurement = false
        }

        let desiredFrame = CGRect(
            x: leftInset,
            y: textContainerInset.top,
            width: availableWidth,
            height: placeholderMeasuredSize.height
        )
        if placeholderLabel.frame != desiredFrame {
            placeholderLabel.frame = desiredFrame
        }

        if needsSelectionReveal, isFirstResponder, let selectedTextRange {
            needsSelectionReveal = false
            let caret = caretRect(for: selectedTextRange.end).insetBy(dx: 0, dy: -12)
            scrollRectToVisible(caret, animated: false)
        }
    }

    override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        if isScrollEnabled {
            super.scrollRectToVisible(rect, animated: animated)
        } else {
            // A growing editor delegates caret visibility to the page's single scroll view.
            var ancestor = superview
            while let view = ancestor {
                if let scrollView = view as? UIScrollView {
                    scrollView.scrollRectToVisible(convert(rect, to: scrollView), animated: animated)
                    break
                }
                ancestor = view.superview
            }
        }
    }

    private func configure() {
        placeholderLabel.numberOfLines = 0
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.isAccessibilityElement = false
        addSubview(placeholderLabel)
    }

    func updatePlaceholder(text: String, color: UIColor) {
        var needsLayout = false

        if placeholderLabel.text != text {
            placeholderLabel.text = text
            needsLayout = true
        }
        if placeholderLabel.textColor != color {
            placeholderLabel.textColor = color
        }
        if let font, placeholderLabel.font != font {
            placeholderLabel.font = font
            needsLayout = true
        }

        let shouldHidePlaceholder = !self.text.isEmpty
        if placeholderLabel.isHidden != shouldHidePlaceholder {
            placeholderLabel.isHidden = shouldHidePlaceholder
        }
        if accessibilityLabel != text {
            accessibilityLabel = text
        }

        if needsLayout {
            placeholderNeedsMeasurement = true
            setNeedsLayout()
        }
    }

    func updateInputMode(
        _ mode: ComposeInputMode,
        emojiPickerHeight: CGFloat,
        emojiRootView: () -> AnyView
    ) {
        var shouldReloadInputViews = false

        switch mode {
        case .emoji:
            let rootView = emojiRootView()
            let pickerInputView: ComposeEmojiInputView
            if let emojiInputView {
                pickerInputView = emojiInputView
                if pickerInputView.update(
                    rootView: rootView,
                    preferredHeight: emojiPickerHeight
                ) {
                    shouldReloadInputViews = true
                }
            } else {
                let newInputView = ComposeEmojiInputView(
                    rootView: rootView,
                    preferredHeight: emojiPickerHeight
                )
                emojiInputView = newInputView
                pickerInputView = newInputView
            }

            if inputView !== pickerInputView {
                inputView = pickerInputView
                shouldReloadInputViews = true
            }

        case .idle, .keyboard:
            if inputView != nil {
                inputView = nil
                shouldReloadInputViews = true
            }
        }

        if isFirstResponder && shouldReloadInputViews {
            reloadInputViews()
        }
    }

}

private final class ComposeEmojiInputView: UIInputView {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    private let hostingController: UIHostingController<AnyView>
    private var preferredHeight: CGFloat

    init(rootView: AnyView, preferredHeight: CGFloat) {
        self.hostingController = UIHostingController(rootView: rootView)
        self.preferredHeight = preferredHeight
        super.init(
            frame: CGRect(x: 0, y: 0, width: 0, height: preferredHeight),
            inputViewStyle: .keyboard
        )

        allowsSelfSizing = true
        autoresizingMask = [.flexibleWidth]
        backgroundColor = .clear

        let hostedView = hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.backgroundColor = .clear
        addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: preferredHeight)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: preferredHeight)
    }

    @discardableResult
    func update(rootView: AnyView, preferredHeight: CGFloat) -> Bool {
        hostingController.rootView = rootView
        guard self.preferredHeight != preferredHeight else { return false }

        self.preferredHeight = preferredHeight
        frame.size.height = preferredHeight
        invalidateIntrinsicContentSize()
        return true
    }
}

private struct ComposeEmojiInputSurface: View {
    let emojiViewModel: CustomEmojiViewModel?
    let hasEmojiHost: Bool
    let isSceneActive: Bool
    let playAnimations: Bool
    let onEmojiSelected: (String) -> Void

    @Environment(\.moroTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            if let emojiViewModel {
                EmojiPickerContentView(
                    emojiViewModel: emojiViewModel,
                    isSceneActive: isSceneActive,
                    playAnimations: playAnimations,
                    onEmojiSelected: onEmojiSelected
                )
            } else if hasEmojiHost {
                VStack(spacing: theme.spacing.s) {
                    ProgressView()
                    Text(MoroL10n.Compose.emojiLoading)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(MoroL10n.Compose.emojiLoadFailed)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background)
        .accessibilityIdentifier("compose.emojiPicker")
    }
}

// MARK: - Emoji Picker Content View

struct EmojiPickerContentView: View {
    @ObservedObject var emojiViewModel: CustomEmojiViewModel
    let isSceneActive: Bool
    let playAnimations: Bool
    let onEmojiSelected: (String) -> Void
    
    @Environment(\.moroTheme) private var theme
    
    var body: some View {
        VStack(spacing: 0) {
            if !emojiViewModel.emojiGroups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: theme.spacing.s) {
                        ForEach(Array(emojiViewModel.emojiGroups.enumerated()), id: \.element.id) { index, group in
                            Button {
                                emojiViewModel.selectGroup(at: index)
                            } label: {
                                Group {
                                    if let coverEmoji = group.emojis.first {
                                        EmojiPickerThumbnail(
                                            url: coverEmoji.staticURL,
                                            size: 28
                                        )
                                    } else {
                                        Image(systemName: "face.smiling")
                                            .moroScaledFont(size: 18)
                                            .foregroundStyle(theme.colors.textSecondary)
                                    }
                                }
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(
                                            emojiViewModel.selectedGroupIndex == index
                                                ? theme.colors.primary500.opacity(0.12)
                                                : Color.clear
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(
                                            emojiViewModel.selectedGroupIndex == index
                                                ? theme.colors.primary500.opacity(0.28)
                                                : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(group.name))
                            .accessibilityAddTraits(
                                emojiViewModel.selectedGroupIndex == index ? [.isSelected] : []
                            )
                        }
                    }
                    .padding(.horizontal, theme.spacing.m)
                    .padding(.vertical, theme.spacing.xs)
                }
                .background(theme.colors.background)

                Divider()
            }

            ZStack(alignment: .top) {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 50), spacing: theme.spacing.m)
                    ], spacing: theme.spacing.m) {
                        ForEach(emojiViewModel.currentGroupEmojis) { emoji in
                            Button(action: {
                                onEmojiSelected(emoji.shortcode)
                            }) {
                                AnimatedEmojiPickerThumbnail(
                                    animatedURL: emoji.url,
                                    staticURL: emoji.staticURL,
                                    isSceneActive: isSceneActive,
                                    animationsEnabled: playAnimations
                                )
                                    .frame(width: 48, height: 48)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(emoji.id)
                            .accessibilityLabel(Text(":\(emoji.shortcode):"))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(theme.spacing.m)
                }
                .defaultScrollAnchor(.top)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .id(emojiViewModel.selectedGroupIndex)

                if emojiViewModel.loadState == .loading,
                   emojiViewModel.emojiGroups.isEmpty {
                    emojiLoadingState
                } else if emojiViewModel.loadState == .fail,
                          emojiViewModel.emojiGroups.isEmpty {
                    emojiFailureState
                } else if emojiViewModel.loadState == .finish,
                          emojiViewModel.emojiGroups.isEmpty {
                    emojiEmptyState
                }
            }
        }
        .background(theme.colors.background)
    }

    private var emojiLoadingState: some View {
        VStack(spacing: theme.spacing.s) {
            ProgressView()
            Text(MoroL10n.Compose.emojiLoading)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background)
    }

    private var emojiFailureState: some View {
        VStack(spacing: theme.spacing.s) {
            Text(MoroL10n.Compose.emojiLoadFailed)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
            Button(MoroL10n.Compose.retry) {
                emojiViewModel.load()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background)
    }

    private var emojiEmptyState: some View {
        Text(MoroL10n.Emoji.noCustomEmoji)
            .font(theme.typography.caption)
            .foregroundStyle(theme.colors.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.colors.background)
    }
}

private struct EmojiPickerThumbnail: View {
    let url: URL
    let size: CGFloat

    @Environment(\.displayScale) private var displayScale
    @Environment(\.moroTheme) private var theme
    @State private var image: UIImage?

    init(url: URL, size: CGFloat = 40) {
        self.url = url
        self.size = size
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(theme.colors.surfaceSubtle)
                    .overlay {
                        Image(systemName: "face.smiling")
                            .moroScaledFont(size: max(size * 0.32, 10))
                            .foregroundStyle(theme.colors.textTertiary)
                    }
            }
        }
        .frame(width: size, height: size)
        .task(id: "\(url.absoluteString)#\(size)") {
            image = nil
            let loadedImage = await ImageCache.shared.loadThumbnail(
                from: url,
                maxPixelSize: size * displayScale
            )
            guard !Task.isCancelled else { return }
            image = loadedImage
        }
    }
}

private struct AnimatedEmojiPickerThumbnail: View {
    let animatedURL: URL
    let staticURL: URL
    let isSceneActive: Bool
    let animationsEnabled: Bool
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.moroTheme) private var theme
    @State private var isLoaded = false
    @State private var isVisible = false
    @State private var usesStaticFallback = false

    init(
        animatedURL: URL,
        staticURL: URL,
        isSceneActive: Bool,
        animationsEnabled: Bool,
        size: CGFloat = 40
    ) {
        self.animatedURL = animatedURL
        self.staticURL = staticURL
        self.isSceneActive = isSceneActive
        self.animationsEnabled = animationsEnabled
        self.size = size
    }

    private var activeURL: URL? {
        // This view lives inside a standalone UIHostingController used as UITextView.inputView.
        // That host does not reliably inherit SwiftUI's scenePhase environment. Loading must
        // therefore depend only on cell visibility; scene activity controls playback below.
        guard ComposeEmojiAnimationPolicy.shouldLoadImage(isVisible: isVisible) else {
            return nil
        }
        return ComposeEmojiAnimationPolicy.imageURL(
            animatedURL: animatedURL,
            staticURL: staticURL,
            animationsEnabled: animationsEnabled,
            reduceMotion: reduceMotion,
            usesStaticFallback: usesStaticFallback
        )
    }

    private var shouldAnimate: Bool {
        ComposeEmojiAnimationPolicy.shouldAnimate(
            isVisible: isVisible,
            isSceneActive: isSceneActive,
            animationsEnabled: animationsEnabled,
            reduceMotion: reduceMotion,
            usesStaticFallback: usesStaticFallback
        )
    }

    var body: some View {
        ZStack {
            if !isLoaded {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(theme.colors.surfaceSubtle)
                    .overlay {
                        Image(systemName: "face.smiling")
                            .moroScaledFont(size: max(size * 0.32, 10))
                            .foregroundStyle(theme.colors.textTertiary)
                    }
            }

            SDWebRemoteImage(
                url: activeURL,
                thumbnailPixelSize: size * displayScale,
                contentMode: .scaleAspectFit,
                allowsAnimation: shouldAnimate,
                animationLoadingMode: .boundedPreview,
                maximumAnimatedBufferSize: 2 * 1024 * 1024,
                onLoadStateChange: { loaded in
                    isLoaded = loaded
                },
                onLoadFailure: {
                    // A server may advertise a static PNG as its original URL or return an
                    // animation format this OS cannot decode. Never leave the picker blank:
                    // retry once with Mastodon's guaranteed static_url variant.
                    guard ComposeEmojiAnimationPolicy.shouldFallbackAfterLoadFailure(
                        animationsEnabled: animationsEnabled,
                        reduceMotion: reduceMotion,
                        usesStaticFallback: usesStaticFallback
                    ) else { return }
                    usesStaticFallback = true
                }
            )
        }
        .frame(width: size, height: size)
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
        }
        .onChange(of: animatedURL) {
            isLoaded = false
            usesStaticFallback = false
        }
        .onChange(of: animationsEnabled) {
            isLoaded = false
            usesStaticFallback = false
        }
        .accessibilityHidden(true)
    }
}
