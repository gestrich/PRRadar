"""Domain models for PRRadar."""

from scripts.domain.agent_outputs import RuleApplicability, RuleEvaluation
from scripts.domain.diff import GitDiff, Hunk
from scripts.domain.mention import MentionAction
from scripts.domain.review import (
    CategorySummary,
    Feedback,
    ReviewOutput,
    ReviewSummary,
)

__all__ = [
    "CategorySummary",
    "Feedback",
    "GitDiff",
    "Hunk",
    "MentionAction",
    "ReviewOutput",
    "ReviewSummary",
    "RuleApplicability",
    "RuleEvaluation",
]
