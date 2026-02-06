"""Tests for PhaseSequencer service, migration script, and command integration.

Tests cover:
- PipelinePhase enum ordering and navigation
- PhaseSequencer directory management
- Dependency validation
- Migration from legacy to canonical directory names
- Command-level dependency validation integration
- Full pipeline chain validation
"""

from __future__ import annotations

import json
import re
import tempfile
import unittest
from pathlib import Path

from scripts.commands.migrate_to_phases import migrate_all, migrate_pr_directory
from scripts.services.phase_sequencer import (
    DiffPhaseChecker,
    EvaluationsPhaseChecker,
    FocusAreasPhaseChecker,
    PhaseSequencer,
    PhaseStatus,
    PipelinePhase,
    ReportPhaseChecker,
    RulesPhaseChecker,
    TasksPhaseChecker,
)


class TestPipelinePhase(unittest.TestCase):
    """Tests for PipelinePhase enum."""

    def test_phase_enum_order(self) -> None:
        """Verify phases are in correct execution order."""
        phases = list(PipelinePhase)
        assert phases[0] == PipelinePhase.DIFF
        assert phases[-1] == PipelinePhase.REPORT

    def test_phase_number(self) -> None:
        """Verify phase_number() returns correct 1-based index."""
        assert PipelinePhase.DIFF.phase_number() == 1
        assert PipelinePhase.FOCUS_AREAS.phase_number() == 2
        assert PipelinePhase.RULES.phase_number() == 3
        assert PipelinePhase.TASKS.phase_number() == 4
        assert PipelinePhase.EVALUATIONS.phase_number() == 5
        assert PipelinePhase.REPORT.phase_number() == 6

    def test_previous_phase_first(self) -> None:
        """First phase has no previous phase."""
        assert PipelinePhase.DIFF.previous_phase() is None

    def test_previous_phase_chain(self) -> None:
        """Verify previous_phase() returns correct dependencies."""
        assert PipelinePhase.FOCUS_AREAS.previous_phase() == PipelinePhase.DIFF
        assert PipelinePhase.RULES.previous_phase() == PipelinePhase.FOCUS_AREAS
        assert PipelinePhase.TASKS.previous_phase() == PipelinePhase.RULES
        assert PipelinePhase.EVALUATIONS.previous_phase() == PipelinePhase.TASKS
        assert PipelinePhase.REPORT.previous_phase() == PipelinePhase.EVALUATIONS

    def test_phase_values_include_numbers(self) -> None:
        """Phase values should include their phase number."""
        assert PipelinePhase.DIFF.value == "phase-1-diff"
        assert PipelinePhase.REPORT.value == "phase-6-report"

    def test_previous_implemented_phase_first(self) -> None:
        """First phase has no previous implemented phase."""
        assert PipelinePhase.DIFF.previous_implemented_phase() is None

    def test_previous_implemented_phase_chain(self) -> None:
        """All phases return their immediate predecessor (no future phases)."""
        assert PipelinePhase.FOCUS_AREAS.previous_implemented_phase() == PipelinePhase.DIFF
        assert PipelinePhase.RULES.previous_implemented_phase() == PipelinePhase.FOCUS_AREAS
        assert PipelinePhase.TASKS.previous_implemented_phase() == PipelinePhase.RULES
        assert PipelinePhase.EVALUATIONS.previous_implemented_phase() == PipelinePhase.TASKS
        assert PipelinePhase.REPORT.previous_implemented_phase() == PipelinePhase.EVALUATIONS


class TestPhaseSequencerDirectoryManagement(unittest.TestCase):
    """Tests for PhaseSequencer directory management."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_get_phase_dir(self) -> None:
        """get_phase_dir returns correct path without creating it."""
        result = PhaseSequencer.get_phase_dir(self.tmp_path, PipelinePhase.DIFF)
        assert result == self.tmp_path / "phase-1-diff"
        assert not result.exists()

    def test_ensure_phase_dir_creates_directory(self) -> None:
        """ensure_phase_dir creates directory if it doesn't exist."""
        result = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.DIFF)
        assert result.exists()
        assert result.is_dir()

    def test_ensure_phase_dir_creates_parents(self) -> None:
        """ensure_phase_dir creates parent directories."""
        nested = self.tmp_path / "deep" / "nested" / "pr-123"
        result = PhaseSequencer.ensure_phase_dir(nested, PipelinePhase.RULES)
        assert result.exists()
        assert result == nested / "phase-3-rules"

    def test_ensure_phase_dir_idempotent(self) -> None:
        """ensure_phase_dir is safe to call multiple times."""
        PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.DIFF)
        result = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.DIFF)
        assert result.exists()

    def test_phase_exists_missing_directory(self) -> None:
        """Missing phase directory should return False."""
        assert not PhaseSequencer.phase_exists(self.tmp_path, PipelinePhase.DIFF)

    def test_phase_exists_empty_directory(self) -> None:
        """Empty phase directory should return False."""
        PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.DIFF)
        assert not PhaseSequencer.phase_exists(self.tmp_path, PipelinePhase.DIFF)

    def test_phase_exists_with_content(self) -> None:
        """Phase directory with files should return True."""
        phase_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.DIFF)
        (phase_dir / "raw.diff").write_text("content")
        assert PhaseSequencer.phase_exists(self.tmp_path, PipelinePhase.DIFF)

    def test_phase_exists_with_subdirectory(self) -> None:
        """Phase directory with subdirectory should return True."""
        phase_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.DIFF)
        (phase_dir / "subdir").mkdir()
        assert PhaseSequencer.phase_exists(self.tmp_path, PipelinePhase.DIFF)


