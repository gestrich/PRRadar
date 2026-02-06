"""Centralized phase management for PRRadar pipeline.

Provides single source of truth for phase names and basic validation.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from pathlib import Path


# Phases not yet implemented (skipped during dependency validation)
_FUTURE_PHASES: set[str] = set()


class PipelinePhase(Enum):
    """Pipeline phases in execution order.

    Each phase transforms artifacts from previous phases.
    The enum order defines the execution sequence.
    """

    DIFF = "phase-1-diff"
    FOCUS_AREAS = "phase-2-focus-areas"
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

    def previous_implemented_phase(self) -> PipelinePhase | None:
        """Get the nearest previous phase that is implemented.

        Skips future/unimplemented phases in the chain.
        """
        phases = list(PipelinePhase)
        index = phases.index(self)
        for i in range(index - 1, -1, -1):
            if phases[i].value not in _FUTURE_PHASES:
                return phases[i]
        return None


@dataclass
class PhaseStatus:
    """Detailed status of a pipeline phase.

    Tracks completion state for resumability and progress reporting.
    """

    phase: PipelinePhase
    exists: bool
    is_complete: bool
    completed_count: int
    total_count: int
    missing_items: list[str]

    def completion_percentage(self) -> float:
        """Get completion percentage (0.0 to 100.0)."""
        if self.total_count == 0:
            return 100.0 if self.is_complete else 0.0
        return (self.completed_count / self.total_count) * 100.0

    def is_partial(self) -> bool:
        """Check if phase is partially complete."""
        return self.exists and not self.is_complete and self.completed_count > 0

    def summary(self) -> str:
        """Get human-readable status summary."""
        if not self.exists:
            return "not started"
        if self.is_complete:
            return "complete"
        if self.is_partial():
            return f"partial ({self.completed_count}/{self.total_count})"
        return "incomplete"


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
        return phase_dir.exists() and any(phase_dir.iterdir())

    @staticmethod
    def can_run_phase(output_dir: Path, phase: PipelinePhase) -> bool:
        """Check if a phase can run (dependencies satisfied).

        Skips unimplemented phases when checking dependencies.

        Args:
            output_dir: PR-specific output directory
            phase: The pipeline phase to check

        Returns:
            True if dependencies are satisfied
        """
        previous = phase.previous_implemented_phase()
        if not previous:
            return True

        return PhaseSequencer.phase_exists(output_dir, previous)

    @staticmethod
    def validate_can_run(output_dir: Path, phase: PipelinePhase) -> str | None:
        """Validate phase can run, returning error message if not.

        Args:
            output_dir: PR-specific output directory
            phase: The pipeline phase to check

        Returns:
            None if can run, otherwise error message for user
        """
        if PhaseSequencer.can_run_phase(output_dir, phase):
            return None

        previous = phase.previous_implemented_phase()
        if not previous:
            return None

        return f"Cannot run {phase.value}: {previous.value} has not completed"
