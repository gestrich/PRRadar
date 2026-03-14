## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules, placement guidance |

## Background

When filtering for open PRs authored by `user123` targeting `develop` in the Mac app (the configured repo, 90d lookback), the PR list shows "No Reviews Found" despite a specific PR being open and targeting `develop` on GitHub.

The Mac app's `AllPRsModel.refresh()` calls `FetchPRListUseCase.execute(filter:)` to fetch PRs from GitHub, then uses `AllPRsModel.filteredPRs()` for local display filtering. The CLI's `refresh` command also uses `FetchPRListUseCase`, making it suitable for reproducing the issue.

### Key code paths

- **Mac app filter construction**: `ContentView.buildFilter()` → `PRFilter(dateFilter: .createdSince(sinceDate), state: selectedPRStateFilter, baseBranch: baseBranchFilter, authorLogin: authorFilter)`
- **Mac app refresh**: `AllPRsModel.refresh(filter:)` → `FetchPRListUseCase.execute(filter:)` (filter is NOT passed through `resolvedFilter` before the API call)
- **Mac app display**: `filteredPRModels(filter:)` → `config.resolvedFilter(filter)` → `filteredPRs(models, filter:)` (resolvedFilter IS applied here)
- **CLI refresh**: `RefreshCommand.run()` → `prRadarConfig.resolvedFilter(filterOptions.buildFilter())` → `FetchPRListUseCase.execute(filter:)` (resolvedFilter IS applied before the API call)

### Notable difference

The CLI applies `resolvedFilter` **before** passing to `FetchPRListUseCase`, while the Mac app does **not**. This means the CLI and Mac app may produce different results for the same logical filter. The `resolvedFilter` logic:
- If `baseBranch` is nil, defaults to `config.defaultBaseBranch`
- If `baseBranch` is "all" or empty, clears it to nil
- If `state` is nil, defaults to `.open`

In the Mac app, `buildFilter()` always sets `baseBranch` explicitly (from the text field), so `resolvedFilter` wouldn't change it during refresh. But it IS applied during display filtering via `filteredPRModels`.

### Potential causes to investigate

1. **GitHub API returning empty**: The `base` parameter to the GitHub PR list API may not match (case sensitivity, branch name mismatch)
2. **Date filter too aggressive**: `createdSince` with 90 days lookback might exclude PRs created earlier but still open
3. **Author login mismatch**: `user123` vs actual GitHub login on the fetched PRs
4. **State filtering**: `enhancedState` mapping may not match expectations
5. **Disk discovery issue**: PRs fetched but not properly written/discovered from disk

## - [x] Phase 1: Reproduce from CLI

**Skills to read**: none

Reproduce the exact Mac app scenario using the CLI `refresh` command with equivalent parameters:

```bash
cd PRRadarLibrary
swift run PRRadarMacCLI refresh --config my-repo --lookback-hours 2160 --base-branch develop --author user123 --json
```

Compare results to running without filters:
```bash
swift run PRRadarMacCLI refresh --config my-repo --lookback-hours 2160 --base-branch develop --json
```

And without author filter:
```bash
swift run PRRadarMacCLI refresh --config my-repo --lookback-hours 2160 --json
```

Also enhance the CLI `refresh --json` output to include `baseRefName` and `author` so we can see what the API actually returns.

**After this phase**: Document findings in this plan — which commands return results and which don't, what the actual PR data looks like.

### Phase 1 Findings

**CLI results**: All three commands return the PR with correct data:
- `baseBranch=develop`, `state=OPEN`, `author=user123`, `createdAt=2026-02-18T20:35:18Z`
- The `--author user123` filtered command returned 303 PRs including 16 by user123
- The no-author command returned 371 PRs

**On-disk data** (`~/Desktop/code-reviews/{pr}/metadata/gh-pr.json`): Correct — `baseRefName: "develop"`, `state: "open"`, author login `user123`. Repo slug `example-org/example-ios` matches the configured repo.

**Conclusion**: The bug is NOT reproducible from the CLI. The API returns correct data, disk storage is correct, and `toPRMetadata()` conversion maps fields correctly. The issue is Mac app specific.

**Hypothesis for Phase 2**: The Mac app's `AllPRsModel.init` calls `refresh()` with an empty `PRFilter()` (no state, no baseBranch, no dateFilter). This fetches up to 300 PRs sorted by `updated` across ALL states with no base branch filter. Later, when the user clicks refresh with filters, `refresh(filter: buildFilter())` fetches filtered PRs and writes them to disk, then `PRDiscoveryService.discoverPRs` discovers ALL PRs from disk. The display filter `filteredPRModels(filter:)` applies `config.resolvedFilter(filter)` before filtering. All code paths look correct on paper — diagnostic logging is needed to identify where PRs are being dropped in the Mac app flow.

**JSON enhancement**: Added `baseBranch` field to `refresh --json` output.

## - [ ] Phase 2: Add diagnostic logging to filter pipeline

**Skills to read**: `/swift-app-architecture:swift-architecture`

Based on Phase 1 findings, add temporary or permanent debug output at key points:

- In `GitHubService.listPullRequests()`: log the filter parameters being sent to the API (`base`, `state`, `sort`)
- In `GitHubService.listPullRequests()`: log the count of PRs returned from each API page and after each filtering step (date filter, state filter, author filter)
- In `AllPRsModel.filteredPRs()`: log the count before and after each filter step

This will reveal exactly where PRs are being dropped.

**After this phase**: Document which filter step is eliminating the expected PRs.

## - [ ] Phase 3: Fix the root cause

**Skills to read**: `/swift-app-architecture:swift-architecture`

Based on findings from Phases 1-2, implement the fix. Possible fixes depending on root cause:

- If date filter is the issue: switch Mac app from `createdSince` to `updatedSince` for refresh, or adjust the early-stop logic
- If author login mismatch: normalize login comparison (case-insensitive)
- If GitHub API `base` param issue: adjust how baseBranch is passed to the API
- If `resolvedFilter` inconsistency: align Mac app and CLI to both resolve before the API call

**After this phase**: Document the root cause and fix applied.

## - [ ] Phase 4: Validation

**Skills to read**: `/swift-testing`

- Run `swift test` to ensure no regressions
- Run `swift build` to ensure clean build
- CLI verification: re-run the commands from Phase 1 and confirm expected PRs appear
- Mac app verification: confirm the PR appears with the same filter settings
- Add unit test for the specific scenario that was failing (if a code fix was needed)

**After this phase**: Document validation results.