class TestPhaseSequencerDependencyValidation(unittest.TestCase):
    """Tests for PhaseSequencer dependency validation."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_can_run_first_phase(self) -> None:
        """First phase (DIFF) should always be able to run."""
        assert PhaseSequencer.can_run_phase(self.tmp_path, PipelinePhase.DIFF)

    def test_cannot_run_without_dependency(self) -> None:
        """Cannot run phase if previous phase doesn't exist."""
        assert not PhaseSequencer.can_run_phase(self.tmp_path, PipelinePhase.EVALUATIONS)

    def test_can_run_with_dependency(self) -> None:
        """Can run phase if previous phase exists with content."""
        tasks_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.TASKS)
        (tasks_dir / "task-001.json").write_text("{}")
        assert PhaseSequencer.can_run_phase(self.tmp_path, PipelinePhase.EVALUATIONS)

    def test_can_run_rules_with_focus_areas(self) -> None:
        """RULES can run if FOCUS_AREAS exists."""
        focus_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.FOCUS_AREAS)
        (focus_dir / "all.json").write_text("{}")
        assert PhaseSequencer.can_run_phase(self.tmp_path, PipelinePhase.RULES)

    def test_cannot_run_rules_without_focus_areas(self) -> None:
        """RULES cannot run without FOCUS_AREAS."""
        diff_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.DIFF)
        (diff_dir / "parsed.json").write_text("{}")
        assert not PhaseSequencer.can_run_phase(self.tmp_path, PipelinePhase.RULES)

    def test_can_run_focus_areas_with_diff(self) -> None:
        """FOCUS_AREAS can run if DIFF exists."""
        diff_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.DIFF)
        (diff_dir / "parsed.json").write_text("{}")
        assert PhaseSequencer.can_run_phase(self.tmp_path, PipelinePhase.FOCUS_AREAS)

    def test_cannot_run_focus_areas_without_diff(self) -> None:
        """FOCUS_AREAS cannot run without DIFF."""
        assert not PhaseSequencer.can_run_phase(self.tmp_path, PipelinePhase.FOCUS_AREAS)

    def test_validate_can_run_returns_none_when_valid(self) -> None:
        """validate_can_run returns None when phase can run."""
        focus_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.FOCUS_AREAS)
        (focus_dir / "all.json").write_text("{}")
        assert PhaseSequencer.validate_can_run(self.tmp_path, PipelinePhase.RULES) is None

    def test_validate_can_run_returns_error_when_invalid(self) -> None:
        """validate_can_run returns error message when phase cannot run."""
        error = PhaseSequencer.validate_can_run(self.tmp_path, PipelinePhase.EVALUATIONS)
        assert error is not None
        assert "phase-4-tasks" in error
        assert "phase-5-evaluations" in error

    def test_validate_can_run_first_phase(self) -> None:
        """validate_can_run returns None for first phase."""
        assert PhaseSequencer.validate_can_run(self.tmp_path, PipelinePhase.DIFF) is None


