#!/usr/bin/env python3
"""CLI entry point for PRRadar GitHub Actions tools.

Usage:
    python -m scripts <command> [options]

Commands:
    post-review     Post review comments to a GitHub PR
    handle-mention  Handle @code-review mentions in PR comments
"""

import argparse
import sys

from scripts.commands.handle_mention import cmd_handle_mention
from scripts.commands.post_review import cmd_post_review


def main() -> int:
    parser = argparse.ArgumentParser(
        description="PRRadar GitHub Actions CLI tools",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Commands:
  post-review     Post review comments to a GitHub PR based on Claude's output
  handle-mention  Handle @code-review mentions in PR comments

Examples:
  python -m scripts post-review --execution-file output.json --pr-number 123 --repo owner/repo
  python -m scripts handle-mention --execution-file output.json --pr-number 123 --repo owner/repo
        """,
    )
    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    # post-review command
    parser_post_review = subparsers.add_parser(
        "post-review",
        help="Post review comments to a GitHub PR",
    )
    parser_post_review.add_argument(
        "--execution-file",
        required=True,
        help="Path to Claude's execution output JSON file",
    )
    parser_post_review.add_argument(
        "--pr-number",
        required=True,
        type=int,
        help="PR number to post comments to",
    )
    parser_post_review.add_argument(
        "--repo",
        required=True,
        help="Repository in owner/repo format",
    )
    parser_post_review.add_argument(
        "--min-score",
        type=int,
        default=5,
        help="Minimum score to post a comment (default: 5)",
    )
    parser_post_review.add_argument(
        "--post-summary",
        action="store_true",
        help="Also post a summary comment to the PR",
    )
    parser_post_review.add_argument(
        "--write-job-summary",
        action="store_true",
        help="Write review summary to GITHUB_STEP_SUMMARY",
    )
    parser_post_review.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be posted without actually posting",
    )

    # handle-mention command
    parser_handle_mention = subparsers.add_parser(
        "handle-mention",
        help="Handle @code-review mentions in PR comments",
    )
    parser_handle_mention.add_argument(
        "--execution-file",
        required=True,
        help="Path to Claude's execution output JSON file",
    )
    parser_handle_mention.add_argument(
        "--pr-number",
        required=True,
        type=int,
        help="PR number",
    )
    parser_handle_mention.add_argument(
        "--repo",
        required=True,
        help="Repository in owner/repo format",
    )
    parser_handle_mention.add_argument(
        "--comment-type",
        choices=["issue_comment", "review_comment"],
        default="issue_comment",
        help="Type of comment that triggered the mention",
    )

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 1

    # Route to command implementations with explicit parameters
    if args.command == "post-review":
        return cmd_post_review(
            execution_file=args.execution_file,
            pr_number=args.pr_number,
            repo=args.repo,
            min_score=args.min_score,
            post_summary=args.post_summary,
            write_job_summary=args.write_job_summary,
            dry_run=args.dry_run,
        )

    elif args.command == "handle-mention":
        return cmd_handle_mention(
            execution_file=args.execution_file,
            pr_number=args.pr_number,
            repo=args.repo,
            comment_type=args.comment_type,
        )

    else:
        parser.print_help()
        return 1


if __name__ == "__main__":
    sys.exit(main())
