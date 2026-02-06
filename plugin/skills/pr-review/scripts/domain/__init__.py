"""Domain models for PRRadar."""

from scripts.domain.agent_outputs import (
    EvaluationSummary,
    RuleApplicability,
    RuleEvaluation,
)
from scripts.domain.diff import GitDiff, Hunk
from scripts.domain.diff_source import DiffSource
from scripts.domain.evaluation_task import EvaluationTask
from scripts.domain.focus_area import FocusArea
from scripts.domain.mention import MentionAction
from scripts.domain.review import (
    CategorySummary,
    Feedback,
    ReviewOutput,
    ReviewSummary,
)
from scripts.domain.rule import AppliesTo, GrepPatterns, Rule, RuleScope

__all__ = [
    "AppliesTo",
    "CategorySummary",
    "FocusArea",
    "DiffSource",
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
    "RuleScope",
    "RuleApplicability",
    "RuleEvaluation",
]
