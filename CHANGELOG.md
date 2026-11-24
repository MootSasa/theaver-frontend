# Changelog

User-facing release history for **Theaver**. Full release packages and checksums are published on [GitHub Releases](https://github.com/MootSasa/theaver-frontend/releases) and [`theaver.app/changelog`](https://theaver.app/changelog).

New changes are authored as bilingual fragments under [`changelogs/fragments/`](./changelogs/README.md) and compiled automatically during release builds.

---

## [1.20.3-beta.429] — 2026-11-09

### English
- **Improved:** Opening chats and profile panels transitions smoothly without dropped frames.
- **Fixed:** Custom emoji and internal storage media links no longer show blank web link preview cards inside message bubbles.
- **Fixed:** Animated stickers and GIFs no longer stutter when scrolling fast through long chats.

### Русский
- **Улучшения:** Переход между списком чатов, диалогом и профилем стал плавнее и без пропусков кадров.
- **Исправления:** Кастомные эмодзи и внутренние ссылки хранилища больше не рисуют лишнюю карточку превью веб-страницы в пузыре сообщения.
- **Исправления:** Анимации стикеров и GIF перестали подёргиваться при быстром пролистывании ленты чата.

---

## [1.20.0-beta.423] — 2026-11-09

### English
- **Added:** Upgraded Mini Apps to v8.0 with ETag caching, safe HUD insets, and faster launch events.
- **Added:** Added automated Authenticode signing for Windows installers and GPG signatures for Linux archives.
- **Improved:** Tightened validation checks across Bot API calls and Walt (`THV`) ledger transfers.

### Русский
- **Новое:** Обновили Mini Apps до версии v8.0 с кэшированием ETag, безопасными отступами экрана и быстрым запуском.
- **Новое:** Включили автоматическую подпись установщиков для Windows и GPG-подписи для архивов Linux.
- **Улучшения:** Добавили дополнительные проверки для запросов Bot API и переводов в кошельке Walt (`THV`).

---

## [1.19.0-beta.421] — 2026-11-08

### English
- **Added:** Added a dedicated Emoji & Sticker side panel for wide desktop windows.
- **Added:** Built a justified GIF grid with press-and-hold preview and full-resolution sending.
- **Added:** Added direct Telegram sticker pack import with live progress inside the app.
- **Improved:** Off-screen animated stickers and GIFs now pause automatically, keeping scrolling smooth on high-refresh-rate displays.

### Русский
- **Новое:** Добавили отдельную боковую панель эмодзи и стикеров для многооконного режима на компьютере.
- **Новое:** Сделали адаптивную сетку GIF с предпросмотром по удержанию и отправкой в полном качестве.
- **Новое:** Появился импорт наборов стикеров из Telegram с отображением прогресса прямо в клиенте.
- **Улучшения:** Стикеры и GIF за пределами экрана теперь ставятся на паузу, чтобы не нагружать процессор и батарею.

---

## [1.18.0-beta.400] — 2026-11-07

### English
- **Added:** Added voice calls, 1080p60 screen sharing, and voice channels inside communities.
- **Added:** Added call summary cards in chat history along with per-chat notification settings.

### Русский
- **Новое:** Запустили аудио- и видеозвонки, показ экрана 1080p60 и голосовые комнаты в сообществах.
- **Новое:** В истории чата появились карточки итогов звонков и раздельные настройки уведомлений.
