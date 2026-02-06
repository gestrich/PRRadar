"""Tests for PhaseSequencer service.

Tests cover:
- PipelinePhase enum ordering and navigation
- PhaseSequencer directory management
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


if __name__ == "__main__":
    unittest.main()
