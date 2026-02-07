"""Tests for LocalGitDiffProvider diff provider.

Tests cover:
- PR diff retrieval with PR metadata from GitHub via GhCommandRunner
- Safety checks delegation to GitOperationsService
- Branch fetching via service
- Diff generation via service
- Source type identification
- Error handling with mocked dependencies
"""

import unittest
from unittest.mock import MagicMock

from prradar.domain.github import PullRequest
from prradar.infrastructure.github.runner import GhCommandRunner
from prradar.infrastructure.diff_provider.local_source import LocalGitDiffProvider
from prradar.services.git_operations import (
    GitDirtyWorkingDirectoryError,
    GitOperationsService,
)


class TestLocalGitDiffProvider(unittest.TestCase):
    """Tests for LocalGitDiffProvider provider with mocked dependencies."""

    def setUp(self):
        """Set up test fixtures."""
        self.mock_git_service = MagicMock(spec=GitOperationsService)
        self.mock_gh_runner = MagicMock(spec=GhCommandRunner)
        self.provider = LocalGitDiffProvider(
            repo_owner="testowner",
            repo_name="testrepo",
            git_service=self.mock_git_service,
            gh_runner=self.mock_gh_runner,
        )

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
        """Test that LocalGitDiffProvider implements DiffProvider interface."""
        from prradar.infrastructure.diff_provider.base import DiffProvider

        self.assertIsInstance(self.provider, DiffProvider)

    def test_get_pr_diff_fetches_pr_metadata_from_github(self):
        """Test that get_pr_diff fetches PR metadata using GhCommandRunner."""
        mock_pr = MagicMock(spec=PullRequest)
        mock_pr.base_ref_name = "main"
        mock_pr.head_ref_name = "feature"
        self.mock_gh_runner.get_pull_request.return_value = (True, mock_pr)
        self.mock_git_service.check_working_directory_clean.return_value = True
        self.mock_git_service.get_branch_diff.return_value = "diff content"

        self.provider.get_pr_diff(123)

        self.mock_gh_runner.get_pull_request.assert_called_once_with(123)

    def test_get_pr_diff_checks_working_directory_clean(self):
        """Test that get_pr_diff checks for clean working directory."""
        mock_pr = MagicMock(spec=PullRequest)
        mock_pr.base_ref_name = "main"
        mock_pr.head_ref_name = "feature"
        self.mock_gh_runner.get_pull_request.return_value = (True, mock_pr)
        self.mock_git_service.get_branch_diff.return_value = "diff content"

        self.provider.get_pr_diff(123)

        self.mock_git_service.check_working_directory_clean.assert_called_once()

    def test_get_pr_diff_aborts_on_dirty_working_directory(self):
        """Test that get_pr_diff raises error when working directory is dirty."""
        mock_pr = MagicMock(spec=PullRequest)
        mock_pr.base_ref_name = "main"
        mock_pr.head_ref_name = "feature"
        self.mock_gh_runner.get_pull_request.return_value = (True, mock_pr)
        self.mock_git_service.check_working_directory_clean.side_effect = (
            GitDirtyWorkingDirectoryError("Uncommitted changes")
        )

        with self.assertRaises(GitDirtyWorkingDirectoryError):
            self.provider.get_pr_diff(123)

        # Should not proceed to fetch or diff
        self.mock_git_service.fetch_branch.assert_not_called()
        self.mock_git_service.get_branch_diff.assert_not_called()

    def test_get_pr_diff_fetches_base_and_head_branches(self):
        """Test that get_pr_diff fetches both base and head branches."""
        mock_pr = MagicMock(spec=PullRequest)
        mock_pr.base_ref_name = "main"
        mock_pr.head_ref_name = "feature-x"
        self.mock_gh_runner.get_pull_request.return_value = (True, mock_pr)
        self.mock_git_service.check_working_directory_clean.return_value = True
        self.mock_git_service.get_branch_diff.return_value = "diff content"

        self.provider.get_pr_diff(123)

        # Should fetch both branches
        calls = self.mock_git_service.fetch_branch.call_args_list
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0][0][0], "main")
        self.assertEqual(calls[1][0][0], "feature-x")

    def test_get_pr_diff_computes_diff_between_branches(self):
        """Test that get_pr_diff computes diff between base and head."""
        mock_pr = MagicMock(spec=PullRequest)
        mock_pr.base_ref_name = "develop"
        mock_pr.head_ref_name = "bugfix"
        self.mock_gh_runner.get_pull_request.return_value = (True, mock_pr)
        self.mock_git_service.check_working_directory_clean.return_value = True
        expected_diff = "diff --git a/file.py b/file.py\n+new\n"
        self.mock_git_service.get_branch_diff.return_value = expected_diff

        result = self.provider.get_pr_diff(123)

        self.assertEqual(result, expected_diff)
        self.mock_git_service.get_branch_diff.assert_called_once_with(
            "develop", "bugfix"
        )

    def test_get_pr_diff_raises_on_github_api_failure(self):
        """Test that get_pr_diff raises RuntimeError when GitHub API fails."""
        self.mock_gh_runner.get_pull_request.return_value = (
            False,
            "pull request not found",
        )

        with self.assertRaises(RuntimeError) as ctx:
            self.provider.get_pr_diff(99999)

        self.assertIn("Failed to fetch PR metadata", str(ctx.exception))

    def test_get_pr_diff_workflow_order(self):
        """Test that get_pr_diff executes operations in correct order."""
        mock_pr = MagicMock(spec=PullRequest)
        mock_pr.base_ref_name = "main"
        mock_pr.head_ref_name = "feature"
        self.mock_gh_runner.get_pull_request.return_value = (True, mock_pr)
        self.mock_git_service.check_working_directory_clean.return_value = True
        self.mock_git_service.get_branch_diff.return_value = "diff"

        call_order = []

        def track_check_clean():
            call_order.append("check_clean")
            return True

        def track_fetch(branch):
            call_order.append(f"fetch_{branch}")

        def track_diff(base, head):
            call_order.append("diff")
            return "diff content"

        self.mock_git_service.check_working_directory_clean.side_effect = (
            track_check_clean
        )
        self.mock_git_service.fetch_branch.side_effect = track_fetch
        self.mock_git_service.get_branch_diff.side_effect = track_diff

        self.provider.get_pr_diff(123)

        # Verify order: check clean → fetch base → fetch head → diff
        self.assertEqual(
            call_order,
            ["check_clean", "fetch_main", "fetch_feature", "diff"],
        )

    def test_get_file_content_delegates_to_git_service(self):
        """Test that get_file_content delegates to GitOperationsService."""
        expected_content = "file content"
        self.mock_git_service.get_file_content.return_value = expected_content

        result = self.provider.get_file_content("src/file.py", "abc123")

        self.assertEqual(result, expected_content)
        self.mock_git_service.get_file_content.assert_called_once_with(
            "src/file.py", "abc123"
        )

    def test_get_file_content_raises_on_service_error(self):
        """Test that get_file_content propagates service errors."""
        self.mock_git_service.get_file_content.side_effect = Exception("File not found")

        with self.assertRaises(Exception) as ctx:
            self.provider.get_file_content("missing.py", "abc123")

        self.assertIn("File not found", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
