# Theaver

Open-source cross-platform Flutter client for **Theaver Messenger** across Android, iOS, Windows, macOS, Linux, and the Web.

[![Release](https://img.shields.io/github/v/release/MootSasa/theaver-frontend?include_prereleases&label=release)](https://github.com/MootSasa/theaver-frontend/releases)
[![Client CI](https://github.com/MootSasa/theaver-frontend/actions/workflows/ci.yml/badge.svg)](https://github.com/MootSasa/theaver-frontend/actions/workflows/ci.yml)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](./LICENSE)
![Flutter](https://img.shields.io/badge/Flutter-3.41%2B-02569B?logo=flutter&logoColor=white)
![Platforms](https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Web-424245)

[Website](https://theaver.app) · [Web Client](https://app.theaver.app) · [Downloads](https://theaver.app/downloads) · [Docs (EN)](https://theaver.app/docs) · [Документация (RU)](https://theaver.app/ru/docs) · [Changelog](https://theaver.app/changelog)

---

## Features

- **Cloud Messaging & Local Cache:** Direct messages, group chats, channels, communities, polls, reactions, and drafts backed by a local Drift (SQLite) store for fast startup and offline reading.
- **Voice & Video Calls:** Real-time audio/video calls and 1080p60 screen sharing over WebRTC / LiveKit, plus voice channels in communities.
- **Multi-Pane Desktop Workspace:** Resizable tiling layout on Windows, macOS, and Linux with dedicated emoji/sticker panels alongside active chats.
- **Media, Stickers & GIFs:** Justified GIF grid with press-and-hold preview, animated stickers, custom inline emoji, and Telegram sticker pack import.
- **Bots & Mini Apps v8:** Bot interactions via `@BotMother`, inline keyboards, WebSocket RPC, and isolated web-view Mini Apps inside the client.
- **Account Security Controls:** Cloud 2FA password with backup codes, local PIN / biometric App Lock, active session inspection with a 24-hour trusted-session guard, and self-service account deletion with a 7-day grace window.

> **Architecture note:** This public repository hosts the complete open-source client (`theaver-frontend`) licensed under **GPL-3.0**. Server infrastructure (`theaver-backend`) runs as a separate private service, while the website and documentation live in [`MootSasa/theaver-website`](https://github.com/MootSasa/theaver-website).

---

## Downloads & Signature Verification

Prebuilt packages for every supported platform are available on the [Downloads page](https://theaver.app/downloads) and in [GitHub Releases](https://github.com/MootSasa/theaver-frontend/releases), alongside a browser build at [`app.theaver.app`](https://app.theaver.app).

| Channel | Intended Use | Source |
|---|---|---|
| **Stable** | Daily use | [theaver.app/downloads](https://theaver.app/downloads) |
| **Beta** | Early feature testing from `beta` | [GitHub Releases](https://github.com/MootSasa/theaver-frontend/releases) · [beta.theaver.app](https://beta.theaver.app) |
| **Web** | Zero-install desktop & mobile fallback | [app.theaver.app](https://app.theaver.app) |

Every release attaches **`SHA256SUMS.txt`** and platform signing artifacts derived from the public keys stored in [`signing/`](./signing):

- **Linux GPG public key:** [`signing/linux/theaver-release-public.asc`](./signing/linux/theaver-release-public.asc)
- **Windows Root CA certificate:** [`signing/windows/theaver-windows-root.cer`](./signing/windows/theaver-windows-root.cer)

Verify downloaded archives before installing:

```bash
# 1. Verify SHA-256 checksum
sha256sum -c SHA256SUMS.txt --ignore-missing

# 2. Verify detached Linux GPG signature
gpg --import signing/linux/theaver-release-public.asc
gpg --verify theaver-*.tar.gz.asc theaver-*.tar.gz
```

On Windows PowerShell:

```powershell
Get-AuthenticodeSignature .\theaver-*-windows-x64-setup.exe
```

Full platform-by-platform instructions live in the [Download Verification Guide](https://theaver.app/docs/guide/verify-downloads).

---

## Building from Source

### Prerequisites

- **Flutter SDK:** `3.41.9` (Dart SDK `>=3.0.0 <4.0.0`)
- Standard platform toolchains for your target OS (Android SDK + JDK 17 for Android, Xcode for iOS/macOS, MSVC/CMake for Windows, `libsqlite3-dev` + GTK/Clang toolchain for Linux)

### Local Setup

1. Clone the repository:

   ```bash
   git clone https://github.com/MootSasa/theaver-frontend.git
   cd theaver-frontend
   ```

2. Prepare local push configuration placeholders (required by Gradle when private Firebase/HMS configs are absent):

   ```bash
   cp android/app/google-services.json.example android/app/google-services.json
   cp android/app/agconnect-services.json.example android/app/agconnect-services.json
   ```

3. Install packages and run the client:

   ```bash
   flutter pub get
   flutter run
   ```

To point a local build at a custom or self-hosted API server, pass `--dart-define` flags (see [`lib/config/app_config.dart`](./lib/config/app_config.dart)):

```bash
flutter run --dart-define=API_BASE_URL=http://localhost:8080
```

### Verification Commands

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
python3 scripts/calculate_release.py --validate-fragments
```

---

## Repository Layout

```text
.
├── assets/l10n/          # 10 client localization dictionaries (de, en, es, fr, it, ja, ko, pt, ru, zh)
├── changelogs/           # Bilingual (RU/EN) release note fragments and style rules
├── lib/
│   ├── animations/       # Custom motion & transition primitives
│   ├── config/           # Environment URLs, update channels, and feature endpoints
│   ├── l10n/             # Localization loader
│   ├── models/           # Typed data models
│   ├── screens/          # App screens (chats, calls, settings, profiles, mini apps)
│   ├── services/         # API client, WebSocket sync, local DB, updates, notifications
│   ├── theme/            # Light/dark themes and visual tokens
│   ├── utils/            # Helpers and platform utilities
│   └── widgets/          # Reusable UI components
├── packages/             # Vendored local workspace packages (liquid_glass_easy)
├── scripts/              # Semver, release-notes builder, signing, and deployment helpers
├── signing/              # Public release GPG key and Windows Root CA certificate
└── test/                 # Unit and widget tests
```

---

## Contributing & Security

- Read [`CONTRIBUTING.md`](./CONTRIBUTING.md) and [`changelogs/README.md`](./changelogs/README.md) before opening a pull request.
- Bug reports and feature requests belong in [Issues](https://github.com/MootSasa/theaver-frontend/issues); questions and general feedback can go to [Discussions](https://github.com/MootSasa/theaver-frontend/discussions).
- **Never disclose security vulnerabilities in public issues.** Follow [`SECURITY.md`](./SECURITY.md) to report issues privately.

## License

Licensed under the **GNU General Public License v3.0** — see [`LICENSE`](./LICENSE).
Copyright (C) 2026 MootSasa.
