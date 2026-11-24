## Summary

<!-- Briefly describe what this pull request changes and why. -->

## Verification

- [ ] `flutter analyze --no-fatal-infos --no-fatal-warnings` passes
- [ ] `flutter test` passes
- [ ] `python3 scripts/calculate_release.py --validate-fragments` passes

## Checklist

- [ ] If user-facing behavior changed, added a bilingual fragment in `changelogs/fragments/<topic-slug>.md` (or included `[no-changelog]` above for internal/CI/docs-only changes)
- [ ] If UI text changed, kept all localization files under `assets/l10n/*.json` valid and consistent
- [ ] No secrets, keystores, or real Firebase/HMS credentials are included
