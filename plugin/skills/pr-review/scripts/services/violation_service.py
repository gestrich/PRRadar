"""Violation service - transform evaluation results into commentable violations.

Core service - focused on data transformation, no I/O.

Used by:
    - commands/agent/analyze.py (violation creation in pipeline)
"""

from __future__ import annotations

from scripts.commands.agent.comment import CommentableViolation
from scripts.domain.evaluation_task import EvaluationTask
from scripts.services.evaluation_service import EvaluationResult


class ViolationService:
    """Transform evaluation results into commentable violations.

    Core service - focused on data transformation, no I/O.
    All methods are static as they are pure transformations with no state dependency.
    """

    @staticmethod
    def create_violation(
        result: EvaluationResult,
        task: EvaluationTask,
    ) -> CommentableViolation:
        """Create a commentable violation from an evaluation result and task.

        Static - pure transformation, no state needed.

        Args:
            result: The evaluation result containing violation details
            task: The original task containing rule metadata (for documentation_link)

        Returns:
            A CommentableViolation ready for posting to GitHub
        """
        # Extract diff context around the violation line
        diff_context = task.segment.get_context_around_line(
            result.evaluation.line_number,
            context_lines=3,
        )

        return CommentableViolation(
            task_id=result.task_id,
            rule_name=result.rule_name,
            file_path=result.file_path,
            line_number=result.evaluation.line_number,
            score=result.evaluation.score,
            comment=result.evaluation.comment,
            documentation_link=task.rule.documentation_link,
            relevant_claude_skill=task.rule.relevant_claude_skill,
            cost_usd=result.cost_usd,
            diff_context=diff_context,
            rule_url=task.rule.rule_url,
        )

    @staticmethod
    def filter_by_score(
        results: list[EvaluationResult],
        tasks: list[EvaluationTask],
        min_score: int,
    ) -> list[CommentableViolation]:
        """Filter evaluation results and convert to violations.

        Static - pure filter function.

        Args:
            results: List of evaluation results to filter
            tasks: List of tasks (used to look up documentation_link by task_id)
            min_score: Minimum score threshold for inclusion

        Returns:
            List of CommentableViolation objects for results that:
            - Have violates_rule=True
            - Have score >= min_score
        """
        task_map = {task.task_id: task for task in tasks}
        violations: list[CommentableViolation] = []

        for result in results:
            if not result.evaluation.violates_rule:
                continue

            if result.evaluation.score < min_score:
                continue

            task = task_map.get(result.task_id)
            if task:
                violations.append(ViolationService.create_violation(result, task))

        return violations