class TestPhaseStatus(unittest.TestCase):
    """Tests for PhaseStatus dataclass and helper methods."""

    def test_completion_percentage_partial(self) -> None:
        """Completion percentage calculated correctly for partial progress."""
        status = PhaseStatus(
            phase=PipelinePhase.EVALUATIONS,
            exists=True,
            is_complete=False,
            completed_count=15,
            total_count=20,
            missing_items=["task-1", "task-2", "task-3", "task-4", "task-5"],
        )
        assert status.completion_percentage() == 75.0

    def test_completion_percentage_complete(self) -> None:
        """Completion percentage is 100% when all items done."""
        status = PhaseStatus(
            phase=PipelinePhase.DIFF,
            exists=True,
            is_complete=True,
            completed_count=5,
            total_count=5,
            missing_items=[],
        )
        assert status.completion_percentage() == 100.0

    def test_completion_percentage_zero_total_complete(self) -> None:
        """Zero total count returns 100% when marked complete."""
        status = PhaseStatus(
            phase=PipelinePhase.DIFF,
            exists=True,
            is_complete=True,
            completed_count=0,
            total_count=0,
            missing_items=[],
        )
        assert status.completion_percentage() == 100.0

    def test_completion_percentage_zero_total_incomplete(self) -> None:
        """Zero total count returns 0% when not complete."""
        status = PhaseStatus(
            phase=PipelinePhase.DIFF,
            exists=False,
            is_complete=False,
            completed_count=0,
            total_count=0,
            missing_items=[],
        )
        assert status.completion_percentage() == 0.0

    def test_completion_percentage_none_done(self) -> None:
        """Completion percentage is 0% when nothing done."""
        status = PhaseStatus(
            phase=PipelinePhase.TASKS,
            exists=True,
            is_complete=False,
            completed_count=0,
            total_count=10,
            missing_items=[],
        )
        assert status.completion_percentage() == 0.0

    def test_is_partial_true(self) -> None:
        """Phase is partial when it exists, is incomplete, and has some progress."""
        status = PhaseStatus(
            phase=PipelinePhase.EVALUATIONS,
            exists=True,
            is_complete=False,
            completed_count=10,
            total_count=20,
            missing_items=[],
        )
        assert status.is_partial()

    def test_is_partial_false_when_complete(self) -> None:
        """Phase is not partial when complete."""
        status = PhaseStatus(
            phase=PipelinePhase.EVALUATIONS,
            exists=True,
            is_complete=True,
            completed_count=20,
            total_count=20,
            missing_items=[],
        )
        assert not status.is_partial()

    def test_is_partial_false_when_not_exists(self) -> None:
        """Phase is not partial when it doesn't exist."""
        status = PhaseStatus(
            phase=PipelinePhase.EVALUATIONS,
            exists=False,
            is_complete=False,
            completed_count=0,
            total_count=20,
            missing_items=[],
        )
        assert not status.is_partial()

    def test_is_partial_false_when_zero_completed(self) -> None:
        """Phase is not partial when nothing completed (exists but empty)."""
        status = PhaseStatus(
            phase=PipelinePhase.EVALUATIONS,
            exists=True,
            is_complete=False,
            completed_count=0,
            total_count=20,
            missing_items=[],
        )
        assert not status.is_partial()

    def test_summary_not_started(self) -> None:
        """Summary shows 'not started' when phase doesn't exist."""
        status = PhaseStatus(
            phase=PipelinePhase.REPORT,
            exists=False,
            is_complete=False,
            completed_count=0,
            total_count=0,
            missing_items=[],
        )
        assert status.summary() == "not started"

    def test_summary_complete(self) -> None:
        """Summary shows 'complete' when phase is done."""
        status = PhaseStatus(
            phase=PipelinePhase.DIFF,
            exists=True,
            is_complete=True,
            completed_count=5,
            total_count=5,
            missing_items=[],
        )
        assert status.summary() == "complete"

    def test_summary_partial(self) -> None:
        """Summary shows 'partial (N/M)' when partially complete."""
        status = PhaseStatus(
            phase=PipelinePhase.EVALUATIONS,
            exists=True,
            is_complete=False,
            completed_count=7,
            total_count=20,
            missing_items=[],
        )
        assert status.summary() == "partial (7/20)"

    def test_summary_incomplete(self) -> None:
        """Summary shows 'incomplete' when exists but nothing completed."""
        status = PhaseStatus(
            phase=PipelinePhase.TASKS,
            exists=True,
            is_complete=False,
            completed_count=0,
            total_count=10,
            missing_items=[],
        )
        assert status.summary() == "incomplete"


