"""Domain model for evaluation tasks.

An evaluation task bundles a rule with a focus area, containing everything
needed for Claude to evaluate whether the code violates the rule.

The `agent rules` command creates these tasks. The `agent evaluate` command
consumes them.
"""

from __future__ import annotations

from dataclasses import dataclass

from scripts.domain.focus_area import FocusArea
from scripts.domain.rule import Rule


# ============================================================
# Domain Models
# ============================================================


@dataclass
class EvaluationTask:
    """A self-contained evaluation task: rule + focus area.

    Each task pairs a rule with a focus area (reviewable code unit).
    Tasks are created during the rules phase by filtering rules
    against focus areas.
    """

    task_id: str
    rule: Rule
    focus_area: FocusArea

    # --------------------------------------------------------
    # Factory Methods
    # --------------------------------------------------------

    @classmethod
    def create(cls, rule: Rule, focus_area: FocusArea) -> EvaluationTask:
        """Create an evaluation task with auto-generated ID.

        Args:
            rule: The rule to evaluate against
            focus_area: The focus area to evaluate

        Returns:
            EvaluationTask with generated task_id
        """
        task_id = f"{rule.name}-{focus_area.focus_id}"
        return cls(task_id=task_id, rule=rule, focus_area=focus_area)

    @classmethod
    def from_dict(cls, data: dict) -> EvaluationTask:
        """Parse evaluation task from dictionary.

        Args:
            data: Dictionary with task data

        Returns:
            Typed EvaluationTask instance
        """
        return cls(
            task_id=data.get("task_id", ""),
            rule=Rule.from_dict(data.get("rule", {})),
            focus_area=FocusArea.from_dict(data.get("focus_area", {})),
        )

    # --------------------------------------------------------
    # Serialization
    # --------------------------------------------------------

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization.

        The output is self-contained—includes full rule content and
        focus area text, ready for Claude evaluation.
        """
        rule_dict = {
            "name": self.rule.name,
            "description": self.rule.description,
            "category": self.rule.category,
            "model": self.rule.model,
            "content": self.rule.content,
        }
        if self.rule.documentation_link:
            rule_dict["documentation_link"] = self.rule.documentation_link

        return {
            "task_id": self.task_id,
            "rule": rule_dict,
            "focus_area": self.focus_area.to_dict(),
        }

    # --------------------------------------------------------
    # Public API
    # --------------------------------------------------------

    def suggested_filename(self) -> str:
        """Generate a filename for storing this task."""
        return f"{self.task_id}.json"

    @property
    def model(self) -> str | None:
        """Get the Claude model to use for evaluation (from rule)."""
        return self.rule.model
