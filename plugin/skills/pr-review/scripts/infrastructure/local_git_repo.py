"""Local git repository diff provider.

Provides diff acquisition using local git operations via GitOperationsService.
Always fetches PR metadata from GitHub API, but uses local git for diff generation.
"""

import json
import subprocess
import sys

from scripts.services.git_operations import GitOperationsService

from .repo_source import DiffProvider


class LocalGitRepo(DiffProvider):
    """Implementation for local git repository operations.

    PR-centric workflow:
    1. Fetches PR metadata from GitHub API (base/head branches)
    2. Safety checks working directory is clean
    3. Fetches branches from remote
    4. Generates diff using local git
    """

    def __init__(
        self, repo_owner: str, repo_name: str, git_service: GitOperationsService
    ):
        """Initialize with dependencies.

        Args:
            repo_owner: GitHub repository owner
            repo_name: GitHub repository name
            git_service: Service for git operations (injected)
        """
        self.repo_owner = repo_owner
        self.repo_name = repo_name
        self.git_service = git_service

    def get_pr_diff(self, pr_number: int) -> str:
        """Fetch PR diff using local git operations.

        Args:
            pr_number: Pull request number

        Returns:
            Raw unified diff text

        Note:
            Always fetches PR metadata from GitHub API first,
            then uses local git for diff generation.
        """
        # Step 1: Get PR metadata from GitHub API
        pr_details = self._get_pr_metadata_from_github(pr_number)
        base_branch = pr_details["base_branch"]
        head_branch = pr_details["head_branch"]

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

    def _get_pr_metadata_from_github(self, pr_number: int) -> dict:
        """Fetch PR metadata from GitHub API using gh CLI.

        Args:
            pr_number: Pull request number

        Returns:
            Dictionary with base_branch and head_branch

        Raises:
            SystemExit: If gh CLI command fails
        """
        try:
            result = subprocess.run(
                [
                    "gh",
                    "pr",
                    "view",
                    str(pr_number),
                    "--repo",
                    f"{self.repo_owner}/{self.repo_name}",
                    "--json",
                    "baseRefName,headRefName",
                ],
                capture_output=True,
                text=True,
                check=True,
            )
            data = json.loads(result.stdout)
            return {
                "base_branch": data["baseRefName"],
                "head_branch": data["headRefName"],
            }
        except subprocess.CalledProcessError as e:
            print(f"Error fetching PR metadata from GitHub: {e.stderr}", file=sys.stderr)
            sys.exit(1)
        except (json.JSONDecodeError, KeyError) as e:
            print(f"Error parsing PR metadata: {e}", file=sys.stderr)
            sys.exit(1)
