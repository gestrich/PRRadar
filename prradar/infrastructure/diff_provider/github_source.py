"""GitHub API diff provider.

Provides diff acquisition using GitHub API via gh CLI.
This is the default and simplest path - no local repo required.
"""

from __future__ import annotations

from ..github.runner import GhCommandRunner
from .base import DiffProvider


class GitHubDiffProvider(DiffProvider):
    """Implementation for GitHub repository operations using gh CLI.

    Uses gh CLI for all GitHub API interactions:
    - Handles authentication automatically
    - Simpler than managing API tokens with requests
    - Consistent with PRRadar's existing patterns
    """

    def __init__(self, repo_owner: str, repo_name: str, gh_runner: GhCommandRunner):
        """Initialize with dependencies.

        Args:
            repo_owner: GitHub repository owner
            repo_name: GitHub repository name
            gh_runner: GitHub CLI runner for API operations (injected)
        """
        self.repo_owner = repo_owner
        self.repo_name = repo_name
        self.gh_runner = gh_runner

    def get_pr_diff(self, pr_number: int) -> str:
        """Fetch PR diff from GitHub API via gh CLI.

        Args:
            pr_number: Pull request number

        Returns:
            Raw unified diff text in git format

        Raises:
            RuntimeError: If PR diff cannot be fetched from GitHub

        Note:
            This is the default and simplest path - no local repo required.
            Uses gh CLI which handles authentication automatically.
        """
        success, result = self.gh_runner.pr_diff(pr_number)
        if not success:
            raise RuntimeError(f"Failed to fetch PR diff: {result}")
        return result

    def get_file_content(self, file_path: str, commit_hash: str) -> str:
        """Get file content at specific commit from GitHub API.

        Args:
            file_path: Path to file in repository
            commit_hash: Git commit SHA or branch name

        Returns:
            File content as string

        Raises:
            RuntimeError: If file content cannot be fetched from GitHub

        Note:
            Uses gh api to fetch raw file content.
        """
        success, result = self.gh_runner.run(
            [
                "gh",
                "api",
                f"repos/{self.repo_owner}/{self.repo_name}/contents/{file_path}",
                "-H",
                "Accept: application/vnd.github.v3.raw",
                "-f",
                f"ref={commit_hash}",
            ]
        )
        if not success:
            raise RuntimeError(f"Failed to fetch file content: {result}")
        return result
