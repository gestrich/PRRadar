# Auto-Fetch Diff on PR Selection

## Background

When a user selects a PR in the Mac app, `PRModel.loadDetail()` loads existing phase outputs from disk. To get fresh data from GitHub (diff, comments, metadata), the user must manually click the "Run" button on the Diff phase. This adds friction — the data should start downloading as soon as the PR is opened so the user sees up-to-date information immediately.

### Current problems

1. **Two separate code paths** — `loadDetail()` reads from disk (sync), `runDiff()` fetches from GitHub (async). These set the same model properties (`diff`, `phaseStates`) but through entirely different mechanisms.
2. **No staleness checking** — Every manual "Run" re-fetches everything from GitHub (5+ API calls: repo metadata, raw diff, PR metadata, comments, images) even if nothing has changed.
3. **`loadDetail()` is one-shot** — The `guard case .unloaded = detailState` guard means it can never run again after the first load.
4. **No loading indicator** — When the diff phase is fetching, the user only sees status in the pipeline strip; there's no prominent indication of ongoing work in the detail view.

### Design principles (from swift-architecture / swift-swiftui / PullRequests project)

- **Unified code path**: Initial load and refresh should follow the same method. When the model's observable properties update, views auto-render — no special reload hacks.
- **Staleness via `updatedAt`**: The PullRequests project (`/Users/bill/Developer/work/swift/PullRequests`) compares the stored `updatedAt` timestamp against GitHub's current value. Only if they differ does it re-fetch detail data. PRRadar's `GitHubPullRequest` already stores `updatedAt` in `gh-pr.json`, though `PRMetadata` doesn't expose it.
- **`@Observable` models in Apps layer only**: Models call use cases and update state; views observe and re-render automatically.
- **Use cases orchestrate**: Multi-step fetch logic lives in the Features layer, returning `AsyncThrowingStream`.

## Phases

## - [x] Phase 1: Expose `updatedAt` for staleness checking

**Goal:** Enable comparing stored PR data against GitHub's current state to avoid unnecessary re-downloads.

**Tasks:**

1. **`GitHubModels.swift`** — Confirm `GitHubPullRequest` already has `updatedAt: String`. It does (the full GitHub response is saved to `gh-pr.json`), but verify it's being populated.

2. **`PRMetadata.swift`** — Add `updatedAt: String` field to `PRMetadata`. Update `GitHubPullRequest.toPRMetadata()` to carry it through.

3. **`PRModel.swift`** — Surface `metadata.updatedAt` so the refresh method can compare against it.

4. **`GitHubService` / SDK layer** — Add a lightweight method to fetch *only* the current `updatedAt` from GitHub without fetching the full PR. Using `gh pr view <number> --json updatedAt` (a single, fast API call) would work. This belongs in the SDK layer since it's a single operation wrapper.

**Architecture note:** The staleness check is a single-operation SDK call (stateless, reusable). The comparison logic goes in the use case. The `updatedAt` field addition to `PRMetadata` is a Services-layer model change.

**Implementation notes:**
- `PRMetadata.updatedAt` added as `String?` (optional with `nil` default for backward compatibility with existing cached data and callers)
- `GitHubPullRequest.toPRMetadata()` and `PRDiscoveryService.discoverPRs()` both pass through `updatedAt`
- `PRModel.metadata.updatedAt` is already surfaced since `PRModel.metadata` is public
- Lightweight staleness check uses GraphQL (`OctokitClient.pullRequestUpdatedAt()`) — a single query returning only `updatedAt`, matching the existing `pullRequestBodyHTML()` pattern
- `GitHubService.getPRUpdatedAt()` wraps the SDK call for service-layer consumers

## - [x] Phase 2: Unify diff loading into a single refresh method

**Goal:** Replace the separate `loadDetail()` (disk read) + `runDiff()` (GitHub fetch) with a single `refreshDiff()` method that handles both cached display and fresh fetching. Initial load and refresh follow the same code path. When model properties update, views auto-update.

**Tasks:**

