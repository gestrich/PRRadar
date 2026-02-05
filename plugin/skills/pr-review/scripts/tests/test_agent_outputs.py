"""Tests for agent domain models and structured output schemas.

Tests cover:
- JSON schema generation for Claude Agent SDK structured outputs
- Parsing SDK responses into typed domain models
- Serialization/deserialization round-trips
"""

from __future__ import annotations

import unittest

from scripts.domain.agent_outputs import (
    EvaluationSummary,
    RuleApplicability,
    RuleEvaluation,
)


# ============================================================
# RuleApplicability Tests
# ============================================================


class TestRuleApplicability(unittest.TestCase):
    """Tests for RuleApplicability domain model."""

    def test_json_schema_has_required_properties(self):
        """Test JSON schema includes all required properties."""
        schema = RuleApplicability.json_schema()

        self.assertEqual(schema["type"], "object")
        self.assertIn("applicable", schema["properties"])
        self.assertIn("reason", schema["properties"])
        self.assertIn("confidence", schema["properties"])
        self.assertEqual(
            set(schema["required"]), {"applicable", "reason", "confidence"}
        )

    def test_json_schema_property_types(self):
        """Test JSON schema property types are correct."""
        schema = RuleApplicability.json_schema()

        self.assertEqual(schema["properties"]["applicable"]["type"], "boolean")
        self.assertEqual(schema["properties"]["reason"]["type"], "string")
        self.assertEqual(schema["properties"]["confidence"]["type"], "number")

    def test_json_schema_confidence_bounds(self):
        """Test JSON schema has confidence bounds 0-1."""
        schema = RuleApplicability.json_schema()

        self.assertEqual(schema["properties"]["confidence"]["minimum"], 0)
        self.assertEqual(schema["properties"]["confidence"]["maximum"], 1)

    def test_from_dict_parses_valid_data(self):
        """Test from_dict parses valid SDK response."""
        data = {
            "applicable": True,
            "reason": "Rule applies to Python files",
            "confidence": 0.95,
        }

        result = RuleApplicability.from_dict(data)

        self.assertTrue(result.applicable)
        self.assertEqual(result.reason, "Rule applies to Python files")
        self.assertEqual(result.confidence, 0.95)

    def test_from_dict_handles_false_applicable(self):
        """Test from_dict handles applicable=False."""
        data = {
            "applicable": False,
            "reason": "No matching file types",
            "confidence": 0.8,
        }

        result = RuleApplicability.from_dict(data)

        self.assertFalse(result.applicable)

    def test_to_dict_round_trip(self):
        """Test to_dict produces dict that can be parsed back."""
        original = RuleApplicability(
            applicable=True,
            reason="Test reason",
            confidence=0.75,
        )

        data = original.to_dict()
        restored = RuleApplicability.from_dict(data)

        self.assertEqual(restored.applicable, original.applicable)
        self.assertEqual(restored.reason, original.reason)
        self.assertEqual(restored.confidence, original.confidence)


# ============================================================
# RuleEvaluation Tests
# ============================================================


