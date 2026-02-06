# Focus Areas Implementation Plan

**Prerequisites:** This plan depends on [phase-sequencer.md](phase-sequencer.md) being implemented first. Phase sequencer provides the infrastructure for phase naming, status tracking, and dependency validation that focus areas builds upon.

**No Backwards Compatibility:** This is a clean break from the current hunk-based structure. We are replacing `CodeSegment` with `FocusArea` and there is no need to support both models simultaneously.

**Architecture Skills Reference:** This implementation follows patterns from the [`gestrich/python-architecture`](https://github.com/gestrich/python-architecture) repository. Each phase references specific skills for validation.

---

## Background

Focus areas allow PRRadar to identify and review changes at the method level rather than at the hunk level. Every method that is added, modified, or removed gets its own focus area for targeted evaluation.

This approach:
- Provides method-level granularity for all changes
- Keeps reviews scoped and manageable
- Allows rules to target specific methods
- Enables more precise rule matching via grep patterns
- Makes it clear which specific methods triggered which rules

**Key architectural principle:** Focus areas are a separate processing stage that happens AFTER hunks are parsed. They are first-class domain objects that reference their source hunks, creating a clean separation between:
- **Hunks** (infrastructure layer): Raw diff parsing artifacts from Git/GitHub
- **Focus areas** (domain layer): Reviewable units of code (methods)
- **Tasks** (application layer): Rule+focus area pairs ready for evaluation

Each focus area contains a reference to its source hunk, maintaining traceability while keeping concerns separated.

## Output Directory Structure with Phase Naming

```
<output-dir>/<pr-number>/
├── phase-1-diff/           (raw.diff, parsed.json, pr.json, comments.json, repo.json)
├── phase-2-focus-areas/    (all.json) - NEW
├── phase-3-rules/          (all-rules.json)
├── phase-4-tasks/          (*.json)
├── phase-5-evaluations/    (*.json, summary.json)
└── phase-6-report/         (summary.json, summary.md)
```

## Phases

## - [ ] Phase 0: Infrastructure - Phase Sequencer

**Note:** This phase has been moved to a separate document: [phase-sequencer.md](phase-sequencer.md)

Establish phase-based naming convention for output directories and migrate existing code to use centralized phase management with completion tracking and resume capability.

**Summary of what Phase 0 provides:**
- `PipelinePhase` enum with all phase names
- `PhaseSequencer` service for directory management
- `PhaseStatus` tracking for completion and partial states
- Dependency validation before running phases
- Resume capability for crashed/partial executions
- Migration script for existing directories

**Implementation:**
See [phase-sequencer.md](phase-sequencer.md) for complete implementation plan.

**Once Phase 0 is complete, the following phases can begin.**

---

## - [ ] Phase 0.1: Quick Reference - PhaseSequencer Usage

For reference during focus areas implementation, here's the basic PhaseSequencer API:

```python
from services.phase_sequencer import PhaseSequencer, PipelinePhase

# Get phase directory path
diff_dir = PhaseSequencer.get_phase_dir(output_dir, PipelinePhase.DIFF)

# Get phase directory and create if needed
diff_dir = PhaseSequencer.ensure_phase_dir(output_dir, PipelinePhase.DIFF)

# Check if phase is complete
status = PhaseSequencer.get_phase_status(output_dir, PipelinePhase.TASKS)
print(f"Tasks: {status.completed_count}/{status.total_count}")

# Validate dependencies before running
can_run, error = PhaseSequencer.can_run_phase(output_dir, PipelinePhase.EVALUATE)
if not can_run:
    print(f"Error: {error}")
```

**Phase Names:**
- `PipelinePhase.DIFF` → `phase-1-diff/`
- `PipelinePhase.FOCUS_AREAS` → `phase-2-focus-areas/`
- `PipelinePhase.RULES` → `phase-3-rules/`
- `PipelinePhase.TASKS` → `phase-4-tasks/`
- `PipelinePhase.EVALUATIONS` → `phase-5-evaluations/`
- `PipelinePhase.REPORT` → `phase-6-report/`

---

## - [x] Phase 1: Focus Area Domain Model

Create `FocusArea` as a first-class domain model that represents a reviewable unit of code (typically a method). Focus areas are separate from hunks and reference their source hunk.

**Completed.** All three tasks implemented:

1. **Created `domain/focus_area.py`** - FocusArea dataclass with `from_dict()`, `to_dict()`, `get_focused_content()`, `get_context_around_line()`, and `content_hash()` methods.
2. **Updated `domain/evaluation_task.py`** - EvaluationTask now uses `focus_area: FocusArea` instead of `segment: CodeSegment`. Task IDs use `{rule.name}-{focus_area.focus_id}` format.
3. **Removed `CodeSegment` entirely** - Clean break, no backward compatibility.

**Technical notes:**
- `focus_id` uses sanitized file paths (replacing `/` with `-`) to ensure task IDs are safe for filenames (e.g., `src-handler.py-0` instead of `src/handler.py-0`)
- `FocusArea.get_context_around_line()` was ported from the old `CodeSegment` to maintain violation context extraction for GitHub commenting
- `FocusArea.content_hash()` was added to support task grouping in the analyze command's interactive mode
- Currently, focus areas map 1:1 with hunks (description is `"hunk N"`). Phase 2 will add Claude-based method detection to create method-level focus areas within hunks.

**Files modified:**
- New: `domain/focus_area.py`
- Modified: `domain/evaluation_task.py`, `domain/__init__.py`, `commands/agent/rules.py`, `commands/agent/analyze.py`, `services/evaluation_service.py`, `services/violation_service.py`, `services/task_loader_service.py`, `tests/test_services.py`, `tests/test_agent_commands.py`

All 229 tests pass.

---

## - [x] Phase 2: Focus Area Generation

**Completed.** All four tasks implemented:

1. **Created `services/focus_generator.py`** - `FocusGeneratorService` with Claude-based method detection using structured outputs. Uses Haiku model by default for speed/cost. Includes `FocusGenerationResult` dataclass for typed results.
2. **Claude prompt template** - Structured JSON schema that asks Claude to identify methods/functions with `method_name`, `start_line`, and `end_line`. Falls back to whole-hunk focus areas if Claude returns no methods or generation fails.
3. **Integrated into rules command** - `cmd_rules()` now generates focus areas before rule filtering. Validates against `PipelinePhase.FOCUS_AREAS` dependency. Saves to `phase-2-focus-areas/all.json`.
4. **Output format** - `all.json` contains `pr_number`, `generated_at`, `focus_areas[]`, `total_hunks_processed`, and `generation_cost_usd`.

**Technical notes:**
- `FocusGeneratorService` uses Claude Agent SDK `query()` with structured outputs (JSON schema for methods array)
- Default model is `claude-haiku-4-5-20251001` for fast structural analysis
- Fallback creates one focus area per hunk (matching Phase 1 behavior) when Claude fails or returns empty results
- `_sanitize_for_id()` strips parentheses/params from method names to create safe focus_id values (e.g., `src-handler.py-0-login`)
- Reconstructs `Hunk` objects from `parsed.json` dictionaries (which contain annotated content from Phase 1)
- `FOCUS_AREAS` removed from `_FUTURE_PHASES` in phase_sequencer.py - now a fully implemented phase
- RULES phase dependency chain updated: DIFF → FOCUS_AREAS → RULES (was DIFF → RULES with FOCUS_AREAS skipped)
- Phase sequencer tests updated to reflect full dependency chain with no future phases
- All 235 tests pass

**Files created:**
- New: `services/focus_generator.py`

**Files modified:**
- Modified: `commands/agent/rules.py` (focus area generation + dependency validation against FOCUS_AREAS)
- Modified: `services/phase_sequencer.py` (removed FOCUS_AREAS from `_FUTURE_PHASES`, removed "Future" comment)
- Modified: `tests/test_phase_sequencer.py` (updated dependency chain tests, removed future phase tests)
- Modified: `tests/test_services.py` (added FocusGeneratorService fallback and FocusGenerationResult tests)

---

## - [x] Phase 3: Update Rule Filtering for Focus Areas

**Completed.** All three tasks implemented:

1. **Added `filter_rules_for_focus_area()` to `RuleLoaderService`** - New method that filters rules against a focus area by checking file patterns and then matching grep patterns against only the focused content (via `FocusArea.get_focused_content()` + `Hunk.extract_changed_content()`), not the entire hunk.
2. **Updated rules command** - `cmd_rules()` now calls `filter_rules_for_focus_area()` instead of `filter_rules_for_segment()` with whole-hunk content. The `Hunk.extract_changed_content()` call on the full hunk content was replaced with focus-area-scoped filtering.
3. **Added 7 tests** for focus area filtering including the key boundary test: a hunk with two methods where grep patterns match only the second method verifies the rule is NOT matched when filtering against the first method's focus area.

**Technical notes:**
- `filter_rules_for_focus_area()` delegates to existing `Rule` methods (`applies_to_file()`, `grep.has_patterns()`, `matches_diff_segment()`) keeping the filtering logic in the domain layer
- The data flow is: `focus_area.get_focused_content()` → `Hunk.extract_changed_content()` → `rule.matches_diff_segment()` — extracting changed lines only from within the focus area bounds
- The old `filter_rules_for_segment()` method is preserved for backward compatibility but no longer called from the rules command
- All 242 tests pass

**Files modified:**
- Modified: `services/rule_loader.py` (added `filter_rules_for_focus_area`, added `FocusArea` and `Hunk` imports)
- Modified: `commands/agent/rules.py` (replaced `filter_rules_for_segment` call with `filter_rules_for_focus_area`)
- Modified: `tests/test_services.py` (added `TestRuleLoaderFilterForFocusArea` test class with 7 tests)

---

## - [ ] Phase 4: Rule Scope (Localized vs Global)

Add `scope` field to rules to distinguish between localized and global evaluation modes.

**Architecture Skills:**
- Use `/python-architecture:domain-modeling` to validate the `RuleScope` enum and `Rule` updates

**Tasks:**
- Add `RuleScope` enum: `LOCALIZED`, `GLOBAL`
- Add `scope: RuleScope` field to `Rule` dataclass (default: `LOCALIZED`)
- Update `Rule.from_file()` to parse `scope` from frontmatter
- Update `Rule.to_dict()` for serialization
- Document the difference:
  - `LOCALIZED`: Rule can be evaluated per-segment (method-level). Works with focus areas.
  - `GLOBAL`: Rule needs broader context. Should receive full diff or multiple segments together.

**Downstream impact (future phases):**
- Localized rules: Evaluated per segment/focus-area as currently done
- Global rules: Need different evaluation strategy (aggregate segments, provide full diff context)
- For now, just add the field and parse it. Later phases can implement different evaluation paths for global rules.

**Example rule frontmatter:**
```yaml
---
description: Check for proper error handling
category: error-handling
scope: localized  # or 'global' for architectural reviews
applies_to:
  file_patterns: ["*.swift"]
---
```

**Files to modify:**
- Modify: `domain/rule.py` (add RuleScope enum and field)
- Update: `services/rule_loader.py` (if any filtering changes needed)

---

## - [ ] Phase 5: CLI Integration and Evaluation Updates

Update remaining commands to work with focus areas and display method-level information.

**Architecture Skills:**
- Use `/python-architecture:cli-architecture` to validate all command updates
- Use `/python-architecture:creating-services` to ensure evaluation service updates follow proper patterns
- Use `/python-architecture:testing-services` to validate test coverage for all updates

**Tasks:**

### 1. Update Evaluate Command

Modify `commands/agent/evaluate.py` to load and display focus area information:

```python
async def cmd_evaluate(pr_number: int, output_dir: Path, rules_filter: list[str] | None = None) -> int:
    # Load tasks from phase-4-tasks/
    tasks_dir = PhaseSequencer.get_phase_dir(output_dir, PipelinePhase.TASKS)
    task_loader = TaskLoaderService(tasks_dir)
    tasks = task_loader.load_all()

    # Progress callback shows method being evaluated
    def on_result(index: int, total: int, result: EvaluationResult) -> None:
        task = tasks[index - 1]
        method_info = task.focus_area.description
        status = "⚠️ Violation" if result.evaluation.violates_rule else "✓ OK"
        print(f"  [{index}/{total}] {result.file_path}:{method_info} - {result.rule_name}: {status}")

    results = await run_batch_evaluation(tasks, output_dir, on_result)

    # Save to phase-5-evaluations/
    evaluations_dir = PhaseSequencer.ensure_phase_dir(output_dir, PipelinePhase.EVALUATIONS)
    # ... save results
```

### 2. Update Analyze Command Interactive Flow

Modify `commands/agent/analyze.py` to show focus area info when prompting:

```python
def prompt_for_focus_area(
    task: EvaluationTask,
    rules: list[str],
    index: int,
    total: int,
) -> str | None:
    """Prompt user to evaluate a focus area with all its rules."""
    print()
    print_separator("=")
    print(f"Focus Area {index}/{total}")
    print_separator("=")
    print(f"  File: {task.focus_area.file_path}")
    print(f"  Method: {task.focus_area.description}")
    print(f"  Lines: {task.focus_area.start_line}-{task.focus_area.end_line}")
    print(f"  Rules: {', '.join(rules)}")
    print_separator("-")
    # Show focused content only
    print(task.focus_area.get_focused_content())
    print_separator("-")

    return prompt_yes_no_quit("Evaluate this focus area?")
```

### 3. Update Evaluation Service Prompts

Modify `services/evaluation_service.py` to pass focus area context:

```python
async def evaluate_task(task: EvaluationTask) -> EvaluationResult:
    """Evaluate a task with focus area context."""

    # Build prompt that emphasizes the focus area
    prompt = f"""
You are reviewing code changes for potential rule violations.

**Focus Area:** {task.focus_area.description} (lines {task.focus_area.start_line}-{task.focus_area.end_line})

**Important:** Only evaluate the code within the focus area boundaries shown below.
Ignore any surrounding code in the diff hunk.

**Code to review:**
{task.focus_area.get_focused_content()}

**Rule to check:**
{task.rule.content}

Does the code within the focus area violate this rule?
"""

    # ... rest of evaluation logic
```

### 4. Update Report Generation

Modify `commands/agent/report.py` and `services/report_generator.py` to group by method:

```python
# In report structure
{
  "by_file": {
    "src/auth.py": {
      "total_violations": 2,
      "by_method": {
        "login(username, password)": [
          {"rule": "error-handling", "score": 8}
        ],
        "validate_token(token)": [
          {"rule": "hardcoded-secrets", "score": 10}
        ]
      }
    }
  }
}
```

### 5. Update All Phase References

Ensure all commands use `PhaseSequencer` for directory access:

- ✅ `commands/agent/diff.py` - Already updated in Phase 0
- ✅ `commands/agent/rules.py` - Already updated in Phase 2 & 3
- ✅ `commands/agent/evaluate.py` - Update here
- ✅ `commands/agent/comment.py` - Update to use `PipelinePhase.EVALUATIONS`
- ✅ `commands/agent/report.py` - Update to use `PipelinePhase.EVALUATIONS`, `PipelinePhase.REPORT`
- ✅ `commands/agent/analyze.py` - Update all phase references

**Files to modify:**
- Modify: `commands/agent/evaluate.py`
- Modify: `commands/agent/analyze.py`
- Modify: `commands/agent/comment.py`
- Modify: `commands/agent/report.py`
- Modify: `services/evaluation_service.py`
- Modify: `services/report_generator.py`

---

---

## Complete Pipeline Visualization (After Focus Areas)

```
┌──────────────────────────────────────────────────────────────┐
│ 1. agent diff                                                │
│    └─→ phase-1-diff/                                         │
│        ├── raw.diff                                          │
│        ├── parsed.json (hunks)                               │
│        ├── pr.json                                           │
│        ├── comments.json                                     │
│        └── repo.json                                         │
└──────────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────────┐
│ 2. agent rules (Part A: Focus Generation)                   │
│    Reads: phase-1-diff/parsed.json                           │
│    └─→ phase-2-focus-areas/                                  │
│        └── all.json (focus areas with hunk references)       │
└──────────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────────┐
│ 3. agent rules (Part B: Rule Loading)                       │
│    Reads: <rules-dir>/*.md                                   │
│    └─→ phase-3-rules/                                        │
│        └── all-rules.json                                    │
└──────────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────────┐
│ 4. agent rules (Part C: Task Creation)                      │
│    Reads: phase-2-focus-areas/all.json                       │
│           phase-3-rules/all-rules.json                        │
│    Filters: rules against focus areas                        │
│    └─→ phase-4-tasks/                                        │
│        └── <rule>-<focus_id>.json (rule + focus area pairs) │
└──────────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────────┐
│ 5. agent evaluate                                            │
│    Reads: phase-4-tasks/*.json                               │
│    Evaluates: Each focus area against its paired rule        │
│    └─→ phase-5-evaluations/                                  │
│        ├── <task_id>.json (individual results)               │
│        └── summary.json (aggregated)                         │
└──────────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────────┐
│ 6. agent comment (optional)                                  │
│    Reads: phase-5-evaluations/*.json                         │
│    Posts: GitHub PR comments                                 │
│    (No new artifacts - external side effect)                 │
└──────────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────────┐
│ 7. agent report                                              │
│    Reads: phase-5-evaluations/*.json                         │
│           phase-4-tasks/*.json (for metadata)                │
│    └─→ phase-6-report/                                       │
│        ├── summary.json (structured, by method)              │
│        └── summary.md (human-readable)                       │
└──────────────────────────────────────────────────────────────┘
```

## Key Architectural Changes

1. **Focus areas are first-class citizens:**
   - Separate phase with dedicated output directory
   - FocusArea domain model references source hunks
   - Bridge between infrastructure (hunks) and application (tasks)

2. **Tasks now pair focus areas with rules:**
   - `EvaluationTask` contains `FocusArea`, not `CodeSegment`
   - Task IDs include focus area identifier
   - Each task is scoped to a single method

3. **Centralized phase management:**
   - `PhaseSequencer` service provides single source of truth
   - `PipelinePhase` enum defines all phase names
   - No magic strings scattered across codebase

4. **Improved traceability:**
   - Results → Tasks → Focus Areas → Hunks → Diff
   - Each artifact references its source
   - Easy debugging at each pipeline stage

---

## Validation Using python-architecture Skills

After implementing each phase, validate the code using the relevant skills from [`gestrich/python-architecture`](https://github.com/gestrich/python-architecture):

### Phase-by-Phase Validation Checklist

**After Phase 1:**
```
/python-architecture:domain-modeling
Review domain/focus_area.py - validate FocusArea follows parse-once principle with proper factory methods and immutability.

/python-architecture:identifying-layer-placement
Verify FocusArea is in the domain layer and properly separated from infrastructure (Hunk) and application (EvaluationTask).
```

**After Phase 2:**
```
/python-architecture:creating-services
Review services/focus_generator.py - validate it follows Service Layer pattern with constructor-based dependency injection.

/python-architecture:domain-modeling
Review FocusGenerationResult dataclass. Ensure proper structure and factory methods.

/python-architecture:identifying-layer-placement
Verify FocusGeneratorService is in services layer with proper dependency flow.
```

**After Phase 3:**
```
/python-architecture:creating-services
Review updated RuleLoaderService.filter_rules_for_focus_area() method. Validate service patterns.

/python-architecture:testing-services
Review tests for focus area filtering. Ensure Arrange-Act-Assert pattern and proper mocking at boundaries.
```

**After Phase 4:**
```
/python-architecture:domain-modeling
Review RuleScope enum and updated Rule dataclass. Validate immutability and proper factory methods.
```

**After Phase 5:**
```
/python-architecture:cli-architecture
Review all updated agent commands (evaluate, analyze, comment, report). Validate command routing and parameter flow.

/python-architecture:creating-services
Review updated evaluation_service.py and report_generator.py. Ensure business logic stays in services.

/python-architecture:testing-services
Review comprehensive test coverage for all focus area functionality.
```

### Key Validation Points

1. **FocusArea Domain Model**:
   - Immutable dataclass with type hints
   - Factory method `from_dict()`
   - No business logic - just data and simple transformations (`get_focused_content()`)
   - Clear separation from Hunk (infrastructure) and EvaluationTask (application)

2. **FocusGeneratorService**:
   - Constructor-based dependency injection (model parameter)
   - Async methods for Claude API calls
   - Returns structured results (FocusGenerationResult)
   - No CLI concerns - pure business logic

3. **EvaluationTask Updates**:
   - Replaces `CodeSegment` with `FocusArea`
   - Maintains immutability and factory methods
   - Clear domain model without infrastructure concerns

4. **Command Updates**:
   - CLI commands orchestrate, don't implement
   - Business logic delegated to services
   - Explicit parameter passing through PhaseSequencer
   - Clear progress reporting to user

---

## Open Questions

1. **Focus area generation model:** Which Claude model for identifying methods in diffs? Haiku for speed/cost since it's structural analysis, or Sonnet for better method boundary detection? Consider using Haiku first and upgrading if accuracy is insufficient.

2. **Global rule evaluation strategy:** How should global-scoped rules receive context? Options:
   - Concatenate all method-level segments into one evaluation
   - Provide PR summary + full diff
   - Multiple-pass evaluation (method-level then file-level)
   This is deferred to future work but worth noting.

3. **Full file content acquisition:** For accurate method boundary detection, we need the complete new file (not just diff context lines). Should this be fetched from GitHub API or local checkout? Local checkout would make this easier (see [diff-source-abstraction.md](diff-source-abstraction.md)).

4. **Method identification accuracy:** How should the system handle edge cases like:
   - Partial method changes (only middle of method changed)
   - Multiple methods in one hunk
   - Language-specific method definitions (functions, methods, closures, etc.)
   Consider language-specific heuristics vs universal Claude-based detection.

5. **Phase sequencing:** Should we add validation that phases are run in order? For example, prevent running `agent evaluate` if `phase-2-focus-areas/` doesn't exist?
