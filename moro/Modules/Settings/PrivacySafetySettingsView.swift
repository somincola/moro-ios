//
//  PrivacySafetySettingsView.swift
//  moro
//
//  Privacy and safety settings view.
//

import SwiftUI

struct PrivacySafetySettingsView: View {
    @Environment(\.moroTheme) private var theme
    @EnvironmentObject private var appState: AppState
    @StateObject private var settings = AppSettings.shared
    
    let apiClient: MastodonAPI?
    
    @State private var isSaving = false
    @State private var saveError: Error?
    @State private var showSaveError = false
    
    init(apiClient: MastodonAPI? = nil) {
        self.apiClient = apiClient
    }
    
    var body: some View {
        List {
            Section {
                Toggle(MoroL10n.PrivacySafety.toggleApproveFollows, isOn: privacyBoolBinding(\.manuallyApproveFollowRequests))
                    .accessibilityIdentifier("settings.privacy.approveFollows")
                if apiClient == nil {
                    Toggle(MoroL10n.PrivacySafety.toggleShowFollowCounts, isOn: privacyBoolBinding(\.showFollowersAndFollowing))
                }
                Toggle(MoroL10n.PrivacySafety.toggleSuggestAccount, isOn: privacyBoolBinding(\.suggestMyAccountToOthers))
                Toggle(MoroL10n.PrivacySafety.toggleSearchEngine, isOn: privacyBoolBinding(\.appearInSearchEngines))
            } header: {
                MoroSettingsSectionHeader(title: MoroL10n.PrivacySafety.sectionOptions)
            }
            
            Section {
                Picker(MoroL10n.PrivacySafety.defaultVisibility, selection: privacyVisibilityBinding) {
                    ForEach(AppSettings.PostVisibility.allCases, id: \.rawValue) { visibility in
                        Text(visibility.localizedName).tag(visibility)
                    }
                }
            } header: {
                MoroSettingsSectionHeader(title: MoroL10n.PrivacySafety.sectionDefaults)
            }

            Section {
                privacyPresetButton(
                    title: MoroL10n.PrivacySafety.presetOpenTitle,
                    description: MoroL10n.PrivacySafety.presetOpenDescription,
                    preset: .openPublic
                )
                privacyPresetButton(
                    title: MoroL10n.PrivacySafety.presetPrivateTitle,
                    description: MoroL10n.PrivacySafety.presetPrivateDescription,
                    preset: .privateRestricted
                )
            } header: {
                MoroSettingsSectionHeader(title: MoroL10n.PrivacySafety.sectionPresets)
            }
        }
        .disabled(isSaving)
        .moroSettingsSwitchStyle()
        .moroSettingsListChrome(separators: .visible)
        .textCase(nil)
        .navigationTitle(MoroL10n.Settings.privacyVisibility)
        .navigationBarTitleDisplayMode(.inline)
        .alert(MoroL10n.PrivacySafety.saveFailed, isPresented: $showSaveError) {
            Button(MoroL10n.PrivacySafety.confirm, role: .cancel) { }
        } message: {
            Text(saveError?.localizedDescription ?? MoroL10n.PrivacySafety.saveErrorFallback)
        }
    }
    
    // MARK: - Privacy Presets
    
    enum PrivacyPreset {
        case openPublic
        case privateRestricted
        
        func apply(to settings: AppSettings) {
            switch self {
            case .openPublic:
                settings.manuallyApproveFollowRequests = false
                settings.showFollowersAndFollowing = true
                settings.suggestMyAccountToOthers = true
                settings.appearInSearchEngines = true
                settings.defaultPostVisibility = .public
            case .privateRestricted:
                settings.manuallyApproveFollowRequests = true
                settings.showFollowersAndFollowing = false
                settings.suggestMyAccountToOthers = false
                settings.appearInSearchEngines = false
                settings.defaultPostVisibility = .followersOnly
            }
        }
        
        func matches(settings: AppSettings) -> Bool {
            switch self {
            case .openPublic:
                return !settings.manuallyApproveFollowRequests &&
                       settings.showFollowersAndFollowing &&
                       settings.suggestMyAccountToOthers &&
                       settings.appearInSearchEngines &&
                       settings.defaultPostVisibility == .public
            case .privateRestricted:
                return settings.manuallyApproveFollowRequests &&
                       !settings.showFollowersAndFollowing &&
                       !settings.suggestMyAccountToOthers &&
                       !settings.appearInSearchEngines &&
                       settings.defaultPostVisibility == .followersOnly
            }
        }
    }
    
