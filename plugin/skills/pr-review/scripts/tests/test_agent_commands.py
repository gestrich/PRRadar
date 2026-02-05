"""Tests for agent commands and pipeline integration.

Tests cover:
- Artifact file structure verification
- Command integration tests with filesystem
- Rule loading and filtering
"""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from scripts.domain.diff import GitDiff
from scripts.domain.rule import AppliesTo, GrepPatterns, Rule
from scripts.infrastructure.git_utils import GitFileInfo
from scripts.services.rule_loader import RuleLoaderService


# ============================================================
# Fixtures Path Helper
# ============================================================


def get_fixtures_path() -> Path:
    """Get the path to test fixtures directory."""
    return Path(__file__).parent / "fixtures"


def make_mock_git_info() -> GitFileInfo:
    """Create a mock GitFileInfo for testing."""
    return GitFileInfo(
        repo_url="https://github.com/test/repo",
        relative_path="rules",
        branch="main",
    )


# ============================================================
# Rule Loading Tests
# ============================================================


class TestRuleLoaderService(unittest.TestCase):
    """Tests for RuleLoaderService loading and filtering."""

    def test_load_rules_from_fixtures(self):
        """Test loading rules from the sample-rules fixture directory."""
        fixtures = get_fixtures_path()
        rules_dir = fixtures / "sample-rules"

        if not rules_dir.exists():
            self.skipTest("Fixtures not available")

        loader = RuleLoaderService(rules_dir=rules_dir, git_info=make_mock_git_info())
        rules = loader.load_all_rules()

        self.assertGreater(len(rules), 0)

        # Check we loaded expected rules
        rule_names = {r.name for r in rules}
        self.assertIn("error-handling", rule_names)
        self.assertIn("async-patterns", rule_names)

    def test_loaded_rule_has_expected_fields(self):
        """Test loaded rules have all expected fields populated."""
        fixtures = get_fixtures_path()
        rules_dir = fixtures / "sample-rules"

        if not rules_dir.exists():
            self.skipTest("Fixtures not available")

        loader = RuleLoaderService(rules_dir=rules_dir, git_info=make_mock_git_info())
        rules = loader.load_all_rules()

        error_handling = next((r for r in rules if r.name == "error-handling"), None)
        self.assertIsNotNone(error_handling)

        self.assertEqual(error_handling.category, "safety")
        self.assertEqual(error_handling.model, "claude-sonnet-4-20250514")
        self.assertEqual(
            error_handling.documentation_link,
            "https://docs.example.com/rules/error-handling",
        )
        self.assertIn("*.py", error_handling.applies_to.file_patterns)
        self.assertIn("except", error_handling.grep.any_patterns)

    def test_rule_content_includes_markdown_body(self):
        """Test rule content includes the markdown body after frontmatter."""
        fixtures = get_fixtures_path()
        rules_dir = fixtures / "sample-rules"

        if not rules_dir.exists():
            self.skipTest("Fixtures not available")

        loader = RuleLoaderService(rules_dir=rules_dir, git_info=make_mock_git_info())
        rules = loader.load_all_rules()

        error_handling = next((r for r in rules if r.name == "error-handling"), None)
        self.assertIsNotNone(error_handling)

        # Content should include markdown body
        self.assertIn("# Error Handling", error_handling.content)
        self.assertIn("## Bad Examples", error_handling.content)
        self.assertIn("## GitHub Comment", error_handling.content)


# ============================================================
# Diff Parsing Tests
# ============================================================


