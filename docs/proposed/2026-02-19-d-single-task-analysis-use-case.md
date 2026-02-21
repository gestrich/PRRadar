# Extract SingleTaskAnalysisUseCase with Nested TaskProgress Enum

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture — layer placement, use case patterns |
| `/swift-testing` | Test style guide for validation |

## Background

`AnalyzeUseCase` and `SelectiveAnalyzeUseCase` both orchestrate batch analysis but share no common abstraction for a single task. The per-task lifecycle (prompt → AI output → tool use → result) is embedded inside batch callbacks, making it impossible to run one task independently without going through the batch machinery.

Meanwhile, `PhaseProgress` has 4 task-specific cases (`taskOutput`, `taskPrompt`, `taskToolUse`, `taskCompleted`) that every consumer must exhaustively switch on — even phases that never emit them. A nested `TaskProgress` enum gives tasks their own focused type, collapses those 4 cases into one `.taskEvent` wrapper in `PhaseProgress`, and enables a shared handler in PRModel.

This supersedes plans `2026-02-19-a` (extract mergeAnalysisResult) and `2026-02-19-c` (unify analyze use cases).

## Phases

## - [x] Phase 1: Add `TaskProgress` enum

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Placed in Features layer alongside `PhaseProgress`; used `AnalysisOutput` in `.completed` to match existing `taskCompleted` data for a mechanical Phase 2

**Skills to read**: `/swift-app-architecture:swift-architecture`

Create a new enum in the Features layer alongside `PhaseProgress`:

```swift
// In Sources/features/PRReviewFeature/models/TaskProgress.swift
public enum TaskProgress: Sendable {
    case prompt(text: String)
    case output(text: String)
    case toolUse(name: String)
    case completed(cumulative: AnalysisOutput)
}
```

The `.completed` case carries `AnalysisOutput` (not `RuleEvaluationResult`) so that Phase 2 is a pure mechanical substitution — existing consumers keep the same data they had before. Phase 3 narrows this to `RuleEvaluationResult` alongside the `handleTaskEvent` extraction.

No other files change yet.

**File to create:** `Sources/features/PRReviewFeature/models/TaskProgress.swift`

## - [x] Phase 2: Replace task cases in `PhaseProgress` with `.taskEvent` (pure mechanical)

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Pure mechanical substitution — no behavioral changes, only pattern-match syntax updated across all 16 files

**Skills to read**: `/swift-app-architecture:swift-architecture`

**This phase is a pure mechanical substitution.** No behavioral changes, no new helpers, no logic restructuring. Every switch site keeps its existing logic — only the pattern-match syntax changes.

Replace the 4 task-specific cases in `PhaseProgress`:
```swift
// Remove these:
case taskOutput(task: AnalysisTaskOutput, text: String)
case taskPrompt(task: AnalysisTaskOutput, text: String)
case taskToolUse(task: AnalysisTaskOutput, name: String)
case taskCompleted(task: AnalysisTaskOutput, cumulative: AnalysisOutput)

// Add this:
case taskEvent(task: AnalysisTaskOutput, event: TaskProgress)
```

Then fix every switch site:
- Sites that `break` on all 4 task cases → collapse into `case .taskEvent: break`
- Sites that forward events (RunAllUseCase, RunPipelineUseCase) → forward `.taskEvent` directly
- Sites that handle specific task events (PRModel `runAnalyze`, `runSelectiveAnalysis`, AnalyzeCommand, RunCommand) → nested pattern match, e.g. `case .taskEvent(let task, .completed(let cumulative)):` with identical logic
- Producers (AnalyzeUseCase, SelectiveAnalyzeUseCase) → yield `.taskEvent(task:, event:)` wrapping the same data

