"""Tests for PhaseSequencer service.

Tests cover:
- PipelinePhase enum ordering and navigation
- PhaseSequencer directory management
- Dependency validation
"""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from scripts.services.phase_sequencer import PhaseSequencer, PipelinePhase


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

    def test_previous_implemented_phase_skips_future(self) -> None:
        """RULES skips FOCUS_AREAS (future) and returns DIFF."""
        assert PipelinePhase.RULES.previous_implemented_phase() == PipelinePhase.DIFF

    def test_previous_implemented_phase_normal_chain(self) -> None:
        """Non-future phases return the immediate predecessor."""
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

    def test_can_run_rules_skips_focus_areas(self) -> None:
        """RULES can run if DIFF exists, even though FOCUS_AREAS doesn't."""
        diff_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.DIFF)
        (diff_dir / "parsed.json").write_text("{}")
        assert PhaseSequencer.can_run_phase(self.tmp_path, PipelinePhase.RULES)

    def test_cannot_run_rules_without_diff(self) -> None:
        """RULES cannot run without DIFF even though FOCUS_AREAS is skipped."""
        assert not PhaseSequencer.can_run_phase(self.tmp_path, PipelinePhase.RULES)

    def test_validate_can_run_returns_none_when_valid(self) -> None:
        """validate_can_run returns None when phase can run."""
        diff_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.DIFF)
        (diff_dir / "raw.diff").write_text("content")
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


class TestPhaseSequencerLegacyDirectories(unittest.TestCase):
    """Tests for legacy directory name support in phase_exists."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_phase_exists_with_legacy_diff_dir(self) -> None:
        """phase_exists detects legacy 'diff' directory."""
        legacy_dir = self.tmp_path / "diff"
        legacy_dir.mkdir()
        (legacy_dir / "parsed.json").write_text("{}")
        assert PhaseSequencer.phase_exists(self.tmp_path, PipelinePhase.DIFF)

    def test_phase_exists_with_legacy_tasks_dir(self) -> None:
        """phase_exists detects legacy 'tasks' directory."""
        legacy_dir = self.tmp_path / "tasks"
        legacy_dir.mkdir()
        (legacy_dir / "task.json").write_text("{}")
        assert PhaseSequencer.phase_exists(self.tmp_path, PipelinePhase.TASKS)

    def test_phase_exists_with_legacy_evaluations_dir(self) -> None:
        """phase_exists detects legacy 'evaluations' directory."""
        legacy_dir = self.tmp_path / "evaluations"
        legacy_dir.mkdir()
        (legacy_dir / "result.json").write_text("{}")
        assert PhaseSequencer.phase_exists(self.tmp_path, PipelinePhase.EVALUATIONS)

    def test_phase_exists_empty_legacy_dir_returns_false(self) -> None:
        """Empty legacy directory should return False."""
        legacy_dir = self.tmp_path / "diff"
        legacy_dir.mkdir()
        assert not PhaseSequencer.phase_exists(self.tmp_path, PipelinePhase.DIFF)

    def test_can_run_with_legacy_dependency(self) -> None:
        """can_run_phase works with legacy directory names."""
        legacy_dir = self.tmp_path / "tasks"
        legacy_dir.mkdir()
        (legacy_dir / "task.json").write_text("{}")
        assert PhaseSequencer.can_run_phase(self.tmp_path, PipelinePhase.EVALUATIONS)

    def test_phase_exists_prefers_canonical_over_legacy(self) -> None:
        """Canonical phase directory is checked before legacy."""
        canonical_dir = PhaseSequencer.ensure_phase_dir(self.tmp_path, PipelinePhase.DIFF)
        (canonical_dir / "raw.diff").write_text("content")
        assert PhaseSequencer.phase_exists(self.tmp_path, PipelinePhase.DIFF)


if __name__ == "__main__":
    unittest.main()
