"""GitHub CLI command runner.

Infrastructure component that wraps subprocess calls to the gh CLI.
This abstraction allows services to be tested without actually calling gh.
"""

from __future__ import annotations

import json
import subprocess
import sys
from dataclasses import dataclass
from typing import Protocol

from prradar.domain.github import PullRequest, PullRequestComments, Repository

# Fields fetched for PR metadata (single PR view)
_PR_FIELDS = [
    "number",
    "title",
    "body",
    "author",
    "baseRefName",
    "headRefName",
    "headRefOid",
    "state",
    "isDraft",
    "url",
    "createdAt",
    "updatedAt",
    "additions",
    "deletions",
    "changedFiles",
    "commits",
    "labels",
    "files",
]

# Lightweight fields for listing multiple PRs (excludes nested connections
# like "files" and "commits" that cause GraphQL node limit errors on large repos)
_PR_LIST_FIELDS = [
    "number",
    "title",
    "body",
    "author",
    "baseRefName",
    "headRefName",
    "headRefOid",
    "state",
    "isDraft",
    "url",
    "createdAt",
    "updatedAt",
    "additions",
    "deletions",
    "changedFiles",
    "labels",
]

# Fields fetched for PR comments
_PR_COMMENT_FIELDS = ["comments", "reviews"]

# Fields fetched for repository metadata
_REPO_FIELDS = ["name", "owner", "url", "defaultBranchRef"]


class CommandRunner(Protocol):
    """Protocol for running shell commands."""

    def run(self, cmd: list[str]) -> tuple[bool, str]:
        """Run a command and return (success, output/error)."""
        ...


@dataclass
class GhCommandRunner:
    """Runs gh CLI commands via subprocess.

    This is the production implementation of CommandRunner.
    For testing, mock this class or use a fake implementation.
    """

    dry_run: bool = False

    # --------------------------------------------------------
    # Public API
    # --------------------------------------------------------

    def run(self, cmd: list[str]) -> tuple[bool, str]:
        """Run a gh CLI command.

        Args:
            cmd: Command and arguments (e.g., ["gh", "api", "..."])

        Returns:
            Tuple of (success, output_or_error)
        """
        if self.dry_run:
            return True, f"[DRY RUN] Would run: {' '.join(cmd)}"

        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            return True, result.stdout
        except subprocess.CalledProcessError as e:
            print(f"Command failed: {e.stderr}", file=sys.stderr)
            return False, e.stderr

    def api_get(self, endpoint: str, jq_filter: str | None = None) -> tuple[bool, str]:
        """Make a GET request to the GitHub API.

        Args:
            endpoint: API endpoint (e.g., "repos/owner/repo/pulls/123")
            jq_filter: Optional jq filter for the response

        Returns:
            Tuple of (success, response_or_error)
        """
        cmd = ["gh", "api", endpoint]
        if jq_filter:
            cmd.extend(["--jq", jq_filter])
        return self.run(cmd)

    def api_post(self, endpoint: str, fields: dict[str, str]) -> tuple[bool, str]:
        """Make a POST request to the GitHub API.

        Args:
            endpoint: API endpoint
            fields: String fields to include in the request body

        Returns:
            Tuple of (success, response_or_error)
        """
        cmd = ["gh", "api", endpoint]
        for key, value in fields.items():
            cmd.extend(["-f", f"{key}={value}"])
        return self.run(cmd)

    def api_post_with_int(
        self,
        endpoint: str,
        string_fields: dict[str, str],
        int_fields: dict[str, int],
    ) -> tuple[bool, str]:
        """Make a POST request with both string and integer fields.

        Args:
            endpoint: API endpoint
            string_fields: String fields (-f flag)
            int_fields: Integer fields (-F flag)

        Returns:
            Tuple of (success, response_or_error)
        """
        cmd = ["gh", "api", endpoint]
        for key, value in string_fields.items():
            cmd.extend(["-f", f"{key}={value}"])
        for key, value in int_fields.items():
            cmd.extend(["-F", f"{key}={value}"])
        return self.run(cmd)

    def api_patch(self, endpoint: str, fields: dict[str, str]) -> tuple[bool, str]:
        """Make a PATCH request to the GitHub API.

        Args:
            endpoint: API endpoint
            fields: Fields to include in the request body

        Returns:
            Tuple of (success, response_or_error)
        """
        cmd = ["gh", "api", endpoint, "-X", "PATCH"]
        for key, value in fields.items():
            cmd.extend(["-f", f"{key}={value}"])
        return self.run(cmd)

    def pr_diff(self, pr_number: int) -> tuple[bool, str]:
        """Get the diff for a pull request.

        Args:
            pr_number: PR number

        Returns:
            Tuple of (success, diff_content_or_error)
        """
        return self.run(["gh", "pr", "diff", str(pr_number)])

    def get_pull_request(self, pr_number: int) -> tuple[bool, PullRequest | str]:
        """Get PR metadata as a typed model.

        Args:
            pr_number: PR number

        Returns:
            Tuple of (success, PullRequest or error string)
        """
        success, result = self.run(
            ["gh", "pr", "view", str(pr_number), "--json", ",".join(_PR_FIELDS)]
        )
        if not success:
            return False, result
        return True, PullRequest.from_json(result)

    def get_pull_request_comments(self, pr_number: int) -> tuple[bool, PullRequestComments | str]:
        """Get PR comments and reviews as a typed model.

        Args:
            pr_number: PR number

        Returns:
            Tuple of (success, PullRequestComments or error string)
        """
        success, result = self.run(
            ["gh", "pr", "view", str(pr_number), "--json", ",".join(_PR_COMMENT_FIELDS)]
        )
        if not success:
            return False, result
        return True, PullRequestComments.from_json(result)

    def list_pull_requests(
        self,
        limit: int,
        state: str,
        repo: str | None = None,
        search: str | None = None,
    ) -> tuple[bool, list[PullRequest] | str]:
        """List recent pull requests for a repository.

        Args:
            limit: Maximum number of PRs to fetch
            state: PR state filter (open, closed, merged, all)
            repo: Repository in owner/name format (uses git remote if None)
            search: Raw GitHub search query string (e.g., "created:>=2025-01-15")

        Returns:
            Tuple of (success, list of PullRequest or error string)
        """
        cmd = [
            "gh", "pr", "list",
            "--json", ",".join(_PR_LIST_FIELDS),
            "--limit", str(limit),
            "--state", state,
        ]
        if repo:
            cmd.extend(["-R", repo])
        if search:
            cmd.extend(["--search", search])
        success, result = self.run(cmd)
        if not success:
            return False, result
        data = json.loads(result)
        return True, [PullRequest.from_dict(item) for item in data]

    def get_repository(self, repo: str | None = None) -> tuple[bool, Repository | str]:
        """Get repository metadata as a typed model.

        Args:
            repo: Repository in owner/name format (uses git remote if None)

        Returns:
            Tuple of (success, Repository or error string)
        """
        cmd = ["gh", "repo", "view", "--json", ",".join(_REPO_FIELDS)]
        if repo:
            cmd.insert(3, repo)
        success, result = self.run(cmd)
        if not success:
            return False, result
        return True, Repository.from_json(result)
