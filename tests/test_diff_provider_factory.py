"""Tests for diff provider factory.

Tests cover:
- Factory creates correct provider types
- GitHub provider instantiation with GitOperationsService
- Local provider instantiation with GitOperationsService injection
- Both providers receive local_repo_path (required for both)
"""

import unittest

from prradar.domain.diff_source import DiffSource
from prradar.infrastructure.diff_provider.factory import create_diff_provider
from prradar.infrastructure.diff_provider.github_source import GitHubDiffProvider
from prradar.infrastructure.diff_provider.local_source import LocalGitDiffProvider


class TestDiffProviderFactory(unittest.TestCase):
    """Tests for create_diff_provider factory function."""

    def test_creates_github_repo_for_github_api_source(self):
        """Test that factory creates GitHubDiffProvider for GITHUB_API source."""
        provider = create_diff_provider(
            source=DiffSource.GITHUB_API,
            repo_owner="testowner",
            repo_name="testrepo",
            local_repo_path=".",
        )

        self.assertIsInstance(provider, GitHubDiffProvider)

    def test_creates_local_git_repo_for_local_git_source(self):
        """Test that factory creates LocalGitDiffProvider for LOCAL_GIT source."""
        provider = create_diff_provider(
            source=DiffSource.LOCAL_GIT,
            repo_owner="testowner",
            repo_name="testrepo",
            local_repo_path=".",
        )

        self.assertIsInstance(provider, LocalGitDiffProvider)

    def test_github_provider_has_correct_attributes(self):
        """Test that GitHub provider is initialized with correct owner/name."""
        provider = create_diff_provider(
            source=DiffSource.GITHUB_API,
            repo_owner="myorg",
            repo_name="myrepo",
            local_repo_path=".",
        )

        self.assertEqual(provider.repo_owner, "myorg")
        self.assertEqual(provider.repo_name, "myrepo")

    def test_github_provider_injects_git_service(self):
        """Test that GitHubDiffProvider receives GitOperationsService dependency."""
        provider = create_diff_provider(
            source=DiffSource.GITHUB_API,
            repo_owner="testowner",
            repo_name="testrepo",
            local_repo_path="/some/path",
        )

        from prradar.services.git_operations import GitOperationsService
        self.assertIsInstance(provider.git_service, GitOperationsService)
        self.assertEqual(str(provider.git_service.repo_path), "/some/path")

    def test_github_provider_injects_gh_runner(self):
        """Test that GitHubDiffProvider receives GhCommandRunner dependency."""
        provider = create_diff_provider(
            source=DiffSource.GITHUB_API,
            repo_owner="testowner",
            repo_name="testrepo",
            local_repo_path=".",
        )

        self.assertIsNotNone(provider.gh_runner)
        from prradar.infrastructure.github.runner import GhCommandRunner
        self.assertIsInstance(provider.gh_runner, GhCommandRunner)

    def test_local_provider_has_correct_attributes(self):
        """Test that Local provider is initialized with correct owner/name."""
        provider = create_diff_provider(
            source=DiffSource.LOCAL_GIT,
            repo_owner="myorg",
            repo_name="myrepo",
            local_repo_path=".",
        )

        self.assertEqual(provider.repo_owner, "myorg")
        self.assertEqual(provider.repo_name, "myrepo")

    def test_local_provider_accepts_custom_repo_path(self):
        """Test that Local provider accepts custom local_repo_path."""
        provider = create_diff_provider(
            source=DiffSource.LOCAL_GIT,
            repo_owner="testowner",
            repo_name="testrepo",
            local_repo_path="/custom/path",
        )

        self.assertEqual(str(provider.git_service.repo_path), "/custom/path")

    def test_local_provider_injects_gh_runner(self):
        """Test that LocalGitDiffProvider receives GhCommandRunner dependency."""
        provider = create_diff_provider(
            source=DiffSource.LOCAL_GIT,
            repo_owner="testowner",
            repo_name="testrepo",
            local_repo_path="/some/path",
        )

        self.assertIsNotNone(provider.gh_runner)
        from prradar.infrastructure.github.runner import GhCommandRunner
        self.assertIsInstance(provider.gh_runner, GhCommandRunner)

    def test_github_provider_uses_repo_path(self):
        """Test that GitHub provider configures GitOperationsService with the given path."""
        provider = create_diff_provider(
            source=DiffSource.GITHUB_API,
            repo_owner="testowner",
            repo_name="testrepo",
            local_repo_path="/my/repo",
        )

        self.assertEqual(str(provider.git_service.repo_path), "/my/repo")


if __name__ == "__main__":
    unittest.main()
