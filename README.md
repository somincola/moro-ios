<p align="center">
  <img src="moro/Resources/Assets.xcassets/AppIcon.appiconset/appicon-default-1024.png" width="112" alt="Moro app icon">
</p>

<h1 align="center">Moro for Mastodon</h1>

<p align="center">
  A calm, light, and privacy-respecting Mastodon client for iPhone.
</p>

<p align="center">
  <a href="https://getmoro.app/">Website</a> ·
  <a href="https://apps.apple.com/app/id6776115614">App Store</a> ·
  <a href="https://github.com/somincola/moro-ios/releases">Releases</a> ·
  <a href="CHANGELOG.md">Changelog / 更新日志</a> ·
  <a href="https://getmoro.app/privacy">Privacy</a> ·
  <a href="https://getmoro.app/support">Support</a>
</p>

Moro brings a focused, native iOS experience to the fediverse. Sign in with an account from any compatible Mastodon server, follow conversations, discover communities, and post without ads or unnecessary noise.

## Preview

These promotional previews are real app captures driven by fictional demo accounts and Unsplash photos (see `screenshots/app-store/showcase-assets/CREDITS.md`). No real account or timeline data is shown.

<p align="center">
  <img src="screenshots/app-store/en-US/promotional/04-moro.png" width="45%" alt="Moro thread view with a mountain sunrise photo and replies">
  <img src="screenshots/app-store/en-US/promotional/09-moro.png" width="45%" alt="Moro notifications with mentions, likes, boosts, and follows">
</p>

<p align="center">
  <img src="screenshots/app-store/en-US/promotional/07-moro.png" width="45%" alt="Moro post editor with a seaside poll">
</p>

## Highlights

- Read Following, Local, and Federated timelines in a clean, distraction-free layout.
- Post, reply, and quote with media, polls, alt text, content warnings, language selection, drafts, and per-post visibility.
- Search posts, people, and hashtags, or browse trending topics and recommended accounts.
- Keep up with notifications, direct messages, bookmarks, favourites, and lists.
- Explore rich profiles with custom emoji, pinned posts, links, and server-aware navigation.
- Add polished Home Screen widgets for quick actions, account overview, profile stats, and a quiet decorative moment.
- Protect app-switcher snapshots with Moro's branded privacy shield when the app leaves the foreground.
- Pick photos or a video in the composer, or share them into Moro from Photos. Share links and text from other apps, too.
- Choose from multiple app icons and use Moro in nine localized languages.
- Enjoy native accessibility support, including Dynamic Type and VoiceOver.

## Download

Moro requires iOS 18 or later and works with any compatible Mastodon instance.

- [Download Moro on the App Store](https://apps.apple.com/app/id6776115614)
- [Visit the Moro website](https://getmoro.app/)

Moro is an independent, third-party Mastodon client and is not an official Mastodon app.

## Releases and updates

Find the [latest release](https://github.com/somincola/moro-ios/releases/latest) and browse [all releases](https://github.com/somincola/moro-ios/releases) for Chinese and English update notes, App Store build numbers, and source references.

The [complete changelog / 完整更新日志](CHANGELOG.md) also preserves the earliest App Store updates, which predate this repository's source history. Install Moro through the [App Store](https://apps.apple.com/app/id6776115614).

## Privacy

Moro has no ads and does not use behavioral tracking. Account credentials are stored in the iOS Keychain, and your social content remains between your device and the Mastodon server you choose. See the [Privacy Policy](https://getmoro.app/privacy) for details.

## Development

1. Open `moro.xcodeproj` in Xcode 26.6 or later; the CI toolchain is pinned in [`.github/workflows/ci.yml`](.github/workflows/ci.yml).
2. Select the `moro` scheme and an iOS 18+ simulator.
3. Build and run from Xcode, or use the commands below. Keep local account credentials and tokens out of source control.

```bash
xcodebuild -project moro.xcodeproj -scheme moro -sdk iphonesimulator -configuration Debug build
xcodebuild -project moro.xcodeproj -scheme moro -destination 'platform=iOS Simulator,id=460D37C1-EE1F-440D-9F0C-BAB4A85EC694' -configuration Debug test -only-testing:moroTests
```

### Project layout

| Path | Purpose |
| --- | --- |
| `moro/App` | App entry point, lifecycle, and navigation shell |
| `moro/Modules` | Auth, Timeline, Post, Profile, Settings, and other features |
| `moro/Core` | Models, stores, Mastodon API, persistence, and shared services |
| `moro/UI` | Theme and reusable SwiftUI components |
| `moroShareExtension` | Import text, links, photos, and videos from the system share sheet |
| `moroNotificationService` | Process incoming push notifications |
| `moroWidgetShared` | Shared WidgetKit intents and snapshot storage |
| `moroWidgets` | Moro Home Screen widgets |
| `moroTests` | Unit and integration tests |
| `docs` | Current product baselines, interaction contracts, and engineering guides |

See [docs/README.md](docs/README.md) for the current documentation map.

<details>
<summary>App Store identifiers</summary>

| Field | Value |
| --- | --- |
| Bundle ID | `com.somincola.moro` |
| SKU | `moro` |
| Apple ID | `6776115614` |
| App Store URL | `https://apps.apple.com/app/id6776115614` |

</details>

## License

Moro's source code is proprietary and confidential. See [LICENSE](LICENSE) for the applicable terms. Third-party components remain subject to their respective licenses and notices.