class TestRuleEvaluation(unittest.TestCase):
    """Tests for RuleEvaluation domain model."""

    def test_json_schema_has_required_properties(self):
        """Test JSON schema includes required properties."""
        schema = RuleEvaluation.json_schema()

        self.assertEqual(schema["type"], "object")
        self.assertIn("violates_rule", schema["properties"])
        self.assertIn("score", schema["properties"])
        self.assertIn("comment", schema["properties"])
        self.assertEqual(
            set(schema["required"]), {"violates_rule", "score", "comment"}
        )

    def test_json_schema_score_bounds(self):
        """Test JSON schema has score bounds 1-10."""
        schema = RuleEvaluation.json_schema()

        self.assertEqual(schema["properties"]["score"]["minimum"], 1)
        self.assertEqual(schema["properties"]["score"]["maximum"], 10)

    def test_json_schema_optional_properties(self):
        """Test JSON schema includes optional properties."""
        schema = RuleEvaluation.json_schema()

        self.assertIn("file_path", schema["properties"])
        self.assertIn("line_number", schema["properties"])
        self.assertNotIn("file_path", schema["required"])
        self.assertNotIn("line_number", schema["required"])

    def test_from_dict_parses_violation(self):
        """Test from_dict parses violation with all fields."""
        data = {
            "violates_rule": True,
            "score": 7,
            "comment": "Silent exception handling detected",
            "file_path": "src/handler.py",
            "line_number": 15,
        }

        result = RuleEvaluation.from_dict(data)

        self.assertTrue(result.violates_rule)
        self.assertEqual(result.score, 7)
        self.assertEqual(result.comment, "Silent exception handling detected")
        self.assertEqual(result.file_path, "src/handler.py")
        self.assertEqual(result.line_number, 15)

    def test_from_dict_handles_no_violation(self):
        """Test from_dict handles non-violation."""
        data = {
            "violates_rule": False,
            "score": 1,
            "comment": "No issues found",
        }

        result = RuleEvaluation.from_dict(data)

        self.assertFalse(result.violates_rule)
        self.assertEqual(result.score, 1)

    def test_from_dict_handles_missing_optional_fields(self):
        """Test from_dict handles missing optional fields."""
        data = {
            "violates_rule": True,
            "score": 5,
            "comment": "Issue found",
        }

        result = RuleEvaluation.from_dict(data)

        self.assertEqual(result.file_path, "")
        self.assertIsNone(result.line_number)

    def test_to_dict_includes_line_number_when_present(self):
        """Test to_dict includes line_number when set."""
        evaluation = RuleEvaluation(
            violates_rule=True,
            score=6,
            comment="Test",
            file_path="test.py",
            line_number=42,
        )

        data = evaluation.to_dict()

        self.assertEqual(data["line_number"], 42)

    def test_to_dict_excludes_line_number_when_none(self):
        """Test to_dict excludes line_number when None."""
        evaluation = RuleEvaluation(
            violates_rule=True,
            score=6,
            comment="Test",
            file_path="test.py",
            line_number=None,
        )

        data = evaluation.to_dict()

        self.assertNotIn("line_number", data)

    def test_is_violation_property_true_for_high_score(self):
        """Test is_violation is True when violates_rule and score >= 5."""
        evaluation = RuleEvaluation(
            violates_rule=True,
            score=5,
            comment="Test",
            file_path="",
            line_number=None,
        )

        self.assertTrue(evaluation.is_violation)

    def test_is_violation_property_false_for_low_score(self):
        """Test is_violation is False when score < 5."""
        evaluation = RuleEvaluation(
            violates_rule=True,
            score=4,
            comment="Test",
            file_path="",
            line_number=None,
        )

        self.assertFalse(evaluation.is_violation)

    def test_is_violation_property_false_when_no_violation(self):
        """Test is_violation is False when violates_rule is False."""
        evaluation = RuleEvaluation(
            violates_rule=False,
            score=8,
            comment="Test",
            file_path="",
            line_number=None,
        )

        self.assertFalse(evaluation.is_violation)


# ============================================================
# EvaluationSummary Tests
# ============================================================


class TestEvaluationSummary(unittest.TestCase):
    """Tests for EvaluationSummary domain model."""

    def test_to_dict_serializes_all_fields(self):
        """Test to_dict includes all summary fields."""
        from datetime import datetime, timezone

        from scripts.services.evaluation_service import EvaluationResult

        evaluation = RuleEvaluation(
            violates_rule=True,
            score=7,
            comment="Test",
            file_path="test.py",
            line_number=10,
        )
        result = EvaluationResult(
            task_id="test-task-123",
            rule_name="test-rule",
            rule_file_path="rules/test.md",
            file_path="test.py",
            evaluation=evaluation,
            model_used="claude-sonnet-4-20250514",
            duration_ms=1500,
            cost_usd=0.001,
        )

        summary = EvaluationSummary(
            pr_number=123,
            evaluated_at=datetime(2025, 1, 15, 10, 30, 0, tzinfo=timezone.utc),
            total_tasks=5,
            violations_found=2,
            total_cost_usd=0.005,
            total_duration_ms=7500,
            results=[result],
        )

        data = summary.to_dict()

        self.assertEqual(data["pr_number"], 123)
        self.assertEqual(data["evaluated_at"], "2025-01-15T10:30:00+00:00")
        self.assertEqual(data["total_tasks"], 5)
        self.assertEqual(data["violations_found"], 2)
        self.assertEqual(data["total_cost_usd"], 0.005)
        self.assertEqual(data["total_duration_ms"], 7500)
        self.assertEqual(len(data["results"]), 1)


if __name__ == "__main__":
    unittest.main()