**Files to modify:**
- `Sources/features/PRReviewFeature/models/PhaseProgress.swift`
- All CLI commands in `Sources/apps/MacCLI/Commands/` (AnalyzeCommand, RunCommand, PrepareCommand, RunAllCommand, RefreshCommand, ReportCommand, CommentCommand, RefreshPRCommand, SyncCommand)
- `Sources/features/PRReviewFeature/usecases/RunPipelineUseCase.swift`
- `Sources/features/PRReviewFeature/usecases/RunAllUseCase.swift`
- `Sources/features/PRReviewFeature/usecases/DeletePRDataUseCase.swift`
- `Sources/features/PRReviewFeature/usecases/AnalyzeUseCase.swift` — yield `.taskEvent` instead of individual cases
- `Sources/features/PRReviewFeature/usecases/SelectiveAnalyzeUseCase.swift` — same
- `Sources/apps/MacApp/Models/PRModel.swift`
- `Sources/apps/MacApp/Models/AllPRsModel.swift`

## - [x] Phase 3: Narrow `TaskProgress.completed` to `RuleEvaluationResult` and extract `handleTaskEvent`

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Narrowed associated value to single-task result; extracted shared `handleTaskEvent` helper in Apps layer; used `appendResult` mutating method on `AnalysisOutput` for incremental updates

**Skills to read**: `/swift-app-architecture:swift-architecture`

Two changes in this phase:

**1. Change `TaskProgress.completed` associated value:**
```swift
// Before (Phase 2 state):
case completed(cumulative: AnalysisOutput)

// After:
case completed(result: RuleEvaluationResult)
```

This requires updating producers (AnalyzeUseCase, SelectiveAnalyzeUseCase) to yield just the individual `RuleEvaluationResult` instead of the cumulative `AnalysisOutput`, and updating consumers accordingly.

**2. Extract `handleTaskEvent` in PRModel:**
```swift
private func handleTaskEvent(_ task: AnalysisTaskOutput, _ event: TaskProgress) {
    switch event {
    case .prompt(let text):
        appendAIPrompt(task: task, text: text)
    case .output(let text):
        appendAIOutput(text)
    case .toolUse(let name):
        appendAIToolUse(name)
    case .completed:
        activeAnalysisFilePath = nil
    }
}
```

Update `runAnalyze` and `runSelectiveAnalysis` to call it:
```swift
case .taskEvent(let task, let event):
    handleTaskEvent(task, event)
    if case .completed(let result) = event {
        insertResult(task, result)  // lightweight append
    }
```

Where `insertResult` is a simple helper that appends to `inProgressAnalysis.evaluations` — not computing full summaries. This replaces the old `mergeAnalysisResult` and the old `inProgressAnalysis = cumulative` assignments.

**Files to modify:**
- `Sources/features/PRReviewFeature/models/TaskProgress.swift`
- `Sources/features/PRReviewFeature/usecases/AnalyzeUseCase.swift`
- `Sources/features/PRReviewFeature/usecases/SelectiveAnalyzeUseCase.swift`
- `Sources/apps/MacApp/Models/PRModel.swift`

## - [x] Phase 4: Create `AnalyzeSingleTaskUseCase`

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Features-layer use case returning `AsyncThrowingStream<TaskProgress, Error>`; replicates credential setup and disk-write patterns from `AnalyzeUseCase`; delegates single-operation work to `AnalysisService.analyzeTask()`

**Skills to read**: `/swift-app-architecture:swift-architecture`

New use case in the Features layer that runs exactly one task:

```swift
public struct AnalyzeSingleTaskUseCase {
    let config: RepositoryConfiguration

    public func execute(
        task: AnalysisTaskOutput,
        prNumber: Int,
        commitHash: String? = nil
    ) -> AsyncThrowingStream<TaskProgress, Error>
}
```

Implementation:
1. Resolve paths (`evalsDir`, `transcriptDir`) via `DataPathsService`
2. Create `AnalysisService` and call `analyzeTask()` with callbacks that yield `.prompt`, `.output`, `.toolUse`
3. Write result file to disk (`data-{taskId}.json` in evalsDir) — currently done by `runBatchAnalysis` at line 240-244 of `AnalysisService.swift`, the single-task use case replicates this
4. Write task snapshot via `AnalysisCacheService.writeTaskSnapshots(tasks: [task], evalsDir:)`
5. Yield `.completed(result)`

**File to create:** `Sources/features/PRReviewFeature/usecases/AnalyzeSingleTaskUseCase.swift`

