//
//  MoroComfortWidget.swift
//  moroWidgets
//

import SwiftUI
import WidgetKit

struct MoroComfortWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MoroWidgetKind.comfort, provider: MoroComfortProvider()) { _ in
            MoroComfortWidgetView()
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("widget.comfort.name")
        .description("widget.comfort.description")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct MoroComfortEntry: TimelineEntry {
    let date: Date
}

private struct MoroComfortProvider: TimelineProvider {
    func placeholder(in context: Context) -> MoroComfortEntry {
        MoroComfortEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (MoroComfortEntry) -> Void) {
        completion(MoroComfortEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MoroComfortEntry>) -> Void) {
        completion(Timeline(entries: [MoroComfortEntry(date: Date())], policy: .never))
    }
}

private struct MoroComfortWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let isPanorama = family == .systemMedium
        let artwork = Image(isPanorama ? .gardenRainforest : .gardenLeaf)

        Color.clear
            .overlay {
                artwork
                    .resizable()
                    .widgetAccentedRenderingMode(.desaturated)
                    .scaledToFill()
            }
            .clipped()
            .unredacted()
            .widgetURL(MoroWidgetDestination.home.deepLinkURL)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isPanorama ? Text("widget.comfort.rainforest") : Text("widget.comfort.leaf"))
    }
}

#Preview(as: .systemSmall) {
    MoroComfortWidget()
} timeline: {
    MoroComfortEntry(date: Date())
}

#Preview(as: .systemMedium) {
    MoroComfortWidget()
} timeline: {
    MoroComfortEntry(date: Date())
}
