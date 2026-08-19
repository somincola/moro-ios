//
//  MoroWidgetDesign.swift
//  moroWidgets
//


import SwiftUI
import UIKit
import WidgetKit

struct MoroWidgetBackground: View {
    let variant: Variant

    enum Variant {
        case violet
        case midnight
        case profile
    }

    private var gradientColors: [Color] {
        switch variant {
        case .violet:
            return [Color(red: 0.11, green: 0.08, blue: 0.22), Color(red: 0.34, green: 0.14, blue: 0.46)]
        case .midnight:
            return [Color(red: 0.04, green: 0.09, blue: 0.17), Color(red: 0.08, green: 0.28, blue: 0.35)]
        case .profile:
            return [Color(red: 0.10, green: 0.12, blue: 0.30), Color(red: 0.34, green: 0.20, blue: 0.55)]
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.24), Color.white.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 90
                    )
                )
                .frame(width: 180, height: 180)
                .offset(x: 95, y: -70)

            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                .frame(width: 135, height: 135)
                .offset(x: -85, y: 95)
        }
    }
}

struct MoroWidgetAvatar: View {
    let account: MoroWidgetAccount?
    let avatarData: Data?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.14))

            if let avatarData, let image = UIImage(data: avatarData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let initial = account?.preferredName.first {
                Text(String(initial).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.white.opacity(0.75), lineWidth: max(1.5, size * 0.045))
        }
        .shadow(color: Color.black.opacity(0.28), radius: 10, y: 5)
        .widgetAccentable()
    }
}

struct MoroWidgetEmptyState: View {
    let title: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle().fill(Color.white.opacity(0.14))
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)

            Spacer(minLength: 0)

            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Text("widget.signIn.subtitle")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.68))
                .lineLimit(2)
        }
    }
}
