# Incremental Evaluation Caching

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture rules, layer responsibilities, dependency rules |
| `swift-testing` | Test style guide and conventions |

## Background

The analysis pipeline currently re-evaluates every task from scratch on every run, even when the underlying code hasn't changed. For a PR with 20+ tasks, each Claude Sonnet evaluation costs ~$0.10-0.50, so repeated runs on the same PR waste significant AI budget.

This plan adds file-level caching by storing the **git blob hash** of each file in its task data. On re-run, if a file's blob hash hasn't changed, its tasks are skipped and prior evaluation results are reused.

### Current State

- `EvaluateUseCase` evaluates ALL tasks from phase-4 — no check for existing results
- `EvaluationService.runBatchEvaluation()` iterates every task without checking for prior `data-{taskId}.json` files
- `EvaluationTaskOutput` has no record of the file's git state at evaluation time
- Task IDs are deterministic (`{ruleName}_{focusId}`) but don't account for file changes

### Design Decisions

**Git blob hash per file**: Each file in git has a blob hash (`git rev-parse HEAD:<filepath>`) that changes only when the file's content changes. By storing this hash in the task data, we can detect whether a file has changed between runs without computing content hashes ourselves.

**No separate cache file**: The cache state lives directly in the existing phase-4 task JSON files (`data-{taskId}.json`). No new `analysis-cache.json` or cache service needed — just compare the `gitBlobHash` field in old vs. new tasks.

**No backward compatibility**: The `gitBlobHash` field is required (`String`, not optional). Existing analysis data files will be deleted so the pipeline starts fresh.

**Architecture placement** (per swift-app-architecture conventions):
- `gitBlobHash` field addition → `PRRadarModels` (Services layer — shared data model)
- Blob hash lookup (calls `git rev-parse`) → `PRRadarMacSDK` or `PRRadarCLIService` (existing git integration)
- Skip logic → `EvaluateUseCase` (Features layer — orchestration)

## Phases

- [x] Phase 1: Add Git Blob Hash to Task Model

**Skills to read**: `swift-app-architecture:swift-architecture`, `swift-testing`

Add a required `gitBlobHash` field to `EvaluationTaskOutput` in `PRRadarModels`.

**Changes to `Sources/services/PRRadarModels/TaskOutput.swift`**:

```swift
public struct EvaluationTaskOutput: Codable, Sendable, Equatable {
    public let taskId: String
    public let rule: TaskRule
    public let focusArea: FocusArea
    public let gitBlobHash: String  // blob hash of focusArea.filePath at time of task creation

    // Update init, CodingKeys, and from() factory accordingly
}
```

**Changes to `TaskCreatorService`**: Look up the git blob hash for `focusArea.filePath` (via `git rev-parse HEAD:<filepath>`) and pass it when creating each task.

**Delete existing analysis data**: Remove all cached analysis output directories so stale data without the new field doesn't cause decoding failures. This is a one-time cleanup — the pipeline regenerates everything on the next run.

**Tests**: Verify that tasks created with a blob hash round-trip through JSON correctly.

**Completed**: Added `gitBlobHash: String` to `EvaluationTaskOutput` with `git_blob_hash` JSON key. Added `getBlobHash()` to `GitOperationsService` using `git rev-parse`. Updated `TaskCreatorService` to accept `GitOperationsService` dependency and look up blob hashes per file (with in-memory cache to avoid redundant git calls for the same file). Updated `FetchRulesUseCase` call site to pass `repoPath`. All 331 tests pass.

- [x] Phase 2: Skip Unchanged Tasks in Evaluate Phase

**Skills to read**: `swift-app-architecture:swift-architecture`

Modify `EvaluateUseCase` (Features layer) to skip tasks whose file hasn't changed since the last evaluation.

**Logic**:
1. Load new tasks from phase-4 (these have the current `gitBlobHash`)
2. For each task, check if a prior evaluation result exists in phase-5 (`data-{taskId}.json`)
3. If a prior result exists, load the corresponding old task from phase-4 and compare `gitBlobHash` values
4. If the blob hashes match → skip evaluation, reuse the existing phase-5 result
5. If they differ (or no prior result exists) → evaluate normally
6. Log how many tasks were skipped vs. evaluated (e.g., "Skipping 12 cached evaluations, evaluating 3 new tasks")

**No changes to `EvaluationService`** itself — it remains a pure "evaluate these tasks" service. The filtering happens in the use case.

**Tests**: Unit tests verifying:
- All tasks evaluated when no prior results exist (cold start)
- Tasks skipped when blob hash matches prior run
- Tasks re-evaluated when blob hash differs (file changed)
- Summary correctly includes both cached and fresh results

**Completed**: Created `EvaluationCacheService` (Services layer) with `partitionTasks()` and `writeTaskSnapshots()` static methods. The service stores task snapshots (`task-{taskId}.json`) alongside evaluation results in phase-5, enabling blob hash comparison on subsequent runs without depending on phase-4 data (which gets regenerated each run). `EvaluateUseCase` delegates to this service to partition tasks into cached vs. fresh, only invoking `EvaluationService` for tasks needing evaluation. 7 new tests in `EvaluationCacheServiceTests` cover cold start, cache hit, cache miss, mixed scenarios, missing snapshots, write round-trip, and full round-trip. All 338 tests pass.

- [ ] Phase 3: CLI Output and Progress Reporting

Update progress reporting so the CLI/UI shows which tasks are cached vs. fresh.

**Changes**:
- `EvaluateUseCase` reports cached vs. fresh counts before starting evaluation
- Cached tasks show a different indicator in progress output (e.g., "(cached)" suffix)
- End-of-run summary shows: "Tasks evaluated: X new, Y cached, Z total"

**Tests**: Verify output messages contain correct counts.

- [ ] Phase 4: Architecture Validation

**Skills to read**: `swift-app-architecture:swift-architecture`

Review all changes and validate they follow the project's architectural conventions.

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. Validate:
   - Model changes are in Services layer (`PRRadarModels`)
   - Git blob hash lookup is in SDK or Services layer
   - Skip logic is in Features layer (use cases)
   - Dependencies flow downward only
4. Fix any violations

- [ ] Phase 5: Validation

**Skills to read**: `swift-testing`

**Automated testing**:
```bash
cd pr-radar-mac
swift build
swift test
```

All existing tests must pass. New tests from Phases 1-3 must pass.

**Manual verification against test repo**:
```bash
cd pr-radar-mac

# First run — should evaluate everything
swift run PRRadarMacCLI analyze 1 --config test-repo

# Second run — should skip all evaluations (blob hashes unchanged)
swift run PRRadarMacCLI analyze 1 --config test-repo
# Expected: "Skipping N cached evaluations, evaluating 0 new tasks"
```

**End-to-end cache invalidation test** (in `PRRadar-TestRepo`):

1. In the test repo's open PR branch, add a rule violation to a file. Commit and push.
2. Run `swift run PRRadarMacCLI analyze 1 --config test-repo` — should evaluate fresh and find the violation.
3. Run `analyze` again immediately — should skip all evaluations (cached). Report should still show the violation.
4. Back in the test repo, edit the same file: add a **second** violation *above* the first one. Commit and push.
5. Run `analyze` again — blob hash changed, so it should re-evaluate (not use cache).
6. Verify the report shows **both** violations, and that the original violation's line number has shifted down to reflect its new position in the file.

**Success criteria**:
- Second run on unchanged PR skips all AI evaluations
- Output clearly indicates cached vs. fresh evaluations
- Report output is identical between cached and fresh runs
- After adding a second violation above the first, re-evaluation finds both and the original violation's line number is updated
