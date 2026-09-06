import SwiftUI

struct ProfileDisplaySettingsView: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @StateObject private var model: ProfileDisplayViewModel

    init(apiClient: MastodonAPI, accountKey: String) {
        _model = StateObject(wrappedValue: ProfileDisplayViewModel(apiClient: apiClient, accountKey: accountKey))
    }

    var body: some View {
        List {
            Section {
                Toggle(MoroL10n.ProfileEditing.showTags, isOn: $model.showTags)
                    .accessibilityIdentifier("profile.display.featuredTags")
            } header: {
                Text(verbatim: "Moro")
            } footer: {
                Text(MoroL10n.ProfileEditing.showTagsHint)
            }

            if let error = model.error {
                Section {
                    Text(error).font(theme.typography.caption).foregroundStyle(theme.colors.error)
                    if !model.hasLoaded {
                        Button(MoroL10n.Timeline.retry) { Task { await model.load() } }
                    }
                }
            }
            if model.hasLoaded {
                Section {
                    Toggle(MoroL10n.ProfileEditing.showMedia, isOn: $model.showMedia)
                        .disabled(!model.supportsMedia)
                        .accessibilityIdentifier("profile.display.media")
                    Toggle(MoroL10n.ProfileEditing.showMediaReplies, isOn: $model.showMediaReplies)
                        .disabled(!model.supportsMediaReplies || !model.showMedia)
                        .accessibilityIdentifier("profile.display.mediaReplies")
                } footer: {
                    if !model.supportsMedia || !model.supportsMediaReplies {
                        Text(MoroL10n.ProfileEditing.unsupported)
                    }
                }
                Section {
                    Toggle(MoroL10n.PrivacySafety.toggleShowFollowCounts, isOn: $model.showConnections)
                        .accessibilityIdentifier("profile.display.connections")
                }
                Section {
                    Toggle(MoroL10n.ProfileEditing.showFeaturedWeb, isOn: $model.showFeatured)
                        .disabled(!model.supportsFeatured)
                        .accessibilityIdentifier("profile.display.featuredWeb")
                } footer: {
                    Text(model.supportsFeatured
                        ? MoroL10n.ProfileEditing.showFeaturedWebHint
                        : MoroL10n.ProfileEditing.unsupported)
                }
            } else if model.isLoading {
                Section { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12) }
            }
        }
        .moroSettingsSwitchStyle()
        .profileEditorChrome()
        .navigationTitle(MoroL10n.ProfileEditing.displaySettings)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if model.isSaving { ProgressView() }
                else {
                    Button(MoroL10n.Common.save) {
                        Task { if await model.save(to: appState) { dismiss() } }
                    }
                    .disabled(!model.hasChanges || model.isLoading)
                    .accessibilityIdentifier("profile.display.save")
                }
            }
        }
        .disabled(model.isSaving)
        .profileEditorExitGuard(hasChanges: model.hasChanges, isSaving: model.isSaving)
        .task { await model.load() }
        .accessibilityIdentifier("profile.display.editor")
    }
}