    @ViewBuilder
    private func privacyPresetButton(title: String, description: String, preset: PrivacyPreset) -> some View {
        Button(action: {
            applyPrivacyMutation { settings in
                preset.apply(to: settings)
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(theme.typography.body)
                        .fontWeight(.medium)
                        .foregroundStyle(theme.colors.textPrimary)
                    
                    Text(description)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                }
                
                Spacer()
                
                if preset.matches(settings: settings) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.colors.primary500)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var privacyVisibilityBinding: Binding<AppSettings.PostVisibility> {
        Binding(
            get: { settings.defaultPostVisibility },
            set: { newValue in
                applyPrivacyMutation { settings in
                    settings.defaultPostVisibility = newValue
                }
            }
        )
    }

    private func privacyBoolBinding(
        _ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                applyPrivacyMutation { settings in
                    settings[keyPath: keyPath] = newValue
                }
            }
        )
    }
    
    // MARK: - Save Settings

    private func applyPrivacyMutation(_ mutation: @escaping (AppSettings) -> Void) {
        let previous = PrivacySettingsSnapshot(settings: settings)
        mutation(settings)

        guard let apiClient else { return }
        Task {
            await persistPrivacySettings(apiClient: apiClient, previousSnapshot: previous)
        }
    }

    @MainActor
    private func persistPrivacySettings(
        apiClient: MastodonAPI,
        previousSnapshot: PrivacySettingsSnapshot
    ) async {
        guard !isSaving else { return }

        isSaving = true
        saveError = nil

        do {
            let updatedAccount = try await apiClient.updateAccountCredentials(
                discoverable: settings.suggestMyAccountToOthers,
                locked: settings.manuallyApproveFollowRequests,
                indexable: settings.appearInSearchEngines,
                hideCollections: !settings.showFollowersAndFollowing,
                privacy: settings.defaultPostVisibility.sourcePrivacyValue
            )
            appState.currentAccount = updatedAccount
        } catch {
            previousSnapshot.apply(to: settings)
            saveError = error
            showSaveError = true
            AppFeedbackCenter.shared.showError(MoroL10n.PrivacySafety.toastSyncFailed)
        }

        isSaving = false
    }
}

struct ContentSafetySettingsView: View {
    let apiClient: MastodonAPI

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AccountGovernanceView(kind: .muted, apiClient: apiClient)
                } label: {
                    Label(MoroL10n.PrivacySafety.governanceMuted, systemImage: "speaker.slash")
                }
                .accessibilityIdentifier("settings.muted")

                NavigationLink {
                    AccountGovernanceView(kind: .blocked, apiClient: apiClient)
                } label: {
                    Label(MoroL10n.PrivacySafety.governanceBlocked, systemImage: "hand.raised")
                }
                .accessibilityIdentifier("settings.blocked")

                NavigationLink {
                    FiltersSettingsView(apiClient: apiClient)
                } label: {
                    Label(MoroL10n.PrivacySafety.governanceFilters, systemImage: "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("settings.filters")
            } footer: {
                Text(MoroL10n.Settings.serverScope)
            }
        }
        .moroSettingsListChrome(separators: .visible)
        .textCase(nil)
        .navigationTitle(MoroL10n.Settings.contentSafety)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacySettingsSnapshot {
    let manuallyApproveFollowRequests: Bool
    let showFollowersAndFollowing: Bool
    let suggestMyAccountToOthers: Bool
    let appearInSearchEngines: Bool
    let defaultPostVisibility: AppSettings.PostVisibility

    init(settings: AppSettings) {
        manuallyApproveFollowRequests = settings.manuallyApproveFollowRequests
        showFollowersAndFollowing = settings.showFollowersAndFollowing
        suggestMyAccountToOthers = settings.suggestMyAccountToOthers
        appearInSearchEngines = settings.appearInSearchEngines
        defaultPostVisibility = settings.defaultPostVisibility
    }

    func apply(to settings: AppSettings) {
        settings.manuallyApproveFollowRequests = manuallyApproveFollowRequests
        settings.showFollowersAndFollowing = showFollowersAndFollowing
        settings.suggestMyAccountToOthers = suggestMyAccountToOthers
        settings.appearInSearchEngines = appearInSearchEngines
        settings.defaultPostVisibility = defaultPostVisibility
    }
}

#Preview {
    NavigationStack {
        PrivacySafetySettingsView()
            .environmentObject(AppState())
            .moroTheme(MoroTheme())
    }
}
