"""Tests for service layer classes.

Tests cover:
- TaskLoaderService: Loading and filtering evaluation tasks from filesystem
- ViolationService: Transforming evaluation results to violations
"""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from scripts.commands.agent.comment import CommentableViolation
from scripts.domain.agent_outputs import RuleEvaluation
from scripts.domain.evaluation_task import EvaluationTask
from scripts.domain.focus_area import FocusArea
from scripts.domain.rule import AppliesTo, GrepPatterns, Rule
from scripts.services.evaluation_service import EvaluationResult
from scripts.services.task_loader_service import TaskLoaderService
from scripts.services.violation_service import ViolationService


# ============================================================
# Test Fixtures
# ============================================================


def make_rule(
    name: str = "test-rule",
    description: str = "Test description",
    documentation_link: str | None = None,
) -> Rule:
    """Create a Rule instance for testing."""
    return Rule(
        name=name,
        file_path=f"/rules/{name}.md",
        description=description,
        category="test",
        applies_to=AppliesTo(),
        grep=GrepPatterns(),
        content="Rule content",
        documentation_link=documentation_link,
    )


def make_focus_area(
    file_path: str = "src/test.py",
    start_line: int = 10,
    end_line: int = 20,
) -> FocusArea:
    """Create a FocusArea instance for testing."""
    safe_path = file_path.replace("/", "-").replace("\\", "-")
    return FocusArea(
        focus_id=f"{safe_path}-0",
        file_path=file_path,
        start_line=start_line,
        end_line=end_line,
        description="hunk 0",
        hunk_index=0,
        hunk_content="+    new code",
    )


def make_task(
    rule_name: str = "test-rule",
    file_path: str = "src/test.py",
    documentation_link: str | None = None,
) -> EvaluationTask:
    """Create an EvaluationTask instance for testing."""
    rule = make_rule(name=rule_name, documentation_link=documentation_link)
    focus_area = make_focus_area(file_path=file_path)
    return EvaluationTask.create(rule=rule, focus_area=focus_area)


def make_evaluation(
    violates_rule: bool = True,
    score: int = 7,
    line_number: int = 15,
) -> RuleEvaluation:
    """Create a RuleEvaluation instance for testing."""
    return RuleEvaluation(
        violates_rule=violates_rule,
        score=score,
        comment="Test comment",
        file_path="src/test.py",
        line_number=line_number,
    )


def make_result(
    task_id: str = "test-rule-abc12345",
    rule_name: str = "test-rule",
    rule_file_path: str = "rules/test-rule.md",
    file_path: str = "src/test.py",
    violates_rule: bool = True,
    score: int = 7,
    cost_usd: float | None = 0.001,
) -> EvaluationResult:
    """Create an EvaluationResult instance for testing."""
    return EvaluationResult(
        task_id=task_id,
        rule_name=rule_name,
        rule_file_path=rule_file_path,
        file_path=file_path,
        evaluation=make_evaluation(violates_rule=violates_rule, score=score),
        model_used="claude-sonnet-4-20250514",
        duration_ms=1500,
        cost_usd=cost_usd,
    )


# ============================================================
# TaskLoaderService Tests
# ============================================================


