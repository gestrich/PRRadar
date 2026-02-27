## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-testing` | Test style guide and conventions |

## Background

When only some tasks are evaluated for a PR (e.g., running 1 rule on 1 file via selective analysis), the MacApp Diff view shows no comment annotations — even though `comment --dry-run` via the CLI finds the violation.

**Root cause:** The MacApp derives comments through `AnalyzeUseCase.parseOutput()` → `PRReviewResult.comments`, which is a separate code path from the CLI's `FetchReviewCommentsUseCase` → `ViolationService.loadViolations()`. The MacApp path requires `summary.json` (only written after full analysis), so it fails for partial evaluations.

**Duplication:** Both paths read the same evaluation files, match outcomes to tasks, and produce `[PRComment]` via `PRComment.from(result:task:)` — but through entirely different code. Only `ViolationService.reconcile()` is shared.

**Fix:** Both MacApp and CLI should call `FetchReviewCommentsUseCase` to load review comments. The MacApp stores the result and reloads from disk after each task completion during streaming.

## Phases

## - [x] Phase 1: Add `reviewComments` to `PRDetail`

**Completed**: Already implemented in prior commit (91a185d).

**File:** `PRRadarLibrary/Sources/features/PRReviewFeature/models/PRDetail.swift`

- Add `public let reviewComments: [ReviewComment]` property (after `analysisSummary`)
- Add corresponding `init` parameter

## - [x] Phase 2: Load review comments in `LoadPRDetailUseCase`

**File:** `PRRadarLibrary/Sources/features/PRReviewFeature/usecases/LoadPRDetailUseCase.swift`

After the `analysisSummary` block (~line 67), call:
```swift
let reviewComments = FetchReviewCommentsUseCase(config: config)
    .execute(prNumber: prNumber, commitHash: resolvedCommit)
```

Pass `reviewComments` to the `PRDetail` initializer. This is the same use case the CLI's `comment` and `report` commands use.

**No changes to `FetchReviewCommentsUseCase`** — it already works correctly.

## - [ ] Phase 3: Update `PRModel` to always load comments from disk

**File:** `PRRadarLibrary/Sources/apps/MacApp/Models/PRModel.swift`

Add a stored property and reload method:
```swift
private(set) var reviewComments: [ReviewComment] = []

var reconciledComments: [ReviewComment] { reviewComments }

private func reloadReviewComments() {
    reviewComments = FetchReviewCommentsUseCase(config: config)
        .execute(prNumber: prNumber, commitHash: currentCommitHash)
}
```

Update call sites:
- **`applyDetail()`**: call `reloadReviewComments()` (handles cold load and post-phase-completion)
- **`handleTaskEvent` `.completed` case**: call `reloadReviewComments()` — since `AnalyzeSingleTaskUseCase` writes each result to disk *before* firing `.completed`, the reload picks up the new comment immediately

This avoids calling `reloadDetail()` per task (which would clobber streaming accumulators in `evaluations`). Only the lightweight comment reload runs.

## - [ ] Phase 4: Update tests

**Skills to read:** `swift-testing`

**File:** `PRRadarLibrary/Tests/PRRadarModelsTests/LoadPRDetailUseCaseTests.swift`

Update existing tests:
- **`fullPR`**: Assert `detail.reviewComments.count == 1`, verify rule name and score
- **`emptyOutputDir`**: Assert `detail.reviewComments.isEmpty`
- **`partialPhases`**: Assert `detail.reviewComments.isEmpty` (only has diff data)

Add new test:
- **`reviewCommentsWithoutSummary`**: Write task + evaluation files but NO `summary.json`. Assert `detail.analysis == nil` but `detail.reviewComments.count == 1`. This directly tests the fix scenario — comments load via `FetchReviewCommentsUseCase` independently of `parseOutput`.

## - [ ] Phase 5: Validation

- `cd PRRadarLibrary && swift build` — compiles
- `swift test` — all tests pass
- `swift run PRRadarMacCLI report 18974 --config ios` — CLI still works
- `swift run PRRadarMacCLI comment 18974 --config ios --dry-run` — still shows 1 pending comment
- Launch MacApp → PR #18974 → Diff view → verify comment annotation appears
