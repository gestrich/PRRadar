from abc import ABC, abstractmethod


class DiffProvider(ABC):
    """Abstract base class for diff providers.

    Provides methods to fetch diffs from various sources (GitHub API, local git).
    All implementations must return identical diff formats for downstream compatibility.
    """

    @abstractmethod
    def get_pr_diff(self, pr_number: int) -> str:
        """Fetch unified diff for the given PR.

        Args:
            pr_number: Pull request number

        Returns:
            Raw unified diff text in git format

        Note:
            Both implementations must return identical format.
            This is the primary method for PR-centric workflow.
        """
        pass

    @abstractmethod
    def get_file_content(self, file_path: str, commit_hash: str) -> str:
        """Get full file content at specific commit.

        Args:
            file_path: Path to file in repository
            commit_hash: Git commit SHA or branch name

        Returns:
            File content as string

        Note:
            Used for focus area generation and full file context.
        """
        pass