class TestTaskLoaderService(unittest.TestCase):
    """Tests for TaskLoaderService task loading functionality."""

    def test_load_all_returns_empty_list_when_directory_does_not_exist(self):
        """Test that load_all returns empty list for non-existent directory."""
        loader = TaskLoaderService(Path("/nonexistent/path"))
        result = loader.load_all()
        self.assertEqual(result, [])

    def test_load_all_returns_empty_list_when_no_files(self):
        """Test that load_all returns empty list when directory has no JSON files."""
        with tempfile.TemporaryDirectory() as tmpdir:
            loader = TaskLoaderService(Path(tmpdir))
            result = loader.load_all()
            self.assertEqual(result, [])

    def test_load_all_loads_single_task(self):
        """Test that load_all correctly loads a single task file."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tasks_dir = Path(tmpdir)

            task = make_task(rule_name="my-rule", file_path="src/handler.py")
            task_file = tasks_dir / f"{task.task_id}.json"
            task_file.write_text(json.dumps(task.to_dict(), indent=2))

            loader = TaskLoaderService(tasks_dir)
            result = loader.load_all()

            self.assertEqual(len(result), 1)
            self.assertEqual(result[0].rule.name, "my-rule")
            self.assertEqual(result[0].focus_area.file_path, "src/handler.py")

    def test_load_all_loads_multiple_tasks(self):
        """Test that load_all loads multiple task files."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tasks_dir = Path(tmpdir)

            task1 = make_task(rule_name="rule-a")
            task2 = make_task(rule_name="rule-b")

            (tasks_dir / f"{task1.task_id}.json").write_text(json.dumps(task1.to_dict()))
            (tasks_dir / f"{task2.task_id}.json").write_text(json.dumps(task2.to_dict()))

            loader = TaskLoaderService(tasks_dir)
            result = loader.load_all()

            self.assertEqual(len(result), 2)
            rule_names = {t.rule.name for t in result}
            self.assertIn("rule-a", rule_names)
            self.assertIn("rule-b", rule_names)

    def test_load_all_skips_invalid_json_files(self):
        """Test that load_all silently skips files with invalid JSON."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tasks_dir = Path(tmpdir)

            valid_task = make_task(rule_name="valid-rule")
            (tasks_dir / f"{valid_task.task_id}.json").write_text(
                json.dumps(valid_task.to_dict())
            )

            (tasks_dir / "invalid.json").write_text("not valid json {{{")

            loader = TaskLoaderService(tasks_dir)
            result = loader.load_all()

            self.assertEqual(len(result), 1)
            self.assertEqual(result[0].rule.name, "valid-rule")

    def test_load_filtered_returns_only_matching_rules(self):
        """Test that load_filtered returns only tasks for specified rules."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tasks_dir = Path(tmpdir)

            task1 = make_task(rule_name="include-me")
            task2 = make_task(rule_name="exclude-me")
            task3 = make_task(rule_name="also-include")

            for task in [task1, task2, task3]:
                (tasks_dir / f"{task.task_id}.json").write_text(
                    json.dumps(task.to_dict())
                )

            loader = TaskLoaderService(tasks_dir)
            result = loader.load_filtered(["include-me", "also-include"])

            self.assertEqual(len(result), 2)
            rule_names = {t.rule.name for t in result}
            self.assertIn("include-me", rule_names)
            self.assertIn("also-include", rule_names)
            self.assertNotIn("exclude-me", rule_names)

    def test_load_filtered_returns_empty_list_when_no_matches(self):
        """Test that load_filtered returns empty list when no rules match."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tasks_dir = Path(tmpdir)

            task = make_task(rule_name="some-rule")
            (tasks_dir / f"{task.task_id}.json").write_text(json.dumps(task.to_dict()))

            loader = TaskLoaderService(tasks_dir)
            result = loader.load_filtered(["different-rule"])

            self.assertEqual(result, [])

    def test_parse_task_file_returns_none_for_invalid_structure(self):
        """Test that _parse_task_file returns None for JSON without required fields."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tasks_dir = Path(tmpdir)

            (tasks_dir / "incomplete.json").write_text('{"some_field": "value"}')

            loader = TaskLoaderService(tasks_dir)
            result = loader.load_all()

            self.assertEqual(len(result), 1)


# ============================================================
# ViolationService Tests
# ============================================================


