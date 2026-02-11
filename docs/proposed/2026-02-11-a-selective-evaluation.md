## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture rules, layer responsibilities, dependency rules, placement guidance |
| `swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns, enum-based state, observable model conventions |
| `swift-testing` | Test style guide and conventions |
| `xcode-sim-automation:interactive-xcuitest` | Interactive XCUITest control for UI exploration and verification |

## Background

Currently PRRadar runs analysis as an all-or-nothing operation: evaluate every task (every rule × every focus area) for the entire PR. Results only appear in the UI after all evaluations complete and `phase_result.json` is written.

Bill wants selective, incremental evaluation:

1. **From the diff view**, right-click a file or hunk and say "run analysis on this code" — evaluating only tasks for that file or focus area
2. **Choose specific rules** — run one rule, a subset of rules, or all applicable rules against the selected code
3. **See results immediately** — each evaluation result should appear inline in the diff view as soon as it completes, without waiting for all evaluations to finish
4. **Both CLI and GUI** — CLI commands like `evaluate --file X --rule Y` alongside GUI interactions

### Design Decisions (from Bill)

- **Requires prior pipeline run**: The diff → focus areas → rules → tasks pipeline must have already run. Selective evaluation works from existing tasks.
- **Filtered rules only**: Use existing `AppliesTo` + grep filtering logic, not "run every rule regardless."
- **Inline diff results**: Violations appear as inline comment annotations in the diff view (same as today).

### Current Architecture Constraints

- `EvaluateUseCase.execute()` loads ALL tasks from phase-4 and evaluates all non-cached ones. No filtering parameters.
- `PRModel.evaluation` is only set on `.completed` — the UI doesn't see individual results as they stream in.
- `phase_result.json` is written once at the end with a single `success`/`failed` status.
- Evaluation results ARE written to disk immediately per-task (`data-{taskId}.json`), so the persistence layer already supports incremental writes.
- `EvaluationService.evaluateTask()` is already a pure function — one task in, one result out.

## Phases

## - [x] Phase 1: Selective Evaluation Use Case (Feature Layer)

**Skills to read**: `swift-app-architecture:swift-architecture`

Create a new `SelectiveEvaluateUseCase` in the Feature layer (`PRReviewFeature/usecases/`) that evaluates a filtered subset of existing tasks.

### Interface

```swift
public struct EvaluationFilter: Sendable {
    public let filePath: String?       // Filter tasks by file
    public let focusAreaId: String?    // Filter tasks by specific focus area
    public let ruleNames: [String]?    // Filter tasks by rule name(s)
}

