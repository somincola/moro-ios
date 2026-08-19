//
//  EditProfileView.swift
//  moro
//
//  Edit profile page for account basic info and media.
//

import SwiftUI
import PhotosUI
import UIKit
import Combine

struct EditProfileView: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @StateObject private var viewModel: EditProfileViewModel
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var headerPickerItem: PhotosPickerItem?
    @State private var attemptedSave = false
    @FocusState private var focusedInput: FocusedInput?

    private enum Metrics {
        static let pagePadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 24
        static let mediaCornerRadius: CGFloat = 8
        static let avatarSize: CGFloat = 78
    }

    private enum FocusedInput: Hashable {
        case displayName
        case bio
        case fieldName(UUID)
        case fieldValue(UUID)
    }

    init(apiClient: MastodonAPI, currentAccount: Account?) {
        _viewModel = StateObject(
            wrappedValue: EditProfileViewModel(
                apiClient: apiClient,
                initialAccount: currentAccount
            )
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Metrics.sectionSpacing) {
                profileMediaSection
                basicInfoSection
                extraFieldsSection
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, theme.spacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.colors.groupedBackground)
        .tint(theme.colors.primary500)
        .navigationTitle(MoroL10n.EditProfile.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.colors.surfaceBase, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                saveButton
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(MoroL10n.Common.done) {
                    focusedInput = nil
                }
            }
        }
        .onChange(of: avatarPickerItem) { _, item in
            guard let item else { return }
            Task {
                await viewModel.selectAvatar(item: item)
                avatarPickerItem = nil
            }
        }
        .onChange(of: headerPickerItem) { _, item in
            guard let item else { return }
            Task {
                await viewModel.selectHeader(item: item)
                headerPickerItem = nil
            }
        }
    }

    @ViewBuilder
    private var profileMediaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(MoroL10n.EditProfile.sectionMedia)
            profileMediaEditor
        }
    }

    @ViewBuilder
    private var profileMediaEditor: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack(alignment: .topTrailing) {
                headerPreview
                    .aspectRatio(3, contentMode: .fit)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: Metrics.mediaCornerRadius,
                            style: .continuous
                        )
                    )

                headerControls
                    .padding(10)
            }

            HStack(alignment: .bottom, spacing: 10) {
                avatarPreview
                    .overlay {
                        Circle()
                            .stroke(theme.colors.surfaceBase, lineWidth: 3)
                    }

                avatarControls
                    .padding(.bottom, 6)
            }
            .padding(.leading, 14)
            .offset(y: Metrics.avatarSize * 0.42)
        }
        .padding(.bottom, Metrics.avatarSize * 0.42)
    }

    @ViewBuilder
    private var headerPreview: some View {
        ZStack {
            theme.colors.surfaceSubtle

            if let image = viewModel.headerPreviewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if !viewModel.isHeaderRemoved,
                      let url = viewModel.account?.profileHeaderURL {
                MoroNetworkImage(url: url)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .moroScaledFont(size: 22, weight: .medium)
                    Text(MoroL10n.EditProfile.mediaHeader)
                        .font(theme.typography.caption)
                }
                .foregroundStyle(theme.colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let image = viewModel.avatarPreviewImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: Metrics.avatarSize, height: Metrics.avatarSize)
                .clipShape(Circle())
        } else if !viewModel.isAvatarRemoved,
                  let avatarURL = viewModel.account?.profileAvatarURL {
            MoroAvatar(
                imageURL: avatarURL,
                staticImageURL: viewModel.account?.avatarURL,
                initials: viewModel.account?.displayNameInitials ?? "ME",
                size: Metrics.avatarSize
            )
        } else {
            Circle()
                .fill(theme.colors.surfaceSubtle)
                .frame(width: Metrics.avatarSize, height: Metrics.avatarSize)
                .overlay {
                    Image(systemName: "person.fill")
                        .moroScaledFont(size: 28, weight: .medium)
                        .foregroundStyle(theme.colors.textTertiary)
                }
        }
    }

    @ViewBuilder
    private var headerControls: some View {
        let isBusy = viewModel.isBusy

        HStack(spacing: 8) {
            PhotosPicker(selection: $headerPickerItem, matching: .images) {
                MoroUtilityIconSurface(
                    systemImage: "photo.badge.plus",
                    isDisabled: isBusy
                )
            }
            .disabled(isBusy)
            .accessibilityLabel(
                "\(MoroL10n.EditProfile.mediaHeader), \(MoroL10n.EditProfile.mediaChange)"
            )

            mediaRemovalControl(
                isRemoved: viewModel.isHeaderRemoved,
                canRemove: viewModel.canRemoveHeader,
                label: MoroL10n.EditProfile.mediaHeader,
                remove: viewModel.markHeaderRemoved,
                restore: viewModel.restoreHeader
            )
        }
    }

    @ViewBuilder
    private var avatarControls: some View {
        let isBusy = viewModel.isBusy

        HStack(spacing: 8) {
            PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                MoroUtilityIconSurface(
                    systemImage: "camera.fill",
                    isDisabled: isBusy
                )
            }
            .disabled(isBusy)
            .accessibilityLabel(
                "\(MoroL10n.EditProfile.mediaAvatar), \(MoroL10n.EditProfile.mediaChange)"
            )

            mediaRemovalControl(
                isRemoved: viewModel.isAvatarRemoved,
                canRemove: viewModel.canRemoveAvatar,
                label: MoroL10n.EditProfile.mediaAvatar,
                remove: viewModel.markAvatarRemoved,
                restore: viewModel.restoreAvatar
            )
        }
    }

    @ViewBuilder
    private func mediaRemovalControl(
        isRemoved: Bool,
        canRemove: Bool,
        label: String,
        remove: @escaping () -> Void,
        restore: @escaping () -> Void
    ) -> some View {
        if isRemoved {
            MoroUtilityIconButton(
                systemImage: "arrow.uturn.backward",
                accessibilityLabel: "\(label), \(MoroL10n.EditProfile.reset)",
                action: restore
            )
        } else if canRemove {
            MoroUtilityIconButton(
                systemImage: "trash",
                activeColor: theme.colors.error,
                inactiveColor: theme.colors.error,
                accessibilityLabel: "\(label), \(MoroL10n.EditProfile.remove)",
                action: remove
            )
        }
    }

    @ViewBuilder
    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(MoroL10n.EditProfile.sectionBasicInfo)

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    inputLabel(MoroL10n.EditProfile.fieldDisplayName)
                    TextField(MoroL10n.EditProfile.fieldDisplayName, text: $viewModel.displayName)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                        .textInputAutocapitalization(.words)
                        .focused($focusedInput, equals: .displayName)
                        .submitLabel(.next)
                        .onSubmit { focusedInput = .bio }
                }
                .padding(14)

                MoroDivider()
                    .padding(.leading, 14)

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        inputLabel(MoroL10n.EditProfile.fieldBio)
                        Spacer()
                        Text("\(viewModel.note.count)/\(EditProfileViewModel.bioCharacterLimit)")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textTertiary)
                            .monospacedDigit()
                    }

                    TextEditor(text: noteBinding)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                        .frame(minHeight: 124)
                        .scrollContentBackground(.hidden)
                        .focused($focusedInput, equals: .bio)
                }
                .padding(14)
            }
            .editProfileSectionSurface(theme: theme)
        }
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { viewModel.note },
            set: viewModel.updateNote
        )
    }

    @ViewBuilder
    private var extraFieldsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle(MoroL10n.EditProfile.sectionExtraFields)
                Spacer()
                Text("\(viewModel.fields.count)/\(EditProfileViewModel.maxFieldCount)")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                    .monospacedDigit()
            }

            if !viewModel.fields.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.fields.enumerated()), id: \.element.id) { index, field in
                        profileFieldEditor(
                            index: index,
                            field: binding(for: field.id)
                        )
                        .id(field.id)

                        if index < viewModel.fields.count - 1 {
                            MoroDivider()
                                .padding(.leading, 14)
                        }
                    }
                }
                .editProfileSectionSurface(theme: theme)
            }

            if viewModel.fields.count < EditProfileViewModel.maxFieldCount {
                Button(action: addField) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .moroScaledFont(size: 15, weight: .semibold)
                        Text(MoroL10n.EditProfile.addField)
                            .font(theme.typography.body)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .foregroundStyle(theme.colors.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .editProfileSectionSurface(theme: theme)
            }
        }
    }

    @ViewBuilder
    private func profileFieldEditor(
        index: Int,
        field: Binding<EditProfileViewModel.EditableField>
    ) -> some View {
        let fieldID = field.wrappedValue.id
        let isInvalid = attemptedSave && viewModel.invalidFieldIDs.contains(fieldID)

        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    inputLabel(MoroL10n.EditProfile.fieldLabel)
                        .lineLimit(1)
                    TextField(MoroL10n.EditProfile.fieldLabelPlaceholder, text: field.name)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                        .textInputAutocapitalization(.sentences)
                        .focused($focusedInput, equals: .fieldName(fieldID))
                        .submitLabel(.next)
                        .onSubmit { focusedInput = .fieldValue(fieldID) }
                }
                .frame(width: 116, alignment: .leading)

                Rectangle()
                    .fill(theme.colors.borderSubtle)
                    .frame(width: 1, height: 38)

                VStack(alignment: .leading, spacing: 4) {
                    inputLabel(MoroL10n.EditProfile.fieldValue)
                        .lineLimit(1)
                    TextField(MoroL10n.EditProfile.fieldValuePlaceholder, text: field.value)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                        .textInputAutocapitalization(.sentences)
                        .focused($focusedInput, equals: .fieldValue(fieldID))
                        .submitLabel(index == viewModel.fields.count - 1 ? .done : .next)
                        .onSubmit { focusNextField(after: index) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(role: .destructive) {
                    viewModel.removeField(id: fieldID)
                } label: {
                    Image(systemName: "trash")
                        .moroScaledFont(size: 15, weight: .medium)
                        .foregroundStyle(theme.colors.textTertiary)
                        .frame(width: 32, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MoroL10n.EditProfile.remove)
            }

            if isInvalid {
                Text(MoroL10n.EditProfile.fieldIncomplete)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.error)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .leading) {
            if isInvalid {
                Rectangle()
                    .fill(theme.colors.error)
                    .frame(width: 2)
            }
        }
    }

    @ViewBuilder
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .moroScaledFont(size: 13, weight: .semibold)
            .foregroundStyle(theme.colors.textSecondary)
    }

    @ViewBuilder
    private func inputLabel(_ text: String) -> some View {
        Text(text)
            .font(theme.typography.caption)
            .foregroundStyle(theme.colors.textSecondary)
    }

    @ViewBuilder
    private var saveButton: some View {
        if viewModel.isSaving {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(MoroL10n.EditProfile.saving)
        } else {
            Button(action: saveProfile) {
                Text(MoroL10n.EditProfile.save)
                    .fontWeight(.semibold)
            }
            .disabled(!viewModel.canSave)
        }
    }

    private func saveProfile() {
        attemptedSave = true
        focusedInput = nil

        Task {
            let saved = await viewModel.save(to: appState)
            if saved {
                dismiss()
            }
        }
    }

    private func addField() {
        guard let fieldID = viewModel.addField() else { return }
        attemptedSave = false
        Task { @MainActor in
            await Task.yield()
            focusedInput = .fieldName(fieldID)
        }
    }

    private func binding(for fieldID: UUID) -> Binding<EditProfileViewModel.EditableField> {
        Binding(
            get: {
                viewModel.fields.first(where: { $0.id == fieldID })
                    ?? EditProfileViewModel.EditableField(id: fieldID)
            },
            set: { updatedField in
                guard let index = viewModel.fields.firstIndex(where: { $0.id == fieldID }) else {
                    return
                }
                viewModel.fields[index] = updatedField
            }
        )
    }

    private func focusNextField(after index: Int) {
        let nextIndex = index + 1
        guard viewModel.fields.indices.contains(nextIndex) else {
            focusedInput = nil
            return
        }
        focusedInput = .fieldName(viewModel.fields[nextIndex].id)
    }
}

