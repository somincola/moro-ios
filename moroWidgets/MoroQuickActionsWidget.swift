//
//  MoroQuickActionsWidget.swift
//  moroWidgets
//


import AppIntents
import SwiftUI
import WidgetKit

struct MoroQuickActionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MoroWidgetKind.quickActions, provider: MoroWidgetProvider()) { entry in
            MoroQuickActionsWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    MoroWidgetBackground(variant: .midnight)
                }
        }
        .configurationDisplayName("widget.actions.name")
        .description("widget.actions.description")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct MoroQuickActionsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MoroWidgetEntry

    private var actions: [MoroWidgetAction] {
        [
            MoroWidgetAction(destination: .compose, icon: "plus", title: "widget.action.compose", emphasized: true),
            MoroWidgetAction(destination: .search, icon: "magnifyingglass", title: "widget.action.search"),
            MoroWidgetAction(
                destination: .inbox,
                icon: "tray.full.fill",
                title: "widget.action.inbox",
                badge: entry.snapshot?.unreadCount
            ),
            MoroWidgetAction(destination: .profile, icon: "person.fill", title: "widget.action.profile"),
            MoroWidgetAction(
                destination: .home,
                icon: "house.fill",
                title: "widget.action.home"
            ),
        ]
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

    private func smallContent(_ snapshot: MoroWidgetDataSnapshot) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                MoroWidgetAvatar(account: snapshot.account, avatarData: entry.avatarData, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.account.preferredName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("widget.actions.shortTitle")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.58))
                }
                Spacer(minLength: 0)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Array(actions.prefix(4))) { action in
                    MoroWidgetActionButton(action: action, compact: true)
                }
            }
        }
        .padding(14)
    }

    private func mediumContent(_ snapshot: MoroWidgetDataSnapshot) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                MoroWidgetAvatar(account: snapshot.account, avatarData: entry.avatarData, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.account.preferredName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("widget.actions.title")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.58))
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.46))
            }

            HStack(spacing: 9) {
                ForEach(actions) { action in
                    MoroWidgetActionButton(action: action, compact: false)
                }
            }
        }
        .padding(16)
    }
}

private struct MoroWidgetAction: Identifiable {
    let destination: MoroWidgetDestination
    let icon: String
    let title: LocalizedStringKey
    var badge: Int?
    var emphasized = false

    var id: MoroWidgetDestination { destination }
}

private struct MoroWidgetActionButton: View {
    let action: MoroWidgetAction
    let compact: Bool

    var body: some View {
        Button(intent: OpenMoroDestinationIntent(destination: action.destination)) {
            if compact {
                actionIcon(size: 18)
                .frame(maxWidth: .infinity, minHeight: 38)
            } else {
                VStack(spacing: 6) {
                    actionIcon(size: 15)
                    Text(action.title)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, minHeight: 64)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(action.title))
        .foregroundStyle(.white)
        .background(
            action.emphasized ? Color.white.opacity(0.23) : Color.white.opacity(0.09),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.white.opacity(action.emphasized ? 0.2 : 0.07), lineWidth: 1)
        }
    }

    private func actionIcon(size: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: action.icon)
                .font(.system(size: size, weight: .bold))
                .frame(width: 18, height: 18)
                .widgetAccentable()

            if let badge = action.badge, badge > 0 {
                Text(badge > 99 ? "99+" : "\(badge)")
                    .font(.system(size: 6.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.06, green: 0.16, blue: 0.2))
                    .padding(.horizontal, 3)
                    .frame(minWidth: 11, minHeight: 11)
                    .background(.white, in: Capsule())
                    .offset(x: 6, y: -5)
            }
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
