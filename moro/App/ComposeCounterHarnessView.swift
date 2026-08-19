//
//  ComposeCounterHarnessView.swift
//  moro
//
//  Dedicated UI test harness for the Mastodon-style compose character counter
//  and the post-button enablement it gates. Buttons set known text values so the
//  test stays deterministic without depending on keyboard input.
//

import SwiftUI

struct ComposeCounterHarnessView: View {
    @State private var text: String = ""

    /// Mirror the compose default (ComposeViewModel.maxCharacters) before any
    /// instance override is fetched.
    private let maxCharacters = 500

    /// The real, shared counter — URLs are a fixed 23 and a remote mention's
    /// @domain is dropped, exactly as the live compose screen counts.
    private var count: Int { MastodonTextCounter.count(text) }

    /// Same length guard the compose view model uses for `canPublish`.
    private var canPost: Bool { count > 0 && count <= maxCharacters }

    var body: some View {
        VStack(spacing: 12) {
            Text("\(count)")
                .font(.title3.monospacedDigit())
                .accessibilityIdentifier("compose.charCount")

            Button("URL") {
                text = "https://example.com/a/very/long/path/that/keeps/going/on"
            }
            .accessibilityIdentifier("compose.set.url")

            Button("Mention") { text = "@alice@mastodon.social" }
                .accessibilityIdentifier("compose.set.mention")

            Button("Plain") { text = "Hello, world!" }
                .accessibilityIdentifier("compose.set.plain")

            Button("Over") { text = String(repeating: "a", count: maxCharacters + 1) }
                .accessibilityIdentifier("compose.set.over")

            Button("Clear") { text = "" }
                .accessibilityIdentifier("compose.set.clear")

            Button("Post") {}
                .disabled(!canPost)
                .accessibilityIdentifier("compose.postButton")
        }
        .padding(16)
        .background(Color(.systemBackground))
    }
}
