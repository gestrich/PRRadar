# Refresh Button & AI Analyze Button

## Background

The app has two scopes for operations — individual PR and list-wide — and each scope needs two actions: **refresh** (data only) and **analyze** (AI pipeline). The buttons should use consistent icons and nomenclature across both scopes, and both scopes should funnel into the same central methods.

### Current State

**Detail toolbar (individual PR):**
- "Run All" text button → `selectedPR?.runAllPhases()` — [ContentView.swift:58-61](PRRadarLibrary/Sources/apps/MacApp/UI/ContentView.swift#L58-L61)
- No dedicated refresh button — diff auto-refreshes on PR selection via `refreshDiff()`

**List toolbar (all PRs):**
- `arrow.clockwise` button → `allPRs?.refresh()` — [ContentView.swift:221-232](PRRadarLibrary/Sources/apps/MacApp/UI/ContentView.swift#L221-L232). Only fetches the PR list metadata (`FetchPRListUseCase`), does NOT fetch per-PR data (diff, comments, images).
- `sparkles` button → `allPRs?.analyzeAll()` — [ContentView.swift:236-260](PRRadarLibrary/Sources/apps/MacApp/UI/ContentView.swift#L236-L260). Runs full AI pipeline on each PR. Shows `ProgressView` with "X/Y" count while running.

**Data fetching:**
- `PRModel.refreshDiff(force:)` → `FetchDiffUseCase` → `PRAcquisitionService.acquire()` — fetches PR metadata, diff, comments, repo info, and images; writes all artifacts to disk. Updates `self.diff` but does NOT reload `postedComments` or `imageURLMap` from the newly written files.
- `AllPRsModel.refresh()` → `FetchPRListUseCase` — fetches PR list from GitHub, writes `gh-pr.json` and `gh-repo.json` per PR, but does NOT run `FetchDiffUseCase` for each PR (no diff, comments, or images).

### Design Goals

1. **Consistent button pairs** — Both list and detail views use the same two icons:
   - `arrow.clockwise` = refresh data (no AI)
   - `sparkles` = run AI analysis
2. **Spinner feedback** — Each button shows a `ProgressView` spinner while its operation is running
3. **Central refresh method** — Both individual PR refresh and list refresh call the same `PRModel.refreshPRData()` under the hood
4. **List refresh fetches PR data** — After fetching the PR list, also runs `PRModel.refreshPRData()` on each PR so diff/comments/images are downloaded
5. **Central analyze method** — Both individual and list analyze use the same `PRModel.runAllPhases()` where possible (note: `AnalyzeAllUseCase` operates at the Feature layer and already handles batch orchestration — consistency here means the buttons look and behave the same way)

## Phases

## - [x] Phase 1: Add `refreshPRData()` to PRModel

Add a `refreshPRData()` method to `PRModel` that serves as the single central method for refreshing all PR data:

1. Calls `refreshDiff(force: true)` to fetch all PR data from GitHub (metadata, diff, comments, images)
2. After the diff refresh completes successfully, reloads `postedComments` and `imageURLMap` from the newly written disk files (reuse the loading logic from `loadCachedNonDiffOutputs()`)

This is the method both the individual refresh button and the list refresh will ultimately call.

**Files modified:**
- [PRModel.swift](PRRadarLibrary/Sources/apps/MacApp/Models/PRModel.swift) — Added `refreshPRData()` method

**Architecture notes:**
- Per swift-architecture, `@Observable` models live in the Apps layer and own state transitions — this method stays in `PRModel`
- The method orchestrates at the model level (calling existing use case + reloading cached data), not adding business logic

**Technical notes:**
- `refreshPRData()` calls `refreshDiff(force: true)` then checks `isPhaseCompleted(.pullRequest)` before reloading cached outputs
- Reloads `postedComments`, `imageURLMap`, and `imageBaseDir` via existing `loadCachedNonDiffOutputs()` — also reloads rules/evaluation/report which is harmless and keeps the method simple

## - [ ] Phase 2: Update list refresh to also fetch PR data

Update `AllPRsModel.refresh()` to call `PRModel.refreshPRData()` on each PR after the list fetch completes. This ensures the list refresh button downloads full PR data (diff, comments, images), not just the PR list metadata.

The flow becomes:
1. `FetchPRListUseCase` fetches the PR list from GitHub (existing behavior)
2. Create `PRModel` instances from discovered metadata (existing behavior)
3. **New:** Call `refreshPRData()` on each `PRModel`, yielding progress as each PR completes

Track and expose progress state so the `arrow.clockwise` button can show a spinner (and optionally an "X/Y" counter) while the batch refresh is running. Add a `refreshAllState` enum (similar to `analyzeAllState`) to `AllPRsModel` to track this.

**Files to modify:**
- [AllPRsModel.swift](PRRadarLibrary/Sources/apps/MacApp/Models/AllPRsModel.swift) — Update `refresh()` to call `refreshPRData()` per PR, add `refreshAllState` tracking

**Architecture notes:**
- `AllPRsModel` coordinates across `PRModel` instances at the Apps layer — this is the right place for batch orchestration over models
- Each `PRModel.refreshPRData()` internally uses `FetchDiffUseCase` from the Features layer — proper layer separation maintained

## - [ ] Phase 3: Update detail toolbar buttons

In `ContentView.swift`, replace the `.primaryAction` toolbar group:

1. **Add refresh button** (`arrow.clockwise`):
   - Action: `Task { await selectedPR?.refreshPRData() }`
   - When the PR's pull request phase is running/refreshing, show a `ProgressView` spinner instead of the icon
   - Disabled when: no PR selected, PR number is empty, or any phase is running
   - `.help("Refresh PR data")`

2. **Replace "Run All" with sparkles button** (`sparkles`):
   - Action: `Task { await selectedPR?.runAllPhases() }`
   - When any phase is running (`isAnyPhaseRunning`), show a `ProgressView` spinner instead of the icon
   - Disabled when: no PR selected, any phase is running, or PR number is empty
   - `.help("Analyze PR")`

Both buttons use the same icon and spinner pattern as their list counterparts.

**Files to modify:**
- [ContentView.swift](PRRadarLibrary/Sources/apps/MacApp/UI/ContentView.swift) — Update detail toolbar

## - [ ] Phase 4: Update list toolbar buttons for consistency

Ensure the list toolbar buttons match the same pattern:

1. **Refresh list button** (`arrow.clockwise`) — already exists at [ContentView.swift:221-232](PRRadarLibrary/Sources/apps/MacApp/UI/ContentView.swift#L221-L232):
   - Update the spinner to also reflect the new `refreshAllState` (shows spinner during both list fetch and per-PR data fetch phases)
   - Optionally show "X/Y" progress text (like the sparkles button does) if tracking per-PR progress

2. **Analyze all button** (`sparkles`) — already exists at [ContentView.swift:236-260](PRRadarLibrary/Sources/apps/MacApp/UI/ContentView.swift#L236-L260):
   - Already correct — uses `sparkles` icon with `ProgressView` + count text while running
   - No changes needed unless minor cleanup for consistency

**Files to modify:**
- [ContentView.swift](PRRadarLibrary/Sources/apps/MacApp/UI/ContentView.swift) — Update list refresh button spinner

## - [ ] Phase 5: Architecture Validation

Review all commits made during the preceding phases and validate they follow the project's architectural conventions:

**For Swift changes** (`pr-radar-mac/`):
- Re-read the `swift-architecture` and `swift-swiftui` skills from `https://github.com/gestrich/swift-app-architecture` (`plugin/skills/`)
- Compare the commits made against the conventions described in each skill
- If any code violates the conventions, make corrections

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. Fetch and read ALL skills from the swift-app-architecture repo
4. Evaluate the changes against each skill's conventions
5. Fix any violations found

## - [ ] Phase 6: Validation

**Build and test:**
```bash
cd pr-radar-mac
swift build
swift test
```

**Manual verification:**
- Launch the Mac app and select a PR
- **Detail toolbar:** Verify `arrow.clockwise` (refresh) and `sparkles` (analyze) buttons replace the old "Run All" text button
- Click detail refresh → PR data updates (diff, comments, images) without analysis; spinner shows while running
- Click detail sparkles → full pipeline runs; spinner shows while running
- **List toolbar:** Verify `arrow.clockwise` now fetches PR data for each PR (not just the list); spinner shows during the full operation
- **List toolbar:** Verify `sparkles` still runs analyze-all with progress counter
- Verify buttons are disabled appropriately during operations
- Verify `@Observable` updates propagate: list rows update badges/counts after refresh, detail views update after data loads
