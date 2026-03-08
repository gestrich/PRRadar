# Switch PR Date Filtering to "Updated Since" by Default

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns, observable model conventions |
| `pr-radar-debug` | Debugging context, CLI commands, config paths |
| `pr-radar-verify-work` | Verify changes via CLI against test repo |

## Background

Bill expects the "last N days" filter (in both CLI and Mac app) to show PRs **updated** within the time frame, not just **created**. PRs like #18920 — created 16 days ago but actively updated 2 days ago — should appear in a 7-day view.

Current issues:
1. **Mac app `buildFilter()`** (`ContentView.swift:709`) hardcodes `.createdSince(sinceDate)` — always filters by creation date
2. **Mac app `filteredPRs()`** (`AllPRsModel.swift:240-244`) always compares against `pr.metadata.createdAt` regardless of the date filter type — ignores `.updatedSince`
3. **CLI `--lookback-hours`** (`PRFilterOptions.swift:44-45`) uses `.createdSince` — should default to `.updatedSince` to match expectations
4. **CLI `refresh` output** returns all PRs from disk (via `PRDiscoveryService.discoverPRs()`) instead of only those matching the filter

`PRMetadata.updatedAt` already exists and is populated from `GitHubPullRequest.toPRMetadata()` (`GitHubModels.swift:231`).

## - [x] Phase 1: Change Mac App Default to `updatedSince`

**Principles applied**: Simple find-and-replace of `.createdSince` → `.updatedSince` in both code paths of `buildFilter()`

Update the Mac app to use `.updatedSince(sinceDate)` instead of `.createdSince(sinceDate)`.

**File:** `Sources/apps/MacApp/UI/ContentView.swift:709`
```swift
// Change from:
dateFilter: .createdSince(sinceDate),
// To:
dateFilter: .updatedSince(sinceDate),
```

## - [x] Phase 2: Fix `filteredPRs()` to Respect Date Filter Type

**Principles applied**: Switch on dateFilter case to select the correct date field; fall back to updatedAt/createdAt since PRMetadata lacks mergedAt/closedAt

The client-side `filteredPRs()` always compares against `createdAt`. It should use the date field matching the filter type.

**File:** `Sources/apps/MacApp/Models/AllPRsModel.swift:234-245`

Change the date extraction to check the filter case:
- `.createdSince` → use `pr.metadata.createdAt`
- `.updatedSince` → use `pr.metadata.updatedAt`
- Handle `updatedAt` being optional (fall through to include the PR if nil, like the current `createdAt.isEmpty` guard)

## - [ ] Phase 3: Fix CLI `refresh` to Filter Output

The `refresh` command shows all PRs ever saved to disk. After fetching, filter the discovered PRs before outputting.

**File:** `Sources/apps/MacCLI/Commands/RefreshCommand.swift:56-75`

After receiving `.completed(let prs)`, filter `prs` using the same date/state filter before printing. Reuse the filter logic or apply it inline.

## - [ ] Phase 4: Change CLI `--lookback-hours` Default to `updatedSince`

Align CLI default with Mac app. Change `--lookback-hours` to use `.updatedSince` instead of `.createdSince`. Keep `--since` as `createdSince` for explicit created-date filtering.

**File:** `Sources/apps/MacCLI/PRFilterOptions.swift:44-45`
```swift
// Change from:
dateFilter = .createdSince(Date.now.addingTimeInterval(-Double(hours) * 3600))
// To:
dateFilter = .updatedSince(Date.now.addingTimeInterval(-Double(hours) * 3600))
```

Also update the help text on line 10 from "PRs created in the last N hours" to "PRs updated in the last N hours".

## - [ ] Phase 5: Validation

- `swift build` — confirm compilation
- `swift test` — run all tests
- CLI: `swift run PRRadarMacCLI refresh --lookback-hours 168 --state open --config ios --json 2>&1 | grep 18920` — verify PR 18920 appears (updated 2 days ago)
- CLI: Verify PRs created >7 days ago but NOT recently updated do NOT appear
- Mac app: open and verify PR 18920 appears in 7-day view with default settings
