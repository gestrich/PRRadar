"""Agent comment command - post review comments to GitHub.

Reads evaluation results from the evaluate command and posts inline
comments to the GitHub PR for violations meeting the score threshold.

Requires:
    <output-dir>/<pr-number>/evaluations/*.json  - Evaluation result files
    <output-dir>/<pr-number>/tasks/*.json        - Task files (for documentation_link)

Features:
    - Individual inline comments per violation
    - Dry-run mode to preview without posting
    - Interactive mode to approve each comment before posting
    - Score threshold filtering (default: score >= 5)
    - Programmatic documentation link appending
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from scripts.domain.agent_outputs import RuleEvaluation
from scripts.infrastructure.gh_runner import GhCommandRunner
from scripts.services.github_comment import GitHubCommentService
from scripts.utils.interactive import print_separator, prompt_yes_no_quit


# ============================================================
# Domain Models
# ============================================================


@dataclass
class CommentableViolation:
    """A violation ready to be posted as a GitHub comment.

    Combines evaluation result with rule metadata for comment composition.
    """

    task_id: str
    rule_name: str
    file_path: str
    line_number: int | None
    score: int
    comment: str
    documentation_link: str | None
    relevant_claude_skill: str | None = None
    cost_usd: float | None = None
    diff_context: str | None = None
    rule_url: str | None = None

    # --------------------------------------------------------
    # Public API
    # --------------------------------------------------------

    def compose_comment(self) -> str:
        """Compose the final GitHub comment body.

        Combines the comment with optional documentation link and
        Claude skill appended programmatically.

        Returns:
            Formatted markdown comment body
        """
        rule_header = (
            f"**[{self.rule_name}]({self.rule_url})**"
            if self.rule_url
            else f"**{self.rule_name}**"
        )
        lines = [
            rule_header,
            "",
            self.comment,
        ]

        if self.relevant_claude_skill:
            lines.extend(["", f"Related Claude Skill: `/{self.relevant_claude_skill}`"])

        if self.documentation_link:
            lines.extend(["", f"Related Documentation: [Docs]({self.documentation_link})"])

        cost_str = f" (cost ${self.cost_usd:.4f})" if self.cost_usd else ""
        lines.extend(["", f"*Assisted by [PR Radar](https://github.com/gestrich/PRRadar){cost_str}*"])

        return "\n".join(lines)


# ============================================================
# Loading Logic
# ============================================================


def load_violations(
    evaluations_dir: Path,
    tasks_dir: Path,
    min_score: int,
) -> list[CommentableViolation]:
    """Load violations from evaluation results.

    Args:
        evaluations_dir: Directory containing evaluation JSON files
        tasks_dir: Directory containing task JSON files (for documentation_link)
        min_score: Minimum score threshold for inclusion

    Returns:
        List of violations meeting the score threshold
    """
    violations: list[CommentableViolation] = []

    # Load task metadata for documentation links
    task_metadata: dict[str, dict] = {}
    for task_file in tasks_dir.glob("*.json"):
        try:
            data = json.loads(task_file.read_text())
            task_id = data.get("task_id", "")
            if task_id:
                task_metadata[task_id] = data
        except (json.JSONDecodeError, KeyError):
            continue

    # Load evaluation results
    for eval_file in evaluations_dir.glob("*.json"):
        if eval_file.name == "summary.json":
            continue

        try:
            data = json.loads(eval_file.read_text())
            evaluation_data = data.get("evaluation", {})
            evaluation = RuleEvaluation.from_dict(evaluation_data)

            if not evaluation.violates_rule:
                continue

            if evaluation.score < min_score:
                continue

            task_id = data.get("task_id", "")
            rule_name = data.get("rule_name", "")
            file_path = data.get("file_path", "") or evaluation.file_path

            # Get rule metadata from task metadata
            documentation_link = None
            relevant_claude_skill = None
            rule_url = None
            if task_id in task_metadata:
                rule_data = task_metadata[task_id].get("rule", {})
                documentation_link = rule_data.get("documentation_link")
                relevant_claude_skill = rule_data.get("relevant_claude_skill")
                rule_url = rule_data.get("rule_url")

            violations.append(
                CommentableViolation(
                    task_id=task_id,
                    rule_name=rule_name,
                    file_path=file_path,
                    line_number=evaluation.line_number,
                    score=evaluation.score,
                    comment=evaluation.comment,
                    documentation_link=documentation_link,
                    relevant_claude_skill=relevant_claude_skill,
                    cost_usd=data.get("cost_usd"),
                    rule_url=rule_url,
                )
            )

        except (json.JSONDecodeError, KeyError) as e:
            print(f"  Warning: Failed to parse {eval_file.name}: {e}")
            continue

    return violations


# ============================================================
# Posting Logic
# ============================================================


def prompt_for_comment(
    violation: CommentableViolation,
    index: int,
    total: int,
) -> str | None:
    """Prompt user to approve, skip, or quit for a comment.

    Args:
        violation: The violation to prompt for
        index: Current index (1-based)
        total: Total number of violations

    Returns:
        'y' to post, 'n' to skip, 'q' to quit, None on EOF
    """
    print()
    print_separator("=")
    print(f"Comment {index}/{total}: {violation.file_path}:{violation.line_number or '?'}")
    print_separator("=")

    # Show diff context if available
    if violation.diff_context:
        print("Diff context:")
        for line in violation.diff_context.split("\n"):
            print(f"  {line}")
        print_separator("-")

    print("Comment to post:")
    print(violation.compose_comment())
    print_separator("-")

    return prompt_yes_no_quit("Post this comment?")


def post_violations(
    violations: list[CommentableViolation],
    pr_number: int,
    repo: str,
    dry_run: bool,
    interactive: bool = False,
) -> tuple[int, int, int]:
    """Post violations as inline comments to GitHub.

    Args:
        violations: List of violations to post
        pr_number: PR number to post comments to
        repo: Repository in owner/repo format
        dry_run: If True, preview without posting
        interactive: If True, prompt for each comment

    Returns:
        Tuple of (successful_count, failed_count, skipped_count)
    """
    if dry_run:
        print("\n[DRY RUN] Would post the following comments:\n")
        for i, v in enumerate(violations, 1):
            print(f"{'─' * 60}")
            print(f"Comment {i}: {v.file_path}:{v.line_number or '?'}")
            print(f"{'─' * 60}")
            print(v.compose_comment())
            print()
        return len(violations), 0, 0

    gh = GhCommandRunner(dry_run=False)
    comment_service = GitHubCommentService(repo=repo, gh=gh)

    # Get the HEAD commit SHA for inline comments
    commit_sha = comment_service.get_pr_head_sha(pr_number)
    if not commit_sha:
        print("  Error: Could not get PR HEAD commit SHA")
        return 0, len(violations), 0

    successful = 0
    failed = 0
    skipped = 0
    total = len(violations)

    for i, v in enumerate(violations, 1):
        # Interactive mode: prompt before posting
        if interactive:
            response = prompt_for_comment(v, i, total)
            if response is None or response == "q":
                remaining = total - i + 1
                skipped += remaining
                print(f"\n  Quit. Skipped {remaining} remaining comment(s).")
                break
            elif response == "n":
                print("  Skipped.")
                skipped += 1
                continue

        comment_body = v.compose_comment()

        if v.line_number:
            # Post as inline review comment
            endpoint = f"repos/{repo}/pulls/{pr_number}/comments"
            success, _ = gh.api_post_with_int(
                endpoint,
                string_fields={
                    "body": comment_body,
                    "path": v.file_path,
                    "side": "RIGHT",
                    "commit_id": commit_sha,
                },
                int_fields={"line": v.line_number},
            )

            if success:
                print(f"  ✓ Posted comment to {v.file_path}:{v.line_number}")
                successful += 1
            else:
                print(f"  ✗ Failed to post comment to {v.file_path}:{v.line_number}")
                failed += 1
        else:
            # No line number - post as general PR comment
            if comment_service.post_comment(pr_number, comment_body):
                print(f"  ✓ Posted general comment for {v.rule_name}")
                successful += 1
            else:
                print(f"  ✗ Failed to post general comment for {v.rule_name}")
                failed += 1

    return successful, failed, skipped


# ============================================================
# Command Entry Point
# ============================================================


def cmd_comment(
    pr_number: int,
    output_dir: Path,
    repo: str,
    min_score: int = 5,
    dry_run: bool = False,
    interactive: bool = False,
) -> int:
    """Execute the comment command.

    Args:
        pr_number: PR number to post comments to
        output_dir: PR-specific output directory (already includes PR number)
        repo: Repository in owner/repo format
        min_score: Minimum score threshold for posting (default: 5)
        dry_run: If True, preview without posting
        interactive: If True, prompt for each comment before posting

    Returns:
        Exit code (0 for success, non-zero for error)
    """
    if dry_run:
        mode = "dry-run"
    elif interactive:
        mode = "interactive"
    else:
        mode = "live"
    print(f"[comment] Posting comments for PR #{pr_number} ({mode})...")
    print(f"  Minimum score: {min_score}")

    # Verify directories exist
    evaluations_dir = output_dir / "evaluations"
    tasks_dir = output_dir / "tasks"

    if not evaluations_dir.exists():
        print(f"  Error: Evaluations directory not found at {evaluations_dir}")
        print("  Run 'agent evaluate' first to create evaluation results")
        return 1

    if not tasks_dir.exists():
        print(f"  Warning: Tasks directory not found at {tasks_dir}")
        print("  Documentation links will not be available")

    # Load violations
    violations = load_violations(evaluations_dir, tasks_dir, min_score)

    if not violations:
        print("  No violations meeting the score threshold")
        return 0

    print(f"  Found {len(violations)} violation(s) to post")

    # Post violations
    successful, failed, skipped = post_violations(
        violations, pr_number, repo, dry_run, interactive
    )

    # Print summary
    print()
    print("Comment Summary:")
    print(f"  Posted: {successful}")
    if skipped > 0:
        print(f"  Skipped: {skipped}")
    if failed > 0:
        print(f"  Failed: {failed}")

    return 0 if failed == 0 else 1
