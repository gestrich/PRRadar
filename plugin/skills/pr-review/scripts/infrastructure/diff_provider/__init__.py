"""Diff acquisition providers - GitHub API and local git sources."""

from .base import DiffProvider
from .factory import create_diff_provider
from .github_source import GitHubDiffProvider
from .local_source import LocalGitDiffProvider

__all__ = [
    "DiffProvider",
    "create_diff_provider",
    "GitHubDiffProvider",
    "LocalGitDiffProvider",
]
