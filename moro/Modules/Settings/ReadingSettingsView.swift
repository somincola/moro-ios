import SwiftUI

struct ReadingSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.moroTheme) private var theme
    @Environment(\.activeAccountKey) private var activeAccountKey

    let apiClient: MastodonAPI?

    var body: some View {
        MoroSettingsList {
            Section {
                NavigationLink {
                    TimelineReadingPositionSettingsView()
                } label: {
                    LabeledContent {
                        Text(
                            settings.timelineOpenBehavior.summary(
                                smartMinutes: settings.smartRefreshIntervalMinutes
                            )
                        )
                        .foregroundStyle(theme.colors.textSecondary)
                    } label: {
                        Text(MoroL10n.ReadingPosition.rowTitle)
                            .foregroundStyle(theme.colors.textPrimary)
                    }
                }
                .accessibilityIdentifier("settings.reading.timelinePosition")

                Toggle(MoroL10n.GeneralSettings.newPostBanner, isOn: $settings.timelineInAppNewPostBannerEnabled)
                    .accessibilityIdentifier("settings.reading.newPostBanner")
            } header: {
                MoroSettingsSectionHeader(title: MoroL10n.Settings.timeline)
            } footer: {
                Text(MoroL10n.GeneralSettings.timelineMediaFooter)
            }

            Section {
                Toggle(MoroL10n.GeneralSettings.autoplayGIFs, isOn: $settings.autoplayGIFs)
                    .accessibilityIdentifier("settings.reading.autoplayGIFs")
                Toggle(MoroL10n.GeneralSettings.playAnimations, isOn: $settings.playAnimations)
                    .accessibilityIdentifier("settings.reading.playAnimations")
                Picker(selection: $settings.videoAutoplayMode) {
                    ForEach(AppSettings.VideoAutoplayMode.allCases, id: \.rawValue) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    Text(MoroL10n.GeneralSettings.videoAutoplayMode)
                        .foregroundStyle(theme.colors.textPrimary)
                }
                .pickerStyle(.menu)
                .tint(theme.colors.textSecondary)
            } header: {
                MoroSettingsSectionHeader(title: MoroL10n.ProfileEditing.media)
            } footer: {
                Text(MoroL10n.GeneralSettings.autoplayFooter)
            }

            Section {
                NavigationLink {
                    SensitiveMediaChoiceView()
                } label: {
                    LabeledContent {
                        Text(settings.sensitiveMediaDisplay.title)
                            .foregroundStyle(theme.colors.textSecondary)
                    } label: {
                        Text(MoroL10n.Settings.sensitiveMediaDisplay)
                            .foregroundStyle(theme.colors.textPrimary)
                    }
                }
                .accessibilityIdentifier("settings.sensitiveMedia")
                Toggle(MoroL10n.Settings.expandContentWarnings, isOn: $settings.expandContentWarnings)
                    .accessibilityIdentifier("settings.expandContentWarnings")
            } header: {
                MoroSettingsSectionHeader(title: MoroL10n.Settings.sensitiveSection)
            } footer: {
                Text(MoroL10n.Settings.sensitiveFooter)
            }

            Section {
                Picker(selection: $settings.openLinksIn) {
                    ForEach(AppSettings.OpenLinksIn.allCases, id: \.rawValue) { option in
                        Text(option.title).tag(option)
                    }
                } label: {
                    Text(MoroL10n.GeneralSettings.openLinksIn)
                        .foregroundStyle(theme.colors.textPrimary)
                }
                .pickerStyle(.menu)
                .tint(theme.colors.textSecondary)
            } header: {
                MoroSettingsSectionHeader(title: MoroL10n.GeneralSettings.linksSection)
            }

            Section {
                NavigationLink {
                    TranslationSettingsView()
                } label: {
                    LabeledContent(MoroL10n.Translation.settingsLabel) {
                        Text(settings.contentTranslationModeSummary)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
                .accessibilityIdentifier("settings.translation")
            }

            if let apiClient {
                Section {
                    NavigationLink(MoroL10n.Settings.profileReading) {
                        ProfileDisplaySettingsView(apiClient: apiClient, accountKey: activeAccountKey, scope: .local)
                    }
                    .accessibilityIdentifier("settings.profileReading")
                } footer: {
                    Text(MoroL10n.Settings.profileLocalScope)
                }
            }
        }
        .moroSettingsSwitchStyle()
        .moroSettingsListChrome()
        .textCase(nil)
        .navigationTitle(MoroL10n.Settings.readingMedia)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SensitiveMediaChoiceView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        MoroChoicePage(
            heading: MoroL10n.Settings.sensitiveMediaDisplay,
            hint: MoroL10n.Settings.sensitiveMediaDisplayHint,
            options: SensitiveMediaDisplay.allCases.map {
                MoroChoiceOption(value: $0, title: $0.title, detail: $0.detail)
            },
            selection: settings.sensitiveMediaDisplay,
            accessibilityPrefix: "settings.sensitiveMedia"
        ) { settings.sensitiveMediaDisplay = $0 }
    }
}

private struct TimelineReadingPositionSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.moroTheme) private var theme

    private let steps = AppSettings.smartRefreshMinuteSteps

    private var selectedStepIndex: Binding<Double> {
        Binding(
            get: {
                let normalized = AppSettings.normalizedSmartRefreshMinutes(settings.smartRefreshIntervalMinutes)
                return Double(steps.firstIndex(of: normalized) ?? 1)
            },
            set: { newValue in
                let index = min(max(Int(newValue.rounded()), 0), steps.count - 1)
                let minutes = steps[index]
                guard settings.smartRefreshIntervalMinutes != minutes else { return }
                UISelectionFeedbackGenerator().selectionChanged()
                settings.smartRefreshIntervalMinutes = minutes
            }
        )
    }

    var body: some View {
        MoroSettingsList {
            Section {
                ForEach(AppSettings.TimelineOpenBehavior.allCases, id: \.rawValue) { behavior in
                    MoroChoiceRow(
                        title: behavior.title,
                        detail: behavior.detail(smartMinutes: settings.smartRefreshIntervalMinutes),
                        isSelected: settings.timelineOpenBehavior == behavior
                    ) {
                        guard settings.timelineOpenBehavior != behavior else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.snappy(duration: 0.22)) {
                            settings.timelineOpenBehavior = behavior
                        }
                    }
                    .accessibilityIdentifier("settings.reading.timelinePosition.\(behavior.rawValue)")
                }
            } header: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(MoroL10n.ReadingPosition.pageHeading)
                        .moroScaledFont(size: 26, weight: .semibold, relativeTo: .title)
                        .foregroundStyle(theme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(MoroL10n.ReadingPosition.pageHint)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .textCase(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }

            if settings.timelineOpenBehavior == .smartRefresh {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(MoroL10n.ReadingPosition.smartThresholdLabel)
                                .font(.body)
                                .foregroundStyle(theme.colors.textPrimary)
                            Spacer()
                            Text(
                                AppSettings.formattedSmartRefreshDuration(
                                    minutes: settings.smartRefreshIntervalMinutes
                                )
                            )
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.colors.textSecondary)
                        }

                        Slider(
                            value: selectedStepIndex,
                            in: 0...Double(steps.count - 1),
                            step: 1
                        )
                        .tint(theme.colors.primary500)
                        .accessibilityIdentifier("settings.reading.smartRefreshSlider")
                        .accessibilityValue(
                            AppSettings.formattedSmartRefreshDuration(
                                minutes: settings.smartRefreshIntervalMinutes
                            )
                        )

                        HStack {
                            Text(AppSettings.formattedSmartRefreshDuration(minutes: steps.first ?? 30))
                            Spacer()
                            Text(AppSettings.formattedSmartRefreshDuration(minutes: steps.last ?? 1440))
                        }
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text(MoroL10n.ReadingPosition.smartThresholdFooter)
                }
                .transition(.opacity)
            }

            Section {
                Toggle(isOn: $settings.syncReadingPositionWithServer) {
                    HStack(spacing: 8) {
                        Text(MoroL10n.ReadingPosition.syncWithServerTitle)
                            .foregroundStyle(theme.colors.textPrimary)
                        Text(verbatim: "Beta")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(theme.colors.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.colors.surfaceSubtle, in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(theme.colors.borderSubtle, lineWidth: 0.75)
                            }
                    }
                }
                .accessibilityIdentifier("settings.reading.syncMarker")
            } header: {
                MoroSettingsSectionHeader(title: MoroL10n.ReadingPosition.syncSectionTitle)
            } footer: {
                Text(MoroL10n.ReadingPosition.syncWithServerFooter)
            }
        }
        .moroSettingsSwitchStyle()
        .moroSettingsListChrome()
        .textCase(nil)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}
