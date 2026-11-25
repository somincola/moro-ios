//
//  QuoteShowcaseHarnessView.swift
//  moro
//
//  Debug-only offline UI test harness verifying the X-inspired quote card layout:
//  Text -> Main Media -> Quoted Post Card (left media thumbnail + +N gallery viewer).
//

#if DEBUG
import SDWebImage
import SwiftUI
import UIKit

struct QuoteShowcaseHarnessView: View {
    var body: some View {
        QuoteShowcaseHarnessContent()
    }
}

private struct QuoteShowcaseHarnessContent: View {
    @State private var posts: [Status] = []
    @State private var lastQuotedTap = "none"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Text("quoteTap:\(lastQuotedTap)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, MoroLayoutMetrics.contentHorizontalInset)
                .padding(.vertical, 8)
                .accessibilityIdentifier("quoteShowcase.tapResult")

            MoroDivider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(posts) { post in
                        PostCard(
                            status: post,
                            actions: PostActions(
                                navigation: PostNavigationActionCenter.Handlers(
                                    onAvatarTap: {},
                                    onUsernameTap: {},
                                    onImageTap: { _ in },
                                    onMentionTap: { _, _ in false },
                                    onHashtagTap: { _, _ in },
                                    onQuotedStatusTap: { quoted in
                                        lastQuotedTap = quoted.id
                                    },
                                    onBoostUserTap: {},
                                    onReplyToUserTap: { _ in },
                                    onTapDetail: {}
                                )
                            ),
                            showToolbar: true
                        )
                        .padding(.horizontal, MoroLayoutMetrics.contentHorizontalInset)
                        .padding(.vertical, 12)
                        .accessibilityIdentifier("quoteShowcase.post.\(post.id)")

                        MoroDivider()
                    }
                }
            }
        }
        .background(colorScheme == .dark ? Color(hex: 0x16181A) : .white)
        .moroTheme(MoroTheme(colorScheme: colorScheme, accent: .monochrome))
        .task {
            posts = await QuoteShowcaseFixtures.buildPosts()
        }
    }
}

@MainActor
private enum QuoteShowcaseFixtures {
    private static let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("QuoteShowcaseFixtures", isDirectory: true)

