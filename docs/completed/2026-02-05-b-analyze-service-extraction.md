# Analyze Command Service Extraction

## Background

The `analyze.py` command currently contains business logic that duplicates code in other commands (`evaluate.py`, `comment.py`). Following the Service Layer pattern from python-architecture, the analyze command should orchestrate high-level operations by calling services, not implement low-level details itself.

**Reference:** This refactor follows the **creating-services** skill from `gestrich/python-architecture`. Key patterns we'll apply:
- **Core vs Composite services**: Core services do ONE thing (TaskLoader, Violation), Composite services orchestrate workflows
- **Constructor injection**: All dependencies via constructor, no defaults, no env var reading in services
- **Static vs instance methods**: Pure functions (filters, transformations) should be `@staticmethod`
- **No CLI output in services**: Services return data; commands handle `print()` statements

**Current problems:**
1. Task loading logic is duplicated between `analyze.py` and `evaluate.py`
2. Batch evaluation loops exist in both files with similar patterns
3. `CommentableViolation` creation is done inline in multiple places
4. Evaluation result file I/O is scattered across commands
5. Statistics tracking uses different structures (`AnalyzeStats` vs `EvaluationSummary`)

**Goal:** Make `cmd_analyze()` a thin orchestration layer that calls service APIs, with all business logic in services.

## - [x] Phase 1: Create TaskLoaderService

Extract task loading logic into a dedicated service.

**Status:** ✅ Completed

**Service type:** Core service (single responsibility: load tasks from filesystem)

**Files created:**
- `services/task_loader_service.py`

**Service API:**
```python
class TaskLoaderService:
    """Load evaluation tasks from JSON files.

    Core service - single responsibility, direct filesystem access.
    """

    def __init__(self, tasks_dir: Path):
        """Constructor injection - dependency passed in, not created internally."""
        self.tasks_dir = tasks_dir

    def load_all(self) -> list[EvaluationTask]:
        """Load all tasks. Returns empty list if none found (not exceptional)."""
        ...

    def load_filtered(self, rules_filter: list[str]) -> list[EvaluationTask]:
        """Load tasks matching rule names."""
        ...

    @staticmethod
    def _parse_task_file(file_path: Path) -> EvaluationTask | None:
        """Static - pure function, no state dependency."""
        ...
```

**Skill patterns applied:**
- Constructor takes `tasks_dir` dependency (no hardcoded paths)
- Returns empty list for "no tasks" (normal case), silently skips unparseable files (returns None)
- `_parse_task_file` is static because it's a pure transformation

**Files modified:**
- `commands/agent/analyze.py` - Now uses `TaskLoaderService.load_all()` instead of inline JSON parsing
- `commands/agent/evaluate.py` - Now uses `TaskLoaderService.load_all()` and `load_filtered()` instead of inline parsing

**Technical notes:**
- Error messages for missing directories preserved in command layer (UI concern)
- Both commands maintain original user-facing output
- `_parse_task_file` returns `None` on parse failure rather than raising—callers silently skip bad files

## - [x] Phase 2: Consolidate Batch Evaluation in EvaluationService

Move batch evaluation loop into the existing evaluation service.

**Status:** ✅ Completed

**Service type:** Core service (direct API access to Claude SDK)

**Files modified:**
- `services/evaluation_service.py` - added `run_batch_evaluation()` function

**Service API additions:**
```python
async def run_batch_evaluation(
    tasks: list[EvaluationTask],
    output_dir: Path,
    on_result: Callable[[int, int, EvaluationResult], None] | None = None,
) -> list[EvaluationResult]:
    """Run evaluations for all tasks.

    Args:
        tasks: Tasks to evaluate
        output_dir: Where to save results (creates 'evaluations' subdirectory)
        on_result: Optional callback for progress reporting. Called with
                   (index, total, result) after each evaluation completes.
                   Index is 1-based. Service does NOT print progress - caller
                   handles display via this callback.

    Returns:
        List of all evaluation results
    """
```

**Skill patterns applied:**
- **No print() in service**: All progress display moved to callback
- **Callback for UI concerns**: `on_result` receives `(index, total, result)` so CLI layer can format progress without service knowing about it
- Service returns data; command layer decides how to display it
- File I/O (saving results to JSON) stays in service (not a UI concern)

**Files updated to use service:**
- `commands/agent/analyze.py` - `run_analyze_batch_evaluation()` wraps service, adds stats tracking
- `commands/agent/evaluate.py` - `run_evaluations()` wraps service, builds `EvaluationSummary`

