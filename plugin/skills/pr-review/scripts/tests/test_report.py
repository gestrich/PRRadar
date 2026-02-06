"""Tests for report generation functionality.

Tests cover:
- ViolationRecord domain model
- ReportSummary calculation
- ReviewReport generation and serialization
- ReportGeneratorService loading and aggregation
"""

from __future__ import annotations

import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from scripts.domain.report import ReportSummary, ReviewReport, ViolationRecord
from scripts.services.phase_sequencer import PhaseSequencer, PipelinePhase
from scripts.services.report_generator import ReportGeneratorService


# ============================================================
# ViolationRecord Tests
# ============================================================


class TestViolationRecord(unittest.TestCase):
    """Tests for ViolationRecord domain model."""

    def test_to_dict_includes_required_fields(self):
        """Test to_dict includes all required fields."""
        violation = ViolationRecord(
            rule_name="error-handling",
            score=7,
            file_path="src/handler.py",
            line_number=42,
            comment="Silent exception handling detected",
        )

        data = violation.to_dict()

        self.assertEqual(data["rule_name"], "error-handling")
        self.assertEqual(data["score"], 7)
        self.assertEqual(data["file_path"], "src/handler.py")
        self.assertEqual(data["line_number"], 42)
        self.assertEqual(data["comment"], "Silent exception handling detected")

    def test_to_dict_includes_optional_fields_when_set(self):
        """Test to_dict includes optional fields when present."""
        violation = ViolationRecord(
            rule_name="error-handling",
            score=7,
            file_path="src/handler.py",
            line_number=42,
            comment="Test comment",
            documentation_link="https://docs.example.com/error-handling",
            relevant_claude_skill="fix-errors",
        )

        data = violation.to_dict()

        self.assertEqual(data["documentation_link"], "https://docs.example.com/error-handling")
        self.assertEqual(data["relevant_claude_skill"], "fix-errors")

    def test_to_dict_excludes_optional_fields_when_none(self):
        """Test to_dict excludes optional fields when None."""
        violation = ViolationRecord(
            rule_name="test-rule",
            score=5,
            file_path="test.py",
            line_number=10,
            comment="Test",
        )

        data = violation.to_dict()

        self.assertNotIn("documentation_link", data)
        self.assertNotIn("relevant_claude_skill", data)

    def test_from_dict_parses_all_fields(self):
        """Test from_dict parses all fields correctly."""
        data = {
            "rule_name": "async-patterns",
            "score": 6,
            "file_path": "src/api.py",
            "line_number": 25,
            "comment": "Missing await",
            "documentation_link": "https://docs.example.com/async",
            "relevant_claude_skill": "async-helper",
        }

        violation = ViolationRecord.from_dict(data)

        self.assertEqual(violation.rule_name, "async-patterns")
        self.assertEqual(violation.score, 6)
        self.assertEqual(violation.file_path, "src/api.py")
        self.assertEqual(violation.line_number, 25)
        self.assertEqual(violation.comment, "Missing await")
        self.assertEqual(violation.documentation_link, "https://docs.example.com/async")
        self.assertEqual(violation.relevant_claude_skill, "async-helper")

    def test_from_dict_handles_missing_optional_fields(self):
        """Test from_dict handles missing optional fields."""
        data = {
            "rule_name": "test-rule",
            "score": 5,
            "file_path": "test.py",
            "line_number": None,
            "comment": "Test",
        }

        violation = ViolationRecord.from_dict(data)

        self.assertIsNone(violation.documentation_link)
        self.assertIsNone(violation.relevant_claude_skill)

    def test_to_dict_includes_method_name_when_set(self):
        """Test to_dict includes method_name when present."""
        violation = ViolationRecord(
            rule_name="error-handling",
            score=7,
            file_path="src/handler.py",
            line_number=42,
            comment="Test comment",
            method_name="login(username, password)",
        )

        data = violation.to_dict()

        self.assertEqual(data["method_name"], "login(username, password)")

    def test_to_dict_excludes_method_name_when_none(self):
        """Test to_dict excludes method_name when None."""
        violation = ViolationRecord(
            rule_name="test-rule",
            score=5,
            file_path="test.py",
            line_number=10,
            comment="Test",
        )

        data = violation.to_dict()

        self.assertNotIn("method_name", data)

    def test_from_dict_parses_method_name(self):
        """Test from_dict parses method_name field."""
        data = {
            "rule_name": "test-rule",
            "score": 6,
            "file_path": "src/api.py",
            "line_number": 25,
            "comment": "Issue found",
            "method_name": "validate_token(token)",
        }

        violation = ViolationRecord.from_dict(data)

        self.assertEqual(violation.method_name, "validate_token(token)")

    def test_from_dict_handles_missing_method_name(self):
        """Test from_dict handles missing method_name."""
        data = {
            "rule_name": "test-rule",
            "score": 5,
            "file_path": "test.py",
            "line_number": 10,
            "comment": "Test",
        }

        violation = ViolationRecord.from_dict(data)

        self.assertIsNone(violation.method_name)

    def test_round_trip_serialization(self):
        """Test to_dict/from_dict round-trip preserves data."""
        original = ViolationRecord(
            rule_name="error-handling",
            score=8,
            file_path="src/handler.py",
            line_number=42,
            comment="Critical issue",
            method_name="handle_request()",
            documentation_link="https://docs.example.com",
        )

        restored = ViolationRecord.from_dict(original.to_dict())

        self.assertEqual(restored.rule_name, original.rule_name)
        self.assertEqual(restored.score, original.score)
        self.assertEqual(restored.file_path, original.file_path)
        self.assertEqual(restored.line_number, original.line_number)
        self.assertEqual(restored.comment, original.comment)
        self.assertEqual(restored.method_name, original.method_name)
        self.assertEqual(restored.documentation_link, original.documentation_link)


