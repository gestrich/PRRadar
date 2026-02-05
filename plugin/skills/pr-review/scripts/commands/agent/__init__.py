"""Agent mode commands for PRRadar.

This module provides the CLI infrastructure for agent mode, which uses
the Claude Agent SDK with structured outputs for deterministic, pipeline-based
code review.

Commands:
    diff      - Fetch and store PR diff artifacts
    rules     - Collect and filter applicable rules
    evaluate  - Run rule evaluations using agent subprocesses
    report    - Generate review report from evaluations
    comment   - Post review comments to GitHub
    analyze   - Run the full pipeline
"""

import argparse
import os
from pathlib import Path


def setup_agent_parser(subparsers: argparse._SubParsersAction) -> None:
    """Set up the agent subcommand group with nested commands."""
    agent_parser = subparsers.add_parser(
        "agent",
        help="Agent mode commands (Claude Agent SDK)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description="""
Agent mode provides a pipeline-based code review system using the
Claude Agent SDK with structured outputs for consistent, debuggable results.

Each phase produces artifacts in the output directory that can be
inspected and debugged independently.
        """,
    )

    agent_parser.add_argument(
        "--output-dir",
        type=str,
        default="code-reviews",
        help="Directory for storing artifacts (default: code-reviews/)",
    )

    agent_subparsers = agent_parser.add_subparsers(
        dest="agent_command",
        help="Agent command to run",
    )

    # diff command
    diff_parser = agent_subparsers.add_parser(
        "diff",
        help="Fetch and store PR diff",
    )
    diff_parser.add_argument(
        "pr_number",
        type=int,
        help="PR number to fetch diff for",
    )

    # rules command
    rules_parser = agent_subparsers.add_parser(
        "rules",
        help="Collect and filter applicable rules",
    )
    rules_parser.add_argument(
        "pr_number",
        type=int,
        help="PR number to analyze rules for",
    )
    rules_parser.add_argument(
        "--rules-dir",
        type=str,
        default="code-review-rules",
        help="Directory containing review rules (default: code-review-rules/)",
    )

    # evaluate command
    evaluate_parser = agent_subparsers.add_parser(
        "evaluate",
        help="Run rule evaluations",
    )
    evaluate_parser.add_argument(
        "pr_number",
        type=int,
        help="PR number to evaluate",
    )
    evaluate_parser.add_argument(
        "--rules",
        nargs="+",
        help="Only evaluate specific rules (by name)",
    )

    # report command
    report_parser = agent_subparsers.add_parser(
        "report",
        help="Generate review report",
    )
    report_parser.add_argument(
        "pr_number",
        type=int,
        help="PR number to generate report for",
    )
    report_parser.add_argument(
        "--min-score",
        type=int,
        default=5,
        help="Minimum score threshold for violations (default: 5)",
    )

    # comment command
    comment_parser = agent_subparsers.add_parser(
        "comment",
        help="Post review comments to GitHub",
    )
    comment_parser.add_argument(
        "pr_number",
        type=int,
        help="PR number to post comments to",
    )
    comment_parser.add_argument(
        "--repo",
        type=str,
        help="Repository in owner/repo format (auto-detected if not provided)",
    )
    comment_parser.add_argument(
        "--min-score",
        type=int,
        default=5,
        help="Minimum score threshold for posting (default: 5)",
    )
    comment_parser.add_argument(
        "-n",
        "--no-interactive",
        action="store_true",
        help="Post all comments without prompting (default: interactive)",
    )
    comment_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview comments without posting (requires --no-interactive)",
    )

    # analyze command (full pipeline)
    analyze_parser = agent_subparsers.add_parser(
        "analyze",
        help="Run full review pipeline",
    )
    analyze_parser.add_argument(
        "pr_number",
        type=int,
        help="PR number to analyze",
    )
    analyze_parser.add_argument(
        "--rules-dir",
        type=str,
        default="code-review-rules",
        help="Directory containing review rules (default: code-review-rules/)",
    )
    analyze_parser.add_argument(
        "--stop-after",
        choices=["diff", "rules", "evaluate"],
        help="Stop after specified phase",
    )
    analyze_parser.add_argument(
        "--skip-to",
        choices=["rules", "evaluate"],
        help="Skip to specified phase (uses existing artifacts)",
    )
    analyze_parser.add_argument(
        "-n",
        "--no-interactive",
        action="store_true",
        help="Run all evaluations without prompting (default: interactive)",
    )
    analyze_parser.add_argument(
        "--no-dry-run",
        action="store_true",
        help="Actually post comments to GitHub (default: dry-run)",
    )
    analyze_parser.add_argument(
        "--min-score",
        type=int,
        default=5,
        help="Minimum score threshold for posting comments (default: 5)",
    )
    analyze_parser.add_argument(
        "--repo",
        type=str,
        help="Repository in owner/repo format (auto-detected if not provided)",
    )


def ensure_output_dir(output_dir: str, pr_number: int) -> Path:
    """Create and return the output directory for a PR.

    Args:
        output_dir: Base output directory
        pr_number: PR number

    Returns:
        Path to the PR-specific output directory
    """
    pr_dir = Path(output_dir) / str(pr_number)
    pr_dir.mkdir(parents=True, exist_ok=True)
    return pr_dir


def cmd_agent(args: argparse.Namespace) -> int:
    """Handle agent subcommands.

    Args:
        args: Parsed command line arguments

    Returns:
        Exit code (0 for success, non-zero for error)
    """
    if not args.agent_command:
        print("Error: No agent command specified")
        print("Use 'python -m scripts agent --help' for usage information")
        return 1

    output_dir = args.output_dir
    pr_number = args.pr_number

    # Ensure output directory exists
    pr_dir = ensure_output_dir(output_dir, pr_number)
    print(f"Output directory: {pr_dir}")

    if args.agent_command == "diff":
        from scripts.commands.agent.diff import cmd_diff

        return cmd_diff(pr_number=pr_number, output_dir=pr_dir)

    elif args.agent_command == "rules":
        from scripts.commands.agent.rules import cmd_rules

        return cmd_rules(
            pr_number=pr_number,
            output_dir=pr_dir,
            rules_dir=args.rules_dir,
        )

    elif args.agent_command == "evaluate":
        from scripts.commands.agent.evaluate import cmd_evaluate

        return cmd_evaluate(
            pr_number=pr_number,
            output_dir=pr_dir,
            rules_filter=args.rules,
        )

    elif args.agent_command == "report":
        from scripts.commands.agent.report import cmd_report

        return cmd_report(
            pr_number=pr_number,
            output_dir=pr_dir,
            min_score=args.min_score,
        )

    elif args.agent_command == "comment":
        from scripts.commands.agent.comment import cmd_comment

        # Validate: dry-run requires non-interactive mode
        interactive = not args.no_interactive
        if args.dry_run and interactive:
            print("  Error: --dry-run requires --no-interactive (-n)")
            return 1

        # Get repo from args or auto-detect
        repo = args.repo
        if not repo:
            from scripts.infrastructure.gh_runner import GhCommandRunner

            gh = GhCommandRunner()
            success, result = gh.get_repository()
            if success:
                repo = f"{result.owner}/{result.name}"
            else:
                print("  Error: Could not detect repository. Use --repo to specify.")
                return 1

        return cmd_comment(
            pr_number=pr_number,
            output_dir=pr_dir,
            repo=repo,
            min_score=args.min_score,
            dry_run=args.dry_run,
            interactive=interactive,
        )

    elif args.agent_command == "analyze":
        from scripts.commands.agent.analyze import cmd_analyze

        # Get repo from args or auto-detect
        repo = args.repo
        if not repo:
            from scripts.infrastructure.gh_runner import GhCommandRunner

            gh = GhCommandRunner()
            success, result = gh.get_repository()
            if success:
                repo = f"{result.owner}/{result.name}"
            else:
                print("  Error: Could not detect repository. Use --repo to specify.")
                return 1

        return cmd_analyze(
            pr_number=pr_number,
            output_dir=pr_dir,
            rules_dir=args.rules_dir,
            repo=repo,
            interactive=not args.no_interactive,
            dry_run=not args.no_dry_run,
            stop_after=args.stop_after,
            skip_to=args.skip_to,
            min_score=args.min_score,
        )

    else:
        print(f"Error: Unknown agent command '{args.agent_command}'")
        return 1
