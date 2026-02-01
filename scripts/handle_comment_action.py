#!/usr/bin/env python3
"""
Handle comment actions from Claude's @code-review mention interpretation.

This script reads the JSON action output from Claude's interpretation and
executes the appropriate GitHub action using the `gh` CLI.

Actions supported:
- postComment: Post a new comment on the PR
- replyToComment: Reply to a specific existing comment
- replaceComment: Edit/replace an existing comment
- postSummary: Post a summary comment
- performReview: Trigger a full code review (handled by workflow, not this script)
"""

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Literal


@dataclass
class PostCommentAction:
    """Post a new comment on the PR."""
    action: Literal["postComment"]
    body: str


@dataclass
class ReplyToCommentAction:
    """Reply to a specific existing comment."""
    action: Literal["replyToComment"]
    comment_id: int
    body: str


@dataclass
class ReplaceCommentAction:
    """Edit/replace an existing comment."""
    action: Literal["replaceComment"]
    comment_id: int
    body: str


@dataclass
class PostSummaryAction:
    """Post a summary comment."""
    action: Literal["postSummary"]
    body: str


@dataclass
class PerformReviewAction:
    """Trigger a full code review."""
    action: Literal["performReview"]
    additional_instructions: str | None
    filter_files: list[str] | None
    filter_rules: list[str] | None


CommentAction = (
    PostCommentAction
    | ReplyToCommentAction
    | ReplaceCommentAction
    | PostSummaryAction
    | PerformReviewAction
)


def parse_action(data: dict) -> CommentAction:
    """Parse an action from JSON data."""
    action_type = data.get("action", "")

    if action_type == "postComment":
        return PostCommentAction(
            action="postComment",
            body=data.get("body", ""),
        )
    elif action_type == "replyToComment":
        return ReplyToCommentAction(
            action="replyToComment",
            comment_id=data.get("commentId", 0),
            body=data.get("body", ""),
        )
    elif action_type == "replaceComment":
        return ReplaceCommentAction(
            action="replaceComment",
            comment_id=data.get("commentId", 0),
            body=data.get("body", ""),
        )
    elif action_type == "postSummary":
        return PostSummaryAction(
            action="postSummary",
            body=data.get("body", ""),
        )
    elif action_type == "performReview":
        return PerformReviewAction(
            action="performReview",
            additional_instructions=data.get("additionalInstructions"),
            filter_files=data.get("filterFiles"),
            filter_rules=data.get("filterRules"),
        )
    else:
        raise ValueError(f"Unknown action type: {action_type}")


def extract_structured_output(execution_data: dict | list) -> dict:
    """Extract structured_output from Claude's execution file format."""
    if isinstance(execution_data, list):
        # Array format (verbose mode) - get last item's result
        if execution_data:
            last_item = execution_data[-1]
            if "result" in last_item and "structured_output" in last_item["result"]:
                return last_item["result"]["structured_output"]
    elif isinstance(execution_data, dict):
        # Direct object format
        if "structured_output" in execution_data:
            return execution_data["structured_output"]
        if "result" in execution_data and "structured_output" in execution_data["result"]:
            return execution_data["result"]["structured_output"]

    return {}


def run_gh_command(cmd: list[str], dry_run: bool = False) -> bool:
    """Execute a gh CLI command."""
    if dry_run:
        print(f"[DRY RUN] Would run: {' '.join(cmd)}")
        return True

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return True
    except subprocess.CalledProcessError as e:
        print(f"Failed to execute command: {e.stderr}", file=sys.stderr)
        return False


def handle_post_comment(
    action: PostCommentAction,
    repo: str,
    pr_number: int,
    dry_run: bool = False,
) -> bool:
    """Post a new comment on the PR."""
    cmd = [
        "gh", "api",
        f"repos/{repo}/issues/{pr_number}/comments",
        "-f", f"body={action.body}",
    ]

    if dry_run:
        print(f"[DRY RUN] Would post comment to PR #{pr_number}:")
        print(f"  Body: {action.body[:200]}...")
        return True

    success = run_gh_command(cmd, dry_run)
    if success:
        print(f"Posted comment to PR #{pr_number}")
    return success