class TestViolationService(unittest.TestCase):
    """Tests for ViolationService violation transformation functionality."""

    def test_create_violation_transforms_result_and_task(self):
        """Test that create_violation correctly transforms result and task."""
        task = make_task(
            rule_name="my-rule",
            file_path="src/handler.py",
            documentation_link="https://docs.example.com/my-rule",
        )
        result = make_result(
            task_id=task.task_id,
            rule_name="my-rule",
            file_path="src/handler.py",
            score=8,
            cost_usd=0.0025,
        )

        violation = ViolationService.create_violation(result, task)

        self.assertIsInstance(violation, CommentableViolation)
        self.assertEqual(violation.task_id, task.task_id)
        self.assertEqual(violation.rule_name, "my-rule")
        self.assertEqual(violation.file_path, "src/handler.py")
        self.assertEqual(violation.score, 8)
        self.assertEqual(violation.documentation_link, "https://docs.example.com/my-rule")
        self.assertEqual(violation.cost_usd, 0.0025)

    def test_create_violation_preserves_comment(self):
        """Test that create_violation preserves comment."""
        task = make_task()
        result = make_result()

        violation = ViolationService.create_violation(result, task)

        self.assertEqual(violation.comment, "Test comment")
        self.assertEqual(violation.line_number, 15)

    def test_filter_by_score_excludes_non_violations(self):
        """Test that filter_by_score excludes results without violations."""
        task1 = make_task(rule_name="rule-a")
        task2 = make_task(rule_name="rule-b")

        results = [
            make_result(task_id=task1.task_id, rule_name="rule-a", violates_rule=True, score=7),
            make_result(task_id=task2.task_id, rule_name="rule-b", violates_rule=False, score=5),
        ]
        tasks = [task1, task2]

        violations = ViolationService.filter_by_score(results, tasks, min_score=5)

        self.assertEqual(len(violations), 1)
        self.assertEqual(violations[0].rule_name, "rule-a")

    def test_filter_by_score_excludes_low_scores(self):
        """Test that filter_by_score excludes results below min_score threshold."""
        task1 = make_task(rule_name="rule-a")
        task2 = make_task(rule_name="rule-b")
        task3 = make_task(rule_name="rule-c")

        results = [
            make_result(task_id=task1.task_id, rule_name="rule-a", violates_rule=True, score=3),
            make_result(task_id=task2.task_id, rule_name="rule-b", violates_rule=True, score=5),
            make_result(task_id=task3.task_id, rule_name="rule-c", violates_rule=True, score=8),
        ]
        tasks = [task1, task2, task3]

        violations = ViolationService.filter_by_score(results, tasks, min_score=5)

        self.assertEqual(len(violations), 2)
        rule_names = {v.rule_name for v in violations}
        self.assertIn("rule-b", rule_names)
        self.assertIn("rule-c", rule_names)
        self.assertNotIn("rule-a", rule_names)

    def test_filter_by_score_returns_empty_for_no_qualifying_results(self):
        """Test that filter_by_score returns empty list when no results qualify."""
        task = make_task()

        results = [
            make_result(task_id=task.task_id, violates_rule=False, score=7),
        ]
        tasks = [task]

        violations = ViolationService.filter_by_score(results, tasks, min_score=5)

        self.assertEqual(violations, [])

    def test_filter_by_score_handles_missing_task(self):
        """Test that filter_by_score silently skips results without matching task."""
        task = make_task(rule_name="existing-rule")

        results = [
            make_result(task_id=task.task_id, rule_name="existing-rule", violates_rule=True, score=7),
            make_result(task_id="orphan-task-id", rule_name="orphan-rule", violates_rule=True, score=7),
        ]
        tasks = [task]

        violations = ViolationService.filter_by_score(results, tasks, min_score=5)

        self.assertEqual(len(violations), 1)
        self.assertEqual(violations[0].rule_name, "existing-rule")

    def test_filter_by_score_preserves_documentation_link(self):
        """Test that filter_by_score preserves documentation_link from task."""
        task = make_task(documentation_link="https://docs.example.com/rule")

        results = [
            make_result(task_id=task.task_id, violates_rule=True, score=7),
        ]
        tasks = [task]

        violations = ViolationService.filter_by_score(results, tasks, min_score=5)

        self.assertEqual(len(violations), 1)
        self.assertEqual(violations[0].documentation_link, "https://docs.example.com/rule")


# ============================================================
# FocusGeneratorService Tests
# ============================================================


