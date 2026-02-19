# Extract mergeAnalysisResult from PRModel

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules — confirms this logic belongs in Features, not Apps |
| `/swift-testing` | Test style guide for writing new unit tests |

## Background

`PRModel.mergeAnalysisResult()` (lines 618–656) contains business logic that builds `AnalysisSummary` objects, computes violation counts, sums costs/durations, and merges evaluation arrays. This violates the architecture principle that App-layer `@Observable` models should contain minimal business logic — they should call use cases and route results to state, not compute domain aggregates.

The CLI already ignores `.analysisResult` events and waits for `.completed` — it has no merging problem. The issue is GUI-specific: `PRModel` needs progressive updates as individual `RuleEvaluationResult` values arrive, so it built its own merge logic.

The fix: make the use cases yield an intermediate `AnalysisOutput` (with summary already computed) alongside each `.analysisResult` event, so `PRModel` simply assigns it to state.

## Phases

## - [x] Phase 1: Add cumulative AnalysisOutput to the `.analysisResult` progress event

**Skills to read**: `/swift-app-architecture:swift-architecture`

Currently `PhaseProgress` has:
```swift
case analysisResult(RuleEvaluationResult)
```

Change it to carry the cumulative output so far:
```swift
case analysisResult(RuleEvaluationResult, cumulativeOutput: AnalysisOutput)
```

**Files to modify:**
- `Sources/features/PRReviewFeature/models/PhaseProgress.swift` — Update the enum case

**Impact:** This is a breaking change to the enum, so all switch-case consumers will need updating (handled in later phases).

**Completion notes:** Updated the enum case and fixed all 23 consumer sites to compile:
- Added `AnalysisOutput.empty` static placeholder (used by construction sites until Phase 2 adds real cumulative logic)
- Use cases that re-yield (RunPipelineUseCase, RunAllUseCase) now pass through both values
- PRModel destructuring sites ignore cumulativeOutput with `_` (Phase 3 will use it)
- All 488 tests pass

## - [x] Phase 2: Build cumulative AnalysisOutput inside the use cases

**Skills to read**: `/swift-app-architecture:swift-architecture`

Move the merge logic into `AnalyzeUseCase` and `SelectiveAnalyzeUseCase`. As each result arrives (from cache or fresh evaluation), the use case maintains a running `AnalysisOutput` and yields it alongside the result.

**`AnalyzeUseCase` changes:**
- Add a local variable tracking cumulative evaluations as results arrive
- After each cached result yield and each fresh result callback, build an `AnalysisOutput` with summary and yield `.analysisResult(result, cumulativeOutput: output)`
- The existing `.completed` logic already builds a final output — no change needed there

**`SelectiveAnalyzeUseCase` changes:**
- Same pattern: maintain running evaluations, yield cumulative output with each `.analysisResult`
- The existing `buildMergedOutput()` at completion is unaffected

**Key detail:** The merge logic currently in `PRModel.mergeAnalysisResult()` does deduplication by `taskId` (filters out existing results before appending). The use case version should replicate this — particularly important for selective analysis where prior results exist.

**Files to modify:**
- `Sources/features/PRReviewFeature/usecases/AnalyzeUseCase.swift`
- `Sources/features/PRReviewFeature/usecases/SelectiveAnalyzeUseCase.swift`

**Completion notes:** Added `AnalysisOutput.cumulative(evaluations:tasks:prNumber:cachedCount:)` static method that deduplicates by taskId (keeping last occurrence, matching PRModel's behavior) and builds a summary. Both use cases now maintain a `cumulativeEvaluations` array and yield real cumulative output with each `.analysisResult`. `SelectiveAnalyzeUseCase` seeds its cumulative state with `loadExistingEvaluations()` from disk (prior run results) so the progressive output includes the full picture. All 488 tests pass.

## - [ ] Phase 3: Simplify PRModel to assign instead of compute

**Skills to read**: `/swift-app-architecture:swift-architecture`

Replace `mergeAnalysisResult()` with a simple assignment. In `runAnalyze()` and `runSelectiveAnalysis()`, the `.analysisResult` case now carries the cumulative output:

```swift
case .analysisResult(let result, let cumulativeOutput):
    inProgressAnalysis = cumulativeOutput
```

Delete `PRModel.mergeAnalysisResult()` entirely.

**Files to modify:**
- `Sources/apps/MacApp/Models/PRModel.swift` — Remove `mergeAnalysisResult()`, update both `runAnalyze()` and `runSelectiveAnalysis()` switch cases

## - [ ] Phase 4: Update CLI consumers for the new enum shape

The CLI's `AnalyzeCommand` currently has `case .analysisResult: break`. Update the pattern match to account for the new associated value, keeping the `break`.

**Files to modify:**
- `Sources/apps/MacCLI/Commands/AnalyzeCommand.swift` — Update pattern match
- Any other switch-case sites on `PhaseProgress.analysisResult` (search for `.analysisResult` across the codebase)

## - [ ] Phase 5: Validation

**Skills to read**: `/swift-testing`

- Run `swift build` — confirm no compile errors from the enum change
- Run `swift test` — all 431+ tests pass
- Verify no remaining references to `mergeAnalysisResult` in the codebase
- If existing tests cover `AnalyzeUseCase` streaming behavior, confirm they still pass with the new cumulative output in `.analysisResult` events
