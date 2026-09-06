import SwiftUI

struct ProfileFieldsEditor: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @StateObject private var model: EditProfileViewModel
    @State private var editingField: EditProfileViewModel.EditableField?

    init(apiClient: MastodonAPI, account: Account?) {
        _model = StateObject(wrappedValue: EditProfileViewModel(
            apiClient: apiClient, initialAccount: account, scope: .fields))
    }

    var body: some View {
        List {
            Section {
                ForEach(model.fields) { field in
                    Button { editingField = field } label: {
                        ProfileEditorSummaryRow(title: field.name, summary: field.value)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile.field.\(model.fields.firstIndex(of: field) ?? 0)")
                    .accessibilityAction(named: MoroL10n.ComposeReading.moveUp) { move(field, by: -1) }
                    .accessibilityAction(named: MoroL10n.ComposeReading.moveDown) { move(field, by: 1) }
                }
                .onMove { model.moveFields(from: $0, to: $1) }
                if model.fields.isEmpty {
                    Text(MoroL10n.ProfileEditing.emptyFields)
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.vertical, 8)
                }
            } header: {
                Text("\(model.fields.count)/\(model.limits.fieldCount)").monospacedDigit()
            } footer: {
                Text(MoroL10n.ProfileEditing.fieldOrderHint)
            }
            if model.fields.count < model.limits.fieldCount {
                Section {
                    Button { editingField = .init() } label: {
                        Label(MoroL10n.EditProfile.addField, systemImage: "plus")
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("profile.field.add")
                }
            }
        }
        .environment(\.editMode, .constant(.active))
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
        .navigationDestination(item: $editingField) { field in
            ProfileFieldEditor(field: field, limits: model.limits,
                isExisting: model.fields.contains(where: { $0.id == field.id }),
                onComplete: { updated in
                    if let index = model.fields.firstIndex(where: { $0.id == updated.id }) {
                        model.fields[index] = updated
                    } else if model.fields.count < model.limits.fieldCount {
                        model.fields.append(updated)
                    }
                }, onDelete: { model.removeField(id: field.id) })
        }
        .accessibilityIdentifier("profile.fields.editor")
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
    let original: EditProfileViewModel.EditableField
    let limits: ProfileLimits
    let isExisting: Bool
    let onComplete: (EditProfileViewModel.EditableField) -> Void
    let onDelete: () -> Void

    init(field: EditProfileViewModel.EditableField, limits: ProfileLimits, isExisting: Bool,
         onComplete: @escaping (EditProfileViewModel.EditableField) -> Void, onDelete: @escaping () -> Void) {
        original = field
        _draft = State(initialValue: field)
        self.limits = limits
        self.isExisting = isExisting
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
                    Button(MoroL10n.Common.delete, role: .destructive) { onDelete(); dismiss() }
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