public struct SelectiveEvaluateUseCase: Sendable {
    func execute(
        prNumber: String,
        filter: EvaluationFilter,
        repoPath: String?
    ) -> AsyncThrowingStream<PhaseProgress<EvaluationPhaseOutput>, Error>
}
```

### Behavior

1. Load all tasks from phase-4 (same as `EvaluateUseCase`)
2. Apply `EvaluationFilter` to narrow the task list
3. Check evaluation cache for the filtered tasks
4. Evaluate only uncached filtered tasks
5. Yield per-task results incrementally via `.progress` or a new `PhaseProgress` case (e.g., `.evaluationResult(RuleEvaluationResult)`)
6. Write each result to disk immediately (already happens in `EvaluationService`)
7. On completion, re-read ALL evaluation results from disk to build an updated `EvaluationSummary` and `EvaluationPhaseOutput` — this merges selective results with any prior full-run results
8. Do NOT write `phase_result.json` — selective runs don't mark the phase as "complete" since they only evaluate a subset

### Key Decisions

- Selective evaluation writes individual `data-{taskId}.json` files but does NOT rewrite `phase_result.json` or `summary.json` — those only get updated by full evaluation runs. This avoids inconsistent phase state.
- The returned `EvaluationPhaseOutput` reflects the merged state (all results on disk), so the UI can show everything.

### Files to Create/Modify

- Create: `PRReviewFeature/usecases/SelectiveEvaluateUseCase.swift`
- Modify: `PRRadarModels/` — add `EvaluationFilter` model

### Completion Notes

- `EvaluationFilter` created at `PRRadarModels/EvaluationFilter.swift` with `matches(_:)` method and `isEmpty` computed property for convenient filtering
- `SelectiveEvaluateUseCase` created at `PRReviewFeature/usecases/SelectiveEvaluateUseCase.swift`
- Filter matching uses AND logic across all non-nil criteria
- `buildMergedOutput()` private helper reads all `data-*.json` files from disk to merge selective results with prior full-run results
- Task snapshots are written for evaluated tasks (enabling cache on re-runs) but `summary.json` and `phase_result.json` are not written
- Per-task incremental `.evaluationResult` streaming deferred to Phase 2 — current implementation uses `.log` for progress like `EvaluateUseCase`

## - [x] Phase 2: Incremental Result Streaming

**Skills to read**: `swift-app-architecture:swift-architecture`

Add a new `PhaseProgress` case that carries an individual evaluation result, so the UI can react to each result as it arrives rather than waiting for the batch to finish.

### Changes

- Add `.evaluationResult(RuleEvaluationResult)` case to `PhaseProgress` enum
- In `SelectiveEvaluateUseCase`, yield `.evaluationResult(result)` after each task evaluates
- In `EvaluateUseCase` (full run), also yield `.evaluationResult(result)` in the `onResult` callback so the full pipeline also benefits from incremental display

### Files to Modify

- `PRReviewFeature/` — `PhaseProgress` enum (wherever defined)
- `SelectiveEvaluateUseCase.swift` (from Phase 1)
- `EvaluateUseCase.swift` — add per-result yields

### Completion Notes

- Added `.evaluationResult(RuleEvaluationResult)` case to `PhaseProgress` enum in `PRReviewFeature/models/PhaseProgress.swift` — required adding `import PRRadarModels`
- Both `EvaluateUseCase` and `SelectiveEvaluateUseCase` now yield `.evaluationResult(result)` for each task (both cached and freshly evaluated)
- `AnalyzeUseCase` forwards `.evaluationResult` from the evaluation phase up through its own stream, so full-pipeline consumers also receive per-task results
- `AnalyzeAllUseCase` likewise forwards `.evaluationResult` from each PR's analyze stream
- All 19 switch-statement consumers across CLI commands, app models, and feature use cases updated to handle the new case (all currently `break` — Phase 4/6 will make the GUI consumers react to results incrementally)
- 344 tests pass, build succeeds

## - [ ] Phase 3: CLI `evaluate` Command Filtering

**Skills to read**: `swift-app-architecture:swift-architecture`

Add `--file`, `--focus-area`, and `--rule` options to the existing `EvaluateCommand`.

### Interface

```
swift run PRRadarMacCLI evaluate 1 --config test-repo --file src/handler.py
swift run PRRadarMacCLI evaluate 1 --config test-repo --rule error-handling
swift run PRRadarMacCLI evaluate 1 --config test-repo --file src/handler.py --rule error-handling
swift run PRRadarMacCLI evaluate 1 --config test-repo --focus-area method-handler_py-process-10-25
```

### Behavior

- When any filter flag is present, use `SelectiveEvaluateUseCase` instead of `EvaluateUseCase`
- When no filter flags are present, use `EvaluateUseCase` (existing behavior, unchanged)
- Display results as they stream in (same format as today but per-task)

### Files to Modify

- `MacCLI/Commands/EvaluateCommand.swift` — add `@Option` parameters and routing logic

## - [ ] Phase 4: GUI — PRModel Incremental Evaluation Support

**Skills to read**: `swift-app-architecture:swift-swiftui`

Update `PRModel` to support running selective evaluations and displaying results incrementally.

### Changes to PRModel

1. Add a `runSelectiveEvaluation(filter: EvaluationFilter)` method that:
   - Uses `SelectiveEvaluateUseCase`
   - On each `.evaluationResult`, merges the new result into the existing `evaluation` property so the diff view updates immediately
   - Manages a new state like `.evaluatingSelective` that doesn't block other UI interactions (unlike full-run `.running` which disables all phase buttons)

2. Incremental evaluation merging:
   - Keep `evaluation` populated throughout the selective run
   - As each new `RuleEvaluationResult` arrives, rebuild the `EvaluationPhaseOutput` with the new result included
   - The diff view will reactively update because `evaluation` is `@Observable`

3. For full analysis runs (`runEvaluate`), also handle `.evaluationResult` to show results incrementally

### State Considerations

- Selective evaluation should NOT block running other phases or another selective evaluation
- Need to track which evaluations are "in flight" (for showing spinners per-file or per-task)
- The `canRunPhase()` gate should still work — selective evaluation only runs if tasks exist

### Files to Modify

- `MacApp/Models/PRModel.swift` — add `runSelectiveEvaluation`, handle `.evaluationResult` in `runEvaluate`

## - [ ] Phase 5: GUI — Diff View "Run Analysis" Actions

**Skills to read**: `swift-app-architecture:swift-swiftui`

Add context menu actions in `DiffPhaseView` for triggering selective evaluations.

### File-Level Actions

In the file sidebar, each file gets a context menu:
- **"Run All Rules"** — runs all applicable rules for tasks matching this file
- **"Run Rule..."** — shows a submenu of applicable rules for this file, letting the user pick one

### Focus Area / Hunk-Level Actions

In the diff content area, add a way to run analysis on a specific focus area. This requires:
- Identifying which focus area(s) correspond to the visible hunk/code
- The `tasks` array already contains focus area metadata, so we can group tasks by `focusArea.focusId` and match them to hunks via `focusArea.hunkIndex` and line ranges
- Add a "Run Analysis" action on the task badge or a context menu on the hunk header

### Rule Selection

When showing applicable rules for a file or focus area:
- Filter the `tasks` array by `focusArea.filePath` (for file) or `focusArea.focusId` (for focus area)
- Extract unique rule names from the filtered tasks
- Present as a list/submenu

### Per-Task Progress Indicator

- While a selective evaluation is running, show a spinner or progress indicator on the affected file/hunk in the sidebar
- When complete, the violation badge updates automatically (since `PRModel.evaluation` is `@Observable`)

### Files to Modify

- `MacApp/UI/PhaseViews/DiffPhaseView.swift` — add context menus, file-level and hunk-level actions
- May need a small helper view for rule selection (submenu or popover)

## - [ ] Phase 6: Incremental Results in Full Analysis Runs

**Skills to read**: `swift-app-architecture:swift-swiftui`

Ensure that full analysis runs (`runAnalysis` / `runEvaluate`) also display evaluation results incrementally as each task completes. This uses the same `.evaluationResult` mechanism from Phase 2.

### Changes

- In `PRModel.runEvaluate()`, handle `.evaluationResult` case to merge each result into `evaluation` as it arrives
- The diff view already reacts to `evaluation` changes via `@Observable`, so inline comments will appear one-by-one during a full run
- Update the summary bar counts incrementally (violations found, tasks evaluated)

### Files to Modify

- `MacApp/Models/PRModel.swift` — `.evaluationResult` handling in `runEvaluate()`

## - [ ] Phase 7: Unit Tests & CLI Validation

**Skills to read**: `swift-testing`

### Unit Tests

- `SelectiveEvaluateUseCase` filter logic: test filtering by file, focus area, rule name, and combinations
- `EvaluationFilter` model: test edge cases (nil filters = no filtering, empty arrays)
- Incremental result merging in `PRModel` (if testable)

### Build & Test

```bash
cd pr-radar-mac
swift build
swift test
```

### CLI Integration Tests (against test repo)

Run selective evaluation via CLI against `/Users/bill/Developer/personal/PRRadar-TestRepo` to verify filtering works end-to-end:

- `evaluate --file` filters to tasks for that file only
- `evaluate --rule` filters to tasks for that rule only
- `evaluate` with no flags runs all tasks (existing behavior preserved)
- Combined flags work (e.g., `--file X --rule Y`)

## - [ ] Phase 8: GUI Validation via Interactive XCUITest

**Skills to read**: `xcode-sim-automation:interactive-xcuitest`

Use the `/interactive-xcuitest` skill to drive the MacApp and validate the full selective evaluation flow in the GUI.

### Test Setup

1. In `/Users/bill/Developer/personal/PRRadar-TestRepo`, create a branch with a deliberate rule violation (e.g., add code that violates an existing rule like naming conventions or error handling)
2. Open a PR for that branch using `gh pr create`
3. Run the full pipeline once via CLI (`swift run PRRadarMacCLI analyze <pr> --config test-repo`) to populate diff, focus areas, rules, and tasks

### GUI Test Scenarios

Use `/interactive-xcuitest` to:

1. **Launch the MacApp** and navigate to the test PR
2. **Verify diff view loads** with the test PR's changed files in the sidebar
3. **Right-click a file** in the sidebar → select "Run All Rules" → verify:
   - A progress indicator appears on the file
   - Inline violation annotations appear in the diff view as each evaluation completes (without a full page refresh or app restart)
   - The violation badge on the file updates in the sidebar
4. **Right-click a file** → select "Run Rule..." → pick a specific rule → verify only that rule's result appears
5. **Run a full analysis** from the UI and verify results stream in incrementally (violations appear one by one, not all at once at the end)
6. **Check state consistency** — after selective evaluation, verify:
   - The summary bar counts update correctly
   - Can still navigate between files and see results
   - No need to manually refresh or relaunch the app to see results
7. **Take screenshots** at key points for visual verification

### What to Verify Without XCUITest

If any interaction is hard to automate (e.g., context menu submenus), document the manual steps clearly and verify what's automatable.