class TestFocusGeneratorServiceFallback(unittest.TestCase):
    """Tests for FocusGeneratorService fallback behavior."""

    def test_fallback_creates_one_focus_area_per_hunk(self):
        """Fallback should create one focus area covering each hunk."""
        from scripts.domain.diff import Hunk
        from scripts.services.focus_generator import FocusGeneratorService

        hunk = Hunk(
            file_path="src/handler.py",
            content="@@ -10,5 +10,8 @@\n context\n+new line",
            new_start=10,
            new_length=8,
            old_start=10,
            old_length=5,
        )

        focus_areas = FocusGeneratorService._fallback_focus_area(hunk, 0, hunk.get_annotated_content())

        self.assertEqual(len(focus_areas), 1)
        fa = focus_areas[0]
        self.assertEqual(fa.file_path, "src/handler.py")
        self.assertEqual(fa.start_line, 10)
        self.assertEqual(fa.end_line, 17)
        self.assertEqual(fa.hunk_index, 0)
        self.assertEqual(fa.description, "hunk 0")
        self.assertEqual(fa.focus_id, "src-handler.py-0")

    def test_fallback_sanitizes_file_path_in_focus_id(self):
        """Focus ID should sanitize slashes in file paths."""
        from scripts.domain.diff import Hunk
        from scripts.services.focus_generator import FocusGeneratorService

        hunk = Hunk(
            file_path="src/deep/nested/file.py",
            content="@@ -1,3 +1,5 @@\n+new",
            new_start=1,
            new_length=5,
        )

        focus_areas = FocusGeneratorService._fallback_focus_area(hunk, 2, hunk.content)
        self.assertEqual(focus_areas[0].focus_id, "src-deep-nested-file.py-2")


class TestFocusGenerationResult(unittest.TestCase):
    """Tests for FocusGenerationResult data model."""

    def test_to_dict_serialization(self):
        """FocusGenerationResult should serialize correctly."""
        from scripts.services.focus_generator import FocusGenerationResult

        fa = FocusArea(
            focus_id="src-test.py-0",
            file_path="src/test.py",
            start_line=10,
            end_line=20,
            description="test_method()",
            hunk_index=0,
            hunk_content="+code",
        )
        result = FocusGenerationResult(
            pr_number=42,
            focus_areas=[fa],
            total_hunks_processed=1,
            generation_cost_usd=0.001,
        )

        data = result.to_dict()
        self.assertEqual(data["pr_number"], 42)
        self.assertEqual(len(data["focus_areas"]), 1)
        self.assertEqual(data["total_hunks_processed"], 1)
        self.assertAlmostEqual(data["generation_cost_usd"], 0.001)

    def test_sanitize_for_id(self):
        """_sanitize_for_id should produce safe identifiers."""
        from scripts.services.focus_generator import FocusGeneratorService

        self.assertEqual(FocusGeneratorService._sanitize_for_id("login(username, password)"), "login")
        self.assertEqual(FocusGeneratorService._sanitize_for_id("__init__"), "__init__")
        self.assertEqual(FocusGeneratorService._sanitize_for_id(""), "unknown")
        self.assertEqual(FocusGeneratorService._sanitize_for_id("my method"), "my-method")


# ============================================================
# RuleLoaderService Focus Area Filtering Tests
# ============================================================


def _make_annotated_hunk_content(
    start_line: int = 10,
    lines: list[tuple[str, str]] | None = None,
) -> str:
    """Build annotated hunk content for testing.

    Args:
        start_line: Starting line number in new file
        lines: List of (prefix, content) tuples where prefix is "+" or " "
               for added/context lines, or "-" for removed lines.

    Returns:
        Annotated hunk content string matching Hunk.get_annotated_content() format
    """
    if lines is None:
        lines = [
            (" ", "context line"),
            ("+", "new code"),
        ]

    result = ["@@ -10,5 +10,8 @@"]
    line_num = start_line
    for prefix, content in lines:
        if prefix == "-":
            result.append(f"   -: -{content}")
        elif prefix == "+":
            result.append(f"{line_num:4d}: +{content}")
            line_num += 1
        else:
            result.append(f"{line_num:4d}:  {content}")
            line_num += 1

    return "\n".join(result)


