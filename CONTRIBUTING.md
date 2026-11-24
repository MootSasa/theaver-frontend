# Contributing to Theaver

Thanks for taking the time to contribute to the Theaver Flutter client.

## Development Workflow

1. **Fork and branch from `beta`** (active integration happens on `beta`; `main` tracks stable releases).
   Use descriptive branch names matching the workspace convention:
   - `feat/<short-name>` for new user-facing features
   - `fix/<short-name>` for bug fixes
   - `chore/<short-name>` for tooling, CI, or dependency maintenance
   - `refactor/<short-name>` for internal code restructuring

2. **Prepare local Android config files** (never commit real keys):

   ```bash
   cp android/app/google-services.json.example android/app/google-services.json
   cp android/app/agconnect-services.json.example android/app/agconnect-services.json
   flutter pub get
   ```

3. **Follow Conventional Commits in English:**
   - Examples: `feat(chat): add message translation toggle`, `fix(calls): handle bluetooth route switch`, `chore(ci): cache pub dependencies`

## Writing Changelog Fragments (Required for User-Facing Changes)

Release notes shown in GitHub Releases, the in-app update dialog, push notifications, and `theaver.app/changelog` are assembled from bilingual fragments—never raw commit lists.

For any `feat/*`, `fix/*`, or noticeable UX/performance change:

1. Copy [`changelogs/TEMPLATE.md`](./changelogs/TEMPLATE.md) to `changelogs/fragments/<topic-slug>.md`.
2. Fill in `type`, one-line `summary_ru` / `summary_en`, and user-focused bullets under `### ru` and `### en`.
3. Validate locally:

   ```bash
   python3 scripts/calculate_release.py --validate-fragments
   ```

See [`changelogs/README.md`](./changelogs/README.md) for editorial rules and examples.

If a PR touches only tests, CI workflows, internal refactoring, or documentation without any user-facing change, omit the fragment and include `[no-changelog]` in your PR description.

## Localization (`assets/l10n/*.json`)

If you add or rename UI translation keys, keep all 10 dictionaries (`de`, `en`, `es`, `fr`, `it`, `ja`, `ko`, `pt`, `ru`, `zh`) valid JSON and aligned with `en.json` and `ru.json`.

## Checks Before Submitting a PR

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
python3 scripts/calculate_release.py --validate-fragments
```

## Licensing

By submitting a pull request to `MootSasa/theaver-frontend`, you agree that your contributions will be licensed under the **GNU General Public License v3.0** (`GPL-3.0`), matching [`LICENSE`](./LICENSE).