# ============================================================
# ReportSummary Tests
# ============================================================


class TestReportSummary(unittest.TestCase):
    """Tests for ReportSummary domain model."""

    def test_to_dict_serializes_all_fields(self):
        """Test to_dict serializes all summary fields."""
        summary = ReportSummary(
            total_tasks_evaluated=10,
            violations_found=3,
            highest_severity=8,
            total_cost_usd=0.0125,
            by_severity={"Severe (8-10)": 1, "Moderate (5-7)": 2},
            by_file={"src/handler.py": 2, "src/utils.py": 1},
            by_rule={"error-handling": 2, "async-patterns": 1},
        )

        data = summary.to_dict()

        self.assertEqual(data["total_tasks_evaluated"], 10)
        self.assertEqual(data["violations_found"], 3)
        self.assertEqual(data["highest_severity"], 8)
        self.assertEqual(data["total_cost_usd"], 0.0125)
        self.assertEqual(data["by_severity"]["Severe (8-10)"], 1)
        self.assertEqual(data["by_file"]["src/handler.py"], 2)
        self.assertEqual(data["by_rule"]["error-handling"], 2)

    def test_to_dict_handles_empty_breakdowns(self):
        """Test to_dict handles empty breakdown dictionaries."""
        summary = ReportSummary(
            total_tasks_evaluated=5,
            violations_found=0,
            highest_severity=0,
            total_cost_usd=0.005,
        )

        data = summary.to_dict()

        self.assertEqual(data["by_severity"], {})
        self.assertEqual(data["by_file"], {})
        self.assertEqual(data["by_rule"], {})
        self.assertNotIn("by_method", data)

    def test_to_dict_includes_by_method_when_present(self):
        """Test to_dict includes by_method when populated."""
        summary = ReportSummary(
            total_tasks_evaluated=5,
            violations_found=2,
            highest_severity=8,
            total_cost_usd=0.005,
            by_method={
                "src/auth.py": {
                    "login(username, password)": [
                        {"rule": "error-handling", "score": 8},
                    ],
                    "validate_token(token)": [
                        {"rule": "hardcoded-secrets", "score": 10},
                    ],
                },
            },
        )

        data = summary.to_dict()

        self.assertIn("by_method", data)
        self.assertIn("src/auth.py", data["by_method"])
        self.assertEqual(len(data["by_method"]["src/auth.py"]), 2)
        self.assertEqual(
            data["by_method"]["src/auth.py"]["login(username, password)"][0]["rule"],
            "error-handling",
        )


