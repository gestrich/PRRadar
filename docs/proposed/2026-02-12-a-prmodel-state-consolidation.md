## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules (layer responsibilities, dependency rules, placement guidance) |
| `/swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns (enum-based state, model composition, state ownership) |
| `/swift-testing` | Test style guide and conventions |

## Background

`PRModel` has ~12 independent `private(set) var` properties for data loaded from disk, plus ~5 lifecycle/transient properties. Data loading is scattered across 6 private methods (`loadAnalysisSummary`, `loadCachedDiff`, `loadCachedNonDiffOutputs`, `loadPhaseStates`, `loadSavedTranscripts`, `refreshAvailableCommits`) that read files directly via `PhaseOutputParser`, `DataPathsService`, and `SyncPRUseCase` static methods. These methods are called from multiple places (`init`, `loadDetail`, `refreshDiff` completion, `refreshPRData`, `switchToCommit`) — each deciding independently which subset of data to reload.

This violates our architecture conventions:
- **Use cases return snapshots; models set state** — PRModel does its own file I/O instead of delegating to a use case
- **Enum-based state** — 12 independent properties instead of one state enum
- **One state transition, not scattered updates** — `currentCommitHash` is set in 3 places, each manually deciding what to reload

The recent commit-scoped directory refactor (`analysis/<commit>/` structure) exposed this fragility: setting `currentCommitHash` after sync didn't trigger reloading the analysis summary, causing a blank summary until manual refresh.

### What we want

One use case (`LoadPRDetailUseCase`) that reads ALL disk state for a PR and returns a single `PRDetail` snapshot. One method on `PRModel` (`reloadDetail()`) that calls this use case and applies the result. Every operation ends with `reloadDetail()`. The model stops doing file I/O.

### What stays in PRModel as transient state

Not everything moves into `PRDetail`. These are UI-only concerns that don't persist to disk and exist only during active operations:

- **Running phase logs** (`phaseStates` entries for running/refreshing phases)
- **Live AI transcripts** (`liveAccumulators`, `currentLivePhase`)
- **Comment posting state** (`commentPostingState`, `submittingCommentIds`, `submittedCommentIds`)
- **Selective analysis tracking** (`selectiveAnalysisInFlight`)
- **In-progress analysis merging** (`mergeAnalysisResult` during streaming)

---

## - [x] Phase 1: Create `PRDetail` and `LoadPRDetailUseCase`

**Skills to read**: `/swift-app-architecture:swift-architecture`

Create the snapshot type and use case that consolidates all disk reading.

**`PRDetail`** — new struct in `Sources/features/PRReviewFeature/models/PRDetail.swift`:

```swift
public struct PRDetail: Sendable {
    public let commitHash: String?
    public let availableCommits: [String]
    public let phaseStatuses: [PRRadarPhase: PhaseStatus]
    public let syncSnapshot: SyncSnapshot?
    public let preparation: PrepareOutput?
    public let analysis: AnalysisOutput?
    public let report: ReportPhaseOutput?
    public let postedComments: GitHubPullRequestComments?
    public let imageURLMap: [String: String]
    public let imageBaseDir: String?
    public let savedTranscripts: [PRRadarPhase: [ClaudeAgentTranscript]]
    public let analysisSummary: AnalysisSummary?
}
```

**`LoadPRDetailUseCase`** — expand the existing `LoadExistingOutputsUseCase` in `Sources/features/PRReviewFeature/usecases/LoadExistingOutputsUseCase.swift`:

- Rename `LoadExistingOutputsUseCase` → `LoadPRDetailUseCase`
- Change return type from `PipelineSnapshot` → `PRDetail`
- Move these operations from PRModel into the use case:
  - Commit hash resolution (already called here via `SyncPRUseCase.resolveCommitHash()`)
  - Available commits scanning (currently `refreshAvailableCommits()` in PRModel)
  - Phase status loading (currently `loadPhaseStates()` → `DataPathsService.allPhaseStatuses()`)
  - Posted comments loading (currently in `loadCachedNonDiffOutputs()` → `PhaseOutputParser.parsePhaseOutput(.metadata, "gh-comments.json")`)
  - Image URL map loading (currently in `loadCachedNonDiffOutputs()` → `PhaseOutputParser.parsePhaseOutput(.metadata, "image-url-map.json")`)
  - Image base dir computation (currently in `loadCachedNonDiffOutputs()` → `OutputFileReader.phaseDirectoryPath(.metadata)` + `/images`)
  - Saved transcript loading (currently `loadSavedTranscripts()` — reads `ai-transcript-*.json` from prepare and analyze phase dirs)
  - Analysis summary loading (currently `loadAnalysisSummary()` → `PhaseOutputParser.parsePhaseOutput(.analyze, "summary.json")`)
- Remove `PipelineSnapshot` (only used here — confirmed via grep)

The use case is synchronous (all file reads) — returns `PRDetail` directly, no streaming.

**Verify**: `swift build` succeeds. Existing callers of `LoadExistingOutputsUseCase` (only PRModel) will be updated in Phase 2.

### Completion Notes

- `PRDetail` created at `Sources/features/PRReviewFeature/models/PRDetail.swift`
- `LoadPRDetailUseCase` created at `Sources/features/PRReviewFeature/usecases/LoadPRDetailUseCase.swift`, replacing `LoadExistingOutputsUseCase.swift`
- `PipelineSnapshot` removed (was only defined and used in the old file)
- PRModel's `loadCachedNonDiffOutputs()` updated to call `LoadPRDetailUseCase` instead of `LoadExistingOutputsUseCase`
- Package paths: actual source is in `PRRadarLibrary/Sources/` (not `pr-radar-mac/Sources/` as originally noted in the spec)
- Build passes, all 412 tests pass

## - [x] Phase 2: Add `reloadDetail()` to PRModel and replace scattered loading

**Skills to read**: `/swift-app-architecture:swift-swiftui`

Add a single method that loads and applies all disk state, then replace all scattered loading with calls to it.

**Add to PRModel**:

```swift
private(set) var detail: PRDetail?