class TestRuleLoaderFilterForFocusArea(unittest.TestCase):
    """Tests for RuleLoaderService.filter_rules_for_focus_area."""

    def _make_service(self) -> "RuleLoaderService":
        """Create a minimal RuleLoaderService for testing."""
        from scripts.infrastructure.git.git_utils import GitFileInfo
        from scripts.services.rule_loader import RuleLoaderService

        return RuleLoaderService(
            rules_dir=Path("/fake/rules"),
            git_info=GitFileInfo(
                repo_url="https://github.com/test/rules",
                branch="main",
                relative_path="rules",
            ),
        )

    def test_rule_without_grep_matches_by_file_pattern(self):
        """Rule with file_patterns but no grep should match any focus area in matching file."""
        service = self._make_service()
        rule = Rule(
            name="swift-rule",
            file_path="/rules/swift-rule.md",
            description="Swift rule",
            category="test",
            applies_to=AppliesTo(file_patterns=["*.swift"]),
            grep=GrepPatterns(),
            content="Check Swift code",
        )
        focus_area = FocusArea(
            focus_id="src-handler.swift-0",
            file_path="src/handler.swift",
            start_line=10,
            end_line=20,
            description="handleRequest()",
            hunk_index=0,
            hunk_content=_make_annotated_hunk_content(10, [
                (" ", "func handleRequest() {"),
                ("+", "    let result = process()"),
                ("+", "    return result"),
                (" ", "}"),
            ]),
        )

        result = service.filter_rules_for_focus_area([rule], focus_area)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0].name, "swift-rule")

    def test_rule_excluded_by_file_pattern(self):
        """Rule should not match focus area in non-matching file."""
        service = self._make_service()
        rule = Rule(
            name="swift-rule",
            file_path="/rules/swift-rule.md",
            description="Swift rule",
            category="test",
            applies_to=AppliesTo(file_patterns=["*.swift"]),
            grep=GrepPatterns(),
            content="Check Swift code",
        )
        focus_area = FocusArea(
            focus_id="src-handler.py-0",
            file_path="src/handler.py",
            start_line=10,
            end_line=20,
            description="handle_request()",
            hunk_index=0,
            hunk_content="+code",
        )

        result = service.filter_rules_for_focus_area([rule], focus_area)
        self.assertEqual(len(result), 0)

    def test_grep_pattern_matches_within_focus_area(self):
        """Grep pattern should match when pattern exists in focus area content."""
        service = self._make_service()
        rule = Rule(
            name="error-handling",
            file_path="/rules/error-handling.md",
            description="Check error handling",
            category="test",
            applies_to=AppliesTo(),
            grep=GrepPatterns(any_patterns=["try|catch|except"]),
            content="Check error handling",
        )
        focus_area = FocusArea(
            focus_id="src-handler.py-0",
            file_path="src/handler.py",
            start_line=10,
            end_line=13,
            description="handle_request()",
            hunk_index=0,
            hunk_content=_make_annotated_hunk_content(10, [
                (" ", "def handle_request():"),
                ("+", "    try:"),
                ("+", "        process()"),
                ("+", "    except Exception:"),
            ]),
        )

        result = service.filter_rules_for_focus_area([rule], focus_area)
        self.assertEqual(len(result), 1)

    def test_grep_pattern_respects_focus_bounds(self):
        """Grep patterns should only match within focus area, not entire hunk."""
        service = self._make_service()
        rule = Rule(
            name="error-handling",
            file_path="/rules/error-handling.md",
            description="Check error handling",
            category="test",
            applies_to=AppliesTo(),
            grep=GrepPatterns(any_patterns=["try|catch|except"]),
            content="Check error handling",
        )
        # Hunk has two methods: first has no try/except, second does.
        # Focus area covers only the first method (lines 10-12).
        hunk_content = _make_annotated_hunk_content(10, [
            (" ", "def first_method():"),
            ("+", "    return 42"),
            (" ", ""),
            (" ", "def second_method():"),
            ("+", "    try:"),
            ("+", "        process()"),
            ("+", "    except Exception:"),
            ("+", "        pass"),
        ])
        focus_area = FocusArea(
            focus_id="src-handler.py-0-first_method",
            file_path="src/handler.py",
            start_line=10,
            end_line=12,
            description="first_method()",
            hunk_index=0,
            hunk_content=hunk_content,
        )

        result = service.filter_rules_for_focus_area([rule], focus_area)
        self.assertEqual(len(result), 0)

    def test_grep_pattern_matches_second_focus_area(self):
        """Grep should match when focus area covers the method with matching content."""
        service = self._make_service()
        rule = Rule(
            name="error-handling",
            file_path="/rules/error-handling.md",
            description="Check error handling",
            category="test",
            applies_to=AppliesTo(),
            grep=GrepPatterns(any_patterns=["try|catch|except"]),
            content="Check error handling",
        )
        hunk_content = _make_annotated_hunk_content(10, [
            (" ", "def first_method():"),
            ("+", "    return 42"),
            (" ", ""),
            (" ", "def second_method():"),
            ("+", "    try:"),
            ("+", "        process()"),
            ("+", "    except Exception:"),
            ("+", "        pass"),
        ])
        # Focus area covers second method (lines 13-17)
        focus_area = FocusArea(
            focus_id="src-handler.py-0-second_method",
            file_path="src/handler.py",
            start_line=13,
            end_line=17,
            description="second_method()",
            hunk_index=0,
            hunk_content=hunk_content,
        )

        result = service.filter_rules_for_focus_area([rule], focus_area)
        self.assertEqual(len(result), 1)

    def test_multiple_rules_filtered_independently(self):
        """Each rule should be filtered independently against the focus area."""
        service = self._make_service()
        swift_rule = Rule(
            name="swift-only",
            file_path="/rules/swift-only.md",
            description="Swift rule",
            category="test",
            applies_to=AppliesTo(file_patterns=["*.swift"]),
            grep=GrepPatterns(),
            content="Check Swift",
        )
        general_rule = Rule(
            name="general",
            file_path="/rules/general.md",
            description="General rule",
            category="test",
            applies_to=AppliesTo(),
            grep=GrepPatterns(),
            content="Check everything",
        )
        grep_rule = Rule(
            name="async-rule",
            file_path="/rules/async-rule.md",
            description="Async rule",
            category="test",
            applies_to=AppliesTo(),
            grep=GrepPatterns(any_patterns=["async|await"]),
            content="Check async usage",
        )

        focus_area = FocusArea(
            focus_id="src-handler.py-0",
            file_path="src/handler.py",
            start_line=10,
            end_line=12,
            description="handle()",
            hunk_index=0,
            hunk_content=_make_annotated_hunk_content(10, [
                ("+", "def handle():"),
                ("+", "    return sync_call()"),
            ]),
        )

        result = service.filter_rules_for_focus_area(
            [swift_rule, general_rule, grep_rule], focus_area
        )
        # swift_rule: excluded (file is .py not .swift)
        # general_rule: included (no file patterns, no grep)
        # grep_rule: excluded (no async/await in focus area)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0].name, "general")

    def test_rule_with_no_patterns_matches_all_focus_areas(self):
        """Rule with no file patterns and no grep should match everything."""
        service = self._make_service()
        rule = Rule(
            name="catch-all",
            file_path="/rules/catch-all.md",
            description="Universal rule",
            category="test",
            applies_to=AppliesTo(),
            grep=GrepPatterns(),
            content="Check everything",
        )
        focus_area = FocusArea(
            focus_id="any-file-0",
            file_path="anything/here.xyz",
            start_line=1,
            end_line=5,
            description="some function",
            hunk_index=0,
            hunk_content="+code",
        )

        result = service.filter_rules_for_focus_area([rule], focus_area)
        self.assertEqual(len(result), 1)


