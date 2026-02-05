"""Evaluation service - core rule evaluation logic using Claude Agent SDK.

This service handles the low-level details of evaluating code against rules
using the Claude Agent SDK with structured outputs.

Used by:
    - commands/agent/evaluate.py (batch evaluation command)
    - commands/agent/analyze.py (interactive pipeline)
"""

from __future__ import annotations

import json
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from claude_agent_sdk import ClaudeAgentOptions, ResultMessage, query

from scripts.domain.agent_outputs import RuleEvaluation
from scripts.domain.evaluation_task import EvaluationTask


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


async def run_batch_evaluation(
    tasks: list[EvaluationTask],
    output_dir: Path,
    on_result: Callable[[int, int, EvaluationResult], None] | None = None,
) -> list[EvaluationResult]:
    """Run evaluations for all tasks.

    Core service method - handles evaluation and file I/O but no printing.
    Progress display is delegated to the caller via callback.

    Args:
        tasks: Tasks to evaluate
        output_dir: Where to save results (creates 'evaluations' subdirectory)
        on_result: Optional callback for progress reporting. Called with
                   (index, total, result) after each evaluation completes.
                   Index is 1-based. Service does NOT print progress - caller
                   handles display via this callback.

    Returns:
        List of all evaluation results
    """
    evaluations_dir = output_dir / "evaluations"
    evaluations_dir.mkdir(parents=True, exist_ok=True)

    results: list[EvaluationResult] = []
    total = len(tasks)

    for i, task in enumerate(tasks, 1):
        result = await evaluate_task(task)
        results.append(result)

        # Save evaluation result to file
        result_path = evaluations_dir / f"{task.task_id}.json"
        result_path.write_text(json.dumps(result.to_dict(), indent=2))

        # Notify caller of progress (UI layer handles printing)
        if on_result:
            on_result(i, total, result)

    return results
