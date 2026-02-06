"""Agent report command - generate summary reports from evaluation results.

Reads evaluation results and generates human-readable reports in
JSON and markdown formats for review and archiving.

Requires:
    <output-dir>/<pr-number>/phase-5-evaluations/*.json  - Evaluation result files
    <output-dir>/<pr-number>/phase-4-tasks/*.json        - Task files (for metadata)

Produces:
    <output-dir>/<pr-number>/phase-6-report/summary.json - Structured JSON report
    <output-dir>/<pr-number>/phase-6-report/summary.md   - Human-readable markdown
"""

from __future__ import annotations

from pathlib import Path

from scripts.services.phase_sequencer import PhaseSequencer, PipelinePhase
from scripts.services.report_generator import ReportGeneratorService


# ============================================================
# Command Entry Point
# ============================================================


def cmd_report(
    pr_number: int,
    output_dir: Path,
    min_score: int = 5,
) -> int:
    """Execute the report command.

    Args:
        pr_number: PR number to generate report for
        output_dir: PR-specific output directory (already includes PR number)
        min_score: Minimum score threshold for including violations (default: 5)

    Returns:
        Exit code (0 for success, non-zero for error)
    """
    print(f"[report] Generating report for PR #{pr_number}...")
    print(f"  Minimum score threshold: {min_score}")

    # Validate dependencies
    error = PhaseSequencer.validate_can_run(output_dir, PipelinePhase.REPORT)
    if error:
        print(f"  Error: {error}")
        print("  Run 'agent evaluate' first to create evaluation results")
        return 1

    # Verify evaluations directory exists
    evaluations_dir = PhaseSequencer.get_phase_dir(output_dir, PipelinePhase.EVALUATIONS)
    tasks_dir = PhaseSequencer.get_phase_dir(output_dir, PipelinePhase.TASKS)

    if not evaluations_dir.exists():
        print(f"  Error: Evaluations directory not found at {evaluations_dir}")
        print("  Run 'agent evaluate' first to create evaluation results")
        return 1

    if not tasks_dir.exists():
        print(f"  Warning: Tasks directory not found at {tasks_dir}")
        print("  Some metadata (documentation links) may be missing")

    # Generate report
    service = ReportGeneratorService(evaluations_dir, tasks_dir)
    report = service.generate_report(pr_number, min_score)

    # Save report files
    json_path, md_path = service.save_report(report, output_dir)

    # Print summary
    print()
    print("Report Summary:")
    print(f"  Tasks evaluated: {report.summary.total_tasks_evaluated}")
    print(f"  Violations found: {report.summary.violations_found}")
    if report.summary.highest_severity > 0:
        print(f"  Highest severity: {report.summary.highest_severity}")
    if report.summary.total_cost_usd > 0:
        print(f"  Total cost: ${report.summary.total_cost_usd:.4f}")

    # Print severity breakdown
    if report.summary.by_severity:
        print()
        print("  By severity:")
        for level in ["Severe (8-10)", "Moderate (5-7)", "Minor (1-4)"]:
            if level in report.summary.by_severity:
                print(f"    {level}: {report.summary.by_severity[level]}")

    # Print file/method breakdown (top 5 files)
    if report.summary.by_method:
        print()
        print("  By file/method:")
        sorted_files = sorted(
            report.summary.by_method.items(),
            key=lambda x: sum(len(methods) for methods in x[1].values()),
            reverse=True,
        )[:5]
        for file_path, methods in sorted_files:
            total = sum(len(v) for v in methods.values())
            print(f"    {file_path}: {total} violation(s)")
            for method_name, violations in methods.items():
                rules = ", ".join(v["rule"] for v in violations)
                print(f"      {method_name}: {rules}")
    elif report.summary.by_file:
        print()
        print("  By file (top 5):")
        sorted_files = sorted(
            report.summary.by_file.items(), key=lambda x: -x[1]
        )[:5]
        for file_path, count in sorted_files:
            print(f"    {file_path}: {count}")

    # Print output paths
    print()
    print("Report files:")
    print(f"  JSON: {json_path}")
    print(f"  Markdown: {md_path}")

    return 0
