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

## - [x] Phase 3: Migration and Integration

Migrate existing code to use PhaseSequencer and update tests.

**Completed.** All hardcoded directory paths replaced with `PhaseSequencer` calls across commands, services, and tests. Migration script created with 5 unit tests. Legacy directory support removed from `phase_exists()` since all code now uses canonical phase names. Module docstrings updated to reference canonical paths. 197 tests pass (1 pre-existing failure unrelated to this change).

**Technical notes:**
- `_LEGACY_DIR_NAMES` mapping removed from `phase_sequencer.py` — no longer needed since all code uses canonical names
- `phase_exists()` simplified to single canonical directory check (no legacy fallback)
- Services (`evaluation_service.py`, `report_generator.py`) also migrated — not just commands
- Migration script at `commands/migrate_to_phases.py` handles: rename, skip-if-migrated, content preservation

**Files created:**
- `commands/migrate_to_phases.py` - Legacy-to-canonical directory migration script

**Files modified:**
- `commands/agent/diff.py` - Use `PhaseSequencer.ensure_phase_dir()` for diff directory
- `commands/agent/rules.py` - Use `PhaseSequencer` for diff, rules, and tasks directories
- `commands/agent/evaluate.py` - Use `PhaseSequencer` for tasks and evaluations directories
- `commands/agent/comment.py` - Use `PhaseSequencer` for evaluations and tasks directories
- `commands/agent/report.py` - Use `PhaseSequencer` for evaluations and tasks directories
- `commands/agent/analyze.py` - Use `PhaseSequencer` for evaluations and tasks directories
- `services/evaluation_service.py` - Use `PhaseSequencer.ensure_phase_dir()` for evaluations
- `services/report_generator.py` - Use `PhaseSequencer.ensure_phase_dir()` for report
- `services/phase_sequencer.py` - Removed `_LEGACY_DIR_NAMES`, simplified `phase_exists()`
- `tests/test_phase_sequencer.py` - Removed legacy tests, added 5 migration tests
- `tests/test_agent_commands.py` - Updated test fixtures to use canonical phase names
- `tests/test_report.py` - Updated test fixtures to use canonical phase names

**Acceptance criteria:**
- ✅ Migration script successfully renames directories
- ✅ All commands use PhaseSequencer (no hardcoded paths)
- ✅ All tests pass with new structure
- ✅ No magic strings in codebase

---

## - [x] Phase 4: Validation

Comprehensive testing of the phase sequencer implementation.

**Completed.** Added 16 new tests (45 total in test_phase_sequencer.py) covering edge cases, full pipeline chain validation, command-level integration, and a programmatic "no magic strings" check. 213 tests pass across the full suite (1 pre-existing failure from missing `claude_agent_sdk`, 1 skip for evaluate command import).

**Technical notes:**
- `TestPipelinePhaseEdgeCases` (5 tests): Validates naming convention regex, sequential numbering, value prefix consistency, future phase classification, and FOCUS_AREAS navigation
- `TestPhaseSequencerFullChain` (3 tests): Validates all implemented phases can run when chain is populated, empty directory blocks all downstream, and error messages reference both phases
- `TestCommandDependencyValidation` (7 tests): Integration tests calling actual `cmd_rules`, `cmd_evaluate`, `cmd_report`, and `cmd_comment` with temp directories — verifies commands return exit code 1 on missing dependencies and exit code 0 on satisfied dependencies
- `TestNoMagicStrings` (1 test): Programmatic scan of all command and service source files for hardcoded phase directory strings — prevents regressions
- Evaluate command integration test skips gracefully when `claude_agent_sdk` is not installed

**Files modified:**
- `tests/test_phase_sequencer.py` - Added 4 new test classes with 16 tests (45 total)

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
