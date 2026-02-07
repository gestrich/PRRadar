"""Handle @code-review mention command.

Thin command that orchestrates domain models and services.
No business logic - just wiring and coordination.
"""

from __future__ import annotations

import json
import sys

from prradar.domain.mention import MentionAction
from prradar.infrastructure import (
    GhCommandRunner,
    extract_structured_output,
    load_execution_file,
    write_github_output,
)
from prradar.services import GitHubCommentService


def cmd_handle_mention(
    execution_file: str,
    pr_number: int,
    repo: str,
    comment_type: str = "issue_comment",
) -> int:
    """Handle a @code-review mention in a PR comment.

    Thin command that:
    1. Loads and parses the execution file into domain models
    2. Routes to appropriate action (comment or review)
    3. Outputs parameters for downstream workflow jobs

    For comment actions (postComment, replyToComment, etc.), posts the comment directly.
    For performReview, outputs parameters to GITHUB_OUTPUT for the review workflow.

    Args:
        execution_file: Path to Claude's execution output JSON file
        pr_number: PR number
        repo: Repository in owner/repo format
        comment_type: Type of comment (issue_comment or review_comment)

    Returns:
        Exit code (0 for success, 1 for failure)
    """
    # --------------------------------------------------------
    # 1. Load and parse into domain model
    # --------------------------------------------------------
    try:
        execution_data = load_execution_file(execution_file)
    except FileNotFoundError:
        print(f"Execution file not found: {execution_file}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Failed to parse execution file: {e}", file=sys.stderr)
        return 1

    structured_output = extract_structured_output(execution_data)
    if not structured_output:
        print("No structured output found in execution file", file=sys.stderr)
        write_github_output("action", "unknown")
        return 1

    # Parse-once: raw JSON → typed domain model
    action = MentionAction.from_dict(structured_output)
    print(f"Parsed action: {action.action}")

    # Always output action type for workflow conditionals
    write_github_output("action", action.action)

    # --------------------------------------------------------
    # 2. Route based on action type
    # --------------------------------------------------------
    if action.is_review_action:
        return _handle_review_action(action, pr_number)

    elif action.is_comment_action:
        return _handle_comment_action(action, pr_number, repo, comment_type)

    else:
        print(f"Unknown action: {action.action}", file=sys.stderr)
        return 1


# ============================================================
# Private Helpers
# ============================================================


def _handle_review_action(action: MentionAction, pr_number: int) -> int:
    """Output parameters for the review workflow."""
    write_github_output("pr_number", str(pr_number))
    write_github_output("additional_instructions", action.additional_instructions)
    write_github_output("filter_files", json.dumps(action.filter_files))
    write_github_output("filter_rules", json.dumps(action.filter_rules))

    print("Review parameters written to GITHUB_OUTPUT")
    return 0


def _handle_comment_action(
    action: MentionAction,
    pr_number: int,
    repo: str,
    comment_type: str,
) -> int:
    """Handle comment action via GitHubCommentService."""
    # Initialize service with dependencies
    gh_runner = GhCommandRunner(dry_run=False)
    comment_service = GitHubCommentService(repo=repo, gh=gh_runner)

    # Delegate to service
    success = comment_service.handle_mention_action(action, pr_number, comment_type)
    return 0 if success else 1