def handle_reply_to_comment(
    action: ReplyToCommentAction,
    repo: str,
    pr_number: int,
    dry_run: bool = False,
) -> bool:
    """Reply to a specific existing comment."""
    # For PR review comments, use the pulls comments reply endpoint
    cmd = [
        "gh", "api",
        f"repos/{repo}/pulls/comments/{action.comment_id}/replies",
        "-f", f"body={action.body}",
    ]

    if dry_run:
        print(f"[DRY RUN] Would reply to comment {action.comment_id}:")
        print(f"  Body: {action.body[:200]}...")
        return True

    success = run_gh_command(cmd, dry_run)
    if success:
        print(f"Posted reply to comment {action.comment_id}")
    return success


def handle_replace_comment(
    action: ReplaceCommentAction,
    repo: str,
    pr_number: int,
    dry_run: bool = False,
) -> bool:
    """Edit/replace an existing comment."""
    # Use PATCH to update the comment
    cmd = [
        "gh", "api",
        f"repos/{repo}/issues/comments/{action.comment_id}",
        "-X", "PATCH",
        "-f", f"body={action.body}",
    ]

    if dry_run:
        print(f"[DRY RUN] Would replace comment {action.comment_id}:")
        print(f"  New body: {action.body[:200]}...")
        return True

    success = run_gh_command(cmd, dry_run)
    if success:
        print(f"Replaced comment {action.comment_id}")
    return success


def handle_post_summary(
    action: PostSummaryAction,
    repo: str,
    pr_number: int,
    dry_run: bool = False,
) -> bool:
    """Post a summary comment (same as postComment but semantically different)."""
    cmd = [
        "gh", "api",
        f"repos/{repo}/issues/{pr_number}/comments",
        "-f", f"body={action.body}",
    ]

    if dry_run:
        print(f"[DRY RUN] Would post summary to PR #{pr_number}:")
        print(f"  Body: {action.body[:200]}...")
        return True

    success = run_gh_command(cmd, dry_run)
    if success:
        print(f"Posted summary comment to PR #{pr_number}")
    return success


def handle_action(
    action: CommentAction,
    repo: str,
    pr_number: int,
    dry_run: bool = False,
) -> bool:
    """Route and handle the action based on its type."""
    if isinstance(action, PostCommentAction):
        return handle_post_comment(action, repo, pr_number, dry_run)
    elif isinstance(action, ReplyToCommentAction):
        return handle_reply_to_comment(action, repo, pr_number, dry_run)
    elif isinstance(action, ReplaceCommentAction):
        return handle_replace_comment(action, repo, pr_number, dry_run)
    elif isinstance(action, PostSummaryAction):
        return handle_post_summary(action, repo, pr_number, dry_run)
    elif isinstance(action, PerformReviewAction):
        # performReview is handled by the workflow, not this script
        print("performReview action should be handled by the workflow")
        print(f"  Additional instructions: {action.additional_instructions}")
        print(f"  Filter files: {action.filter_files}")
        print(f"  Filter rules: {action.filter_rules}")
        return True
    else:
        print(f"Unknown action type: {type(action)}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Handle comment actions from Claude's @code-review interpretation"
    )
    parser.add_argument(
        "--action-file",
        required=True,
        help="Path to Claude's execution output JSON file containing the action",
    )
    parser.add_argument(
        "--pr-number",
        required=True,
        type=int,
        help="PR number to operate on",
    )
    parser.add_argument(
        "--repo",
        required=True,
        help="Repository in owner/repo format",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be done without actually doing it",
    )

    args = parser.parse_args()

    # Read and parse the action file
    action_path = Path(args.action_file)
    if not action_path.exists():
        print(f"Action file not found: {action_path}", file=sys.stderr)
        sys.exit(1)

    try:
        with open(action_path) as f:
            execution_data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"Failed to parse action file: {e}", file=sys.stderr)
        sys.exit(1)

    # Extract structured output from execution data
    structured_output = extract_structured_output(execution_data)
    if not structured_output:
        print("No structured output found in action file", file=sys.stderr)
        sys.exit(1)

    # Parse the action
    try:
        action = parse_action(structured_output)
    except ValueError as e:
        print(f"Failed to parse action: {e}", file=sys.stderr)
        sys.exit(1)

    # Handle the action
    success = handle_action(action, args.repo, args.pr_number, args.dry_run)

    if not success:
        sys.exit(1)


if __name__ == "__main__":
    main()
