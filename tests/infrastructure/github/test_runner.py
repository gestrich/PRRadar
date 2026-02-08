"""Tests for GhCommandRunner.list_pull_requests method.

Tests cover:
- Correct gh CLI command construction
- JSON parsing into PullRequest domain objects
- Limit and state parameter handling
- Error propagation from failed commands
"""

import json
import unittest
from unittest.mock import MagicMock, patch

from prradar.infrastructure.github.runner import GhCommandRunner, _PR_FIELDS


class TestListPullRequests(unittest.TestCase):
    """Tests for GhCommandRunner.list_pull_requests."""

    def setUp(self):
        self.runner = GhCommandRunner()

    def test_constructs_correct_gh_command(self):
        with patch.object(self.runner, "run", return_value=(True, "[]")) as mock_run:
            self.runner.list_pull_requests(limit=50, state="open")

        mock_run.assert_called_once_with([
            "gh", "pr", "list",
            "--json", ",".join(_PR_FIELDS),
            "--limit", "50",
            "--state", "open",
        ])

    def test_passes_custom_limit_and_state(self):
        with patch.object(self.runner, "run", return_value=(True, "[]")) as mock_run:
            self.runner.list_pull_requests(limit=10, state="closed")

        args = mock_run.call_args[0][0]
        self.assertIn("--limit", args)
        self.assertEqual(args[args.index("--limit") + 1], "10")
        self.assertIn("--state", args)
        self.assertEqual(args[args.index("--state") + 1], "closed")

    def test_parses_json_into_pull_request_list(self):
        pr_data = [
            {"number": 1, "title": "First PR", "state": "OPEN"},
            {"number": 2, "title": "Second PR", "state": "OPEN"},
        ]
        with patch.object(self.runner, "run", return_value=(True, json.dumps(pr_data))):
            success, result = self.runner.list_pull_requests(limit=50, state="open")

        self.assertTrue(success)
        self.assertEqual(len(result), 2)
        self.assertEqual(result[0].number, 1)
        self.assertEqual(result[0].title, "First PR")
        self.assertEqual(result[1].number, 2)
        self.assertEqual(result[1].title, "Second PR")

    def test_returns_empty_list_for_no_prs(self):
        with patch.object(self.runner, "run", return_value=(True, "[]")):
            success, result = self.runner.list_pull_requests(limit=50, state="open")

        self.assertTrue(success)
        self.assertEqual(result, [])

    def test_returns_error_on_command_failure(self):
        with patch.object(self.runner, "run", return_value=(False, "not logged in")):
            success, result = self.runner.list_pull_requests(limit=50, state="open")

        self.assertFalse(success)
        self.assertEqual(result, "not logged in")

    def test_preserves_raw_json_on_parsed_prs(self):
        pr_data = [{"number": 5, "title": "Raw JSON test", "author": {"login": "dev"}}]
        with patch.object(self.runner, "run", return_value=(True, json.dumps(pr_data))):
            success, result = self.runner.list_pull_requests(limit=50, state="open")

        self.assertTrue(success)
        raw = json.loads(result[0].raw_json)
        self.assertEqual(raw["number"], 5)
        self.assertEqual(raw["title"], "Raw JSON test")


if __name__ == "__main__":
    unittest.main()