**Technical notes:**
- Callback signature includes `(index, total, result)` rather than just `result` since callers need index for progress display
- Both command wrappers use `nonlocal` or mutable objects to track running totals in callbacks
- Service handles directory creation (`evaluations/`) and per-task JSON file writes
- Summary file writing remains in `cmd_evaluate()` as it's command-specific

## - [x] Phase 3: Create ViolationService

Extract violation creation and filtering logic.

**Status:** ✅ Completed

**Service type:** Core service (single responsibility: transform evaluation results to violations)

**Files created:**
- `services/violation_service.py`

**Service API:**
```python
class ViolationService:
    """Transform evaluation results into commentable violations.

    Core service - focused on data transformation, no I/O.
    """

    @staticmethod
    def create_violation(
        result: EvaluationResult,
        task: EvaluationTask,
    ) -> CommentableViolation:
        """Static - pure transformation, no state needed."""
        ...

    @staticmethod
    def filter_by_score(
        results: list[EvaluationResult],
        tasks: list[EvaluationTask],
        min_score: int,
    ) -> list[CommentableViolation]:
        """Static - pure filter function."""
        ...
```

**Skill patterns applied:**
- **All static methods**: These are pure transformations with no state dependency
- No constructor needed - this service has no dependencies (could be module-level functions, but class groups related operations)
- **Decision guide**: "Does this service do ONE thing?" → Yes (data transformation) → Core service

**Files modified:**
- `commands/agent/analyze.py` - Now uses `ViolationService.create_violation()` and `ViolationService.filter_by_score()`

**Technical notes:**
- `create_violation()` is used in interactive mode after each individual evaluation
- `filter_by_score()` is used in batch mode to filter and convert all results at once
- `comment.py` `load_violations()` remains separate as it loads from files (different use case - reconstructs violations from persisted evaluation results)
- Removed `CommentableViolation` import from analyze.py (now accessed via ViolationService)

**Expected outcome:** Single place for EvaluationResult → CommentableViolation conversion.

## - [x] Phase 4: Move EvaluationSummary to Domain

The `EvaluationSummary` dataclass is a domain model, not command-specific.

**Status:** ✅ Completed

**Related skill:** See **domain-modeling** skill for domain model patterns.

**Files modified:**
- `domain/agent_outputs.py` - Added `EvaluationSummary` dataclass
- `domain/__init__.py` - Added export for `EvaluationSummary`
- `commands/agent/evaluate.py` - Updated to import `EvaluationSummary` from domain

**Moved:**
- `EvaluationSummary` dataclass from `evaluate.py` to `domain/agent_outputs.py`

**Decision on `AnalyzeStats`:** Kept in command layer (option 1) since:
- It has `print_summary()` which is presentation logic
- `AnalyzeStats` is specific to the analyze command's workflow
- The skill guidance states this is "acceptable since it's presentation logic"

**Technical notes:**
- `EvaluationSummary` references `EvaluationResult` which remains in `evaluation_service.py`
- Used `TYPE_CHECKING` import to avoid circular dependencies between domain and service layers
- `EvaluationResult` could be moved to domain in a future refactoring phase

## - [x] Phase 5: Refactor analyze.py to Use Services

Update `cmd_analyze()` to use the new services.

**Status:** ✅ Completed

**Related skill:** See **cli-architecture** skill for command structure patterns.

**Files modified:**
- `commands/agent/analyze.py`

**Changes verified:**
1. ✅ Uses `TaskLoaderService.load_all()` for task loading (line 308-309)
2. ✅ Uses `run_batch_evaluation()` from evaluation_service (imported at line 27-28, used via `run_analyze_batch_evaluation`)
3. ✅ Uses `ViolationService.filter_by_score()` for batch mode violations (line 350)
4. ✅ Uses `ViolationService.create_violation()` for interactive mode (line 171)
5. ✅ Keeps `run_interactive_evaluation()` in analyze.py (interactive UI logic)
6. ✅ Keeps `AnalyzeStats` and `prompt_for_task()` (UI concerns in command layer)

**Skill patterns applied:**
- **Entry point instantiates services**: `cmd_analyze()` creates `TaskLoaderService` with dependency
- **Command handles output**: All `print()` statements stay in command, not services
- **Services are stateless**: Fresh `TaskLoaderService` instance per invocation
- **Callback for UI concerns**: `run_analyze_batch_evaluation` uses callback for progress display

**Technical notes:**
- The `run_analyze_batch_evaluation()` wrapper (lines 189-222) serves as the UI adapter between the service's callback interface and the `AnalyzeStats` tracking
- `ViolationService` has only static methods, so no instance is created (called as `ViolationService.create_violation()`)
- The phase flow (diff → rules → evaluate → comment) uses `stop_after` and `skip_to` for partial execution

