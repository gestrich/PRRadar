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
from scripts.services.evaluation_service import (
    EvaluationResult,
    evaluate_task,
    run_batch_evaluation,
)
from scripts.commands.agent.rules import cmd_rules
from scripts.domain.evaluation_task import EvaluationTask
from scripts.services.task_loader_service import TaskLoaderService
from scripts.services.violation_service import ViolationService
from scripts.utils.interactive import print_separator, prompt_yes_skip_quit


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


def prompt_for_task(task: EvaluationTask, index: int, total: int) -> str | None:
    """Prompt user to evaluate, skip, or quit for a task.

    Args:
        task: The evaluation task to prompt for
        index: Current index (1-based)
        total: Total number of tasks

    Returns:
        'y' to evaluate, 's' to skip, 'q' to quit, None on EOF
    """
    print()
    print_separator("=")
    print(f"Task {index}/{total}")
    print_separator("=")
    print(f"  Rule: {task.rule.name}")
    print(f"  Description: {task.rule.description}")
    print(f"  File: {task.segment.file_path}")
    print(f"  Lines: {task.segment.start_line}-{task.segment.end_line}")
    print_separator("-")
    # Show a preview of the diff content (first few lines)
    content_lines = task.segment.content.split("\n")
    preview_lines = content_lines[:10]
    for line in preview_lines:
        print(f"  {line}")
    if len(content_lines) > 10:
        print(f"  ... ({len(content_lines) - 10} more lines)")
    print_separator("-")

    return prompt_yes_skip_quit("Evaluate this task?")


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
    """Run evaluations interactively, prompting for each task.

    Args:
        tasks: List of evaluation tasks
        output_dir: PR output directory
        pr_number: PR number
        repo: Repository in owner/repo format
        stats: Statistics object to update
    """
    evaluations_dir = output_dir / "evaluations"
    evaluations_dir.mkdir(parents=True, exist_ok=True)

    total = len(tasks)

    for i, task in enumerate(tasks, 1):
        # Prompt for this task
        response = prompt_for_task(task, i, total)

        if response is None or response == "q":
            remaining = total - i + 1
            stats.tasks_skipped += remaining
            print(f"\n  Quit. Skipped {remaining} remaining task(s).")
            break

        if response == "s":
            print("  Skipped.")
            stats.tasks_skipped += 1
            continue

        # Evaluate the task
        print(f"  Evaluating...")
        result = await evaluate_task(task)
        stats.tasks_evaluated += 1

        if result.cost_usd:
            stats.total_cost_usd += result.cost_usd

        # Save evaluation result
        result_path = evaluations_dir / f"{task.task_id}.json"
        result_path.write_text(json.dumps(result.to_dict(), indent=2))

        if result.evaluation.violates_rule:
            stats.violations_found += 1
            print(f"  ⚠️  Violation found (score: {result.evaluation.score})")
            print(f"  {result.evaluation.explanation[:100]}...")

            # Create violation for commenting
            violation = ViolationService.create_violation(result, task)

            # Prompt to post comment
            comment_response = prompt_for_comment(violation, 1, 1)

            if comment_response == "y":
                posted, failed, _ = post_violations(
                    [violation], pr_number, repo, dry_run=False, interactive=False
                )
                stats.comments_posted += posted
                stats.comments_failed += failed
            else:
                print("  Comment skipped.")
                stats.comments_skipped += 1
        else:
            print(f"  ✓ No violation")


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
    print(f"  Rules directory: {rules_dir}")
    print(f"  Output directory: {output_dir}")
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
    print(f"  Found {len(tasks)} evaluation tasks")
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