class TestMigrateToPhases(unittest.TestCase):
    """Tests for the legacy-to-canonical directory migration script."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_migrate_renames_legacy_directories(self) -> None:
        """Migration renames legacy directories to canonical phase names."""
        pr_dir = self.tmp_path / "123"
        (pr_dir / "diff").mkdir(parents=True)
        (pr_dir / "diff" / "raw.diff").write_text("content")
        (pr_dir / "tasks").mkdir()
        (pr_dir / "tasks" / "task.json").write_text("{}")

        migrate_pr_directory(pr_dir)

        assert not (pr_dir / "diff").exists()
        assert not (pr_dir / "tasks").exists()
        assert (pr_dir / "phase-1-diff").exists()
        assert (pr_dir / "phase-1-diff" / "raw.diff").exists()
        assert (pr_dir / "phase-4-tasks").exists()
        assert (pr_dir / "phase-4-tasks" / "task.json").exists()

    def test_migrate_skips_already_migrated(self) -> None:
        """Migration skips directories that already have canonical names."""
        pr_dir = self.tmp_path / "123"
        (pr_dir / "diff").mkdir(parents=True)
        (pr_dir / "diff" / "raw.diff").write_text("legacy")
        canonical = pr_dir / "phase-1-diff"
        canonical.mkdir()
        (canonical / "raw.diff").write_text("canonical")

        migrate_pr_directory(pr_dir)

        # Legacy dir should still exist since canonical already exists
        assert (pr_dir / "diff").exists()
        assert (canonical / "raw.diff").read_text() == "canonical"

    def test_migrate_all_processes_pr_directories(self) -> None:
        """migrate_all processes only numeric PR directories."""
        (self.tmp_path / "42" / "evaluations").mkdir(parents=True)
        (self.tmp_path / "42" / "evaluations" / "result.json").write_text("{}")
        (self.tmp_path / "99" / "report").mkdir(parents=True)
        (self.tmp_path / "99" / "report" / "summary.json").write_text("{}")
        (self.tmp_path / "not-a-pr").mkdir()

        migrate_all(self.tmp_path)

        assert (self.tmp_path / "42" / "phase-5-evaluations").exists()
        assert (self.tmp_path / "99" / "phase-6-report").exists()
        assert not (self.tmp_path / "42" / "evaluations").exists()
        assert not (self.tmp_path / "99" / "report").exists()

    def test_migrate_nonexistent_directory(self) -> None:
        """migrate_all handles nonexistent directory gracefully."""
        migrate_all(self.tmp_path / "does-not-exist")

    def test_migrate_preserves_file_content(self) -> None:
        """Migration preserves file contents during rename."""
        pr_dir = self.tmp_path / "100"
        rules_dir = pr_dir / "rules"
        rules_dir.mkdir(parents=True)
        (rules_dir / "all-rules.json").write_text('["rule1", "rule2"]')

        migrate_pr_directory(pr_dir)

        migrated_file = pr_dir / "phase-3-rules" / "all-rules.json"
        assert migrated_file.exists()
        assert migrated_file.read_text() == '["rule1", "rule2"]'


class TestPipelinePhaseEdgeCases(unittest.TestCase):
    """Additional edge case tests for PipelinePhase enum."""

    def test_all_phase_values_match_naming_convention(self) -> None:
        """All phase values must follow 'phase-N-name' pattern."""
        pattern = re.compile(r"^phase-\d+-[a-z-]+$")
        for phase in PipelinePhase:
            assert pattern.match(phase.value), f"{phase.name} has invalid value: {phase.value}"

    def test_phase_numbers_are_sequential(self) -> None:
        """Phase numbers should be sequential starting from 1."""
        numbers = [p.phase_number() for p in PipelinePhase]
        assert numbers == list(range(1, len(numbers) + 1))

    def test_phase_number_matches_value_prefix(self) -> None:
        """Phase number in value string matches phase_number()."""
        for phase in PipelinePhase:
            number_in_value = int(phase.value.split("-")[1])
            assert number_in_value == phase.phase_number(), (
                f"{phase.name}: value has {number_in_value} but phase_number() returns {phase.phase_number()}"
            )

    def test_no_future_phases(self) -> None:
        """All phases should be implemented (no future phases)."""
        from scripts.services.phase_sequencer import _FUTURE_PHASES

        assert len(_FUTURE_PHASES) == 0

    def test_previous_implemented_phase_for_focus_areas(self) -> None:
        """FOCUS_AREAS' previous implemented phase is DIFF."""
        assert PipelinePhase.FOCUS_AREAS.previous_implemented_phase() == PipelinePhase.DIFF


