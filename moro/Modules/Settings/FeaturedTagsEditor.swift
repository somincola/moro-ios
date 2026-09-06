import SwiftUI

struct FeaturedTagsEditor: View {
    @Environment(\.moroTheme) private var theme
    @StateObject private var model: FeaturedTagsViewModel

    init(apiClient: MastodonAPI) {
        _model = StateObject(wrappedValue: FeaturedTagsViewModel(apiClient: apiClient))
    }

    var body: some View {
        List {
            Section {
                TextField(MoroL10n.ProfileEditing.tagPlaceholder, text: $model.input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { Task { await model.add() } }
                    .accessibilityIdentifier("profile.featuredTags.input")
                Button {
                    Task { await model.add() }
                } label: {
                    Label(MoroL10n.ProfileEditing.addTag, systemImage: "plus")
                        .frame(minHeight: 44)
                }
                .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || model.tags.count >= model.limits.featuredTagCount)
                .accessibilityIdentifier("profile.featuredTags.add")
            } footer: {
                Text(MoroL10n.ProfileEditing.tagHint)
            }

            if let error = model.error {
                Section {
                    Text(error).font(theme.typography.caption).foregroundStyle(theme.colors.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("profile.featuredTags.error")
                }
            }

            if !model.availableSuggestions.isEmpty && model.tags.count < model.limits.featuredTagCount {
                Section {
                    ForEach(model.availableSuggestions, id: \.name) { tag in
                        Button {
                            Task { await model.add(tag.name) }
                        } label: {
                            HStack(spacing: 12) {
                                Text("#\(tag.name)")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "plus.circle").accessibilityHidden(true)
                            }
                            .frame(minHeight: 44)
                        }
                    }
                } header: { Text(MoroL10n.ProfileEditing.suggestions) }
            }

            Section {
                if model.tags.isEmpty {
                    Text(MoroL10n.ProfileEditing.emptyTags)
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.vertical, 8)
                }
                ForEach(model.tags) { tag in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("#\(tag.name)").font(theme.typography.bodyStrong)
                            Text(MoroL10n.Timeline.statusCount(tag.statusesCount))
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button(role: .destructive) {
                            Task { await model.remove(tag) }
                        } label: {
                            Image(systemName: "minus.circle")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(MoroL10n.Common.delete) #\(tag.name)")
                        .accessibilityIdentifier("profile.featuredTags.remove.\(tag.name)")
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("\(model.tags.count)/\(model.limits.featuredTagCount)").monospacedDigit()
            } footer: {
                Text(MoroL10n.ProfileEditing.immediateSave)
            }
        }
        .profileEditorChrome()
        .navigationTitle(MoroL10n.ProfileEditing.featuredTags)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .disabled(model.isSaving || !model.hasLoaded)
        .overlay {
            if !model.hasLoaded {
                ProfileEditorLoadingView(error: model.error) { Task { await model.load() } }
            }
        }
        .toolbar {
            if model.isSaving {
                ToolbarItem(placement: .topBarTrailing) { ProgressView() }
            }
        }
        .task { if !model.hasLoaded { await model.load() } }
        .accessibilityIdentifier("profile.featuredTags.editor")
    }
}
