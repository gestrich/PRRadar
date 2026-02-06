"""Tests for diff provider factory.

Tests cover:
- Factory creates correct provider types
- GitHub provider instantiation
- Local provider instantiation with GitOperationsService injection
- Default parameters and overrides
"""

import unittest

from scripts.domain.diff_source import DiffSource
from scripts.infrastructure.diff_provider_factory import create_diff_provider
from scripts.infrastructure.github_repo import GithubRepo
from scripts.infrastructure.local_git_repo import LocalGitRepo


class TestDiffProviderFactory(unittest.TestCase):
    """Tests for create_diff_provider factory function."""

    def test_creates_github_repo_for_github_api_source(self):
        """Test that factory creates GithubRepo for GITHUB_API source."""
        provider = create_diff_provider(
            source=DiffSource.GITHUB_API,
            repo_owner="testowner",
            repo_name="testrepo"
        )

        self.assertIsInstance(provider, GithubRepo)

    def test_creates_local_git_repo_for_local_git_source(self):
        """Test that factory creates LocalGitRepo for LOCAL_GIT source."""
        provider = create_diff_provider(
            source=DiffSource.LOCAL_GIT,
            repo_owner="testowner",
            repo_name="testrepo"
        )

        self.assertIsInstance(provider, LocalGitRepo)

    def test_github_provider_has_correct_attributes(self):
        """Test that GitHub provider is initialized with correct owner/name."""
        provider = create_diff_provider(
            source=DiffSource.GITHUB_API,
            repo_owner="myorg",
            repo_name="myrepo"
        )

        self.assertEqual(provider.repo_owner, "myorg")
        self.assertEqual(provider.repo_name, "myrepo")

    def test_local_provider_has_correct_attributes(self):
        """Test that Local provider is initialized with correct owner/name."""
        provider = create_diff_provider(
            source=DiffSource.LOCAL_GIT,
            repo_owner="myorg",
            repo_name="myrepo"
        )

        self.assertEqual(provider.repo_owner, "myorg")
        self.assertEqual(provider.repo_name, "myrepo")

    def test_local_provider_uses_default_repo_path(self):
        """Test that Local provider defaults to current directory."""
        provider = create_diff_provider(
            source=DiffSource.LOCAL_GIT,
            repo_owner="testowner",
            repo_name="testrepo"
        )

        # GitOperationsService is injected with default path
        self.assertIsNotNone(provider.git_service)
        self.assertEqual(str(provider.git_service.repo_path), ".")

    def test_local_provider_accepts_custom_repo_path(self):
        """Test that Local provider accepts custom local_repo_path."""
        provider = create_diff_provider(
            source=DiffSource.LOCAL_GIT,
            repo_owner="testowner",
            repo_name="testrepo",
            local_repo_path="/custom/path"
        )

        self.assertEqual(str(provider.git_service.repo_path), "/custom/path")

    def test_github_provider_ignores_local_repo_path(self):
        """Test that GitHub provider ignores local_repo_path argument."""
        # Should not raise error even if local_repo_path is provided
        provider = create_diff_provider(
            source=DiffSource.GITHUB_API,
            repo_owner="testowner",
            repo_name="testrepo",
            local_repo_path="/some/path"
        )

        self.assertIsInstance(provider, GithubRepo)


if __name__ == "__main__":
    unittest.main()
