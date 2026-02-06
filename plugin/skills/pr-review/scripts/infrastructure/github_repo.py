"""GitHub API diff provider.

Provides diff acquisition using GitHub API via gh CLI.
This is the default and simplest path - no local repo required.
"""

import subprocess
import sys

from .repo_source import DiffProvider


class GithubRepo(DiffProvider):
    """Implementation for GitHub repository operations using gh CLI.

    Uses gh CLI for all GitHub API interactions:
    - Handles authentication automatically
    - Simpler than managing API tokens with requests
    - Consistent with PRRadar's existing patterns
    """

    def __init__(self, repo_owner: str, repo_name: str):
        """Initialize with repository details.

        Args:
            repo_owner: GitHub repository owner
            repo_name: GitHub repository name
        """
        self.repo_owner = repo_owner
        self.repo_name = repo_name

    def get_pr_diff(self, pr_number: int) -> str:
        """Fetch PR diff from GitHub API via gh CLI.

        Args:
            pr_number: Pull request number

        Returns:
            Raw unified diff text in git format

        Note:
            This is the default and simplest path - no local repo required.
            Uses gh CLI which handles authentication automatically.
        """
        try:
            result = subprocess.run(
                [
                    "gh",
                    "pr",
                    "diff",
                    str(pr_number),
                    "--repo",
                    f"{self.repo_owner}/{self.repo_name}",
                ],
                capture_output=True,
                text=True,
                check=True,
            )
            return result.stdout
        except subprocess.CalledProcessError as e:
            print(f"Error fetching PR diff from GitHub: {e.stderr}", file=sys.stderr)
            sys.exit(1)

    def get_file_content(self, file_path: str, commit_hash: str) -> str:
        """Get file content at specific commit from GitHub API.

        Args:
            file_path: Path to file in repository
            commit_hash: Git commit SHA or branch name

        Returns:
            File content as string

        Note:
            Uses gh api to fetch raw file content.
        """
        try:
            result = subprocess.run(
                [
                    "gh",
                    "api",
                    f"repos/{self.repo_owner}/{self.repo_name}/contents/{file_path}",
                    "--jq",
                    ".content",
                    "-H",
                    "Accept: application/vnd.github.v3.raw",
                    "-f",
                    f"ref={commit_hash}",
                ],
                capture_output=True,
                text=True,
                check=True,
            )
            return result.stdout
        except subprocess.CalledProcessError as e:
            print(
                f"Error fetching file content from GitHub: {e.stderr}", file=sys.stderr
            )
            return ""
