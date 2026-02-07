"""Status command for displaying pipeline progress.

Shows detailed completion status for all pipeline phases,
including visual indicators and progress percentages.
"""

from pathlib import Path

from prradar.services.phase_sequencer import PhaseSequencer


def cmd_status(output_dir: Path) -> int:
    """Show pipeline status for a PR.

    Args:
        output_dir: PR-specific output directory

    Returns:
        Exit code (0 for success, 1 for error)
    """
    if not output_dir.exists():
        print(f"Output directory not found: {output_dir}")
        return 1

    PhaseSequencer.print_pipeline_status(output_dir)
    return 0