    static func buildPosts() async -> [Status] {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let mainBanner = await makeFixtureImage(
            name: "main-banner.png",
            size: CGSize(width: 640, height: 360),
            topColor: UIColor(red: 0.96, green: 0.94, blue: 0.87, alpha: 1),
            bottomColor: UIColor(red: 0.90, green: 0.86, blue: 0.72, alpha: 1),
            label: "Main Post Photo"
        )
        let quotePhoto1 = await makeFixtureImage(
            name: "quote-1.png",
            size: CGSize(width: 480, height: 480),
            topColor: UIColor(red: 0.24, green: 0.37, blue: 0.56, alpha: 1),
            bottomColor: UIColor(red: 0.14, green: 0.22, blue: 0.36, alpha: 1),
            label: "Quote Photo 1"
        )
        let quotePhoto2 = await makeFixtureImage(
            name: "quote-2.png",
            size: CGSize(width: 480, height: 480),
            topColor: UIColor(red: 0.30, green: 0.52, blue: 0.42, alpha: 1),
            bottomColor: UIColor(red: 0.18, green: 0.34, blue: 0.28, alpha: 1),
            label: "Quote Photo 2"
        )
        let quotePhoto3 = await makeFixtureImage(
            name: "quote-3.png",
            size: CGSize(width: 480, height: 480),
            topColor: UIColor(red: 0.58, green: 0.36, blue: 0.34, alpha: 1),
            bottomColor: UIColor(red: 0.36, green: 0.20, blue: 0.20, alpha: 1),
            label: "Quote Photo 3"
        )
        let emojiURL = await makeFixtureImage(
            name: "emoji-cat.png",
            size: CGSize(width: 64, height: 64),
            topColor: UIColor.systemOrange,
            bottomColor: UIColor.systemYellow,
            label: ":)"
        )

        let author = Account(
            id: "showcase-author",
            username: "acacius",
            acct: "acacius",
            displayName: "acacius",
            note: "",
            avatar: "",
            avatarStatic: "",
            header: "",
            headerStatic: "",
            followersCount: 120,
            followingCount: 80,
            statusesCount: 42
        )
        let quotedAuthor = Account(
            id: "showcase-quoted-author",
            username: "mrfish",
            acct: "mrfish@mastodon.social",
            displayName: "鱼哥",
            note: "",
            avatar: "",
            avatarStatic: "",
            header: "",
            headerStatic: "",
            followersCount: 520,
            followingCount: 95,
            statusesCount: 310
        )

        let customEmoji = Status.Emoji(shortcode: "catjoy", url: emojiURL, staticURL: emojiURL)

        let quotedWithThreePhotos = Status(
            id: "quoted-multi-media",
            content: "<p>在设计重构之后 :catjoy: 左侧展示缩略图与 +N 角标。</p><p>点击图片可直接打开全屏查看并左右滑动浏览全部照片。</p>",
            createdAt: Date().addingTimeInterval(-86_400),
            account: quotedAuthor,
            mediaAttachments: [
                Status.Attachment(
                    id: "q-img-1",
                    type: "image",
                    url: quotePhoto1,
                    previewURL: quotePhoto1,
                    description: "First quoted photo",
                    meta: .init(original: .init(width: 480, height: 480, aspect: 1), small: nil)
                ),
                Status.Attachment(
                    id: "q-img-2",
                    type: "image",
                    url: quotePhoto2,
                    previewURL: quotePhoto2,
                    description: "Second quoted photo",
                    meta: .init(original: .init(width: 480, height: 480, aspect: 1), small: nil)
                ),
                Status.Attachment(
                    id: "q-img-3",
                    type: "image",
                    url: quotePhoto3,
                    previewURL: quotePhoto3,
                    description: "Third quoted photo",
                    meta: .init(original: .init(width: 480, height: 480, aspect: 1), small: nil)
                ),
            ],
            favouritesCount: 12,
            reblogsCount: 3,
            repliesCount: 2,
            bookmarked: false,
            favourited: false,
            reblogged: false,
            emojis: [customEmoji]
        )

        let postWithMediaAndQuote = Status(
            id: "post-media-before-quote",
            content: "<p>测试优化引用帖子样式：正文 → 主贴配图 → 引用贴子卡片 👍</p>",
            createdAt: Date().addingTimeInterval(-240),
            account: author,
            mediaAttachments: [
                Status.Attachment(
                    id: "main-img-1",
                    type: "image",
                    url: mainBanner,
                    previewURL: mainBanner,
                    description: "Main post banner",
                    meta: .init(original: .init(width: 640, height: 360, aspect: 16.0 / 9.0), small: nil)
                )
            ],
            favouritesCount: 8,
            reblogsCount: 2,
            repliesCount: 1,
            bookmarked: false,
            favourited: false,
            reblogged: false,
            quote: Status.Quote(state: .accepted, quotedStatus: quotedWithThreePhotos)
        )

        let textOnlyQuoted = Status(
            id: "quoted-text-only",
            content: "<p>纯文字引用卡片保持简洁白底与 14pt 圆角细边框，不再显示多余的「引用的嘟文」标题栏。</p>",
            createdAt: Date().addingTimeInterval(-7_200),
            account: quotedAuthor,
            mediaAttachments: [],
            favouritesCount: 4,
            reblogsCount: 0,
            repliesCount: 1,
            bookmarked: false,
            favourited: false,
            reblogged: false
        )

        let postWithTextOnlyQuote = Status(
            id: "post-text-quote",
            content: "<p>无配图时直接展示单行作者信息与清晰富文本引用内容。</p>",
            createdAt: Date().addingTimeInterval(-1_800),
            account: author,
            mediaAttachments: [],
            favouritesCount: 3,
            reblogsCount: 1,
            repliesCount: 0,
            bookmarked: false,
            favourited: false,
            reblogged: false,
            quote: Status.Quote(state: .accepted, quotedStatus: textOnlyQuoted)
        )

        return [postWithMediaAndQuote, postWithTextOnlyQuote]
    }

    private static func makeFixtureImage(
        name: String,
        size: CGSize,
        topColor: UIColor,
        bottomColor: UIColor,
        label: String
    ) async -> URL {
        let url = directory.appendingPathComponent(name)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [topColor.cgColor, bottomColor.cgColor] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) {
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: min(size.width, size.height) * 0.14, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.92),
            ]
            let text = label as NSString
            let textSize = text.size(withAttributes: attrs)
            text.draw(
                at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                withAttributes: attrs
            )
        }
        if let png = image.pngData() {
            try? png.write(to: url, options: .atomic)
            await SDImageCache.shared.store(image, imageData: png, forKey: url.absoluteString, toDisk: true)
            ImageCache.shared.setImage(image, for: url)
        }
        return url
    }
}
#endif
