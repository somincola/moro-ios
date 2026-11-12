<p align="center">
  <img src="moro/Resources/Assets.xcassets/AppIcon.appiconset/appicon-default-1024.png" width="88" alt="Moro app icon">
</p>

<h1 align="center">Moro for Mastodon</h1>

<p align="center">
  <strong>Light. Simple. Friendly.</strong><br>
  A calmer home for the fediverse, made for iPhone.
</p>

<p align="center">
  <a href="https://github.com/somincola/moro-ios/releases/latest"><img src="https://img.shields.io/github/v/release/somincola/moro-ios?style=flat-square&amp;label=release&amp;color=131B3E" alt="Latest release"></a>
  <a href="https://apps.apple.com/app/id6776115614"><img src="https://img.shields.io/badge/iOS-18%2B-131B3E?style=flat-square&amp;logo=apple&amp;logoColor=white" alt="Requires iOS 18 or later"></a>
  <a href="https://github.com/topics/swiftui"><img src="https://img.shields.io/badge/SwiftUI-native-166E78?style=flat-square&amp;logo=swift&amp;logoColor=white" alt="Native SwiftUI app"></a>
  <a href="https://github.com/topics/mastodon-client"><img src="https://img.shields.io/badge/Mastodon-client-6364FF?style=flat-square&amp;logo=mastodon&amp;logoColor=white" alt="Mastodon client"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-proprietary-626873?style=flat-square" alt="Proprietary license"></a>
</p>

<p align="center">
  <a href="https://apps.apple.com/app/id6776115614"><img src="docs/assets/readme/app-store-badge.svg" height="44" alt="Download on the App Store"></a>
</p>

<p align="center">
  <a href="https://getmoro.app/">Official website</a> ·
  <a href="https://github.com/somincola/moro-ios/releases">Release notes</a> ·
  <a href="https://getmoro.app/support">Support</a> ·
  <a href="README.zh-CN.md">简体中文</a>
</p>

## Meet Moro

Moro is a native Mastodon client for iPhone, built around three ideas: **light, simple, friendly**. Bring your account from a compatible Mastodon server and enjoy a clear timeline, connected conversations, and a comfortable place to post.

Follow your communities, switch between accounts, and pick up where you left off. Make the experience your own with a theme color, readable text, and an app icon that feels right.

<p align="center">
  <a href="https://apps.apple.com/app/id6776115614"><img src="screenshots/app-store/en-US/promotional/04-moro.png" width="270" alt="Official Moro App Store preview: follow a threaded conversation"></a>
  <a href="https://apps.apple.com/app/id6776115614"><img src="screenshots/app-store/en-US/promotional/10-moro.png" width="270" alt="Official Moro App Store preview: personalize appearance, text size, and app icon"></a>
</p>

<p align="center">
  <sub>Two official App Store previews. <a href="https://apps.apple.com/app/id6776115614">See more on the App Store</a> · <a href="docs/assets/readme/SOURCES.md">Artwork sources</a></sub>
</p>

## Made for everyday Mastodon

| Experience | What you can do |
| --- | --- |
| **Read at your pace** | Browse Following, Local, Federated, and list timelines. Return to your reading position and open new posts when you are ready. |
| **Stay in the conversation** | Follow threads, reply and quote, translate posts, and catch up on mentions, favourites, boosts, and messages. |
| **Say it your way** | Share photos or a video, add a poll, save a draft, and choose alt text, content warnings, language, and visibility. Bring media straight from Photos into the composer. |
| **Keep your accounts together** | Sign in across servers, switch accounts with a long press, and edit your profile, avatar, header, and extra fields in one place. |
| **Make Moro yours** | Choose a theme color, post text size, and app icon. Use Moro in nine languages, with Dynamic Type and VoiceOver support. |
| **Feel at home on iPhone** | Use Home Screen widgets and the system share sheet. On iPhone Duo, enjoy a two-column layout with more space for reading and conversations. |

## Your account, your choice

Moro has **no ads and no cross-app tracking**. Your accounts connect to the Mastodon servers you choose, and credentials are stored in the iOS Keychain.

Read the [Privacy Policy](https://getmoro.app/privacy) and [Transparency page](https://getmoro.app/transparency) for notification delivery, optional Apple diagnostics, and the services involved.

## Get Moro and stay up to date

- **Download:** [Moro on the App Store](https://apps.apple.com/app/id6776115614) — requires iOS 18 or later.
- **Explore:** [Official website](https://getmoro.app/).
- **Updates:** [Latest release](https://github.com/somincola/moro-ios/releases/latest), [all releases](https://github.com/somincola/moro-ios/releases), and the [complete changelog](CHANGELOG.md).
- **Get in touch:** [Support](https://getmoro.app/support) or [GitHub Issues](https://github.com/somincola/moro-ios/issues).

## For developers

Moro is built with Swift and SwiftUI, with a share extension, notification service extension, and WidgetKit widgets. Start with the [documentation index](docs/README.md) for product behaviour, architecture, and integration contracts.

<details>
<summary>Build and project structure</summary>

Open `moro.xcodeproj` in Xcode 26.6 or later, select the `moro` scheme, and choose an installed iOS 18+ simulator. The CI toolchain is pinned in [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

```bash
xcodebuild -project moro.xcodeproj -scheme moro -sdk iphonesimulator -configuration Debug build
```

| Path | Purpose |
| --- | --- |
| `moro` | App, features, shared services, and SwiftUI components |
| `moroShareExtension` | Share-sheet import into the composer |
| `moroNotificationService` | Incoming push notification processing |
| `moroWidgets` / `moroWidgetShared` | Widgets, intents, and shared snapshots |
| `moroTests` / `moroUITests` | Unit, integration, and UI tests |
| `metadata/app-store` | Localized App Store metadata |
| `docs` | Product and engineering documentation |

</details>

---

Moro is an independent Mastodon client, developed by Somincola. Source code and app assets are covered by the [proprietary license](LICENSE); third-party materials retain their own terms. © 2025–2026 Somincola. All rights reserved.
