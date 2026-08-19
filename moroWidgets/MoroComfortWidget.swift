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
                    MoroComfortBackground()
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
        Group {
            if family == .systemMedium {
                mediumContent
            } else {
                smallContent
            }
        }
        .foregroundStyle(MoroComfortPalette.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("widget.comfort.accessibility"))
    }

    private var smallContent: some View {
        ZStack(alignment: .topTrailing) {
            MoroComfortBloom(size: 50)

            VStack(alignment: .leading, spacing: 0) {
                comfortEyebrow
                    .padding(.trailing, 48)

                Spacer(minLength: 12)

                Text("widget.comfort.message")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)

                Text("widget.comfort.subtitle")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(MoroComfortPalette.ink.opacity(0.58))
                    .lineLimit(2)
                    .padding(.top, 5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(16)
    }

    private var mediumContent: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 0) {
                comfortEyebrow

                Spacer(minLength: 8)

                Text("widget.comfort.message")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .lineLimit(2)

                Text("widget.comfort.subtitle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MoroComfortPalette.ink.opacity(0.58))
                    .lineLimit(1)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            MoroComfortBloom(size: 88)
                .padding(.trailing, 12)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var comfortEyebrow: some View {
        HStack(spacing: 5) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 8, weight: .bold))
            Text("widget.comfort.eyebrow")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.8)
                .lineLimit(1)
        }
        .foregroundStyle(MoroComfortPalette.ink.opacity(0.64))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.48), in: Capsule())
        .overlay {
            Capsule().stroke(Color.white.opacity(0.56), lineWidth: 1)
        }
    }
}

private enum MoroComfortPalette {
    static let ink = Color(red: 0.23, green: 0.18, blue: 0.34)
    static let lavender = Color(red: 0.70, green: 0.60, blue: 0.90)
    static let blush = Color(red: 0.98, green: 0.68, blue: 0.72)
    static let butter = Color(red: 1.00, green: 0.84, blue: 0.52)
}

private struct MoroComfortBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.96, blue: 0.92),
                    Color(red: 0.94, green: 0.90, blue: 1.00),
                    Color(red: 0.85, green: 0.93, blue: 1.00),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.46))
                .frame(width: 180, height: 180)
                .offset(x: 120, y: -80)

            Circle()
                .fill(MoroComfortPalette.blush.opacity(0.12))
                .frame(width: 125, height: 125)
                .offset(x: -120, y: 95)

            Circle()
                .stroke(Color.white.opacity(0.44), lineWidth: 1)
                .frame(width: 205, height: 205)
                .offset(x: 105, y: 105)

            Circle()
                .fill(MoroComfortPalette.butter.opacity(0.32))
                .frame(width: 9, height: 9)
                .offset(x: -48, y: -63)

            Circle()
                .fill(MoroComfortPalette.lavender.opacity(0.26))
                .frame(width: 14, height: 14)
                .offset(x: 46, y: 69)
        }
    }
}

private struct MoroComfortBloom: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.28))
                .frame(width: size, height: size)

            ForEach(0..<6, id: \.self) { index in
                Capsule()
                    .fill(index.isMultiple(of: 2) ? MoroComfortPalette.blush : MoroComfortPalette.lavender)
                    .frame(width: size * 0.20, height: size * 0.40)
                    .offset(y: -size * 0.22)
                    .rotationEffect(.degrees(Double(index) * 60))
            }

            Circle()
                .fill(MoroComfortPalette.butter)
                .frame(width: size * 0.31, height: size * 0.31)
                .overlay {
                    Image(systemName: "sparkle")
                        .font(.system(size: size * 0.13, weight: .bold))
                        .foregroundStyle(MoroComfortPalette.ink.opacity(0.66))
                }
        }
        .frame(width: size, height: size)
        .shadow(color: MoroComfortPalette.lavender.opacity(0.22), radius: size * 0.16, y: size * 0.08)
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
