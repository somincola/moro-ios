//
//  MoroProfileCardWidget.swift
//  moroWidgets
//
//  Monochrome editorial Mastodon identity card in Small and Medium sizes,
//  pairing profile stats with one-tap Compose and Profile jumps.
//

import AppIntents
import SwiftUI
import WidgetKit

struct MoroProfileCardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MoroWidgetKind.profileCard, provider: MoroWidgetProvider()) { entry in
            MoroProfileCardWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    MoroWidgetSurfaceBackground(accent: entry.snapshot?.accent ?? .default)
                }
        }
        .configurationDisplayName("widget.profile.name")
        .description("widget.profile.description")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct MoroProfileCardWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    let entry: MoroWidgetEntry

    private var palette: MoroWidgetPalette {
        MoroWidgetPalette(
            colorScheme: colorScheme,
            renderingMode: renderingMode,
            accent: entry.snapshot?.accent ?? .default
        )
    }

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                if family == .systemMedium {
                    mediumContent(snapshot)
                } else {
                    smallContent(snapshot)
                }
            } else {
                MoroWidgetEmptyState(title: "widget.signIn.title")
                    .padding(16)
            }
        }
        .privacySensitive()
    }

    // MARK: - Home Screen Small

    private func smallContent(_ snapshot: MoroWidgetDataSnapshot) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                MoroWidgetAvatar(
                    account: snapshot.account,
                    avatarData: entry.avatarData,
                    size: 40,
                    palette: palette
                )

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(snapshot.account.preferredName)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(palette.inkPrimary)
                        .lineLimit(1)

                    Text(snapshot.account.handle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.inkSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 0) {
                MoroProfileStatCell(
                    value: snapshot.account.followersCount,
                    title: "widget.profile.followers",
                    palette: palette
                )

                Rectangle()
                    .fill(palette.divider)
                    .frame(width: 0.75, height: 22)

                MoroProfileStatCell(
                    value: snapshot.account.followingCount,
                    title: "widget.profile.following",
                    palette: palette
                )
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(palette.tileSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.tileBorder, lineWidth: 0.75)
            }

            HStack(spacing: 7) {
                Button(intent: OpenMoroDestinationIntent(destination: .compose)) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 12.5, weight: .semibold))
                            .widgetAccentable()
                        Text("widget.action.compose")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 35)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("widget.action.compose"))
                .foregroundStyle(palette.primaryTileForeground)
                .background(
                    palette.primaryTileFill,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(palette.primaryTileBorder, lineWidth: 0.75)
                }

                Button(intent: OpenMoroDestinationIntent(destination: .profile)) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 35, height: 35)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("widget.action.profile"))
                .foregroundStyle(palette.inkPrimary)
                .background(
                    palette.tileSurface,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(palette.tileBorder, lineWidth: 0.75)
                }
            }
        }
        .padding(14)
        .widgetURL(MoroWidgetDestination.profile.deepLinkURL)
    }

    // MARK: - Home Screen Medium (Mastodon Identity Card)

    private func mediumContent(_ snapshot: MoroWidgetDataSnapshot) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                MoroWidgetAvatar(
                    account: snapshot.account,
                    avatarData: entry.avatarData,
                    size: 50,
                    palette: palette
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.account.preferredName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(palette.inkPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(snapshot.account.handle)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(palette.inkSecondary)
                            .lineLimit(1)

                        if let domain = snapshot.account.instanceDomain {
                            Text(domain)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(palette.inkSecondary)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(palette.subtleSurface, in: Capsule())
                        }
                    }
                }

                Spacer(minLength: 4)

                MoroWidgetBrandBadge(palette: palette, size: 28)
            }

            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    MoroProfileStatCell(
                        value: snapshot.account.followersCount,
                        title: "widget.profile.followers",
                        palette: palette
                    )

                    Rectangle()
                        .fill(palette.divider)
                        .frame(width: 0.75, height: 24)

                    MoroProfileStatCell(
                        value: snapshot.account.followingCount,
                        title: "widget.profile.following",
                        palette: palette
                    )

                    Rectangle()
                        .fill(palette.divider)
                        .frame(width: 0.75, height: 24)

                    MoroProfileStatCell(
                        value: snapshot.unreadCount,
                        title: "widget.profile.unread",
                        palette: palette,
                        highlighted: snapshot.unreadCount > 0
                    )
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(palette.tileSurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(palette.tileBorder, lineWidth: 0.75)
                }
                .shadow(color: palette.tileShadowColor, radius: 3, y: 1.5)

                Button(intent: OpenMoroDestinationIntent(destination: .compose)) {
                    VStack(spacing: 3) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .widgetAccentable()
                        Text("widget.action.compose")
                            .font(.system(size: 10, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.horizontal, 8)
                    .frame(width: 68, height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("widget.action.compose"))
                .foregroundStyle(palette.primaryTileForeground)
                .background(
                    palette.primaryTileFill,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(palette.primaryTileBorder, lineWidth: 0.75)
                }
                .shadow(color: palette.tileShadowColor, radius: 3, y: 1.5)
            }
        }
        .padding(16)
        .widgetURL(MoroWidgetDestination.profile.deepLinkURL)
    }
}

private struct MoroProfileStatCell: View {
    let value: Int
    let title: LocalizedStringKey
    let palette: MoroWidgetPalette
    var highlighted: Bool = false

    var body: some View {
        VStack(spacing: 1.5) {
            Text(value, format: .number.notation(.compactName))
                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(highlighted ? palette.accentTint : palette.inkPrimary)
                .lineLimit(1)
                .widgetAccentable(highlighted)

            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(palette.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview(as: .systemSmall) {
    MoroProfileCardWidget()
} timeline: {
    MoroWidgetEntry.placeholder
}

#Preview(as: .systemMedium) {
    MoroProfileCardWidget()
} timeline: {
    MoroWidgetEntry.placeholder
}
