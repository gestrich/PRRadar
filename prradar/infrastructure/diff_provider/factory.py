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
    local_repo_path: str | None = None,
) -> DiffProvider:
    """Create a diff provider based on source type.

    Args:
        source: GITHUB_API or LOCAL_GIT
        repo_owner: GitHub repo owner (needed for both sources)
        repo_name: GitHub repo name (needed for both sources)
        local_repo_path: Path to local git repo (required for LOCAL_GIT)

    Returns:
        DiffProvider implementation appropriate for the source type

    Raises:
        ValueError: If source is LOCAL_GIT but local_repo_path is None

    Note:
        Both providers use GitHub API for PR metadata.
        LOCAL_GIT only uses local git for diff acquisition.

    Examples:
        >>> # Create GitHub API provider (default, simplest)
        >>> provider = create_diff_provider(
        ...     DiffSource.GITHUB_API,
        ...     "myorg",
        ...     "myrepo"
        ... )

        >>> # Create local git provider
        >>> provider = create_diff_provider(
        ...     DiffSource.LOCAL_GIT,
        ...     "myorg",
        ...     "myrepo",
        ...     local_repo_path="/path/to/repo"
        ... )
    """
    if source == DiffSource.GITHUB_API:
        gh_runner = GhCommandRunner()
        return GitHubDiffProvider(repo_owner, repo_name, gh_runner)
    elif source == DiffSource.LOCAL_GIT:
        if local_repo_path is None:
            raise ValueError("local_repo_path is required for LOCAL_GIT source")
        git_service = GitOperationsService(local_repo_path)
        gh_runner = GhCommandRunner()
        return LocalGitDiffProvider(repo_owner, repo_name, git_service, gh_runner)
    else:
        raise ValueError(f"Unknown diff source: {source}")
