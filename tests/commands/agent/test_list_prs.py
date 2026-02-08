"""Tests for the agent list-prs command.

Tests cover:
- Successful PR list fetch and metadata file writing
- Directory structure creation ({output_dir}/{pr_number}/phase-1-pull-request/)
- Error handling when gh pr list fails
- Error handling when gh repo view fails
- Empty PR list behavior
- Limit and state parameter passthrough
"""

import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import MagicMock, patch

from prradar.commands.agent.list_prs import cmd_list_prs
from prradar.domain.github import PullRequest, Repository
from prradar.services.phase_sequencer import GH_PR_FILENAME, GH_REPO_FILENAME


def _make_pr(number: int, title: str = "Test PR") -> PullRequest:
    """Create a PullRequest with raw_json populated via from_dict."""
    return PullRequest.from_dict({
        "number": number,
        "title": title,
        "state": "OPEN",
        "author": {"login": "testuser"},
    })


def _make_repo(name: str = "testrepo") -> Repository:
    """Create a Repository with raw_json populated via from_dict."""
    return Repository.from_dict({
        "name": name,
        "owner": {"login": "testowner"},
        "url": f"https://github.com/testowner/{name}",
        "defaultBranchRef": {"name": "main"},
    })


class TestCmdListPrs(unittest.TestCase):
    """Tests for cmd_list_prs function."""

    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.output_dir = self.tmp.name
        self.mock_gh = MagicMock()

    def tearDown(self):
        self.tmp.cleanup()

    def _patch_gh(self):
        return patch(
            "prradar.commands.agent.list_prs.GhCommandRunner",
            return_value=self.mock_gh,
        )

    def test_writes_pr_metadata_to_correct_directory(self):
        pr = _make_pr(42, "Add feature")
        repo = _make_repo()
        self.mock_gh.list_pull_requests.return_value = (True, [pr])
        self.mock_gh.get_repository.return_value = (True, repo)

        with self._patch_gh():
            result = cmd_list_prs(self.output_dir)

        pr_file = Path(self.output_dir) / "42" / "phase-1-pull-request" / GH_PR_FILENAME
        self.assertTrue(pr_file.exists())
        data = json.loads(pr_file.read_text())
        self.assertEqual(data["number"], 42)
        self.assertEqual(data["title"], "Add feature")
        self.assertEqual(result, 0)

    def test_writes_repo_metadata_for_each_pr(self):
        prs = [_make_pr(1), _make_pr(2)]
        repo = _make_repo("myrepo")
        self.mock_gh.list_pull_requests.return_value = (True, prs)
        self.mock_gh.get_repository.return_value = (True, repo)

        with self._patch_gh():
            cmd_list_prs(self.output_dir)

        for pr_num in [1, 2]:
            repo_file = Path(self.output_dir) / str(pr_num) / "phase-1-pull-request" / GH_REPO_FILENAME
            self.assertTrue(repo_file.exists())
            data = json.loads(repo_file.read_text())
            self.assertEqual(data["name"], "myrepo")

    def test_passes_limit_and_state_to_runner(self):
        self.mock_gh.list_pull_requests.return_value = (True, [])

        with self._patch_gh():
            cmd_list_prs(self.output_dir, limit=10, state="closed")

        self.mock_gh.list_pull_requests.assert_called_once_with(limit=10, state="closed", repo=None)

    def test_uses_default_limit_and_state(self):
        self.mock_gh.list_pull_requests.return_value = (True, [])

        with self._patch_gh():
            cmd_list_prs(self.output_dir)

        self.mock_gh.list_pull_requests.assert_called_once_with(limit=50, state="open", repo=None)

    def test_passes_repo_to_runner(self):
        self.mock_gh.list_pull_requests.return_value = (True, [])

        with self._patch_gh():
            cmd_list_prs(self.output_dir, repo="owner/repo")

        self.mock_gh.list_pull_requests.assert_called_once_with(limit=50, state="open", repo="owner/repo")

    def test_returns_zero_for_empty_pr_list(self):
        self.mock_gh.list_pull_requests.return_value = (True, [])

        with self._patch_gh():
            result = cmd_list_prs(self.output_dir)

        self.assertEqual(result, 0)
        self.mock_gh.get_repository.assert_not_called()

    def test_returns_one_when_pr_list_fails(self):
        self.mock_gh.list_pull_requests.return_value = (False, "gh: not logged in")

        with self._patch_gh():
            result = cmd_list_prs(self.output_dir)

        self.assertEqual(result, 1)
        self.mock_gh.get_repository.assert_not_called()

    def test_returns_one_when_repo_fetch_fails(self):
        self.mock_gh.list_pull_requests.return_value = (True, [_make_pr(1)])
        self.mock_gh.get_repository.return_value = (False, "repo not found")

        with self._patch_gh():
            result = cmd_list_prs(self.output_dir)

        self.assertEqual(result, 1)

    def test_multiple_prs_each_get_own_directory(self):
        prs = [_make_pr(10), _make_pr(20), _make_pr(30)]
        repo = _make_repo()
        self.mock_gh.list_pull_requests.return_value = (True, prs)
        self.mock_gh.get_repository.return_value = (True, repo)

        with self._patch_gh():
            result = cmd_list_prs(self.output_dir)

        self.assertEqual(result, 0)
        for pr_num in [10, 20, 30]:
            pr_dir = Path(self.output_dir) / str(pr_num) / "phase-1-pull-request"
            self.assertTrue(pr_dir.is_dir())
            self.assertTrue((pr_dir / GH_PR_FILENAME).exists())
            self.assertTrue((pr_dir / GH_REPO_FILENAME).exists())

    def test_saved_pr_json_is_parseable_back_to_domain_model(self):
        pr = _make_pr(99, "Roundtrip test")
        repo = _make_repo()
        self.mock_gh.list_pull_requests.return_value = (True, [pr])
        self.mock_gh.get_repository.return_value = (True, repo)

        with self._patch_gh():
            cmd_list_prs(self.output_dir)

        pr_file = Path(self.output_dir) / "99" / "phase-1-pull-request" / GH_PR_FILENAME
        restored = PullRequest.from_file(pr_file)
        self.assertEqual(restored.number, 99)
        self.assertEqual(restored.title, "Roundtrip test")

    def test_saved_repo_json_is_parseable_back_to_domain_model(self):
        pr = _make_pr(1)
        repo = _make_repo("roundtrip-repo")
        self.mock_gh.list_pull_requests.return_value = (True, [pr])
        self.mock_gh.get_repository.return_value = (True, repo)

        with self._patch_gh():
            cmd_list_prs(self.output_dir)

        repo_file = Path(self.output_dir) / "1" / "phase-1-pull-request" / GH_REPO_FILENAME
        restored = Repository.from_file(repo_file)
        self.assertEqual(restored.name, "roundtrip-repo")
        self.assertEqual(restored.full_name, "testowner/roundtrip-repo")


if __name__ == "__main__":
    unittest.main()
