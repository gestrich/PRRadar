#!/usr/bin/env python3
"""
Post review comments to GitHub PRs based on Claude's structured review output.

This script reads the JSON output from Claude's code review and posts
violations (score >= 5) as PR review comments using the `gh` CLI.
"""

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Feedback:
    """A single piece of review feedback for a code segment."""
    file: str
    segment: str
    rule: str
    score: int
    line_number: int
    github_comment: str
    details: str


@dataclass
class CategorySummary:
    """Summary statistics for a review category."""
    aggregate_score: int
    summary: str


@dataclass
class ReviewSummary:
    """Overall review summary with statistics and category breakdowns."""
    summary_file: str
    total_segments: int
    total_violations: int
    categories: dict[str, CategorySummary]


@dataclass
class ReviewOutput:
    """Complete review output from Claude."""
    success: bool
    feedback: list[Feedback]
    summary: ReviewSummary


def parse_feedback(data: dict) -> Feedback:
    """Parse a feedback item from JSON."""
    return Feedback(
        file=data.get("file", ""),
        segment=data.get("segment", ""),
        rule=data.get("rule", ""),
        score=data.get("score", 0),
        line_number=data.get("lineNumber", 0),
        github_comment=data.get("githubComment", ""),
        details=data.get("details", ""),
    )


def parse_category_summary(data: dict) -> CategorySummary:
    """Parse a category summary from JSON."""
    return CategorySummary(
        aggregate_score=data.get("aggregateScore", 0),
        summary=data.get("summary", ""),
    )


def parse_review_summary(data: dict) -> ReviewSummary:
    """Parse the review summary from JSON."""
    categories = {}
    for name, cat_data in data.get("categories", {}).items():
        categories[name] = parse_category_summary(cat_data)

    return ReviewSummary(
        summary_file=data.get("summaryFile", ""),
        total_segments=data.get("totalSegments", 0),
        total_violations=data.get("totalViolations", 0),
        categories=categories,
    )


def parse_review_output(data: dict) -> ReviewOutput:
    """Parse the complete review output from JSON."""
    feedback = [parse_feedback(f) for f in data.get("feedback", [])]
    summary_data = data.get("summary", {})
    summary = parse_review_summary(summary_data)

    return ReviewOutput(
        success=data.get("success", False),
        feedback=feedback,
        summary=summary,
    )


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


def post_review_comment(
    repo: str,
    pr_number: int,
    feedback: Feedback,
    commit_sha: str | None = None,
    dry_run: bool = False,
) -> bool:
    """Post a single review comment to GitHub using gh CLI."""
    comment_body = f"**{feedback.rule}** (Score: {feedback.score})\n\n{feedback.github_comment}"

    if feedback.details and feedback.details != feedback.github_comment:
        comment_body += f"\n\n---\n*Details: {feedback.details}*"

    # Build the gh api command for posting a PR review comment
    # Uses -F for integer values and -f for strings
    cmd = [
        "gh", "api",
        f"repos/{repo}/pulls/{pr_number}/comments",
        "-f", f"body={comment_body}",
        "-f", f"path={feedback.file}",
        "-F", f"line={feedback.line_number}",  # -F for integer
        "-f", "side=RIGHT",  # Required for multi-line diff format
    ]

    # Add commit SHA if provided (required for review comments)
    if commit_sha:
        cmd.extend(["-f", f"commit_id={commit_sha}"])

    if dry_run:
        print(f"[DRY RUN] Would post comment to {feedback.file}:{feedback.line_number}")
        print(f"  Rule: {feedback.rule}")
        print(f"  Score: {feedback.score}")
        print(f"  Comment: {feedback.github_comment[:100]}...")
        return True

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        print(f"Posted comment to {feedback.file}:{feedback.line_number} ({feedback.rule})")
        return True
    except subprocess.CalledProcessError as e:
        print(f"Failed to post comment: {e.stderr}", file=sys.stderr)
        return False


