//
//  MoroOverviewWidget.swift
//  moroWidgets
//


import AppIntents
import SwiftUI
import WidgetKit

struct MoroOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MoroWidgetKind.overview, provider: MoroWidgetProvider()) { entry in
            MoroOverviewWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    MoroWidgetBackground(variant: .violet)
                }
        }
        .configurationDisplayName("widget.overview.name")
        .description("widget.overview.description")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct MoroOverviewWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MoroWidgetEntry

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

    private func smallContent(_ snapshot: MoroWidgetDataSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                MoroWidgetAvatar(account: snapshot.account, avatarData: entry.avatarData, size: 52)
                Spacer()
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(7)
                    .background(Color.white.opacity(0.08), in: Circle())
            }

            Spacer(minLength: 8)

            Text(snapshot.account.preferredName)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(snapshot.account.handle)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.58))
                .lineLimit(1)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                MoroOverviewActionButton(
                    destination: .compose,
                    icon: "square.and.pencil",
                    title: "widget.action.compose",
                    compact: true,
                    emphasized: true
                )
                MoroOverviewActionButton(
                    destination: .inbox,
                    icon: "tray.full.fill",
                    title: "widget.action.inbox",
                    badge: snapshot.unreadCount,
                    compact: true
                )
            }
        }
        .padding(16)
    }

    private func mediumContent(_ snapshot: MoroWidgetDataSnapshot) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    MoroWidgetAvatar(account: snapshot.account, avatarData: entry.avatarData, size: 58)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("widget.overview.greeting")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.58))
                        Text(snapshot.account.preferredName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(snapshot.account.handle)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.56))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text("widget.overview.caption")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 9) {
                MoroOverviewActionButton(
                    destination: .compose,
                    icon: "square.and.pencil",
                    title: "widget.action.compose",
                    emphasized: true
                )
                MoroOverviewActionButton(
                    destination: .inbox,
                    icon: "tray.full.fill",
                    title: "widget.action.inbox",
                    badge: snapshot.unreadCount
                )
            }
            .frame(width: 126)
        }
        .padding(18)
    }
}

private struct MoroOverviewActionButton: View {
    let destination: MoroWidgetDestination
    let icon: String
    let title: LocalizedStringKey
    var badge: Int?
    var compact = false
    var emphasized = false

    var body: some View {
        Button(intent: OpenMoroDestinationIntent(destination: destination)) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: compact ? 13 : 15, weight: .bold))
                    .widgetAccentable()

                if !compact {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 2)
                }

                if let badge, badge > 0 {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(.system(size: compact ? 8 : 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.24, green: 0.10, blue: 0.34))
                        .padding(.horizontal, 5)
                        .frame(minWidth: compact ? 17 : 20, minHeight: compact ? 17 : 20)
                        .background(.white, in: Capsule())
                }
            }
            .padding(.horizontal, compact ? 12 : 11)
            .frame(maxWidth: .infinity, minHeight: compact ? 40 : 49)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(accessibilityValue)
        .foregroundStyle(.white)
        .background(
            emphasized ? Color.white.opacity(0.22) : Color.white.opacity(0.10),
            in: RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                .stroke(Color.white.opacity(emphasized ? 0.20 : 0.08), lineWidth: 1)
        }
    }

    private var accessibilityValue: Text {
        guard let badge, badge > 0 else { return Text(verbatim: "") }
        return Text(badge, format: .number)
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
