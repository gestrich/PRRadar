"""Post review comments command.

Thin command that orchestrates domain models and services.
No business logic - just wiring and coordination.
"""

from __future__ import annotations

import sys
from pathlib import Path

from prradar.domain.review import ReviewOutput
from prradar.infrastructure import (
    GhCommandRunner,
    extract_structured_output,
    load_execution_file,
    write_github_step_summary,
)
from prradar.services import GitHubCommentService


def cmd_post_review(
    execution_file: str,
    pr_number: int,
    repo: str,
    min_score: int = 5,
    post_summary: bool = False,
    write_job_summary: bool = False,
    dry_run: bool = False,
) -> int:
    """Post review comments to a GitHub PR.

    Thin command that:
    1. Loads and parses the execution file into domain models
    2. Initializes services with dependencies
    3. Orchestrates the posting workflow
    4. Returns exit code

    Args:
        execution_file: Path to Claude's execution output JSON file
        pr_number: PR number to post comments to
        repo: Repository in owner/repo format
        min_score: Minimum score to post a comment (default: 5)
        post_summary: Also post a summary comment to the PR
        write_job_summary: Write review summary to GITHUB_STEP_SUMMARY
        dry_run: Print what would be posted without actually posting

    Returns:
        Exit code (0 for success, 1 for failure)
    """
    # --------------------------------------------------------
    # 1. Load and parse into domain model
    # --------------------------------------------------------
    try:
        execution_data = load_execution_file(execution_file)
    except FileNotFoundError:
        print(f"Execution file not found: {execution_file}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Failed to parse execution file: {e}", file=sys.stderr)
        return 1

    structured_output = extract_structured_output(execution_data)
    if not structured_output:
        print("No structured output found in execution file", file=sys.stderr)
        return 1

    # Parse-once: raw JSON → typed domain model
    review = ReviewOutput.from_dict(structured_output)

    # --------------------------------------------------------
    # 2. Handle unsuccessful review
    # --------------------------------------------------------
    if not review.success:
        print("Review was not successful, skipping comment posting")
        if write_job_summary:
            _write_job_summary(review)
        return 1

    # --------------------------------------------------------
    # 3. Initialize services with dependencies
    # --------------------------------------------------------
    gh_runner = GhCommandRunner(dry_run=dry_run)
    comment_service = GitHubCommentService(repo=repo, gh=gh_runner)

    # --------------------------------------------------------
    # 4. Get violations using domain model API
    # --------------------------------------------------------
    violations = review.get_violations_by_min_score(min_score)

    if not violations:
        print(f"No violations found with score >= {min_score}")
        if post_summary:
            comment_service.post_review_summary(pr_number, review)
        if write_job_summary:
            _write_job_summary(review)
        return 0

    print(f"Found {len(violations)} violation(s) to post")

    # --------------------------------------------------------
    # 5. Post review comments via service
    # --------------------------------------------------------
    commit_sha = comment_service.get_pr_head_sha(pr_number)
    if not commit_sha and not dry_run:
        print("Warning: Could not get PR HEAD SHA, comments may fail", file=sys.stderr)

    success_count = 0
    for feedback in violations:
        if comment_service.post_review_comment(pr_number, feedback, commit_sha or ""):
            success_count += 1

    # --------------------------------------------------------
    # 6. Post summary and write job summary
    # --------------------------------------------------------
    if post_summary:
        comment_service.post_review_summary(pr_number, review)

    if write_job_summary:
        _write_job_summary(review)

    print(f"Posted {success_count}/{len(violations)} comments")

    return 0 if success_count == len(violations) else 1


# ============================================================
# Private Helpers
# ============================================================


def _write_job_summary(review: ReviewOutput) -> None:
    """Write review summary to GitHub Actions job summary."""
    content = _generate_job_summary_content(review)
    write_github_step_summary(content)


def _generate_job_summary_content(review: ReviewOutput) -> str:
    """Generate markdown content for the job summary."""
    lines = ["## Code Review Summary", ""]

    # Try to read the summary file if it exists
    if review.summary.summary_file:
        file_path = Path(review.summary.summary_file)
        if file_path.exists():
            try:
                lines.append(file_path.read_text())
                return "\n".join(lines)
            except OSError:
                pass

    # Fallback to generated summary
    violations = review.violations
    lines.extend(
        [
            f"**Total Segments Reviewed:** {review.summary.total_segments}",
            f"**Violations Found:** {len(violations)}",
            "",
        ]
    )

    if review.summary.categories:
        lines.extend(
            [
                "### Category Scores",
                "",
                "| Category | Score | Summary |",
                "|----------|-------|---------|",
            ]
        )
        for cat_name, cat_summary in review.summary.categories.items():
            lines.append(
                f"| {cat_name} | {cat_summary.aggregate_score} | {cat_summary.summary} |"
            )
        lines.append("")

    if violations:
        lines.extend(["### Violations", ""])
        for v in violations:
            lines.append(f"- **{v.file}:{v.line_number}** - {v.rule} (Score: {v.score})")

    return "\n".join(lines)
