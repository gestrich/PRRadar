"""GitHub API diff provider.

Provides diff acquisition using GitHub API via gh CLI.
Both providers checkout the PR branch locally; this one uses GitHub API for the diff text.
"""

from __future__ import annotations

from prradar.domain.github import PullRequest
from prradar.services.git_operations import GitOperationsService

from ..github.runner import GhCommandRunner
from .base import DiffProvider


class GitHubDiffProvider(DiffProvider):
    """Implementation for GitHub repository operations using gh CLI.

    PR-centric workflow:
    1. Fetches PR metadata from GitHub API (base/head branches + head SHA)
    2. Safety checks working directory is clean
    3. Fetches branches from remote
    4. Checks out PR's head commit (detached HEAD)
    5. Returns diff from gh pr diff (GitHub API)
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
            gh_runner: GitHub CLI runner for API operations (injected)
        """
        self.repo_owner = repo_owner
        self.repo_name = repo_name
        self.git_service = git_service
        self.gh_runner = gh_runner

    def get_pr_diff(self, pr_number: int) -> str:
        """Fetch PR diff from GitHub API via gh CLI, after checking out the branch.

        Args:
            pr_number: Pull request number

        Returns:
            Raw unified diff text in git format

        Raises:
            RuntimeError: If PR diff cannot be fetched from GitHub
        """
        # Step 1: Get PR metadata from GitHub API
        success, pr_result = self.gh_runner.get_pull_request(pr_number)
        if not success:
            raise RuntimeError(f"Failed to fetch PR metadata: {pr_result}")
        assert isinstance(pr_result, PullRequest)

        base_branch = pr_result.base_ref_name
        head_branch = pr_result.head_ref_name
        head_sha = pr_result.head_ref_oid

        # Step 2: Safety check via GitOperationsService
        self.git_service.check_working_directory_clean()

        # Step 3: Fetch branches via GitOperationsService
        self.git_service.fetch_branch(base_branch)
        self.git_service.fetch_branch(head_branch)

        # Step 4: Checkout PR's head commit (detached HEAD)
        self.git_service.checkout_commit(head_sha)
        self.git_service.clean()

        # Step 5: Return diff from gh pr diff (existing behavior)
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
