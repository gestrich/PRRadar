# Checkout PR Branch Before Evaluation

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules — layer placement and dependency rules |
| `/swift-testing` | Test style guide |

## Background

The evaluation prompt tells the Claude agent "The PR branch is checked out locally at: {repo_path}" and gives it `Read`, `Grep`, `Glob` tools with `cwd` set to the repo path. However, nothing in the pipeline actually checks out the PR's commit before running evaluations. The agent reads whatever branch happens to be on disk (often `develop` or a detached HEAD from a previous run).

This causes the agent to find violations at wrong line numbers — lines that exist in the local checkout but not in the PR's version of the file. `DiffCommentMapper` then can't match those line numbers to any diff hunk, so they fall through to "file-level comments" in the UI.

**Example:** PR #18957 evaluated `FFDownloadTaskURLSession.m`. The diff adds new methods around lines 1481–1506, but the agent returned violations at lines 472, 481, 495 — pre-existing code in whatever was checked out locally. The new code (which should have been reviewed) was never seen by the agent.

**Goal:** Before evaluations begin, checkout the PR's head commit so the agent reads the correct code. Additionally, give the AI a structured way to report when it can't complete a review (e.g., file not found on disk) so it fails fast instead of silently returning erroneous data.

### Design Decision: `git checkout` vs `git worktree`

Two approaches:

1. **`git checkout`** — Simple. Check out the commit, run evaluations, restore the original branch afterward. Downside: mutates the working directory, won't work if the tree is dirty, and only one evaluation can run at a time per repo.

2. **`git worktree`** — Create a temporary worktree for the PR commit. The agent's `cwd` points to the worktree. Clean up when done. Downside: more complex, but supports concurrent evaluations and doesn't disturb the main working directory.

**Recommendation:** Use `git checkout` for now. It's simpler, matches the existing `GitOperationsService.checkoutCommit()` API, and the pipeline already runs one PR at a time. We can upgrade to worktrees later if concurrent evaluation is needed.

### Safety

- Check for a clean working directory before checkout (already have `checkWorkingDirectoryClean`)
- Save the current branch/HEAD before checkout
- Restore the original branch/HEAD after evaluations complete (even on error)

### Concurrent Analysis Guard

The Mac app has three entry points that trigger evaluations, all in `PRModel`:
- `runAnalyze()` — full PR analysis
- `runFilteredAnalysis(filter:)` — subset of tasks for one PR
- `runSingleAnalysis(task:)` — single task via `AnalyzeSingleTaskUseCase`

Today there is no guard preventing concurrent runs. With `git checkout`, two concurrent analyses (even on the same PR) would fight over the working directory — one checkout would clobber the other.

**Approach:** Add a per-repo checkout lock at the use case layer. Before checkout, acquire the lock. Release after restore. If the lock is already held (another analysis is running on the same repo), skip checkout and log a warning — same degraded behavior as the dirty-directory case.

Since `AnalyzeUseCase` and `AnalyzeSingleTaskUseCase` are structs (value types, no shared state), the lock needs to live somewhere shared. Options:
- A static `actor` keyed by repo path — simple, process-wide, no new dependencies
- Passed in from the App layer — more testable but heavier

**Recommendation:** Use a static actor (`RepoCheckoutLock`) in the Features layer. It's internal to the evaluation flow and doesn't need injection.

## Phases

## - [ ] Phase 1: Add restore-branch support to GitOperationsService

**Skills to read**: `/swift-app-architecture:swift-architecture`

Add a method to save and restore the current branch state:

- `getCurrentRef(repoPath:) -> String` — returns current branch name or detached HEAD sha
- `restoreRef(ref:repoPath:)` — checks out the saved ref

These belong in `GitOperationsService` (SDK layer) since they wrap single git commands.

Files to modify:
- `PRRadarLibrary/Sources/sdks/GitSDK/GitOperationsService.swift`
- `PRRadarLibrary/Sources/sdks/GitSDK/GitCLI.swift` (if new CLI commands needed)

## - [ ] Phase 2: Add RepoCheckoutLock actor

**Skills to read**: `/swift-app-architecture:swift-architecture`

Create a static actor that serializes checkout/restore per repo path. This prevents concurrent analyses from fighting over the working directory.

```swift
actor RepoCheckoutLock {
    private static let shared = RepoCheckoutLock()
    private var lockedRepos: Set<String> = []

    static func acquire(repoPath: String) async -> Bool {
        await shared._acquire(repoPath: repoPath)
    }

    static func release(repoPath: String) async {
        await shared._release(repoPath: repoPath)
    }

    private func _acquire(repoPath: String) -> Bool {
        lockedRepos.insert(repoPath).inserted
    }

    private func _release(repoPath: String) {
        lockedRepos.remove(repoPath)
    }
}
```

