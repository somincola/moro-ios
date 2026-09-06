import SwiftUI

struct ProfileFieldsEditor: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @StateObject private var model: EditProfileViewModel
    @State private var editMode = EditMode.inactive

    init(apiClient: MastodonAPI, account: Account?) {
        _model = StateObject(wrappedValue: EditProfileViewModel(
            apiClient: apiClient, initialAccount: account, scope: .fields))
    }

    var body: some View {
        List {
            Section {
                ForEach(model.fields) { field in
                    fieldRow(field)
                        .accessibilityIdentifier("profile.field.\(model.fields.firstIndex(of: field) ?? 0)")
                        .accessibilityAction(named: MoroL10n.ComposeReading.moveUp) { move(field, by: -1) }
                        .accessibilityAction(named: MoroL10n.ComposeReading.moveDown) { move(field, by: 1) }
                        .moveDisabled(!editMode.isEditing)
                }
                .onDelete { model.fields.remove(atOffsets: $0) }
                .onMove { model.moveFields(from: $0, to: $1) }
                if model.fields.isEmpty {
                    Text(MoroL10n.ProfileEditing.emptyFields)
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.vertical, 8)
                }
            } header: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(model.fields.count)/\(model.limits.fieldCount)")
                        .font(theme.typography.caption)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    if model.fields.count > 1 || editMode.isEditing {
                        Button {
                            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                        } label: {
                            Text(editMode.isEditing
                                ? MoroL10n.ProfileEditing.finishReordering
                                : MoroL10n.ProfileEditing.reorderFields)
                                .font(theme.typography.caption.weight(.medium))
                                .foregroundStyle(theme.colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.fields.reorder")
                    }
                }
                .textCase(nil)
            } footer: {
                Text(editMode.isEditing
                    ? MoroL10n.ProfileEditing.fieldOrderHint
                    : MoroL10n.ProfileEditing.fieldEditingHint)
            }
            if !editMode.isEditing && model.fields.count < model.limits.fieldCount {
                Section {
                    NavigationLink {
                        fieldEditor()
                    } label: {
                        Label(MoroL10n.EditProfile.addField, systemImage: "plus")
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("profile.field.add")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .profileEditorChrome()
        .navigationTitle(MoroL10n.EditProfile.sectionExtraFields)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if model.isSaving { ProgressView() }
                else {
                    Button(MoroL10n.Common.save) {
                        Task { if await model.save(to: appState) { dismiss() } }
                    }
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("profile.fields.save")
                }
            }
        }
        .disabled(model.isSaving || !model.hasLoadedSource)
        .overlay {
            if !model.hasLoadedSource {
                ProfileEditorLoadingView(error: model.loadError) { Task { await model.load() } }
            }
        }
        .task { await model.load() }
        .profileEditorExitGuard(hasChanges: model.hasUnsavedChanges, isSaving: model.isBusy)
        .accessibilityIdentifier("profile.fields.editor")
    }

    private func fieldEditor(_ field: EditProfileViewModel.EditableField? = nil) -> some View {
        ProfileFieldEditor(field: field, limits: model.limits,
            onComplete: { updated in
                if let index = model.fields.firstIndex(where: { $0.id == updated.id }) {
                    model.fields[index] = updated
                } else if model.fields.count < model.limits.fieldCount {
                    model.fields.append(updated)
                }
            }, onDelete: {
                if let field { model.removeField(id: field.id) }
            })
    }

    @ViewBuilder
    private func fieldRow(_ field: EditProfileViewModel.EditableField) -> some View {
        if editMode.isEditing {
            ProfileEditorSummaryRow(title: field.name, summary: field.value)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(field.name)
                .accessibilityValue(field.value)
        } else {
            // The production shell uses UINavigationController, so use the
            // same destination-based link as the other profile editor pages.
            NavigationLink {
                fieldEditor(field)
            } label: {
                ProfileEditorSummaryRow(title: field.name, summary: field.value)
                    .contentShape(Rectangle())
            }
        }
    }

    private func move(_ field: EditProfileViewModel.EditableField, by offset: Int) {
        guard let index = model.fields.firstIndex(of: field), model.fields.indices.contains(index + offset) else { return }
        model.moveFields(from: IndexSet(integer: index), to: index + (offset > 0 ? 2 : -1))
    }
}

private struct ProfileFieldEditor: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var draft: EditProfileViewModel.EditableField
    // Freeze the baseline with the draft when NavigationLink rebuilds its destination.
    @State private var original: EditProfileViewModel.EditableField
    let limits: ProfileLimits
    let isExisting: Bool
    let onComplete: (EditProfileViewModel.EditableField) -> Void
    let onDelete: () -> Void

    init(field: EditProfileViewModel.EditableField?, limits: ProfileLimits,
         onComplete: @escaping (EditProfileViewModel.EditableField) -> Void, onDelete: @escaping () -> Void) {
        let initialField = field ?? .init()
        _original = State(initialValue: initialField)
        _draft = State(initialValue: initialField)
        self.limits = limits
        self.isExisting = field != nil
        self.onComplete = onComplete
        self.onDelete = onDelete
    }

    private var valid: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.name.count <= limits.fieldNameLength && draft.value.count <= limits.fieldValueLength
    }

    var body: some View {
        Form {
            Section {
                TextField(MoroL10n.EditProfile.fieldLabelPlaceholder, text: $draft.name, axis: .vertical)
                    .lineLimit(1...3)
                    .accessibilityIdentifier("profile.field.name")
            } header: {
                Text(MoroL10n.EditProfile.fieldLabel)
            } footer: {
                Text("\(draft.name.count)/\(limits.fieldNameLength)").monospacedDigit()
            }
            Section {
                TextField(MoroL10n.EditProfile.fieldValuePlaceholder, text: $draft.value, axis: .vertical)
                    .lineLimit(3...8)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("profile.field.value")
            } header: {
                Text(MoroL10n.EditProfile.fieldValue)
            } footer: {
                Text("\(draft.value.count)/\(limits.fieldValueLength)").monospacedDigit()
            }
            if isExisting {
                Section {
                    Button(role: .destructive) { onDelete(); dismiss() } label: {
                        Label(MoroL10n.Common.delete, systemImage: "trash")
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("profile.field.delete")
                }
            }
        }
        .environment(\.editMode, .constant(.inactive))
        .profileEditorChrome()
        .navigationTitle(MoroL10n.ProfileEditing.editField)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(MoroL10n.Common.done) { onComplete(draft); dismiss() }
                    .disabled(!valid)
                    .accessibilityIdentifier("profile.field.done")
            }
        }
        .profileEditorExitGuard(hasChanges: draft != original, isSaving: false)
    }
}
