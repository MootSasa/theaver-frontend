[English](./README.md) | **Русский**

# Theaver

Кроссплатформенный Flutter-клиент мессенджера **Theaver** для Android, iOS, Windows, macOS, Linux и браузера.

[![Релиз](https://img.shields.io/github/v/release/MootSasa/theaver-frontend?include_prereleases&label=release)](https://github.com/MootSasa/theaver-frontend/releases)
[![Сборка релизов](https://github.com/MootSasa/theaver-frontend/actions/workflows/release.yml/badge.svg)](https://github.com/MootSasa/theaver-frontend/releases)
[![Лицензия: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](./LICENSE)
![Flutter](https://img.shields.io/badge/Flutter-3.44%2B-02569B?logo=flutter&logoColor=white)
![Платформы](https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Web-424245)

[Сайт](https://theaver.app/ru/) | [Веб-клиент](https://app.theaver.app) | [Загрузки](https://theaver.app/ru/downloads) | [Документация (RU)](https://theaver.app/ru/docs) | [Docs (EN)](https://theaver.app/docs) | [Обновления](https://theaver.app/ru/changelog)

---

## Что есть в клиенте

В приложении работают личные чаты, группы, каналы, сообщества, опросы и реакции. Переписки и черновики кэшируются локально в Drift (SQLite), поэтому клиент быстро запускается и открывает историю даже без сети. В десктопной версии поддерживается многооконный тайлинг: например, чат и боковая панель стикеров рядом.

Голосовые и видеозвонки вместе с демонстрацией экрана 1080p60 идут через WebRTC и LiveKit, в сообществах есть голосовые комнаты. Для общения доступны анимированные стикеры, встроенные кастомные эмодзи, адаптивная сетка GIF с предпросмотром по удержанию и импорт стикерпаков из Telegram.

Платформа ботов через `@BotMother` поддерживает inline-кнопки, WebSocket RPC и изолированные для каждого аккаунта Mini Apps v8. В настройках безопасности есть облачный пароль 2FA с резервными кодами, локальный PIN или биометрия на вход (App Lock), просмотр активных сессий с 24-часовой защитой старых устройств и самостоятельное удаление аккаунта с 7-дневным сроком на отмену.

В этом открытом репозитории лежит исходный код клиента под лицензией `GPL-3.0`. Серверная часть закрыта, а исходники сайта и документации находятся в [MootSasa/theaver-website](https://github.com/MootSasa/theaver-website).

---

## Загрузка и проверка подписей

Готовые сборки лежат на странице [Загрузки](https://theaver.app/ru/downloads) и в [GitHub Releases](https://github.com/MootSasa/theaver-frontend/releases), а браузерная версия открывается по адресу [app.theaver.app](https://app.theaver.app).

| Канал | Для чего | Где скачать |
|---|---|---|
| Stable | Основная стабильная ветка | [theaver.app/ru/downloads](https://theaver.app/ru/downloads) |
| Beta | Тестовые сборки из `beta` | [GitHub Releases](https://github.com/MootSasa/theaver-frontend/releases) · [beta.theaver.app](https://beta.theaver.app) |
| Web | Работа прямо в браузере | [app.theaver.app](https://app.theaver.app) |

К каждому релизу прикладывается общий файл контрольных сумм `SHA256SUMS.txt` и платформенные подписи от публичных ключей из этого репозитория:

- Публичный GPG-ключ для Linux: [signing/linux/theaver-release-public.asc](./signing/linux/theaver-release-public.asc)
- Корневой сертификат Windows: [signing/windows/theaver-windows-root.cer](./signing/windows/theaver-windows-root.cer)

Проверить архивы перед запуском можно так:

```bash
sha256sum -c SHA256SUMS.txt --ignore-missing
gpg --import signing/linux/theaver-release-public.asc
gpg --verify theaver-*.tar.gz.asc theaver-*.tar.gz
```

В Windows PowerShell:

```powershell
Get-AuthenticodeSignature .\theaver-*-windows-x64-setup.exe
```

Подробная инструкция по проверке сборок опубликована в разделе [Проверка подписей](https://theaver.app/ru/docs/guide/verify-downloads).

---

## Сборка из исходников

Для сборки понадобится Flutter `3.44.9` (Dart `>=3.0.0 <4.0.0`) и стандартный инструментарий выбранной ОС (Android SDK и JDK 17 для Android, Xcode для Apple, MSVC и CMake для Windows, `libsqlite3-dev` + GTK/Clang для Linux).

1. Клонируйте репозиторий:

   ```bash
   git clone https://github.com/MootSasa/theaver-frontend
   cd theaver-frontend
   ```

2. Скопируйте шаблоны конфигов Firebase и HMS для локальной сборки Android:

   ```bash
   cp android/app/google-services.json.example android/app/google-services.json
   cp android/app/agconnect-services.json.example android/app/agconnect-services.json
   ```

3. Установите зависимости и запустите приложение:

   ```bash
   flutter pub get
   flutter run
   ```

Чтобы подключить клиент к локальному или собственному серверу, передайте адрес через `--dart-define` (все параметры собраны в [lib/config/app_config.dart](./lib/config/app_config.dart)):

```bash
flutter run --dart-define=API_BASE_URL=http://localhost:8080
```

Проверки перед коммитом:

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
python3 scripts/calculate_release.py --validate-fragments
```

---

## Структура репозитория

```text
.
├── assets/l10n/          # Словари локализации (de, en, es, fr, it, ja, ko, pt, ru, zh)
├── changelogs/           # Двуязычные фрагменты описаний релизов (RU/EN) и памятка
├── lib/
│   ├── animations/       # Анимации и переходы
│   ├── config/           # URL серверов и каналов обновлений
│   ├── l10n/             # Загрузчик локализаций
│   ├── models/           # Модели данных
│   ├── screens/          # Экраны чатов, звонков, настроек, профилей и Mini Apps
│   ├── services/         # HTTP/WebSocket клиент, локальная БД, обновления, уведомления
│   ├── theme/            # Светлая и тёмная темы оформления
│   ├── utils/            # Платформенные утилиты
│   └── widgets/          # Общие виджеты интерфейса
├── packages/             # Локальные пакеты (liquid_glass_easy)
├── scripts/              # Версионирование, сборка заметок релизов, подпись и деплой
├── signing/              # Публичный GPG-ключ и корневой сертификат Windows
└── test/                 # Юнит- и виджет-тесты
```

---

## Участие в разработке и безопасность

Перед отправкой Pull Request загляните в [CONTRIBUTING.md](./CONTRIBUTING.md) и [changelogs/README.md](./changelogs/README.md). Сообщения об ошибках и предложения публикуйте в [Issues](https://github.com/MootSasa/theaver-frontend/issues), а общие вопросы удобно задавать в [Discussions](https://github.com/MootSasa/theaver-frontend/discussions).

О найденных уязвимостях не пишите в публичных темах; порядок приватной отправки описан в [SECURITY.md](./SECURITY.md).

## Лицензия

GNU General Public License v3.0. Полный текст: [LICENSE](./LICENSE).
Copyright (C) 2026 MootSasa.
