[English](#english) | [Русский](#русский)

# Changelog Fragments Guide / Правила оформления Changelog

## English

Theaver release notes appear in four places: the in-app update dialog, push/desktop notifications, [theaver.app/changelog](https://theaver.app/changelog), and [GitHub Releases](https://github.com/MootSasa/theaver-frontend/releases) (where the technical commit log sits folded inside `<details>`).

Instead of copying raw git history into user screens, write a short bilingual fragment in `changelogs/fragments/<topic-slug>.md`.

### Adding an Entry in Your Branch

1. Copy [TEMPLATE.md](./TEMPLATE.md) to `changelogs/fragments/<topic-slug>.md`, for example `changelogs/fragments/voice-noise-suppression.md`.
2. Set `type` to match the user-visible impact:

| Type | Section Heading | Purpose |
|---|---|---|
| `added` | `Added` | New user-facing capability |
| `improved` | `Improved` | UX, layout speed, or polish |
| `fixed` | `Fixed` | Bug users could hit in practice |
| `security` | `Security` | Security fix relevant to end users |

3. Write `summary_ru` and `summary_en` as single plain-text lines (no `**`, backticks, or `#` headings). Push notifications and release card titles read from these two fields.
4. Add 1 to 3 clear bullets (`- ...`) under `### ru` and `### en`.
5. Validate locally:

   ```bash
   python3 scripts/calculate_release.py --validate-fragments
   ```

### Editorial Rules

Describe what changed for the person using the app, and group a multi-commit branch into one concise bullet or a tight pair. Leave out internal refactoring, widget/class renames, unit tests, CI/Docker changes, version bumps in `pubspec.yaml`, regressions fixed inside the same unreleased branch, technical scopes like `**tiling**:`, and commit SHAs.

If a branch makes no user-facing change, skip adding a fragment and write `[no-changelog]` in the PR description.

Bad vs Good:

- **Bad:** `- **tiling**: wrap workspace scaffold and emoji panel in Material to prevent fallback underline text style (efa8fc95)`
- **Good:** `- **Emoji panel:** fixed stray yellow text underlines in the desktop chat workspace.`

### How Releases Pick Up Fragments

`scripts/calculate_release.py` inspects `git diff --diff-filter=AM <tag>..HEAD` on `changelogs/fragments/`. On `beta`, it picks up fragments added or updated since the last tag. On `stable`, it automatically aggregates every fragment merged into beta builds since the previous stable tag. You do not need to delete fragment files after a release.

---

## Русский

Заметки о новых версиях Theaver показываются в окне обновления внутри клиента, в push- и системных уведомлениях, на [theaver.app/ru/changelog](https://theaver.app/ru/changelog) и на странице [GitHub Releases](https://github.com/MootSasa/theaver-frontend/releases) (где технический список коммитов скрыт в спойлере `<details>`).

Чтобы в приложение не попадал сырой вывод `git log`, для каждой заметной задачи создаётся небольшой двуязычный файл в `changelogs/fragments/<topic-slug>.md`.

### Как добавить запись в своей ветке

1. Скопируйте [TEMPLATE.md](./TEMPLATE.md) в `changelogs/fragments/<topic-slug>.md`, например `changelogs/fragments/voice-noise-suppression.md`.
2. Укажите подходящий `type`:

| Тип | Заголовок | Когда использовать |
|---|---|---|
| `added` | `Новое` | Новая заметная функция |
| `improved` | `Улучшения` | Интерфейс, скорость, удобство |
| `fixed` | `Исправления` | Ошибка, заметная пользователям |
| `security` | `Безопасность` | Значимая для пользователей правка защиты |

3. Заполните `summary_ru` и `summary_en` — по одной короткой строке без Markdown (`**`, `` ` ``, `#`). Этот текст идёт в push-уведомления и заголовок карточки на сайте.
4. Напишите 1–3 понятных пункта (`- ...`) в разделах `### ru` и `### en`.
5. Проверьте схему локально:

   ```bash
   python3 scripts/calculate_release.py --validate-fragments
   ```

### О чём писать и что опускать

Пишите о видимом для человека результате и объединяйте серию коммитов одной ветки в 1–3 ясных пункта. Не добавляйте внутренний рефакторинг, имена виджетов и классов, тесты, правки CI и скриптов сборки, обновление версии в `pubspec.yaml`, ошибки, исправленные до выхода релиза, технические префиксы (`**tiling**:`) и SHA-хэши коммитов.

Если ветка не меняет поведение приложения для пользователя, фрагмент не нужен — укажите `[no-changelog]` в описании Pull Request.

Сравнение формулировок:

- **Плохо:** `- **tiling**: wrap workspace scaffold and emoji panel in Material to prevent fallback underline text style (efa8fc95)`
- **Хорошо:** `- **Панель эмодзи:** убрано случайное жёлтое подчёркивание текста в окне чата на компьютере.`

- **Плохо:** `- **account**: add POST /api/security/account/delete/confirm and SecurityScreen dialog`
- **Хорошо:** `- **Удаление аккаунта:** в настройках безопасности появилось самостоятельное удаление аккаунта с кодом на почту и 7-дневным периодом отмены.`

### Как скрипт собирает фрагменты

`scripts/calculate_release.py` определяет прошлый тег и собирает фрагменты через `git diff --diff-filter=AM <tag>..HEAD`. На канале `beta` берутся изменения с прошлой беты, а на канале `stable` автоматически объединяются все фрагменты, вышедшие в бета-сборках со времени последнего стабильного тега. Удалять файлы после релиза вручную или автокоммитом не нужно.
