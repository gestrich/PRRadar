"""Migrate existing output directories to phase-based naming.

Renames legacy directory names (e.g., 'diff', 'tasks') to canonical
phase directory names (e.g., 'phase-1-diff', 'phase-4-tasks').
"""

from __future__ import annotations

import sys
from pathlib import Path

from prradar.services.phase_sequencer import PhaseSequencer, PipelinePhase


LEGACY_TO_PHASE_MAPPING = {
    "diff": PipelinePhase.DIFF,
    "rules": PipelinePhase.RULES,
    "tasks": PipelinePhase.TASKS,
    "evaluations": PipelinePhase.EVALUATIONS,
    "report": PipelinePhase.REPORT,
}


def migrate_pr_directory(pr_dir: Path) -> None:
    """Migrate a single PR directory to phase naming."""
    print(f"Migrating {pr_dir}...")

    for legacy_name, phase in LEGACY_TO_PHASE_MAPPING.items():
        legacy_dir = pr_dir / legacy_name
        if legacy_dir.exists():
            new_dir = PhaseSequencer.get_phase_dir(pr_dir, phase)
            if not new_dir.exists():
                legacy_dir.rename(new_dir)
                print(f"  {legacy_name}/ → {phase.value}/")
            else:
                print(f"  {legacy_name}/ already migrated")


def migrate_all(output_base: Path) -> None:
    """Migrate all PR directories in output directory."""
    if not output_base.exists():
        print(f"Output directory not found: {output_base}")
        return

    migrated = 0
    for pr_dir in output_base.iterdir():
        if pr_dir.is_dir() and pr_dir.name.isdigit():
            migrate_pr_directory(pr_dir)
            migrated += 1

    print(f"\nMigrated {migrated} PR directories")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python -m prradar.commands.migrate_to_phases <output_dir>")
        sys.exit(1)

    output_base = Path(sys.argv[1])
    migrate_all(output_base)
