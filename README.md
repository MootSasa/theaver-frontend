**English** | [Русский](./README.ru.md)

# Theaver

Theaver is a cross-platform Flutter messenger client targeting Android, iOS, Windows, macOS, Linux, and the Web.

[![Release](https://img.shields.io/github/v/release/MootSasa/theaver-frontend?include_prereleases&label=release)](https://github.com/MootSasa/theaver-frontend/releases)
[![Release Build](https://github.com/MootSasa/theaver-frontend/actions/workflows/release.yml/badge.svg)](https://github.com/MootSasa/theaver-frontend/releases)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](./LICENSE)
![Flutter](https://img.shields.io/badge/Flutter-3.44%2B-02569B?logo=flutter&logoColor=white)
![Platforms](https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Web-424245)

[Website](https://theaver.app) | [Web Client](https://app.theaver.app) | [Downloads](https://theaver.app/downloads) | [Docs (EN)](https://theaver.app/docs) | [Docs (RU)](https://theaver.app/ru/docs) | [Changelog](https://theaver.app/changelog)

---

## What It Includes

The client handles direct messages, groups, channels, communities, polls, and reactions, backed by a local Drift (SQLite) cache so chats and drafts open immediately offline. On desktop platforms, you can arrange multiple chat and sticker panes side by side.

Audio calls, video calls, and 1080p60 screen sharing run over WebRTC and LiveKit, alongside voice channels inside communities. Chats also support animated stickers, inline custom emoji, a justified GIF picker with hold-to-preview, and importing sticker packs from Telegram.

For bots and embedded tools, Theaver supports `@BotMother` bots, inline keyboards, WebSocket RPC, and per-account isolated Mini Apps v8. Account controls include cloud 2FA with backup codes, local PIN or biometric App Lock, active session inspection with a 24-hour trusted-session guard, and self-service account deletion with a 7-day cancellation window.

This public repository holds only the open-source client code under `GPL-3.0`. The backend server stays private, while the website and bilingual docs live in [MootSasa/theaver-website](https://github.com/MootSasa/theaver-website).

---

## Downloads and Signature Checks

Prebuilt installers and packages are published on the [Downloads page](https://theaver.app/downloads) and in [GitHub Releases](https://github.com/MootSasa/theaver-frontend/releases). You can also open the Web build directly at [app.theaver.app](https://app.theaver.app).

| Channel | Use Case | Link |
|---|---|---|
| Stable | Everyday builds | [theaver.app/downloads](https://theaver.app/downloads) |
| Beta | Preview builds from `beta` | [GitHub Releases](https://github.com/MootSasa/theaver-frontend/releases) · [beta.theaver.app](https://beta.theaver.app) |
| Web | Browser access with no install | [app.theaver.app](https://app.theaver.app) |

Every release includes `SHA256SUMS.txt` and platform signatures backed by public keys in this repository:

- Linux GPG public key: [signing/linux/theaver-release-public.asc](./signing/linux/theaver-release-public.asc)
- Windows Root CA certificate: [signing/windows/theaver-windows-root.cer](./signing/windows/theaver-windows-root.cer)

Verify archives before running them:

```bash
sha256sum -c SHA256SUMS.txt --ignore-missing
gpg --import signing/linux/theaver-release-public.asc
gpg --verify theaver-*.tar.gz.asc theaver-*.tar.gz
```

On Windows PowerShell:

```powershell
Get-AuthenticodeSignature .\theaver-*-windows-x64-setup.exe
```

Step-by-step instructions are in the [Download Verification Guide](https://theaver.app/docs/guide/verify-downloads).

---

## Building from Source

You need Flutter `3.44.9` (Dart `>=3.0.0 <4.0.0`) and standard build tools for your target platform (Android SDK + JDK 17, Xcode for Apple targets, MSVC + CMake on Windows, or `libsqlite3-dev` + GTK/Clang toolchain on Linux).

1. Clone the repository:

   ```bash
   git clone https://github.com/MootSasa/theaver-frontend
   cd theaver-frontend
   ```

2. Copy placeholder Firebase and HMS config files so Gradle builds without private store credentials:

   ```bash
   cp android/app/google-services.json.example android/app/google-services.json
   cp android/app/agconnect-services.json.example android/app/agconnect-services.json
   ```

3. Fetch packages and run:

   ```bash
   flutter pub get
   flutter run
   ```

To point a local build at another backend instance, pass `--dart-define` (configured in [lib/config/app_config.dart](./lib/config/app_config.dart)):

```bash
flutter run --dart-define=API_BASE_URL=http://localhost:8080
```

Run checks before committing:

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
python3 scripts/calculate_release.py --validate-fragments
```

---

## Repository Layout

```text
.
├── assets/l10n/          # Localization dictionaries (de, en, es, fr, it, ja, ko, pt, ru, zh)
├── changelogs/           # Bilingual (RU/EN) release note fragments and rules
├── lib/
│   ├── animations/       # Custom motion primitives
│   ├── config/           # Environment endpoints and update channels
│   ├── l10n/             # Localization loader
│   ├── models/           # Typed data models
│   ├── screens/          # Chats, calls, settings, profiles, Mini Apps
│   ├── services/         # API client, WebSocket sync, local DB, updates, notifications
│   ├── theme/            # Light and dark color themes
│   ├── utils/            # Platform utilities
│   └── widgets/          # Reusable UI widgets
├── packages/             # Vendored packages (liquid_glass_easy)
├── scripts/              # Versioning, release notes, signing, and deploy scripts
├── signing/              # Public GPG key and Windows Root CA certificate
└── test/                 # Unit and widget tests
```

---

## Contributing and Security

Read [CONTRIBUTING.md](./CONTRIBUTING.md) and [changelogs/README.md](./changelogs/README.md) before opening a pull request. Report bugs and feature requests in [Issues](https://github.com/MootSasa/theaver-frontend/issues) or start a thread in [Discussions](https://github.com/MootSasa/theaver-frontend/discussions).

Do not open public issues for security vulnerabilities. Follow [SECURITY.md](./SECURITY.md) instead.

## License

GNU General Public License v3.0. See [LICENSE](./LICENSE).
Copyright (C) 2026 MootSasa.
