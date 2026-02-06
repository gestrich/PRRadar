# Phase Resume Capability Implementation Plan

## Background

This plan builds on the [phase-sequencer.md](./phase-sequencer.md) foundation to add advanced resume and status tracking capabilities.

**Prerequisites:** The basic PhaseSequencer service must be implemented first (PipelinePhase enum, directory management, and basic dependency validation).

These features enable:
- **Crash recovery** - Resume after Python script crashes mid-execution
- **Partial execution** - Run just some tasks (e.g., 3 of 20)
- **Progress reporting** - See "Phase 4: 15/20 tasks (75%)"
- **Granular status** - Know exactly which items are missing

## Use Cases

1. **Crash Recovery**: Evaluation crashes after processing 10 of 20 tasks. Resume should skip the completed 10 and continue with remaining 10.

2. **Partial Analysis**: User wants to test a single rule. Run rules → tasks → evaluate 1 task, then see status.

3. **Status Visibility**: Before running full pipeline, check what's already done and what needs to run.

4. **Debugging**: When a phase fails, see exactly which items are missing to understand the problem.

## Important Notes

**Build on Foundation:** This assumes Phase 1 of phase-sequencer.md is complete. We're adding PhaseStatus tracking on top of the basic PhaseSequencer.

**Optional Feature:** These capabilities are optional. The basic PhaseSequencer works fine without them. Only implement if the use cases above are valuable.

---

## Phases

## - [x] Phase 1: PhaseStatus Data Model

Create data structures for detailed completion tracking.

**Architecture Skills:**
- Use `/python-architecture:domain-modeling` to validate the `PhaseStatus` dataclass design

**Tasks:**

### 1. Define PhaseStatus Dataclass

Add to `services/phase_sequencer.py`:

```python
from dataclasses import dataclass

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
```

**Files to modify:**
- Modify: `services/phase_sequencer.py`

**Acceptance criteria:**
- ✅ PhaseStatus dataclass defined with all fields
- ✅ Helper methods for percentages and summaries
- ✅ Unit tests for all methods

**Implementation notes:**
- Added `PhaseStatus` dataclass between `PipelinePhase` enum and `PhaseSequencer` class in `phase_sequencer.py`
- Exported via existing import path (`scripts.services.phase_sequencer.PhaseStatus`)
- 13 unit tests covering: `completion_percentage` (5 tests), `is_partial` (4 tests), `summary` (4 tests)

---

## - [x] Phase 2: Phase Completion Checkers

Implement logic to determine completion status for each phase.

**Architecture Skills:**
- Use `/python-architecture:creating-services` to validate checker implementations
- Use `/python-architecture:identifying-layer-placement` to ensure correct layer

**Tasks:**

### 1. Define Checker Protocol

```python
from typing import Protocol

class PhaseChecker(Protocol):
    """Protocol for checking phase completion status."""

    def check_status(self, output_dir: Path) -> PhaseStatus:
        """Check completion status for this phase."""
        ...
```

### 2. Implement Simple Checkers

For phases with fixed files (diff, rules, report):

```python
class DiffPhaseChecker:
    """Checks completion status for phase-1-diff."""

    REQUIRED_FILES = ["raw.diff", "parsed.json", "pr.json", "comments.json", "repo.json"]

    def check_status(self, output_dir: Path) -> PhaseStatus:
        phase_dir = PhaseSequencer.get_phase_dir(output_dir, PipelinePhase.DIFF)

        if not phase_dir.exists():
            return PhaseStatus(
                phase=PipelinePhase.DIFF,
                exists=False,
                is_complete=False,
                completed_count=0,
                total_count=len(self.REQUIRED_FILES),
                missing_items=self.REQUIRED_FILES.copy(),
            )

        missing = [f for f in self.REQUIRED_FILES if not (phase_dir / f).exists()]
        completed = len(self.REQUIRED_FILES) - len(missing)

        return PhaseStatus(
            phase=PipelinePhase.DIFF,
            exists=True,
            is_complete=len(missing) == 0,
            completed_count=completed,
            total_count=len(self.REQUIRED_FILES),
            missing_items=missing,
        )
```

