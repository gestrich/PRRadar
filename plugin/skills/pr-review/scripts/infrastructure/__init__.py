"""Infrastructure components for PRRadar.

This layer handles external system interactions:
- GitHub API via gh CLI
- GitHub Actions outputs
- File system operations
- Diff parsing and input

Organized into subdirectories:
- git/ - Git primitives (diff parsing, data structures)
- diff_provider/ - Diff acquisition providers (GitHub vs local)
- github/ - GitHub API wrapper
- claude/ - Claude-specific utilities
"""

# Git primitives
from .git import (
    GitDiff,
    GitError,
    GitFileInfo,
    Hunk,
    get_git_file_info,
)
from .git.diff_parser import (
    format_diff_as_json,
    format_diff_as_text,
    has_content,
    is_binary_file_marker,
    is_rename_operation,
    read_diff,
    read_diff_from_file,
    read_diff_from_stdin,
)

# Diff providers
from .diff_provider import (
    DiffProvider,
    create_diff_provider,
    GitHubDiffProvider,
    LocalGitDiffProvider,
)

# GitHub API
from .github import GhCommandRunner
from .github.output import (
    write_github_output,
    write_github_step_summary,
)

# Claude utilities
from .claude.execution import (
    extract_structured_output,
    load_execution_file,
)

__all__ = [
    # Diff providers
    "create_diff_provider",
    "DiffProvider",
    "GitHubDiffProvider",
    "LocalGitDiffProvider",
    # Git primitives
    "GitDiff",
    "GitError",
    "GitFileInfo",
    "Hunk",
    "get_git_file_info",
    "format_diff_as_json",
    "format_diff_as_text",
    "has_content",
    "is_binary_file_marker",
    "is_rename_operation",
    "read_diff",
    "read_diff_from_file",
    "read_diff_from_stdin",
    # GitHub API
    "GhCommandRunner",
    "write_github_output",
    "write_github_step_summary",
    # Claude utilities
    "extract_structured_output",
    "load_execution_file",
]
