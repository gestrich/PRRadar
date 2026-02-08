"""Agent diff command - fetch and store PR data artifacts.

Fetches diff, PR metadata, comments, and repository info from GitHub and stores
them as artifacts for subsequent pipeline phases. Also runs the effective diff
pipeline to detect moved code and produce reduced diffs.

Artifact outputs (all in phase-1-pull-request/):
    diff-raw.diff                - Original diff text
    diff-parsed.json             - Structured diff with hunks (machine-readable)
    diff-parsed.md               - Structured diff with hunks (human-readable)
    effective-diff-parsed.json   - Effective diff with moves removed (machine-readable)
    effective-diff-parsed.md     - Effective diff with moves removed (human-readable)
    effective-diff-moves.json    - Move detection report
    gh-pr.json                   - Raw GitHub PR metadata JSON
    gh-comments.json             - Raw GitHub comments JSON
    gh-repo.json                 - Raw GitHub repository JSON
"""

from __future__ import annotations

import json
from pathlib import Path

from prradar.domain.diff_source import DiffSource
from prradar.infrastructure.diff_provider.factory import create_diff_provider
from prradar.infrastructure.effective_diff import run_effective_diff_pipeline
from prradar.infrastructure.github.runner import GhCommandRunner
from prradar.services.git_operations import GitFileNotFoundError
from prradar.services.phase_sequencer import (
    DIFF_PARSED_JSON_FILENAME,
    DIFF_PARSED_MD_FILENAME,
    DIFF_RAW_FILENAME,
    EFFECTIVE_DIFF_MOVES_FILENAME,
    EFFECTIVE_DIFF_PARSED_JSON_FILENAME,
    EFFECTIVE_DIFF_PARSED_MD_FILENAME,
    GH_COMMENTS_FILENAME,
    GH_PR_FILENAME,
    GH_REPO_FILENAME,
    PhaseSequencer,
    PipelinePhase,
)


def cmd_diff(
    pr_number: int,
    output_dir: Path,
    source: DiffSource = DiffSource.LOCAL,
    repo_path: str = ".",
) -> int:
    """Execute the diff command.

    Args:
        pr_number: PR number to fetch
        output_dir: PR-specific output directory (already includes PR number)
        source: Diff source (DiffSource.LOCAL or DiffSource.GITHUB)
        repo_path: Path to local git repo (default: current directory)

    Returns:
        Exit code (0 for success, non-zero for error)
    """
    from prradar.domain.diff import GitDiff

    gh = GhCommandRunner()
    print(f"Fetching PR #{pr_number} data...")

    # Get repository information from GitHub
    print("  Detecting repository...")
    success, repo_result = gh.get_repository()
    if not success:
        print(f"  Error detecting repository: {repo_result}")
        return 1
    assert not isinstance(repo_result, str)
    repo = repo_result

    # Create diff subdirectory
    diff_dir = PhaseSequencer.ensure_phase_dir(output_dir, PipelinePhase.DIFF)

    # Create appropriate diff provider
    print(f"  Using diff source: {source.value}")
    provider = create_diff_provider(
        source,
        repo.owner,
        repo.name,
        local_repo_path=repo_path,
    )

    # Fetch and store diff
    print("  Fetching diff...")
    try:
        diff_content = provider.get_pr_diff(pr_number)
    except Exception as e:
        print(f"  Error fetching diff: {e}")
        return 1

    raw_diff_path = diff_dir / DIFF_RAW_FILENAME
    raw_diff_path.write_text(diff_content)
    print(f"  Wrote {raw_diff_path}")

    # Fetch PR metadata (needed for commit hash and effective diff)
    print("  Fetching PR metadata...")
    success, pr_result = gh.get_pull_request(pr_number)
    if not success:
        print(f"  Error fetching PR metadata: {pr_result}")
        return 1
    assert not isinstance(pr_result, str)
    pr = pr_result

    pr_path = diff_dir / GH_PR_FILENAME
    pr_path.write_text(pr.raw_json)
    print(f"  Wrote {pr_path}")

    # Parse diff into structured format
    git_diff = GitDiff.from_diff_content(diff_content, commit_hash=pr.head_ref_oid)
    parsed_diff = git_diff.to_dict(annotate_lines=True)
    parsed_diff_path = diff_dir / DIFF_PARSED_JSON_FILENAME
    parsed_diff_path.write_text(json.dumps(parsed_diff, indent=2))
    print(f"  Wrote {parsed_diff_path} ({len(git_diff.hunks)} hunks)")

    parsed_md_path = diff_dir / DIFF_PARSED_MD_FILENAME
    parsed_md_path.write_text(git_diff.to_markdown())
    print(f"  Wrote {parsed_md_path}")

    # Run effective diff pipeline
    print("  Running effective diff analysis...")
    base_ref = f"origin/{pr.base_ref_name}" if source == DiffSource.LOCAL else pr.base_ref_name
    head_ref = pr.head_ref_oid

    old_files: dict[str, str] = {}
    new_files: dict[str, str] = {}
    for file_path in git_diff.get_unique_files():
        try:
            old_files[file_path] = provider.get_file_content(file_path, base_ref)
        except GitFileNotFoundError:
            pass
        try:
            new_files[file_path] = provider.get_file_content(file_path, head_ref)
        except GitFileNotFoundError:
            pass

    effective_diff, move_report = run_effective_diff_pipeline(git_diff, old_files, new_files)

    eff_json_path = diff_dir / EFFECTIVE_DIFF_PARSED_JSON_FILENAME
    eff_json_path.write_text(json.dumps(effective_diff.to_dict(annotate_lines=True), indent=2))
    print(f"  Wrote {eff_json_path}")

    eff_md_path = diff_dir / EFFECTIVE_DIFF_PARSED_MD_FILENAME
    eff_md_path.write_text(effective_diff.to_markdown())
    print(f"  Wrote {eff_md_path}")

    moves_path = diff_dir / EFFECTIVE_DIFF_MOVES_FILENAME
    moves_path.write_text(json.dumps(move_report.to_dict(), indent=2))
    print(f"  Wrote {moves_path}")

    # Fetch comments
    print("  Fetching comments...")
    success, comments_result = gh.get_pull_request_comments(pr_number)
    if not success:
        print(f"  Error fetching comments: {comments_result}")
        return 1
    assert not isinstance(comments_result, str)
    comments = comments_result

    comments_path = diff_dir / GH_COMMENTS_FILENAME
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

    repo_path = diff_dir / GH_REPO_FILENAME
    repo_path.write_text(repo.raw_json)
    print(f"  Wrote {repo_path}")

    # Summary - now using typed model properties
    print()
    print(f"PR #{pr_number}: {pr.title}")
    print(f"  Files changed: {pr.changed_files}")
    print(f"  Additions: +{pr.additions}")
    print(f"  Deletions: -{pr.deletions}")
    print(f"  Moves detected: {move_report.moves_detected}")
    print(f"  Lines moved: {move_report.total_lines_moved}")
    print(f"  Lines effectively changed: {move_report.total_lines_effectively_changed}")
    print(f"  Comments: {len(comments.comments)}")
    print(f"  Reviews: {len(comments.reviews)}")
    print()
    print(f"Artifacts saved to: {output_dir}")

    return 0
