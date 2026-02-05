"""Agent analyze command - run the full review pipeline.

Chains diff → rules → evaluate → comment phases with optional interactive mode
for reviewing each task before evaluation.

Features:
    - Interactive mode (default): prompt before each evaluation
    - Dry-run mode (default): preview comments without posting
    - Support for --stop-after and --skip-to for partial execution
"""

from __future__ import annotations

import asyncio
import json
from dataclasses import dataclass
from pathlib import Path

from scripts.commands.agent.comment import (
    post_violations,
    prompt_for_comment,
)
from scripts.commands.agent.diff import cmd_diff
from scripts.infrastructure.gh_runner import GhCommandRunner
from scripts.services.github_comment import GitHubCommentService
from scripts.services.evaluation_service import (
    EvaluationResult,
    evaluate_task,
    run_batch_evaluation,
)
from scripts.commands.agent.rules import cmd_rules
from scripts.domain.evaluation_task import EvaluationTask
from scripts.services.task_loader_service import TaskLoaderService
from scripts.services.violation_service import ViolationService
from scripts.utils.interactive import print_separator, prompt_yes_no_quit


# ============================================================
# Domain Models
# ============================================================


@dataclass
class AnalyzeStats:
    """Statistics for the analyze command."""

    tasks_total: int = 0
    tasks_evaluated: int = 0
    tasks_skipped: int = 0
    violations_found: int = 0
    comments_posted: int = 0
    comments_skipped: int = 0
    comments_failed: int = 0
    total_cost_usd: float = 0.0

    def print_summary(self) -> None:
        """Print a summary of the analysis."""
        print()
        print("=" * 60)
        print("Analysis Summary")
        print("=" * 60)
        print(f"  Tasks total: {self.tasks_total}")
        print(f"  Tasks evaluated: {self.tasks_evaluated}")
        if self.tasks_skipped > 0:
            print(f"  Tasks skipped: {self.tasks_skipped}")
        print(f"  Violations found: {self.violations_found}")
        if self.comments_posted > 0 or self.comments_skipped > 0:
            print(f"  Comments posted: {self.comments_posted}")
            if self.comments_skipped > 0:
                print(f"  Comments skipped: {self.comments_skipped}")
            if self.comments_failed > 0:
                print(f"  Comments failed: {self.comments_failed}")
        if self.total_cost_usd > 0:
            print(f"  Total cost: ${self.total_cost_usd:.4f}")


# ============================================================
# Interactive Task Prompting
# ============================================================


def group_tasks_by_segment(
    tasks: list[EvaluationTask],
) -> list[tuple[EvaluationTask, list[EvaluationTask]]]:
    """Group tasks by their code segment.

    Args:
        tasks: List of evaluation tasks (already sorted by file/line)

    Returns:
        List of (representative_task, all_tasks_for_segment) tuples
    """
    from collections import OrderedDict

    # Group by segment content hash (unique identifier for segment)
    groups: OrderedDict[str, list[EvaluationTask]] = OrderedDict()
    for task in tasks:
        key = task.segment.content_hash()
        if key not in groups:
            groups[key] = []
        groups[key].append(task)

    # Return as list of (first_task, all_tasks) for display
    return [(tasks_list[0], tasks_list) for tasks_list in groups.values()]


def prompt_for_segment(
    task: EvaluationTask,
    rules: list[str],
    index: int,
    total: int,
) -> str | None:
    """Prompt user to evaluate a segment with all its rules.

    Args:
        task: Representative task (for segment info)
        rules: List of rule names that apply to this segment
        index: Current index (1-based)
        total: Total number of segments

    Returns:
        'y' to evaluate, 'n' to skip, 'q' to quit, None on EOF
    """
    print()
    print_separator("=")
    print(f"Segment {index}/{total}")
    print_separator("=")
    print(f"  File: {task.segment.file_path}")
    print(f"  Lines: {task.segment.start_line}-{task.segment.end_line}")
    print(f"  Rules: {', '.join(rules)}")
    print_separator("-")
    # Show full diff content
    for line in task.segment.content.split("\n"):
        print(f"  {line}")
    print_separator("-")

    return prompt_yes_no_quit("Evaluate this segment?")


# ============================================================
# Interactive Evaluation Loop
# ============================================================


