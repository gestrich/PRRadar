"""Infrastructure components for PRRadar.

This layer handles external system interactions:
- GitHub API via gh CLI
- GitHub Actions outputs
- File system operations
- Diff parsing and input
"""

from scripts.infrastructure.diff_parser import (
    format_diff_as_json,
    format_diff_as_text,
    has_content,
    is_binary_file_marker,
    is_rename_operation,
    read_diff,
    read_diff_from_file,
    read_diff_from_stdin,
)
from scripts.infrastructure.execution_parser import (
    extract_structured_output,
    load_execution_file,
)
from scripts.infrastructure.gh_runner import GhCommandRunner
from scripts.infrastructure.github_output import (
    write_github_output,
    write_github_step_summary,
)

__all__ = [
    "GhCommandRunner",
    "extract_structured_output",
    "format_diff_as_json",
    "format_diff_as_text",
    "has_content",
    "is_binary_file_marker",
    "is_rename_operation",
    "load_execution_file",
    "read_diff",
    "read_diff_from_file",
    "read_diff_from_stdin",
    "write_github_output",
    "write_github_step_summary",
]
