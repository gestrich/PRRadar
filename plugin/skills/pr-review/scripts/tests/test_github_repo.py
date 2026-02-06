"""Tests for GithubRepo diff provider.

Tests cover:
- PR diff retrieval via gh CLI
- File content retrieval via gh API
- Source type identification
- Error handling for network failures and invalid PRs
"""

import subprocess
import unittest
from unittest.mock import MagicMock, patch

from scripts.infrastructure.github_repo import GithubRepo


class TestGithubRepo(unittest.TestCase):
    """Tests for GithubRepo provider with mocked subprocess."""

    def setUp(self):
        """Set up test fixtures."""
        self.provider = GithubRepo(repo_owner="testowner", repo_name="testrepo")

    def test_initialization_stores_owner_and_name(self):
        """Test that provider stores owner and repo name."""
        self.assertEqual(self.provider.repo_owner, "testowner")
        self.assertEqual(self.provider.repo_name, "testrepo")

    def test_provider_is_instance_of_diff_provider(self):
        """Test that GithubRepo implements DiffProvider interface."""
        from scripts.infrastructure.repo_source import DiffProvider
        self.assertIsInstance(self.provider, DiffProvider)

    @patch("subprocess.run")
    def test_get_pr_diff_calls_gh_pr_diff(self, mock_run):
        """Test that get_pr_diff calls gh pr diff with correct arguments."""
        expected_diff = "diff --git a/file.py b/file.py\n+new line\n"
        mock_run.return_value = MagicMock(stdout=expected_diff, returncode=0)

        result = self.provider.get_pr_diff(123)

        self.assertEqual(result, expected_diff)
        mock_run.assert_called_once_with(
            ["gh", "pr", "diff", "123", "--repo", "testowner/testrepo"],
            capture_output=True,
            text=True,
            check=True,
        )

    @patch("subprocess.run")
    def test_get_pr_diff_handles_different_pr_numbers(self, mock_run):
        """Test that get_pr_diff works with different PR numbers."""
        mock_run.return_value = MagicMock(stdout="diff content", returncode=0)

        self.provider.get_pr_diff(456)

        args = mock_run.call_args[0][0]
        self.assertIn("456", args)

    @patch("subprocess.run")
    def test_get_pr_diff_exits_on_network_failure(self, mock_run):
        """Test that get_pr_diff calls sys.exit on network failure."""
        mock_run.side_effect = subprocess.CalledProcessError(
            returncode=1,
            cmd=["gh", "pr", "diff"],
            stderr="HTTP 500: Internal Server Error",
        )

        with self.assertRaises(SystemExit):
            self.provider.get_pr_diff(123)

    @patch("subprocess.run")
    def test_get_pr_diff_exits_on_invalid_pr(self, mock_run):
        """Test that get_pr_diff calls sys.exit for non-existent PR."""
        mock_run.side_effect = subprocess.CalledProcessError(
            returncode=1,
            cmd=["gh", "pr", "diff"],
            stderr="pull request not found",
        )

        with self.assertRaises(SystemExit):
            self.provider.get_pr_diff(99999)

    @patch("subprocess.run")
    def test_get_file_content_calls_gh_api(self, mock_run):
        """Test that get_file_content calls gh api with correct arguments."""
        expected_content = "def main():\n    pass\n"
        mock_run.return_value = MagicMock(stdout=expected_content, returncode=0)

        result = self.provider.get_file_content("src/main.py", "abc123")

        self.assertEqual(result, expected_content)
        mock_run.assert_called_once_with(
            [
                "gh",
                "api",
                "repos/testowner/testrepo/contents/src/main.py",
                "--jq",
                ".content",
                "-H",
                "Accept: application/vnd.github.v3.raw",
                "-f",
                "ref=abc123",
            ],
            capture_output=True,
            text=True,
            check=True,
        )

    @patch("subprocess.run")
    def test_get_file_content_handles_different_files(self, mock_run):
        """Test that get_file_content works with different file paths."""
        mock_run.return_value = MagicMock(stdout="content", returncode=0)

        self.provider.get_file_content("docs/README.md", "def456")

        args = mock_run.call_args[0][0]
        self.assertIn("repos/testowner/testrepo/contents/docs/README.md", args)
        self.assertIn("ref=def456", args)

    @patch("subprocess.run")
    def test_get_file_content_returns_empty_on_missing_file(self, mock_run):
        """Test that get_file_content returns empty string for missing file."""
        mock_run.side_effect = subprocess.CalledProcessError(
            returncode=1,
            cmd=["gh", "api"],
            stderr="Not Found",
        )

        result = self.provider.get_file_content("nonexistent.py", "abc123")
        self.assertEqual(result, "")

    @patch("subprocess.run")
    def test_get_file_content_returns_empty_on_invalid_commit(self, mock_run):
        """Test that get_file_content returns empty string for invalid commit."""
        mock_run.side_effect = subprocess.CalledProcessError(
            returncode=1,
            cmd=["gh", "api"],
            stderr="No commit found for the ref invalid",
        )

        result = self.provider.get_file_content("file.py", "invalid")
        self.assertEqual(result, "")

    def test_provider_can_be_instantiated_with_different_repos(self):
        """Test that multiple provider instances can exist."""
        provider1 = GithubRepo("owner1", "repo1")
        provider2 = GithubRepo("owner2", "repo2")

        self.assertEqual(provider1.repo_owner, "owner1")
        self.assertEqual(provider2.repo_owner, "owner2")


if __name__ == "__main__":
    unittest.main()