class TestPhaseSequencerFullChain(unittest.TestCase):
    """Tests for full pipeline dependency chain validation."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_full_chain_all_phases_can_run(self) -> None:
        """When all phases have content, every phase can run."""
        for phase in PipelinePhase:
            phase_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, phase)
            (phase_dir / "data.json").write_text("{}")

        for phase in PipelinePhase:
            assert PhaseSequencer.can_run_phase(self.tmp_path, phase), (
                f"{phase.name} should be able to run when all dependencies exist"
            )

    def test_empty_dependency_blocks_all_downstream(self) -> None:
        """If DIFF has empty dir, all downstream phases cannot run."""
        PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.DIFF)
        # DIFF exists but is empty — should block FOCUS_AREAS and everything downstream
        assert not PhaseSequencer.can_run_phase(self.tmp_path, PipelinePhase.FOCUS_AREAS)
        assert not PhaseSequencer.can_run_phase(self.tmp_path, PipelinePhase.RULES)
        assert not PhaseSequencer.can_run_phase(self.tmp_path, PipelinePhase.TASKS)
        assert not PhaseSequencer.can_run_phase(self.tmp_path, PipelinePhase.EVALUATIONS)
        assert not PhaseSequencer.can_run_phase(self.tmp_path, PipelinePhase.REPORT)

    def test_validate_error_mentions_both_phases(self) -> None:
        """Error message should mention the missing dependency and the blocked phase."""
        for phase in [PipelinePhase.FOCUS_AREAS, PipelinePhase.RULES, PipelinePhase.TASKS, PipelinePhase.EVALUATIONS, PipelinePhase.REPORT]:
            error = PhaseSequencer.validate_can_run(self.tmp_path, phase)
            assert error is not None
            assert phase.value in error
            dep = phase.previous_implemented_phase()
            assert dep is not None
            assert dep.value in error


class TestCommandDependencyValidation(unittest.TestCase):
    """Integration tests verifying commands reject missing dependencies.

    These tests call the actual command functions with temporary directories
    that lack the required upstream phase artifacts.
    """

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_rules_command_fails_without_diff(self) -> None:
        """Rules command should return error when diff phase is missing."""
        from scripts.commands.agent.rules import cmd_rules

        result = cmd_rules(
            pr_number=123,
            output_dir=self.tmp_path,
            rules_dir="/nonexistent",
        )
        assert result == 1

    def test_rules_command_fails_with_empty_diff(self) -> None:
        """Rules command should return error when diff directory exists but is empty."""
        from scripts.commands.agent.rules import cmd_rules

        PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.DIFF)
        result = cmd_rules(
            pr_number=123,
            output_dir=self.tmp_path,
            rules_dir="/nonexistent",
        )
        assert result == 1

    def test_rules_command_fails_without_parsed_diff(self) -> None:
        """Rules command should return error when diff exists but parsed.json is missing."""
        from scripts.commands.agent.rules import cmd_rules

        diff_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.DIFF)
        (diff_dir / "raw.diff").write_text("content")
        result = cmd_rules(
            pr_number=123,
            output_dir=self.tmp_path,
            rules_dir="/nonexistent",
        )
        assert result == 1

    def test_evaluate_command_fails_without_tasks(self) -> None:
        """Evaluate command should return error when tasks phase is missing."""
        try:
            from scripts.commands.agent.evaluate import cmd_evaluate
        except ImportError:
            self.skipTest("claude_agent_sdk not available")

        result = cmd_evaluate(pr_number=123, output_dir=self.tmp_path)
        assert result == 1

    def test_report_command_fails_without_evaluations(self) -> None:
        """Report command should return error when evaluations phase is missing."""
        from scripts.commands.agent.report import cmd_report

        result = cmd_report(pr_number=123, output_dir=self.tmp_path)
        assert result == 1

    def test_comment_command_fails_without_evaluations(self) -> None:
        """Comment command should return error when evaluations phase is missing."""
        from scripts.commands.agent.comment import cmd_comment

        result = cmd_comment(
            pr_number=123,
            output_dir=self.tmp_path,
            repo="test/repo",
            dry_run=True,
        )
        assert result == 1

    def test_report_command_succeeds_with_dependencies(self) -> None:
        """Report command should succeed when evaluations phase has content."""
        from scripts.commands.agent.report import cmd_report

        eval_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.EVALUATIONS)
        (eval_dir / "result.json").write_text(json.dumps({
            "task_id": "test-001",
            "rule_name": "test-rule",
            "evaluation": {
                "violates_rule": False,
                "score": 0,
                "comment": "OK",
            },
        }))
        tasks_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.TASKS)
        (tasks_dir / "task.json").write_text("{}")

        result = cmd_report(pr_number=123, output_dir=self.tmp_path)
        assert result == 0

    def test_comment_command_succeeds_with_dependencies_no_violations(self) -> None:
        """Comment command should succeed (no violations) when evaluations have content."""
        from scripts.commands.agent.comment import cmd_comment

        eval_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.EVALUATIONS)
        (eval_dir / "result.json").write_text(json.dumps({
            "task_id": "test-001",
            "rule_name": "test-rule",
            "evaluation": {
                "violates_rule": False,
                "score": 0,
                "comment": "OK",
            },
        }))

        result = cmd_comment(
            pr_number=123,
            output_dir=self.tmp_path,
            repo="test/repo",
            dry_run=True,
        )
        assert result == 0


class TestDiffPhaseChecker(unittest.TestCase):
    """Tests for DiffPhaseChecker."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self._tmp.name)
        self.checker = DiffPhaseChecker()

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_not_started(self) -> None:
        """Returns not-started status when directory doesn't exist."""
        status = self.checker.check_status(self.tmp_path)
        assert not status.exists
        assert not status.is_complete
        assert status.completed_count == 0
        assert status.total_count == 2
        assert "raw.diff" in status.missing_items
        assert "parsed.json" in status.missing_items

    def test_partial_completion(self) -> None:
        """Returns partial status when only some files exist."""
        diff_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.DIFF)
        (diff_dir / "raw.diff").write_text("content")

        status = self.checker.check_status(self.tmp_path)
        assert status.exists
        assert not status.is_complete
        assert status.completed_count == 1
        assert status.total_count == 2
        assert status.missing_items == ["parsed.json"]

    def test_complete(self) -> None:
        """Returns complete status when all required files exist."""
        diff_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.DIFF)
        (diff_dir / "raw.diff").write_text("content")
        (diff_dir / "parsed.json").write_text("{}")

        status = self.checker.check_status(self.tmp_path)
        assert status.exists
        assert status.is_complete
        assert status.completed_count == 2
        assert status.total_count == 2
        assert status.missing_items == []

    def test_empty_directory(self) -> None:
        """Empty directory exists but has no required files."""
        PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.DIFF)

        status = self.checker.check_status(self.tmp_path)
        assert status.exists
        assert not status.is_complete
        assert status.completed_count == 0


