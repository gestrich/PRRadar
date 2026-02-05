"""Agent diff command - fetch and store PR diff artifacts.

Fetches diff, PR metadata, and comments from GitHub and stores them as artifacts
for subsequent pipeline phases.

Artifact outputs:
    <output-dir>/<pr-number>/diff/raw.diff     - Original diff text
    <output-dir>/<pr-number>/diff/parsed.json  - Structured diff with hunks
    <output-dir>/<pr-number>/pr.json           - Raw GitHub PR metadata JSON
    <output-dir>/<pr-number>/comments.json     - Raw GitHub comments JSON
    <output-dir>/<pr-number>/repo.json         - Raw GitHub repository JSON
"""

from __future__ import annotations

import json
from pathlib import Path

from scripts.infrastructure.gh_runner import GhCommandRunner


def cmd_diff(pr_number: int, output_dir: Path) -> int:
    """Execute the diff command.

    Args:
        pr_number: PR number to fetch
        output_dir: PR-specific output directory (already includes PR number)

    Returns:
        Exit code (0 for success, non-zero for error)
    """
    from scripts.domain.diff import GitDiff

    gh = GhCommandRunner()
    print(f"Fetching PR #{pr_number} data...")

    # Create diff subdirectory
    diff_dir = output_dir / "diff"
    diff_dir.mkdir(parents=True, exist_ok=True)

    # Fetch and store diff
    print("  Fetching diff...")
    success, diff_content = gh.pr_diff(pr_number)
    if not success:
        print(f"  Error fetching diff: {diff_content}")
        return 1

    raw_diff_path = diff_dir / "raw.diff"
    raw_diff_path.write_text(diff_content)
    print(f"  Wrote {raw_diff_path}")

    # Parse diff into structured format
    git_diff = GitDiff.from_diff_content(diff_content)
    parsed_diff = git_diff.to_dict(annotate_lines=True)
    parsed_diff_path = diff_dir / "parsed.json"
    parsed_diff_path.write_text(json.dumps(parsed_diff, indent=2))
    print(f"  Wrote {parsed_diff_path} ({len(git_diff.hunks)} hunks)")

    # Fetch PR metadata
    print("  Fetching PR metadata...")
    success, pr_result = gh.get_pull_request(pr_number)
    if not success:
        print(f"  Error fetching PR metadata: {pr_result}")
        return 1
    assert not isinstance(pr_result, str)
    pr = pr_result

    pr_path = output_dir / "pr.json"
    pr_path.write_text(pr.raw_json)
    print(f"  Wrote {pr_path}")

    # Fetch comments
    print("  Fetching comments...")
    success, comments_result = gh.get_pull_request_comments(pr_number)
    if not success:
        print(f"  Error fetching comments: {comments_result}")
        return 1
    assert not isinstance(comments_result, str)
    comments = comments_result

    comments_path = output_dir / "comments.json"
    comments_path.write_text(comments.raw_json)
    print(f"  Wrote {comments_path}")

    # Fetch repo metadata
    print("  Fetching repo metadata...")
    success, repo_result = gh.get_repository()
    if not success:
        print(f"  Error fetching repo metadata: {repo_result}")
        return 1
    assert not isinstance(repo_result, str)
    repo = repo_result

    repo_path = output_dir / "repo.json"
    repo_path.write_text(repo.raw_json)
    print(f"  Wrote {repo_path}")

    # Summary - now using typed model properties
    print()
    print(f"PR #{pr_number}: {pr.title}")
    print(f"  Files changed: {pr.changed_files}")
    print(f"  Additions: +{pr.additions}")
    print(f"  Deletions: -{pr.deletions}")
    print(f"  Comments: {len(comments.comments)}")
    print(f"  Reviews: {len(comments.reviews)}")
    print()
    print(f"Artifacts saved to: {output_dir}")

    return 0
