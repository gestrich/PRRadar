"""Git primitives - unified diff parsing and data structures."""

from .git_diff import GitDiff
from .git_utils import GitError, GitFileInfo, get_git_file_info
from .hunk import Hunk

__all__ = [
    "GitDiff",
    "Hunk",
    "GitError",
    "GitFileInfo",
    "get_git_file_info",
]
