## Summary / Описание

<!-- Briefly explain what this PR changes and why. / Кратко опишите изменения и цель PR. -->

## Verification / Проверка

- [ ] `flutter analyze --no-fatal-infos --no-fatal-warnings` passes / без ошибок
- [ ] `flutter test` passes / тесты пройдены
- [ ] `python3 scripts/calculate_release.py --validate-fragments` passes / фрагменты валидны

## Checklist / Чеклист

- [ ] Added a bilingual changelog fragment in `changelogs/fragments/<topic-slug>.md` for user-facing changes (or included `[no-changelog]` above for internal/CI/docs work) / Добавлен двуязычный фрагмент changelog или тег `[no-changelog]`
- [ ] Kept all localization files in `assets/l10n/*.json` valid JSON and consistent / Словари локализации валидны
- [ ] Included no secrets, keystores, or real Firebase/HMS configs / Нет секретов и реальных конфигов ключей