### 3. Implement Variable Checkers

For phases with dynamic counts (tasks, evaluations):

```python
class EvaluationsPhaseChecker:
    """Checks completion status for phase-5-evaluations."""

    def check_status(self, output_dir: Path) -> PhaseStatus:
        import json

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

        # Load expected task IDs
        expected_ids = set()
        for task_file in tasks_dir.glob("*.json"):
            try:
                task_data = json.loads(task_file.read_text())
                expected_ids.add(task_data["task_id"])
            except (json.JSONDecodeError, KeyError):
                continue

        # Check which evaluations exist
        completed_ids = {f.stem for f in eval_dir.glob("*.json") if f.name != "summary.json"}
        missing = sorted(expected_ids - completed_ids)

        return PhaseStatus(
            phase=PipelinePhase.EVALUATIONS,
            exists=True,
            is_complete=len(missing) == 0,
            completed_count=len(completed_ids),
            total_count=len(expected_ids),
            missing_items=missing,
        )
```

### 4. Register Checkers

```python
class PhaseSequencer:
    _CHECKERS: dict[PipelinePhase, PhaseChecker] = {
        PipelinePhase.DIFF: DiffPhaseChecker(),
        PipelinePhase.RULES: RulesPhaseChecker(),
        PipelinePhase.TASKS: TasksPhaseChecker(),
        PipelinePhase.EVALUATIONS: EvaluationsPhaseChecker(),
        PipelinePhase.REPORT: ReportPhaseChecker(),
    }

    @staticmethod
    def get_phase_status(output_dir: Path, phase: PipelinePhase) -> PhaseStatus:
        """Get detailed completion status for a phase."""
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
```

**Files to modify:**
- Modify: `services/phase_sequencer.py`

**Acceptance criteria:**
- ✅ Checker implemented for each phase
- ✅ Checkers accurately count completed/missing items
- ✅ Unit tests for each checker with various states

**Implementation notes:**
- Introduced `PhaseChecker` Protocol and `_FixedFileChecker` base class for DRY fixed-file checkers
- Fixed-file checkers: `DiffPhaseChecker` (raw.diff, parsed.json), `FocusAreasPhaseChecker` (all.json), `RulesPhaseChecker` (all-rules.json), `ReportPhaseChecker` (summary.json, summary.md)
- Adjusted DiffPhaseChecker from spec: only checks files in the phase directory (raw.diff, parsed.json), not pr.json/comments.json/repo.json which live at the output_dir level
- Variable checkers: `TasksPhaseChecker` (counts *.json files), `EvaluationsPhaseChecker` (cross-references task IDs, excludes summary.json)
- All 6 checkers registered in `PhaseSequencer._CHECKERS` class variable
- `PhaseSequencer.get_phase_status()` delegates to registered checkers
- 28 new tests across 8 test classes (TestDiffPhaseChecker, TestFocusAreasPhaseChecker, TestRulesPhaseChecker, TestReportPhaseChecker, TestTasksPhaseChecker, TestEvaluationsPhaseChecker, TestGetPhaseStatus); 303 total tests pass

---

## - [x] Phase 3: Resume Logic in Commands

Add ability to skip already-completed work when resuming.

**Architecture Skills:**
- Use `/python-architecture:cli-architecture` to validate command structure
- Use `/python-architecture:creating-services` to ensure business logic stays in services

**Tasks:**

### 1. Add Resume Helper Method

```python
class PhaseSequencer:
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

        # Get IDs of completed items
        phase_dir = PhaseSequencer.get_phase_dir(output_dir, phase)
        completed = {f.stem for f in phase_dir.glob("*.json")}

        # Filter to remaining
        remaining = [item_id for item_id in all_items if item_id not in completed]
        skipped = len(all_items) - len(remaining)

        return remaining, skipped
```

### 2. Update Evaluate Command

