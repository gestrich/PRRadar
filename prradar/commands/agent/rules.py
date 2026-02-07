"""Agent rules command - collect and filter applicable rules.

Loads rules from a directory, determines needed focus types,
generates focus areas, and creates evaluation tasks by pairing
each rule with focus areas of matching type.

Requires:
    <output-dir>/<pr-number>/phase-1-pull-request/diff-parsed.json  - Structured diff with hunks

Artifact outputs:
    <output-dir>/<pr-number>/phase-2-focus-areas/method.json  - Method-level focus areas (if needed)
    <output-dir>/<pr-number>/phase-2-focus-areas/file.json    - File-level focus areas (if needed)
    <output-dir>/<pr-number>/phase-3-rules/all-rules.json     - All collected rules
    <output-dir>/<pr-number>/phase-4-tasks/*.json              - Evaluation tasks (rule+focus_area)
"""

from __future__ import annotations

import asyncio
import json
from datetime import datetime, timezone
from pathlib import Path

from prradar.domain.diff import Hunk
from prradar.domain.evaluation_task import EvaluationTask
from prradar.domain.focus_area import FocusArea, FocusType
from prradar.services.focus_generator import FocusGenerationResult, FocusGeneratorService
from prradar.services.phase_sequencer import DIFF_PARSED_JSON_FILENAME, PhaseSequencer, PipelinePhase
from prradar.services.rule_loader import RuleLoaderService


def cmd_rules(pr_number: int, output_dir: Path, rules_dir: str) -> int:
    """Execute the rules command.

    Args:
        pr_number: PR number being analyzed
        output_dir: PR-specific output directory (already includes PR number)
        rules_dir: Path to directory containing rule markdown files

    Returns:
        Exit code (0 for success, non-zero for error)
    """
    print(f"[rules] Collecting rules for PR #{pr_number}...")
    print(f"  Rules directory: {rules_dir}")

    # Validate dependencies
    error = PhaseSequencer.validate_can_run(output_dir, PipelinePhase.FOCUS_AREAS)
    if error:
        print(f"  Error: {error}")
        print("  Run 'agent diff' first to collect PR data")
        return 1

    # Verify diff artifacts exist
    parsed_diff_path = PhaseSequencer.get_phase_dir(output_dir, PipelinePhase.DIFF) / DIFF_PARSED_JSON_FILENAME
    if not parsed_diff_path.exists():
        print(f"  Error: Diff not found at {parsed_diff_path}")
        print("  Run 'agent diff' first to collect PR data")
        return 1

    # Load parsed diff and reconstruct Hunk objects
    print("  Loading diff...")
    parsed_diff = json.loads(parsed_diff_path.read_text())
    hunk_dicts = parsed_diff.get("hunks", [])
    print(f"  Found {len(hunk_dicts)} hunks in diff")

    if not hunk_dicts:
        print("  No hunks to analyze - empty diff")
        return 0

    hunks = _reconstruct_hunks(hunk_dicts)

    # Load rules first to determine needed focus types
    try:
        rule_loader = RuleLoaderService.create(rules_dir)
    except ValueError as e:
        print(f"  Error: {e}")
        return 1

    print("  Loading rules...")
    all_rules = rule_loader.load_all_rules()
    print(f"  Loaded {len(all_rules)} rules")

    if not all_rules:
        print("  Warning: No rules found in rules directory")
        return 0

    # Determine which focus types are needed based on loaded rules
    needed_types = {rule.focus_type for rule in all_rules}
    print(f"  Needed focus types: {', '.join(t.value for t in sorted(needed_types, key=lambda t: t.value))}")

    # Generate focus areas for needed types only
    print("  Generating focus areas...")
    try:
        focus_result = asyncio.run(
            FocusGeneratorService().generate_all_focus_areas(hunks, pr_number, requested_types=needed_types)
        )
    except Exception as e:
        print(f"  Error generating focus areas: {e}")
        print("  Falling back to hunk-level focus areas...")
        focus_result = _fallback_focus_areas(hunks, hunk_dicts, pr_number)

    focus_areas = focus_result.focus_areas
    print(f"  Found {len(focus_areas)} focus areas across {len(hunks)} hunks")
    if focus_result.generation_cost_usd > 0:
        print(f"  Generation cost: ${focus_result.generation_cost_usd:.4f}")

    # Save focus areas to per-type files in phase-2-focus-areas/
    focus_dir = PhaseSequencer.ensure_phase_dir(output_dir, PipelinePhase.FOCUS_AREAS)
    generated_at = datetime.now(timezone.utc).isoformat()

    for focus_type in needed_types:
        typed_areas = [fa for fa in focus_areas if fa.focus_type == focus_type]
        typed_cost = focus_result.generation_cost_usd if focus_type == FocusType.METHOD else 0.0
        type_file = focus_dir / f"{focus_type.value}.json"
        type_data = {
            "pr_number": pr_number,
            "generated_at": generated_at,
            "focus_type": focus_type.value,
            "focus_areas": [fa.to_dict() for fa in typed_areas],
            "total_hunks_processed": focus_result.total_hunks_processed,
            "generation_cost_usd": typed_cost,
        }
        type_file.write_text(json.dumps(type_data, indent=2))
        print(f"  Wrote {type_file} ({len(typed_areas)} focus areas)")

    # Write all rules to rules/all-rules.json
    rules_output_dir = PhaseSequencer.ensure_phase_dir(output_dir, PipelinePhase.RULES)

    all_rules_path = rules_output_dir / "all-rules.json"
    all_rules_data = [rule.to_dict() for rule in all_rules]
    all_rules_path.write_text(json.dumps(all_rules_data, indent=2))
    print(f"  Wrote {all_rules_path}")

    # Create tasks directory
    tasks_dir = PhaseSequencer.ensure_phase_dir(output_dir, PipelinePhase.TASKS)

    # Clear any existing task files
    for existing_task in tasks_dir.glob("*.json"):
        existing_task.unlink()

    # Pair rules with focus areas of matching type, then filter
    print("  Filtering rules and creating tasks...")
    tasks_created = 0
    skipped_no_rules = 0

    for focus_area in focus_areas:
        matching_rules = [r for r in all_rules if r.focus_type == focus_area.focus_type]
        applicable_rules = rule_loader.filter_rules_for_focus_area(
            matching_rules, focus_area
        )

        if not applicable_rules:
            skipped_no_rules += 1
            continue

        for rule in applicable_rules:
            task = EvaluationTask.create(rule=rule, focus_area=focus_area)
            task_path = tasks_dir / task.suggested_filename()
            task_path.write_text(json.dumps(task.to_dict(), indent=2))
            tasks_created += 1

    # Summary
    unique_files = sorted(set(fa.file_path for fa in focus_areas))
    print()
    print(f"Rules Summary:")
    print(f"  Total rules loaded: {len(all_rules)}")
    print(f"  Files in diff: {len(unique_files)}")
    print(f"  Focus areas analyzed: {len(focus_areas)}")
    print(f"  Focus areas with no matching rules: {skipped_no_rules}")
    print(f"  Evaluation tasks created: {tasks_created}")
    print()
    print(f"Artifacts saved to: {output_dir}")

    return 0


