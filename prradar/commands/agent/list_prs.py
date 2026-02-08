"""Agent list-prs command - fetch recent PR metadata from GitHub.

Fetches recent pull requests via `gh pr list` and saves each PR's metadata
as gh-pr.json in the standard output directory structure. Also fetches
repository metadata once (shared across all PRs).

Artifact outputs (per PR, in {output_dir}/{pr_number}/phase-1-pull-request/):
    gh-pr.json   - Raw GitHub PR metadata JSON
    gh-repo.json - Raw GitHub repository JSON (same content for all PRs)
"""

from __future__ import annotations

from pathlib import Path

from prradar.infrastructure.github.runner import GhCommandRunner
from prradar.services.phase_sequencer import (
    GH_PR_FILENAME,
    GH_REPO_FILENAME,
    PhaseSequencer,
    PipelinePhase,
)


def cmd_list_prs(output_dir: str, limit: int = 50, state: str = "open", repo: str | None = None) -> int:
    """Fetch recent PRs from GitHub and save their metadata.

    Args:
        output_dir: Base output directory (PRs saved under {output_dir}/{pr_number}/)
        limit: Maximum number of PRs to fetch
        state: PR state filter (open, closed, merged, all)
        repo: Repository in owner/name format (auto-detected if None)

    Returns:
        Exit code (0 for success, non-zero for error)
    """
    gh = GhCommandRunner()
    base_dir = Path(output_dir)

    print(f"Fetching up to {limit} {state} pull requests...")
    success, pr_result = gh.list_pull_requests(limit=limit, state=state, repo=repo)
    if not success:
        print(f"  Error fetching PR list: {pr_result}")
        return 1
    assert not isinstance(pr_result, str)
    prs = pr_result

    if not prs:
        print("  No pull requests found.")
        return 0

    # Fetch repo metadata once
    print("  Fetching repository metadata...")
    success, repo_result = gh.get_repository(repo=repo)
    if not success:
        print(f"  Error fetching repository metadata: {repo_result}")
        return 1
    assert not isinstance(repo_result, str)
    repo = repo_result

    print(f"  Found {len(prs)} pull requests. Saving metadata...")

    for pr in prs:
        pr_dir = base_dir / str(pr.number)
        diff_dir = PhaseSequencer.ensure_phase_dir(pr_dir, PipelinePhase.DIFF)

        pr_path = diff_dir / GH_PR_FILENAME
        pr_path.write_text(pr.raw_json)

        repo_path = diff_dir / GH_REPO_FILENAME
        repo_path.write_text(repo.raw_json)

        print(f"    PR #{pr.number}: {pr.title}")

    print(f"\nSaved metadata for {len(prs)} PRs to: {base_dir}")
    return 0
