"""Git utilities for detecting repository information from file paths.

Infrastructure component that wraps git CLI commands to determine
which repository a file belongs to and construct GitHub URLs.
"""

from __future__ import annotations

import os
import re
import subprocess
from dataclasses import dataclass


@dataclass
class GitFileInfo:
    """Information about a file's location within a git repository."""

    repo_url: str  # https://github.com/owner/repo
    relative_path: str  # code-review-rules/nullability-m-objc.md
    branch: str  # main, develop, etc.

    def to_github_url(self) -> str:
        """Generate the GitHub URL to view this file."""
        return f"{self.repo_url}/blob/{self.branch}/{self.relative_path}"


class GitError(Exception):
    """Raised when a git operation fails."""

    pass


def get_git_file_info(file_path: str) -> GitFileInfo:
    """Get git repository information for a file.

    Args:
        file_path: Absolute path to a file

    Returns:
        GitFileInfo with repo URL, relative path, and branch

    Raises:
        GitError: If the file is not in a git repository or git commands fail
    """
    directory = os.path.dirname(file_path) if os.path.isfile(file_path) else file_path

    remote_url = _get_remote_url(directory)
    repo_root = _get_repo_root(directory)
    branch = _get_current_branch(directory)
    relative_path = _compute_relative_path(file_path, repo_root)
    repo_url = _convert_to_https_url(remote_url)

    return GitFileInfo(
        repo_url=repo_url,
        relative_path=relative_path,
        branch=branch,
    )


def _run_git_command(directory: str, args: list[str]) -> str:
    """Run a git command in the specified directory.

    Args:
        directory: Directory to run the command in
        args: Git command arguments (without 'git')

    Returns:
        Command output (stdout)

    Raises:
        GitError: If the command fails
    """
    cmd = ["git", "-C", directory] + args
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        raise GitError(f"Git command failed: {' '.join(cmd)}\n{e.stderr.strip()}")


def _get_remote_url(directory: str) -> str:
    """Get the origin remote URL for a repository."""
    return _run_git_command(directory, ["remote", "get-url", "origin"])


def _get_repo_root(directory: str) -> str:
    """Get the repository root directory."""
    return _run_git_command(directory, ["rev-parse", "--show-toplevel"])


def _get_current_branch(directory: str) -> str:
    """Get the current branch name."""
    return _run_git_command(directory, ["rev-parse", "--abbrev-ref", "HEAD"])


def _compute_relative_path(file_path: str, repo_root: str) -> str:
    """Compute the relative path from repo root to file."""
    abs_file = os.path.abspath(file_path)
    abs_root = os.path.abspath(repo_root)
    return os.path.relpath(abs_file, abs_root)


def _convert_to_https_url(remote_url: str) -> str:
    """Convert a git remote URL to HTTPS format.

    Handles:
    - SSH format: git@github.com:owner/repo.git
    - HTTPS format: https://github.com/owner/repo.git
    - HTTPS format without .git suffix

    Args:
        remote_url: Git remote URL in any format

    Returns:
        HTTPS URL without .git suffix (e.g., https://github.com/owner/repo)

    Raises:
        GitError: If the URL format is not recognized
    """
    url = remote_url.strip()

    # Handle SSH format: git@github.com:owner/repo.git
    ssh_match = re.match(r"git@([^:]+):(.+?)(?:\.git)?$", url)
    if ssh_match:
        host, path = ssh_match.groups()
        return f"https://{host}/{path}"

    # Handle HTTPS format
    https_match = re.match(r"https://([^/]+)/(.+?)(?:\.git)?$", url)
    if https_match:
        host, path = https_match.groups()
        return f"https://{host}/{path}"

    raise GitError(f"Unrecognized git remote URL format: {remote_url}")
