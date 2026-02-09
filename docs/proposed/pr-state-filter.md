# PR State Filter for Analyze All & PR List

## Background

The analyze-all feature currently supports a `--state` CLI flag that accepts a single value (`open`, `closed`, `merged`, `all`), but the MacApp UI does not expose state filtering at all. Bill wants the ability to filter by PR status — Open, Draft, Closed, Merged, or any combination — from both the CLI and the MacApp UI, using the same underlying service logic.

The existing time-based filter (1d/7d/14d/30d/60d/90d) already works in both CLI and UI. State filtering will be added alongside it so both filters compose together.

**Key constraint:** The GitHub REST API only accepts `state=open|closed|all`. "Merged" and "Draft" are not distinct API states — merged PRs have `state=closed` + `mergedAt != nil`, and drafts have `state=open` + `isDraft=true`. The service layer must map multi-state selections to the minimum API scope and apply client-side post-filtering.

**Current state of code:**
- `PRState` enum exists in `PRRadarModels/PRMetadata.swift` with `.open`, `.closed`, `.merged`, `.draft`
- `GitHubService.listPullRequests(state:)` accepts a single `String` and handles the merged→closed mapping
- `AnalyzeAllUseCase.execute(state:)` passes a single `String?` through
- `AnalyzeAllCommand` has `--state` as a single `String?` option
- `AllPRsModel` has an unused `stateFilter: String` property
- `ContentView.filteredPRModels` filters only by date and pending comments — no state filter
- `ContentView.analyzeAllPopover` shows only the date range, not state selection

## Phases

## - [ ] Phase 1: Service Layer — Multi-State Filter Type and GitHubService Update

Add a shared filter type that both CLI and UI consume, and update `GitHubService` to accept it.

**PRRadarModels changes:**
- Add a `PRStateFilter` struct (or typealias for `Set<PRState>`) in `PRMetadata.swift` (alongside the existing `PRState` enum). It should:
  - Be `Sendable`, `Codable`, `Hashable`
  - Have a static `.all` convenience for the full set
  - Have a computed property to determine the minimum GitHub API `Openness` scope needed:
    - Subset of `{.open, .draft}` → `"open"`
    - Subset of `{.closed, .merged}` → `"closed"`
    - Mix → `"all"`
  - Have a `func matches(_ pr: GitHubPullRequest) -> Bool` method for post-fetch client-side filtering using `enhancedState`

**GitHubService changes** (`PRRadarCLIService/GitHubService.swift`):
- Add a new overload or update `listPullRequests` to accept `Set<PRState>` instead of (or in addition to) the `state: String` parameter
- Internally: determine the API scope from the set, fetch PRs, then filter results by exact state match using `GitHubPullRequest.enhancedState`
- Keep backward compatibility: if a single string is passed, convert to the corresponding `Set<PRState>`

**Architecture notes (per swift-architecture):** `PRStateFilter`/`Set<PRState>` is a shared data model → belongs in Services layer (`PRRadarModels`). The `GitHubService` filtering logic also lives in Services. No new modules needed.

## - [ ] Phase 2: Feature Layer — Update Use Cases

Update `AnalyzeAllUseCase` and `FetchPRListUseCase` to accept the multi-state filter.

**AnalyzeAllUseCase** (`PRReviewFeature/usecases/AnalyzeAllUseCase.swift`):
- Change `state: String? = nil` parameter to `states: Set<PRState>? = nil`
- Default to `PRState.allCases` (equivalent to current `"all"` behavior) when nil
- Pass the set through to `GitHubService`

**FetchPRListUseCase** (`PRReviewFeature/usecases/FetchPRListUseCase.swift`):
- Change `state: String? = nil` parameter to `states: Set<PRState>? = nil`
- Default to `[.open]` when nil (matches current behavior where refresh fetches open PRs)
- Pass through to `GitHubService`

**Architecture notes (per swift-architecture):** Use cases orchestrate in the Features layer but don't contain business logic — they delegate state mapping to the Services layer. The parameter type change keeps use cases as simple pass-throughs.

## - [ ] Phase 3: CLI — Multi-State `--state` Option

Update the CLI to accept comma-separated state values.