def post_summary_comment(
    repo: str,
    pr_number: int,
    review: ReviewOutput,
    dry_run: bool = False,
) -> bool:
    """Post a summary comment to the PR."""
    violations = [f for f in review.feedback if f.score >= 5]

    body_lines = [
        "## Code Review Summary",
        "",
        f"**Total Segments Reviewed:** {review.summary.total_segments}",
        f"**Violations Found:** {len(violations)}",
        "",
    ]

    if review.summary.categories:
        body_lines.extend([
            "### Category Scores",
            "",
            "| Category | Score | Summary |",
            "|----------|-------|---------|",
        ])
        for cat_name, cat_summary in review.summary.categories.items():
            body_lines.append(
                f"| {cat_name} | {cat_summary.aggregate_score} | {cat_summary.summary} |"
            )
        body_lines.append("")

    if violations:
        body_lines.extend([
            "### Violations",
            "",
        ])
        for v in violations:
            body_lines.append(
                f"- **{v.file}:{v.line_number}** - {v.rule} (Score: {v.score})"
            )

    body = "\n".join(body_lines)

    cmd = [
        "gh", "api",
        f"repos/{repo}/issues/{pr_number}/comments",
        "-f", f"body={body}",
    ]

    if dry_run:
        print("[DRY RUN] Would post summary comment:")
        print(body[:500])
        return True

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        print("Posted summary comment to PR")
        return True
    except subprocess.CalledProcessError as e:
        print(f"Failed to post summary comment: {e.stderr}", file=sys.stderr)
        return False


def get_pr_head_sha(repo: str, pr_number: int) -> str | None:
    """Get the HEAD commit SHA for a PR."""
    try:
        result = subprocess.run(
            ["gh", "api", f"repos/{repo}/pulls/{pr_number}", "--jq", ".head.sha"],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return None


def main():
    parser = argparse.ArgumentParser(
        description="Post review comments to GitHub PRs based on Claude's review output"
    )
    parser.add_argument(
        "--execution-file",
        required=True,
        help="Path to Claude's execution output JSON file",
    )
    parser.add_argument(
        "--pr-number",
        required=True,
        type=int,
        help="PR number to post comments to",
    )
    parser.add_argument(
        "--repo",
        required=True,
        help="Repository in owner/repo format",
    )
    parser.add_argument(
        "--min-score",
        type=int,
        default=5,
        help="Minimum score to post a comment (default: 5)",
    )
    parser.add_argument(
        "--post-summary",
        action="store_true",
        help="Also post a summary comment to the PR",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be posted without actually posting",
    )

    args = parser.parse_args()

    # Read and parse the execution file
    execution_path = Path(args.execution_file)
    if not execution_path.exists():
        print(f"Execution file not found: {execution_path}", file=sys.stderr)
        sys.exit(1)

    try:
        with open(execution_path) as f:
            execution_data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"Failed to parse execution file: {e}", file=sys.stderr)
        sys.exit(1)

    # Extract structured output from execution data
    structured_output = extract_structured_output(execution_data)
    if not structured_output:
        print("No structured output found in execution file", file=sys.stderr)
        sys.exit(1)

    # Parse into typed models
    review = parse_review_output(structured_output)

    if not review.success:
        print("Review was not successful, skipping comment posting")
        sys.exit(0)

    # Filter to violations only
    violations = [f for f in review.feedback if f.score >= args.min_score]

    if not violations:
        print(f"No violations found with score >= {args.min_score}")
        if args.post_summary:
            post_summary_comment(args.repo, args.pr_number, review, args.dry_run)
        sys.exit(0)

    print(f"Found {len(violations)} violation(s) to post")

    # Get PR HEAD SHA for review comments
    commit_sha = get_pr_head_sha(args.repo, args.pr_number)
    if not commit_sha and not args.dry_run:
        print("Warning: Could not get PR HEAD SHA, comments may fail", file=sys.stderr)

    # Post each violation as a review comment
    success_count = 0
    for feedback in violations:
        if post_review_comment(
            args.repo,
            args.pr_number,
            feedback,
            commit_sha,
            args.dry_run,
        ):
            success_count += 1

    # Optionally post summary
    if args.post_summary:
        post_summary_comment(args.repo, args.pr_number, review, args.dry_run)

    print(f"Posted {success_count}/{len(violations)} comments")

    if success_count < len(violations):
        sys.exit(1)


if __name__ == "__main__":
    main()
