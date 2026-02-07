"""Agent evaluate command - run rule evaluations using Claude Agent SDK.

Reads evaluation tasks created by the rules command and evaluates each
rule+focus area combination using the Claude Agent SDK with structured outputs.

Requires:
    <output-dir>/<pr-number>/phase-4-tasks/*.json  - Evaluation task files

Artifact outputs:
    <output-dir>/<pr-number>/phase-5-evaluations/*.json     - Per-task evaluation results
    <output-dir>/<pr-number>/phase-5-evaluations/summary.json - Aggregated results
"""

from __future__ import annotations

import asyncio
import json
from datetime import datetime, timezone
from pathlib import Path

from prradar.domain.agent_outputs import EvaluationSummary
from prradar.domain.evaluation_task import EvaluationTask
from prradar.services.evaluation_service import (
    EvaluationResult,
    run_batch_evaluation,
)
from prradar.services.phase_sequencer import PhaseSequencer, PipelinePhase
from prradar.services.task_loader_service import TaskLoaderService


def cmd_evaluate(
    pr_number: int,
    output_dir: Path,
    rules_filter: list[str] | None = None,
    repo_path: str = ".",
) -> int:
    """Execute the evaluate command.

    Args:
        pr_number: PR number being evaluated
        output_dir: PR-specific output directory (already includes PR number)
        rules_filter: Only evaluate tasks for these rule names (None = all rules)
        repo_path: Path to the local repo checkout for codebase exploration

    Returns:
        Exit code (0 for success, non-zero for error)
    """
    print(f"[evaluate] Running evaluations for PR #{pr_number}...")

    # Validate dependencies
    error = PhaseSequencer.validate_can_run(output_dir, PipelinePhase.EVALUATIONS)
    if error:
        print(f"  Error: {error}")
        print("  Run 'agent rules' first to create evaluation tasks")
        return 1

    # Initialize services
    task_loader = TaskLoaderService(PhaseSequencer.get_phase_dir(output_dir, PipelinePhase.TASKS))

    # Load tasks (service returns data, command prints)
    if rules_filter:
        tasks = task_loader.load_filtered(rules_filter)
        print(f"  Filtering by rules: {', '.join(rules_filter)}")
        print(f"  Matched {len(tasks)} tasks")
    else:
        tasks = task_loader.load_all()
        print(f"  Loaded {len(tasks)} tasks")

    # Handle no tasks case
    if not tasks:
        tasks_dir = PhaseSequencer.get_phase_dir(output_dir, PipelinePhase.TASKS)
        if not tasks_dir.exists():
            print(f"  Error: Tasks directory not found at {tasks_dir}")
            print("  Run 'agent rules' first to create evaluation tasks")
            return 1
        if rules_filter:
            print("  No tasks match the specified rules")
        else:
            print("  No evaluation tasks found")
            print("  Run 'agent rules' to create tasks")
        return 0

    # Check for resume (skip already-evaluated tasks)
    task_ids = [t.task_id for t in tasks]
    remaining_ids, skipped = PhaseSequencer.get_remaining_items(
        output_dir, PipelinePhase.EVALUATIONS, task_ids
    )

    if skipped > 0:
        print(f"  Resuming: skipping {skipped} already-evaluated tasks")
        remaining_set = set(remaining_ids)
        tasks = [t for t in tasks if t.task_id in remaining_set]

    if not tasks:
        print("  All tasks already evaluated")
        return 0

    print()

    # Track running totals for summary
    total_cost = 0.0
    total_duration = 0
    violations_count = 0

    # Callbacks for progress display
    def on_start(index: int, total: int, task: EvaluationTask) -> None:
        method_info = task.focus_area.description
        print(f"  [{index}/{total}] {task.focus_area.file_path}:{method_info} - {task.rule.name}")

    def on_result(index: int, total: int, result: EvaluationResult) -> None:
        nonlocal total_cost, total_duration, violations_count

        if result.evaluation.violates_rule:
            print(f"    ⚠️ Violation (score: {result.evaluation.score})")
        else:
            print(f"    ✓ OK")

        total_duration += result.duration_ms
        if result.cost_usd:
            total_cost += result.cost_usd
        if result.evaluation.violates_rule:
            violations_count += 1

    # Run evaluations
    results = asyncio.run(
        run_batch_evaluation(tasks, output_dir, on_result, on_start=on_start, repo_path=repo_path)
    )

    # Build and save summary
    summary = EvaluationSummary(
        pr_number=pr_number,
        evaluated_at=datetime.now(timezone.utc),
        total_tasks=len(tasks),
        violations_found=violations_count,
        total_cost_usd=total_cost,
        total_duration_ms=total_duration,
        results=results,
    )

    evaluations_dir = PhaseSequencer.get_phase_dir(output_dir, PipelinePhase.EVALUATIONS)
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
