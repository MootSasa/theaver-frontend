#!/usr/bin/env python3
"""
Calculate semantic release version and curated bilingual changelog.
Reads structured fragments from changelogs/fragments/ (or falls back to
user-facing Conventional Commits) and generates:
  - release_notes.md for the Backend API, app UpdateDialog, website, and push alerts
  - github_release_notes.md for GitHub Releases (EN + RU + collapsible commit log)
"""

import argparse
from datetime import date
import os
import re
import subprocess
import sys


CATEGORY_ORDER = ("added", "improved", "fixed", "security")

TYPE_ALIASES = {
    "added": "added",
    "feat": "added",
    "feature": "added",
    "improved": "improved",
    "perf": "improved",
    "improvement": "improved",
    "fixed": "fixed",
    "fix": "fixed",
    "bugfix": "fixed",
    "security": "security",
}

CATEGORY_TITLES_RU = {
    "added": "Новое",
    "improved": "Улучшения",
    "fixed": "Исправления",
    "security": "Безопасность",
}

CATEGORY_TITLES_EN = {
    "added": "Added",
    "improved": "Improved",
    "fixed": "Fixed",
    "security": "Security",
}

SKIPPED_MD_NAMES = {"README.md", "TEMPLATE.md"}
SHA_SUFFIX_RE = re.compile(r"\s*\(`?[0-9a-f]{6,40}`?\)\s*$", re.IGNORECASE)
SCOPE_PREFIX_RE = re.compile(r"^\*\*[^*]+?\*\*:\s*")


class FragmentValidationError(ValueError):
    """Raised when a changelog fragment fails schema or content validation."""


def run_git(args, cwd=None):
    result = subprocess.run(
        ["git"] + args,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return result.stdout.strip(), result.returncode


def get_current_branch():
    branch, code = run_git(["rev-parse", "--abbrev-ref", "HEAD"])
    if code == 0 and branch and branch != "HEAD":
        return branch
    ref_name = os.environ.get("GITHUB_REF_NAME", "")
    if ref_name:
        return ref_name
    head_ref = os.environ.get("GITHUB_HEAD_REF", "")
    if head_ref:
        return head_ref
    return "main"


def get_commit_count():
    count_str, code = run_git(["rev-list", "--count", "HEAD"])
    if code == 0 and count_str.isdigit():
        return int(count_str)
    return 1


def parse_semver(v_str):
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)", v_str)
    if m:
        return int(m.group(1)), int(m.group(2)), int(m.group(3))
    return 0, 0, 0


def parse_tag_sort_key(tag_str):
    clean = tag_str.lstrip("v")
    base_part = clean.split("-", 1)[0]
    major, minor, patch = parse_semver(base_part)
    if "-" not in clean:
        # Stable release ranks higher than pre-release of the same X.Y.Z
        return (major, minor, patch, 1, 0)
    prerelease_part = clean.split("-", 1)[1]
    nums = re.findall(r"\d+", prerelease_part)
    pre_num = int(nums[-1]) if nums else 0
    return (major, minor, patch, 0, pre_num)


def get_all_version_tags():
    out, code = run_git(["tag", "-l", "v[0-9]*"])
    if code == 0 and out.strip():
        tags = [t.strip() for t in out.strip().splitlines() if t.strip()]
        tags.sort(key=parse_tag_sort_key, reverse=True)
        return tags
    return []


def get_latest_tag():
    tags = get_all_version_tags()
    return tags[0] if tags else ""


def get_latest_stable_tag():
    tags = get_all_version_tags()
    for t in tags:
        clean = t.lstrip("v")
        if re.match(r"^\d+\.\d+\.\d+$", clean):
            return t
    return ""


