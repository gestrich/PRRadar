"""Local git repository diff provider.

Provides diff acquisition using local git operations via GitOperationsService.
Always fetches PR metadata from GitHub API, but uses local git for diff generation.
"""

from __future__ import annotations

from scripts.domain.github import PullRequest
from scripts.services.git_operations import GitOperationsService

from ..github.runner import GhCommandRunner
from .base import DiffProvider


class LocalGitDiffProvider(DiffProvider):
    """Implementation for local git repository operations.

    PR-centric workflow:
    1. Fetches PR metadata from GitHub API (base/head branches)
    2. Safety checks working directory is clean
    3. Fetches branches from remote
    4. Generates diff using local git
    """

    def __init__(
        self,
        repo_owner: str,
        repo_name: str,
        git_service: GitOperationsService,
        gh_runner: GhCommandRunner,
    ):
        """Initialize with dependencies.

        Args:
            repo_owner: GitHub repository owner
            repo_name: GitHub repository name
            git_service: Service for git operations (injected)
            gh_runner: GitHub CLI runner for fetching PR metadata (injected)
        """
        self.repo_owner = repo_owner
        self.repo_name = repo_name
        self.git_service = git_service
        self.gh_runner = gh_runner

    def get_pr_diff(self, pr_number: int) -> str:
        """Fetch PR diff using local git operations.

        Args:
            pr_number: Pull request number

        Returns:
            Raw unified diff text

        Raises:
            RuntimeError: If PR metadata cannot be fetched from GitHub

        Note:
            Always fetches PR metadata from GitHub API first,
            then uses local git for diff generation.
        """
        # Step 1: Get PR metadata from GitHub API
        success, pr_result = self.gh_runner.get_pull_request(pr_number)
        if not success:
            raise RuntimeError(f"Failed to fetch PR metadata: {pr_result}")
        assert isinstance(pr_result, PullRequest)

        base_branch = pr_result.base_ref_name
        head_branch = pr_result.head_ref_name

        # Step 2: Safety check via GitOperationsService
        self.git_service.check_working_directory_clean()

        # Step 3: Fetch branches via GitOperationsService
        self.git_service.fetch_branch(base_branch)
        self.git_service.fetch_branch(head_branch)

        # Step 4: Get diff via GitOperationsService
        return self.git_service.get_branch_diff(base_branch, head_branch)

    def get_file_content(self, file_path: str, commit_hash: str) -> str:
        """Get file content at specific commit using local git.

        Args:
            file_path: Path to file in repository
            commit_hash: Git commit SHA or branch name

        Returns:
            File content as string
        """
        return self.git_service.get_file_content(file_path, commit_hash)