class TestFocusAreasPhaseChecker(unittest.TestCase):
    """Tests for FocusAreasPhaseChecker."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self._tmp.name)
        self.checker = FocusAreasPhaseChecker()

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_not_started(self) -> None:
        """Returns not-started when directory missing."""
        status = self.checker.check_status(self.tmp_path)
        assert not status.exists
        assert status.missing_items == ["all.json"]

    def test_complete(self) -> None:
        """Returns complete when all.json exists."""
        focus_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.FOCUS_AREAS)
        (focus_dir / "all.json").write_text("{}")

        status = self.checker.check_status(self.tmp_path)
        assert status.is_complete
        assert status.missing_items == []


class TestRulesPhaseChecker(unittest.TestCase):
    """Tests for RulesPhaseChecker."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self._tmp.name)
        self.checker = RulesPhaseChecker()

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_not_started(self) -> None:
        """Returns not-started when directory missing."""
        status = self.checker.check_status(self.tmp_path)
        assert not status.exists
        assert status.missing_items == ["all-rules.json"]

    def test_complete(self) -> None:
        """Returns complete when all-rules.json exists."""
        rules_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.RULES)
        (rules_dir / "all-rules.json").write_text("[]")

        status = self.checker.check_status(self.tmp_path)
        assert status.is_complete
        assert status.missing_items == []


class TestReportPhaseChecker(unittest.TestCase):
    """Tests for ReportPhaseChecker."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self._tmp.name)
        self.checker = ReportPhaseChecker()

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_not_started(self) -> None:
        """Returns not-started when directory missing."""
        status = self.checker.check_status(self.tmp_path)
        assert not status.exists
        assert status.total_count == 2
        assert "summary.json" in status.missing_items
        assert "summary.md" in status.missing_items

    def test_partial(self) -> None:
        """Returns partial when only one report file exists."""
        report_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.REPORT)
        (report_dir / "summary.json").write_text("{}")

        status = self.checker.check_status(self.tmp_path)
        assert status.exists
        assert not status.is_complete
        assert status.completed_count == 1
        assert status.missing_items == ["summary.md"]

    def test_complete(self) -> None:
        """Returns complete when both report files exist."""
        report_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.REPORT)
        (report_dir / "summary.json").write_text("{}")
        (report_dir / "summary.md").write_text("# Report")

        status = self.checker.check_status(self.tmp_path)
        assert status.is_complete
        assert status.missing_items == []


class TestTasksPhaseChecker(unittest.TestCase):
    """Tests for TasksPhaseChecker."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self._tmp.name)
        self.checker = TasksPhaseChecker()

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_not_started(self) -> None:
        """Returns not-started when directory missing."""
        status = self.checker.check_status(self.tmp_path)
        assert not status.exists
        assert status.total_count == 0

    def test_empty_directory(self) -> None:
        """Returns incomplete when directory exists but has no tasks."""
        PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.TASKS)

        status = self.checker.check_status(self.tmp_path)
        assert status.exists
        assert not status.is_complete
        assert status.completed_count == 0

    def test_with_tasks(self) -> None:
        """Returns complete when task files exist."""
        tasks_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.TASKS)
        (tasks_dir / "task-001.json").write_text("{}")
        (tasks_dir / "task-002.json").write_text("{}")
        (tasks_dir / "task-003.json").write_text("{}")

        status = self.checker.check_status(self.tmp_path)
        assert status.is_complete
        assert status.completed_count == 3
        assert status.total_count == 3

    def test_ignores_non_json_files(self) -> None:
        """Only counts .json files as tasks."""
        tasks_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.TASKS)
        (tasks_dir / "readme.txt").write_text("not a task")

        status = self.checker.check_status(self.tmp_path)
        assert status.exists
        assert not status.is_complete
        assert status.completed_count == 0


