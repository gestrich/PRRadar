"""Agent analyze-all command - batch analysis of PRs since a given date.

Fetches all PRs created since a specified date and runs the full analysis
pipeline on each one. Reuses cmd_analyze() for per-PR processing.

Features:
    - Date-based filtering via gh pr list --search "created:>=YYYY-MM-DD"
    - Commenting OFF by default (--comment flag enables it)
    - Per-PR success/failure tracking with aggregate summary
    - Safety cap on number of PRs (--limit, default 50)
"""

from __future__ import annotations

from prradar.commands.agent import ensure_output_dir
from prradar.commands.agent.analyze import cmd_analyze
from prradar.domain.diff_source import DiffSource
from prradar.infrastructure.github.runner import GhCommandRunner


def cmd_analyze_all(
    output_dir: str,
    since: str,
    rules_dir: str,
    repo: str,
    comment: bool = False,
    limit: int = 50,
    state: str = "all",
    min_score: int = 5,
    source: DiffSource = DiffSource.LOCAL,
    repo_path: str = ".",
) -> int:
    """Execute batch analysis of all PRs created since a given date.

    Args:
        output_dir: Base output directory (PRs saved under {output_dir}/{pr_number}/)
        since: Date string in YYYY-MM-DD format
        rules_dir: Path to rules directory
        repo: Repository in owner/repo format
        comment: If True, post comments to GitHub; if False, dry-run mode
        limit: Maximum number of PRs to process
        state: PR state filter (open, closed, merged, all)
        min_score: Minimum score threshold for violations
        source: Diff source (LOCAL or GITHUB)
        repo_path: Path to local git repo

    Returns:
        Exit code (0 if all succeeded, 1 if any failed)
    """
    search_query = f"created:>={since}"

    print(f"[analyze-all] Fetching PRs created since {since}...")
    print(f"  Repository: {repo}")
    print(f"  Search: {search_query}")
    print(f"  State: {state}, Limit: {limit}")
    print(f"  Commenting: {'enabled' if comment else 'disabled (dry-run)'}")
    print()

    gh = GhCommandRunner()
    success, result = gh.list_pull_requests(
        limit=limit, state=state, search=search_query, repo=repo
    )
    if not success:
        print(f"  Error fetching PR list: {result}")
        return 1

    assert not isinstance(result, str)
    prs = result

    if not prs:
        print(f"  No PRs found created since {since}")
        return 0

    print(f"Found {len(prs)} PR(s) created since {since}:")
    for pr in prs:
        print(f"  #{pr.number}: {pr.title}")
    print()

    succeeded = 0
    failed = 0
    failures: list[tuple[int, str]] = []

    for i, pr in enumerate(prs, 1):
        print("=" * 60)
        print(f"[{i}/{len(prs)}] Analyzing PR #{pr.number}: {pr.title}")
        print("=" * 60)

        pr_dir = ensure_output_dir(output_dir, pr.number)

        try:
            exit_code = cmd_analyze(
                pr_number=pr.number,
                output_dir=pr_dir,
                rules_dir=rules_dir,
                repo=repo,
                interactive=False,
                dry_run=not comment,
                stop_after=None,
                skip_to=None,
                min_score=min_score,
                source=source,
                repo_path=repo_path,
            )
            if exit_code == 0:
                succeeded += 1
            else:
                failed += 1
                failures.append((pr.number, f"exit code {exit_code}"))
        except Exception as e:
            failed += 1
            failures.append((pr.number, str(e)))
            print(f"  Error analyzing PR #{pr.number}: {e}")

        print()

    # Aggregate summary
    print("=" * 60)
    print("Batch Analysis Summary")
    print("=" * 60)
    print(f"  Total PRs: {len(prs)}")
    print(f"  Succeeded: {succeeded}")
    print(f"  Failed: {failed}")
    if failures:
        print("  Failures:")
        for pr_number, reason in failures:
            print(f"    PR #{pr_number}: {reason}")

    return 1 if failed > 0 else 0
