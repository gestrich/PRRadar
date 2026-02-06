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

## - [ ] Phase 2: Focus Area Generation

Generate focus areas from hunks using Claude-based analysis. Focus areas are saved to `phase-2-focus-areas/all.json` as a standalone pipeline artifact.

**Architecture Skills:**
- Use `/python-architecture:creating-services` to validate the `FocusGeneratorService` structure
- Use `/python-architecture:domain-modeling` to validate the `FocusGenerationResult` dataclass
- Use `/python-architecture:identifying-layer-placement` to ensure service is in correct layer

**Tasks:**

### 1. Create FocusGeneratorService

Create `services/focus_generator.py`:

```python
"""Service for generating focus areas from diff hunks using Claude."""

from dataclasses import dataclass
from typing import List
from domain.focus_area import FocusArea
from domain.diff import Hunk


@dataclass
class FocusGenerationResult:
    """Result of focus area generation for a PR."""

    pr_number: int
    focus_areas: List[FocusArea]
    total_hunks_processed: int
    generation_cost_usd: float = 0.0


class FocusGeneratorService:
    """Generates focus areas (reviewable units) from diff hunks.

    Uses Claude to identify method-level changes within hunks.
    Each identified method becomes a FocusArea that references
    its source hunk.
    """

    def __init__(self, model: str = "claude-haiku-4-5-20251001"):
        """Initialize with Claude model for focus generation.

        Args:
            model: Claude model to use (default: Haiku for speed/cost)
        """
        self.model = model

    async def generate_focus_areas_for_hunk(
        self, hunk: Hunk, hunk_index: int
    ) -> List[FocusArea]:
        """Generate focus areas for a single hunk.

        Args:
            hunk: The hunk to analyze
            hunk_index: Index of this hunk in the diff

        Returns:
            List of focus areas found in this hunk
        """
        # Use Claude Agent SDK to identify methods
        # Prompt: "Analyze this diff hunk and identify all methods..."
        # Return structured output with method boundaries
        pass

    async def generate_all_focus_areas(
        self, hunks: List[Hunk], pr_number: int
    ) -> FocusGenerationResult:
        """Generate focus areas for all hunks in a diff.

        Args:
            hunks: List of hunks from parsed diff
            pr_number: PR number being analyzed

        Returns:
            FocusGenerationResult with all focus areas
        """
        all_focus_areas = []
        total_cost = 0.0

        for i, hunk in enumerate(hunks):
            focus_areas = await self.generate_focus_areas_for_hunk(hunk, i)
            all_focus_areas.extend(focus_areas)

        return FocusGenerationResult(
            pr_number=pr_number,
            focus_areas=all_focus_areas,
            total_hunks_processed=len(hunks),
            generation_cost_usd=total_cost,
        )
```

### 2. Create Claude Prompt Template

Create prompt template for focus generation (structured output):

```python
# In services/focus_generator.py

FOCUS_GENERATION_PROMPT = """
Analyze this diff hunk and identify all methods/functions that were added,
modified, or removed.

Hunk:
{hunk_content}

For each method you identify, provide:
1. start_line: First line number in the new file
2. end_line: Last line number in the new file
3. description: Method name and signature (e.g., "login(username, password)")

Return a list of all methods found in this hunk.
"""
```

### 3. Integrate into Rules Command

Modify `commands/agent/rules.py` to generate focus areas BEFORE filtering rules:

```python
from services.focus_generator import FocusGeneratorService
from services.phase_sequencer import PhaseSequencer, PipelinePhase

async def cmd_rules(pr_number: int, output_dir: Path, rules_dir: str) -> int:
    # Load parsed diff from phase-1-diff/
    diff_dir = PhaseSequencer.get_phase_dir(output_dir, PipelinePhase.DIFF)
    parsed_diff_path = diff_dir / "parsed.json"
    parsed_diff = json.loads(parsed_diff_path.read_text())
    hunks = [Hunk.from_dict(h) for h in parsed_diff.get("hunks", [])]

    # Generate focus areas
    print("  Generating focus areas...")
    focus_generator = FocusGeneratorService()
    focus_result = await focus_generator.generate_all_focus_areas(hunks, pr_number)
    print(f"  Found {len(focus_result.focus_areas)} methods across {len(hunks)} hunks")

    # Save focus areas to phase-2-focus-areas/
    focus_dir = PhaseSequencer.ensure_phase_dir(output_dir, PipelinePhase.FOCUS_AREAS)
    focus_areas_path = focus_dir / "all.json"
    focus_areas_data = {
        "pr_number": pr_number,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "focus_areas": [fa.to_dict() for fa in focus_result.focus_areas],
        "total_hunks_processed": focus_result.total_hunks_processed,
        "generation_cost_usd": focus_result.generation_cost_usd,
    }
    focus_areas_path.write_text(json.dumps(focus_areas_data, indent=2))
    print(f"  Wrote {focus_areas_path}")

    # Continue with rule loading and task creation...
    # Now create tasks by pairing focus_areas with filtered rules
```

