"""Tests for GitHubDiffProvider diff provider.

Tests cover:
- PR diff retrieval with checkout flow then gh pr diff
- File content retrieval via GhCommandRunner
- Source type identification
- Error handling for network failures and invalid PRs
- Checkout workflow order
"""

import unittest
from unittest.mock import MagicMock

from prradar.domain.github import PullRequest
from prradar.infrastructure.github.runner import GhCommandRunner
from prradar.infrastructure.diff_provider.github_source import GitHubDiffProvider
from prradar.services.git_operations import (
    GitCheckoutError,
    GitDirtyWorkingDirectoryError,
    GitOperationsService,
)


class TestGitHubDiffProvider(unittest.TestCase):
    """Tests for GitHubDiffProvider provider with mocked dependencies."""

    def setUp(self):
        """Set up test fixtures."""
        self.mock_git_service = MagicMock(spec=GitOperationsService)
        self.mock_gh_runner = MagicMock(spec=GhCommandRunner)
        self.provider = GitHubDiffProvider(
            repo_owner="testowner",
            repo_name="testrepo",
            git_service=self.mock_git_service,
            gh_runner=self.mock_gh_runner,
        )

    def _setup_successful_pr(self, base="main", head="feature", sha="abc123sha"):
        """Helper to set up a successful PR metadata response."""
        mock_pr = MagicMock(spec=PullRequest)
        mock_pr.base_ref_name = base
        mock_pr.head_ref_name = head
        mock_pr.head_ref_oid = sha
        self.mock_gh_runner.get_pull_request.return_value = (True, mock_pr)
        self.mock_git_service.check_working_directory_clean.return_value = True
        return mock_pr

    def test_initialization_stores_owner_and_name(self):
        """Test that provider stores owner and repo name."""
        self.assertEqual(self.provider.repo_owner, "testowner")
        self.assertEqual(self.provider.repo_name, "testrepo")

    def test_initialization_stores_git_service(self):
        """Test that provider stores injected git service."""
        self.assertEqual(self.provider.git_service, self.mock_git_service)

    def test_initialization_stores_gh_runner(self):
        """Test that provider stores injected gh runner."""
        self.assertEqual(self.provider.gh_runner, self.mock_gh_runner)

    def test_provider_is_instance_of_diff_provider(self):
        """Test that GitHubDiffProvider implements DiffProvider interface."""
        from prradar.infrastructure.diff_provider.base import DiffProvider

        self.assertIsInstance(self.provider, DiffProvider)

    def test_get_pr_diff_fetches_pr_metadata_from_github(self):
        """Test that get_pr_diff fetches PR metadata using GhCommandRunner."""
        self._setup_successful_pr()
        self.mock_gh_runner.pr_diff.return_value = (True, "diff content")

        self.provider.get_pr_diff(123)

        self.mock_gh_runner.get_pull_request.assert_called_once_with(123)

    def test_get_pr_diff_checks_working_directory_clean(self):
        """Test that get_pr_diff checks for clean working directory."""
        self._setup_successful_pr()
        self.mock_gh_runner.pr_diff.return_value = (True, "diff content")

        self.provider.get_pr_diff(123)

        self.mock_git_service.check_working_directory_clean.assert_called_once()

    def test_get_pr_diff_aborts_on_dirty_working_directory(self):
        """Test that get_pr_diff raises error when working directory is dirty."""
        self._setup_successful_pr()
        self.mock_git_service.check_working_directory_clean.side_effect = (
            GitDirtyWorkingDirectoryError("Uncommitted changes")
        )

        with self.assertRaises(GitDirtyWorkingDirectoryError):
            self.provider.get_pr_diff(123)

        self.mock_git_service.fetch_branch.assert_not_called()
        self.mock_git_service.checkout_commit.assert_not_called()
        self.mock_gh_runner.pr_diff.assert_not_called()

    def test_get_pr_diff_fetches_base_and_head_branches(self):
        """Test that get_pr_diff fetches both base and head branches."""
        self._setup_successful_pr(base="main", head="feature-x")
        self.mock_gh_runner.pr_diff.return_value = (True, "diff content")

        self.provider.get_pr_diff(123)

        calls = self.mock_git_service.fetch_branch.call_args_list
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0][0][0], "main")
        self.assertEqual(calls[1][0][0], "feature-x")

    def test_get_pr_diff_checks_out_head_commit(self):
        """Test that get_pr_diff checks out the PR's head commit SHA."""
        self._setup_successful_pr(sha="deadbeef123")
        self.mock_gh_runner.pr_diff.return_value = (True, "diff content")

        self.provider.get_pr_diff(123)

        self.mock_git_service.checkout_commit.assert_called_once_with("deadbeef123")

    def test_get_pr_diff_aborts_on_checkout_failure(self):
        """Test that get_pr_diff propagates checkout errors."""
        self._setup_successful_pr(sha="badsha")
        self.mock_git_service.checkout_commit.side_effect = GitCheckoutError(
            "Failed to checkout badsha"
        )

        with self.assertRaises(GitCheckoutError):
            self.provider.get_pr_diff(123)

        self.mock_gh_runner.pr_diff.assert_not_called()

    def test_get_pr_diff_returns_gh_pr_diff_result(self):
        """Test that get_pr_diff returns the diff from gh pr diff."""
        self._setup_successful_pr()
        expected_diff = "diff --git a/file.py b/file.py\n+new line\n"
        self.mock_gh_runner.pr_diff.return_value = (True, expected_diff)

        result = self.provider.get_pr_diff(123)

        self.assertEqual(result, expected_diff)
        self.mock_gh_runner.pr_diff.assert_called_once_with(123)

    def test_get_pr_diff_raises_on_pr_metadata_failure(self):
        """Test that get_pr_diff raises RuntimeError when PR metadata fails."""
        self.mock_gh_runner.get_pull_request.return_value = (
            False,
            "pull request not found",
        )

        with self.assertRaises(RuntimeError) as ctx:
            self.provider.get_pr_diff(99999)

        self.assertIn("Failed to fetch PR metadata", str(ctx.exception))

    def test_get_pr_diff_raises_on_diff_fetch_failure(self):
        """Test that get_pr_diff raises RuntimeError when gh pr diff fails."""
        self._setup_successful_pr()
        self.mock_gh_runner.pr_diff.return_value = (
            False,
            "HTTP 500: Internal Server Error",
        )

        with self.assertRaises(RuntimeError) as ctx:
            self.provider.get_pr_diff(123)

        self.assertIn("Failed to fetch PR diff", str(ctx.exception))

    def test_get_pr_diff_workflow_order(self):
        """Test that get_pr_diff executes operations in correct order."""
        self._setup_successful_pr()
        self.mock_gh_runner.pr_diff.return_value = (True, "diff")

        call_order = []

        def track_check_clean():
            call_order.append("check_clean")
            return True

        def track_fetch(branch):
            call_order.append(f"fetch_{branch}")

        def track_checkout(sha):
            call_order.append("checkout_commit")

        def track_pr_diff(pr_number):
            call_order.append("pr_diff")
            return (True, "diff content")

        self.mock_git_service.check_working_directory_clean.side_effect = (
            track_check_clean
        )
        self.mock_git_service.fetch_branch.side_effect = track_fetch
        self.mock_git_service.checkout_commit.side_effect = track_checkout
        self.mock_gh_runner.pr_diff.side_effect = track_pr_diff

        self.provider.get_pr_diff(123)

        self.assertEqual(
            call_order,
            ["check_clean", "fetch_main", "fetch_feature", "checkout_commit", "pr_diff"],
        )

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
        mock_git1 = MagicMock(spec=GitOperationsService)
        mock_git2 = MagicMock(spec=GitOperationsService)
        mock_runner1 = MagicMock(spec=GhCommandRunner)
        mock_runner2 = MagicMock(spec=GhCommandRunner)
        provider1 = GitHubDiffProvider("owner1", "repo1", mock_git1, mock_runner1)
        provider2 = GitHubDiffProvider("owner2", "repo2", mock_git2, mock_runner2)

        self.assertEqual(provider1.repo_owner, "owner1")
        self.assertEqual(provider2.repo_owner, "owner2")


if __name__ == "__main__":
    unittest.main()
