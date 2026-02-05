"""Agent evaluate command - run rule evaluations using Claude Agent SDK.

Reads evaluation tasks created by the rules command and evaluates each
rule+segment combination using the Claude Agent SDK with structured outputs.

Requires:
    <output-dir>/<pr-number>/tasks/*.json  - Evaluation task files

Artifact outputs:
    <output-dir>/<pr-number>/evaluations/*.json     - Per-task evaluation results
    <output-dir>/<pr-number>/evaluations/summary.json - Aggregated results
"""

from __future__ import annotations

import asyncio
import json
from datetime import datetime, timezone
from pathlib import Path

from scripts.domain.agent_outputs import EvaluationSummary
from scripts.domain.evaluation_task import EvaluationTask
from scripts.services.evaluation_service import (
    EvaluationResult,
    run_batch_evaluation,
)
from scripts.services.task_loader_service import TaskLoaderService


async def run_evaluations(tasks: list[EvaluationTask], output_dir: Path) -> EvaluationSummary:
    """Run evaluations for all tasks sequentially.

    Thin wrapper around the evaluation service that handles progress display
    and builds the EvaluationSummary (command layer concerns).

    Args:
        tasks: List of evaluation tasks to process
        output_dir: Directory for evaluation outputs

    Returns:
        EvaluationSummary with all results
    """
    total_cost = 0.0
    total_duration = 0
    violations_count = 0

    def on_result(index: int, total: int, result: EvaluationResult) -> None:
        """Progress callback - handles printing and running totals."""
        nonlocal total_cost, total_duration, violations_count

        print(f"  [{index}/{total}] Evaluating {result.rule_name} on {result.file_path}...")

        total_duration += result.duration_ms
        if result.cost_usd:
            total_cost += result.cost_usd
        if result.evaluation.violates_rule:
            violations_count += 1
            print(f"    ⚠️  Violation found (score: {result.evaluation.score})")
        else:
            print(f"    ✓  No violation")

    results = await run_batch_evaluation(tasks, output_dir, on_result=on_result)

    # Extract PR number from output_dir path (assumes format like .../18696/...)
    pr_number = 0
    try:
        pr_number = int(output_dir.name)
    except ValueError:
        pass

    return EvaluationSummary(
        pr_number=pr_number,
        evaluated_at=datetime.now(timezone.utc),
        total_tasks=len(tasks),
        violations_found=violations_count,
        total_cost_usd=total_cost,
        total_duration_ms=total_duration,
        results=results,
    )


# ============================================================
# Command Entry Point
# ============================================================


def cmd_evaluate(pr_number: int, output_dir: Path, rules_filter: list[str] | None = None) -> int:
    """Execute the evaluate command.

    Args:
        pr_number: PR number being evaluated
        output_dir: PR-specific output directory (already includes PR number)
        rules_filter: Only evaluate tasks for these rule names (None = all rules)

    Returns:
        Exit code (0 for success, non-zero for error)
    """
    print(f"[evaluate] Running evaluations for PR #{pr_number}...")

    # Load tasks using TaskLoaderService
    task_loader = TaskLoaderService(output_dir / "tasks")

    # Apply rules filter if specified
    if rules_filter:
        all_tasks = task_loader.load_all()
        tasks = task_loader.load_filtered(rules_filter)
        if not all_tasks:
            tasks_dir = output_dir / "tasks"
            if not tasks_dir.exists():
                print(f"  Error: Tasks directory not found at {tasks_dir}")
                print("  Run 'agent rules' first to create evaluation tasks")
                return 1
            print("  No evaluation tasks found")
            print("  Run 'agent rules' to create tasks")
            return 0
        print(f"  Filtering by rules: {', '.join(rules_filter)}")
        print(f"  Matched {len(tasks)} of {len(all_tasks)} tasks")
        if not tasks:
            print("  No tasks match the specified rules")
            return 0
    else:
        tasks = task_loader.load_all()
        if not tasks:
            tasks_dir = output_dir / "tasks"
            if not tasks_dir.exists():
                print(f"  Error: Tasks directory not found at {tasks_dir}")
                print("  Run 'agent rules' first to create evaluation tasks")
                return 1
            print("  No evaluation tasks found")
            print("  Run 'agent rules' to create tasks")
            return 0
        print(f"  Loaded {len(tasks)} tasks")

    print()

    # Run evaluations
    summary = asyncio.run(run_evaluations(tasks, output_dir))

    # Write summary
    evaluations_dir = output_dir / "evaluations"
    summary_path = evaluations_dir / "summary.json"
    summary_path.write_text(json.dumps(summary.to_dict(), indent=2))

    # Print summary
    print()
    print("Evaluation Summary:")
    print(f"  Tasks evaluated: {summary.total_tasks}")
    print(f"  Violations found: {summary.violations_found}")
    print(f"  Total cost: ${summary.total_cost_usd:.4f}")
    print(f"  Total time: {summary.total_duration_ms / 1000:.1f}s")
    print()
    print(f"Artifacts saved to: {evaluations_dir}")

    return 0
