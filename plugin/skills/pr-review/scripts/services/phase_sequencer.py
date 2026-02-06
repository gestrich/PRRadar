"""Centralized phase management for PRRadar pipeline.

Provides single source of truth for phase names and basic validation.
"""

from __future__ import annotations

from enum import Enum
from pathlib import Path


class PipelinePhase(Enum):
    """Pipeline phases in execution order.

    Each phase transforms artifacts from previous phases.
    The enum order defines the execution sequence.
    """

    DIFF = "phase-1-diff"
    FOCUS_AREAS = "phase-2-focus-areas"  # Future: focus areas feature
    RULES = "phase-3-rules"
    TASKS = "phase-4-tasks"
    EVALUATIONS = "phase-5-evaluations"
    REPORT = "phase-6-report"

    def phase_number(self) -> int:
        """Get the numeric phase number (1-6)."""
        return list(PipelinePhase).index(self) + 1

    def previous_phase(self) -> PipelinePhase | None:
        """Get the phase that must complete before this one."""
        phases = list(PipelinePhase)
        index = phases.index(self)
        return phases[index - 1] if index > 0 else None


class PhaseSequencer:
    """Manages phase directory paths and sequencing.

    All methods are static as they are pure utilities with no state dependency.
    """

    @staticmethod
    def get_phase_dir(output_dir: Path, phase: PipelinePhase) -> Path:
        """Get the directory path for a given phase.

        Args:
            output_dir: PR-specific output directory
            phase: The pipeline phase

        Returns:
            Path to the phase directory
        """
        return output_dir / phase.value

    @staticmethod
    def ensure_phase_dir(output_dir: Path, phase: PipelinePhase) -> Path:
        """Get and create the directory for a phase.

        Args:
            output_dir: PR-specific output directory
            phase: The pipeline phase

        Returns:
            Path to the phase directory (created if needed)
        """
        phase_dir = PhaseSequencer.get_phase_dir(output_dir, phase)
        phase_dir.mkdir(parents=True, exist_ok=True)
        return phase_dir

    @staticmethod
    def phase_exists(output_dir: Path, phase: PipelinePhase) -> bool:
        """Check if a phase directory exists and has content.

        Args:
            output_dir: PR-specific output directory
            phase: The pipeline phase

        Returns:
            True if phase directory exists and is non-empty
        """
        phase_dir = PhaseSequencer.get_phase_dir(output_dir, phase)
        if not phase_dir.exists():
            return False
        return any(phase_dir.iterdir())
