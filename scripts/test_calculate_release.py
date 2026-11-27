#!/usr/bin/env python3
"""Unit tests for bilingual changelog fragment validation and release notes assembly."""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import calculate_release as cr


VALID_FRAGMENT = """---
type: added
summary_ru: Адаптивная сетка GIF и быстрый предпросмотр
summary_en: Justified GIF grid with quick preview
---

### ru
- **GIF в чатах:** добавлена адаптивная сетка и предпросмотр по удержанию.

### en
- **GIFs in chats:** added a justified grid with press-and-hold preview.
"""


class CalculateReleaseTests(unittest.TestCase):
    def test_parse_valid_fragment_and_aliases(self):
        frag = cr.parse_fragment_text(VALID_FRAGMENT, "gif-grid.md")
        self.assertEqual(frag["type"], "added")
        self.assertEqual(frag["summary_ru"], "Адаптивная сетка GIF и быстрый предпросмотр")
        self.assertEqual(frag["summary_en"], "Justified GIF grid with quick preview")
        self.assertEqual(len(frag["ru"]), 1)
        self.assertEqual(len(frag["en"]), 1)

        perf_frag = cr.parse_fragment_text(
            VALID_FRAGMENT.replace("type: added", "type: perf # alias"),
            "perf-alias.md",
        )
        self.assertEqual(perf_frag["type"], "improved")

    def test_reject_invalid_fragments(self):
        bad_cases = [
            "No frontmatter at all",
            "---\ntype: chore\nsummary_ru: тест\nsummary_en: test\n---\n### ru\n- а\n### en\n- b\n",
            "---\ntype: fixed\nsummary_ru:\nsummary_en: Fix\n---\n### ru\n- а\n### en\n- b\n",
            "---\ntype: fixed\nsummary_ru: Исправлено\nsummary_en: Fixed\n---\n### ru\n- Только русский\n",
            "---\ntype: fixed\nsummary_ru: # Заголовок\nsummary_en: Fixed\n---\n### ru\n- а\n### en\n- b\n",
        ]
        for idx, sample in enumerate(bad_cases):
            with self.subTest(case=idx):
                with self.assertRaises(cr.FragmentValidationError):
                    cr.parse_fragment_text(sample, f"bad-{idx}.md")

    def test_build_release_documents_from_fragments(self):
        frag1 = cr.parse_fragment_text(VALID_FRAGMENT, "gif-grid.md")
        frag2 = cr.parse_fragment_text(
            """---
type: fixed
summary_ru: Исправлен сбой перехода к профилю
summary_en: Fixed crash when opening chat profile
---

### ru
- **Профиль чата:** исправлен редкий сбой при быстром открытии карточки контакта.

### en
- **Chat profile:** fixed an occasional crash when opening a contact card quickly.
""",
            "profile-fix.md",
        )
        commits = {
            "feat": [("12345678", "**gif**: add grid view")],
            "fix": [],
            "perf": [],
            "refactor": [("abcdef01", "cleanup widget tree")],
            "chore": [("9999aaaa", "bump deps")],
            "other": [],
        }

        app_notes, gh_notes, changelog_entry = cr.build_release_documents(
            version="1.21.0-beta.440",
            channel="beta",
            fragments=[frag1, frag2],
            categorized_commits=commits,
            release_date="2026-11-24",
        )

        # App/API notes contain clean bilingual sections + summaries, without commit SHAs or chore noise
        self.assertIn("<!-- lang:ru -->", app_notes)
        self.assertIn("<!-- /lang:ru -->", app_notes)
        self.assertIn("<!-- lang:en -->", app_notes)
        self.assertIn("<!-- summary: Адаптивная сетка GIF и быстрый предпросмотр; Исправлен сбой перехода к профилю -->", app_notes)
        self.assertNotIn("12345678", app_notes)
        self.assertNotIn("cleanup widget tree", app_notes)
        self.assertNotIn("bump deps", app_notes)

        # GitHub release notes include both languages, verification guidance, and collapsible commit log
        self.assertIn("# Theaver v1.21.0-beta.440 (Beta)", gh_notes)
        self.assertIn("SHA256SUMS.txt", gh_notes)
        self.assertIn("<details>", gh_notes)
        self.assertIn("Technical commit log (3 commits)", gh_notes)
        self.assertIn("`12345678`", gh_notes)

        # CHANGELOG entry carries both English and Russian sections
        self.assertIn("## [1.21.0-beta.440] — 2026-11-24", changelog_entry)
        self.assertIn("- **Added:**", changelog_entry)
        self.assertIn("- **Исправления:**", changelog_entry)

    def test_build_release_documents_fallback_without_fragments(self):
        commits = {
            "feat": [("aabbcc11", "**chat**: add quick reactions")],
            "fix": [("ddeeff22", "**calls**: reconnect after wifi switch")],
            "perf": [],
            "refactor": [("11223344", "rename internal controller")],
            "chore": [("55667788", "update workflow yaml")],
            "other": [],
        }
        app_notes, gh_notes, _ = cr.build_release_documents(
            version="1.20.4",
            channel="stable",
            fragments=[],
            categorized_commits=commits,
            release_date="2026-11-24",
        )

        # Fallback strips technical scope prefix and commit hashes, and drops chore/refactor
        self.assertIn("- Add quick reactions", app_notes)
        self.assertIn("- Reconnect after wifi switch", app_notes)
        self.assertNotIn("**chat**:", app_notes)
        self.assertNotIn("aabbcc11", app_notes)
        self.assertNotIn("rename internal controller", app_notes)
        self.assertNotIn("update workflow yaml", app_notes)
        self.assertIn("`55667788`", gh_notes)

    def test_validate_and_prepend_changelog_on_disk(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            frag_dir = os.path.join(tmpdir, "changelogs", "fragments")
            os.makedirs(frag_dir, exist_ok=True)
            with open(os.path.join(frag_dir, "README.md"), "w", encoding="utf-8") as fh:
                fh.write("# Guide\n")
            with open(os.path.join(frag_dir, "feature-one.md"), "w", encoding="utf-8") as fh:
                fh.write(VALID_FRAGMENT)

            parsed, errors = cr.validate_all_fragments(tmpdir)
            self.assertEqual(errors, [])
            self.assertEqual(len(parsed), 1)

            cl_path = os.path.join(tmpdir, "CHANGELOG.md")
            inserted = cr.prepend_changelog_file(cl_path, "1.21.0", "## [1.21.0] — 2026-11-24\n- Item")
            self.assertTrue(inserted)
            inserted_again = cr.prepend_changelog_file(cl_path, "1.21.0", "## [1.21.0] — 2026-11-24\n- Item")
            self.assertFalse(inserted_again)

    def test_previous_tag_resolution_for_tag_trigger(self):
        tags = ["v1.21.0", "v1.20.9-beta.435", "v1.20.0", "v1.19.0"]
        self.assertEqual(cr.get_previous_tag_for_changelog(tags, "stable", current_tag="v1.21.0"), "v1.20.0")
        self.assertEqual(cr.get_previous_tag_for_changelog(tags, "beta", current_tag="v1.20.9-beta.435"), "v1.20.0")


if __name__ == "__main__":
    unittest.main()