@MainActor
final class EditProfileViewModel: ObservableObject {
    static let maxFieldCount = 4
    static let bioCharacterLimit = 500

    struct FieldPair: Equatable {
        let name: String
        let value: String
    }

    struct EditableField: Identifiable, Equatable {
        let id: UUID
        var name: String
        var value: String

        init(id: UUID = UUID(), name: String = "", value: String = "") {
            self.id = id
            self.name = name
            self.value = value
        }
    }

    @Published var displayName: String
    @Published var note: String
    @Published var fields: [EditableField]
    @Published var avatarPreviewImage: UIImage?
    @Published var headerPreviewImage: UIImage?
    @Published private(set) var isAvatarRemoved = false
    @Published private(set) var isHeaderRemoved = false
    @Published private(set) var isSaving: Bool = false
    @Published private(set) var account: Account?

    private let apiClient: MastodonAPI
    private var avatarUpload: AccountProfileImageUpload?
    private var headerUpload: AccountProfileImageUpload?

    private var originalDisplayName: String
    private var originalNote: String
    private var originalFields: [FieldPair]

    init(apiClient: MastodonAPI, initialAccount: Account?) {
        self.apiClient = apiClient
        self.account = initialAccount

        let loadedDisplayName = initialAccount?.displayNameFormatted ?? ""
        let loadedNote = HTMLParser.stripHTML(initialAccount?.note ?? "")
        let loadedFields =
            (initialAccount?.fields ?? [])
            .prefix(Self.maxFieldCount)
            .map { EditableField(name: $0.name, value: HTMLParser.stripHTML($0.value)) }

        self.displayName = loadedDisplayName
        self.note = loadedNote
        self.fields = Array(loadedFields)

        self.originalDisplayName = loadedDisplayName
        self.originalNote = loadedNote
        self.originalFields = loadedFields.map {
            FieldPair(
                name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                value: $0.value.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    var isBusy: Bool {
        isSaving
    }

    var hasUnsavedChanges: Bool {
        hasAnyChanges
    }

    var canSave: Bool {
        hasAnyChanges && !isBusy
    }

    var canRemoveAvatar: Bool {
        !isAvatarRemoved && (avatarPreviewImage != nil || hasExistingAvatar)
    }

    var canRemoveHeader: Bool {
        !isHeaderRemoved && (headerPreviewImage != nil || hasExistingHeader)
    }

    var invalidFieldIDs: Set<UUID> {
        Set(
            fields.compactMap { field in
                let name = field.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty || value.isEmpty ? field.id : nil
            }
        )
    }

    @discardableResult
    func addField() -> UUID? {
        guard fields.count < Self.maxFieldCount else { return nil }
        let field = EditableField()
        fields.append(field)
        return field.id
    }

    func resetPendingChanges() {
        guard !isBusy else { return }

        displayName = originalDisplayName
        note = originalNote
        fields = originalFields.map { field in
            EditableField(name: field.name, value: field.value)
        }

        avatarUpload = nil
        headerUpload = nil
        avatarPreviewImage = nil
        headerPreviewImage = nil
        isAvatarRemoved = false
        isHeaderRemoved = false
    }

    func removeField(id: UUID) {
        fields.removeAll { $0.id == id }
    }

    func updateNote(_ value: String) {
        note = String(value.prefix(Self.bioCharacterLimit))
    }

    func selectAvatar(item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            AppFeedbackCenter.shared.showError(MoroL10n.EditProfile.toastAvatarLoadFailed)
            return
        }
        guard
            let prepared = Self.prepareImageUpload(
                data: data,
                maxDimension: 1024,
                fileNamePrefix: "avatar"
            )
        else {
            AppFeedbackCenter.shared.showError(MoroL10n.EditProfile.toastAvatarProcessFailed)
            return
        }

        avatarPreviewImage = prepared.previewImage
        avatarUpload = prepared.upload
        isAvatarRemoved = false
    }

    func selectHeader(item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            AppFeedbackCenter.shared.showError(MoroL10n.EditProfile.toastHeaderLoadFailed)
            return
        }
        guard
            let prepared = Self.prepareImageUpload(
                data: data,
                maxDimension: 2048,
                fileNamePrefix: "header"
            )
        else {
            AppFeedbackCenter.shared.showError(MoroL10n.EditProfile.toastHeaderProcessFailed)
            return
        }

        headerPreviewImage = prepared.previewImage
        headerUpload = prepared.upload
        isHeaderRemoved = false
    }

    func markAvatarRemoved() {
        guard !isBusy else { return }
        avatarUpload = nil
        avatarPreviewImage = nil
        isAvatarRemoved = hasExistingAvatar
    }

    func restoreAvatar() {
        guard !isBusy else { return }
        isAvatarRemoved = false
    }

    func markHeaderRemoved() {
        guard !isBusy else { return }
        headerUpload = nil
        headerPreviewImage = nil
        isHeaderRemoved = hasExistingHeader
    }

    func restoreHeader() {
        guard !isBusy else { return }
        isHeaderRemoved = false
    }

    func save(to appState: AppState) async -> Bool {
        guard !isBusy else { return false }

        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let normalizedFields = normalizedFieldsForSubmit() else {
            AppFeedbackCenter.shared.showError(MoroL10n.EditProfile.toastFieldsIncomplete)
            return false
        }

        guard hasAnyChanges else {
            AppFeedbackCenter.shared.showInfo(MoroL10n.EditProfile.toastNoChanges)
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let previousAccount = account ?? appState.currentAccount
            let requestedAvatarReplacement = avatarUpload != nil
            let requestedHeaderReplacement = headerUpload != nil
            let requestedAvatarRemoval = isAvatarRemoved && avatarUpload == nil
            let requestedHeaderRemoval = isHeaderRemoved && headerUpload == nil

            let serverReturnedAccount = try await apiClient.updateAccountProfile(
                displayName: normalizedName,
                note: normalizedNote,
                avatar: avatarUpload,
                header: headerUpload,
                removeAvatar: requestedAvatarRemoval,
                removeHeader: requestedHeaderRemoval,
                fields: normalizedFields
            )

            let updatedAccount = await resolveLatestAccountAfterProfileUpdate(
                fallback: serverReturnedAccount,
                previous: previousAccount,
                requestedAvatarRemoval: requestedAvatarRemoval,
                requestedHeaderRemoval: requestedHeaderRemoval,
                requestedAvatarReplacement: requestedAvatarReplacement,
                requestedHeaderReplacement: requestedHeaderReplacement
            )

            applyUpdatedAccount(
                updatedAccount,
                to: appState,
                bustAvatarURL: requestedAvatarReplacement || requestedAvatarRemoval,
                bustHeaderURL: requestedHeaderReplacement || requestedHeaderRemoval
            )

            avatarUpload = nil
            headerUpload = nil
            avatarPreviewImage = nil
            headerPreviewImage = nil
            isAvatarRemoved = false
            isHeaderRemoved = false

            originalDisplayName = updatedAccount.displayNameFormatted
            originalNote = HTMLParser.stripHTML(updatedAccount.note)
            originalFields = updatedAccount.fields.prefix(Self.maxFieldCount).map {
                FieldPair(
                    name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    value: HTMLParser.stripHTML($0.value).trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            fields = updatedAccount.fields.prefix(Self.maxFieldCount).map {
                EditableField(
                    name: $0.name,
                    value: HTMLParser.stripHTML($0.value)
                )
            }

            AppFeedbackCenter.shared.showSuccess(MoroL10n.EditProfile.toastUpdated)
            return true
        } catch {
            AppFeedbackCenter.shared.showError(MoroL10n.EditProfile.toastUpdateFailed)
            return false
        }
    }

    private func applyUpdatedAccount(
        _ updatedAccount: Account,
        to appState: AppState,
        bustAvatarURL: Bool = false,
        bustHeaderURL: Bool = false
    ) {
        let appliedAccount = updatedAccount.withCacheBustedMedia(
            avatar: bustAvatarURL,
            header: bustHeaderURL
        )

        account = appliedAccount
        appState.currentAccount = appliedAccount
        CacheManager.shared.accountCache.set(appliedAccount)
        invalidateImageCachesForProfileUpdate()
    }

    private func resolveLatestAccountAfterProfileUpdate(
        fallback: Account,
        previous: Account?,
        requestedAvatarRemoval: Bool,
        requestedHeaderRemoval: Bool,
        requestedAvatarReplacement: Bool,
        requestedHeaderReplacement: Bool
    ) async -> Account {
        var latest = fallback

        // Some instances may return stale media URLs immediately after profile update.
        // Re-verify credentials with short retries to converge on authoritative account state.
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }

            guard let verified = try? await apiClient.verifyCredentials() else { continue }
            latest = verified

            let needsRetry = shouldRetryAccountRefresh(
                previous: previous,
                latest: verified,
                requestedAvatarRemoval: requestedAvatarRemoval,
                requestedHeaderRemoval: requestedHeaderRemoval,
                requestedAvatarReplacement: requestedAvatarReplacement,
                requestedHeaderReplacement: requestedHeaderReplacement
            )

            if !needsRetry {
                break
            }
        }

        return latest
    }

    private func shouldRetryAccountRefresh(
        previous: Account?,
        latest: Account,
        requestedAvatarRemoval: Bool,
        requestedHeaderRemoval: Bool,
        requestedAvatarReplacement: Bool,
        requestedHeaderReplacement: Bool
    ) -> Bool {
        guard let previous else { return false }

        let avatarChangeRequested = requestedAvatarRemoval || requestedAvatarReplacement
        let headerChangeRequested = requestedHeaderRemoval || requestedHeaderReplacement

        let avatarUnchanged =
            previous.avatar == latest.avatar
            && previous.avatarStatic == latest.avatarStatic
        let headerUnchanged =
            previous.header == latest.header
            && previous.headerStatic == latest.headerStatic

        return (avatarChangeRequested && avatarUnchanged)
            || (headerChangeRequested && headerUnchanged)
    }

    private func invalidateImageCachesForProfileUpdate() {
        URLCache.shared.removeAllCachedResponses()
        ImageCache.shared.clearMemoryCache()
    }

    private var hasAnyChanges: Bool {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentFields = normalizedFieldsForComparison()

        return normalizedName != originalDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            || normalizedNote != originalNote.trimmingCharacters(in: .whitespacesAndNewlines)
            || currentFields != originalFields
            || avatarUpload != nil
            || headerUpload != nil
            || isAvatarRemoved
            || isHeaderRemoved
    }

    private var hasExistingAvatar: Bool {
        account?.profileAvatarURL != nil
    }

    private var hasExistingHeader: Bool {
        account?.profileHeaderURL != nil
    }

    private func normalizedFieldsForComparison() -> [FieldPair] {
        fields.map { field in
            let name = field.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return FieldPair(name: name, value: value)
        }
    }

    private func normalizedFieldsForSubmit() -> [AccountField]? {
        guard fields.count <= Self.maxFieldCount else { return nil }

        var result: [AccountField] = []
        for field in fields {
            let name = field.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)

            if name.isEmpty || value.isEmpty {
                return nil
            }
            result.append(AccountField(name: name, value: value))
        }
        return result
    }

    private static func prepareImageUpload(
        data: Data,
        maxDimension: CGFloat,
        fileNamePrefix: String
    ) -> (previewImage: UIImage, upload: AccountProfileImageUpload)? {
        guard let originalImage = UIImage(data: data) else { return nil }
        let processedImage = resizeIfNeeded(originalImage, maxDimension: maxDimension)
        guard let jpegData = processedImage.jpegData(compressionQuality: 0.85) else {
            return nil
        }

        let upload = AccountProfileImageUpload(
            data: jpegData,
            fileName: "\(fileNamePrefix)-\(UUID().uuidString).jpg",
            mimeType: "image/jpeg"
        )
        return (processedImage, upload)
    }

    private static func resizeIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let width = image.size.width
        let height = image.size.height
        guard width > maxDimension || height > maxDimension else { return image }

        let scale = min(maxDimension / width, maxDimension / height)
        let newSize = CGSize(width: width * scale, height: height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return resized
    }
}

private extension View {
    func editProfileSectionSurface(theme: MoroTheme) -> some View {
        background(theme.colors.surfaceBase)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.colors.borderSubtle, lineWidth: 1)
            }
    }
}