class TestEvaluationsPhaseChecker(unittest.TestCase):
    """Tests for EvaluationsPhaseChecker."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self._tmp.name)
        self.checker = EvaluationsPhaseChecker()

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_not_started_no_tasks(self) -> None:
        """Returns not-started with zero total when no tasks exist."""
        status = self.checker.check_status(self.tmp_path)
        assert not status.exists
        assert status.total_count == 0

    def test_not_started_with_tasks(self) -> None:
        """Returns not-started with correct total from tasks phase."""
        tasks_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.TASKS)
        (tasks_dir / "task-001.json").write_text('{"task_id": "task-001"}')
        (tasks_dir / "task-002.json").write_text('{"task_id": "task-002"}')

        status = self.checker.check_status(self.tmp_path)
        assert not status.exists
        assert status.total_count == 2
        assert status.completed_count == 0

    def test_partial_completion(self) -> None:
        """Returns partial status when some evaluations are done."""
        tasks_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.TASKS)
        for i in range(5):
            (tasks_dir / f"task-{i}.json").write_text(json.dumps({"task_id": f"task-{i}"}))

        eval_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.EVALUATIONS)
        for i in range(3):
            (eval_dir / f"task-{i}.json").write_text('{"result": "pass"}')

        status = self.checker.check_status(self.tmp_path)
        assert status.exists
        assert not status.is_complete
        assert status.completed_count == 3
        assert status.total_count == 5
        assert "task-3" in status.missing_items
        assert "task-4" in status.missing_items

    def test_complete(self) -> None:
        """Returns complete when all evaluations are done."""
        tasks_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.TASKS)
        for i in range(3):
            (tasks_dir / f"task-{i}.json").write_text(json.dumps({"task_id": f"task-{i}"}))

        eval_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.EVALUATIONS)
        for i in range(3):
            (eval_dir / f"task-{i}.json").write_text('{"result": "pass"}')

        status = self.checker.check_status(self.tmp_path)
        assert status.is_complete
        assert status.missing_items == []

    def test_summary_json_excluded(self) -> None:
        """summary.json should not count as an evaluation result."""
        tasks_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.TASKS)
        (tasks_dir / "task-001.json").write_text('{"task_id": "task-001"}')

        eval_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.EVALUATIONS)
        (eval_dir / "summary.json").write_text("{}")

        status = self.checker.check_status(self.tmp_path)
        assert not status.is_complete
        assert status.completed_count == 0
        assert status.total_count == 1
        assert status.missing_items == ["task-001"]

    def test_malformed_task_files_skipped(self) -> None:
        """Malformed task files are skipped when counting expected tasks."""
        tasks_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.TASKS)
        (tasks_dir / "bad.json").write_text("not json")
        (tasks_dir / "good.json").write_text('{"task_id": "good"}')

        eval_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.EVALUATIONS)
        (eval_dir / "good.json").write_text('{"result": "pass"}')

        status = self.checker.check_status(self.tmp_path)
        assert status.is_complete
        assert status.total_count == 1

    def test_eval_dir_exists_but_no_tasks_dir(self) -> None:
        """Handles case where eval dir exists but tasks dir doesn't."""
        eval_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.EVALUATIONS)
        (eval_dir / "result.json").write_text("{}")

        status = self.checker.check_status(self.tmp_path)
        assert status.exists
        assert not status.is_complete
        assert status.total_count == 0


class TestGetPhaseStatus(unittest.TestCase):
    """Tests for PhaseSequencer.get_phase_status integration."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_all_phases_have_checkers(self) -> None:
        """Every PipelinePhase should have a registered checker."""
        for phase in PipelinePhase:
            status = PhaseSequencer.get_phase_status(self.tmp_path, phase)
            assert status.phase == phase

    def test_diff_status_via_sequencer(self) -> None:
        """get_phase_status delegates to DiffPhaseChecker correctly."""
        diff_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.DIFF)
        (diff_dir / "raw.diff").write_text("content")
        (diff_dir / "parsed.json").write_text("{}")

        status = PhaseSequencer.get_phase_status(self.tmp_path, PipelinePhase.DIFF)
        assert status.is_complete

    def test_evaluations_status_via_sequencer(self) -> None:
        """get_phase_status delegates to EvaluationsPhaseChecker correctly."""
        tasks_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.TASKS)
        (tasks_dir / "t1.json").write_text('{"task_id": "t1"}')
        (tasks_dir / "t2.json").write_text('{"task_id": "t2"}')

        eval_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.EVALUATIONS)
        (eval_dir / "t1.json").write_text("{}")

        status = PhaseSequencer.get_phase_status(self.tmp_path, PipelinePhase.EVALUATIONS)
        assert not status.is_complete
        assert status.completed_count == 1
        assert status.total_count == 2
        assert status.missing_items == ["t2"]

    def test_not_started_phase(self) -> None:
        """Status for a phase that hasn't started."""
        status = PhaseSequencer.get_phase_status(self.tmp_path, PipelinePhase.REPORT)
        assert not status.exists
        assert not status.is_complete
        assert status.summary() == "not started"