## - [ ] Phase 5: Wire `AnalyzeSingleTaskUseCase` into `AnalyzeUseCase`

**Skills to read**: `/swift-app-architecture:swift-architecture`

Refactor `AnalyzeUseCase` to call `AnalyzeSingleTaskUseCase` per task instead of calling `AnalysisService.runBatchAnalysis` directly.

The loop replaces the `runBatchAnalysis` call:
```swift
for task in tasksToEvaluate {
    for try await event in singleTaskUseCase.execute(task: task, prNumber: prNumber, commitHash: commitHash) {
        continuation.yield(.taskEvent(task: task, event: event))
        if case .completed(let result) = event {
            cumulativeEvaluations.append(result)
            let cumOutput = AnalysisOutput.cumulative(...)
            // cumulative tracking stays internal to AnalyzeUseCase
        }
    }
}
```

Cached tasks still yield `.taskEvent(task, .completed(cachedResult))` without going through the single-task use case (they're already evaluated).

**File to modify:** `Sources/features/PRReviewFeature/usecases/AnalyzeUseCase.swift`

## - [ ] Phase 6: Unify AnalyzeUseCase and SelectiveAnalyzeUseCase

Add optional `filter: AnalysisFilter?` to `AnalyzeUseCase.execute()`. When present:
- Filter tasks before evaluation
- Seed cumulative state from existing disk evaluations (`loadExistingEvaluations`)
- Write task snapshots only for evaluated tasks (a full run writes for all tasks; a filtered run can't write for tasks it didn't evaluate or they'd be incorrectly marked cached)
- Re-read all results from disk for final output (`buildMergedOutput`) since the filtered run only has its subset in memory but the UI needs the complete picture

Move `loadExistingEvaluations()` and `buildMergedOutput()` from `SelectiveAnalyzeUseCase` into `AnalyzeUseCase` as private helpers. Delete `SelectiveAnalyzeUseCase`.

Update callers:
- `PRModel` — collapse `runAnalyze`/`runSelectiveAnalysis` into `runAnalyze(filter:)`
- `AnalyzeCommand` — remove `if filter.isEmpty` branch
- `RunPipelineUseCase` / `RunAllUseCase` — no changes (already use no filter)

**Files to modify:**
- `Sources/features/PRReviewFeature/usecases/AnalyzeUseCase.swift`
- `Sources/apps/MacApp/Models/PRModel.swift`
- `Sources/apps/MacCLI/Commands/AnalyzeCommand.swift`

**File to delete:** `Sources/features/PRReviewFeature/usecases/SelectiveAnalyzeUseCase.swift`

## - [ ] Phase 7: Add `runSingleAnalysis` to PRModel

**Skills to read**: `/swift-app-architecture:swift-architecture`

Add a method for running one task standalone from the UI:

```swift
func runSingleAnalysis(task: AnalysisTaskOutput) async {
    selectiveAnalysisInFlight.insert(task.taskId)
    liveAccumulators = []
    currentLivePhase = .analyze

    let useCase = AnalyzeSingleTaskUseCase(config: config)
    do {
        for try await event in useCase.execute(task: task, prNumber: prNumber, commitHash: currentCommitHash) {
            handleTaskEvent(task, event)
        }
        // Result was written to disk by the use case
        reloadDetail()
    } catch {
        // handle error
    }
    selectiveAnalysisInFlight.remove(task.taskId)
    currentLivePhase = nil
}
```

No merge logic — the use case writes the result to disk, and `reloadDetail()` picks it up.

Update `startSelectiveAnalysis` to call `runSingleAnalysis` for single-task filters, or `runAnalyze(filter:)` for multi-task filters.

**File to modify:** `Sources/apps/MacApp/Models/PRModel.swift`

## - [ ] Phase 8: Validation

**Skills to read**: `/swift-testing`

- `swift build` — no compile errors
- `swift test` — all tests pass
- Search for remaining references to `SelectiveAnalyzeUseCase` — should be zero
- Search for old PhaseProgress cases (`taskOutput`, `taskPrompt`, `taskToolUse`, `taskCompleted`) — should be zero
- Verify the old `mergeAnalysisResult` method is gone from PRModel