1. **`PRModel.swift`** — Add `refreshDiff(force: Bool = false)` method:

   ```
   refreshDiff(force:)
     1. Load cached data from disk via FetchDiffUseCase.parseOutput()
        → Set self.diff (views show cached data immediately)
        → Set phaseStates[.pullRequest] = .completed if cache exists, .idle if not
     2. Determine whether to fetch:
        - If force == true → always fetch
        - If no cached data (diff == nil) → always fetch
        - Otherwise → call lightweight updatedAt check from Phase 1
          - Compare stored updatedAt vs GitHub's current updatedAt
          - If equal → return (cached data is current)
     3. Fetch from GitHub:
        - Set phaseStates[.pullRequest] = .refreshing (new state, see below)
        - Stream FetchDiffUseCase.execute() → update diff, phaseStates
        - On completion: diff = newSnapshot, phaseStates = .completed
   ```

2. **`PRModel.PhaseState`** — Add a `.refreshing(logs: String)` case to distinguish between "first fetch" (`.running`) and "updating with cached data visible" (`.refreshing`). Views can show a subtle refresh indicator for `.refreshing` vs a full loading state for `.running`.

3. **`PRModel.swift`** — Extract the non-diff portions of `loadDetail()` into a separate method (e.g., `loadCachedNonDiffOutputs()`) that loads rules, evaluation, report, comments from disk. This still runs once on PR selection.

4. **`PRModel.runDiff()`** — Refactor to call `refreshDiff(force: true)` so the manual "Run" button and auto-refresh use the same code path.

5. **Views** — Since views already observe `PRModel.diff` and `PRModel.phaseStates`, they will automatically re-render when `refreshDiff()` updates these properties. No special reload logic needed — this is the MV pattern working as designed.

**Key invariant:** Whether it's a new PR (no cache), a returning PR (has cache, may be stale), or a manual refresh — all go through `refreshDiff()`. The model updates → views re-render.

**Implementation notes:**
- `loadDetail()` decomposed into three helpers: `loadPhaseStates()`, `loadCachedDiff()`, `loadCachedNonDiffOutputs()`
- `loadCachedDiff()` uses `FetchDiffUseCase.parseOutput()` directly (same as `LoadExistingOutputsUseCase` internally) and sets `phaseStates[.pullRequest] = .completed` when cache exists and state is `.idle`
- `refreshDiff(force:)` chooses `.refreshing` vs `.running` based on whether cached data is already displayed
- `isStale()` uses `GitHubServiceFactory.create()` + `GitHubService.getPRUpdatedAt()` from Phase 1 to compare stored `metadata.updatedAt` against GitHub's current value; falls back to "stale" on error or missing `updatedAt`
- `runDiff()` is now a one-liner delegating to `refreshDiff(force: true)`
- All views updated to handle `.refreshing` in switch statements: `PipelineStatusView`, `PhaseInputView`, `ReviewDetailView`
- `isAnyPhaseRunning`, `runningLogs(for:)`, and `appendLog(_:to:)` all handle `.refreshing` alongside `.running`

## - [ ] Phase 3: Loading indicator in the detail view

**Goal:** Show a visible loading indicator while the diff phase is fetching data.

**Tasks:**

1. **`ReviewDetailView.swift`** or **`PipelineStatusView.swift`** — When `phaseStates[.pullRequest]` is `.running` (no cached data) or `.refreshing` (has cached data, updating):
   - `.running`: Show a prominent loading indicator (e.g., `ProgressView` overlay or content unavailable view with spinner) since there's no cached data to display
   - `.refreshing`: Show a subtle indicator (e.g., small spinner in the toolbar or pipeline strip) since cached data is already visible

2. **`PhaseInputView.swift`** — The "Run" button already shows "Running..." when the phase is in progress. Update it to also recognize the `.refreshing` state, showing something like "Refreshing..." with the button disabled.

3. The `PipelineStatusView` phase node already shows a spinner for `.running` — extend it to also show an indicator for `.refreshing` (perhaps a different icon or animation to indicate "updating" vs "loading from scratch").

