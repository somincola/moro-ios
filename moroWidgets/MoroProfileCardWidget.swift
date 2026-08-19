//
//  MoroProfileCardWidget.swift
//  moroWidgets
//

import AppIntents
import SwiftUI
import WidgetKit

struct MoroProfileCardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MoroWidgetKind.profileCard, provider: MoroWidgetProvider()) { entry in
            MoroProfileCardWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    MoroWidgetBackground(variant: .profile)
                }
        }
        .configurationDisplayName("widget.profile.name")
        .description("widget.profile.description")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

private struct MoroProfileCardWidgetView: View {
    let entry: MoroWidgetEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                profileContent(snapshot)
            } else {
                MoroWidgetEmptyState(title: "widget.signIn.title")
                    .padding(16)
            }
        }
        .privacySensitive()
    }

    private func profileContent(_ snapshot: MoroWidgetDataSnapshot) -> some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                MoroWidgetAvatar(account: snapshot.account, avatarData: entry.avatarData, size: 45)

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.account.preferredName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(snapshot.account.handle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.58))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 7) {
                MoroProfileStat(
                    value: snapshot.account.followersCount,
                    title: "widget.profile.followers"
                )
                MoroProfileStat(
                    value: snapshot.account.followingCount,
                    title: "widget.profile.following"
                )
            }

            Button(intent: OpenMoroDestinationIntent(destination: .compose)) {
                HStack(spacing: 7) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .bold))
                        .widgetAccentable()
                    Text("widget.action.compose")
                        .font(.caption.weight(.bold))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.58))
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 37)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("widget.action.compose"))
            .foregroundStyle(.white)
            .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
        }
        .padding(14)
    }
}

private struct MoroProfileStat: View {
    let value: Int
    let title: LocalizedStringKey

    var body: some View {
        VStack(spacing: 1) {
            Text(value, format: .number.notation(.compactName))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview(as: .systemSmall) {
    MoroProfileCardWidget()
} timeline: {
    MoroWidgetEntry.placeholder
}
