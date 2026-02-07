"""Git operations service.

Core service for git command operations. Encapsulates all subprocess calls
to git commands and returns domain models where relevant.
"""

import subprocess
from pathlib import Path


class GitDirtyWorkingDirectoryError(Exception):
    """Raised when git working directory has uncommitted changes."""

    pass


class GitFetchError(Exception):
    """Raised when git fetch fails."""

    pass


class GitDiffError(Exception):
    """Raised when git diff command fails."""

    pass


class GitFileNotFoundError(Exception):
    """Raised when file doesn't exist at specified commit."""

    pass


class GitCheckoutError(Exception):
    """Raised when git checkout fails."""

    pass


class GitRepositoryError(Exception):
    """Raised when directory is not a git repository."""

    pass


class GitOperationsService:
    """Core service for git command operations.

    Encapsulates all subprocess calls to git commands.
    Returns domain models where relevant.
    Reusable across the entire application.
    """

    def __init__(self, repo_path: str = "."):
        """Initialize with repository path.

        Args:
            repo_path: Path to git repository (default: current directory)
        """
        self.repo_path = Path(repo_path)

    def check_working_directory_clean(self) -> bool:
        """Check if working directory has uncommitted changes.

        Returns:
            True if clean

        Raises:
            GitDirtyWorkingDirectoryError: If uncommitted changes detected
            GitRepositoryError: If not in a git repository
        """
        if not self.is_git_repository():
            raise GitRepositoryError(
                f"Not a git repository: {self.repo_path}\n"
                "Make sure you're running from within a git repository."
            )

        result = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=self.repo_path,
            capture_output=True,
            text=True,
            check=True,
        )

        if result.stdout.strip():
            raise GitDirtyWorkingDirectoryError(
                "Cannot proceed - uncommitted changes detected. "
                "Commit or stash your changes:\n"
                "  git stash\n"
                "  git commit -am 'WIP'\n"
                "Then try again."
            )

        return True

    def fetch_branch(self, branch_name: str, remote: str = "origin") -> None:
        """Fetch branch from remote.

        Args:
            branch_name: Branch to fetch
            remote: Remote name (default: origin)

        Raises:
            GitFetchError: If fetch fails
            GitRepositoryError: If not in a git repository
        """
        if not self.is_git_repository():
            raise GitRepositoryError(
                f"Not a git repository: {self.repo_path}\n"
                "Make sure you're running from within a git repository."
            )

        try:
            subprocess.run(
                ["git", "fetch", remote, branch_name],
                cwd=self.repo_path,
                capture_output=True,
                text=True,
                check=True,
            )
        except subprocess.CalledProcessError as e:
            raise GitFetchError(
                f"Failed to fetch {remote}/{branch_name}: {e.stderr}"
            )

    def checkout_commit(self, sha: str) -> None:
        """Checkout a specific commit (detached HEAD).

        Args:
            sha: Commit SHA to checkout

        Raises:
            GitCheckoutError: If checkout fails
            GitRepositoryError: If not in a git repository
        """
        if not self.is_git_repository():
            raise GitRepositoryError(
                f"Not a git repository: {self.repo_path}\n"
                "Make sure you're running from within a git repository."
            )

        try:
            subprocess.run(
                ["git", "checkout", sha],
                cwd=self.repo_path,
                capture_output=True,
                text=True,
                check=True,
            )
        except subprocess.CalledProcessError as e:
            raise GitCheckoutError(
                f"Failed to checkout {sha}: {e.stderr}"
            )

    def get_branch_diff(
        self, base_branch: str, head_branch: str, remote: str = "origin"
    ) -> str:
        """Get diff between two branches.

        Args:
            base_branch: Base branch name
            head_branch: Head branch name
            remote: Remote name (default: origin)

        Returns:
            Raw unified diff text

        Raises:
            GitDiffError: If diff command fails
            GitRepositoryError: If not in a git repository
        """
        if not self.is_git_repository():
            raise GitRepositoryError(
                f"Not a git repository: {self.repo_path}\n"
                "Make sure you're running from within a git repository."
            )

        try:
            result = subprocess.run(
                ["git", "diff", f"{remote}/{base_branch}...{remote}/{head_branch}"],
                cwd=self.repo_path,
                capture_output=True,
                text=True,
                check=True,
            )
            return result.stdout
        except subprocess.CalledProcessError as e:
            raise GitDiffError(f"Failed to compute diff: {e.stderr}")

    def is_git_repository(self) -> bool:
        """Check if current directory is a git repository.

        Returns:
            True if valid git repo, False otherwise
        """
        try:
            subprocess.run(
                ["git", "rev-parse", "--git-dir"],
                cwd=self.repo_path,
                capture_output=True,
                check=True,
            )
            return True
        except subprocess.CalledProcessError:
            return False

    def get_file_content(self, file_path: str, commit_hash: str) -> str:
        """Get file content at specific commit.

        Args:
            file_path: Path to file in repository
            commit_hash: Git commit SHA or branch name

        Returns:
            File content as string

        Raises:
            GitFileNotFoundError: If file doesn't exist at commit
            GitRepositoryError: If not in a git repository
        """
        if not self.is_git_repository():
            raise GitRepositoryError(
                f"Not a git repository: {self.repo_path}\n"
                "Make sure you're running from within a git repository."
            )

        try:
            result = subprocess.run(
                ["git", "show", f"{commit_hash}:{file_path}"],
                cwd=self.repo_path,
                capture_output=True,
                text=True,
                check=True,
            )
            return result.stdout
        except subprocess.CalledProcessError as e:
            raise GitFileNotFoundError(
                f"File {file_path} not found at {commit_hash}: {e.stderr}"
            )