**Architecture note:** Per swift-swiftui, views read directly from the `@Observable` model. The `.refreshing` state on the model drives all loading indicators — no separate `@State` booleans needed in views.

## - [ ] Phase 4: Auto-trigger on PR selection with task cancellation

**Goal:** Wire `refreshDiff()` to PR selection and handle rapid switching.

**Tasks:**

1. **`ContentView.swift`** — Update the `.onChange(of: selectedPR)` handler:
   ```swift
   .onChange(of: selectedPR) { old, new in
       old?.cancelRefresh()
       if let pr = new {
           pr.loadCachedNonDiffOutputs()   // Load rules/eval/report from disk
           Task { await pr.refreshDiff() }  // Load cached diff + auto-fetch
           savedPRNumber = pr.metadata.number
       } else {
           savedPRNumber = 0
       }
   }
   ```

2. **`PRModel.swift`** — Add task cancellation support:
   - Store `refreshTask: Task<Void, Never>?` property
   - `refreshDiff()` cancels any existing `refreshTask` before starting
   - `cancelRefresh()` cancels the task and restores phase state (`.completed` if cached, `.idle` if not)

3. **`ContentView.submitNewReview()`** — Remove the explicit `await newPR.runDiff()` call. Setting `selectedPR = newPR` triggers `.onChange` which calls `refreshDiff()`. The flow becomes:
   - Create `PRModel` with fallback metadata → set as selected → auto-refresh triggers
   - No cached data exists → `refreshDiff()` fetches from GitHub (same code path)

4. **`FetchDiffUseCase.execute()`** — Add `try Task.checkCancellation()` at key points in the stream to support cooperative cancellation when the user switches PRs mid-fetch.

5. Verify the `.task` block that restores the saved PR on launch also triggers auto-refresh (it should, since it sets `selectedPR`).

**Architecture note:** SwiftUI's `.id(selectedPR.metadata.number)` on `ReviewDetailView` already resets the view on PR switch. Task cancellation in the model complements this by cleaning up background work.

## - [ ] Phase 5: Architecture Validation

Review all commits made during the preceding phases and validate they follow the project's architectural conventions.

**For Swift changes** (`pr-radar-mac/`):
- Re-read the `swift-architecture` and `swift-swiftui` skills from `https://github.com/gestrich/swift-app-architecture` (`plugin/skills/`)
- Compare the commits made against the conventions described in each skill
- If any code violates the conventions, make corrections

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. Fetch and read ALL skills from the swift-app-architecture repo
4. Evaluate the changes against each skill's conventions:
   - `@Observable` models only in the Apps layer
   - Use cases only in the Features layer (no business logic in models)
   - SDK methods are stateless, single-operation wrappers
   - No separate `@State` booleans for loading when the model already has the state
   - Task cancellation uses cooperative structured concurrency
5. Fix any violations found

## - [ ] Phase 6: Validation

**Automated testing:**
- Run `swift build` to ensure the project compiles
- Run `swift test` to ensure all existing tests pass

**Manual verification:**
- Launch the Mac app (`swift run MacApp`)
- Select a config, then select an existing PR that has cached data:
  - Cached data should appear immediately
  - If stale, a refresh indicator should appear while fetching
  - When fetch completes, the view updates in place (no manual reload needed)
- Select a PR with no cached data:
  - A loading indicator should appear
  - When fetch completes, data appears automatically
- Switch rapidly between PRs — verify previous fetch is cancelled (no stale data appearing)
- Use "New PR Review" — verify it fetches automatically via the same `refreshDiff()` path
- Click the "Run" button manually — verify it forces a re-fetch even if data is current
- Select a PR, wait for refresh to complete, re-select the same PR — verify it doesn't re-fetch (staleness check passes)

**Success criteria:**
- Single code path (`refreshDiff()`) for initial load, auto-refresh, and manual re-run
- Staleness check prevents unnecessary re-downloads
- Loading/refreshing indicators visible during fetch
- Views auto-update from model changes (no reload hacks)
- Rapid PR switching cancels stale fetches
- All tests pass
