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

struct ProfileBasicsEditor: View {
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
    }

    init(apiClient: MastodonAPI, currentAccount: Account?) {
        _viewModel = StateObject(
            wrappedValue: EditProfileViewModel(
                apiClient: apiClient,
                initialAccount: currentAccount, scope: .basic
            )
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Metrics.sectionSpacing) {
                profileMediaSection
                basicInfoSection
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, theme.spacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.colors.groupedBackground)
        .tint(theme.colors.primary500)
        .navigationTitle(MoroL10n.EditProfile.sectionBasicInfo)
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
        .disabled(viewModel.isSaving || !viewModel.hasLoadedSource)
        .overlay {
            if !viewModel.hasLoadedSource {
                ProfileEditorLoadingView(error: viewModel.loadError) { Task { await viewModel.load() } }
            }
        }
        .task { await viewModel.load() }
        .profileEditorExitGuard(hasChanges: viewModel.hasUnsavedChanges, isSaving: viewModel.isBusy)
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
                        Text("\(viewModel.note.count)/\(viewModel.limits.noteLength)")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textTertiary)
                            .monospacedDigit()
                    }

                    TextEditor(text: noteBinding)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                        .frame(minHeight: 220)
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