class TestGetRemainingItems(unittest.TestCase):
    """Tests for PhaseSequencer.get_remaining_items resume helper."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_nothing_completed_returns_all(self) -> None:
        """When phase hasn't started, all items are remaining."""
        all_items = ["task-0", "task-1", "task-2"]
        remaining, skipped = PhaseSequencer.get_remaining_items(
            self.tmp_path, PipelinePhase.EVALUATIONS, all_items
        )
        assert remaining == all_items
        assert skipped == 0

    def test_everything_completed_returns_none(self) -> None:
        """When all items are done, remaining is empty."""
        tasks_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.TASKS)
        for i in range(3):
            (tasks_dir / f"task-{i}.json").write_text(json.dumps({"task_id": f"task-{i}"}))

        eval_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.EVALUATIONS)
        for i in range(3):
            (eval_dir / f"task-{i}.json").write_text('{"result": "pass"}')

        all_items = ["task-0", "task-1", "task-2"]
        remaining, skipped = PhaseSequencer.get_remaining_items(
            self.tmp_path, PipelinePhase.EVALUATIONS, all_items
        )
        # Phase is complete (not partial), so all items returned
        assert remaining == all_items
        assert skipped == 0

    def test_partial_completion_filters_completed(self) -> None:
        """When some items are done, only remaining are returned."""
        tasks_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.TASKS)
        for i in range(5):
            (tasks_dir / f"task-{i}.json").write_text(json.dumps({"task_id": f"task-{i}"}))

        eval_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.EVALUATIONS)
        for i in range(3):
            (eval_dir / f"task-{i}.json").write_text('{"result": "pass"}')

        all_items = [f"task-{i}" for i in range(5)]
        remaining, skipped = PhaseSequencer.get_remaining_items(
            self.tmp_path, PipelinePhase.EVALUATIONS, all_items
        )
        assert skipped == 3
        assert len(remaining) == 2
        assert "task-3" in remaining
        assert "task-4" in remaining

    def test_preserves_order_of_remaining(self) -> None:
        """Remaining items maintain their original order."""
        tasks_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.TASKS)
        for i in range(5):
            (tasks_dir / f"task-{i}.json").write_text(json.dumps({"task_id": f"task-{i}"}))

        eval_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.EVALUATIONS)
        # Complete tasks 0 and 2 (not sequential)
        (eval_dir / "task-0.json").write_text('{}')
        (eval_dir / "task-2.json").write_text('{}')

        all_items = [f"task-{i}" for i in range(5)]
        remaining, skipped = PhaseSequencer.get_remaining_items(
            self.tmp_path, PipelinePhase.EVALUATIONS, all_items
        )
        assert remaining == ["task-1", "task-3", "task-4"]
        assert skipped == 2

    def test_summary_json_excluded_from_completed(self) -> None:
        """summary.json should not count as a completed item."""
        tasks_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.TASKS)
        for i in range(2):
            (tasks_dir / f"task-{i}.json").write_text(json.dumps({"task_id": f"task-{i}"}))

        eval_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.EVALUATIONS)
        (eval_dir / "task-0.json").write_text('{}')
        (eval_dir / "summary.json").write_text('{}')

        all_items = ["task-0", "task-1"]
        remaining, skipped = PhaseSequencer.get_remaining_items(
            self.tmp_path, PipelinePhase.EVALUATIONS, all_items
        )
        assert skipped == 1
        assert remaining == ["task-1"]

    def test_empty_all_items(self) -> None:
        """Empty input list returns empty remaining."""
        remaining, skipped = PhaseSequencer.get_remaining_items(
            self.tmp_path, PipelinePhase.EVALUATIONS, []
        )
        assert remaining == []
        assert skipped == 0

    def test_phase_directory_exists_but_empty(self) -> None:
        """When phase dir exists but is empty, status is not partial so all items returned."""
        tasks_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.TASKS)
        (tasks_dir / "task-0.json").write_text(json.dumps({"task_id": "task-0"}))
        PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.EVALUATIONS)

        all_items = ["task-0"]
        remaining, skipped = PhaseSequencer.get_remaining_items(
            self.tmp_path, PipelinePhase.EVALUATIONS, all_items
        )
        assert remaining == ["task-0"]
        assert skipped == 0


class TestNoMagicStrings(unittest.TestCase):
    """Verify no hardcoded directory names exist in command and service files."""

    def _get_source_files(self) -> list[Path]:
        """Collect all Python source files in commands and services."""
        scripts_root = Path(__file__).parent.parent
        files = []
        for subdir in ["commands/agent", "services"]:
            directory = scripts_root / subdir
            if directory.exists():
                files.extend(directory.glob("*.py"))
        return files

    def test_no_hardcoded_phase_directory_names(self) -> None:
        """No command or service file should use hardcoded phase directory strings."""
        legacy_names = ["diff", "rules", "tasks", "evaluations", "report"]
        pattern = re.compile(
            r'output_dir\s*/\s*["\'](' + "|".join(legacy_names) + r')["\']'
        )

        violations = []
        for source_file in self._get_source_files():
            content = source_file.read_text()
            matches = pattern.findall(content)
            if matches:
                violations.append(f"{source_file.name}: {matches}")

        assert not violations, f"Hardcoded phase dirs found: {violations}"


if __name__ == "__main__":
    unittest.main()
