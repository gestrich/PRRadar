"""Domain models for PRRadar."""

from prradar.domain.agent_outputs import (
    EvaluationSummary,
    RuleApplicability,
    RuleEvaluation,
)
from prradar.domain.diff import GitDiff, Hunk
from prradar.domain.diff_source import DiffSource
from prradar.domain.evaluation_task import EvaluationTask
from prradar.domain.focus_area import FocusArea, FocusType
from prradar.domain.mention import MentionAction
from prradar.domain.review import (
    CategorySummary,
    Feedback,
    ReviewOutput,
    ReviewSummary,
)
from prradar.domain.rule import AppliesTo, GrepPatterns, Rule, RuleScope

__all__ = [
    "AppliesTo",
    "CategorySummary",
    "FocusArea",
    "FocusType",
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
