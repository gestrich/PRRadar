"""Agent report command - generate summary reports from evaluation results.

Reads evaluation results and generates human-readable reports in
JSON and markdown formats for review and archiving.

Requires:
    <output-dir>/<pr-number>/evaluations/*.json  - Evaluation result files
    <output-dir>/<pr-number>/tasks/*.json        - Task files (for metadata)

Produces:
    <output-dir>/<pr-number>/report/summary.json - Structured JSON report
    <output-dir>/<pr-number>/report/summary.md   - Human-readable markdown
"""

from __future__ import annotations

from pathlib import Path

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

    # Verify evaluations directory exists
    evaluations_dir = output_dir / "evaluations"
    tasks_dir = output_dir / "tasks"

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

    # Print file breakdown (top 5)
    if report.summary.by_file:
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
