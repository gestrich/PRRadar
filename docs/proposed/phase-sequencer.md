# Phase Sequencer Implementation Plan

## Background

PRRadar's pipeline consists of multiple phases that transform data sequentially. Each phase depends on artifacts from previous phases. Currently, phase directory names are scattered as magic strings throughout the codebase (`output_dir / "diff"`, `output_dir / "tasks"`, etc.).

This plan establishes:
1. **Centralized phase naming** - Single source of truth for phase directory names via enum
2. **Basic dependency validation** - Prevent phases from running without upstream dependencies
3. **Clean migration** - Move existing output directories to new structure

This is the **essential foundation**. Advanced features like detailed status tracking, resume capability, and progress reporting are covered in [phase-resume.md](./phase-resume.md).

## Important Notes

**No Backwards Compatibility Required:** This is a clean break from the current directory structure. We will migrate existing output directories using a migration script, but the code itself does not need to support both old and new structures.

**Architecture Skills Reference:** This implementation follows patterns from the [`gestrich/python-architecture`](https://github.com/gestrich/python-architecture) repository. Each phase references specific skills for validation.

## Current State vs. Target State

### Current State (Problems)
```python
# Magic strings scattered across codebase
diff_dir = output_dir / "diff"
tasks_dir = output_dir / "tasks"

# No validation that dependencies exist
# Can run evaluate before diff completes
```

### Target State (Solution)
```python
from services.phase_sequencer import PhaseSequencer, PipelinePhase

# Centralized phase naming
diff_dir = PhaseSequencer.ensure_phase_dir(output_dir, PipelinePhase.DIFF)

# Simple validation
if not PhaseSequencer.can_run_phase(output_dir, PipelinePhase.EVALUATIONS):
    print("Error: Cannot run evaluations - tasks phase not complete")
```

## Pipeline Phases

```
phase-1-diff/           - Fetch and parse PR diff
phase-2-focus-areas/    - Generate reviewable code units (FUTURE)
phase-3-rules/          - Load review rules
phase-4-tasks/          - Create evaluation tasks
phase-5-evaluations/    - Execute evaluations
phase-6-report/         - Generate summary reports
```

**Note:** Phase 2 (focus-areas) will be added in a future implementation.

---

## Phases

## - [x] Phase 1: Core PhaseSequencer Service

Create the foundational PhaseSequencer service with phase naming and directory management.

**Completed.** Implemented `PipelinePhase` enum and `PhaseSequencer` class with all static directory management methods. 13 unit tests covering enum ordering, phase navigation, and directory management (create, idempotent create, exists checks for missing/empty/populated directories).

**Files created:**
- `services/phase_sequencer.py` - PipelinePhase enum + PhaseSequencer class
- `tests/test_phase_sequencer.py` - 13 unit tests

**Acceptance criteria:**
- ✅ PipelinePhase enum defines all phases with proper naming
- ✅ Directory management methods work correctly
- ✅ `phase_exists()` detects both missing and empty directories
- ✅ Unit tests for basic functionality

---

## - [x] Phase 2: Basic Dependency Validation

Add simple validation that upstream phases are complete before running downstream phases.

**Completed.** Added `can_run_phase()` and `validate_can_run()` to PhaseSequencer, plus `previous_implemented_phase()` to PipelinePhase to skip future/unimplemented phases (FOCUS_AREAS). Added legacy directory name support to `phase_exists()` for transition compatibility until Phase 3 migration. Validation integrated into rules, evaluate, comment, and report commands. 17 new unit tests added (30 total).

**Technical notes:**
- `previous_implemented_phase()` skips FOCUS_AREAS (future phase) so RULES correctly depends on DIFF
- `phase_exists()` checks both canonical (`phase-1-diff`) and legacy (`diff`) directory names via `_LEGACY_DIR_NAMES` mapping, ensuring validation works before Phase 3 directory migration
- Comment command uses `phase_exists()` directly (not `validate_can_run()`) since it's not a sequenced pipeline phase
- Existing ad-hoc directory checks preserved in commands as secondary validation until Phase 3 replaces all hardcoded paths

**Files modified:**
- `services/phase_sequencer.py` - Added `can_run_phase()`, `validate_can_run()`, `previous_implemented_phase()`, `_FUTURE_PHASES`, `_LEGACY_DIR_NAMES`
- `commands/agent/rules.py` - Added dependency validation
- `commands/agent/evaluate.py` - Added dependency validation
- `commands/agent/comment.py` - Added dependency validation
- `commands/agent/report.py` - Added dependency validation
- `tests/test_phase_sequencer.py` - 17 new tests across 3 new test classes

**Acceptance criteria:**
- ✅ Dependency validation prevents running phases out of order
- ✅ Clear error messages guide users to run missing phases
- ✅ First phase (DIFF) can always run
- ✅ Unit tests for validation logic

---

## - [ ] Phase 3: Migration and Integration

Migrate existing code to use PhaseSequencer and update tests.

**Architecture Skills:**
- Use `/python-architecture:cli-architecture` to validate all command updates follow proper patterns
- Use `/python-architecture:testing-services` to ensure comprehensive test coverage
- Use `/python-architecture:python-code-style` to verify consistent code style

**Tasks:**

### 1. Create Migration Script

```python
# In scripts/commands/migrate_to_phases.py

"""Migrate existing output directories to phase-based naming."""

from pathlib import Path
from services.phase_sequencer import PipelinePhase, PhaseSequencer


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
    import sys

    if len(sys.argv) < 2:
        print("Usage: python -m scripts.commands.migrate_to_phases <output_dir>")
        sys.exit(1)

    output_base = Path(sys.argv[1])
    migrate_all(output_base)
```

### 2. Update All Commands

Replace all hardcoded directory names with PhaseSequencer calls:

**Before:**
```python
diff_dir = output_dir / "diff"
diff_dir.mkdir(parents=True, exist_ok=True)
```

**After:**
```python
from services.phase_sequencer import PhaseSequencer, PipelinePhase

diff_dir = PhaseSequencer.ensure_phase_dir(output_dir, PipelinePhase.DIFF)
```

**Files to modify:**
- Modify: `commands/agent/diff.py`
- Modify: `commands/agent/rules.py`
- Modify: `commands/agent/evaluate.py`
- Modify: `commands/agent/comment.py`
- Modify: `commands/agent/report.py`
- Modify: `commands/agent/analyze.py`

### 3. Update Tests

Update all test fixtures and assertions:

```python
# Before
def test_rules_command(tmp_path):
    output_dir = tmp_path / "123"
    diff_dir = output_dir / "diff"
    diff_dir.mkdir(parents=True)

# After
def test_rules_command(tmp_path):
    output_dir = tmp_path / "123"
    diff_dir = PhaseSequencer.ensure_phase_dir(output_dir, PipelinePhase.DIFF)
```

**Files to modify:**
- All test files in `tests/`

**Acceptance criteria:**
- ✅ Migration script successfully renames directories
- ✅ All commands use PhaseSequencer (no hardcoded paths)
- ✅ All tests pass with new structure
- ✅ No magic strings in codebase

---

## - [ ] Phase 4: Validation

Comprehensive testing of the phase sequencer implementation.

**Architecture Skills:**
- Use `/python-architecture:testing-services` to validate test patterns

**Tasks:**

### 1. Unit Tests

Test the core PhaseSequencer functionality:

```python
# tests/test_phase_sequencer.py

def test_phase_enum_order():
    """Verify phases are in correct execution order."""
    phases = list(PipelinePhase)
    assert phases[0] == PipelinePhase.DIFF
    assert phases[-1] == PipelinePhase.REPORT

def test_previous_phase():
    """Verify previous_phase() returns correct dependencies."""
    assert PipelinePhase.DIFF.previous_phase() is None
    assert PipelinePhase.RULES.previous_phase() == PipelinePhase.DIFF
    assert PipelinePhase.EVALUATIONS.previous_phase() == PipelinePhase.TASKS

def test_phase_exists_empty_directory(tmp_path):
    """Empty phase directory should return False."""
    phase_dir = PhaseSequencer.ensure_phase_dir(tmp_path, PipelinePhase.DIFF)
    assert not PhaseSequencer.phase_exists(tmp_path, PipelinePhase.DIFF)

def test_phase_exists_with_content(tmp_path):
    """Phase directory with files should return True."""
    phase_dir = PhaseSequencer.ensure_phase_dir(tmp_path, PipelinePhase.DIFF)
    (phase_dir / "raw.diff").write_text("content")
    assert PhaseSequencer.phase_exists(tmp_path, PipelinePhase.DIFF)

def test_can_run_first_phase(tmp_path):
    """First phase should always be able to run."""
    assert PhaseSequencer.can_run_phase(tmp_path, PipelinePhase.DIFF)

def test_cannot_run_without_dependency(tmp_path):
    """Cannot run phase if previous phase doesn't exist."""
    assert not PhaseSequencer.can_run_phase(tmp_path, PipelinePhase.RULES)

def test_can_run_with_dependency(tmp_path):
    """Can run phase if previous phase exists with content."""
    diff_dir = PhaseSequencer.ensure_phase_dir(tmp_path, PipelinePhase.DIFF)
    (diff_dir / "raw.diff").write_text("content")
    assert PhaseSequencer.can_run_phase(tmp_path, PipelinePhase.RULES)
```

### 2. Integration Tests

Test validation in actual commands:

```python
def test_evaluate_validates_dependencies(tmp_path):
    """Evaluate command should fail if tasks phase not complete."""
    output_dir = tmp_path / "123"
    result = cmd_evaluate(123, output_dir)
    assert result == 1  # Exit code indicates error
```

### 3. Migration Tests

Test migration script:

```python
def test_migrate_legacy_directories(tmp_path):
    """Migration script should rename directories correctly."""
    pr_dir = tmp_path / "123"
    (pr_dir / "diff").mkdir(parents=True)
    (pr_dir / "tasks").mkdir(parents=True)

    migrate_pr_directory(pr_dir)

    assert not (pr_dir / "diff").exists()
    assert not (pr_dir / "tasks").exists()
    assert (pr_dir / "phase-1-diff").exists()
    assert (pr_dir / "phase-4-tasks").exists()
```

**Acceptance criteria:**
- ✅ All unit tests pass
- ✅ All integration tests pass
- ✅ All existing tests updated and passing
- ✅ Migration script tested with real output directories
- ✅ No regressions in command functionality

---

## Usage Examples

### Basic Usage

```python
# In any command
from services.phase_sequencer import PhaseSequencer, PipelinePhase

# Get phase directory
diff_dir = PhaseSequencer.ensure_phase_dir(output_dir, PipelinePhase.DIFF)

# Check if phase can run
if not PhaseSequencer.can_run_phase(output_dir, PipelinePhase.EVALUATIONS):
    print("Error: Tasks phase not complete")
    return 1

# Validate with user-friendly error
error = PhaseSequencer.validate_can_run(output_dir, PipelinePhase.EVALUATIONS)
if error:
    print(f"Error: {error}")
    return 1
```

### Migration

```bash
# Migrate existing output directories
python -m scripts.commands.migrate_to_phases ./output
```

---

## Next Steps

This implementation provides the essential foundation for phase management. For advanced features like:
- Detailed progress tracking (15/20 tasks complete)
- Resume capability after crashes
- Status reporting with percentages
- Per-phase completion checkers

See [phase-resume.md](./phase-resume.md).

---

## Validation Using python-architecture Skills

After implementing each phase, validate using skills from [`gestrich/python-architecture`](https://github.com/gestrich/python-architecture):

**After Phase 1:**
```
/python-architecture:domain-modeling
Review the PipelinePhase enum design. Ensure it follows best practices.

/python-architecture:creating-services
Review PhaseSequencer service. Validate static method usage for utilities.
```

**After Phase 2:**
```
/python-architecture:creating-services
Review validation methods. Ensure they follow service patterns.

/python-architecture:python-code-style
Review method ordering and organization.
```

**After Phase 3:**
```
/python-architecture:cli-architecture
Review all updated commands. Validate proper command structure.

/python-architecture:testing-services
Ensure comprehensive test coverage with Arrange-Act-Assert pattern.
```