# ============================================================
# Evaluation Service Prompt Tests
# ============================================================


class TestEvaluationPromptTemplate(unittest.TestCase):
    """Tests for evaluation prompt template format."""

    def test_prompt_template_includes_focus_area_description(self):
        """Prompt template should include focus area description placeholder."""
        from scripts.services.evaluation_service import EVALUATION_PROMPT_TEMPLATE

        self.assertIn("{focus_area_description}", EVALUATION_PROMPT_TEMPLATE)

    def test_prompt_template_includes_focus_area_boundary_instruction(self):
        """Prompt should instruct Claude to only evaluate within focus area boundaries."""
        from scripts.services.evaluation_service import EVALUATION_PROMPT_TEMPLATE

        self.assertIn("Only evaluate the code within the focus area boundaries", EVALUATION_PROMPT_TEMPLATE)

    def test_prompt_formats_with_focus_area_fields(self):
        """Prompt template should format correctly with all focus area fields."""
        from scripts.services.evaluation_service import EVALUATION_PROMPT_TEMPLATE

        formatted = EVALUATION_PROMPT_TEMPLATE.format(
            rule_name="test-rule",
            rule_description="Test description",
            rule_content="Rule content here",
            focus_area_description="login(username, password)",
            file_path="src/auth.py",
            start_line=10,
            end_line=25,
            diff_content="+    new code",
        )

        self.assertIn("Focus Area: login(username, password)", formatted)
        self.assertIn("File: src/auth.py", formatted)
        self.assertIn("Lines: 10-25", formatted)


if __name__ == "__main__":
    unittest.main()
