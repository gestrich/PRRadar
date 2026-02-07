"""Factory for creating diff providers.

This module provides factory functions for creating appropriate diff providers
based on the source type (GitHub API or local git).
"""

from __future__ import annotations

from prradar.domain.diff_source import DiffSource
from prradar.services.git_operations import GitOperationsService

from ..github.runner import GhCommandRunner
from .base import DiffProvider
from .github_source import GitHubDiffProvider
from .local_source import LocalGitDiffProvider


def create_diff_provider(
    source: DiffSource,
    repo_owner: str,
    repo_name: str,
    local_repo_path: str,
) -> DiffProvider:
    """Create a diff provider based on source type.

    Args:
        source: GITHUB or LOCAL
        repo_owner: GitHub repo owner (needed for both sources)
        repo_name: GitHub repo name (needed for both sources)
        local_repo_path: Path to local git repo (required for both sources)

    Returns:
        DiffProvider implementation appropriate for the source type
    """
    git_service = GitOperationsService(local_repo_path)
    gh_runner = GhCommandRunner()

    if source == DiffSource.GITHUB:
        return GitHubDiffProvider(repo_owner, repo_name, git_service, gh_runner)
    elif source == DiffSource.LOCAL:
        return LocalGitDiffProvider(repo_owner, repo_name, git_service, gh_runner)
    else:
        raise ValueError(f"Unknown diff source: {source}")
