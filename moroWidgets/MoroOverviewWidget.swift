//
//  MoroOverviewWidget.swift
//  moroWidgets
//
//  Editorial account overview widget supporting Home Screen (Small, Medium)
//  and Lock Screen (Accessory Circular, Accessory Rectangular).
//

import AppIntents
import SwiftUI
import WidgetKit

struct MoroOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MoroWidgetKind.overview, provider: MoroWidgetProvider()) { entry in
            MoroOverviewWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    MoroWidgetSurfaceBackground(accent: entry.snapshot?.accent ?? .default)
                }
        }
        .configurationDisplayName("widget.overview.name")
        .description("widget.overview.description")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

private struct MoroOverviewWidgetView: View {
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
                accessoryCircularContent
            case .accessoryRectangular:
                accessoryRectangularContent
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

    // MARK: - Home Screen Small

    private func smallContent(_ snapshot: MoroWidgetDataSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                MoroWidgetAvatar(
                    account: snapshot.account,
                    avatarData: entry.avatarData,
                    size: 42,
                    palette: palette
                )

                Spacer(minLength: 6)

                if snapshot.unreadCount > 0 {
                    MoroWidgetUnreadPill(count: snapshot.unreadCount, palette: palette)
                } else {
                    MoroWidgetBrandBadge(palette: palette, size: 26)
                }
            }

            Spacer(minLength: 8)

            Text(snapshot.account.preferredName)
                .font(.system(size: 15.5, weight: .bold))
                .foregroundStyle(palette.inkPrimary)
                .lineLimit(1)

            Text(snapshot.account.handle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.inkSecondary)
                .lineLimit(1)
                .padding(.top, 1)

            Spacer(minLength: 10)

