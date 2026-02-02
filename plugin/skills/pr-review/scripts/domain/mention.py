"""Domain models for @code-review mention handling.

Parse-once pattern: Raw JSON is parsed into type-safe models at the boundary.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal

ActionType = Literal[
    "postComment",
    "replyToComment",
    "replaceComment",
    "postSummary",
    "performReview",
    "unknown",
]


@dataclass
class MentionAction:
    """Parsed action from Claude's interpretation of a @mention.

    This model represents the action to take in response to a @code-review
    mention in a PR comment.
    """

    action: ActionType
    body: str = ""
    comment_id: int | None = None
    additional_instructions: str = ""
    filter_files: list[str] = field(default_factory=list)
    filter_rules: list[str] = field(default_factory=list)

    # --------------------------------------------------------
    # Factory Methods
    # --------------------------------------------------------

    @classmethod
    def from_dict(cls, data: dict) -> MentionAction:
        """Parse mention action from JSON dictionary.

        Args:
            data: Raw structured_output dictionary from Claude

        Returns:
            Typed MentionAction instance
        """
        action = data.get("action", "unknown")
        if action not in (
            "postComment",
            "replyToComment",
            "replaceComment",
            "postSummary",
            "performReview",
        ):
            action = "unknown"

        return cls(
            action=action,
            body=data.get("body", ""),
            comment_id=data.get("commentId"),
            additional_instructions=data.get("additionalInstructions", ""),
            filter_files=data.get("filterFiles") or [],
            filter_rules=data.get("filterRules") or [],
        )

    # --------------------------------------------------------
    # Public API
    # --------------------------------------------------------

    @property
    def is_comment_action(self) -> bool:
        """Whether this action posts/modifies a comment directly."""
        return self.action in (
            "postComment",
            "replyToComment",
            "replaceComment",
            "postSummary",
        )

    @property
    def is_review_action(self) -> bool:
        """Whether this action triggers a full code review."""
        return self.action == "performReview"

    @property
    def requires_comment_id(self) -> bool:
        """Whether this action requires a comment_id."""
        return self.action in ("replyToComment", "replaceComment")
