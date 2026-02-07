"""GitHub comment service.

Core service that handles posting, replying to, and replacing comments
on GitHub PRs using the gh CLI.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass

from prradar.domain.mention import MentionAction
from prradar.domain.review import Feedback, ReviewOutput
from prradar.infrastructure.github.runner import GhCommandRunner


@dataclass
class GitHubCommentService:
    """Service for managing GitHub PR comments.

    Core service with single responsibility: GitHub comment operations.
    Uses GhCommandRunner for actual API calls (dependency injection).
    """

    repo: str
    gh: GhCommandRunner

    # ============================================================
    # Public API - Comment Operations
    # ============================================================

    def post_comment(self, pr_number: int, body: str) -> bool:
        """Post a new comment to a PR.

        Args:
            pr_number: PR number to comment on
            body: Comment body (markdown supported)

        Returns:
            True if comment was posted successfully
        """
        endpoint = f"repos/{self.repo}/issues/{pr_number}/comments"
        success, _ = self.gh.api_post(endpoint, {"body": body})

        if success:
            print(f"Posted comment to PR #{pr_number}")
        return success

    def reply_to_review_comment(
        self,
        pr_number: int,
        comment_id: int,
        body: str,
    ) -> bool:
        """Reply to a PR review comment (inline comment thread).

        Args:
            pr_number: PR number (for logging)
            comment_id: ID of the review comment to reply to
            body: Reply body

        Returns:
            True if reply was posted successfully
        """
        endpoint = f"repos/{self.repo}/pulls/comments/{comment_id}/replies"
        success, _ = self.gh.api_post(endpoint, {"body": body})

        if success:
            print(f"Replied to review comment {comment_id}")
        return success

    def replace_comment(self, comment_id: int, body: str) -> bool:
        """Replace (edit) an existing issue comment.

        Args:
            comment_id: ID of the comment to replace
            body: New comment body

        Returns:
            True if comment was replaced successfully
        """
        endpoint = f"repos/{self.repo}/issues/comments/{comment_id}"
        success, _ = self.gh.api_patch(endpoint, {"body": body})

        if success:
            print(f"Replaced comment {comment_id}")
        return success

    def post_review_comment(
        self,
        pr_number: int,
        feedback: Feedback,
        commit_sha: str,
    ) -> bool:
        """Post a review comment on a specific line of a PR.

        Args:
            pr_number: PR number
            feedback: Feedback domain model with file, line, and comment
            commit_sha: Commit SHA for the review comment

        Returns:
            True if comment was posted successfully
        """
        endpoint = f"repos/{self.repo}/pulls/{pr_number}/comments"
        body = feedback.format_comment_body()

        success, _ = self.gh.api_post_with_int(
            endpoint,
            string_fields={
                "body": body,
                "path": feedback.file,
                "side": "RIGHT",
                "commit_id": commit_sha,
            },
            int_fields={"line": feedback.line_number},
        )

        if success:
            print(f"Posted comment to {feedback.file}:{feedback.line_number} ({feedback.rule})")
        return success

    # ============================================================
    # Public API - Composite Operations
    # ============================================================

    def post_review_summary(self, pr_number: int, review: ReviewOutput) -> bool:
        """Post a summary comment for a code review.

        Args:
            pr_number: PR number
            review: ReviewOutput domain model

        Returns:
            True if summary was posted successfully
        """
        body = self._format_review_summary(review)
        return self.post_comment(pr_number, body)

    def handle_mention_action(
        self,
        action: MentionAction,
        pr_number: int,
        comment_type: str,
    ) -> bool:
        """Handle a mention action from Claude's interpretation.

        Args:
            action: MentionAction domain model
            pr_number: PR number
            comment_type: "issue_comment" or "review_comment"

        Returns:
            True if action was handled successfully
        """
        if action.action in ("postComment", "postSummary"):
            return self.post_comment(pr_number, action.body)

        elif action.action == "replyToComment":
            if not action.comment_id:
                print("replyToComment requires commentId", file=sys.stderr)
                return False

            if comment_type == "review_comment":
                return self.reply_to_review_comment(pr_number, action.comment_id, action.body)
            else:
                print("Cannot reply to issue comment - posting new comment instead")
                return self.post_comment(pr_number, action.body)

        elif action.action == "replaceComment":
            if not action.comment_id:
                print("replaceComment requires commentId", file=sys.stderr)
                return False
            return self.replace_comment(action.comment_id, action.body)

        else:
            print(f"Unknown comment action: {action.action}", file=sys.stderr)
            return False

    # ============================================================
    # Public API - Utility Operations
    # ============================================================

    def get_pr_head_sha(self, pr_number: int) -> str | None:
        """Get the HEAD commit SHA for a PR.

        Args:
            pr_number: PR number

        Returns:
            Commit SHA string, or None if not found
        """
        endpoint = f"repos/{self.repo}/pulls/{pr_number}"
        success, output = self.gh.api_get(endpoint, ".head.sha")

        if success:
            return output.strip()
        return None

    # ============================================================
    # Private Helpers
    # ============================================================

    @staticmethod
    def _format_review_summary(review: ReviewOutput) -> str:
        """Format a ReviewOutput as a markdown summary comment."""
        violations = review.violations

        lines = [
            "## Code Review Summary",
            "",
            f"**Total Focus Areas Reviewed:** {review.summary.total_focus_areas}",
            f"**Violations Found:** {len(violations)}",
            "",
        ]

        if review.summary.categories:
            lines.extend(
                [
                    "### Category Scores",
                    "",
                    "| Category | Score | Summary |",
                    "|----------|-------|---------|",
                ]
            )
            for cat_name, cat_summary in review.summary.categories.items():
                lines.append(
                    f"| {cat_name} | {cat_summary.aggregate_score} | {cat_summary.summary} |"
                )
            lines.append("")

        if violations:
            lines.extend(["### Violations", ""])
            for v in violations:
                lines.append(f"- **{v.file}:{v.line_number}** - {v.rule} (Score: {v.score})")

        return "\n".join(lines)
