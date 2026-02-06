"""Parse diff command.

Thin command that orchestrates diff parsing infrastructure.
Reads raw diff from stdin or file and outputs structured JSON with hunk line numbers.
"""

from __future__ import annotations

import sys

from scripts.domain.diff import GitDiff
from scripts.infrastructure.git.diff_parser import (
    format_diff_as_json,
    format_diff_as_text,
    read_diff,
)


def cmd_parse_diff(
    input_file: str | None = None,
    output_format: str = "json",
    annotate_lines: bool = False,
) -> int:
    """Parse a git diff and output structured hunk information.

    Thin command that:
    1. Reads diff from stdin or file
    2. Parses into domain model with deterministic hunk parsing
    3. Outputs JSON or text format with new_start line numbers

    Args:
        input_file: Optional path to read diff from. If None, reads from stdin.
        output_format: Output format - 'json' (default) or 'text' for debugging
        annotate_lines: If True, prepend target file line numbers to each diff line

    Returns:
        Exit code (0 for success, 1 for failure)
    """
    # --------------------------------------------------------
    # 1. Read diff input
    # --------------------------------------------------------
    try:
        diff_content = read_diff(input_file)
    except FileNotFoundError:
        print(f"Input file not found: {input_file}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Failed to read diff: {e}", file=sys.stderr)
        return 1

    # --------------------------------------------------------
    # 2. Parse into domain model
    # --------------------------------------------------------
    diff = GitDiff.from_diff_content(diff_content)

    # --------------------------------------------------------
    # 3. Output in requested format
    # --------------------------------------------------------
    if output_format == "text":
        print(format_diff_as_text(diff))
    else:
        print(format_diff_as_json(diff, annotate_lines=annotate_lines))

    return 0
