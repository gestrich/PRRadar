"""Domain models for code review output.

Parse-once pattern: Raw JSON is parsed into type-safe models at the boundary.
Services use the clean, typed API - no dictionary access or parsing logic.
"""

from __future__ import annotations

from dataclasses import dataclass, field


# ============================================================
# Domain Models
# ============================================================


@dataclass
class Feedback:
    """A single piece of review feedback for a focus area."""

    file: str
    focus_area_id: str
    rule: str
    score: int
    line_number: int
    github_comment: str
    details: str

    # --------------------------------------------------------
    # Factory Methods
    # --------------------------------------------------------

    @classmethod
    def from_dict(cls, data: dict) -> Feedback:
        """Parse feedback from JSON dictionary.

        Args:
            data: Raw JSON dictionary from Claude's output

        Returns:
            Typed Feedback instance
        """
        return cls(
            file=data.get("file", ""),
            focus_area_id=data.get("focus_area_id", data.get("segment", "")),
            rule=data.get("rule", ""),
            score=data.get("score", 0),
            line_number=data.get("lineNumber", 0),
            github_comment=data.get("githubComment", ""),
            details=data.get("details", ""),
        )

    # --------------------------------------------------------
    # Public API
    # --------------------------------------------------------

    @property
    def is_violation(self) -> bool:
        """Whether this feedback qualifies as a violation (score >= 5)."""
        return self.score >= 5

    def format_comment_body(self) -> str:
        """Format the feedback as a GitHub comment body."""
        body = f"**{self.rule}** (Score: {self.score})\n\n{self.github_comment}"
        if self.details and self.details != self.github_comment:
            body += f"\n\n---\n*Details: {self.details}*"
        return body


@dataclass
class CategorySummary:
    """Summary statistics for a review category."""

    aggregate_score: int
    summary: str

    @classmethod
    def from_dict(cls, data: dict) -> CategorySummary:
        """Parse category summary from JSON dictionary."""
        return cls(
            aggregate_score=data.get("aggregateScore", 0),
            summary=data.get("summary", ""),
        )


@dataclass
class ReviewSummary:
    """Overall review summary with statistics and category breakdowns."""

    summary_file: str
    total_focus_areas: int
    total_violations: int
    categories: dict[str, CategorySummary] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, data: dict) -> ReviewSummary:
        """Parse review summary from JSON dictionary."""
        categories = {}
        for name, cat_data in data.get("categories", {}).items():
            categories[name] = CategorySummary.from_dict(cat_data)

        return cls(
            summary_file=data.get("summaryFile", ""),
            total_focus_areas=data.get("totalFocusAreas", data.get("totalSegments", 0)),
            total_violations=data.get("totalViolations", 0),
            categories=categories,
        )


@dataclass
class ReviewOutput:
    """Complete review output from Claude.

    This is the top-level domain model for code review results.
    Use from_dict() to parse raw JSON into a type-safe model.
    """

    success: bool
    feedback: list[Feedback] = field(default_factory=list)
    summary: ReviewSummary = field(default_factory=lambda: ReviewSummary(summary_file="", total_focus_areas=0, total_violations=0))

    # --------------------------------------------------------
    # Factory Methods
    # --------------------------------------------------------

    @classmethod
    def from_dict(cls, data: dict) -> ReviewOutput:
        """Parse complete review output from JSON dictionary.

        This is the primary entry point for parsing Claude's structured output.

        Args:
            data: Raw structured_output dictionary from Claude

        Returns:
            Typed ReviewOutput instance with all nested models parsed
        """
        feedback = [Feedback.from_dict(f) for f in data.get("feedback", [])]
        summary_data = data.get("summary", {})
        summary = ReviewSummary.from_dict(summary_data)

        return cls(
            success=data.get("success", False),
            feedback=feedback,
            summary=summary,
        )

    # --------------------------------------------------------
    # Public API
    # --------------------------------------------------------

    @property
    def violations(self) -> list[Feedback]:
        """Get only feedback items that qualify as violations (score >= 5)."""
        return [f for f in self.feedback if f.is_violation]

    def get_violations_by_min_score(self, min_score: int) -> list[Feedback]:
        """Get feedback items with score >= min_score."""
        return [f for f in self.feedback if f.score >= min_score]
