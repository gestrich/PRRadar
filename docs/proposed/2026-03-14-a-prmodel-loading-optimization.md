## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules, placement guidance |
| `/swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns, observable model conventions |
| `/swift-testing` | Test style guide |
| `/pr-radar-verify-work` | Verify changes by running CLI against test repo |

## Background

Two related issues in `PRModel` loading:

1. **Stale data flash on PR search** — When searching for a PR by number, `PRModel.init` immediately loads cached data from disk (including old `gh-comments.json` with bot comments like "CI Insights"). This renders on the Summary tab for ~1 second before `refreshDiff` completes and overwrites with fresh data. Additionally, `submitNewReview` and `onChange(of: selectedPR)` both call `refreshDiff`, with the second call cancelling the first forced one.

2. **Heavy launch I/O** — `PRModel.init` fires `Task { await reloadDetailAsync() }` for every PR in the list. `LoadPRDetailUseCase` performs 12+ file reads per PR (diff, preparation, analysis, report, comments, evaluations, phase statuses, image maps, etc.). With 200+ PRs, that's 2400+ concurrent file I/O operations on launch — all to populate two list badge values: `analysisState` and `pendingCommentCount`.

These share a root cause: `PRModel.init` unconditionally fires a full detail load as an implicit async side effect. The fix addresses both by making loading explicit and introducing a lightweight path for list items.

### Key files

- `PRRadarLibrary/Sources/apps/MacApp/Models/PRModel.swift` — model init, `reloadDetailAsync`, `applyDetail`
- `PRRadarLibrary/Sources/apps/MacApp/Models/AllPRsModel.swift` — creates PRModels for list (3 call sites)
- `PRRadarLibrary/Sources/apps/MacApp/UI/ContentView.swift` — `submitNewReview`, `onChange(of: selectedPR)`
- `PRRadarLibrary/Sources/features/PRReviewFeature/usecases/LoadPRDetailUseCase.swift` — full detail loader (12+ file reads)

### PRModel creation sites

| Site | File | Purpose | Needs full detail? |
|------|------|---------|-------------------|
| `load()` line 91 | AllPRsModel | Initial list from disk | No — only needs summary |
| `refresh()` line 141 | AllPRsModel | New PR from GitHub refresh | No — only needs summary |
| `reloadFromDisk()` line 256 | AllPRsModel | Reload after analysis | No — only needs summary |
| `submitNewReview()` line 719 | ContentView | User searched by number | No — wants fresh data from GitHub |

## Phases

## - [x] Phase 1: Remove implicit async load from PRModel.init

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: Followed model-scalability guidance — PRModel stays lean at init, heavyweight data loads only when explicitly requested

Remove `Task { await reloadDetailAsync() }` from `PRModel.init`. No PRModel should do I/O as a side effect of initialization.

Add a new method for lightweight list data:

```swift
func loadSummary() {
    // Reads only: analysisSummary (for analysisState badge)
    //             and reviewComments (for pendingCommentCount badge)
    // Skips: diff, preparation, analysis, report, comments, images, saved outputs
}
```

This method should read only the two pieces of data the list row needs:
- `summary.json` → `analysisState` (violation count, evaluated date, posted comment count)
- Review comments → `pendingCommentCount`

That's 2-3 file reads instead of 12+.

Keep `loadDetailAsync()` / `reloadDetailAsync()` unchanged — they still load everything, but only when explicitly called.

## - [x] Phase 2: Extract common PRModel creation helper in AllPRsModel

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Centralized PRModel creation so loadSummary() is always called for list badge data

All three PRModel creation sites in `AllPRsModel` do the same thing: map metadata to PRModels and need `loadSummary()` called on each. Extract a single helper:

```swift
private func makePRModels(from metadata: [PRMetadata]) -> [PRModel] {
    metadata.map { meta in
        let model = PRModel(metadata: meta, config: config)
        model.loadSummary()
        return model
    }
}
```

Replace the three inline `.map` calls:
- `load()` line 91 → `let prModels = makePRModels(from: metadata)`
- `refresh()` line 141 → `return makePRModels(from: [meta]).first!` (for newly created PRModels only; reused ones keep their existing state)
- `reloadFromDisk()` line 256 → `let prModels = makePRModels(from: metadata)`

`loadSummary()` is synchronous and fast (2-3 file reads), so it runs inline with no `Task` or `await`.

## - [x] Phase 3: Fix submitNewReview flow — eliminate race and stale flash

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: Moved sync logic into AllPRsModel (syncAndDiscover) following MV pattern — views stay thin, models own business operations. Errors surface to user via alert instead of being swallowed.

Remove the fallback PRModel hack from `submitNewReview`. Instead:

1. Show a loading state in the detail column (no `selectedPR` set yet)
2. Sync the PR data from GitHub using `SyncPRUseCase` directly (not through a PRModel)
3. Call `model.load()` to re-discover PRs from disk — #17976 now exists as a real PRModel with fresh data
4. Find the real PRModel and set `selectedPR` — this triggers `onChange`, which loads detail and shows it

This eliminates the fallback PRModel entirely. The user sees a loading indicator in the detail column while the fetch happens, then the real PR appears fully loaded.

Also fix `onChange(of: selectedPR)` to not call `refreshDiff()` if a sync just completed (the data is already fresh). Check `refreshTask != nil` or whether the diff phase is already `.completed`. This prevents the duplicate refresh where onChange would re-fetch data that was just synced.

## - [x] Phase 4: Load full detail on PR selection with background refresh

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: Kept refreshDiff on MainActor (PRModel is @Observable) but made it non-blocking by wrapping in unstructured Task — detail view renders immediately with cached data while GitHub sync runs concurrently

When a PR is selected from the list (via `onChange(of: selectedPR)`), the flow should be:

1. `loadDetailAsync()` — loads full cached detail from disk (fast), sets `detailLoaded = true`. The detail view renders immediately with cached data.
2. `refreshDiff()` — fires in the background (non-blocking). Syncs with GitHub, then calls `reloadDetail()` on completion to update the view with fresh data. The existing "Updating..." banner (`.refreshing` state) already shows during this.

The key difference from current behavior: step 1 completes and renders the UI **without waiting** for step 2. Currently both run sequentially in the same `Task` (`await loadDetailAsync()` then `await refreshDiff()`), so the detail view doesn't appear until both finish. With this change, the user sees cached data instantly and it silently updates in the background.

The `refreshDiff` background task should be tracked so it can be cancelled if the user selects a different PR (the existing `refreshTask` / `cancelRefresh()` pattern handles this).

## - [ ] Phase 5: Validation

**Skills to read**: `swift-testing`, `pr-radar-verify-work`

### Automated
- Run `swift build` — verify all targets compile
- Run `swift test` — verify existing tests pass
- Check that no existing tests depend on `PRModel.init` firing `reloadDetailAsync` implicitly

### Manual verification
- Launch MacApp, verify list loads with correct badges (violation counts, checkmarks)
- Search for a PR by number — verify no stale data flash, loading indicator shows until fresh data arrives
- Select a PR from the list — verify detail loads correctly with cached data, then refreshes
- Check logs (`swift run PRRadarMacCLI logs --last-run`) — verify no duplicate `refreshDiff` calls for a single PR selection

### Performance check
- Compare launch behavior before/after: list should populate faster since each PR only reads 2-3 files instead of 12+
- Add temporary timing logs if needed to quantify the improvement
