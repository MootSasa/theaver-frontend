[English](#english) | [Русский](#русский)

# Contributing to Theaver / Участие в разработке Theaver

## English

### Branching and Commits

Open pull requests against `beta` (which collects daily work) rather than pushing straight to `main`. Name topic branches by purpose: `feat/<name>` for features, `fix/<name>` for fixes, `chore/<name>` for tooling or CI, and `refactor/<name>` for internal code cleanup.

Write commit messages in English following Conventional Commits, for example `feat(chat): add message translation toggle` or `fix(calls): handle bluetooth route switch`.

Copy local Android config placeholders before running Gradle builds without private Firebase or HMS credentials:

```bash
cp android/app/google-services.json.example android/app/google-services.json
cp android/app/agconnect-services.json.example android/app/agconnect-services.json
flutter pub get
```

### Changelog Fragments

User-facing release notes for GitHub Releases, the in-app update dialog, push alerts, and `theaver.app/changelog` are assembled from bilingual fragment files rather than raw git logs.

If a branch changes something a user will notice:

1. Copy [changelogs/TEMPLATE.md](./changelogs/TEMPLATE.md) to `changelogs/fragments/<topic-slug>.md`.
2. Fill in `type`, plain single-line `summary_ru` and `summary_en`, and user-facing bullets under `### ru` and `### en`.
3. Validate the format with `python3 scripts/calculate_release.py --validate-fragments`.

For pure internal refactoring, tests, docs, or CI edits, skip creating a fragment and include `[no-changelog]` in your PR description. Full guidelines live in [changelogs/README.md](./changelogs/README.md).

### Localization Files

If you add or rename translation strings, keep all ten dictionaries under `assets/l10n/` (`de`, `en`, `es`, `fr`, `it`, `ja`, `ko`, `pt`, `ru`, `zh`) valid JSON and in sync with `en.json` and `ru.json`.

### Pre-PR Checks

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
python3 scripts/calculate_release.py --validate-fragments
```

By opening a pull request against `MootSasa/theaver-frontend`, you agree to license your changes under the **GNU General Public License v3.0** (`GPL-3.0`). See [LICENSE](./LICENSE).

---

## Русский

### Ветки и коммиты

Новая разработка ведётся от ветки `beta`, а в `main` попадают стабильные релизы. Называйте ветки по типу задачи: `feat/<name>` для новых возможностей, `fix/<name>` для исправлений, `chore/<name>` для инфраструктуры и сборки, `refactor/<name>` для внутреннего рефакторинга.

Сообщения коммитов пишутся на английском языке по формату Conventional Commits, например `feat(chat): add message translation toggle` или `fix(calls): handle bluetooth route switch`.

Перед локальной сборкой под Android без приватных ключей скопируйте заглушки конфигов:

```bash
cp android/app/google-services.json.example android/app/google-services.json
cp android/app/agconnect-services.json.example android/app/agconnect-services.json
flutter pub get
```

### Фрагменты для Changelog

Списки изменений для GitHub Releases, диалога обновления в клиенте, push-уведомлений и сайта собираются из двуязычных фрагментов, а не из сырого списка коммитов.

Если ваша ветка меняет что-то заметное для пользователя:

1. Скопируйте [changelogs/TEMPLATE.md](./changelogs/TEMPLATE.md) в `changelogs/fragments/<topic-slug>.md`.
2. Укажите `type`, короткие однострочные `summary_ru` и `summary_en`, а также пункты под заголовками `### ru` и `### en`.
3. Проверьте схему командой `python3 scripts/calculate_release.py --validate-fragments`.

Если правка касается только тестов, CI, документации или внутреннего рефакторинга, фрагмент не нужен — достаточно добавить тег `[no-changelog]` в описание PR. Подробные правила приведены в [changelogs/README.md](./changelogs/README.md).

### Словари локализации

При добавлении или изменении ключей интерфейса проверяйте, что все 10 файлов в `assets/l10n/` (`de`, `en`, `es`, `fr`, `it`, `ja`, `ko`, `pt`, `ru`, `zh`) остаются валидным JSON и содержат нужные переводы.

### Проверки перед отправкой PR

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
python3 scripts/calculate_release.py --validate-fragments
```

Отправляя Pull Request в `MootSasa/theaver-frontend`, вы соглашаетесь с публикацией своего вклада под лицензией **GNU General Public License v3.0** (`GPL-3.0`), см. [LICENSE](./LICENSE).