```python
async def cmd_evaluate(
    pr_number: int,
    output_dir: Path,
    rules_filter: list[str] | None = None,
) -> int:
    """Execute the evaluate command with resume support."""

    # Load all tasks
    task_loader = TaskLoaderService(PhaseSequencer.get_phase_dir(output_dir, PipelinePhase.TASKS))
    tasks = task_loader.load_all()

    # Check for resume
    task_ids = [t.task_id for t in tasks]
    remaining_ids, skipped = PhaseSequencer.get_remaining_items(
        output_dir, PipelinePhase.EVALUATIONS, task_ids
    )

    if skipped > 0:
        print(f"  Resuming: skipping {skipped} already-evaluated tasks")
        tasks = [t for t in tasks if t.task_id in remaining_ids]

    if not tasks:
        print("  All tasks already evaluated")
        return 0

    # Continue with evaluation...
```

**Files to modify:**
- Modify: `services/phase_sequencer.py` (add resume helper)
- Modify: `commands/agent/evaluate.py` (add resume logic)
- Modify: `commands/agent/analyze.py` (add resume logic)

**Acceptance criteria:**
- ✅ Resume logic skips completed items
- ✅ Clear messaging when resuming
- ✅ Works correctly when nothing completed
- ✅ Works correctly when everything completed

**Implementation notes:**
- `get_remaining_items()` relies on `is_partial()` to detect resume scenarios: only filters when phase exists, is incomplete, and has some progress. When phase is complete or not started, returns all items unchanged.
- Excludes `summary.json` from completed item detection (consistent with `EvaluationsPhaseChecker`)
- `evaluate.py`: Resume check inserted after task loading but before batch evaluation. Uses a `remaining_set` for O(1) lookup when filtering tasks.
- `analyze.py`: Resume check inserted after task loading, before `group_tasks_by_focus_area()`. Skipped count added to `stats.tasks_skipped`. Returns early with summary if all tasks already evaluated.
- 7 new unit tests in `TestGetRemainingItems` class covering: nothing completed, everything completed, partial completion, order preservation, summary.json exclusion, empty input, and empty phase directory. 310 total tests pass.

---

## - [ ] Phase 4: Status Command

Create command to display detailed pipeline status.

**Architecture Skills:**
- Use `/python-architecture:cli-architecture` to validate command structure

**Tasks:**

### 1. Add Status Formatting

```python
class PhaseSequencer:
    @staticmethod
    def get_all_statuses(output_dir: Path) -> dict[PipelinePhase, PhaseStatus]:
        """Get status for all phases."""
        return {
            phase: PhaseSequencer.get_phase_status(output_dir, phase)
            for phase in PipelinePhase
        }

    @staticmethod
    def print_pipeline_status(output_dir: Path) -> None:
        """Print formatted pipeline status summary."""
        statuses = PhaseSequencer.get_all_statuses(output_dir)

        print("\nPipeline Status:")
        print("=" * 60)

        for phase in PipelinePhase:
            status = statuses[phase]

            # Status indicator
            if status.is_complete:
                indicator = "✓"
            elif status.is_partial():
                indicator = "⚠"
            elif status.exists:
                indicator = "✗"
            else:
                indicator = " "

            # Progress display
            if status.total_count > 0:
                progress = f"{status.completed_count}/{status.total_count}"
                pct = status.completion_percentage()
                progress += f" ({pct:.0f}%)"
            else:
                progress = status.summary()

            print(f"  {indicator} {phase.value:<25} {progress}")
```

### 2. Create Status Command

```python
# In commands/agent/status.py

def cmd_status(output_dir: Path) -> int:
    """Show pipeline status for a PR."""
    if not output_dir.exists():
        print(f"Output directory not found: {output_dir}")
        return 1

    PhaseSequencer.print_pipeline_status(output_dir)
    return 0
```

**Files to create:**
- New: `commands/agent/status.py`

**Files to modify:**
- Modify: `services/phase_sequencer.py` (add status formatting)

**Acceptance criteria:**
- ✅ Status command shows all phases
- ✅ Visual indicators for complete/partial/incomplete
- ✅ Percentages shown for countable phases
- ✅ Human-readable output

---

## - [ ] Phase 5: Validation

Test resume capabilities and status reporting.

