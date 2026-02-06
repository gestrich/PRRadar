"""Report generation service.

Generates structured reports from evaluation results, including
JSON and markdown formats for human review.

Used by:
    - commands/agent/report.py (report command)
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from scripts.domain.agent_outputs import RuleEvaluation
from scripts.domain.report import ReportSummary, ReviewReport, ViolationRecord
from scripts.services.phase_sequencer import PhaseSequencer, PipelinePhase


# ============================================================
# Report Generator Service
# ============================================================


class ReportGeneratorService:
    """Generates review reports from evaluation results.

    Follows the Service Layer pattern with no external dependencies
    beyond file I/O for reading evaluation results.
    """

    def __init__(self, evaluations_dir: Path, tasks_dir: Path):
        """Initialize the report generator.

        Args:
            evaluations_dir: Directory containing evaluation JSON files
            tasks_dir: Directory containing task JSON files (for metadata)
        """
        self._evaluations_dir = evaluations_dir
        self._tasks_dir = tasks_dir

    # --------------------------------------------------------
    # Public API
    # --------------------------------------------------------

    def generate_report(self, pr_number: int, min_score: int) -> ReviewReport:
        """Generate a complete review report.

        Args:
            pr_number: PR number for the report
            min_score: Minimum score threshold for including violations

        Returns:
            ReviewReport with summary and violations
        """
        # Load all evaluation results
        violations, total_tasks, total_cost = self._load_violations(min_score)

        # Calculate summary statistics
        summary = self._calculate_summary(violations, total_tasks, total_cost)

        # Sort violations by score (highest first), then by file
        violations.sort(key=lambda v: (-v.score, v.file_path))

        return ReviewReport(
            pr_number=pr_number,
            generated_at=datetime.now(timezone.utc),
            min_score_threshold=min_score,
            summary=summary,
            violations=violations,
        )

    def save_report(self, report: ReviewReport, output_dir: Path) -> tuple[Path, Path]:
        """Save report to JSON and markdown files.

        Args:
            report: The generated report
            output_dir: PR-specific output directory

        Returns:
            Tuple of (json_path, markdown_path)
        """
        report_dir = PhaseSequencer.ensure_phase_dir(output_dir, PipelinePhase.REPORT)

        # Save JSON
        json_path = report_dir / "summary.json"
        json_path.write_text(json.dumps(report.to_dict(), indent=2))

        # Save markdown
        md_path = report_dir / "summary.md"
        md_path.write_text(report.to_markdown())

        return json_path, md_path

    # --------------------------------------------------------
    # Private Helpers
    # --------------------------------------------------------

    def _load_violations(
        self, min_score: int
    ) -> tuple[list[ViolationRecord], int, float]:
        """Load violations from evaluation results.

        Args:
            min_score: Minimum score threshold

        Returns:
            Tuple of (violations, total_tasks_evaluated, total_cost_usd)
        """
        violations: list[ViolationRecord] = []
        total_tasks = 0
        total_cost = 0.0

        # Load task metadata for additional fields
        task_metadata = self._load_task_metadata()

        # Process evaluation files
        for eval_file in self._evaluations_dir.glob("*.json"):
            if eval_file.name == "summary.json":
                continue

            try:
                data = json.loads(eval_file.read_text())
                total_tasks += 1

                # Accumulate cost
                if data.get("cost_usd"):
                    total_cost += data["cost_usd"]

                evaluation_data = data.get("evaluation", {})
                evaluation = RuleEvaluation.from_dict(evaluation_data)

                # Skip non-violations
                if not evaluation.violates_rule:
                    continue

                # Skip below threshold
                if evaluation.score < min_score:
                    continue

                # Get task metadata for enrichment
                task_id = data.get("task_id", "")
                rule_name = data.get("rule_name", "")
                file_path = data.get("file_path", "") or evaluation.file_path

                documentation_link = None
                relevant_claude_skill = None
                if task_id in task_metadata:
                    rule_data = task_metadata[task_id].get("rule", {})
                    documentation_link = rule_data.get("documentation_link")
                    relevant_claude_skill = rule_data.get("relevant_claude_skill")

                violations.append(
                    ViolationRecord(
                        rule_name=rule_name,
                        score=evaluation.score,
                        file_path=file_path,
                        line_number=evaluation.line_number,
                        comment=evaluation.comment,
                        documentation_link=documentation_link,
                        relevant_claude_skill=relevant_claude_skill,
                    )
                )

            except (json.JSONDecodeError, KeyError):
                continue

        return violations, total_tasks, total_cost

    def _load_task_metadata(self) -> dict[str, dict]:
        """Load task metadata for enrichment.

        Returns:
            Dictionary mapping task_id to task data
        """
        metadata: dict[str, dict] = {}

        if not self._tasks_dir.exists():
            return metadata

        for task_file in self._tasks_dir.glob("*.json"):
            try:
                data = json.loads(task_file.read_text())
                task_id = data.get("task_id", "")
                if task_id:
                    metadata[task_id] = data
            except (json.JSONDecodeError, KeyError):
                continue

        return metadata

    def _calculate_summary(
        self,
        violations: list[ViolationRecord],
        total_tasks: int,
        total_cost: float,
    ) -> ReportSummary:
        """Calculate summary statistics from violations.

        Args:
            violations: List of violations
            total_tasks: Total number of tasks evaluated
            total_cost: Total cost in USD

        Returns:
            ReportSummary with aggregated statistics
        """
        # Calculate highest severity
        highest_severity = max((v.score for v in violations), default=0)

        # Group by severity level
        by_severity: dict[str, int] = {}
        for v in violations:
            if v.score >= 8:
                level = "Severe (8-10)"
            elif v.score >= 5:
                level = "Moderate (5-7)"
            else:
                level = "Minor (1-4)"
            by_severity[level] = by_severity.get(level, 0) + 1

        # Group by file
        by_file: dict[str, int] = {}
        for v in violations:
            by_file[v.file_path] = by_file.get(v.file_path, 0) + 1

        # Group by rule
        by_rule: dict[str, int] = {}
        for v in violations:
            by_rule[v.rule_name] = by_rule.get(v.rule_name, 0) + 1

        return ReportSummary(
            total_tasks_evaluated=total_tasks,
            violations_found=len(violations),
            highest_severity=highest_severity,
            total_cost_usd=total_cost,
            by_severity=by_severity,
            by_file=by_file,
            by_rule=by_rule,
        )
