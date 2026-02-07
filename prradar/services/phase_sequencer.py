"""Centralized phase management for PRRadar pipeline.

Provides single source of truth for phase names and basic validation.
Includes phase completion checkers for resume and status tracking.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Protocol


# Phases not yet implemented (skipped during dependency validation)
_FUTURE_PHASES: set[str] = set()

# Phase 1 artifact filenames
DIFF_RAW_FILENAME = "diff-raw.diff"
DIFF_PARSED_JSON_FILENAME = "diff-parsed.json"
DIFF_PARSED_MD_FILENAME = "diff-parsed.md"
GH_PR_FILENAME = "gh-pr.json"
GH_COMMENTS_FILENAME = "gh-comments.json"
GH_REPO_FILENAME = "gh-repo.json"
EFFECTIVE_DIFF_PARSED_JSON_FILENAME = "effective-diff-parsed.json"
EFFECTIVE_DIFF_PARSED_MD_FILENAME = "effective-diff-parsed.md"
EFFECTIVE_DIFF_MOVES_FILENAME = "effective-diff-moves.json"


class PipelinePhase(Enum):
    """Pipeline phases in execution order.

    Each phase transforms artifacts from previous phases.
    The enum order defines the execution sequence.
    """

    DIFF = "phase-1-pull-request"
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


# ============================================================
# Phase Completion Checkers
# ============================================================


class PhaseChecker(Protocol):
    """Protocol for checking phase completion status."""

    def check_status(self, output_dir: Path) -> PhaseStatus:
        """Check completion status for this phase."""
        ...


class _FixedFileChecker:
    """Checker for phases with a known set of required files."""

    def __init__(self, phase: PipelinePhase, required_files: list[str]):
        self._phase = phase
        self._required_files = required_files

    def check_status(self, output_dir: Path) -> PhaseStatus:
        phase_dir = PhaseSequencer.get_phase_dir(output_dir, self._phase)

        if not phase_dir.exists():
            return PhaseStatus(
                phase=self._phase,
                exists=False,
                is_complete=False,
                completed_count=0,
                total_count=len(self._required_files),
                missing_items=self._required_files.copy(),
            )

        missing = [f for f in self._required_files if not (phase_dir / f).exists()]
        completed = len(self._required_files) - len(missing)

        return PhaseStatus(
            phase=self._phase,
            exists=True,
            is_complete=len(missing) == 0,
            completed_count=completed,
            total_count=len(self._required_files),
            missing_items=missing,
        )


class DiffPhaseChecker(_FixedFileChecker):
    """Checks completion status for phase-1-pull-request."""

    REQUIRED_FILES = [
        DIFF_RAW_FILENAME,
        DIFF_PARSED_JSON_FILENAME,
        GH_PR_FILENAME,
        GH_COMMENTS_FILENAME,
        GH_REPO_FILENAME,
        EFFECTIVE_DIFF_PARSED_JSON_FILENAME,
        EFFECTIVE_DIFF_PARSED_MD_FILENAME,
        EFFECTIVE_DIFF_MOVES_FILENAME,
    ]

    def __init__(self) -> None:
        super().__init__(PipelinePhase.DIFF, self.REQUIRED_FILES)


class FocusAreasPhaseChecker(_FixedFileChecker):
    """Checks completion status for phase-2-focus-areas."""

    REQUIRED_FILES = ["all.json"]

    def __init__(self) -> None:
        super().__init__(PipelinePhase.FOCUS_AREAS, self.REQUIRED_FILES)


class RulesPhaseChecker(_FixedFileChecker):
    """Checks completion status for phase-3-rules."""

    REQUIRED_FILES = ["all-rules.json"]

    def __init__(self) -> None:
        super().__init__(PipelinePhase.RULES, self.REQUIRED_FILES)


class ReportPhaseChecker(_FixedFileChecker):
    """Checks completion status for phase-6-report."""

    REQUIRED_FILES = ["summary.json", "summary.md"]

    def __init__(self) -> None:
        super().__init__(PipelinePhase.REPORT, self.REQUIRED_FILES)


class TasksPhaseChecker:
    """Checks completion status for phase-4-tasks.

    Tasks are dynamically generated, so completion is based on
    whether any task files exist in the directory.
    """

    def check_status(self, output_dir: Path) -> PhaseStatus:
        tasks_dir = PhaseSequencer.get_phase_dir(output_dir, PipelinePhase.TASKS)

        if not tasks_dir.exists():
            return PhaseStatus(
                phase=PipelinePhase.TASKS,
                exists=False,
                is_complete=False,
                completed_count=0,
                total_count=0,
                missing_items=[],
            )

        task_files = list(tasks_dir.glob("*.json"))
        has_tasks = len(task_files) > 0

        return PhaseStatus(
            phase=PipelinePhase.TASKS,
            exists=True,
            is_complete=has_tasks,
            completed_count=len(task_files),
            total_count=len(task_files),
            missing_items=[],
        )


class EvaluationsPhaseChecker:
    """Checks completion status for phase-5-evaluations.

    Compares evaluation results against expected tasks from phase-4-tasks.
    """

    def check_status(self, output_dir: Path) -> PhaseStatus:
        eval_dir = PhaseSequencer.get_phase_dir(output_dir, PipelinePhase.EVALUATIONS)
        tasks_dir = PhaseSequencer.get_phase_dir(output_dir, PipelinePhase.TASKS)

        if not eval_dir.exists():
            task_count = len(list(tasks_dir.glob("*.json"))) if tasks_dir.exists() else 0
            return PhaseStatus(
                phase=PipelinePhase.EVALUATIONS,
                exists=False,
                is_complete=False,
                completed_count=0,
                total_count=task_count,
                missing_items=[],
            )

        expected_ids = set()
        if tasks_dir.exists():
            for task_file in tasks_dir.glob("*.json"):
                try:
                    task_data = json.loads(task_file.read_text())
                    expected_ids.add(task_data["task_id"])
                except (json.JSONDecodeError, KeyError):
                    continue

        completed_ids = {
            f.stem for f in eval_dir.glob("*.json") if f.name != "summary.json"
        }
        missing = sorted(expected_ids - completed_ids)

        return PhaseStatus(
            phase=PipelinePhase.EVALUATIONS,
            exists=True,
            is_complete=len(missing) == 0 and len(expected_ids) > 0,
            completed_count=len(completed_ids),
            total_count=len(expected_ids),
            missing_items=missing,
        )


class PhaseSequencer:
    """Manages phase directory paths and sequencing.

    All methods are static as they are pure utilities with no state dependency.
    """

    _CHECKERS: dict[PipelinePhase, PhaseChecker] = {
        PipelinePhase.DIFF: DiffPhaseChecker(),
        PipelinePhase.FOCUS_AREAS: FocusAreasPhaseChecker(),
        PipelinePhase.RULES: RulesPhaseChecker(),
        PipelinePhase.TASKS: TasksPhaseChecker(),
        PipelinePhase.EVALUATIONS: EvaluationsPhaseChecker(),
        PipelinePhase.REPORT: ReportPhaseChecker(),
    }

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

    @staticmethod
    def get_remaining_items(
        output_dir: Path,
        phase: PipelinePhase,
        all_items: list[str],
    ) -> tuple[list[str], int]:
        """Get items that still need processing.

        Args:
            output_dir: PR-specific output directory
            phase: The phase being processed
            all_items: All item IDs that should be processed

        Returns:
            Tuple of (remaining_items, skipped_count)
        """
        status = PhaseSequencer.get_phase_status(output_dir, phase)

        if not status.is_partial():
            return all_items, 0

        phase_dir = PhaseSequencer.get_phase_dir(output_dir, phase)
        completed = {
            f.stem for f in phase_dir.glob("*.json") if f.name != "summary.json"
        }

        remaining = [item_id for item_id in all_items if item_id not in completed]
        skipped = len(all_items) - len(remaining)

        return remaining, skipped

    @staticmethod
    def get_phase_status(output_dir: Path, phase: PipelinePhase) -> PhaseStatus:
        """Get detailed completion status for a phase.

        Args:
            output_dir: PR-specific output directory
            phase: The pipeline phase to check

        Returns:
            PhaseStatus with completion details
        """
        checker = PhaseSequencer._CHECKERS.get(phase)
        if not checker:
            return PhaseStatus(
                phase=phase,
                exists=False,
                is_complete=False,
                completed_count=0,
                total_count=0,
                missing_items=[],
            )

        return checker.check_status(output_dir)

    @staticmethod
    def get_all_statuses(output_dir: Path) -> dict[PipelinePhase, PhaseStatus]:
        """Get status for all phases.

        Args:
            output_dir: PR-specific output directory

        Returns:
            Dictionary mapping each phase to its status
        """
        return {
            phase: PhaseSequencer.get_phase_status(output_dir, phase)
            for phase in PipelinePhase
        }

    @staticmethod
    def print_pipeline_status(output_dir: Path) -> None:
        """Print formatted pipeline status summary.

        Args:
            output_dir: PR-specific output directory
        """
        statuses = PhaseSequencer.get_all_statuses(output_dir)

        print("\nPipeline Status:")
        print("=" * 60)

        for phase in PipelinePhase:
            status = statuses[phase]

            if status.is_complete:
                indicator = "✓"
            elif status.is_partial():
                indicator = "⚠"
            elif status.exists:
                indicator = "✗"
            else:
                indicator = " "

            if status.total_count > 0:
                progress = f"{status.completed_count}/{status.total_count}"
                pct = status.completion_percentage()
                progress += f" ({pct:.0f}%)"
            else:
                progress = status.summary()

            print(f"  {indicator} {phase.value:<25} {progress}")
