//
//  MoroQuickActionsWidget.swift
//  moroWidgets
//
//  Tactile quick-launcher widget with labeled 2x2 Small grid,
//  asymmetric Bento Medium launchpad (Hero Compose + Search/Inbox/Home/Profile),
//  and Lock Screen quick-compose circular launcher.
//

import AppIntents
import SwiftUI
import WidgetKit

struct MoroQuickActionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MoroWidgetKind.quickActions, provider: MoroWidgetProvider()) { entry in
            MoroQuickActionsWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    MoroWidgetSurfaceBackground(accent: entry.snapshot?.accent ?? .default)
                }
        }
        .configurationDisplayName("widget.actions.name")
        .description("widget.actions.description")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
        .contentMarginsDisabled()
    }
}

private struct MoroQuickActionsWidgetView: View {
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
            switch family {
            case .accessoryCircular:
                accessoryCircularCompose
            case .systemMedium:
                if let snapshot = entry.snapshot {
                    mediumContent(snapshot)
                } else {
                    MoroWidgetEmptyState(title: "widget.signIn.title")
                        .padding(16)
                }
            default:
                if let snapshot = entry.snapshot {
                    smallContent(snapshot)
                } else {
                    MoroWidgetEmptyState(title: "widget.signIn.title")
                        .padding(16)
                }
            }
        }
        .privacySensitive()
    }

    // MARK: - Home Screen Small (2x2 Labeled Tiles)

    private func smallContent(_ snapshot: MoroWidgetDataSnapshot) -> some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                MoroWidgetAvatar(
                    account: snapshot.account,
                    avatarData: entry.avatarData,
                    size: 24,
                    palette: palette
                )

                Text(snapshot.account.preferredName)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(palette.inkPrimary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                MoroWidgetElephantMark(
                    size: 16,
                    primaryColor: palette.inkSecondary,
                    secondaryColor: palette.inkTertiary
                )
                .widgetAccentable()
            }

            VStack(spacing: 7) {
                HStack(spacing: 7) {
                    MoroSmallActionTile(
                        destination: .compose,
                        icon: "square.and.pencil",
                        title: "widget.action.compose",
                        palette: palette,
                        emphasized: true
                    )

                    MoroSmallActionTile(
                        destination: .search,
                        icon: "magnifyingglass",
                        title: "widget.action.search",
                        palette: palette
                    )
                }

                HStack(spacing: 7) {
                    MoroSmallActionTile(
                        destination: .inbox,
                        icon: "bell.fill",
                        title: "widget.action.inbox",
                        badge: snapshot.unreadCount,
                        palette: palette
                    )

                    MoroSmallActionTile(
                        destination: .profile,
                        icon: "person.fill",
                        title: "widget.action.profile",
                        palette: palette
                    )
                }
            }
        }
        .padding(14)
        .widgetURL(MoroWidgetDestination.home.deepLinkURL)
    }

    // MARK: - Home Screen Medium (Asymmetric Bento Launchpad)

    private func mediumContent(_ snapshot: MoroWidgetDataSnapshot) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                MoroWidgetAvatar(
                    account: snapshot.account,
                    avatarData: entry.avatarData,
                    size: 24,
                    palette: palette
                )

                Text(snapshot.account.preferredName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.inkPrimary)
                    .lineLimit(1)

                Text(snapshot.account.handle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.inkSecondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                MoroWidgetElephantMark(
                    size: 17,
                    primaryColor: palette.inkSecondary,
                    secondaryColor: palette.inkTertiary
                )
                .widgetAccentable()
            }

            HStack(spacing: 8) {
                heroComposeCard

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        MoroMediumBentoTile(
                            destination: .search,
                            icon: "magnifyingglass",
                            title: "widget.action.search",
                            palette: palette
                        )

                        MoroMediumBentoTile(
                            destination: .inbox,
                            icon: "bell.fill",
                            title: "widget.action.inbox",
                            badge: snapshot.unreadCount,
                            palette: palette
                        )
                    }

                    HStack(spacing: 8) {
                        MoroMediumBentoTile(
                            destination: .home,
                            icon: "house.fill",
                            title: "widget.action.home",
                            palette: palette
                        )

                        MoroMediumBentoTile(
                            destination: .profile,
                            icon: "person.fill",
                            title: "widget.action.profile",
                            palette: palette
                        )
                    }
                }
            }
        }
        .padding(15)
        .widgetURL(MoroWidgetDestination.home.deepLinkURL)
    }

    private var heroComposeCard: some View {
        Button(intent: OpenMoroDestinationIntent(destination: .compose)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18, weight: .semibold))
                        .widgetAccentable()
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.primaryTileSecondaryForeground)
                }

                Spacer(minLength: 8)

                Text("widget.action.compose")
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("widget.actions.shortTitle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.primaryTileSecondaryForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 1)
            }
            .padding(12)
            .frame(minWidth: 106, maxWidth: 106, maxHeight: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("widget.action.compose"))
        .foregroundStyle(palette.primaryTileForeground)
        .background(
            palette.primaryTileFill,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.primaryTileBorder, lineWidth: 0.75)
        }
        .shadow(color: palette.tileShadowColor, radius: 4, y: 2)
    }

    // MARK: - Lock Screen Circular Quick Compose

    private var accessoryCircularCompose: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "square.and.pencil")
                .font(.system(size: 21, weight: .semibold))
                .widgetAccentable()
        }
        .widgetURL(MoroWidgetDestination.compose.deepLinkURL)
        .accessibilityLabel(Text("widget.action.compose"))
    }
}