async def run_interactive_evaluation(
    tasks: list[EvaluationTask],
    output_dir: Path,
    pr_number: int,
    repo: str,
    stats: AnalyzeStats,
) -> None:
    """Run evaluations interactively, prompting for each segment.

    Groups tasks by segment and prompts once per segment. When approved,
    evaluates all rules for that segment.

    Args:
        tasks: List of evaluation tasks
        output_dir: PR output directory
        pr_number: PR number
        repo: Repository in owner/repo format
        stats: Statistics object to update
    """
    evaluations_dir = output_dir / "evaluations"
    evaluations_dir.mkdir(parents=True, exist_ok=True)

    # Group tasks by segment
    segment_groups = group_tasks_by_segment(tasks)
    total_segments = len(segment_groups)

    for i, (representative, segment_tasks) in enumerate(segment_groups, 1):
        rules = [t.rule.name for t in segment_tasks]

        # Prompt for this segment
        response = prompt_for_segment(representative, rules, i, total_segments)

        if response is None or response == "q":
            # Count remaining tasks across all remaining segments
            remaining_tasks = sum(
                len(grp[1]) for grp in segment_groups[i - 1 :]
            )
            stats.tasks_skipped += remaining_tasks
            print(f"\n  Quit. Skipped {remaining_tasks} remaining task(s).")
            break

        if response == "n":
            print(f"  Skipped {len(segment_tasks)} rule(s).")
            stats.tasks_skipped += len(segment_tasks)
            continue

        # Evaluate all rules for this segment
        violations_for_segment = []

        for task in segment_tasks:
            print(f"  Evaluating rule: {task.rule.name}...")
            result = await evaluate_task(task)
            stats.tasks_evaluated += 1

            if result.cost_usd:
                stats.total_cost_usd += result.cost_usd

            # Save evaluation result
            result_path = evaluations_dir / f"{task.task_id}.json"
            result_path.write_text(json.dumps(result.to_dict(), indent=2))

            # Print result path and cost
            cost_str = f", cost: ${result.cost_usd:.4f}" if result.cost_usd else ""
            print(f"    → {result_path}{cost_str}")

            if result.evaluation.violates_rule:
                stats.violations_found += 1
                print(f"    ⚠️  Violation (score: {result.evaluation.score})")
                violation = ViolationService.create_violation(result, task)
                violations_for_segment.append(violation)
            else:
                print(f"    ✓ No violation")

        # Prompt to post comments for any violations found
        if violations_for_segment:
            print()
            for vi, violation in enumerate(violations_for_segment, 1):
                comment_response = prompt_for_comment(
                    violation, vi, len(violations_for_segment)
                )

                if comment_response is None or comment_response == "q":
                    remaining = len(violations_for_segment) - vi + 1
                    stats.comments_skipped += remaining
                    print(f"  Skipped {remaining} remaining comment(s).")
                    break

                if comment_response == "y":
                    posted, failed, _ = post_violations(
                        [violation], pr_number, repo, dry_run=False, interactive=False
                    )
                    stats.comments_posted += posted
                    stats.comments_failed += failed
                else:
                    print("  Comment skipped.")
                    stats.comments_skipped += 1


async def run_analyze_batch_evaluation(
    tasks: list[EvaluationTask],
    output_dir: Path,
    stats: AnalyzeStats,
) -> list[EvaluationResult]:
    """Run all evaluations without interaction.

    Thin wrapper around the evaluation service that handles progress display
    and statistics tracking (UI concerns that belong in the command layer).

    Args:
        tasks: List of evaluation tasks
        output_dir: PR output directory
        stats: Statistics object to update

    Returns:
        List of evaluation results
    """

    def on_result(index: int, total: int, result: EvaluationResult) -> None:
        """Progress callback - handles printing and stats updates."""
        print(f"  [{index}/{total}] Evaluating {result.rule_name} on {result.file_path}...")
        stats.tasks_evaluated += 1

        if result.cost_usd:
            stats.total_cost_usd += result.cost_usd

        if result.evaluation.violates_rule:
            stats.violations_found += 1
            print(f"    ⚠️  Violation found (score: {result.evaluation.score})")
        else:
            print(f"    ✓  No violation")

    return await run_batch_evaluation(tasks, output_dir, on_result=on_result)


# ============================================================
# Command Entry Point
# ============================================================


