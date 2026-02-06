from abc import ABC, abstractmethod

from .git_diff import GitDiff


class GitRepoSource(ABC):
    """Abstract base class for git repository sources."""

    @abstractmethod
    def get_commit_diff(self, commit_hash: str) -> GitDiff:
        """Get the diff for a specific commit."""
        pass

    @abstractmethod
    def get_file_content(self, file_path: str, commit_hash: str) -> str:
        """Get the content of a file at a specific commit."""
        pass
