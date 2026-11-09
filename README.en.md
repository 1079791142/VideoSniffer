# VideoSniffer

![Swift](https://img.shields.io/badge/Swift-6-orange?style=flat&logo=swift) ![SwiftUI](https://img.shields.io/badge/framework-SwiftUI-blue?style=flat) ![Platforms](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS-lightgrey?style=flat) ![Native](https://img.shields.io/badge/100%25-native-brightgreen)

[简体中文](README.md) | English

A personal-use iOS app: **built-in browser + web video sniffing + download management**. It is not meant for the App Store and is installed on a single iPhone via free-account sideloading (Sideloadly).

> **Status (2026-11-09)**: the HLS download engine from [LSX-s-Software/M3U8-Downloader](https://github.com/LSX-s-Software/M3U8-Downloader) is imported verbatim. **The in-app browser (WKWebView, Browse / Downloads tabs) and the video sniffer (JS injection + message bridge) are implemented, but have not been compiled by CI or tested on a device yet.** Project cleanup and the GitHub Actions workflow are in place. See [Docs/HANDOFF.md](Docs/HANDOFF.md) for the architecture map, the gap list, the CI recipe and the acceptance criteria.

![Upstream M3U8 Downloader UI (download management part)](Docs/demo.en.png)

## Goals

1. **Browse** any URL inside the app, with back / forward / reload.
2. **Sniff** HLS (`.m3u8`) and progressive media (`.mp4` / `.m4s`) requests made by the page, listing candidates with resolution / bandwidth hints.
3. **Download** concurrently with pause / resume / retry / cancel / delete, visible progress and storage usage, and in-app playback of finished files.
4. **Install** from an unsigned IPA built by CI and sideloaded from Windows.

## Feature status

| Area | Status | Notes |
| --- | :---: | --- |
| HLS parsing (master / variant, AES-128, EXT-X-MAP, BYTERANGE) | ✅ | From upstream |
| Concurrent segment download, retry, pause / resume / cancel | ✅ | From upstream |
| Assembly to a playable local file, local HLS playback server | ✅ | From upstream |
| Download management UI (list / detail / settings / storage) | ✅ | From upstream |
| SwiftData job model and persistence | ✅ | From upstream |
| Simplified Chinese / English, dark mode | ✅ | From upstream |
| In-app browser (WKWebView) | 🟡 | Implemented, not verified by CI |
| Video sniffing (JS injection + message bridge) | 🟡 | Implemented (HLS can be queued for download, MP4 is listed only), not verified by CI |
| Referer / Cookie / User-Agent propagation | ⬜ | To do; needed by anti-hotlink sites |
| Direct MP4 download (not via HLS segments) | ⬜ | To do |
| Project cleanup (team, bundle IDs, ATS, display name) | ✅ | Bundle ID `com.videosniffer.app`, display name VideoSniffer |
| GitHub Actions unsigned IPA | 🟡 | Workflow committed, not run yet |

## Requirements

- **Runtime**: iOS 26.0 or later (the target device is confirmed)
- **Build**: no local Mac required. A GitHub Actions macOS runner can produce the unsigned IPA; Xcode 26 works too if you have a Mac
- **Dependencies**: none — Apple frameworks only (SwiftUI / SwiftData / WebKit / AVKit / Network / CommonCrypto)

## Building without a Mac

Builds are delegated to GitHub Actions. The repository is **public**, so Actions minutes are free. [.github/workflows/build.yml](.github/workflows/build.yml) builds the unsigned IPA on every push to `main`, on every PR, and on manual `workflow_dispatch`. The core steps are:

```sh
xcodebuild \
  -scheme "M3U8 Downloader" \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

mkdir -p Payload
cp -R "build/Build/Products/Release-iphoneos/M3U8 Downloader.app" Payload/
ditto -c -k --sequesterRsrc --keepParent Payload VideoSniffer-unsigned.ipa
```

Download `VideoSniffer-unsigned.ipa` from the workflow run's artifacts.

> Always pass `-destination 'generic/platform=iOS'`. The project also supports macOS, and without an explicit destination `xcodebuild` may pick the macOS platform.

## Installing on iPhone (Windows + Sideloadly)

1. Install **Sideloadly** (<https://sideloadly.io>).
2. Install the **iTunes** and **iCloud** builds from apple.com (not the Microsoft Store versions); Sideloadly relies on their drivers.
3. On the iPhone, enable **Settings → Privacy & Security → Developer Mode** and reboot.
4. Sign in to Sideloadly with a **throwaway Apple ID** (a free account yields a 7-day certificate and a limit of 3 sideloaded apps).
5. Drag the IPA into Sideloadly, enter the Apple ID, and press Start.
6. Before launching, trust the developer certificate under **Settings → General → VPN & Device Management**.

When the 7-day certificate expires, simply re-sign and reinstall. Download history lives inside the app sandbox and normally survives a reinstall; if Sideloadly insists on uninstalling first, export the downloaded files beforehand.

## Project layout

```text
VideoSniffer/
├── M3U8 Downloader/                 # App target (directory keeps the upstream name for now)
│   ├── Browser/                     # In-app browser: WKWebView, address bar, sniffing script and message handler
│   ├── Models/                      # SwiftData: DownloadJob / DownloadSegment, etc.
│   ├── Services/                    # HLS parsing, segment download, AES-128, assembly, local playback server
│   ├── Settings/                    # Concurrency / retry / timeout / proxy settings
│   ├── Utilities/                   # Paths, Keychain, launch arguments, preview samples
│   ├── Views/                       # Download list, detail, settings, player
│   ├── ContentView.swift            # Root view: Browse / Downloads tabs on iOS
│   ├── M3U8_DownloaderApp.swift     # @main entry point
│   └── Localizable.xcstrings        # English + Simplified Chinese copy
├── .github/workflows/build.yml      # CI: build the unsigned IPA and upload it as an artifact
├── M3U8 DownloaderTests/            # Unit tests (HLS parsing, file store, deletion, settings, sniffer validation)
├── M3U8 DownloaderUITests/          # UI tests (switch to the Downloads tab, then open Settings)
├── M3U8 Downloader.xcodeproj/       # objectVersion 77; source folders sync automatically, new .swift files need no project edits
├── Docs/                            # Screenshots and documents
├── iOS-Info.plist                   # iOS-only Info.plist (including ATS)
├── AGENTS.md                        # Style and collaboration rules (follow them)
└── LICENSE                          # Upstream MIT license
```

## Development notes

- **Demo mode**: launch argument `--demo-mode`, or environment variable `M3U8_DOWNLOADER_DEMO_MODE=1`, loads in-memory sample jobs.
- **Localization**: add new strings to `Localizable.xcstrings` as symbol keys with `extractionState: manual`, providing both `en` and `zh-Hans`.
- **Code style**: see [AGENTS.md](AGENTS.md). Highlights: Swift 6 concurrency, `@Observable` + `@MainActor`, no `ObservableObject` / `DispatchQueue`, one type per file, no force unwraps, no third-party frameworks.

## Constraints and compliance (important)

- This project is **for personal use only**. It is **not submitted to the App Store** and is not distributed.
- Only **non-DRM** content and HLS with clear keys (AES-128) is supported. **No FairPlay / Widevine or any other DRM circumvention.**
- The upstream signing team (`C2A3XCXCZS`) and bundle IDs (`LSX-s-Software.*`) must **not** be reused; replace them with your own.
- **No secrets** — no keys, certificates, Apple IDs or passwords — ever go into this repository.
- Copyright and the target site's terms of service for downloaded content are the user's responsibility.

## Upstream and license

This project is derived from [LSX-s-Software/M3U8-Downloader](https://github.com/LSX-s-Software/M3U8-Downloader), released under the MIT License:

```text
MIT License

Copyright (c) 2026 LSX-s-Software
```

See [LICENSE](LICENSE) for the full text. Upstream code and UI screenshots (`Docs/demo.png`, `Docs/demo.en.png`) retain their original attribution and copyright notice.