            HStack(spacing: 8) {
                MoroOverviewTileButton(
                    destination: .compose,
                    icon: "square.and.pencil",
                    title: "widget.action.compose",
                    palette: palette,
                    emphasized: true,
                    showsLabel: false
                )

                MoroOverviewTileButton(
                    destination: .inbox,
                    icon: snapshot.unreadCount > 0 ? "bell.badge.fill" : "bell.fill",
                    title: "widget.action.inbox",
                    badge: snapshot.unreadCount,
                    palette: palette,
                    emphasized: false,
                    showsLabel: false
                )
            }
        }
        .padding(15)
        .widgetURL(MoroWidgetDestination.home.deepLinkURL)
    }

    // MARK: - Home Screen Medium

    private func mediumContent(_ snapshot: MoroWidgetDataSnapshot) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    MoroWidgetElephantMark(
                        size: 15,
                        primaryColor: palette.inkPrimary,
                        secondaryColor: palette.inkSecondary
                    )
                    .widgetAccentable()

                    Text("widget.comfort.eyebrow")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(palette.inkSecondary)

                    Spacer(minLength: 4)

                    statusPill(unreadCount: snapshot.unreadCount)
                }

                Spacer(minLength: 8)

                HStack(spacing: 10) {
                    MoroWidgetAvatar(
                        account: snapshot.account,
                        avatarData: entry.avatarData,
                        size: 46,
                        palette: palette
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.account.preferredName)
                            .font(.system(size: 16.5, weight: .bold))
                            .foregroundStyle(palette.inkPrimary)
                            .lineLimit(1)

                        Text(snapshot.account.handle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.inkSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text("widget.overview.caption")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(palette.inkSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                MoroOverviewTileButton(
                    destination: .compose,
                    icon: "square.and.pencil",
                    title: "widget.action.compose",
                    palette: palette,
                    emphasized: true,
                    showsLabel: true,
                    showsArrow: true
                )
                .frame(height: 46)

                HStack(spacing: 8) {
                    MoroOverviewCompactSquareTile(
                        destination: .search,
                        icon: "magnifyingglass",
                        title: "widget.action.search",
                        palette: palette
                    )

                    MoroOverviewCompactSquareTile(
                        destination: .inbox,
                        icon: "bell.fill",
                        title: "widget.action.inbox",
                        badge: snapshot.unreadCount,
                        palette: palette
                    )
                }
                .frame(maxHeight: .infinity)
            }
            .frame(width: 142)
        }
        .padding(16)
        .widgetURL(MoroWidgetDestination.home.deepLinkURL)
    }

    private func statusPill(unreadCount: Int) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(unreadCount > 0 ? palette.accentTint : palette.inkTertiary.opacity(0.6))
                .frame(width: 5.5, height: 5.5)
                .widgetAccentable()

            if unreadCount > 0 {
                Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.accentTint)
            } else {
                Text("widget.overview.quiet")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(palette.inkSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(
            unreadCount > 0 ? palette.accentSubtleFill : palette.subtleSurface,
            in: Capsule()
        )
    }

    // MARK: - Lock Screen Accessories

    private var accessoryCircularContent: some View {
        let unread = entry.snapshot?.unreadCount ?? 0
        let destination: MoroWidgetDestination = unread > 0 ? .inbox : .home

        return ZStack {
            AccessoryWidgetBackground()

            if unread > 0 {
                VStack(spacing: 1) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .widgetAccentable()
                    Text(unread > 99 ? "99+" : "\(unread)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            } else {
                MoroWidgetElephantMark(size: 28, primaryColor: .primary)
                    .widgetAccentable()
            }
        }
        .widgetURL(destination.deepLinkURL)
    }

    private var accessoryRectangularContent: some View {
        let snapshot = entry.snapshot
        let unread = snapshot?.unreadCount ?? 0

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                MoroWidgetElephantMark(size: 13, primaryColor: .primary)
                    .widgetAccentable()
                Text("widget.comfort.eyebrow")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if unread > 0 {
                    Text(unread > 99 ? "99+" : "\(unread)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .widgetAccentable()
                }
            }

            if let snapshot {
                Text(snapshot.account.preferredName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                if unread > 0 {
                    Text(verbatim: String.localizedStringWithFormat(
                        String(localized: "widget.overview.unreadStatus"), Int64(unread)))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("widget.overview.allCaughtUp")
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("widget.signIn.title")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL((unread > 0 ? MoroWidgetDestination.inbox : .home).deepLinkURL)
    }
}

private struct MoroOverviewTileButton: View {
    let destination: MoroWidgetDestination
    let icon: String
    let title: LocalizedStringKey
    var badge: Int? = nil
    let palette: MoroWidgetPalette
    var emphasized: Bool = false
    var showsLabel: Bool = true
    var showsArrow: Bool = false

    var body: some View {
        Button(intent: OpenMoroDestinationIntent(destination: destination)) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: showsLabel ? 14 : 15, weight: .semibold))
                    .widgetAccentable(emphasized)

                if showsLabel {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 2)
                }

                if showsArrow {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.primaryTileSecondaryForeground)
                }

                if let badge, badge > 0, !emphasized {
                    MoroWidgetUnreadPill(count: badge, palette: palette, compact: true)
                }
            }
            .padding(.horizontal, showsLabel ? 12 : 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: showsLabel ? .leading : .center)
            .frame(minHeight: 38)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(accessibilityValue)
        .foregroundStyle(emphasized ? palette.primaryTileForeground : palette.inkPrimary)
        .background(
            emphasized ? palette.primaryTileFill : palette.tileSurface,
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(
                    emphasized ? palette.primaryTileBorder : palette.tileBorder,
                    lineWidth: 0.75
                )
        }
        .shadow(color: palette.tileShadowColor, radius: 3, y: 1.5)
    }

    private var accessibilityValue: Text {
        guard let badge, badge > 0 else { return Text(verbatim: "") }
        return Text(badge, format: .number)
    }
}

private struct MoroOverviewCompactSquareTile: View {
    let destination: MoroWidgetDestination
    let icon: String
    let title: LocalizedStringKey
    var badge: Int? = nil
    let palette: MoroWidgetPalette

    var body: some View {
        Button(intent: OpenMoroDestinationIntent(destination: destination)) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 20, height: 20)

                    if let badge, badge > 0 {
                        Circle()
                            .fill(palette.accentTint)
                            .frame(width: 7, height: 7)
                            .overlay {
                                Circle().stroke(palette.tileSurface, lineWidth: 1.2)
                            }
                            .offset(x: 3, y: -2)
                            .widgetAccentable()
                    }
                }

                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .foregroundStyle(palette.inkPrimary)
        .background(palette.tileSurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(palette.tileBorder, lineWidth: 0.75)
        }
        .shadow(color: palette.tileShadowColor, radius: 3, y: 1.5)
    }
}

#Preview(as: .systemSmall) {
    MoroOverviewWidget()
} timeline: {
    MoroWidgetEntry.placeholder
}

#Preview(as: .systemMedium) {
    MoroOverviewWidget()
} timeline: {
    MoroWidgetEntry.placeholder
}
