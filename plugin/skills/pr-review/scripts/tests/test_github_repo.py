"""Tests for GitHubDiffProvider diff provider.

Tests cover:
- PR diff retrieval via GhCommandRunner
- File content retrieval via GhCommandRunner
- Source type identification
- Error handling for network failures and invalid PRs
"""

import unittest
from unittest.mock import MagicMock

from scripts.infrastructure.github.runner import GhCommandRunner
from scripts.infrastructure.diff_provider.github_source import GitHubDiffProvider


class TestGitHubDiffProvider(unittest.TestCase):
    """Tests for GitHubDiffProvider provider with mocked GhCommandRunner."""

    def setUp(self):
        """Set up test fixtures."""
        self.mock_gh_runner = MagicMock(spec=GhCommandRunner)
        self.provider = GitHubDiffProvider(
            repo_owner="testowner", repo_name="testrepo", gh_runner=self.mock_gh_runner
        )

    def test_initialization_stores_owner_and_name(self):
        """Test that provider stores owner and repo name."""
        self.assertEqual(self.provider.repo_owner, "testowner")
        self.assertEqual(self.provider.repo_name, "testrepo")

    def test_initialization_stores_gh_runner(self):
        """Test that provider stores injected gh runner."""
        self.assertEqual(self.provider.gh_runner, self.mock_gh_runner)

    def test_provider_is_instance_of_diff_provider(self):
        """Test that GitHubDiffProvider implements DiffProvider interface."""
        from scripts.infrastructure.diff_provider.base import DiffProvider

        self.assertIsInstance(self.provider, DiffProvider)

    def test_get_pr_diff_calls_gh_runner_pr_diff(self):
        """Test that get_pr_diff calls gh_runner.pr_diff with correct PR number."""
        expected_diff = "diff --git a/file.py b/file.py\n+new line\n"
        self.mock_gh_runner.pr_diff.return_value = (True, expected_diff)

        result = self.provider.get_pr_diff(123)

        self.assertEqual(result, expected_diff)
        self.mock_gh_runner.pr_diff.assert_called_once_with(123)

    def test_get_pr_diff_handles_different_pr_numbers(self):
        """Test that get_pr_diff works with different PR numbers."""
        self.mock_gh_runner.pr_diff.return_value = (True, "diff content")

        self.provider.get_pr_diff(456)

        self.mock_gh_runner.pr_diff.assert_called_once_with(456)

    def test_get_pr_diff_raises_on_network_failure(self):
        """Test that get_pr_diff raises RuntimeError on network failure."""
        self.mock_gh_runner.pr_diff.return_value = (
            False,
            "HTTP 500: Internal Server Error",
        )

        with self.assertRaises(RuntimeError) as ctx:
            self.provider.get_pr_diff(123)

        self.assertIn("Failed to fetch PR diff", str(ctx.exception))

    def test_get_pr_diff_raises_on_invalid_pr(self):
        """Test that get_pr_diff raises RuntimeError for non-existent PR."""
        self.mock_gh_runner.pr_diff.return_value = (False, "pull request not found")

        with self.assertRaises(RuntimeError) as ctx:
            self.provider.get_pr_diff(99999)

        self.assertIn("Failed to fetch PR diff", str(ctx.exception))

    def test_get_file_content_calls_gh_runner_run(self):
        """Test that get_file_content calls gh_runner.run with correct arguments."""
        expected_content = "def main():\n    pass\n"
        self.mock_gh_runner.run.return_value = (True, expected_content)

        result = self.provider.get_file_content("src/main.py", "abc123")

        self.assertEqual(result, expected_content)
        self.mock_gh_runner.run.assert_called_once_with(
            [
                "gh",
                "api",
                "repos/testowner/testrepo/contents/src/main.py",
                "-H",
                "Accept: application/vnd.github.v3.raw",
                "-f",
                "ref=abc123",
            ]
        )

    def test_get_file_content_handles_different_files(self):
        """Test that get_file_content works with different file paths."""
        self.mock_gh_runner.run.return_value = (True, "content")

        self.provider.get_file_content("docs/README.md", "def456")

        call_args = self.mock_gh_runner.run.call_args[0][0]
        self.assertIn("repos/testowner/testrepo/contents/docs/README.md", call_args)
        self.assertIn("ref=def456", call_args)

    def test_get_file_content_raises_on_missing_file(self):
        """Test that get_file_content raises RuntimeError for missing file."""
        self.mock_gh_runner.run.return_value = (False, "Not Found")

        with self.assertRaises(RuntimeError) as ctx:
            self.provider.get_file_content("nonexistent.py", "abc123")

        self.assertIn("Failed to fetch file content", str(ctx.exception))

    def test_get_file_content_raises_on_invalid_commit(self):
        """Test that get_file_content raises RuntimeError for invalid commit."""
        self.mock_gh_runner.run.return_value = (
            False,
            "No commit found for the ref invalid",
        )

        with self.assertRaises(RuntimeError) as ctx:
            self.provider.get_file_content("file.py", "invalid")

        self.assertIn("Failed to fetch file content", str(ctx.exception))

    def test_provider_can_be_instantiated_with_different_repos(self):
        """Test that multiple provider instances can exist."""
        mock_runner1 = MagicMock(spec=GhCommandRunner)
        mock_runner2 = MagicMock(spec=GhCommandRunner)
        provider1 = GitHubDiffProvider("owner1", "repo1", mock_runner1)
        provider2 = GitHubDiffProvider("owner2", "repo2", mock_runner2)

        self.assertEqual(provider1.repo_owner, "owner1")
        self.assertEqual(provider2.repo_owner, "owner2")


if __name__ == "__main__":
    unittest.main()
