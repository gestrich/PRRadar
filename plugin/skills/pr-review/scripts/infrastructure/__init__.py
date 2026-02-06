"""Infrastructure components for PRRadar.

This layer handles external system interactions:
- GitHub API via gh CLI
- GitHub Actions outputs
- File system operations
- Diff parsing and input
"""

from .diff_parser import (
    format_diff_as_json,
    format_diff_as_text,
    has_content,
    is_binary_file_marker,
    is_rename_operation,
    read_diff,
    read_diff_from_file,
    read_diff_from_stdin,
)
from .execution_parser import (
    extract_structured_output,
    load_execution_file,
)
from .gh_runner import GhCommandRunner
from .git_diff import GitDiff
from .git_utils import (
    GitError,
    GitFileInfo,
    get_git_file_info,
)
from .github_output import (
    write_github_output,
    write_github_step_summary,
)
from .github_repo import GithubRepo
from .hunk import Hunk
from .local_git_repo import LocalGitRepo
from .repo_source import DiffProvider

__all__ = [
    "get_git_file_info",
    "GitDiff",
    "GitError",
    "GitFileInfo",
    "GhCommandRunner",
    "GithubRepo",
    "Hunk",
    "LocalGitRepo",
    "DiffProvider",
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