### 4. Output Format for phase-2-focus-areas/all.json

```json
{
  "pr_number": 123,
  "generated_at": "2024-02-06T12:34:56Z",
  "total_hunks_processed": 5,
  "generation_cost_usd": 0.0023,
  "focus_areas": [
    {
      "focus_id": "src/auth.py-0-login",
      "file_path": "src/auth.py",
      "start_line": 45,
      "end_line": 52,
      "description": "login(username, password)",
      "hunk_index": 0,
      "hunk_content": "@@ -44,8 +44,15 @@\n..."
    }
  ]
}
```

**Files to create:**
- New: `services/focus_generator.py`

**Files to modify:**
- Modify: `commands/agent/rules.py` (integrate focus generation)

---

## - [ ] Phase 3: Update Rule Filtering for Focus Areas

Update rule filtering to work with focus areas instead of hunks. Grep patterns should only match against the focused code region, not the entire hunk.

**Architecture Skills:**
- Use `/python-architecture:creating-services` to validate the updated `RuleLoaderService` methods
- Use `/python-architecture:testing-services` to ensure proper test coverage for focus area filtering

**Tasks:**

### 1. Update RuleLoaderService to Filter by Focus Area

Modify `services/rule_loader.py`:

```python
class RuleLoaderService:
    """Service for loading and filtering rules."""

    def filter_rules_for_focus_area(
        self,
        all_rules: List[Rule],
        focus_area: FocusArea,
    ) -> List[Rule]:
        """Filter rules applicable to a focus area.

        Args:
            all_rules: All loaded rules
            focus_area: The focus area to filter against

        Returns:
            List of rules that apply to this focus area
        """
        applicable_rules = []

        for rule in all_rules:
            # Check file pattern matches
            if not self._matches_file_patterns(rule, focus_area.file_path):
                continue

            # Check grep patterns against focused content only
            if rule.applies_to and rule.applies_to.get("grep_patterns"):
                focused_content = focus_area.get_focused_content()
                changed_content = Hunk.extract_changed_content(focused_content)

                if not self._matches_grep_patterns(rule, changed_content):
                    continue

            applicable_rules.append(rule)

        return applicable_rules
```

### 2. Update Rules Command to Filter Focus Areas

Modify `commands/agent/rules.py` to pair focus areas with rules:

```python
async def cmd_rules(pr_number: int, output_dir: Path, rules_dir: str) -> int:
    # ... (after generating focus areas)

    # Load all rules
    rule_loader = RuleLoaderService.create(rules_dir)
    all_rules = rule_loader.load_all_rules()

    # Load focus areas from phase-2-focus-areas/
    focus_dir = PhaseSequencer.get_phase_dir(output_dir, PipelinePhase.FOCUS_AREAS)
    focus_areas_path = focus_dir / "all.json"
    focus_areas_data = json.loads(focus_areas_path.read_text())
    focus_areas = [FocusArea.from_dict(fa) for fa in focus_areas_data["focus_areas"]]

    # Save all rules to phase-3-rules/
    rules_dir = PhaseSequencer.ensure_phase_dir(output_dir, PipelinePhase.RULES)
    all_rules_path = rules_dir / "all-rules.json"
    all_rules_path.write_text(json.dumps([r.to_dict() for r in all_rules], indent=2))

    # Create tasks by pairing focus areas with filtered rules
    tasks_dir = PhaseSequencer.ensure_phase_dir(output_dir, PipelinePhase.TASKS)

    # Clear existing tasks
    for existing_task in tasks_dir.glob("*.json"):
        existing_task.unlink()

    tasks_created = 0
    for focus_area in focus_areas:
        # Filter rules for this focus area
        applicable_rules = rule_loader.filter_rules_for_focus_area(
            all_rules, focus_area
        )

        # Create task for each applicable rule
        for rule in applicable_rules:
            task = EvaluationTask.create(rule=rule, focus_area=focus_area)
            task_path = tasks_dir / f"{task.task_id}.json"
            task_path.write_text(json.dumps(task.to_dict(), indent=2))
            tasks_created += 1

    print(f"  Evaluation tasks created: {tasks_created}")
```

### 3. Update Tests

Add tests verifying grep patterns respect focus area boundaries:

```python
def test_grep_pattern_respects_focus_bounds():
    """Grep patterns should only match within focus area, not entire hunk."""
    # Create hunk with two methods
    # Create focus area for first method only
    # Rule with grep pattern that matches second method
    # Verify rule is NOT matched when filtering against first method's focus area
```

**Rationale:** With focus areas, rules should only trigger if their grep patterns match within the focused method, not in surrounding code within the same hunk.

**Files to modify:**
- Modify: `services/rule_loader.py` (add `filter_rules_for_focus_area`)
- Modify: `commands/agent/rules.py` (use focus areas for task creation)
- Modify: `tests/test_services.py` (add focus area filtering tests)

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
