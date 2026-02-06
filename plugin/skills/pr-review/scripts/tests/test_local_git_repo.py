"""Tests for LocalGitRepo diff provider.

Tests cover:
- PR diff retrieval with PR metadata from GitHub
- Safety checks delegation to GitOperationsService
- Branch fetching via service
- Diff generation via service
- Source type identification
- Error handling with mocked dependencies
"""

import subprocess
import unittest
from unittest.mock import MagicMock, patch

from scripts.infrastructure.local_git_repo import LocalGitRepo
from scripts.services.git_operations import (
    GitDirtyWorkingDirectoryError,
    GitOperationsService,
)


class TestLocalGitRepo(unittest.TestCase):
    """Tests for LocalGitRepo provider with mocked GitOperationsService."""

    def setUp(self):
        """Set up test fixtures."""
        self.mock_git_service = MagicMock(spec=GitOperationsService)
        self.provider = LocalGitRepo(
            repo_owner="testowner",
            repo_name="testrepo",
            git_service=self.mock_git_service,
        )

    def test_initialization_stores_owner_and_name(self):
        """Test that provider stores owner and repo name."""
        self.assertEqual(self.provider.repo_owner, "testowner")
        self.assertEqual(self.provider.repo_name, "testrepo")

    def test_initialization_stores_git_service(self):
        """Test that provider stores injected git service."""
        self.assertEqual(self.provider.git_service, self.mock_git_service)

    def test_provider_is_instance_of_diff_provider(self):
        """Test that LocalGitRepo implements DiffProvider interface."""
        from scripts.infrastructure.repo_source import DiffProvider
        self.assertIsInstance(self.provider, DiffProvider)

    @patch("subprocess.run")
    def test_get_pr_diff_fetches_pr_metadata_from_github(self, mock_run):
        """Test that get_pr_diff fetches PR metadata using gh CLI."""
        pr_json = '{"baseRefName": "main", "headRefName": "feature"}'
        mock_run.return_value = MagicMock(stdout=pr_json, returncode=0)
        self.mock_git_service.check_working_directory_clean.return_value = True
        self.mock_git_service.get_branch_diff.return_value = "diff content"

        self.provider.get_pr_diff(123)

        mock_run.assert_called_once_with(
            ["gh", "pr", "view", "123", "--repo", "testowner/testrepo", "--json", "baseRefName,headRefName"],
            capture_output=True,
            text=True,
            check=True,
        )

    @patch("subprocess.run")
    def test_get_pr_diff_checks_working_directory_clean(self, mock_run):
        """Test that get_pr_diff checks for clean working directory."""
        pr_json = '{"baseRefName": "main", "headRefName": "feature"}'
        mock_run.return_value = MagicMock(stdout=pr_json, returncode=0)
        self.mock_git_service.get_branch_diff.return_value = "diff content"

        self.provider.get_pr_diff(123)

        self.mock_git_service.check_working_directory_clean.assert_called_once()

    @patch("subprocess.run")
    def test_get_pr_diff_aborts_on_dirty_working_directory(self, mock_run):
        """Test that get_pr_diff raises error when working directory is dirty."""
        pr_json = '{"baseRefName": "main", "headRefName": "feature"}'
        mock_run.return_value = MagicMock(stdout=pr_json, returncode=0)
        self.mock_git_service.check_working_directory_clean.side_effect = (
            GitDirtyWorkingDirectoryError("Uncommitted changes")
        )

        with self.assertRaises(GitDirtyWorkingDirectoryError):
            self.provider.get_pr_diff(123)

        # Should not proceed to fetch or diff
        self.mock_git_service.fetch_branch.assert_not_called()
        self.mock_git_service.get_branch_diff.assert_not_called()

    @patch("subprocess.run")
    def test_get_pr_diff_fetches_base_and_head_branches(self, mock_run):
        """Test that get_pr_diff fetches both base and head branches."""
        pr_json = '{"baseRefName": "main", "headRefName": "feature-x"}'
        mock_run.return_value = MagicMock(stdout=pr_json, returncode=0)
        self.mock_git_service.check_working_directory_clean.return_value = True
        self.mock_git_service.get_branch_diff.return_value = "diff content"

        self.provider.get_pr_diff(123)

        # Should fetch both branches
        calls = self.mock_git_service.fetch_branch.call_args_list
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0][0][0], "main")
        self.assertEqual(calls[1][0][0], "feature-x")

    @patch("subprocess.run")
    def test_get_pr_diff_computes_diff_between_branches(self, mock_run):
        """Test that get_pr_diff computes diff between base and head."""
        pr_json = '{"baseRefName": "develop", "headRefName": "bugfix"}'
        mock_run.return_value = MagicMock(stdout=pr_json, returncode=0)
        self.mock_git_service.check_working_directory_clean.return_value = True
        expected_diff = "diff --git a/file.py b/file.py\n+new\n"
        self.mock_git_service.get_branch_diff.return_value = expected_diff

        result = self.provider.get_pr_diff(123)

        self.assertEqual(result, expected_diff)
        self.mock_git_service.get_branch_diff.assert_called_once_with("develop", "bugfix")

    @patch("subprocess.run")
    def test_get_pr_diff_exits_on_invalid_pr_number(self, mock_run):
        """Test that get_pr_diff calls sys.exit for invalid PR."""
        mock_run.side_effect = subprocess.CalledProcessError(
            returncode=1,
            cmd=["gh", "pr", "view"],
            stderr="pull request not found",
        )

        with self.assertRaises(SystemExit):
            self.provider.get_pr_diff(99999)

    @patch("subprocess.run")
    def test_get_pr_diff_exits_on_malformed_pr_metadata(self, mock_run):
        """Test that get_pr_diff calls sys.exit for malformed JSON."""
        mock_run.return_value = MagicMock(stdout="not valid json {{{", returncode=0)

        with self.assertRaises(SystemExit):
            self.provider.get_pr_diff(123)

    @patch("subprocess.run")
    def test_get_pr_diff_workflow_order(self, mock_run):
        """Test that get_pr_diff executes operations in correct order."""
        pr_json = '{"baseRefName": "main", "headRefName": "feature"}'
        mock_run.return_value = MagicMock(stdout=pr_json, returncode=0)
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

        self.mock_git_service.check_working_directory_clean.side_effect = track_check_clean
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
        self.mock_git_service.get_file_content.assert_called_once_with("src/file.py", "abc123")

    def test_get_file_content_raises_on_service_error(self):
        """Test that get_file_content propagates service errors."""
        self.mock_git_service.get_file_content.side_effect = Exception("File not found")

        with self.assertRaises(Exception) as ctx:
            self.provider.get_file_content("missing.py", "abc123")

        self.assertIn("File not found", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