# ============================================================
# ReviewReport Tests
# ============================================================


class TestReviewReport(unittest.TestCase):
    """Tests for ReviewReport domain model."""

    def test_to_dict_serializes_complete_report(self):
        """Test to_dict serializes the complete report."""
        violations = [
            ViolationRecord(
                rule_name="error-handling",
                score=8,
                file_path="src/handler.py",
                line_number=42,
                comment="Silent exception",
            ),
        ]
        summary = ReportSummary(
            total_tasks_evaluated=5,
            violations_found=1,
            highest_severity=8,
            total_cost_usd=0.005,
            by_severity={"Severe (8-10)": 1},
            by_file={"src/handler.py": 1},
            by_rule={"error-handling": 1},
        )
        report = ReviewReport(
            pr_number=123,
            generated_at=datetime(2025, 1, 15, 10, 30, 0, tzinfo=timezone.utc),
            min_score_threshold=5,
            summary=summary,
            violations=violations,
        )

        data = report.to_dict()

        self.assertEqual(data["pr_number"], 123)
        self.assertEqual(data["generated_at"], "2025-01-15T10:30:00+00:00")
        self.assertEqual(data["min_score_threshold"], 5)
        self.assertEqual(data["summary"]["violations_found"], 1)
        self.assertEqual(len(data["violations"]), 1)

    def test_to_markdown_includes_header(self):
        """Test to_markdown includes header with PR number."""
        report = ReviewReport(
            pr_number=456,
            generated_at=datetime(2025, 1, 15, 10, 30, 0, tzinfo=timezone.utc),
            min_score_threshold=5,
            summary=ReportSummary(
                total_tasks_evaluated=0,
                violations_found=0,
                highest_severity=0,
                total_cost_usd=0,
            ),
            violations=[],
        )

        md = report.to_markdown()

        self.assertIn("# Code Review Report: PR #456", md)
        self.assertIn("Minimum Score Threshold: 5", md)

    def test_to_markdown_includes_summary_section(self):
        """Test to_markdown includes summary statistics."""
        summary = ReportSummary(
            total_tasks_evaluated=10,
            violations_found=3,
            highest_severity=9,
            total_cost_usd=0.0125,
        )
        report = ReviewReport(
            pr_number=123,
            generated_at=datetime.now(timezone.utc),
            min_score_threshold=5,
            summary=summary,
            violations=[],
        )

        md = report.to_markdown()

        self.assertIn("## Summary", md)
        self.assertIn("**Tasks Evaluated:** 10", md)
        self.assertIn("**Violations Found:** 3", md)
        self.assertIn("**Highest Severity:** 9", md)
        self.assertIn("**Total Cost:** $0.0125", md)

    def test_to_markdown_includes_severity_breakdown(self):
        """Test to_markdown includes severity breakdown table."""
        summary = ReportSummary(
            total_tasks_evaluated=10,
            violations_found=3,
            highest_severity=9,
            total_cost_usd=0.01,
            by_severity={"Severe (8-10)": 1, "Moderate (5-7)": 2},
        )
        report = ReviewReport(
            pr_number=123,
            generated_at=datetime.now(timezone.utc),
            min_score_threshold=5,
            summary=summary,
            violations=[],
        )

        md = report.to_markdown()

        self.assertIn("### By Severity", md)
        self.assertIn("| Severe (8-10) | 1 |", md)
        self.assertIn("| Moderate (5-7) | 2 |", md)

    def test_to_markdown_includes_violations_section(self):
        """Test to_markdown includes violations with details."""
        violations = [
            ViolationRecord(
                rule_name="error-handling",
                score=8,
                file_path="src/handler.py",
                line_number=42,
                comment="Silent exception handling detected",
                documentation_link="https://docs.example.com/error-handling",
            ),
        ]
        report = ReviewReport(
            pr_number=123,
            generated_at=datetime.now(timezone.utc),
            min_score_threshold=5,
            summary=ReportSummary(
                total_tasks_evaluated=5,
                violations_found=1,
                highest_severity=8,
                total_cost_usd=0.005,
            ),
            violations=violations,
        )

        md = report.to_markdown()

        self.assertIn("## Violations", md)
        self.assertIn("### 1. error-handling (Score: 8)", md)
        self.assertIn("**Location:** `src/handler.py:42`", md)
        self.assertIn("Silent exception handling detected", md)
        self.assertIn("[Documentation](https://docs.example.com/error-handling)", md)

    def test_to_markdown_includes_method_name_when_present(self):
        """Test to_markdown includes method name for violations with method info."""
        violations = [
            ViolationRecord(
                rule_name="error-handling",
                score=8,
                file_path="src/handler.py",
                line_number=42,
                comment="Silent exception handling detected",
                method_name="handle_request()",
            ),
        ]
        report = ReviewReport(
            pr_number=123,
            generated_at=datetime.now(timezone.utc),
            min_score_threshold=5,
            summary=ReportSummary(
                total_tasks_evaluated=5,
                violations_found=1,
                highest_severity=8,
                total_cost_usd=0.005,
            ),
            violations=violations,
        )

        md = report.to_markdown()

        self.assertIn("**Method:** `handle_request()`", md)

    def test_to_markdown_handles_no_violations(self):
        """Test to_markdown handles empty violations list."""
        report = ReviewReport(
            pr_number=123,
            generated_at=datetime.now(timezone.utc),
            min_score_threshold=5,
            summary=ReportSummary(
                total_tasks_evaluated=5,
                violations_found=0,
                highest_severity=0,
                total_cost_usd=0.005,
            ),
            violations=[],
        )

        md = report.to_markdown()

        self.assertIn("No violations found meeting the score threshold", md)