private func reloadDetail(commitHash: String? = nil) {
    let newDetail = LoadPRDetailUseCase(config: config)
        .execute(prNumber: prNumber, commitHash: commitHash)
    applyDetail(newDetail)
}

private func applyDetail(_ newDetail: PRDetail) {
    self.detail = newDetail

    // Derive at-rest phase states from disk (preserve running/refreshing phases)
    for (phase, status) in newDetail.phaseStatuses {
        if case .running = phaseStates[phase] { continue }
        if case .refreshing = phaseStates[phase] { continue }
        if status.isComplete {
            phaseStates[phase] = .completed(logs: "")
        } else if !status.exists {
            phaseStates[phase] = .idle
        } else {
            phaseStates[phase] = .failed(error: status.missingItems.first ?? "Incomplete", logs: "")
        }
    }

    // Update analysis state (for list row badge)
    if let summary = newDetail.analysisSummary {
        let postedCount = newDetail.postedComments?.reviewComments.count ?? 0
        analysisState = .loaded(
            violationCount: summary.violationsFound,
            evaluatedAt: summary.evaluatedAt,
            postedCommentCount: postedCount
        )
    } else if newDetail.syncSnapshot != nil {
        analysisState = .unavailable
    }
}
```

**Add forwarding computed properties** so views don't need to change:

```swift
var syncSnapshot: SyncSnapshot? { detail?.syncSnapshot }
var preparation: PrepareOutput? { detail?.preparation }
var report: ReportPhaseOutput? { detail?.report }
var postedComments: GitHubPullRequestComments? { detail?.postedComments }
var imageURLMap: [String: String] { detail?.imageURLMap ?? [:] }
var imageBaseDir: String? { detail?.imageBaseDir }
var savedTranscripts: [PRRadarPhase: [ClaudeAgentTranscript]] { detail?.savedTranscripts ?? [:] }
var currentCommitHash: String? { detail?.commitHash }
var availableCommits: [String] { detail?.availableCommits ?? [] }
```

Remove the corresponding `private(set) var` stored properties that are now forwarded.

**`analysis` and `comments` need transient overrides** — during streaming operations, the model writes to these before `reloadDetail()`:

```swift
private var inProgressAnalysis: AnalysisOutput?
private var pendingComments: CommentPhaseOutput?
var analysis: AnalysisOutput? { inProgressAnalysis ?? detail?.analysis }
var comments: CommentPhaseOutput? { pendingComments }
```

`mergeAnalysisResult()` writes to `inProgressAnalysis`. When analyze completes and `reloadDetail()` runs, clear `inProgressAnalysis = nil`. Same pattern for `pendingComments` — set by `runComments()`, not persisted to disk.

**Replace scattered loading calls**:

| Current code | Replace with |
|---|---|
| `init`: `Task { await loadAnalysisSummary() }` | `Task { reloadDetail() }` |
| `loadDetail()` body: calls `loadPhaseStates()`, `loadCachedDiff()`, `loadCachedNonDiffOutputs()`, `loadSavedTranscripts()` | `reloadDetail()` |
| `refreshDiff()` `.completed` handler: sets `syncSnapshot`, `currentCommitHash`, calls `refreshAvailableCommits()` | `reloadDetail(commitHash: snapshot.commitHash)` |
| `refreshPRData()`: calls `refreshDiff()` then `loadCachedNonDiffOutputs()` | Call `refreshDiff()` only — its completion handler now calls `reloadDetail()` |
| `switchToCommit()`: clears all properties, calls 4 load methods + `Task { await loadAnalysisSummary() }` | Clear transient state, call `reloadDetail(commitHash: commitHash)` |
| `runPrepare()` `.completed`: sets `preparation`, calls `loadSavedTranscripts()` | Call `reloadDetail()` |
| `runAnalyze()` `.completed`: sets `analysis`, calls `loadSavedTranscripts()` | Clear `inProgressAnalysis`, call `reloadDetail()` |
| `runReport()` `.completed`: sets `report` | Call `reloadDetail()` |
| `runAnalysis()`: calls `await loadAnalysisSummary()` at end | Remove — each phase completion already calls `reloadDetail()` |

**Remove from PRModel** (moved to use case in Phase 1):
- `loadAnalysisSummary()`
- `loadCachedDiff()`
- `loadCachedNonDiffOutputs()`
- `loadPhaseStates()`
- `loadSavedTranscripts()`
- `refreshAvailableCommits()`

**Remove `ReviewSnapshot`** (lines 7-13) — only used by `detailState` which is simplified below.

**Simplify `detailState`**: Replace the full enum with a simple guard in `loadDetail()`:

```swift
func loadDetail() {
    guard detail == nil else { return }
    reloadDetail()
    detailState = .loaded
}
```

Or remove `detailState` entirely and use `detail != nil` as the guard.

**Verify**: `swift build` succeeds. The blank summary bug is fixed — sync completion calls `reloadDetail()` which loads the summary with the correct commit hash.

### Completion Notes

- `detail: PRDetail?` stored property added; 10 forwarding computed properties replace the old `private(set) var` stored properties
- `reloadDetail(commitHash:)` and `applyDetail(_:)` consolidate all disk loading and state application
- `inProgressAnalysis` provides transient override during streaming — `analysis` computed property returns `inProgressAnalysis ?? detail?.analysis`
- `comments` remains a stored property (transient, set by `runComments`, not persisted to disk)
- `ReviewSnapshot` struct removed; `DetailState` enum removed; replaced with simple `detailLoaded: Bool` guard
- `loadAnalysisSummary()` removed — `applyDetail()` now derives `analysisState` from `PRDetail.analysisSummary`
- Six private loading methods removed: `loadAnalysisSummary()`, `loadCachedDiff()`, `loadCachedNonDiffOutputs()`, `loadPhaseStates()`, `loadSavedTranscripts()`, `refreshAvailableCommits()`
- Init now calls `reloadDetail()` (replacing `loadAnalysisSummary()`) so summary badge populates immediately
- `refreshPRData()` simplified to just `refreshDiff(force: true)` — its completion handler calls `reloadDetail()`
- `mergeAnalysisResult()` now writes to `inProgressAnalysis` instead of `analysis` directly
- `resetPhase()` calls `reloadDetail()` instead of nil-ing individual properties
- Build passes, all 412 tests pass

## - [x] Phase 3: Tests

**Skills to read**: `/swift-testing`

Add tests for `LoadPRDetailUseCase`:

- Returns correct `PRDetail` with all fields populated from a fully-analyzed PR output directory (set up temp directory with known files)
- Returns nil/empty fields gracefully for missing phases
- Resolves commit hash from metadata when not explicitly provided
- Loads transcripts from correct phase subdirectories
- Loads posted comments and image map from metadata/ directory
- Scans available commits from analysis/ directory
- Returns analysis summary from evaluate/summary.json

Run full test suite:
```bash
swift build && swift test
```

### Completion Notes

- Created `LoadPRDetailUseCaseTests.swift` with 19 tests covering all spec requirements
- Added `PRReviewFeature` to `PRRadarModelsTests` test target dependencies in `Package.swift` (use case lives in the feature layer)
- Tests use temp directories with real filesystem fixtures — no mocks needed since the use case is entirely file-driven
- Test categories: full PR (1), missing/partial phases (2), commit hash resolution (3), transcripts (2), posted comments (1), image map (2), available commits (3), analysis summary (2), phase statuses (1), syncSnapshot nil (1), sorted commits (1)
- All 431 tests pass (412 existing + 19 new)

## - [ ] Phase 4: Validation

End-to-end validation against the test repo:

```bash
swift run PRRadarMacCLI analyze 1 --config test-repo
swift run PRRadarMacCLI status 1 --config test-repo
```

Verify the original bug is fixed:
1. Run MacApp
2. Use "+" button to add a new PR by number
3. Summary badge should populate after sync completes (no manual refresh needed)
4. Select different commits via the commit picker — data reloads correctly
5. Run analysis — summary updates when analysis completes

Confirm no regressions:
- PR list loads with summary badges for all PRs
- Selecting a PR shows diff, report, transcripts
- Running individual phases updates status correctly
- Selective analysis works
- Comment posting works
- Refresh button works
