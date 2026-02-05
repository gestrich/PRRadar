"""Domain models for report generation.

These models represent the structured report output, including
individual violation records and aggregated summaries.

Used by:
    - services/report_generator.py (report generation)
    - commands/agent/report.py (report command)
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime


# ============================================================
# Violation Record
# ============================================================


@dataclass
class ViolationRecord:
    """A single violation for inclusion in the report.

    Represents a rule violation with all relevant context for
    human review and potential action.
    """

    rule_name: str
    score: int
    file_path: str
    line_number: int | None
    comment: str
    documentation_link: str | None = None
    relevant_claude_skill: str | None = None

    # --------------------------------------------------------
    # Serialization
    # --------------------------------------------------------

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        result = {
            "rule_name": self.rule_name,
            "score": self.score,
            "file_path": self.file_path,
            "line_number": self.line_number,
            "comment": self.comment,
        }
        if self.documentation_link:
            result["documentation_link"] = self.documentation_link
        if self.relevant_claude_skill:
            result["relevant_claude_skill"] = self.relevant_claude_skill
        return result

    # --------------------------------------------------------
    # Factory Methods
    # --------------------------------------------------------

    @classmethod
    def from_dict(cls, data: dict) -> ViolationRecord:
        """Create ViolationRecord from dictionary.

        Args:
            data: Dictionary with violation data

        Returns:
            ViolationRecord instance
        """
        return cls(
            rule_name=data["rule_name"],
            score=data["score"],
            file_path=data["file_path"],
            line_number=data.get("line_number"),
            comment=data["comment"],
            documentation_link=data.get("documentation_link"),
            relevant_claude_skill=data.get("relevant_claude_skill"),
        )


# ============================================================
# Report Summary
# ============================================================


@dataclass
class ReportSummary:
    """Aggregated statistics for the report."""

    total_tasks_evaluated: int
    violations_found: int
    highest_severity: int
    total_cost_usd: float
    by_severity: dict[str, int] = field(default_factory=dict)
    by_file: dict[str, int] = field(default_factory=dict)
    by_rule: dict[str, int] = field(default_factory=dict)

    # --------------------------------------------------------
    # Serialization
    # --------------------------------------------------------

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "total_tasks_evaluated": self.total_tasks_evaluated,
            "violations_found": self.violations_found,
            "highest_severity": self.highest_severity,
            "total_cost_usd": self.total_cost_usd,
            "by_severity": self.by_severity,
            "by_file": self.by_file,
            "by_rule": self.by_rule,
        }


# ============================================================
# Review Report
# ============================================================


@dataclass
class ReviewReport:
    """Complete review report for a PR.

    Contains summary statistics, individual violations,
    and metadata about the review process.
    """

    pr_number: int
    generated_at: datetime
    min_score_threshold: int
    summary: ReportSummary
    violations: list[ViolationRecord]

    # --------------------------------------------------------
    # Serialization
    # --------------------------------------------------------

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "pr_number": self.pr_number,
            "generated_at": self.generated_at.isoformat(),
            "min_score_threshold": self.min_score_threshold,
            "summary": self.summary.to_dict(),
            "violations": [v.to_dict() for v in self.violations],
        }

    # --------------------------------------------------------
    # Markdown Generation
    # --------------------------------------------------------

    def to_markdown(self) -> str:
        """Generate human-readable markdown report.

        Returns:
            Formatted markdown string
        """
        lines: list[str] = []

        # Header
        lines.append(f"# Code Review Report: PR #{self.pr_number}")
        lines.append("")
        lines.append(f"Generated: {self.generated_at.strftime('%Y-%m-%d %H:%M:%S UTC')}")
        lines.append(f"Minimum Score Threshold: {self.min_score_threshold}")
        lines.append("")

        # Summary section
        lines.append("## Summary")
        lines.append("")
        lines.append(f"- **Tasks Evaluated:** {self.summary.total_tasks_evaluated}")
        lines.append(f"- **Violations Found:** {self.summary.violations_found}")
        if self.summary.highest_severity > 0:
            lines.append(f"- **Highest Severity:** {self.summary.highest_severity}")
        if self.summary.total_cost_usd > 0:
            lines.append(f"- **Total Cost:** ${self.summary.total_cost_usd:.4f}")
        lines.append("")

        # Breakdown by severity
        if self.summary.by_severity:
            lines.append("### By Severity")
            lines.append("")
            lines.append("| Severity | Count |")
            lines.append("|----------|-------|")
            for severity, count in sorted(
                self.summary.by_severity.items(),
                key=lambda x: self._severity_sort_key(x[0]),
                reverse=True,
            ):
                lines.append(f"| {severity} | {count} |")
            lines.append("")

        # Breakdown by file
        if self.summary.by_file:
            lines.append("### By File")
            lines.append("")
            lines.append("| File | Violations |")
            lines.append("|------|------------|")
            for file_path, count in sorted(
                self.summary.by_file.items(), key=lambda x: -x[1]
            ):
                lines.append(f"| `{file_path}` | {count} |")
            lines.append("")

        # Breakdown by rule
        if self.summary.by_rule:
            lines.append("### By Rule")
            lines.append("")
            lines.append("| Rule | Violations |")
            lines.append("|------|------------|")
            for rule_name, count in sorted(
                self.summary.by_rule.items(), key=lambda x: -x[1]
            ):
                lines.append(f"| {rule_name} | {count} |")
            lines.append("")

        # Violations section
        if self.violations:
            lines.append("## Violations")
            lines.append("")

            for i, v in enumerate(self.violations, 1):
                location = (
                    f"{v.file_path}:{v.line_number}"
                    if v.line_number
                    else v.file_path
                )
                lines.append(f"### {i}. {v.rule_name} (Score: {v.score})")
                lines.append("")
                lines.append(f"**Location:** `{location}`")
                lines.append("")
                lines.append(v.comment)
                if v.documentation_link:
                    lines.append("")
                    lines.append(f"[Documentation]({v.documentation_link})")
                if v.relevant_claude_skill:
                    lines.append("")
                    lines.append(f"Related Claude Skill: `/{v.relevant_claude_skill}`")
                lines.append("")
                lines.append("---")
                lines.append("")
        else:
            lines.append("## Violations")
            lines.append("")
            lines.append("No violations found meeting the score threshold.")
            lines.append("")

        return "\n".join(lines)

    # --------------------------------------------------------
    # Private Helpers
    # --------------------------------------------------------

    def _severity_sort_key(self, severity: str) -> int:
        """Return sort key for severity level."""
        severity_order = {"Severe (8-10)": 3, "Moderate (5-7)": 2, "Minor (1-4)": 1}
        return severity_order.get(severity, 0)
