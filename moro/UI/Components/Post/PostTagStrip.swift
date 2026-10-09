//
//  PostTagStrip.swift
//  moro
//
//  Horizontally scrollable status hashtags sourced from the Mastodon tags field.
//

import SwiftUI

struct PostTagStrip: View {
    struct DisplayTag: Equatable, Identifiable {
        let name: String
        let url: URL

        var id: String {
            "\(name.lowercased())|\(url.absoluteString)"
        }
    }

    let tags: [Status.Tag]
    var onTagTap: ((String, URL) -> Void)? = nil

    @Environment(\.moroTheme) private var theme
    @Environment(\.openURL) private var openURL

    private var displayTags: [DisplayTag] {
        Self.displayTags(from: tags)
    }

    @ViewBuilder
    var body: some View {
        if !displayTags.isEmpty {
            ScrollView(.horizontal) {
                LazyHStack(spacing: theme.spacing.xs) {
                    ForEach(displayTags) { tag in
                        Button {
                            if let onTagTap {
                                onTagTap(tag.name, tag.url)
                            } else {
                                openURL(tag.url)
                            }
                        } label: {
                            Text("#\(tag.name)")
                                .font(theme.typography.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(theme.colors.textPrimary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, theme.spacing.s)
                                .padding(.vertical, theme.spacing.xs)
                                .background {
                                    Capsule(style: .continuous)
                                        .fill(theme.colors.primary50)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("#\(tag.name)")
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func displayTags(from tags: [Status.Tag]) -> [DisplayTag] {
        var seenNames = Set<String>()
        var seenURLs = Set<String>()
        var result: [DisplayTag] = []

        for tag in tags {
            let name = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            let normalizedName = name.lowercased()
            let normalizedURL = tag.url.absoluteString.lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !seenNames.contains(normalizedName),
                !seenURLs.contains(normalizedURL)
            else {
                continue
            }

            seenNames.insert(normalizedName)
            seenURLs.insert(normalizedURL)
            result.append(DisplayTag(name: name, url: tag.url))
        }

        return result
    }
}