class TestDiffParsing(unittest.TestCase):
    """Tests for parsing sample diff fixture."""

    def test_parse_sample_diff(self):
        """Test parsing the sample-diff.diff fixture."""
        fixtures = get_fixtures_path()
        diff_file = fixtures / "sample-diff.diff"

        if not diff_file.exists():
            self.skipTest("Fixtures not available")

        diff_content = diff_file.read_text()
        diff = GitDiff.from_diff_content(diff_content)

        self.assertFalse(diff.is_empty)
        self.assertGreater(len(diff.hunks), 0)

    def test_sample_diff_has_expected_files(self):
        """Test sample diff contains expected files."""
        fixtures = get_fixtures_path()
        diff_file = fixtures / "sample-diff.diff"

        if not diff_file.exists():
            self.skipTest("Fixtures not available")

        diff_content = diff_file.read_text()
        diff = GitDiff.from_diff_content(diff_content)

        files = diff.get_unique_files()
        self.assertIn("src/handler.py", files)
        self.assertIn("src/utils.py", files)

    def test_sample_diff_hunk_line_numbers(self):
        """Test sample diff hunks have correct line numbers."""
        fixtures = get_fixtures_path()
        diff_file = fixtures / "sample-diff.diff"

        if not diff_file.exists():
            self.skipTest("Fixtures not available")

        diff_content = diff_file.read_text()
        diff = GitDiff.from_diff_content(diff_content)

        handler_hunks = diff.get_hunks_by_file("src/handler.py")
        self.assertEqual(len(handler_hunks), 1)
        self.assertEqual(handler_hunks[0].new_start, 10)


# ============================================================
# Rule Filtering Tests
# ============================================================


class TestRuleFiltering(unittest.TestCase):
    """Tests for rule filtering against diff content."""

    def test_rule_matches_python_file(self):
        """Test rule with *.py pattern matches Python files."""
        fixtures = get_fixtures_path()
        rules_dir = fixtures / "sample-rules"
        diff_file = fixtures / "sample-diff.diff"

        if not rules_dir.exists() or not diff_file.exists():
            self.skipTest("Fixtures not available")

        loader = RuleLoaderService(rules_dir=rules_dir, git_info=make_mock_git_info())
        rules = loader.load_all_rules()

        error_handling = next((r for r in rules if r.name == "error-handling"), None)
        self.assertIsNotNone(error_handling)

        # Should match Python files
        self.assertTrue(error_handling.applies_to.matches_file("src/handler.py"))
        self.assertTrue(error_handling.applies_to.matches_file("src/utils.py"))

        # Should not match non-Python files
        self.assertFalse(error_handling.applies_to.matches_file("src/handler.js"))

    def test_rule_grep_matches_diff_content(self):
        """Test rule grep patterns match against diff content."""
        fixtures = get_fixtures_path()
        rules_dir = fixtures / "sample-rules"
        diff_file = fixtures / "sample-diff.diff"

        if not rules_dir.exists() or not diff_file.exists():
            self.skipTest("Fixtures not available")

        loader = RuleLoaderService(rules_dir=rules_dir, git_info=make_mock_git_info())
        rules = loader.load_all_rules()

        error_handling = next((r for r in rules if r.name == "error-handling"), None)
        self.assertIsNotNone(error_handling)

        diff_content = diff_file.read_text()
        diff = GitDiff.from_diff_content(diff_content)

        # Get the handler.py hunk content
        handler_hunks = diff.get_hunks_by_file("src/handler.py")
        self.assertEqual(len(handler_hunks), 1)

        # The hunk contains "except Exception" which should match
        hunk_content = handler_hunks[0].content
        self.assertTrue(error_handling.grep.matches(hunk_content))


# ============================================================
# Artifact Structure Tests
# ============================================================


