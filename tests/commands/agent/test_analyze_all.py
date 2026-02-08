"""Tests for the agent analyze-all command.

Tests cover:
- Search query construction from --since date
- Per-PR cmd_analyze calls with correct parameters
- comment=False (default) results in dry_run=True, interactive=False
- comment=True results in dry_run=False, interactive=False
- Failure in one PR doesn't stop processing of remaining PRs
- Aggregate exit code reflects any failures
- Default state is 'all'
"""

import unittest
from unittest.mock import MagicMock, call, patch

from prradar.commands.agent.analyze_all import cmd_analyze_all
from prradar.domain.diff_source import DiffSource
from prradar.domain.github import PullRequest


def _make_pr(number: int, title: str = "Test PR") -> PullRequest:
    """Create a PullRequest with raw_json populated via from_dict."""
    return PullRequest.from_dict({
        "number": number,
        "title": title,
        "state": "OPEN",
        "author": {"login": "testuser"},
    })


class TestCmdAnalyzeAll(unittest.TestCase):
    """Tests for cmd_analyze_all function."""

    def setUp(self):
        self.mock_gh = MagicMock()
        self.gh_patcher = patch(
            "prradar.commands.agent.analyze_all.GhCommandRunner",
            return_value=self.mock_gh,
        )
        self.gh_patcher.start()

        self.analyze_patcher = patch(
            "prradar.commands.agent.analyze_all.cmd_analyze",
        )
        self.mock_analyze = self.analyze_patcher.start()
        self.mock_analyze.return_value = 0

        self.ensure_dir_patcher = patch(
            "prradar.commands.agent.analyze_all.ensure_output_dir",
            side_effect=lambda output_dir, pr_number: f"{output_dir}/{pr_number}",
        )
        self.mock_ensure_dir = self.ensure_dir_patcher.start()

    def tearDown(self):
        self.gh_patcher.stop()
        self.analyze_patcher.stop()
        self.ensure_dir_patcher.stop()

    def test_passes_correct_search_query_to_list_pull_requests(self):
        self.mock_gh.list_pull_requests.return_value = (True, [])

        cmd_analyze_all(
            output_dir="/tmp/out",
            since="2025-06-15",
            rules_dir="rules",
            repo="owner/repo",
        )

        self.mock_gh.list_pull_requests.assert_called_once_with(
            limit=50,
            state="all",
            search="created:>=2025-06-15",
            repo="owner/repo",
        )

    def test_each_pr_triggers_cmd_analyze_with_correct_params(self):
        prs = [_make_pr(10, "First"), _make_pr(20, "Second")]
        self.mock_gh.list_pull_requests.return_value = (True, prs)

        cmd_analyze_all(
            output_dir="/tmp/out",
            since="2025-01-01",
            rules_dir="my-rules",
            repo="owner/repo",
            min_score=3,
            source=DiffSource.GITHUB,
            repo_path="/code",
        )

        self.assertEqual(self.mock_analyze.call_count, 2)
        self.mock_analyze.assert_any_call(
            pr_number=10,
            output_dir="/tmp/out/10",
            rules_dir="my-rules",
            repo="owner/repo",
            interactive=False,
            dry_run=True,
            stop_after=None,
            skip_to=None,
            min_score=3,
            source=DiffSource.GITHUB,
            repo_path="/code",
        )
        self.mock_analyze.assert_any_call(
            pr_number=20,
            output_dir="/tmp/out/20",
            rules_dir="my-rules",
            repo="owner/repo",
            interactive=False,
            dry_run=True,
            stop_after=None,
            skip_to=None,
            min_score=3,
            source=DiffSource.GITHUB,
            repo_path="/code",
        )

    def test_comment_false_sets_dry_run_true(self):
        self.mock_gh.list_pull_requests.return_value = (True, [_make_pr(1)])

        cmd_analyze_all(
            output_dir="/tmp/out",
            since="2025-01-01",
            rules_dir="rules",
            repo="owner/repo",
            comment=False,
        )

        _, kwargs = self.mock_analyze.call_args
        self.assertTrue(kwargs["dry_run"])
        self.assertFalse(kwargs["interactive"])

    def test_comment_true_sets_dry_run_false(self):
        self.mock_gh.list_pull_requests.return_value = (True, [_make_pr(1)])

        cmd_analyze_all(
            output_dir="/tmp/out",
            since="2025-01-01",
            rules_dir="rules",
            repo="owner/repo",
            comment=True,
        )

        _, kwargs = self.mock_analyze.call_args
        self.assertFalse(kwargs["dry_run"])
        self.assertFalse(kwargs["interactive"])

    def test_failure_in_one_pr_does_not_stop_remaining(self):
        prs = [_make_pr(1), _make_pr(2), _make_pr(3)]
        self.mock_gh.list_pull_requests.return_value = (True, prs)
        self.mock_analyze.side_effect = [
            0,
            Exception("API timeout"),
            0,
        ]

        cmd_analyze_all(
            output_dir="/tmp/out",
            since="2025-01-01",
            rules_dir="rules",
            repo="owner/repo",
        )

        self.assertEqual(self.mock_analyze.call_count, 3)

    def test_nonzero_exit_code_tracked_as_failure(self):
        prs = [_make_pr(1), _make_pr(2)]
        self.mock_gh.list_pull_requests.return_value = (True, prs)
        self.mock_analyze.side_effect = [1, 0]

        result = cmd_analyze_all(
            output_dir="/tmp/out",
            since="2025-01-01",
            rules_dir="rules",
            repo="owner/repo",
        )

        self.assertEqual(result, 1)

    def test_returns_zero_when_all_succeed(self):
        prs = [_make_pr(1), _make_pr(2)]
        self.mock_gh.list_pull_requests.return_value = (True, prs)
        self.mock_analyze.return_value = 0

        result = cmd_analyze_all(
            output_dir="/tmp/out",
            since="2025-01-01",
            rules_dir="rules",
            repo="owner/repo",
        )

        self.assertEqual(result, 0)

    def test_returns_one_when_any_fail(self):
        prs = [_make_pr(1), _make_pr(2), _make_pr(3)]
        self.mock_gh.list_pull_requests.return_value = (True, prs)
        self.mock_analyze.side_effect = [0, Exception("boom"), 0]

        result = cmd_analyze_all(
            output_dir="/tmp/out",
            since="2025-01-01",
            rules_dir="rules",
            repo="owner/repo",
        )

        self.assertEqual(result, 1)

    def test_default_state_is_all(self):
        self.mock_gh.list_pull_requests.return_value = (True, [])

        cmd_analyze_all(
            output_dir="/tmp/out",
            since="2025-01-01",
            rules_dir="rules",
            repo="owner/repo",
        )

        _, kwargs = self.mock_gh.list_pull_requests.call_args
        self.assertEqual(kwargs["state"], "all")

    def test_returns_zero_for_empty_pr_list(self):
        self.mock_gh.list_pull_requests.return_value = (True, [])

        result = cmd_analyze_all(
            output_dir="/tmp/out",
            since="2025-01-01",
            rules_dir="rules",
            repo="owner/repo",
        )

        self.assertEqual(result, 0)
        self.mock_analyze.assert_not_called()

    def test_returns_one_when_pr_list_fetch_fails(self):
        self.mock_gh.list_pull_requests.return_value = (False, "gh: not logged in")

        result = cmd_analyze_all(
            output_dir="/tmp/out",
            since="2025-01-01",
            rules_dir="rules",
            repo="owner/repo",
        )

        self.assertEqual(result, 1)
        self.mock_analyze.assert_not_called()

    def test_custom_limit_and_state_passed_through(self):
        self.mock_gh.list_pull_requests.return_value = (True, [])

        cmd_analyze_all(
            output_dir="/tmp/out",
            since="2025-01-01",
            rules_dir="rules",
            repo="owner/repo",
            limit=10,
            state="open",
        )

        self.mock_gh.list_pull_requests.assert_called_once_with(
            limit=10,
            state="open",
            search="created:>=2025-01-01",
            repo="owner/repo",
        )

    def test_creates_output_dir_per_pr(self):
        prs = [_make_pr(5), _make_pr(15)]
        self.mock_gh.list_pull_requests.return_value = (True, prs)

        cmd_analyze_all(
            output_dir="/tmp/out",
            since="2025-01-01",
            rules_dir="rules",
            repo="owner/repo",
        )

        self.mock_ensure_dir.assert_any_call("/tmp/out", 5)
        self.mock_ensure_dir.assert_any_call("/tmp/out", 15)


if __name__ == "__main__":
    unittest.main()
