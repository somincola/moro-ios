import PhotosUI
import SwiftUI

/// Everything you type about yourself lives on this one page: images, name, bio and
/// the extra fields share one draft and one Save. Settings that aren't text stay a
/// tap away at the bottom.
struct EditProfileView: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.activeAccountKey) private var activeAccountKey
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @EnvironmentObject private var appState: AppState
    @StateObject private var model: EditProfileViewModel
    @State private var attemptedSave = false
    @State private var pickerTarget: MediaKind = .avatar
    @State private var isPickerPresented = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var mediaOptions: MediaKind?
    @FocusState private var focus: Focus?
    private let apiClient: MastodonAPI

    private enum Metrics {
        static let avatarSize: CGFloat = 88
        static let mediaSpacing: CGFloat = 16
        static let headerCornerRadius: CGFloat = 16
        static let inputCornerRadius: CGFloat = 14
        static let inputPadding: CGFloat = 14
    }

    enum MediaKind { case avatar, header }

    private enum Focus: Hashable {
        case displayName, bio
        case fieldName(UUID), fieldValue(UUID)
    }

    init(apiClient: MastodonAPI, currentAccount: Account?) {
        self.apiClient = apiClient
        _model = StateObject(wrappedValue: EditProfileViewModel(
            apiClient: apiClient, initialAccount: currentAccount, scope: .all))
    }

    var body: some View {
        // A plain scroll view, not a List: inset-grouped lists round the first and
        // last row of each section, which clipped the input boxes' borders.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                mediaRow
                    .padding(.bottom, 20)
                VStack(alignment: .leading, spacing: 16) {
                    displayNameRow
                    bioRow
                }
                .disabled(!model.hasLoadedSource)
                fieldsSection
                    .padding(.top, MoroSettingsMetrics.sectionSpacing + 4)
                linkGroup(MoroL10n.EditProfile.sectionProfileSettings) {
                    linkRow(MoroL10n.ProfileEditing.featuredTags, MoroL10n.ProfileEditing.tagHint,
                        id: "profile.edit.featuredTags") { FeaturedTagsEditor(apiClient: apiClient) }
                    divider
                    linkRow(MoroL10n.Settings.profilePublic, MoroL10n.Settings.serverScope,
                        id: "profile.edit.display") {
                        ProfileDisplaySettingsView(apiClient: apiClient, accountKey: activeAccountKey)
                    }
                }
                .padding(.top, MoroSettingsMetrics.sectionSpacing + 4)
                linkGroup(MoroL10n.Settings.appSection) {
                    linkRow(MoroL10n.Settings.profileReading, MoroL10n.Settings.profileLocalScope,
                        id: "profile.edit.localDisplay") {
                        ProfileDisplaySettingsView(apiClient: apiClient, accountKey: activeAccountKey, scope: .local)
                    }
                }
                .padding(.top, MoroSettingsMetrics.sectionSpacing)
            }
            .padding(.horizontal, MoroSettingsMetrics.pageHorizontalInset)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .moroSettingsPageChrome()
        .navigationTitle(MoroL10n.EditProfile.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { saveButton }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(MoroL10n.Common.done) { focus = nil }
            }
        }
        .disabled(model.isSaving)
        .overlay {
            if !model.hasLoadedSource, model.loadError != nil {
                ProfileEditorLoadingView(error: model.loadError) { Task { await model.load() } }
            }
        }
        .task { await model.load() }
        .photosPicker(isPresented: $isPickerPresented, selection: $pickedItem, matching: .images)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            let target = pickerTarget
            Task {
                switch target {
                case .avatar: await model.selectAvatar(item: item)
                case .header: await model.selectHeader(item: item)
                }
                pickedItem = nil
            }
        }
        .profileEditorExitGuard(hasChanges: model.hasUnsavedChanges, isSaving: model.isBusy)
        // Toolbar items (Save, the guarded back button, keyboard Done) sit outside the
        // page chrome's tint; without this they fall back to system blue on iOS 18.
        .tint(theme.colors.primary500)
        .accessibilityIdentifier("profile.edit.overview")
    }

    // MARK: - Images

    /// The images are the controls: tap one for its menu. With nothing to undo or
    /// remove, the tap goes straight to the photo picker. The avatar sits centred
    /// on its own row below the cover.
    private var mediaRow: some View {
        VStack(spacing: Metrics.mediaSpacing) {
            mediaControl(.header) {
                // The frame is fixed at 3:1 first; a picked photo of any shape fills it.
                Color.clear
                    .aspectRatio(3, contentMode: .fit)
                    .overlay { headerPreview }
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.headerCornerRadius, style: .continuous))
                    .overlay(alignment: .topTrailing) { imageBadge.padding(10) }
                    .contentShape(RoundedRectangle(cornerRadius: Metrics.headerCornerRadius, style: .continuous))
            }
            mediaControl(.avatar) {
                avatarPreview
                    .overlay { Circle().stroke(theme.colors.groupedBackground, lineWidth: 4) }
                    .overlay(alignment: .bottomTrailing) { avatarBadge.offset(x: 2, y: 0) }
                    .contentShape(Circle())
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(!model.hasLoadedSource)
    }

    /// A plain button with a light press. Options open as an action sheet rather
    /// than a context menu, which would fade the image it was opened from.
    private func mediaControl<Label: View>(_ kind: MediaKind, @ViewBuilder label: () -> Label) -> some View {
        let isAvatar = kind == .avatar
        return Button {
            if hasMediaOptions(kind) {
                focus = nil
                mediaOptions = kind
            } else {
                presentPicker(for: kind)
            }
        } label: {
            label()
        }
        .buttonStyle(MediaPressStyle())
        .accessibilityLabel(isAvatar ? MoroL10n.EditProfile.mediaAvatar : MoroL10n.EditProfile.mediaHeader)
        .accessibilityHint(MoroL10n.EditProfile.mediaChange)
        .accessibilityIdentifier(isAvatar ? "profile.edit.avatar" : "profile.edit.header")
        // Each image owns its presentation anchor on iOS 26 and later.
        .confirmationDialog(
            isAvatar ? MoroL10n.EditProfile.mediaAvatar : MoroL10n.EditProfile.mediaHeader,
            isPresented: Binding(
                get: { mediaOptions == kind },
                set: { if !$0, mediaOptions == kind { mediaOptions = nil } }
            ),
            titleVisibility: .visible
        ) {
            mediaOptionButtons(kind)
        }
    }

    private func hasMediaOptions(_ kind: MediaKind) -> Bool {
        kind == .avatar
            ? model.hasPendingAvatarChange || model.canRemoveAvatar
            : model.hasPendingHeaderChange || model.canRemoveHeader
    }

    @ViewBuilder
    private func mediaOptionButtons(_ kind: MediaKind) -> some View {
        let isAvatar = kind == .avatar
        Button(MoroL10n.EditProfile.mediaChoosePhoto) { presentPicker(for: kind) }
        if isAvatar ? model.hasPendingAvatarChange : model.hasPendingHeaderChange {
            Button(MoroL10n.EditProfile.mediaRevert) {
                isAvatar ? model.revertAvatar() : model.revertHeader()
            }
        }
        if isAvatar ? model.canRemoveAvatar : model.canRemoveHeader {
            Button(isAvatar ? MoroL10n.EditProfile.mediaRemoveAvatar : MoroL10n.EditProfile.mediaRemoveHeader,
                   role: .destructive) {
                isAvatar ? model.markAvatarRemoved() : model.markHeaderRemoved()
            }
        }
        Button(MoroL10n.Common.cancel, role: .cancel) {}
    }

    private func presentPicker(for kind: MediaKind) {
        focus = nil
        pickerTarget = kind
        isPickerPresented = true
    }

    @ViewBuilder
    private var headerPreview: some View {
        ZStack {
            theme.colors.surfaceSubtle
            if let image = model.headerPreviewImage {
                Image(uiImage: image).resizable().scaledToFill()
            } else if !model.isHeaderRemoved, let url = model.account?.profileHeaderURL {
                MoroNetworkImage(url: url)
            } else {
                // Exactly what the profile will show without a cover, plus the hint.
                ProfileGeneratedHeader(
                    avatarURL: model.isAvatarRemoved ? nil : model.account?.profileAvatarURL,
                    avatarImage: model.avatarPreviewImage,
                    seed: placeholderSeed)
                Label(MoroL10n.EditProfile.mediaAddHeader, systemImage: "photo.badge.plus")
                    .font(theme.typography.caption.weight(.medium))
                    .foregroundStyle(theme.colors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let image = model.avatarPreviewImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: Metrics.avatarSize, height: Metrics.avatarSize)
                .clipShape(Circle())
        } else if !model.isAvatarRemoved, let url = model.account?.profileAvatarURL {
            MoroAvatar(imageURL: url, staticImageURL: model.account?.avatarURL,
                initials: model.account?.displayNameInitials ?? "ME", seed: placeholderSeed,
                size: Metrics.avatarSize)
        } else {
            // What the profile will show without an avatar.
            GeneratedAvatar(initials: model.account?.displayNameInitials ?? "ME",
                seed: placeholderSeed, size: Metrics.avatarSize)
        }
    }

    private var placeholderSeed: String {
        model.account?.placeholderSeed ?? appState.currentAccount?.placeholderSeed ?? ""
    }

    /// Sits on a photo, so it carries its own dark backing in both themes.
    private var imageBadge: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(.black.opacity(0.5)))
            .accessibilityHidden(true)
    }

    private var avatarBadge: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.colors.groupedBackground)
            .frame(width: 26, height: 26)
            .background(Circle().fill(theme.colors.textPrimary))
            .overlay { Circle().stroke(theme.colors.groupedBackground, lineWidth: 2.5) }
            .accessibilityHidden(true)
    }

    // MARK: - Basic info

    private var displayNameRow: some View {
        let count = model.displayName.count
        let limit = model.limits.displayNameLength
        return VStack(alignment: .leading, spacing: 8) {
            inputLabel(MoroL10n.EditProfile.fieldDisplayName,
                counter: count >= limit - 10 ? "\(count)/\(limit)" : nil, isOver: count > limit)
            HStack(spacing: 8) {
                TextField(MoroL10n.EditProfile.fieldDisplayName, text: $model.displayName)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textPrimary)
                    .textInputAutocapitalization(.words)
                    .focused($focus, equals: .displayName)
                    .submitLabel(.next)
                    .onSubmit { focus = .bio }
                    .accessibilityIdentifier("profile.basic.name")
                if focus == .displayName, !model.displayName.isEmpty {
                    Button { model.displayName = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(theme.colors.textTertiary)
                            .frame(minWidth: 28, minHeight: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(MoroL10n.EditProfile.clearText)
                }
            }
            .padding(.horizontal, Metrics.inputPadding)
            .frame(minHeight: 48)
            .inputBox(isFocused: focus == .displayName, theme: theme)
        }
    }

    private var bioRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            inputLabel(MoroL10n.EditProfile.fieldBio,
                counter: "\(model.note.count)/\(model.limits.noteLength)",
                isOver: model.note.count > model.limits.noteLength)
            TextField(MoroL10n.EditProfile.fieldBio,
                text: Binding(get: { model.note }, set: model.updateNote), axis: .vertical)
                .lineLimit(4...)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textPrimary)
                .focused($focus, equals: .bio)
                .padding(.horizontal, Metrics.inputPadding)
                .padding(.vertical, 12)
                .inputBox(isFocused: focus == .bio, theme: theme)
                .accessibilityIdentifier("profile.basic.bio")
        }
    }

    private func inputLabel(_ title: String, counter: String? = nil, isOver: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(theme.typography.caption)
                .fontWeight(.medium)
                .foregroundStyle(theme.colors.textSecondary)
            Spacer(minLength: 8)
            if let counter {
                Text(counter)
                    .font(theme.typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(isOver ? theme.colors.error : theme.colors.textTertiary)
            }
        }
        .padding(.horizontal, Metrics.inputPadding)
    }

    // MARK: - Extra fields

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                MoroSettingsSectionHeader(title: MoroL10n.EditProfile.sectionExtraFields)
                Spacer(minLength: 8)
                Text("\(model.fields.count)/\(model.limits.fieldCount)")
                    .font(theme.typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(.horizontal, Metrics.inputPadding)
            ForEach(Array(model.fields.enumerated()), id: \.element.id) { index, field in
                fieldCard(field, index: index)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
            if model.fields.count < model.limits.fieldCount {
                addFieldButton
            }
            Text(model.fields.isEmpty ? MoroL10n.ProfileEditing.emptyFields : MoroL10n.EditProfile.fieldsFooter)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .padding(.horizontal, Metrics.inputPadding)
        }
        .disabled(!model.hasLoadedSource)
    }

    /// Label over value, the way the pair reads on the profile itself.
    private func fieldCard(_ field: EditProfileViewModel.EditableField, index: Int) -> some View {
        let isInvalid = attemptedSave && model.invalidFieldIDs.contains(field.id)
        let isTooLong = model.overLimitFieldIDs.contains(field.id)
        let isFocused = focus == .fieldName(field.id) || focus == .fieldValue(field.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    TextField(MoroL10n.EditProfile.fieldLabelPlaceholder, text: fieldBinding(field.id, \.name))
                        .font(theme.typography.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(theme.colors.textSecondary)
                        .focused($focus, equals: .fieldName(field.id))
                        .submitLabel(.next)
                        .onSubmit { focus = .fieldValue(field.id) }
                        .padding(.top, 12)
                        .padding(.bottom, 9)
                        .accessibilityLabel(MoroL10n.EditProfile.fieldLabel)
                        .accessibilityIdentifier("profile.field.\(index).name")
                    Rectangle()
                        .fill(theme.colors.borderSubtle)
                        .frame(height: 1 / displayScale)
                    TextField(MoroL10n.EditProfile.fieldValuePlaceholder,
                        text: fieldBinding(field.id, \.value, singleLine: true), axis: .vertical)
                        .lineLimit(1...5)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .fieldValue(field.id))
                        .padding(.top, 9)
                        .padding(.bottom, 12)
                        .accessibilityLabel(MoroL10n.EditProfile.fieldValue)
                        .accessibilityIdentifier("profile.field.\(index).value")
                }
                .padding(.leading, Metrics.inputPadding)
                fieldMenu(field, index: index)
            }
            .inputBox(isFocused: isFocused, isInvalid: isInvalid || isTooLong, theme: theme)
            if isInvalid || isTooLong {
                Text(isTooLong ? MoroL10n.ProfileEditing.limitsExceeded : MoroL10n.EditProfile.fieldIncomplete)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.error)
                    .padding(.horizontal, Metrics.inputPadding)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.field.\(index)")
    }

    private func fieldMenu(_ field: EditProfileViewModel.EditableField, index: Int) -> some View {
        Menu {
            Button { move(field.id, by: -1) } label: {
                SwiftUI.Label(MoroL10n.ComposeReading.moveUp, systemImage: "arrow.up")
            }
            .disabled(index == 0)
            Button { move(field.id, by: 1) } label: {
                SwiftUI.Label(MoroL10n.ComposeReading.moveDown, systemImage: "arrow.down")
            }
            .disabled(index == model.fields.count - 1)
            Divider()
            Button(role: .destructive) { removeField(field.id) } label: {
                SwiftUI.Label(MoroL10n.Common.delete, systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .moroScaledFont(size: 15, weight: .semibold)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .padding(.top, 2)
        .padding(.trailing, 2)
        .accessibilityLabel(MoroL10n.EditProfile.fieldOptions)
        .accessibilityIdentifier("profile.field.\(index).menu")
    }

    private var addFieldButton: some View {
        Button(action: addField) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .moroScaledFont(size: 15, weight: .semibold)
                Text(MoroL10n.EditProfile.addField)
                    .font(theme.typography.body)
            }
            .foregroundStyle(theme.colors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                RoundedRectangle(cornerRadius: Metrics.inputCornerRadius, style: .continuous)
                    .strokeBorder(theme.colors.textTertiary.opacity(0.6),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            .contentShape(RoundedRectangle(cornerRadius: Metrics.inputCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile.field.add")
    }

    /// Field values can't hold line breaks; Return moves on instead of inserting one.
    private func fieldBinding(_ id: UUID, _ keyPath: WritableKeyPath<EditProfileViewModel.EditableField, String>,
                              singleLine: Bool = false) -> Binding<String> {
        Binding(
            get: { model.fields.first { $0.id == id }?[keyPath: keyPath] ?? "" },
            set: { newValue in
                guard let index = model.fields.firstIndex(where: { $0.id == id }) else { return }
                if singleLine, newValue.contains("\n") {
                    model.fields[index][keyPath: keyPath] = newValue.replacingOccurrences(of: "\n", with: "")
                    focus = nil
                } else {
                    model.fields[index][keyPath: keyPath] = newValue
                }
            })
    }

    private func addField() {
        guard let id = withAnimation(.easeOut(duration: 0.2), { model.addField() }) else { return }
        // Focus once the new row exists.
        DispatchQueue.main.async { focus = .fieldName(id) }
    }

    private func removeField(_ id: UUID) {
        if focus == .fieldName(id) || focus == .fieldValue(id) { focus = nil }
        withAnimation(.easeOut(duration: 0.2)) { model.removeField(id: id) }
    }

    private func move(_ id: UUID, by offset: Int) {
        withAnimation(.easeInOut(duration: 0.25)) { model.moveField(id: id, by: offset) }
    }

    // MARK: - Other profile settings

    private func linkGroup<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MoroSettingsSectionHeader(title: title)
                .padding(.horizontal, Metrics.inputPadding)
            VStack(spacing: 0) { rows() }
                .background(theme.colors.groupedSurface,
                    in: RoundedRectangle(cornerRadius: Metrics.inputCornerRadius, style: .continuous))
        }
    }

    private func linkRow<Destination: View>(_ title: String, _ summary: String, id: String,
                                            @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                ProfileEditorSummaryRow(title: title, summary: summary)
                Image(systemName: "chevron.right")
                    .moroScaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(.horizontal, Metrics.inputPadding)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.colors.borderSubtle)
            .frame(height: 1 / displayScale)
            .padding(.leading, Metrics.inputPadding)
    }

    // MARK: - Save

    @ViewBuilder
    private var saveButton: some View {
        if model.isSaving || (!model.hasLoadedSource && model.loadError == nil) {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(model.isSaving ? MoroL10n.EditProfile.saving : MoroL10n.EditProfile.title)
        } else {
            Button(action: save) {
                Text(MoroL10n.EditProfile.save).fontWeight(.semibold)
            }
            .disabled(!model.canSave)
            .accessibilityIdentifier("profile.edit.save")
        }
    }

    private func save() {
        attemptedSave = true
        focus = nil
        Task {
            if await model.save(to: appState) { dismiss() }
        }
    }
}

struct ProfileEditorSummaryRow: View {
    @Environment(\.moroTheme) private var theme
    let title: String
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(theme.typography.body).foregroundStyle(theme.colors.textPrimary)
            Text(summary)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

/// Images stay fully visible while pressed; a slight shrink is the only feedback.
private struct MediaPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private extension View {
    func inputBox(isFocused: Bool, isInvalid: Bool = false, theme: MoroTheme) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let border = isInvalid ? theme.colors.error : isFocused ? theme.colors.primary500 : theme.colors.borderSubtle
        return background(theme.colors.groupedSurface, in: shape)
            .overlay { shape.strokeBorder(border, lineWidth: isFocused || isInvalid ? 1.5 : 1) }
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
