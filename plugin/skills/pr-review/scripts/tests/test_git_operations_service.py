"""Tests for GitOperationsService.

Tests cover:
- Working directory clean checks
- Branch fetching
- Diff generation between branches
- Git repository validation
- File content retrieval
- Error handling for all operations
- Subprocess command verification (via mocking)
"""

import subprocess
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from scripts.services.git_operations import (
    GitDiffError,
    GitDirtyWorkingDirectoryError,
    GitFetchError,
    GitFileNotFoundError,
    GitOperationsService,
)


class TestGitOperationsService(unittest.TestCase):
    """Tests for GitOperationsService with mocked subprocess."""

    def setUp(self):
        """Set up test fixtures."""
        self.service = GitOperationsService(repo_path="/test/repo")

    @patch("subprocess.run")
    def test_check_working_directory_clean_returns_true_when_clean(self, mock_run):
        """Test that check_working_directory_clean returns True for clean repo."""
        mock_run.return_value = MagicMock(stdout="", returncode=0)

        result = self.service.check_working_directory_clean()

        self.assertTrue(result)
        args = mock_run.call_args
        self.assertEqual(args[0][0], ["git", "status", "--porcelain"])
        self.assertEqual(str(args[1]["cwd"]), "/test/repo")

    @patch("subprocess.run")
    def test_check_working_directory_clean_raises_on_dirty_repo(self, mock_run):
        """Test that check_working_directory_clean raises error for dirty repo."""
        mock_run.return_value = MagicMock(stdout=" M file.py\n", returncode=0)

        with self.assertRaises(GitDirtyWorkingDirectoryError) as ctx:
            self.service.check_working_directory_clean()

        self.assertIn("uncommitted changes detected", str(ctx.exception))
        self.assertIn("git stash", str(ctx.exception))

    @patch("subprocess.run")
    def test_check_working_directory_clean_raises_on_staged_changes(self, mock_run):
        """Test that check_working_directory_clean raises error for staged changes."""
        mock_run.return_value = MagicMock(stdout="A  new_file.py\n", returncode=0)

        with self.assertRaises(GitDirtyWorkingDirectoryError):
            self.service.check_working_directory_clean()

    @patch("subprocess.run")
    def test_fetch_branch_calls_correct_command(self, mock_run):
        """Test that fetch_branch calls git fetch with correct arguments."""
        mock_run.return_value = MagicMock(returncode=0)

        self.service.fetch_branch("feature-branch")

        args = mock_run.call_args
        self.assertEqual(args[0][0], ["git", "fetch", "origin", "feature-branch"])
        self.assertIn("capture_output", args[1])
        self.assertTrue(args[1]["capture_output"])

    @patch("subprocess.run")
    def test_fetch_branch_accepts_custom_remote(self, mock_run):
        """Test that fetch_branch accepts custom remote name."""
        mock_run.return_value = MagicMock(returncode=0)

        self.service.fetch_branch("feature-branch", remote="upstream")

        args = mock_run.call_args
        self.assertEqual(args[0][0], ["git", "fetch", "upstream", "feature-branch"])

    @patch("subprocess.run")
    def test_fetch_branch_raises_on_failure(self, mock_run):
        """Test that fetch_branch raises GitFetchError on failure."""
        # First call succeeds (is_git_repository check)
        # Second call fails (fetch operation)
        mock_run.side_effect = [
            MagicMock(returncode=0),  # is_git_repository
            subprocess.CalledProcessError(
                returncode=1,
                cmd=["git", "fetch"],
                stderr="fatal: couldn't find remote ref feature-branch",
            ),
        ]

        with self.assertRaises(GitFetchError) as ctx:
            self.service.fetch_branch("feature-branch")

        self.assertIn("Failed to fetch", str(ctx.exception))
        self.assertIn("feature-branch", str(ctx.exception))

    @patch("subprocess.run")
    def test_get_branch_diff_returns_diff_content(self, mock_run):
        """Test that get_branch_diff returns diff output."""
        expected_diff = "diff --git a/file.py b/file.py\n+new line\n"
        mock_run.return_value = MagicMock(stdout=expected_diff, returncode=0)

        result = self.service.get_branch_diff("main", "feature")

        self.assertEqual(result, expected_diff)
        args = mock_run.call_args
        self.assertEqual(args[0][0], ["git", "diff", "origin/main...origin/feature"])

    @patch("subprocess.run")
    def test_get_branch_diff_uses_custom_remote(self, mock_run):
        """Test that get_branch_diff accepts custom remote."""
        mock_run.return_value = MagicMock(stdout="diff content", returncode=0)

        self.service.get_branch_diff("main", "feature", remote="upstream")

        args = mock_run.call_args
        self.assertEqual(args[0][0], ["git", "diff", "upstream/main...upstream/feature"])

    @patch("subprocess.run")
    def test_get_branch_diff_raises_on_failure(self, mock_run):
        """Test that get_branch_diff raises GitDiffError on failure."""
        # First call succeeds (is_git_repository check)
        # Second call fails (diff operation)
        mock_run.side_effect = [
            MagicMock(returncode=0),  # is_git_repository
            subprocess.CalledProcessError(
                returncode=1,
                cmd=["git", "diff"],
                stderr="fatal: bad revision",
            ),
        ]

        with self.assertRaises(GitDiffError) as ctx:
            self.service.get_branch_diff("main", "feature")

        self.assertIn("Failed to compute diff", str(ctx.exception))

    @patch("subprocess.run")
    def test_is_git_repository_returns_true_for_valid_repo(self, mock_run):
        """Test that is_git_repository returns True for valid repo."""
        mock_run.return_value = MagicMock(returncode=0)

        result = self.service.is_git_repository()

        self.assertTrue(result)
        args = mock_run.call_args
        self.assertEqual(args[0][0], ["git", "rev-parse", "--git-dir"])

    @patch("subprocess.run")
    def test_is_git_repository_returns_false_for_invalid_repo(self, mock_run):
        """Test that is_git_repository returns False for non-git directory."""
        mock_run.side_effect = subprocess.CalledProcessError(
            returncode=128,
            cmd=["git", "rev-parse", "--git-dir"],
        )

        result = self.service.is_git_repository()

        self.assertFalse(result)

    @patch("subprocess.run")
    def test_get_file_content_returns_file_content(self, mock_run):
        """Test that get_file_content returns file content at commit."""
        expected_content = "def main():\n    pass\n"
        mock_run.return_value = MagicMock(stdout=expected_content, returncode=0)

        result = self.service.get_file_content("src/main.py", "abc123")

        self.assertEqual(result, expected_content)
        args = mock_run.call_args
        self.assertEqual(args[0][0], ["git", "show", "abc123:src/main.py"])

    @patch("subprocess.run")
    def test_get_file_content_raises_on_missing_file(self, mock_run):
        """Test that get_file_content raises GitFileNotFoundError for missing file."""
        # First call succeeds (is_git_repository check)
        # Second call fails (show operation)
        mock_run.side_effect = [
            MagicMock(returncode=0),  # is_git_repository
            subprocess.CalledProcessError(
                returncode=128,
                cmd=["git", "show"],
                stderr="fatal: path 'missing.py' does not exist",
            ),
        ]

        with self.assertRaises(GitFileNotFoundError) as ctx:
            self.service.get_file_content("missing.py", "abc123")

        self.assertIn("File missing.py not found", str(ctx.exception))
        self.assertIn("abc123", str(ctx.exception))

    @patch("subprocess.run")
    def test_get_file_content_accepts_branch_name(self, mock_run):
        """Test that get_file_content accepts branch name instead of commit."""
        mock_run.return_value = MagicMock(stdout="content", returncode=0)

        self.service.get_file_content("file.py", "feature-branch")

        args = mock_run.call_args
        self.assertEqual(args[0][0], ["git", "show", "feature-branch:file.py"])

    def test_service_initializes_with_default_path(self):
        """Test that service can be initialized with default repo path."""
        service = GitOperationsService()

        self.assertEqual(str(service.repo_path), ".")

    def test_service_stores_repo_path_as_pathlib_path(self):
        """Test that repo_path is stored as Path object."""
        service = GitOperationsService(repo_path="/custom/path")

        self.assertIsInstance(service.repo_path, Path)
        self.assertEqual(str(service.repo_path), "/custom/path")


if __name__ == "__main__":
    unittest.main()
