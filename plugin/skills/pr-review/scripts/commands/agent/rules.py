"""Agent rules command - collect and filter applicable rules.

Loads rules from a directory and filters them against the diff.
Creates evaluation tasks for each rule+segment combination.

Requires:
    <output-dir>/<pr-number>/diff/parsed.json  - Structured diff with hunks

Artifact outputs:
    <output-dir>/<pr-number>/rules/all-rules.json  - All collected rules
    <output-dir>/<pr-number>/tasks/*.json          - Evaluation tasks (rule+segment)
"""

from __future__ import annotations

import json
from pathlib import Path

from scripts.domain.diff import Hunk
from scripts.domain.evaluation_task import CodeSegment, EvaluationTask
from scripts.domain.rule import Rule
from scripts.services.phase_sequencer import PhaseSequencer, PipelinePhase
from scripts.services.rule_loader import RuleLoaderService


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
    error = PhaseSequencer.validate_can_run(output_dir, PipelinePhase.RULES)
    if error:
        print(f"  Error: {error}")
        print("  Run 'agent diff' first to collect PR data")
        return 1

    # Verify diff artifacts exist
    parsed_diff_path = output_dir / "diff" / "parsed.json"
    if not parsed_diff_path.exists():
        print(f"  Error: Diff not found at {parsed_diff_path}")
        print("  Run 'agent diff' first to collect PR data")
        return 1

    # Load parsed diff
    print("  Loading diff...")
    parsed_diff = json.loads(parsed_diff_path.read_text())
    hunks = parsed_diff.get("hunks", [])
    print(f"  Found {len(hunks)} hunks in diff")

    if not hunks:
        print("  No hunks to analyze - empty diff")
        return 0

    # Create rule loader service
    try:
        rule_loader = RuleLoaderService.create(rules_dir)
    except ValueError as e:
        print(f"  Error: {e}")
        return 1

    # Load all rules
    print("  Loading rules...")
    all_rules = rule_loader.load_all_rules()
    print(f"  Loaded {len(all_rules)} rules")

    if not all_rules:
        print("  Warning: No rules found in rules directory")
        return 0

    # Write all rules to rules/all-rules.json
    rules_output_dir = output_dir / "rules"
    rules_output_dir.mkdir(parents=True, exist_ok=True)

    all_rules_path = rules_output_dir / "all-rules.json"
    all_rules_data = [rule.to_dict() for rule in all_rules]
    all_rules_path.write_text(json.dumps(all_rules_data, indent=2))
    print(f"  Wrote {all_rules_path}")

    # Create tasks directory
    tasks_dir = output_dir / "tasks"
    tasks_dir.mkdir(parents=True, exist_ok=True)

    # Clear any existing task files
    for existing_task in tasks_dir.glob("*.json"):
        existing_task.unlink()

    # Filter rules and create evaluation tasks
    print("  Filtering rules and creating tasks...")
    tasks_created = 0
    skipped_no_rules = 0

    for hunk_index, hunk in enumerate(hunks):
        file_path = hunk.get("file_path", "")
        content = hunk.get("content", "")
        new_start = hunk.get("new_start", 0)
        new_length = hunk.get("new_length", 0)

        # Extract only changed lines for grep filtering
        # (context lines should not trigger rule matches)
        changed_content = Hunk.extract_changed_content(content)

        # Filter rules for this segment
        applicable_rules = rule_loader.filter_rules_for_segment(
            all_rules, file_path, changed_content
        )

        if not applicable_rules:
            skipped_no_rules += 1
            continue

        # Create code segment
        segment = CodeSegment(
            file_path=file_path,
            hunk_index=hunk_index,
            start_line=new_start,
            end_line=new_start + new_length - 1,
            content=content,
        )

        # Create evaluation task for each applicable rule
        for rule in applicable_rules:
            task = EvaluationTask.create(rule=rule, segment=segment)
            task_path = tasks_dir / task.suggested_filename()
            task_path.write_text(json.dumps(task.to_dict(), indent=2))
            tasks_created += 1

    # Summary
    unique_files = sorted(set(h.get("file_path", "") for h in hunks))
    print()
    print(f"Rules Summary:")
    print(f"  Total rules loaded: {len(all_rules)}")
    print(f"  Files in diff: {len(unique_files)}")
    print(f"  Hunks analyzed: {len(hunks)}")
    print(f"  Hunks with no matching rules: {skipped_no_rules}")
    print(f"  Evaluation tasks created: {tasks_created}")
    print()
    print(f"Artifacts saved to: {output_dir}")

    return 0