def get_previous_tag_for_changelog(tags, channel, current_tag=None):
    """Return the baseline tag used to compute commits and fragments for this release."""
    if current_tag:
        cur_key = parse_tag_sort_key(current_tag)
        filtered = [t for t in tags if t != current_tag and parse_tag_sort_key(t) < cur_key]
    else:
        filtered = list(tags)
    if channel == "stable":
        for t in filtered:
            if re.match(r"^\d+\.\d+\.\d+$", t.lstrip("v")):
                return t
    return filtered[0] if filtered else ""


def get_pubspec_version(pubspec_path="pubspec.yaml"):
    if os.path.exists(pubspec_path):
        try:
            with open(pubspec_path, "r", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("version:"):
                        val = line.split(":", 1)[1].strip()
                        ver = val.split("+")[0].strip()
                        if re.match(r"^\d+\.\d+\.\d+$", ver):
                            return ver
        except Exception:
            pass
    return ""


def get_base_version(pubspec_path="pubspec.yaml"):
    latest_tag = get_latest_tag()
    tag_clean = re.sub(r"-[a-zA-Z0-9\.]+$", "", latest_tag).lstrip("v") if latest_tag else ""
    tag_semver = parse_semver(tag_clean) if tag_clean else (0, 0, 0)

    pub_ver = get_pubspec_version(pubspec_path)
    pub_semver = parse_semver(pub_ver) if pub_ver else (0, 0, 0)

    major, minor, patch = max(tag_semver, pub_semver)
    if (major, minor, patch) == (0, 0, 0):
        return "1.0.0"
    return f"{major}.{minor}.{patch}"


def get_commits_since_tag(tag):
    if tag:
        _, code = run_git(["rev-parse", tag])
        range_spec = f"{tag}..HEAD" if code == 0 else "HEAD~50..HEAD"
    else:
        range_spec = "HEAD~50..HEAD"

    _, code = run_git(["rev-parse", range_spec.split("..")[0]])
    if code != 0:
        range_spec = "HEAD"

    output, code = run_git(["log", range_spec, "--pretty=format:%H|%s|%b<END_OF_COMMIT>"])
    if code != 0 or not output:
        output, _ = run_git(["log", "-n", "30", "--pretty=format:%H|%s|%b<END_OF_COMMIT>"])

    commits = []
    if not output:
        return commits

    for item in output.split("<END_OF_COMMIT>"):
        item = item.strip()
        if not item:
            continue
        parts = item.split("|", 2)
        sha = parts[0].strip()
        subject = parts[1].strip() if len(parts) > 1 else ""
        body = parts[2].strip() if len(parts) > 2 else ""
        commits.append(
            {
                "sha": sha[:8],
                "subject": subject,
                "body": body,
                "message": f"{subject}\n{body}".strip(),
            }
        )
    return commits


def analyze_commits(commits):
    has_breaking = False
    has_feat = False
    has_fix = False

    categorized = {
        "feat": [],
        "fix": [],
        "perf": [],
        "refactor": [],
        "chore": [],
        "other": [],
    }

    cc_re = re.compile(r"^([a-zA-Z]+)(?:\(([^\)]+)\))?(!)?:\s*(.*)$")

    for c in commits:
        sub = c["subject"]
        msg = c["message"]

        if (
            sub.startswith("Merge pull request ")
            or sub.startswith("Merge branch ")
            or sub.startswith("Merge remote-tracking branch ")
        ):
            continue

        if "BREAKING CHANGE:" in msg or "BREAKING-CHANGE:" in msg:
            has_breaking = True

        m = cc_re.match(sub)
        if m:
            ctype = m.group(1).lower()
            scope = m.group(2)
            breaking_bang = m.group(3)
            desc = m.group(4)

            if breaking_bang:
                has_breaking = True

            formatted_desc = f"**{scope}**: {desc}" if scope else desc

            if ctype == "feat":
                has_feat = True
                categorized["feat"].append((c["sha"], formatted_desc))
            elif ctype == "fix":
                has_fix = True
                categorized["fix"].append((c["sha"], formatted_desc))
            elif ctype == "perf":
                categorized["perf"].append((c["sha"], formatted_desc))
            elif ctype == "refactor":
                categorized["refactor"].append((c["sha"], formatted_desc))
            elif ctype in ("chore", "ci", "build", "test", "docs", "style"):
                categorized["chore"].append((c["sha"], formatted_desc))
            else:
                categorized["other"].append((c["sha"], formatted_desc))
        else:
            categorized["other"].append((c["sha"], sub))

    if has_breaking:
        bump = "major"
    elif has_feat:
        bump = "minor"
    elif has_fix:
        bump = "patch"
    else:
        bump = "patch"

    return bump, categorized


def _strip_quotes(val):
    val = val.strip()
    if len(val) >= 2 and ((val[0] == '"' and val[-1] == '"') or (val[0] == "'" and val[-1] == "'")):
        return val[1:-1].strip()
    return val


def parse_fragment_text(text, source_name="<fragment>"):
    """Parse and validate a bilingual changelog fragment string."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        raise FragmentValidationError(f"{source_name}: missing opening YAML frontmatter '---'")

    end_idx = None
    for idx in range(1, len(lines)):
        if lines[idx].strip() == "---":
            end_idx = idx
            break
    if end_idx is None:
        raise FragmentValidationError(f"{source_name}: missing closing YAML frontmatter '---'")

    meta = {}
    for line in lines[1:end_idx]:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if ":" not in stripped:
            raise FragmentValidationError(f"{source_name}: invalid frontmatter line '{stripped}'")
        key, raw_val = stripped.split(":", 1)
        meta[key.strip().lower()] = raw_val.strip()

    raw_type = meta.get("type", "").split("#", 1)[0].strip().lower()
    raw_type = _strip_quotes(raw_type)
    norm_type = TYPE_ALIASES.get(raw_type)
    if not norm_type:
        raise FragmentValidationError(
            f"{source_name}: invalid or missing 'type' ({raw_type!r}); expected one of added, improved, fixed, security"
        )

    summary_ru = _strip_quotes(meta.get("summary_ru", ""))
    summary_en = _strip_quotes(meta.get("summary_en", ""))
    for field_name, summary_val in (("summary_ru", summary_ru), ("summary_en", summary_en)):
        if not summary_val:
            raise FragmentValidationError(f"{source_name}: '{field_name}' must be non-empty")
        if summary_val.startswith("#") or "<!--" in summary_val or "-->" in summary_val:
            raise FragmentValidationError(f"{source_name}: '{field_name}' must be plain text without headings or HTML comments")

    sections = {"ru": [], "en": []}
    current_lang = None
    lang_re = re.compile(r"^#{2,3}\s*(ru|en)\s*$", re.IGNORECASE)
    bullet_re = re.compile(r"^(?:[-*•])\s+(.*)$")

    for raw_line in lines[end_idx + 1 :]:
        line = raw_line.rstrip()
        stripped = line.strip()
        if not stripped:
            continue
        m_lang = lang_re.match(stripped)
        if m_lang:
            current_lang = m_lang.group(1).lower()
            continue
        if current_lang is None:
            continue
        m_bullet = bullet_re.match(stripped)
        if m_bullet:
            bullet_text = m_bullet.group(1).strip()
            if bullet_text:
                sections[current_lang].append(bullet_text)
        elif line.startswith((" ", "\t")) and sections[current_lang]:
            sections[current_lang][-1] = f"{sections[current_lang][-1]} {stripped}".strip()
        elif not stripped.startswith("#"):
            sections[current_lang].append(stripped)

    if not sections["ru"]:
        raise FragmentValidationError(f"{source_name}: missing bullet items under '### ru'")
    if not sections["en"]:
        raise FragmentValidationError(f"{source_name}: missing bullet items under '### en'")

    return {
        "source": source_name,
        "type": norm_type,
        "summary_ru": summary_ru,
        "summary_en": summary_en,
        "ru": sections["ru"],
        "en": sections["en"],
    }


def list_all_fragment_files(base_dir="."):
    """Return sorted relative paths of all fragment Markdown files."""
    files = []
    for sub in ("changelogs/fragments", "changelogs/unreleased"):
        folder = os.path.join(base_dir, sub)
        if not os.path.isdir(folder):
            continue
        for entry in sorted(os.listdir(folder)):
            if not entry.endswith(".md") or entry.startswith(".") or entry in SKIPPED_MD_NAMES:
                continue
            full_path = os.path.join(folder, entry)
            if os.path.isfile(full_path):
                files.append(os.path.relpath(full_path, base_dir).replace("\\", "/"))
    return sorted(set(files))


def validate_all_fragments(base_dir="."):
    """Validate every fragment file present under changelogs/fragments and changelogs/unreleased."""
    files = list_all_fragment_files(base_dir=base_dir)
    parsed = []
    errors = []
    for rel_path in files:
        full_path = os.path.join(base_dir, rel_path)
        try:
            with open(full_path, "r", encoding="utf-8") as fh:
                parsed.append(parse_fragment_text(fh.read(), source_name=rel_path))
        except FragmentValidationError as exc:
            errors.append(str(exc))
    return parsed, errors


def get_fragments_since_tag(tag, base_dir="."):
    """Discover fragment files added or modified since `tag` (or all if `tag` is empty)."""
    if not tag:
        candidate_paths = list_all_fragment_files(base_dir=base_dir)
    else:
        _, code = run_git(["rev-parse", "--verify", tag], cwd=base_dir)
        if code != 0:
            candidate_paths = list_all_fragment_files(base_dir=base_dir)
        else:
            out, diff_code = run_git(
                [
                    "diff",
                    "--relative",
                    "--diff-filter=AM",
                    "--name-only",
                    f"{tag}..HEAD",
                    "--",
                    "changelogs/fragments",
                    "changelogs/unreleased",
                ],
                cwd=base_dir,
            )
            paths = set()
            if diff_code == 0 and out:
                for line in out.splitlines():
                    p = line.strip().replace("\\", "/")
                    name = os.path.basename(p)
                    if p.endswith(".md") and not name.startswith(".") and name not in SKIPPED_MD_NAMES:
                        if os.path.isfile(os.path.join(base_dir, p)):
                            paths.add(p)

            # Also pick up untracked/staged local fragments when run interactively
            st_out, st_code = run_git(
                ["status", "--porcelain", "-uall", "--", "changelogs/fragments", "changelogs/unreleased"],
                cwd=base_dir,
            )
            if st_code == 0 and st_out:
                for line in st_out.splitlines():
                    if len(line) < 4:
                        continue
                    status_code = line[:2]
                    if "D" in status_code:
                        continue
                    rel = line[3:].strip().strip('"').replace("\\", "/")
                    if " -> " in rel:
                        rel = rel.split(" -> ", 1)[1].strip()
                    name = os.path.basename(rel)
                    if rel.endswith(".md") and not name.startswith(".") and name not in SKIPPED_MD_NAMES:
                        if os.path.isfile(os.path.join(base_dir, rel)):
                            paths.add(rel)

            candidate_paths = sorted(paths)

    parsed = []
    for rel_path in candidate_paths:
        full_path = os.path.join(base_dir, rel_path)
        if not os.path.isfile(full_path):
            continue
        with open(full_path, "r", encoding="utf-8") as fh:
            parsed.append(parse_fragment_text(fh.read(), source_name=rel_path))
    return parsed


def _clean_commit_for_user(raw_desc):
    text = SHA_SUFFIX_RE.sub("", raw_desc).strip()
    text = SCOPE_PREFIX_RE.sub("", text).strip()
    if text:
        text = text[0].upper() + text[1:]
    return text


def _combine_summaries(fragments, key, max_len=140):
    priority = {cat: idx for idx, cat in enumerate(("added", "security", "improved", "fixed"))}
    ordered = sorted(fragments, key=lambda f: priority.get(f["type"], 99))
    seen = []
    for frag in ordered:
        s = frag[key].strip().rstrip(".")
        if s and s not in seen:
            seen.append(s)
    if not seen:
        return ""
    if len(seen) == 1:
        combined = seen[0]
    else:
        combined = seen[0]
        for nxt in seen[1:3]:
            candidate = f"{combined}; {nxt}"
            if len(candidate) <= max_len:
                combined = candidate
    if len(combined) > max_len:
        cut = combined[: max_len - 1].rsplit(" ", 1)[0]
        combined = (cut if cut else combined[: max_len - 1]).rstrip(" ,;:-") + "…"
    return combined


def _render_category_sections(buckets, titles_map):
    parts = []
    for cat in CATEGORY_ORDER:
        items = buckets.get(cat, [])
        if not items:
            continue
        lines = [f"### {titles_map[cat]}"]
        for item in items:
            lines.append(f"- {item}")
        parts.append("\n".join(lines))
    return "\n\n".join(parts)


def build_release_documents(version, channel, fragments, categorized_commits, release_date=None):
    """Build bilingual app/API notes, rich GitHub notes, and CHANGELOG.md block."""
    ru_buckets = {cat: [] for cat in CATEGORY_ORDER}
    en_buckets = {cat: [] for cat in CATEGORY_ORDER}

    if fragments:
        for frag in fragments:
            cat = frag["type"]
            ru_buckets[cat].extend(frag["ru"])
            en_buckets[cat].extend(frag["en"])
        summary_ru = _combine_summaries(fragments, "summary_ru")
        summary_en = _combine_summaries(fragments, "summary_en")
    else:
        for _, raw_desc in categorized_commits.get("feat", []):
            en_buckets["added"].append(_clean_commit_for_user(raw_desc))
            ru_buckets["added"].append(_clean_commit_for_user(raw_desc))
        for _, raw_desc in categorized_commits.get("perf", []):
            en_buckets["improved"].append(_clean_commit_for_user(raw_desc))
            ru_buckets["improved"].append(_clean_commit_for_user(raw_desc))
        for _, raw_desc in categorized_commits.get("fix", []):
            en_buckets["fixed"].append(_clean_commit_for_user(raw_desc))
            ru_buckets["fixed"].append(_clean_commit_for_user(raw_desc))

        if not any(en_buckets.values()):
            ru_buckets["improved"].append("Плановое обновление стабильности и производительности клиента.")
            en_buckets["improved"].append("Scheduled client stability and performance update.")

        if en_buckets["added"] or en_buckets["improved"]:
            summary_ru = f"Новые возможности и улучшения стабильности в Theaver v{version}"
            summary_en = f"New features and stability improvements in Theaver v{version}"
        else:
            summary_ru = f"Исправления ошибок и повышение стабильности в Theaver v{version}"
            summary_en = f"Bug fixes and stability improvements in Theaver v{version}"

    ru_body = _render_category_sections(ru_buckets, CATEGORY_TITLES_RU)
    en_body = _render_category_sections(en_buckets, CATEGORY_TITLES_EN)

    app_notes = "\n".join(
        [
            "<!-- lang:ru -->",
            f"<!-- summary: {summary_ru} -->",
            ru_body,
            "<!-- /lang:ru -->",
            "",
            "<!-- lang:en -->",
            f"<!-- summary: {summary_en} -->",
            en_body,
            "<!-- /lang:en -->",
        ]
    ).strip()

    commit_titles = [
        ("feat", "Features"),
        ("fix", "Bug Fixes"),
        ("perf", "Performance"),
        ("refactor", "Refactoring"),
        ("chore", "Maintenance & Build"),
        ("other", "Other Commits"),
    ]
    tech_sections = []
    total_commits = 0
    for key, label in commit_titles:
        items = categorized_commits.get(key, [])
        if not items:
            continue
        total_commits += len(items)
        sec_lines = [f"### {label}"]
        for sha, desc in items:
            sec_lines.append(f"- {desc} (`{sha}`)")
        tech_sections.append("\n".join(sec_lines))

    gh_parts = [
        f"# Theaver v{version} ({channel.capitalize()})",
        "",
        f"**Summary:** {summary_en}",
        f"**Кратко:** {summary_ru}",
        "",
        "## What's Changed (English)",
        "",
        en_body,
        "",
        "## Что нового (Русский)",
        "",
        ru_body,
        "",
        "---",
        "",
        "Verify downloads using `SHA256SUMS.txt` and the public keys in "
        "[`signing/`](https://github.com/MootSasa/theaver-frontend/tree/main/signing) "
        "([verification guide](https://theaver.app/docs/guide/verify-downloads)).",
    ]
    if tech_sections:
        gh_parts.extend(
            [
                "",
                "<details>",
                f"<summary>Technical commit log ({total_commits} commits)</summary>",
                "",
                "\n\n".join(tech_sections),
                "",
                "</details>",
            ]
        )
    github_notes = "\n".join(gh_parts).strip()

    day = release_date or date.today().isoformat()
    changelog_parts = [f"## [{version}] — {day}", "", "### English"]
    for cat in CATEGORY_ORDER:
        for item in en_buckets.get(cat, []):
            changelog_parts.append(f"- **{CATEGORY_TITLES_EN[cat]}:** {item}")
    changelog_parts.extend(["", "### Русский"])
    for cat in CATEGORY_ORDER:
        for item in ru_buckets.get(cat, []):
            changelog_parts.append(f"- **{CATEGORY_TITLES_RU[cat]}:** {item}")
    changelog_entry = "\n".join(changelog_parts).strip()

    return app_notes, github_notes, changelog_entry


def prepend_changelog_file(changelog_path, version, entry_block):
    """Insert `entry_block` at the top of release history inside CHANGELOG.md unless version exists."""
    header = (
        "# Changelog\n\n"
        "User-facing release history for **Theaver**. Full release packages and checksums are published on "
        "[GitHub Releases](https://github.com/MootSasa/theaver-frontend/releases) and "
        "[`theaver.app/changelog`](https://theaver.app/changelog).\n\n"
        "New changes are authored as bilingual fragments under [`changelogs/fragments/`](./changelogs/README.md) "
        "and compiled automatically during release builds.\n\n---\n"
    )
    if os.path.exists(changelog_path):
        with open(changelog_path, "r", encoding="utf-8") as fh:
            existing = fh.read()
        if f"## [{version}]" in existing:
            return False
        marker = "\n---\n"
        idx = existing.find(marker)
        if idx != -1:
            split_at = idx + len(marker)
            prefix = existing[:split_at]
            rest = existing[split_at:].lstrip("\n")
            updated = f"{prefix}\n{entry_block}\n\n---\n\n{rest}".rstrip() + "\n"
        else:
            updated = f"{header}\n{entry_block}\n\n{existing.lstrip()}".rstrip() + "\n"
    else:
        updated = f"{header}\n{entry_block}\n"

    with open(changelog_path, "w", encoding="utf-8") as fh:
        fh.write(updated)
    return True


def main():
    parser = argparse.ArgumentParser(description="Calculate semantic version and bilingual changelog.")
    parser.add_argument(
        "--channel",
        choices=["stable", "beta", "alpha"],
        default=None,
        help="Target release channel (stable, beta, alpha). Defaults based on branch.",
    )
    parser.add_argument(
        "--bump",
        choices=["auto", "patch", "minor", "major", "custom"],
        default="auto",
        help="Type of version bump.",
    )
    parser.add_argument("--custom-version", default="", help="Custom version if bump=custom.")
    parser.add_argument("--output-file", default="release_notes.md", help="File to write app/API release notes to.")
    parser.add_argument(
        "--github-notes-file",
        default="",
        help="Optional file to write full GitHub Release body (with collapsible commit log).",
    )
    parser.add_argument(
        "--validate-fragments",
        action="store_true",
        help="Validate all changelog fragments under changelogs/fragments/ and exit.",
    )
    parser.add_argument(
        "--prepend-changelog",
        default="",
        help="Optional CHANGELOG.md file path to prepend the generated version section.",
    )
    parser.add_argument("--github-output", action="store_true", help="Set outputs in $GITHUB_OUTPUT.")
    parser.add_argument(
        "--sync-local",
        action="store_true",
        help="Sync calculated version and build number into pubspec.yaml and lib/config/app_config.dart for local builds.",
    )

    args = parser.parse_args()

    if args.validate_fragments:
        parsed, errors = validate_all_fragments(".")
        if errors:
            for err in errors:
                print(f"❌ {err}", file=sys.stderr)
            sys.exit(1)
        print(f"✅ Validated {len(parsed)} changelog fragment(s).")
        sys.exit(0)

    ref_type = os.environ.get("GITHUB_REF_TYPE", "")
    ref_name = os.environ.get("GITHUB_REF_NAME", "")
    is_tag_trigger = (ref_type == "tag" or ref_name.startswith("v")) and bool(re.match(r"^v?\d+\.\d+", ref_name))

    build_number = get_commit_count()
    all_tags = get_all_version_tags()
    latest_tag = all_tags[0] if all_tags else ""
    base_ver_str = get_base_version()
    base_major, base_minor, base_patch = parse_semver(base_ver_str)
    pub_ver_str = get_pubspec_version()
    pub_semver = parse_semver(pub_ver_str) if pub_ver_str else (0, 0, 0)

    if args.channel:
        channel = args.channel
    else:
        branch = get_current_branch()
        if branch in ("main", "master") or "stable" in branch:
            channel = "stable"
        elif "beta" in branch or "release" in branch:
            channel = "beta"
        else:
            channel = "alpha"

    current_tag_for_diff = (ref_name if ref_name.startswith("v") else f"v{ref_name}") if is_tag_trigger else None
    changelog_tag = get_previous_tag_for_changelog(all_tags, channel, current_tag=current_tag_for_diff)
    commits = get_commits_since_tag(changelog_tag)
    auto_bump, categorized = analyze_commits(commits)
    fragments = get_fragments_since_tag(changelog_tag)

    if any(f["type"] == "added" for f in fragments) and auto_bump == "patch":
        auto_bump = "minor"

    if is_tag_trigger:
        tag_name = ref_name if ref_name.startswith("v") else f"v{ref_name}"
        version = tag_name.lstrip("v")
        clean_version = re.sub(r"-[a-zA-Z0-9\.\-]+$", "", version)
        if args.channel:
            channel = args.channel
        elif "beta" in version:
            channel = "beta"
        elif "alpha" in version or "dev" in version:
            channel = "alpha"
        else:
            channel = "stable"
        is_prerelease = channel != "stable"
    else:
        bump = auto_bump if args.bump == "auto" else args.bump

        is_latest_tag_prerelease = bool(re.search(r"-[a-zA-Z0-9\.]+", latest_tag))
        tag_clean = re.sub(r"-[a-zA-Z0-9\.]+$", "", latest_tag).lstrip("v") if latest_tag else ""
        tag_semver = parse_semver(tag_clean) if tag_clean else (0, 0, 0)

        if bump == "custom" and args.custom_version:
            clean_version = args.custom_version.lstrip("v")
        elif channel != "stable":
            if pub_semver > tag_semver:
                clean_version = pub_ver_str
            else:
                if bump == "major":
                    clean_version = f"{base_major + 1}.0.0"
                elif bump == "minor":
                    clean_version = f"{base_major}.{base_minor + 1}.0"
                else:
                    clean_version = f"{base_major}.{base_minor}.{base_patch + 1}"

            if channel == "beta":
                version = f"{clean_version}-beta.{build_number}"
            else:
                version = f"{clean_version}-alpha.{build_number}"
            is_prerelease = True
        else:
            if is_latest_tag_prerelease:
                clean_version = tag_clean if tag_semver >= pub_semver else pub_ver_str
            else:
                if pub_semver > tag_semver:
                    clean_version = pub_ver_str
                else:
                    if bump == "major":
                        clean_version = f"{base_major + 1}.0.0"
                    elif bump == "minor":
                        clean_version = f"{base_major}.{base_minor + 1}.0"
                    else:
                        clean_version = f"{base_major}.{base_minor}.{base_patch + 1}"
            version = clean_version
            is_prerelease = False

        tag_name = f"v{version}"

    app_notes, github_notes, changelog_entry = build_release_documents(
        version=version,
        channel=channel,
        fragments=fragments,
        categorized_commits=categorized,
    )

    if args.sync_local:
        pub_path = "pubspec.yaml"
        if os.path.exists(pub_path):
            with open(pub_path, "r", encoding="utf-8") as pf:
                pub_text = pf.read()
            new_pub_text = re.sub(
                r"(?m)^version:\s*[^\r\n]+",
                f"version: {clean_version}+{build_number}",
                pub_text,
                count=1,
            )
            with open(pub_path, "w", encoding="utf-8") as pf:
                pf.write(new_pub_text)
            print(f"Updated {pub_path} -> version: {clean_version}+{build_number}")

        cfg_path = os.path.join("lib", "config", "app_config.dart")
        if os.path.exists(cfg_path):
            with open(cfg_path, "r", encoding="utf-8") as cf:
                cfg_text = cf.read()
            cfg_text = re.sub(
                r"String\.fromEnvironment\('APP_VERSION',\s*defaultValue:\s*'[^']*'\)",
                f"String.fromEnvironment('APP_VERSION', defaultValue: '{version}')",
                cfg_text,
            )
            cfg_text = re.sub(
                r"int\.fromEnvironment\('APP_BUILD_NUMBER',\s*defaultValue:\s*\d+\)",
                f"int.fromEnvironment('APP_BUILD_NUMBER', defaultValue: {build_number})",
                cfg_text,
            )
            with open(cfg_path, "w", encoding="utf-8") as cf:
                cf.write(cfg_text)
            print(f"Updated {cfg_path} -> APP_VERSION='{version}', APP_BUILD_NUMBER={build_number}")
    else:
        with open(args.output_file, "w", encoding="utf-8") as f:
            f.write(app_notes + "\n")
        if args.github_notes_file:
            with open(args.github_notes_file, "w", encoding="utf-8") as gf:
                gf.write(github_notes + "\n")
        if args.prepend_changelog:
            prepend_changelog_file(args.prepend_changelog, version, changelog_entry)

    print(f"Channel:        {channel}")
    print(f"Base Version:   {base_ver_str}")
    print(f"Calculated:     {version}")
    print(f"Build Number:   {build_number}")
    print(f"Tag Name:       {tag_name}")
    print(f"Is Pre-release: {is_prerelease}")
    print(f"Fragments used: {len(fragments)}")
    print(f"Changelog saved to: {args.output_file}")
    if args.github_notes_file and not args.sync_local:
        print(f"GitHub notes saved to: {args.github_notes_file}")

    gh_output_path = os.environ.get("GITHUB_OUTPUT")
    if args.github_output and gh_output_path:
        with open(gh_output_path, "a", encoding="utf-8") as gh:
            gh.write(f"version={version}\n")
            gh.write(f"clean_version={clean_version}\n")
            gh.write(f"build_number={build_number}\n")
            gh.write(f"channel={channel}\n")
            gh.write(f"tag_name={tag_name}\n")
            gh.write(f"is_prerelease={'true' if is_prerelease else 'false'}\n")
            gh.write(f"release_notes_file={args.output_file}\n")
            if args.github_notes_file:
                gh.write(f"github_notes_file={args.github_notes_file}\n")


if __name__ == "__main__":
    main()
