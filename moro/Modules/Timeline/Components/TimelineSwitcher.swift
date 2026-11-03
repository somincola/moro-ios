//
//  TimelineSwitcher.swift
//  moro
//
//  Timeline selector presented as a compact menu in the root header.
//

import SwiftUI

/// Available timeline types
enum TimelineType: Hashable, Identifiable {
    case home
    case local
    case federated
    /// A user list pinned into the home switcher.
    case list(id: String, title: String)

    /// The three built-in timelines that are always present in the switcher.
    static let builtin: [TimelineType] = [.home, .local, .federated]

    var id: String {
        switch self {
        case .home: return "home"
        case .local: return "local"
        case .federated: return "federated"
        case .list(let id, _): return "list-\(id)"
        }
    }

    var localizedTitle: String {
        switch self {
        case .home: return MoroL10n.TimelineSwitcher.home
        case .local: return MoroL10n.TimelineSwitcher.local
        case .federated: return MoroL10n.TimelineSwitcher.federated
        case .list(_, let title): return title
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .local: return "building.2"
        case .federated: return "globe"
        case .list: return "list.bullet"
        }
    }

    /// The menu's glyph in iPhone Duo's vertical side bar, which shows no text. Following uses
    /// people rather than its house, which would repeat the Home tab's below it.
    var sideBarIcon: String {
        switch self {
        case .home: return "person.2"
        default: return icon
        }
    }

    var description: String {
        switch self {
        case .home: return MoroL10n.TimelineSwitcher.homeDesc
        case .local: return MoroL10n.TimelineSwitcher.localDesc
        case .federated: return MoroL10n.TimelineSwitcher.federatedDesc
        case .list(_, let title): return title
        }
    }

    /// Corresponding StreamWatcher stream type
    var streamType: StreamWatcher.Stream {
        switch self {
        case .home: return .user
        case .local: return .local
        case .federated: return .federated
        case .list: return .list
        }
    }
}

/// Compact timeline selector with one source of truth and no horizontal paging gesture.
struct TimelineSwitcher: View {
    enum Style {
        /// The custom floating header.
        case header
        /// A system toolbar item: the title in a horizontal bar, the timeline's icon in the
        /// vertical side bar (which shows no text).
        case toolbar
    }

    @Binding var selectedTimeline: TimelineType
    /// Pinned timelines appended after the built-in three.
    var pinnedTimelines: [TimelineType] = []
    var style: Style = .header
    var onManageLists: (() -> Void)?
    var onManageTopics: (() -> Void)?
    @Environment(\.moroTheme) private var theme

    private var items: [TimelineType] {
        TimelineType.builtin + pinnedTimelines
    }

    var body: some View {
        Menu {
            ForEach(items) { type in
                Button {
                    guard selectedTimeline != type else { return }
                    selectedTimeline = type
                } label: {
                    Label(
                        type.localizedTitle,
                        systemImage: selectedTimeline == type ? "checkmark" : type.icon
                    )
                }
            }

            if let onManageLists {
                Divider()

                Button(action: onManageLists) {
                    Label(MoroL10n.Navigation.lists, systemImage: "list.bullet.rectangle")
                }
            }
            if let onManageTopics {
                Button(action: onManageTopics) {
                    Label(MoroL10n.Topics.title, systemImage: "number")
                }
                .accessibilityIdentifier("topics.menu")
            }
        } label: {
            if style == .toolbar {
                ToolbarAxisReader { isVertical in
                    if isVertical {
                        Image(systemName: selectedTimeline.sideBarIcon)
                    } else {
                        titleLabel
                    }
                }
            } else {
                titleLabel
            }
        }
        .accessibilityLabel(MoroL10n.TimelineSwitcher.accessibility)
        .accessibilityValue(selectedTimeline.localizedTitle)
    }

    private var titleLabel: some View {
        HStack(spacing: 8) {
            Text(selectedTimeline.localizedTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Image(systemName: "chevron.down")
                .moroScaledFont(size: 11, weight: .semibold, relativeTo: .caption)
        }
        .moroScaledFont(size: 15, weight: .semibold)
        .foregroundStyle(theme.colors.textPrimary)
        .padding(.horizontal, 8)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// Tells toolbar content whether it is laid out in a vertical side bar (iPhone Duo).
struct ToolbarAxisReader<Content: View>: View {
    @ViewBuilder let content: (_ isVertical: Bool) -> Content

    var body: some View {
        // The vertical toolbar edge is an iOS 27.1 SDK API (Swift 6.4); older toolchains,
        // such as CI's Xcode 26, build without it and never run on an iPhone Duo.
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            VerticalToolbarEdgeReader(content: content)
        } else {
            content(false)
        }
        #else
        content(false)
        #endif
    }
}

#if compiler(>=6.4)
@available(iOS 27.1, *)
private struct VerticalToolbarEdgeReader<Content: View>: View {
    @Environment(\.toolbarVerticalEdge) private var verticalEdge
    let content: (Bool) -> Content

    var body: some View { content(verticalEdge != nil) }
}
#endif

#Preview {
    @Previewable @State var selectedTimeline: TimelineType = .home

    return VStack {
        TimelineSwitcher(selectedTimeline: $selectedTimeline)
    }
    .moroTheme(MoroTheme())
}
