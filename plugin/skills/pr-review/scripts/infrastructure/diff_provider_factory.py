"""Factory for creating diff providers.

This module provides factory functions for creating appropriate diff providers
based on the source type (GitHub API or local git).
"""

from scripts.domain.diff_source import DiffSource
from scripts.services.git_operations import GitOperationsService

from .github_repo import GithubRepo
from .local_git_repo import LocalGitRepo
from .repo_source import DiffProvider


def create_diff_provider(
    source: DiffSource, repo_owner: str, repo_name: str, **kwargs
) -> DiffProvider:
    """Create a diff provider based on source type.

    Args:
        source: GITHUB_API or LOCAL_GIT
        repo_owner: GitHub repo owner (needed for both sources)
        repo_name: GitHub repo name (needed for both sources)
        **kwargs: Additional args (e.g., local_repo_path for LOCAL_GIT)

    Returns:
        DiffProvider implementation appropriate for the source type

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
        return GithubRepo(repo_owner, repo_name)
    elif source == DiffSource.LOCAL_GIT:
        local_path = kwargs.get("local_repo_path", ".")
        git_service = GitOperationsService(local_path)
        return LocalGitRepo(repo_owner, repo_name, git_service)
    else:
        raise ValueError(f"Unknown diff source: {source}")
