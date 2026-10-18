#!/usr/bin/env python3
"""
Calculate semantic release version and changelog from Conventional Commits.
Can be run locally or inside GitHub Actions.
"""

import argparse
import os
import re
import subprocess
import sys


def run_git(args, cwd=None):
    result = subprocess.run(
        ["git"] + args,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace"
    )
    return result.stdout.strip(), result.returncode


def get_current_branch():
    branch, code = run_git(["rev-parse", "--abbrev-ref", "HEAD"])
    if code == 0 and branch and branch != "HEAD":
        return branch
    # If in detached HEAD in GitHub Actions, check GITHUB_REF_NAME or GITHUB_HEAD_REF
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
    # Return list of version tags sorted by semantic version descending
    # First try tags reachable from HEAD
    out, code = run_git(["tag", "--merged", "HEAD", "-l", "v[0-9]*"])
    if code == 0 and out.strip():
        tags = [t.strip() for t in out.strip().splitlines() if t.strip()]
        if tags:
            tags.sort(key=parse_tag_sort_key, reverse=True)
            return tags
    # Fallback to all version tags in repo
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
        if code == 0:
            range_spec = f"{tag}..HEAD"
        else:
            range_spec = "HEAD~50..HEAD"
    else:
        # If no tag, take up to the last 50 commits
        range_spec = "HEAD~50..HEAD"
    
    # Check if range is valid
    _, code = run_git(["rev-parse", range_spec.split("..")[0]])
    if code != 0:
        range_spec = "HEAD"

    output, code = run_git(["log", range_spec, "--pretty=format:%H|%s|%b<END_OF_COMMIT>"])
    if code != 0 or not output:
        # Fallback to all commits
        output, _ = run_git(["log", "-n", "30", "--pretty=format:%H|%s|%b<END_OF_COMMIT>"])
    
    commits = []
    if not output:
        return commits

    raw_items = output.split("<END_OF_COMMIT>")
    for item in raw_items:
        item = item.strip()
        if not item:
            continue
        parts = item.split("|", 2)
        sha = parts[0].strip()
        subject = parts[1].strip() if len(parts) > 1 else ""
        body = parts[2].strip() if len(parts) > 2 else ""
        commits.append({
            "sha": sha[:8],
            "subject": subject,
            "body": body,
            "message": f"{subject}\n{body}".strip()
        })
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
        "other": []
    }

    # Conventional commit regex
    cc_re = re.compile(r"^([a-zA-Z]+)(?:\(([^\)]+)\))?(!)?:\s*(.*)$")

    for c in commits:
        sub = c["subject"]
        msg = c["message"]

        # Skip automatic merge commits from cluttering changelog
        if sub.startswith("Merge pull request ") or sub.startswith("Merge branch ") or sub.startswith("Merge remote-tracking branch "):
            continue
        
        # Check for breaking changes in subject or body
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


def generate_changelog(version, channel, categorized):
    lines = [f"# Theaver v{version} ({channel.capitalize()})\n"]

    section_titles = [
        ("feat", "🚀 Новые функции (Features)"),
        ("fix", "🐛 Исправления ошибок (Bug Fixes)"),
        ("perf", "⚡ Производительность (Performance)"),
        ("refactor", "🔄 Рефакторинг (Refactoring)"),
        ("chore", "🛠️ Обслуживание и сборка (Maintenance)"),
        ("other", "📝 Прочие изменения (Other Changes)"),
    ]

    has_content = False
    for key, title in section_titles:
        items = categorized.get(key, [])
        if items:
            has_content = True
            lines.append(f"### {title}")
            for sha, desc in items:
                lines.append(f"- {desc} (`{sha}`)")
            lines.append("")

    if not has_content:
        lines.append("- Регулярное обновление приложения и исправление мелких недочетов.")

    return "\n".join(lines).strip()


def main():
    parser = argparse.ArgumentParser(description="Calculate semantic version and changelog.")
    parser.add_argument("--channel", choices=["stable", "beta", "alpha"], default=None,
                        help="Target release channel (stable, beta, alpha). Defaults based on branch.")
    parser.add_argument("--bump", choices=["auto", "patch", "minor", "major", "custom"], default="auto",
                        help="Type of version bump.")
    parser.add_argument("--custom-version", default="", help="Custom version if bump=custom.")
    parser.add_argument("--output-file", default="release_notes.md", help="File to write release notes to.")
    parser.add_argument("--github-output", action="store_true", help="Set outputs in $GITHUB_OUTPUT.")

    args = parser.parse_args()

    # Check if triggered directly by a Git tag
    ref_type = os.environ.get("GITHUB_REF_TYPE", "")
    ref_name = os.environ.get("GITHUB_REF_NAME", "")
    is_tag_trigger = (ref_type == "tag" or ref_name.startswith("v")) and bool(re.match(r"^v?\d+\.\d+", ref_name))

    # Get build number (monotonically increasing commit count)
    build_number = get_commit_count()
    latest_tag = get_latest_tag()
    latest_stable_tag = get_latest_stable_tag()
    base_ver_str = get_base_version()
    base_major, base_minor, base_patch = parse_semver(base_ver_str)
    pub_ver_str = get_pubspec_version()
    pub_semver = parse_semver(pub_ver_str) if pub_ver_str else (0, 0, 0)

    # Determine channel based on branch
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

    changelog_tag = latest_stable_tag if (channel == "stable" and latest_stable_tag) else latest_tag
    commits = get_commits_since_tag(changelog_tag if not is_tag_trigger else "")
    auto_bump, categorized = analyze_commits(commits)

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
        is_prerelease = (channel != "stable")
    else:
        bump = auto_bump if args.bump == "auto" else args.bump

        is_latest_tag_prerelease = bool(re.search(r"-[a-zA-Z0-9\.]+", latest_tag))
        tag_clean = re.sub(r"-[a-zA-Z0-9\.]+$", "", latest_tag).lstrip("v") if latest_tag else ""
        tag_semver = parse_semver(tag_clean) if tag_clean else (0, 0, 0)

        if bump == "custom" and args.custom_version:
            clean_version = args.custom_version.lstrip("v")
        elif channel != "stable":
            # In a pre-release channel (beta / alpha):
            # Advance semver on every release according to Conventional Commits (major / minor / patch),
            # or adopt pubspec.yaml version if it was manually bumped higher than the latest tag.
            if pub_semver > tag_semver:
                clean_version = pub_ver_str
            else:
                if bump == "major":
                    clean_version = f"{base_major + 1}.0.0"
                elif bump == "minor":
                    clean_version = f"{base_major}.{base_minor + 1}.0"
                else:  # patch
                    clean_version = f"{base_major}.{base_minor}.{base_patch + 1}"

            if channel == "beta":
                version = f"{clean_version}-beta.{build_number}"
            else:
                version = f"{clean_version}-alpha.{build_number}"
            is_prerelease = True
        else:  # channel == "stable"
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

    changelog = generate_changelog(version, channel, categorized)

    # Write release notes to file
    with open(args.output_file, "w", encoding="utf-8") as f:
        f.write(changelog)

    # Print summary
    print(f"Channel:        {channel}")
    print(f"Base Version:   {base_ver_str}")
    print(f"Calculated:     {version}")
    print(f"Build Number:   {build_number}")
    print(f"Tag Name:       {tag_name}")
    print(f"Is Pre-release: {is_prerelease}")
    print(f"Changelog saved to: {args.output_file}")

    # GitHub Actions output
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


if __name__ == "__main__":
    main()