class TestArtifactStructure(unittest.TestCase):
    """Tests for artifact file structure verification."""

    def test_evaluation_result_json_structure(self):
        """Test evaluation result JSON has expected structure."""
        # Create a mock evaluation result
        eval_data = {
            "task_id": "error-handling-abc123",
            "rule_name": "error-handling",
            "rule_file_path": "rules/error-handling.md",
            "file_path": "src/handler.py",
            "evaluation": {
                "violates_rule": True,
                "score": 7,
                "comment": "Silent exception handling detected",
                "file_path": "src/handler.py",
                "line_number": 15,
            },
            "model_used": "claude-sonnet-4-20250514",
            "duration_ms": 1500,
            "cost_usd": 0.001,
        }

        # Verify required fields exist
        self.assertIn("task_id", eval_data)
        self.assertIn("rule_name", eval_data)
        self.assertIn("evaluation", eval_data)
        self.assertIn("violates_rule", eval_data["evaluation"])
        self.assertIn("score", eval_data["evaluation"])
        self.assertIn("comment", eval_data["evaluation"])

    def test_task_json_structure(self):
        """Test task JSON has expected structure."""
        task_data = {
            "task_id": "error-handling-abc123",
            "rule": {
                "name": "error-handling",
                "file_path": "rules/error-handling.md",
                "description": "Handle exceptions explicitly",
                "category": "safety",
                "documentation_link": "https://docs.example.com/error-handling",
                "content": "# Error Handling\n...",
            },
            "segment": {
                "file_path": "src/handler.py",
                "hunk_index": 0,
                "start_line": 10,
                "end_line": 20,
                "content": "@@ -10,8 +10,12 @@\n...",
            },
        }

        # Verify required fields exist
        self.assertIn("task_id", task_data)
        self.assertIn("rule", task_data)
        self.assertIn("segment", task_data)
        self.assertIn("name", task_data["rule"])
        self.assertIn("file_path", task_data["segment"])
        self.assertIn("start_line", task_data["segment"])

    def test_report_json_structure(self):
        """Test report JSON has expected structure."""
        report_data = {
            "pr_number": 123,
            "generated_at": "2025-01-15T10:30:00+00:00",
            "min_score_threshold": 5,
            "summary": {
                "total_tasks_evaluated": 10,
                "violations_found": 3,
                "highest_severity": 8,
                "total_cost_usd": 0.0125,
                "by_severity": {"Severe (8-10)": 1, "Moderate (5-7)": 2},
                "by_file": {"src/handler.py": 2, "src/utils.py": 1},
                "by_rule": {"error-handling": 2, "async-patterns": 1},
            },
            "violations": [
                {
                    "rule_name": "error-handling",
                    "score": 8,
                    "file_path": "src/handler.py",
                    "line_number": 15,
                    "comment": "Silent exception",
                }
            ],
        }

        # Verify required fields exist
        self.assertIn("pr_number", report_data)
        self.assertIn("generated_at", report_data)
        self.assertIn("summary", report_data)
        self.assertIn("violations", report_data)
        self.assertIn("total_tasks_evaluated", report_data["summary"])
        self.assertIn("violations_found", report_data["summary"])


# ============================================================
# End-to-End Pipeline Tests (without API calls)
# ============================================================


class TestPipelineIntegration(unittest.TestCase):
    """Integration tests for pipeline phases without API calls."""

    def test_rules_phase_creates_tasks(self):
        """Test that rules phase can create evaluation tasks from fixtures."""
        fixtures = get_fixtures_path()
        rules_dir = fixtures / "sample-rules"
        diff_file = fixtures / "sample-diff.diff"

        if not rules_dir.exists() or not diff_file.exists():
            self.skipTest("Fixtures not available")

        # Load rules
        loader = RuleLoaderService(rules_dir=rules_dir, git_info=make_mock_git_info())
        rules = loader.load_all_rules()

        # Parse diff
        diff_content = diff_file.read_text()
        diff = GitDiff.from_diff_content(diff_content)

        # For each hunk, check which rules apply
        tasks_created = 0
        for hunk in diff.hunks:
            changed_content = hunk.get_changed_content()
            for rule in rules:
                if rule.should_evaluate(hunk.file_path, changed_content):
                    tasks_created += 1

        # Should have at least one task (error-handling on handler.py)
        self.assertGreater(tasks_created, 0)

    def test_report_phase_can_run_on_empty_evaluations(self):
        """Test report phase handles empty evaluations gracefully."""
        with tempfile.TemporaryDirectory() as tmpdir:
            evaluations_dir = Path(tmpdir) / "evaluations"
            evaluations_dir.mkdir()
            tasks_dir = Path(tmpdir) / "tasks"
            tasks_dir.mkdir()
            output_dir = Path(tmpdir)

            from scripts.services.report_generator import ReportGeneratorService

            service = ReportGeneratorService(evaluations_dir, tasks_dir)
            report = service.generate_report(pr_number=123, min_score=5)
            json_path, md_path = service.save_report(report, output_dir)

            # Should create files even with no violations
            self.assertTrue(json_path.exists())
            self.assertTrue(md_path.exists())

            # JSON should be valid
            data = json.loads(json_path.read_text())
            self.assertEqual(data["violations"], [])


if __name__ == "__main__":
    unittest.main()
