"""Infrastructure for reading and parsing git diffs.

Handles reading diff content from stdin or files and converting to JSON output.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from scripts.domain.diff import GitDiff


# ============================================================
# Input Functions
# ============================================================


def read_diff_from_stdin() -> str:
    """Read diff content from stdin.

    Returns:
        Raw diff content as a string
    """
    return sys.stdin.read()


def read_diff_from_file(path: str | Path) -> str:
    """Read diff content from a file.

    Args:
        path: Path to the diff file

    Returns:
        Raw diff content as a string

    Raises:
        FileNotFoundError: If the file doesn't exist
    """
    with open(path) as f:
        return f.read()


def read_diff(input_file: str | None = None) -> str:
    """Read diff content from stdin or a file.

    Args:
        input_file: Optional path to read from. If None, reads from stdin.

    Returns:
        Raw diff content as a string
    """
    if input_file is None:
        return read_diff_from_stdin()
    return read_diff_from_file(input_file)


# ============================================================
# Output Functions
# ============================================================


def format_diff_as_json(diff: GitDiff, annotate_lines: bool = False) -> str:
    """Format a GitDiff as JSON.

    Args:
        diff: Parsed GitDiff instance
        annotate_lines: If True, hunk content will have line numbers prepended

    Returns:
        JSON string representation of the diff
    """
    return json.dumps(diff.to_dict(annotate_lines=annotate_lines), indent=2)


def format_diff_as_text(diff: GitDiff) -> str:
    """Format a GitDiff as human-readable text for debugging.

    Args:
        diff: Parsed GitDiff instance

    Returns:
        Text representation showing hunks and their line numbers
    """
    if diff.is_empty:
        return "Empty diff (no hunks found)"

    lines = []
    if diff.commit_hash:
        lines.append(f"Commit: {diff.commit_hash}")

    lines.append(f"Files changed: {len(diff.get_unique_files())}")
    lines.append(f"Total hunks: {len(diff.hunks)}")
    lines.append("")

    for i, hunk in enumerate(diff.hunks, 1):
        lines.append(f"Hunk {i}: {hunk.file_path}")
        lines.append(f"  Old: lines {hunk.old_start}-{hunk.old_start + hunk.old_length - 1} ({hunk.old_length} lines)")
        lines.append(f"  New: lines {hunk.new_start}-{hunk.new_start + hunk.new_length - 1} ({hunk.new_length} lines)")
        lines.append("")

    return "\n".join(lines)


# ============================================================
# Edge Case Handling
# ============================================================


def is_binary_file_marker(line: str) -> bool:
    """Check if a line indicates a binary file.

    Args:
        line: A line from the diff

    Returns:
        True if this is a binary file marker
    """
    return line.startswith("Binary files") or "GIT binary patch" in line


def is_rename_operation(diff_content: str) -> bool:
    """Check if the diff contains a rename operation.

    Args:
        diff_content: Raw diff content

    Returns:
        True if this diff includes file renames
    """
    return "rename from " in diff_content or "rename to " in diff_content


def has_content(diff_content: str) -> bool:
    """Check if the diff has any meaningful content.

    Args:
        diff_content: Raw diff content

    Returns:
        True if the diff contains actual changes
    """
    stripped = diff_content.strip()
    if not stripped:
        return False
    return "diff --git" in stripped or stripped.startswith("@@")
