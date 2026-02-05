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
from typing import TYPE_CHECKING

from claude_agent_sdk import ClaudeAgentOptions, ResultMessage, query

from scripts.domain.agent_outputs import RuleEvaluation
from scripts.domain.evaluation_task import EvaluationTask

if TYPE_CHECKING:
    pass


# ============================================================
# Constants
# ============================================================

DEFAULT_MODEL = "claude-sonnet-4-20250514"

EVALUATION_PROMPT_TEMPLATE = """You are a code reviewer evaluating whether code violates a specific rule.

## Rule: {rule_name}

{rule_description}

### Rule Details

{rule_content}

## Code to Review

File: {file_path}
Lines: {start_line}-{end_line}

```diff
{diff_content}
```

## Instructions

Analyze the code changes shown in the diff and determine if they violate the rule.

Focus ONLY on the added/changed lines (lines starting with `+`). Context lines (no prefix or starting with `-`) are provided for understanding but should not be evaluated for violations.

Consider:
1. Does the new or modified code violate the rule?
2. How severe is the violation (1-10 scale)?
3. What specific improvement would fix the issue?

Be precise about the file path and line number where any violation occurs.
"""


# ============================================================
# Domain Models
# ============================================================


@dataclass
class EvaluationResult:
    """Result of evaluating a single task."""

    task_id: str
    rule_name: str
    file_path: str
    evaluation: RuleEvaluation
    model_used: str
    duration_ms: int
    cost_usd: float | None

    # --------------------------------------------------------
    # Serialization
    # --------------------------------------------------------

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "task_id": self.task_id,
            "rule_name": self.rule_name,
            "file_path": self.file_path,
            "evaluation": self.evaluation.to_dict(),
            "model_used": self.model_used,
            "duration_ms": self.duration_ms,
            "cost_usd": self.cost_usd,
        }


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


# ============================================================
# Evaluation Logic
# ============================================================


async def evaluate_task(task: EvaluationTask) -> EvaluationResult:
    """Evaluate a single task using Claude Agent SDK.

    Args:
        task: The evaluation task containing rule and code segment

    Returns:
        EvaluationResult with the evaluation outcome
    """
    # Determine model to use (from rule or default)
    model = task.model or DEFAULT_MODEL

    # Build prompt from template
    prompt = EVALUATION_PROMPT_TEMPLATE.format(
        rule_name=task.rule.name,
        rule_description=task.rule.description,
        rule_content=task.rule.content,
        file_path=task.segment.file_path,
        start_line=task.segment.start_line,
        end_line=task.segment.end_line,
        diff_content=task.segment.content,
    )

    # Configure structured output
    # Note: Don't use max_turns=1 as it may prevent the agent from completing
    # the structured output generation
    options = ClaudeAgentOptions(
        model=model,
        output_format={
            "type": "json_schema",
            "schema": RuleEvaluation.json_schema(),
        },
    )

    # Call Claude Agent SDK
    evaluation_data: dict | None = None
    duration_ms = 0
    cost_usd: float | None = None

    async for message in query(prompt=prompt, options=options):
        if isinstance(message, ResultMessage):
            # Capture structured output
            if message.structured_output:
                evaluation_data = message.structured_output
            duration_ms = message.duration_ms
            cost_usd = message.total_cost_usd

    # Check if we got valid structured output
    if evaluation_data:
        # Ensure file_path and line_number are populated from task if not in output
        if not evaluation_data.get("file_path"):
            evaluation_data["file_path"] = task.segment.file_path
        if not evaluation_data.get("line_number"):
            evaluation_data["line_number"] = task.segment.start_line

        evaluation = RuleEvaluation.from_dict(evaluation_data)
    else:
        evaluation = RuleEvaluation(
            violates_rule=False,
            score=1,
            explanation="Evaluation failed - no structured output returned",
            suggestion="",
            file_path=task.segment.file_path,
            line_number=task.segment.start_line,
        )

    return EvaluationResult(
        task_id=task.task_id,
        rule_name=task.rule.name,
        file_path=task.segment.file_path,
        evaluation=evaluation,
        model_used=model,
        duration_ms=duration_ms,
        cost_usd=cost_usd,
    )


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