**AnalyzeAllCommand** (`MacCLI/Commands/AnalyzeAllCommand.swift`):
- Change `--state` help text to: `"PR state filter: open,draft,closed,merged,all (comma-separated, default: all)"`
- Parse the comma-separated string into `Set<PRState>`:
  - `--state open,draft` → `[.open, .draft]`
  - `--state all` → all 4 cases
  - `--state merged` → `[.merged]`
  - No `--state` flag → default to all (current behavior)
- Pass the parsed set to `AnalyzeAllUseCase.execute(states:)`
- Validate: if any value isn't recognized, print an error listing valid values

## - [ ] Phase 4: MacApp UI — State Filter in Filter Bar

Add a multi-select state filter in the PR list filter bar. Per the SwiftUI MV pattern, state lives in an `@Observable` model (or `@AppStorage` for persistence) and the view reads it directly.

**ContentView changes** (`MacApp/UI/ContentView.swift`):

- Add `@AppStorage("selectedPRStates")` property storing a comma-separated string of selected states (default: `"OPEN,DRAFT,CLOSED,MERGED"` i.e. all)
  - Compute a `Set<PRState>` from this stored string
- Add a state filter `Menu` in `prListFilterBar`, positioned after the days-lookback menu:
  - Each `PRState` case gets a toggleable item (checkmark when selected)
  - An "All" option that selects/deselects everything
  - Display as a compact label showing count or abbreviated selection (e.g., "Open, Draft" or "All States")
- Update `filteredPRModels` to also filter by the selected states:
  - Parse each PR's `metadata.state` into `PRState` and check membership in the selected set

**Architecture notes (per swift-swiftui):** The state filter is view-level presentation state (which PRs to show), not business logic. `@AppStorage` is appropriate for persisting UI preferences. The filter bar is a view concern — no model changes needed for list filtering.

## - [ ] Phase 5: MacApp UI — Wire State Filter into Analyze All & Refresh

Connect the UI state filter to the analyze-all and refresh operations so they use the same filter.

**Analyze All popover** (`ContentView.analyzeAllPopover`):
- Show the currently selected state filter as a label (e.g., "States: Open, Draft") so the user knows what will be analyzed
- Pass the selected `Set<PRState>` to `AllPRsModel.analyzeAll()`

**AllPRsModel changes** (`MacApp/Models/AllPRsModel.swift`):
- Update `analyzeAll(since:)` to accept `states: Set<PRState>` parameter
- Remove the unused `stateFilter: String` property
- Pass `states` through to `AnalyzeAllUseCase.execute(states:)`
- Update `refresh(since:)` to also accept and pass through `states: Set<PRState>`

**ContentView refresh button:**
- Pass selected state filter to `allPRs?.refresh(since:states:)` so the refresh fetches PRs matching the current filter

**Architecture notes (per swift-architecture):** `AllPRsModel` is `@Observable` in the Apps layer — it should invoke use cases and relay progress. The model doesn't interpret the states; it passes them through to the Feature layer use case.

## - [ ] Phase 6: Architecture Validation

Review all commits made during the preceding phases and validate they follow the project's architectural conventions.

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

**Key conventions to verify:**
- `@Observable` models only in Apps layer
- Use cases as `Sendable` structs in Features layer
- Shared types in Services layer (`PRRadarModels`)
- No upward dependencies between layers
- `Set<PRState>` flows down through layers correctly (Apps → Features → Services)

## - [ ] Phase 7: Validation

**Automated testing:**
- `swift build` — verify the project compiles
- `swift test` — all existing tests pass (230+ tests)

**Unit test additions:**
- Test `PRState` set → GitHub API scope mapping (e.g., `[.open, .draft]` → `"open"`, `[.open, .merged]` → `"all"`)
- Test client-side filtering with `enhancedState` matching
- Test CLI comma-separated state parsing

**Manual verification (CLI):**
```bash
cd pr-radar-mac
swift run PRRadarMacCLI analyze-all --since 2025-01-01 --state open,draft --config test-repo --limit 5
swift run PRRadarMacCLI analyze-all --since 2025-01-01 --state merged --config test-repo --limit 5
swift run PRRadarMacCLI analyze-all --since 2025-01-01 --state all --config test-repo --limit 5
```

**Manual verification (MacApp):**
- Launch MacApp, verify state filter menu appears in filter bar
- Toggle individual states and confirm the PR list filters accordingly
- Open analyze-all popover, confirm it shows current state selection
- Run analyze-all with a subset of states selected
