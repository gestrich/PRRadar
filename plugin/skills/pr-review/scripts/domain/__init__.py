"""Domain models for PRRadar."""

from scripts.domain.agent_outputs import (
    EvaluationSummary,
    RuleApplicability,
    RuleEvaluation,
)
from scripts.domain.diff import GitDiff, Hunk
from scripts.domain.evaluation_task import CodeSegment, EvaluationTask
from scripts.domain.mention import MentionAction
from scripts.domain.review import (
    CategorySummary,
    Feedback,
    ReviewOutput,
    ReviewSummary,
)
from scripts.domain.rule import AppliesTo, GrepPatterns, Rule

__all__ = [
    "AppliesTo",
    "CategorySummary",
    "CodeSegment",
    "EvaluationSummary",
    "EvaluationTask",
    "Feedback",
    "GitDiff",
    "GrepPatterns",
    "Hunk",
    "MentionAction",
    "ReviewOutput",
    "ReviewSummary",
    "Rule",
    "RuleApplicability",
    "RuleEvaluation",
]