private struct MoroSmallActionTile: View {
    let destination: MoroWidgetDestination
    let icon: String
    let title: LocalizedStringKey
    var badge: Int? = nil
    let palette: MoroWidgetPalette
    var emphasized: Bool = false

    var body: some View {
        Button(intent: OpenMoroDestinationIntent(destination: destination)) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .widgetAccentable(emphasized)

                    if let badge, badge > 0 {
                        MoroWidgetUnreadPill(count: badge, palette: palette, compact: true)
                            .scaleEffect(0.82, anchor: .topTrailing)
                            .offset(x: 10, y: -5)
                    }
                }

                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(
                        emphasized ? palette.primaryTileForeground : palette.inkSecondary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .foregroundStyle(emphasized ? palette.primaryTileForeground : palette.inkPrimary)
        .background(
            emphasized ? palette.primaryTileFill : palette.tileSurface,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    emphasized ? palette.primaryTileBorder : palette.tileBorder,
                    lineWidth: 0.75
                )
        }
        .shadow(color: palette.tileShadowColor, radius: 2.5, y: 1)
    }
}

private struct MoroMediumBentoTile: View {
    let destination: MoroWidgetDestination
    let icon: String
    let title: LocalizedStringKey
    var badge: Int? = nil
    let palette: MoroWidgetPalette

    var body: some View {
        Button(intent: OpenMoroDestinationIntent(destination: destination)) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    tileIcon
                    tileTitle.fixedSize()
                    unreadBadge
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        tileIcon
                        Spacer(minLength: 0)
                        unreadBadge
                    }
                    tileTitle.minimumScaleFactor(0.75)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .background(
            palette.tileSurface,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.tileBorder, lineWidth: 0.75)
        }
        .shadow(color: palette.tileShadowColor, radius: 2.5, y: 1)
    }

    private var tileIcon: some View {
        Image(systemName: icon)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(palette.inkPrimary)
    }

    private var tileTitle: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.inkPrimary)
            .lineLimit(1)
    }

    @ViewBuilder private var unreadBadge: some View {
        if let badge, badge > 0 {
            MoroWidgetUnreadPill(count: badge, palette: palette, compact: true)
        }
    }
}

#Preview(as: .systemSmall) {
    MoroQuickActionsWidget()
} timeline: {
    MoroWidgetEntry.placeholder
}

#Preview(as: .systemMedium) {
    MoroQuickActionsWidget()
} timeline: {
    MoroWidgetEntry.placeholder
}
