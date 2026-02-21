# Unify AnalyzeUseCase and SelectiveAnalyzeUseCase

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture — confirms use cases belong in Features layer |
| `/swift-testing` | Test style guide for validation |

## Background

`AnalyzeUseCase` and `SelectiveAnalyzeUseCase` are two separate use cases that share ~80% of their logic. The only real differences are:

1. **Task filtering** — selective filters tasks before evaluation; full evaluates all
2. **Cumulative seeding** — selective seeds from existing disk evaluations so the UI shows the full picture; full starts fresh
3. **Task snapshots** — selective writes snapshots only for evaluated tasks; full writes for all
4. **Final output** — selective re-reads all results from disk to merge; full uses only the current run's results

These are all variants of the same operation: "evaluate some tasks and report results." Adding an optional `AnalysisFilter` parameter to `AnalyzeUseCase` can handle both flows, eliminating `SelectiveAnalyzeUseCase` entirely.

In PRModel, `runAnalyze` and `runSelectiveAnalysis` can collapse into one method, and `startSelectiveAnalysis` just calls `runAnalyze` with a filter. The CLI's `AnalyzeCommand` already branches between the two use cases based on `filter.isEmpty` — that branch disappears.

## Phases

## - [ ] Phase 1: Add optional filter to AnalyzeUseCase

**Skills to read**: `/swift-app-architecture:swift-architecture`

Add an optional `AnalysisFilter` parameter to `AnalyzeUseCase.execute()`:

```swift
public func execute(
    prNumber: Int,
    filter: AnalysisFilter? = nil,
    repoPath: String? = nil,
    commitHash: String? = nil
) -> AsyncThrowingStream<PhaseProgress<AnalysisOutput>, Error>
```

Port the behavioral differences from `SelectiveAnalyzeUseCase` into `AnalyzeUseCase`, conditioned on whether a non-empty filter is present:

| Behavior | `filter == nil` (full) | `filter != nil` (selective) |
|----------|------------------------|----------------------------|
| Tasks evaluated | all tasks | `allTasks.filter { filter.matches($0) }` |
| Cumulative seed | empty array | `loadExistingEvaluations()` from disk |
| Task snapshots | write for all tasks | write only for evaluated tasks |
| Final output | `cachedResults + freshResults` | `buildMergedOutput()` from all disk files |
| Empty tasks | yield empty output | yield merged disk output |

**Why the branching matters for snapshots and final output:**

- **Task snapshots** record each task's blob hash so the cache can detect changes on the next run. A full run evaluates every task, so it writes snapshots for all of them. A filtered run only evaluates a subset — writing snapshots for unevaluated tasks would incorrectly mark them as "up to date" even though they weren't re-run. So the filtered path writes snapshots only for the tasks it actually evaluated.

- **Final output** in a full run already has every result in memory (`cachedResults + freshResults` covers all tasks), so there's no need to hit disk again. A filtered run only has results for the filtered subset in memory, but the UI needs the complete picture (all prior evaluations plus the new ones). So the filtered path calls `buildMergedOutput()` which re-reads all individual `data-{taskId}.json` files from disk to reconstruct the full set of evaluations.

Both of these behaviors are conditioned on `filter != nil` inside the unified method — not separate code paths in separate files.

Move `loadExistingEvaluations()` and `buildMergedOutput()` from `SelectiveAnalyzeUseCase` into `AnalyzeUseCase` as private helpers.

**Files to modify:**
- `Sources/features/PRReviewFeature/usecases/AnalyzeUseCase.swift`

## - [ ] Phase 2: Update all callers to use the unified AnalyzeUseCase

Update every caller to drop `SelectiveAnalyzeUseCase` and use `AnalyzeUseCase` with the filter parameter.

**PRModel** — Collapse `runAnalyze` and `runSelectiveAnalysis` into a single method:
```swift
private func runAnalyze(filter: AnalysisFilter? = nil) async {
    // ...
    let useCase = AnalyzeUseCase(config: config)
    // stream = useCase.execute(prNumber: prNumber, filter: filter, commitHash: currentCommitHash)
    // Same switch handling — taskCompleted manages both inProgressAnalysis
    // and selectiveAnalysisInFlight (when filter is present)
}
```

Update `startSelectiveAnalysis` to call `runAnalyze(filter:)` instead of `runSelectiveAnalysis(filter:)`.

**AnalyzeCommand (CLI)** — Remove the `if filter.isEmpty` branch; always use `AnalyzeUseCase`:
```swift
let useCase = AnalyzeUseCase(config: config)
let stream = useCase.execute(
    prNumber: options.prNumber,
    filter: filter.isEmpty ? nil : filter,
    commitHash: options.commitHash
)
```

**RunPipelineUseCase** — Already uses `AnalyzeUseCase` with no filter; no changes needed.

**Files to modify:**
- `Sources/apps/MacApp/Models/PRModel.swift` — merge the two methods, update `startSelectiveAnalysis`
- `Sources/apps/MacCLI/Commands/AnalyzeCommand.swift` — remove branching
- Verify `RunPipelineUseCase` and `RunAllUseCase` need no changes

## - [ ] Phase 3: Delete SelectiveAnalyzeUseCase

Remove the file entirely. Update `Package.swift` if needed (though SPM auto-discovers sources).

**Files to delete:**
- `Sources/features/PRReviewFeature/usecases/SelectiveAnalyzeUseCase.swift`

## - [ ] Phase 4: Validation

**Skills to read**: `/swift-testing`

- `swift build` — no compile errors
- `swift test` — all tests pass
- Search codebase for any remaining references to `SelectiveAnalyzeUseCase` — should be zero
- Verify the CLI still works with filter flags: `swift run PRRadarMacCLI analyze 1 --config test-repo --file SomeFile.swift` should use the filtered path
