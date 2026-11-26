#if DEBUG
import SwiftUI

/// Two 32×20 frames, red for 230 ms and blue for 470 ms, with a transparent corner.
/// These small independent encodings also exercise a real animated WebP on Apple's decoder.
enum PostEmojiPlaybackFixture {
    static let originals: [(name: String, data: Data)] = [
        ("gif.gif", Data(base64Encoded: "R0lGODlhIAAUAPAAAAAAAP8AACH/C05FVFNDQVBFMi4wAwEAAAAh+QQJFwAAACwAAAAAIAAUAAACK4yPmcDtrGJ8FMh76sNYO355DSiJEKmYFrqYbCu+iCrX9o3n+s73/g/EFQAAIfkECS8AAAAsAAAAACAAFACAAAAAAAD/AiuMj5nA7axifBTIe+rDWDt+eQ0oiRCpmBa6mGwrvogq1/aN5/rO9/4PxBUAADs=")!),
        ("animated.png", Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAUCAYAAADskT9PAAAACGFjVEwAAAACAAAAAPONk3AAAAAaZmNUTAAAAAAAAAAgAAAAFAAAAAAAAAAAABcAZAAAcRVjUAAAAC1JREFUeJxj+M/A8J+amIFUMOqAUQeMOmDUAcPOASQ7eNQBow4YdcCoAwbaAQBJdAwtNyi6PQAAABpmY1RMAAAAAQAAACAAAAAUAAAAAAAAAAAALwBkAAB7N3rDAAAAMGZkQVQAAAACeJxjYGD4/5+6mGQw6oBRB4w6YNQBw84BJDt41AGjDhh1wKgDBtYBAD1IDC3s/5yUAAAAAElFTkSuQmCC")!),
        ("webp.webp", Data(base64Encoded: "UklGRpwAAABXRUJQVlA4WAoAAAASAAAAHwAAEwAAQU5JTQYAAAD/////AABBTk1GNAAAAAAAAAAAAB8AABMAAOYAAAJWUDhMGwAAAC8fwAQQDxDzH/MfDCEB4YH/a3ULIvo/ASWXKwBBTk1GNAAAAAAAAAAAAB8AABMAANYBAABWUDhMGwAAAC8fwAQQDxAx//MfDCEB4YH/a3ULIvo/ASWXKwA=")!),
    ]

    static let post: Status = {
        let directory = FileManager.default.temporaryDirectory
        let posterURL = directory.appendingPathComponent("post-emoji-still.png")
        let size = CGSize(width: 32, height: 20)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let poster = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        try! poster.pngData()!.write(to: posterURL, options: .atomic)
        InlineEmojiRendering.store(poster, for: posterURL)
        var emojis = originals.map { name, data in
            let url = directory.appendingPathComponent("post-emoji-\(name)")
            try! data.write(to: url, options: .atomic)
            // Mastodon-compatible servers can return the APNG itself for static_url.
            let still = name == "animated.png" ? url : posterURL
            if still == url { InlineEmojiRendering.store(UIImage(data: data)!, for: url) }
            return Status.Emoji(shortcode: String(name.split(separator: ".")[0]), url: url, staticURL: still)
        }
        emojis.append(Status.Emoji(shortcode: "still", url: posterURL, staticURL: posterURL))
        return Status(id: "post-emoji", content: "<p>GIF :gif: and PNG :animated:<br/>WebP :webp: repeat :gif: still :still:</p>",
                      createdAt: Date(), account: ThreadReadingFixtures.author, mediaAttachments: [],
                      favouritesCount: 0, reblogsCount: 0, repliesCount: 0, bookmarked: false, favourited: false,
                      reblogged: false, emojis: emojis)
    }()

    // Opaque square frames expose clipping on any edge of a trailing name badge.
    static let profileBadge: Status.Emoji = {
        let data = Data(base64Encoded: "R0lGODlhFAAUAPAAAP8AAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQAKgAAACwAAAAAFAAUAAACEYSPqcvtD6OctNqLs968+68VACH5BAAqAAAALAAAAAAUABQAgAAA/wAAAAIRhI+py+0Po5y02ouz3rz7rxUAOw==")!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("profile-badge.gif")
        try! data.write(to: url, options: .atomic)
        // Real servers also supply large transparent PNG posters, loaded after first layout.
        let posterURL = url.deletingPathExtension().appendingPathExtension("png")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let poster = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 6, y: 6, width: 500, height: 500))
        }
        try! poster.pngData()!.write(to: posterURL, options: .atomic)
        return Status.Emoji(shortcode: "gif", url: url, staticURL: posterURL)
    }()

    // A scroll restart is visible on the same row: red for 6.5 s, then blue for 120 s.
    static let scrollGIF: Status.Emoji = {
        let data = Data(base64Encoded: "R0lGODlhIAAUAPAAAAAAAP8AACH/C05FVFNDQVBFMi4wAwEAAAAh+QQJigIAACwAAAAAIAAUAAACK4yPmcDtrGJ8FMh76sNYO355DSiJEKmYFrqYbCu+iCrX9o3n+s73/g/EFQAAIfkECeAuAAAsAAAAACAAFACAAAAAAAD/AiuMj5nA7axifBTIe+rDWDt+eQ0oiRCpmBa6mGwrvogq1/aN5/rO9/4PxBUAADs=")!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("profile-scroll.gif")
        try! data.write(to: url, options: .atomic)
        return Status.Emoji(shortcode: "gif", url: url, staticURL: post.emojis![0].staticURL)
    }()
}

struct PostEmojiPlaybackHarness: View {
    @State private var detail = false
    @State private var playback = false
    @StateObject private var appState = AppState()
    private let post = PostEmojiPlaybackFixture.post
    private static let client = ThreadFixtureProtocol.makeClient(focus: PostEmojiPlaybackFixture.post,
                                                               context: StatusContext(ancestors: [], descendants: []))

    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    Button(detail ? "Timeline" : "Detail") { detail.toggle() }
                        .accessibilityIdentifier("emoji.detail")
                    Toggle("Play emoji", isOn: $playback).accessibilityIdentifier("emoji.playback")
                }.padding(.horizontal)
                if detail {
                    StatusDetailView(status: post, apiClient: Self.client, threadCache: ThreadCache())
                } else {
                    ScrollView { TimelinePostRow(status: post, threadContext: .none) }
                }
            }
        }
        .environmentObject(appState)
        .moroTheme(MoroTheme())
        .environment(\.moroMediaPrefs, MoroMediaPreferences(playAnimations: playback))
    }
}
#endif