def cmd_analyze(
    pr_number: int,
    output_dir: Path,
    rules_dir: str,
    repo: str,
    interactive: bool = True,
    dry_run: bool = True,
    stop_after: str | None = None,
    skip_to: str | None = None,
    min_score: int = 5,
) -> int:
    """Execute the analyze command - full review pipeline.

    Args:
        pr_number: PR number to analyze
        output_dir: PR-specific output directory
        rules_dir: Path to rules directory
        repo: Repository in owner/repo format
        interactive: If True, prompt before each evaluation
        dry_run: If True, don't post comments to GitHub
        stop_after: Stop after this phase (diff, rules, evaluate)
        skip_to: Skip to this phase (rules, evaluate, comment)
        min_score: Minimum score for posting comments

    Returns:
        Exit code (0 for success, non-zero for error)
    """
    # Determine mode string for display
    modes = []
    if interactive:
        modes.append("interactive")
    if dry_run:
        modes.append("dry-run")
    mode_str = ", ".join(modes) if modes else "live"

    print(f"[analyze] Running full pipeline for PR #{pr_number} ({mode_str})...")
    print(f"  Repository: {repo}")
    print(f"  Rules directory: {rules_dir}")
    print(f"  Output directory: {output_dir}")
    print()

    # Validate PR exists in repo before starting (interactive mode can post comments)
    if interactive or not dry_run:
        gh = GhCommandRunner(dry_run=False)
        comment_service = GitHubCommentService(repo=repo, gh=gh)
        commit_sha = comment_service.get_pr_head_sha(pr_number)
        if not commit_sha:
            print(f"  Error: PR #{pr_number} not found in {repo}")
            print("  Check the PR number and --repo argument.")
            return 1
        print(f"  PR validated (HEAD: {commit_sha[:8]})")
        print()

    stats = AnalyzeStats()

    # Phase 1: Diff
    if not skip_to or skip_to == "diff":
        print("=" * 60)
        print("Phase 1: Fetching PR diff")
        print("=" * 60)
        result = cmd_diff(pr_number, output_dir)
        if result != 0:
            print("  Error in diff phase")
            return result
        print()

        if stop_after == "diff":
            print("Stopped after diff phase (--stop-after diff)")
            return 0

    # Phase 2: Rules
    if not skip_to or skip_to in ("diff", "rules"):
        print("=" * 60)
        print("Phase 2: Collecting and filtering rules")
        print("=" * 60)
        result = cmd_rules(pr_number, output_dir, rules_dir)
        if result != 0:
            print("  Error in rules phase")
            return result
        print()

        if stop_after == "rules":
            print("Stopped after rules phase (--stop-after rules)")
            return 0

    # Phase 3: Evaluate
    print("=" * 60)
    print("Phase 3: Evaluating rules")
    print("=" * 60)

    # Load tasks using TaskLoaderService
    task_loader = TaskLoaderService(output_dir / "tasks")
    tasks = task_loader.load_all()

    if not tasks:
        tasks_dir = output_dir / "tasks"
        if not tasks_dir.exists():
            print(f"  Error: Tasks directory not found at {tasks_dir}")
            print("  Run without --skip-to or use --skip-to rules")
            return 1
        print("  No evaluation tasks found")
        stats.print_summary()
        return 0

    stats.tasks_total = len(tasks)
    segment_groups = group_tasks_by_segment(tasks)
    print(f"  Found {len(segment_groups)} segments, {len(tasks)} total evaluations")
    print()

    if interactive:
        # Interactive mode: prompt for each task
        asyncio.run(
            run_interactive_evaluation(
                tasks, output_dir, pr_number, repo, stats
            )
        )
    else:
        # Batch mode: evaluate all tasks
        results = asyncio.run(run_analyze_batch_evaluation(tasks, output_dir, stats))

        if stop_after == "evaluate":
            print()
            print("Stopped after evaluate phase (--stop-after evaluate)")
            stats.print_summary()
            return 0

        # Phase 4: Comment (only in non-interactive batch mode)
        if not dry_run and stats.violations_found > 0:
            print()
            print("=" * 60)
            print("Phase 4: Posting comments")
            print("=" * 60)

            # Build violations from results using ViolationService
            violations = ViolationService.filter_by_score(results, tasks, min_score)

            if violations:
                print(f"  Posting {len(violations)} comment(s)...")
                posted, failed, skipped = post_violations(
                    violations, pr_number, repo, dry_run=False, interactive=False
                )
                stats.comments_posted = posted
                stats.comments_failed = failed
                stats.comments_skipped = skipped
            else:
                print("  No violations meet the score threshold")

    stats.print_summary()
    return 0