def _reconstruct_hunks(hunk_dicts: list[dict]) -> list[Hunk]:
    """Reconstruct Hunk objects from diff-parsed.json dictionaries.

    The diff-parsed.json stores hunks with annotated content. We reconstruct
    Hunk objects with enough data for the focus generator to work.

    Args:
        hunk_dicts: List of hunk dictionaries from diff-parsed.json

    Returns:
        List of Hunk objects
    """
    hunks: list[Hunk] = []
    for h in hunk_dicts:
        hunks.append(
            Hunk(
                file_path=h.get("file_path", ""),
                content=h.get("content", ""),
                new_start=h.get("new_start", 0),
                new_length=h.get("new_length", 0),
                old_start=h.get("old_start", 0),
                old_length=h.get("old_length", 0),
            )
        )
    return hunks


def _fallback_focus_areas(
    hunks: list[Hunk],
    hunk_dicts: list[dict],
    pr_number: int,
) -> FocusGenerationResult:
    """Create hunk-level focus areas without calling Claude.

    Used as a fallback when focus generation fails.
    Tags all focus areas as METHOD since this replaces the method-level
    Claude-based generation.
    """
    focus_areas: list[FocusArea] = []
    for hunk_index, hunk in enumerate(hunks):
        safe_path = hunk.file_path.replace("/", "-").replace("\\", "-")
        focus_areas.append(
            FocusArea(
                focus_id=f"{safe_path}-{hunk_index}",
                file_path=hunk.file_path,
                start_line=hunk.new_start,
                end_line=hunk.new_start + hunk.new_length - 1,
                description=f"hunk {hunk_index}",
                hunk_index=hunk_index,
                hunk_content=hunk.content,
                focus_type=FocusType.METHOD,
            )
        )

    return FocusGenerationResult(
        pr_number=pr_number,
        focus_areas=focus_areas,
        total_hunks_processed=len(hunks),
        generation_cost_usd=0.0,
    )