**Architecture Skills:**
- Use `/python-architecture:testing-services` to validate test patterns

**Tasks:**

### 1. Unit Tests for Status Tracking

```python
def test_phase_status_completion_percentage():
    status = PhaseStatus(
        phase=PipelinePhase.EVALUATIONS,
        exists=True,
        is_complete=False,
        completed_count=15,
        total_count=20,
        missing_items=["task-1", "task-2"],
    )
    assert status.completion_percentage() == 75.0

def test_phase_status_is_partial():
    status = PhaseStatus(
        phase=PipelinePhase.EVALUATIONS,
        exists=True,
        is_complete=False,
        completed_count=10,
        total_count=20,
        missing_items=[],
    )
    assert status.is_partial()
```

### 2. Integration Tests for Resume

```python
def test_evaluate_resumes_partial_work(tmp_path):
    """Evaluate should skip already-completed tasks."""
    output_dir = tmp_path / "123"

    # Create tasks
    tasks_dir = PhaseSequencer.ensure_phase_dir(output_dir, PipelinePhase.TASKS)
    for i in range(5):
        (tasks_dir / f"task-{i}.json").write_text('{"task_id": "task-' + str(i) + '"}')

    # Create partial evaluations (completed 0, 1, 2)
    eval_dir = PhaseSequencer.ensure_phase_dir(output_dir, PipelinePhase.EVALUATIONS)
    for i in range(3):
        (eval_dir / f"task-{i}.json").write_text('{"result": "pass"}')

    # Get remaining items
    remaining, skipped = PhaseSequencer.get_remaining_items(
        output_dir, PipelinePhase.EVALUATIONS, [f"task-{i}" for i in range(5)]
    )

    assert skipped == 3
    assert len(remaining) == 2
    assert "task-3" in remaining
    assert "task-4" in remaining
```

### 3. Status Command Tests

```python
def test_status_command_shows_all_phases(tmp_path, capsys):
    """Status command should display all phases."""
    output_dir = tmp_path / "123"

    # Create some completed phases
    diff_dir = PhaseSequencer.ensure_phase_dir(output_dir, PipelinePhase.DIFF)
    (diff_dir / "raw.diff").write_text("content")

    cmd_status(output_dir)

    captured = capsys.readouterr()
    assert "phase-1-diff" in captured.out
    assert "phase-3-rules" in captured.out
    assert "✓" in captured.out  # Has at least one complete phase
```

**Acceptance criteria:**
- ✅ All unit tests pass
- ✅ Resume logic tested with various scenarios
- ✅ Status command produces correct output
- ✅ No regressions in basic functionality

---

## Usage Examples

### Check Status

```bash
python -m scripts.commands.agent.status --output-dir ./output/123
```

Output:
```
Pipeline Status:
============================================================
  ✓ phase-1-diff                 5/5 (100%)
  ✓ phase-3-rules                1/1 (100%)
  ⚠ phase-4-tasks                15/20 (75%)
  ✗ phase-5-evaluations          0/15 (0%)
    phase-6-report               not started
```

### Resume After Crash

```bash
# First run - crashes after 10 tasks
python -m scripts.commands.agent.evaluate --pr-number 123 --output-dir ./output/123
# ... processes 10 tasks, then crashes

# Resume - automatically skips completed
python -m scripts.commands.agent.evaluate --pr-number 123 --output-dir ./output/123
# Output: "Resuming: skipping 10 already-evaluated tasks"
# ... processes remaining 10 tasks
```

---

## Validation Using python-architecture Skills

**After Phase 1:**
```
/python-architecture:domain-modeling
Review PhaseStatus dataclass. Ensure immutability and proper design.
```

**After Phase 2:**
```
/python-architecture:creating-services
Review all checker implementations. Validate separation of concerns.

/python-architecture:identifying-layer-placement
Verify checkers are in correct layer with proper dependencies.
```

**After Phase 3:**
```
/python-architecture:cli-architecture
Review updated commands. Validate parameter flow and command structure.

/python-architecture:creating-services
Ensure resume logic is in service layer, not CLI.
```