# ============================================================
# ReportGeneratorService Tests
# ============================================================


class TestReportGeneratorService(unittest.TestCase):
    """Tests for ReportGeneratorService."""

    def test_generate_report_with_no_evaluations(self):
        """Test generate_report handles empty evaluations directory."""
        with tempfile.TemporaryDirectory() as tmpdir:
            evaluations_dir = PhaseSequencer.ensure_phase_dir(Path(tmpdir), PipelinePhase.EVALUATIONS)
            tasks_dir = PhaseSequencer.ensure_phase_dir(Path(tmpdir), PipelinePhase.TASKS)

            service = ReportGeneratorService(evaluations_dir, tasks_dir)
            report = service.generate_report(pr_number=123, min_score=5)

            self.assertEqual(report.pr_number, 123)
            self.assertEqual(report.summary.total_tasks_evaluated, 0)
            self.assertEqual(report.summary.violations_found, 0)
            self.assertEqual(report.violations, [])

    def test_generate_report_filters_by_min_score(self):
        """Test generate_report filters violations by min_score."""
        with tempfile.TemporaryDirectory() as tmpdir:
            evaluations_dir = PhaseSequencer.ensure_phase_dir(Path(tmpdir), PipelinePhase.EVALUATIONS)
            tasks_dir = PhaseSequencer.ensure_phase_dir(Path(tmpdir), PipelinePhase.TASKS)

            # Create evaluations with different scores
            for i, score in enumerate([3, 5, 8]):
                eval_data = {
                    "task_id": f"task-{i}",
                    "rule_name": f"rule-{i}",
                    "file_path": "test.py",
                    "evaluation": {
                        "violates_rule": True,
                        "score": score,
                        "comment": f"Score {score} violation",
                        "file_path": "test.py",
                        "line_number": 10 + i,
                    },
                    "cost_usd": 0.001,
                }
                (evaluations_dir / f"task-{i}.json").write_text(
                    json.dumps(eval_data, indent=2)
                )

            service = ReportGeneratorService(evaluations_dir, tasks_dir)
            report = service.generate_report(pr_number=123, min_score=5)

            self.assertEqual(report.summary.total_tasks_evaluated, 3)
            self.assertEqual(report.summary.violations_found, 2)
            self.assertEqual(len(report.violations), 2)

            # Verify only score >= 5 are included
            scores = [v.score for v in report.violations]
            self.assertNotIn(3, scores)
            self.assertIn(5, scores)
            self.assertIn(8, scores)

    def test_generate_report_excludes_non_violations(self):
        """Test generate_report excludes evaluations where violates_rule is False."""
        with tempfile.TemporaryDirectory() as tmpdir:
            evaluations_dir = PhaseSequencer.ensure_phase_dir(Path(tmpdir), PipelinePhase.EVALUATIONS)
            tasks_dir = PhaseSequencer.ensure_phase_dir(Path(tmpdir), PipelinePhase.TASKS)

            # Create violation
            violation_data = {
                "task_id": "task-violation",
                "rule_name": "rule-a",
                "file_path": "test.py",
                "evaluation": {
                    "violates_rule": True,
                    "score": 7,
                    "comment": "Violation",
                    "file_path": "test.py",
                    "line_number": 10,
                },
            }
            (evaluations_dir / "task-violation.json").write_text(
                json.dumps(violation_data, indent=2)
            )

            # Create non-violation
            non_violation_data = {
                "task_id": "task-ok",
                "rule_name": "rule-b",
                "file_path": "test.py",
                "evaluation": {
                    "violates_rule": False,
                    "score": 1,
                    "comment": "No issues",
                    "file_path": "test.py",
                    "line_number": None,
                },
            }
            (evaluations_dir / "task-ok.json").write_text(
                json.dumps(non_violation_data, indent=2)
            )

            service = ReportGeneratorService(evaluations_dir, tasks_dir)
            report = service.generate_report(pr_number=123, min_score=5)

            self.assertEqual(report.summary.total_tasks_evaluated, 2)
            self.assertEqual(report.summary.violations_found, 1)
            self.assertEqual(report.violations[0].rule_name, "rule-a")

    def test_generate_report_calculates_severity_breakdown(self):
        """Test generate_report calculates severity breakdown correctly."""
        with tempfile.TemporaryDirectory() as tmpdir:
            evaluations_dir = PhaseSequencer.ensure_phase_dir(Path(tmpdir), PipelinePhase.EVALUATIONS)
            tasks_dir = PhaseSequencer.ensure_phase_dir(Path(tmpdir), PipelinePhase.TASKS)

            # Create violations: 1 minor (3), 2 moderate (5, 6), 1 severe (9)
            scores = [3, 5, 6, 9]
            for i, score in enumerate(scores):
                eval_data = {
                    "task_id": f"task-{i}",
                    "rule_name": f"rule-{i}",
                    "file_path": "test.py",
                    "evaluation": {
                        "violates_rule": True,
                        "score": score,
                        "comment": f"Score {score}",
                        "file_path": "test.py",
                        "line_number": 10,
                    },
                }
                (evaluations_dir / f"task-{i}.json").write_text(
                    json.dumps(eval_data, indent=2)
                )

            service = ReportGeneratorService(evaluations_dir, tasks_dir)
            # Use min_score=1 to include all
            report = service.generate_report(pr_number=123, min_score=1)

            self.assertEqual(report.summary.by_severity.get("Minor (1-4)"), 1)
            self.assertEqual(report.summary.by_severity.get("Moderate (5-7)"), 2)
            self.assertEqual(report.summary.by_severity.get("Severe (8-10)"), 1)

    def test_generate_report_accumulates_cost(self):
        """Test generate_report accumulates total cost from evaluations."""
        with tempfile.TemporaryDirectory() as tmpdir:
            evaluations_dir = PhaseSequencer.ensure_phase_dir(Path(tmpdir), PipelinePhase.EVALUATIONS)
            tasks_dir = PhaseSequencer.ensure_phase_dir(Path(tmpdir), PipelinePhase.TASKS)

            costs = [0.001, 0.002, 0.0015]
            for i, cost in enumerate(costs):
                eval_data = {
                    "task_id": f"task-{i}",
                    "rule_name": "test-rule",
                    "file_path": "test.py",
                    "evaluation": {
                        "violates_rule": False,
                        "score": 1,
                        "comment": "OK",
                    },
                    "cost_usd": cost,
                }
                (evaluations_dir / f"task-{i}.json").write_text(
                    json.dumps(eval_data, indent=2)
                )

            service = ReportGeneratorService(evaluations_dir, tasks_dir)
            report = service.generate_report(pr_number=123, min_score=5)

            self.assertAlmostEqual(report.summary.total_cost_usd, 0.0045, places=4)

    def test_save_report_creates_files(self):
        """Test save_report creates JSON and markdown files."""
        with tempfile.TemporaryDirectory() as tmpdir:
            evaluations_dir = PhaseSequencer.ensure_phase_dir(Path(tmpdir), PipelinePhase.EVALUATIONS)
            tasks_dir = PhaseSequencer.ensure_phase_dir(Path(tmpdir), PipelinePhase.TASKS)
            output_dir = Path(tmpdir)

            service = ReportGeneratorService(evaluations_dir, tasks_dir)
            report = service.generate_report(pr_number=123, min_score=5)

            json_path, md_path = service.save_report(report, output_dir)

            self.assertTrue(json_path.exists())
            self.assertTrue(md_path.exists())
            self.assertEqual(json_path.name, "summary.json")
            self.assertEqual(md_path.name, "summary.md")

            # Verify JSON is valid
            json_data = json.loads(json_path.read_text())
            self.assertEqual(json_data["pr_number"], 123)

            # Verify markdown contains expected content
            md_content = md_path.read_text()
            self.assertIn("Code Review Report: PR #123", md_content)

    def test_generate_report_enriches_from_task_metadata(self):
        """Test generate_report enriches violations with task metadata."""
        with tempfile.TemporaryDirectory() as tmpdir:
            evaluations_dir = PhaseSequencer.ensure_phase_dir(Path(tmpdir), PipelinePhase.EVALUATIONS)
            tasks_dir = PhaseSequencer.ensure_phase_dir(Path(tmpdir), PipelinePhase.TASKS)

            # Create task with documentation_link
            task_data = {
                "task_id": "task-123",
                "rule": {
                    "name": "error-handling",
                    "documentation_link": "https://docs.example.com/error-handling",
                    "relevant_claude_skill": "fix-errors",
                },
            }
            (tasks_dir / "task-123.json").write_text(
                json.dumps(task_data, indent=2)
            )

            # Create evaluation referencing the task
            eval_data = {
                "task_id": "task-123",
                "rule_name": "error-handling",
                "file_path": "test.py",
                "evaluation": {
                    "violates_rule": True,
                    "score": 7,
                    "comment": "Violation found",
                    "file_path": "test.py",
                    "line_number": 42,
                },
            }
            (evaluations_dir / "task-123.json").write_text(
                json.dumps(eval_data, indent=2)
            )

            service = ReportGeneratorService(evaluations_dir, tasks_dir)
            report = service.generate_report(pr_number=123, min_score=5)

            self.assertEqual(len(report.violations), 1)
            self.assertEqual(
                report.violations[0].documentation_link,
                "https://docs.example.com/error-handling",
            )
            self.assertEqual(
                report.violations[0].relevant_claude_skill,
                "fix-errors",
            )


    def test_generate_report_enriches_method_name_from_task_metadata(self):
        """Test generate_report populates method_name from task focus_area description."""
        with tempfile.TemporaryDirectory() as tmpdir:
            evaluations_dir = PhaseSequencer.ensure_phase_dir(Path(tmpdir), PipelinePhase.EVALUATIONS)
            tasks_dir = PhaseSequencer.ensure_phase_dir(Path(tmpdir), PipelinePhase.TASKS)

            # Create task with focus_area description
            task_data = {
                "task_id": "task-456",
                "rule": {
                    "name": "error-handling",
                },
                "focus_area": {
                    "description": "login(username, password)",
                    "file_path": "src/auth.py",
                    "start_line": 10,
                    "end_line": 25,
                },
            }
            (tasks_dir / "task-456.json").write_text(
                json.dumps(task_data, indent=2)
            )

            # Create evaluation referencing the task
            eval_data = {
                "task_id": "task-456",
                "rule_name": "error-handling",
                "file_path": "src/auth.py",
                "evaluation": {
                    "violates_rule": True,
                    "score": 7,
                    "comment": "Violation found",
                    "file_path": "src/auth.py",
                    "line_number": 15,
                },
            }
            (evaluations_dir / "task-456.json").write_text(
                json.dumps(eval_data, indent=2)
            )

            service = ReportGeneratorService(evaluations_dir, tasks_dir)
            report = service.generate_report(pr_number=456, min_score=5)

            self.assertEqual(len(report.violations), 1)
            self.assertEqual(report.violations[0].method_name, "login(username, password)")

    def test_generate_report_builds_by_method_grouping(self):
        """Test generate_report creates by_method grouping in summary."""
        with tempfile.TemporaryDirectory() as tmpdir:
            evaluations_dir = PhaseSequencer.ensure_phase_dir(Path(tmpdir), PipelinePhase.EVALUATIONS)
            tasks_dir = PhaseSequencer.ensure_phase_dir(Path(tmpdir), PipelinePhase.TASKS)

            # Create tasks with different methods
            for task_id, method, file_path in [
                ("task-a", "login()", "src/auth.py"),
                ("task-b", "validate_token()", "src/auth.py"),
                ("task-c", "login()", "src/auth.py"),
            ]:
                task_data = {
                    "task_id": task_id,
                    "rule": {"name": f"rule-{task_id}"},
                    "focus_area": {
                        "description": method,
                        "file_path": file_path,
                    },
                }
                (tasks_dir / f"{task_id}.json").write_text(json.dumps(task_data))

            # Create evaluations (all violations)
            for task_id, rule_name, score in [
                ("task-a", "rule-task-a", 7),
                ("task-b", "rule-task-b", 8),
                ("task-c", "rule-task-c", 6),
            ]:
                eval_data = {
                    "task_id": task_id,
                    "rule_name": rule_name,
                    "file_path": "src/auth.py",
                    "evaluation": {
                        "violates_rule": True,
                        "score": score,
                        "comment": "Issue",
                        "file_path": "src/auth.py",
                        "line_number": 10,
                    },
                }
                (evaluations_dir / f"{task_id}.json").write_text(json.dumps(eval_data))

            service = ReportGeneratorService(evaluations_dir, tasks_dir)
            report = service.generate_report(pr_number=789, min_score=5)

            by_method = report.summary.by_method
            self.assertIn("src/auth.py", by_method)
            self.assertIn("login()", by_method["src/auth.py"])
            self.assertIn("validate_token()", by_method["src/auth.py"])
            self.assertEqual(len(by_method["src/auth.py"]["login()"]), 2)
            self.assertEqual(len(by_method["src/auth.py"]["validate_token()"]), 1)


if __name__ == "__main__":
    unittest.main()
