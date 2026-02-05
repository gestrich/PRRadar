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
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from scripts.domain.evaluation_task import EvaluationTask
from scripts.services.evaluation_service import (
    DEFAULT_MODEL,
    EvaluationResult,
    evaluate_task,
)


# ============================================================
# Domain Models
# ============================================================


@dataclass
class EvaluationSummary:
    """Summary of all evaluations for a PR."""

    pr_number: int
    evaluated_at: datetime
    total_tasks: int
    violations_found: int
    total_cost_usd: float
    total_duration_ms: int
    results: list[EvaluationResult]

    # --------------------------------------------------------
    # Serialization
    # --------------------------------------------------------

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "pr_number": self.pr_number,
            "evaluated_at": self.evaluated_at.isoformat(),
            "total_tasks": self.total_tasks,
            "violations_found": self.violations_found,
            "total_cost_usd": self.total_cost_usd,
            "total_duration_ms": self.total_duration_ms,
            "results": [r.to_dict() for r in self.results],
        }


async def run_evaluations(tasks: list[EvaluationTask], output_dir: Path) -> EvaluationSummary:
    """Run evaluations for all tasks sequentially.

    Args:
        tasks: List of evaluation tasks to process
        output_dir: Directory for evaluation outputs

    Returns:
        EvaluationSummary with all results
    """
    evaluations_dir = output_dir / "evaluations"
    evaluations_dir.mkdir(parents=True, exist_ok=True)

    results: list[EvaluationResult] = []
    total_cost = 0.0
    total_duration = 0
    violations_count = 0

    for i, task in enumerate(tasks, 1):
        print(f"  [{i}/{len(tasks)}] Evaluating {task.rule.name} on {task.segment.file_path}...")

        result = await evaluate_task(task)
        results.append(result)

        # Update totals
        total_duration += result.duration_ms
        if result.cost_usd:
            total_cost += result.cost_usd
        if result.evaluation.violates_rule:
            violations_count += 1
            print(f"    ⚠️  Violation found (score: {result.evaluation.score})")
        else:
            print(f"    ✓  No violation")

        # Write individual result
        result_path = evaluations_dir / f"{task.task_id}.json"
        result_path.write_text(json.dumps(result.to_dict(), indent=2))

    # Create summary
    # Extract PR number from output_dir path (assumes format like .../18696/...)
    pr_number = 0
    try:
        pr_number = int(output_dir.name)
    except ValueError:
        pass

    summary = EvaluationSummary(
        pr_number=pr_number,
        evaluated_at=datetime.now(timezone.utc),
        total_tasks=len(tasks),
        violations_found=violations_count,
        total_cost_usd=total_cost,
        total_duration_ms=total_duration,
        results=results,
    )

    return summary


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

    # Verify tasks directory exists
    tasks_dir = output_dir / "tasks"
    if not tasks_dir.exists():
        print(f"  Error: Tasks directory not found at {tasks_dir}")
        print("  Run 'agent rules' first to create evaluation tasks")
        return 1

    # Load all task files
    task_files = sorted(tasks_dir.glob("*.json"))
    if not task_files:
        print("  No evaluation tasks found")
        print("  Run 'agent rules' to create tasks")
        return 0

    print(f"  Found {len(task_files)} evaluation tasks")

    # Parse tasks
    tasks: list[EvaluationTask] = []
    for task_file in task_files:
        try:
            data = json.loads(task_file.read_text())
            task = EvaluationTask.from_dict(data)
            tasks.append(task)
        except (json.JSONDecodeError, KeyError) as e:
            print(f"  Warning: Failed to parse {task_file.name}: {e}")
            continue

    if not tasks:
        print("  Error: No valid tasks could be loaded")
        return 1

    # Apply rules filter if specified
    if rules_filter:
        filtered_tasks = [t for t in tasks if t.rule.name in rules_filter]
        print(f"  Filtering by rules: {', '.join(rules_filter)}")
        print(f"  Matched {len(filtered_tasks)} of {len(tasks)} tasks")
        tasks = filtered_tasks
        if not tasks:
            print("  No tasks match the specified rules")
            return 0
    else:
        print(f"  Loaded {len(tasks)} valid tasks")

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