## - [x] Phase 6: Refactor evaluate.py to Use Services

Update `cmd_evaluate()` to use the shared services.

**Status:** ✅ Completed

**Files modified:**
- `commands/agent/evaluate.py`

**Changes applied:**
1. ✅ Uses `TaskLoaderService` for task loading (with filter support)
2. ✅ Uses `run_batch_evaluation()` from evaluation_service directly
3. ✅ Imports `EvaluationSummary` from domain layer
4. ✅ All `print()` statements are in the command layer
5. ✅ Removed intermediate `run_evaluations()` wrapper - simplified to inline callback

**Final structure:**
```python
def cmd_evaluate(pr_number: int, output_dir: Path, rules_filter: list[str] | None = None) -> int:
    # 1. Initialize services
    task_loader = TaskLoaderService(output_dir / "tasks")

    # 2. Load tasks (service returns data, command prints)
    if rules_filter:
        tasks = task_loader.load_filtered(rules_filter)
        print(f"  Filtering by rules: {', '.join(rules_filter)}")
        print(f"  Matched {len(tasks)} tasks")
    else:
        tasks = task_loader.load_all()
        print(f"  Loaded {len(tasks)} tasks")

    # 3. Handle no tasks case (unified error handling)
    if not tasks:
        ...  # Error messages for missing dir or no matches

    # 4. Run evaluations with progress callback
    total_cost = 0.0
    total_duration = 0
    violations_count = 0

    def on_result(index: int, total: int, result: EvaluationResult) -> None:
        nonlocal total_cost, total_duration, violations_count
        status = "⚠️ Violation" if result.evaluation.violates_rule else "✓ OK"
        print(f"  [{index}/{total}] {result.rule_name}: {status}")
        # Track running totals...

    results = asyncio.run(run_batch_evaluation(tasks, output_dir, on_result))

    # 5. Build and save summary
    summary = EvaluationSummary(...)
    summary_path.write_text(json.dumps(summary.to_dict(), indent=2))

    # 6. Print summary (command layer responsibility)
    print(f"  Tasks evaluated: {summary.total_tasks}")
    ...
```

**Technical notes:**
- File reduced from 155 lines to 116 lines (~25% reduction)
- Removed `run_evaluations()` wrapper function - callback pattern is sufficient
- Running totals tracked via `nonlocal` in callback for summary building
- Unified "no tasks" error handling (was duplicated in if/else branches)

**Skill patterns applied:**
- **Entry point instantiates services**: `cmd_evaluate()` creates `TaskLoaderService`
- **Command handles output**: All `print()` statements stay in command
- **Callback for UI concerns**: Progress display delegated to callback
- **Service returns data**: Summary built from service results in command layer

## - [x] Phase 7: Validation

**Status:** ✅ Completed

**Related skill:** See **testing-services** skill for service testing patterns.

**Unit tests created:**
- `scripts/tests/test_services.py` - 15 tests covering both services

**TaskLoaderService tests:**
- `test_load_all_returns_empty_list_when_directory_does_not_exist`
- `test_load_all_returns_empty_list_when_no_files`
- `test_load_all_loads_single_task`
- `test_load_all_loads_multiple_tasks`
- `test_load_all_skips_invalid_json_files`
- `test_load_filtered_returns_only_matching_rules`
- `test_load_filtered_returns_empty_list_when_no_matches`
- `test_parse_task_file_returns_none_for_invalid_structure`

**ViolationService tests:**
- `test_create_violation_transforms_result_and_task`
- `test_create_violation_preserves_evaluation_details`
- `test_filter_by_score_excludes_non_violations`
- `test_filter_by_score_excludes_low_scores`
- `test_filter_by_score_returns_empty_for_no_qualifying_results`
- `test_filter_by_score_handles_missing_task`
- `test_filter_by_score_preserves_documentation_link`

**Success criteria verification:**
- ✅ No duplicate code between analyze.py and evaluate.py (both use shared services)
- ✅ `analyze.py` uses service layer for task loading and evaluation
- ✅ `evaluate.py` uses service layer for task loading and evaluation
- ✅ All business logic lives in services (TaskLoaderService, ViolationService, run_batch_evaluation)
- ✅ Services have no `print()` statements (verified via grep - new services are print-free)
- ✅ All services can be unit tested with mocked dependencies (71 tests pass)

**Technical notes:**
- Tests use `tempfile.TemporaryDirectory()` for filesystem isolation
- Test fixtures (`make_task`, `make_result`, etc.) provide reusable test data builders
- Tests follow Arrange-Act-Assert pattern from testing-services skill
- No mocking of Claude SDK needed since services use constructor injection