If `acquire` returns `false`, the caller skips checkout and logs a warning: "Another analysis is running — skipping branch checkout."

This lives in the Features layer alongside the use cases since it's internal coordination, not a reusable SDK concept.

Files to create:
- `PRRadarLibrary/Sources/features/PRReviewFeature/usecases/RepoCheckoutLock.swift`

## - [ ] Phase 3: Wire checkout into AnalyzeUseCase

**Skills to read**: `/swift-app-architecture:swift-architecture`

In `AnalyzeUseCase.runEvaluations()`:
1. Before evaluations start: acquire `RepoCheckoutLock`, save current ref, check working directory is clean, checkout the PR commit
2. After evaluations complete (in a `defer` or structured cleanup): restore the original ref, release the lock
3. Log the checkout/restore steps via `continuation.yield(.log(...))`

The `commitHash` is already resolved and available in both `executeFullRun` and `executeFiltered`. The `config.repoPath` is available on the use case.

`AnalyzeUseCase` will need access to `GitOperationsService`. Since `GitOperationsService` is in the SDK layer and `AnalyzeUseCase` is in the Features layer, this dependency is valid. Create the `GitOperationsService` instance in the use case (it just needs a `CLIClient`).

Also wire the same checkout into `AnalyzeSingleTaskUseCase.execute()` for consistency — it also passes `config.repoPath` to the agent.

If the lock cannot be acquired (another analysis holds it), skip checkout and log a warning. Same degraded behavior as the dirty-directory case.

Files to modify:
- `PRRadarLibrary/Sources/features/PRReviewFeature/usecases/AnalyzeUseCase.swift`
- `PRRadarLibrary/Sources/features/PRReviewFeature/usecases/AnalyzeSingleTaskUseCase.swift`

## - [ ] Phase 4: Handle dirty working directory gracefully

**Skills to read**: `/swift-app-architecture:swift-architecture`

If the working directory is dirty, the checkout will fail. Rather than aborting the entire analysis, we should:

1. Log a warning: "Working directory has uncommitted changes — skipping branch checkout. Agent will read whatever is currently on disk."
2. Continue with evaluations without checking out (degraded but functional — same behavior as today)

This keeps the pipeline robust for users who may have local modifications.

Files to modify:
- `PRRadarLibrary/Sources/features/PRReviewFeature/usecases/AnalyzeUseCase.swift`
- `PRRadarLibrary/Sources/features/PRReviewFeature/usecases/AnalyzeSingleTaskUseCase.swift`

## - [ ] Phase 5: Add AI error reporting to structured output

**Skills to read**: `/swift-app-architecture:swift-architecture`

Even with the checkout fix, there are scenarios where the AI reads the wrong code (dirty directory, lock contention, stale checkout). Rather than silently returning violations at wrong lines, give the AI a structured way to report that it cannot satisfy the request.

### Schema change

Add an optional `error` field to the evaluation output schema alongside `violations`:

```json
{
  "violations": [...],
  "error": "The file ffm/.../FFDownloadTaskURLSession.m does not contain the expected code at lines 1481-1506. The PR branch may not be checked out."
}
```

- `error` is a nullable string, default `null`
- When `error` is non-null, the result should be treated as a `RuleOutcome.error` regardless of what's in `violations`

### Prompt change

Add to the evaluation prompt instructions:

> If you cannot find the file specified in the focus area on disk, or the code at the specified lines does not match the diff content provided, set the `error` field to a brief description of the problem and return an empty violations array. Do not guess or evaluate code that doesn't match the provided diff.

### Parsing change

In `AnalysisService.analyzeTask()`, after parsing the structured output:
1. Check if `error` is a non-nil, non-empty string
2. If so, return `RuleOutcome.error(RuleError(..., errorMessage: error))` instead of a success with violations

This gives us a fail-fast signal that surfaces clearly in the UI ("ERROR: file not found") rather than producing misleading file-level comments.

Files to modify:
- `PRRadarLibrary/Sources/services/PRRadarCLIService/AnalysisService.swift` (schema, prompt, parsing)

## - [ ] Phase 6: Validation

**Skills to read**: `/swift-testing`

- Build passes (`swift build`)
- All existing tests pass (`swift test`)
- Manual verification: run `swift run PRRadarMacCLI analyze <pr> --config <config>` and confirm:
  - Log shows checkout/restore messages
  - The repo is on the correct commit during evaluation
  - The repo is restored to its original ref after evaluation completes
  - If working directory is dirty, a warning is logged and evaluations proceed
