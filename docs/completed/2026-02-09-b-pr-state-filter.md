# PR State Filter for Analyze All & PR List

## Background

The analyze-all feature currently supports a `--state` CLI flag that accepts a single value (`open`, `closed`, `merged`, `all`), but the MacApp UI does not expose state filtering at all. Bill wants the ability to filter by a single PR status — Open, Draft, Closed, Merged, or All — from both the CLI and the MacApp UI, using the same underlying service logic. No combo/multi-select needed; just pick one state or "all".

The existing time-based filter (1d/7d/14d/30d/60d/90d) already works in both CLI and UI. State filtering will be added alongside it so both filters compose together.

**Key constraint:** The GitHub REST API only accepts `state=open|closed|all`. "Merged" and "Draft" are not distinct API states — merged PRs have `state=closed` + `mergedAt != nil`, and drafts have `state=open` + `isDraft=true`. The service layer must map the selected state to the appropriate API scope and apply client-side post-filtering when needed.

**Current state of code:**
- `PRState` enum exists in `PRRadarModels/PRMetadata.swift` with `.open`, `.closed`, `.merged`, `.draft` and already has a `filterValue` property mapping to GitHub API values
- `GitHubService.listPullRequests(state:)` accepts a single `String` and handles the merged→closed mapping
- `AnalyzeAllUseCase.execute(state:)` passes a single `String?` through
- `AnalyzeAllCommand` has `--state` as a single `String?` option
- `AllPRsModel` has an unused `stateFilter: String` property
- `ContentView.filteredPRModels` filters only by date and pending comments — no state filter
- `ContentView.analyzeAllPopover` shows only the date range, not state selection

## Phases

## - [x] Phase 1: Service Layer — PRState-Based Filtering in GitHubService

Update `GitHubService` to accept `PRState?` instead of a raw `String`, leveraging the existing enum.

**PRRadarModels changes** (`PRMetadata.swift`):
- Add an `apiStateValue` computed property on `PRState` that returns the GitHub API string (`"open"`, `"closed"`, or `"all"`):
  - `.open` → `"open"`
  - `.draft` → `"open"` (drafts are open PRs with `isDraft=true`)
  - `.closed` → `"closed"`
  - `.merged` → `"closed"` (merged PRs are closed with `mergedAt != nil`)
- Add a static `PRState.fromCLIString(_ value: String) -> PRState?` to parse CLI input (`"open"`, `"draft"`, `"closed"`, `"merged"`) — returns nil for unrecognized values. `"all"` is handled separately (represented as `nil` at the type level).

**GitHubService changes** (`PRRadarCLIService/GitHubService.swift`):
- Update `listPullRequests` to accept `state: PRState?` instead of `state: String`
  - `nil` means "all" (fetch with `Openness.all`, no post-filtering)
  - Non-nil: use `state.apiStateValue` to determine API scope, then post-filter results using `enhancedState` to match the exact requested state (e.g., `.merged` fetches closed PRs then filters to only those with `mergedAt != nil`; `.draft` fetches open PRs then filters to `isDraft == true`)

**Architecture notes (per swift-architecture):** `PRState` is a shared data model in Services layer (`PRRadarModels`). The filtering logic in `GitHubService` also lives in Services. No new types or modules needed — just making the existing `PRState` enum the contract between layers.

**Completed.** Also updated `FetchPRListUseCase` and `AnalyzeAllUseCase` callers to use `PRState?` via `fromCLIString` to keep the build passing. These callers still accept `String?` parameters (formal signature change deferred to Phase 2).

## - [x] Phase 2: Feature Layer — Update Use Cases

Update `AnalyzeAllUseCase` and `FetchPRListUseCase` to use `PRState?` instead of `String?`.

**AnalyzeAllUseCase** (`PRReviewFeature/usecases/AnalyzeAllUseCase.swift`):
- Change `state: String? = nil` parameter to `state: PRState? = nil`
- `nil` means "all" (current default behavior preserved)
- Pass through to `GitHubService.listPullRequests(state:)`

**FetchPRListUseCase** (`PRReviewFeature/usecases/FetchPRListUseCase.swift`):
- Change `state: String? = nil` parameter to `state: PRState? = .open`
- Default is `.open` (preserving existing behavior where FetchPRListUseCase defaulted to open)
- Pass through to `GitHubService`

**Architecture notes (per swift-architecture):** Use cases in the Features layer orchestrate but don't contain business logic. The parameter type change keeps them as simple pass-throughs to Services.

**Completed.** Both use cases now accept `PRState?` directly. CLI callers (`AnalyzeAllCommand`, `RefreshCommand`) convert `String?` → `PRState?` via `fromCLIString` at the call site. `AllPRsModel` uses defaults (no explicit `state:` argument yet — wiring deferred to Phase 5).

## - [x] Phase 3: CLI — Update `--state` Option to Include "draft"

The CLI already accepts `--state` as a single value. Just add "draft" as a recognized option and wire to the typed enum.

**AnalyzeAllCommand** (`MacCLI/Commands/AnalyzeAllCommand.swift`):
- Update `--state` help text to: `"PR state filter (open, draft, closed, merged, all). Default: all"`
- Parse the string into `PRState?`:
  - `"all"` or omitted → `nil` (all states)
  - `"open"` → `.open`
  - `"draft"` → `.draft`
  - `"closed"` → `.closed`
  - `"merged"` → `.merged`
  - Unrecognized → validation error listing valid values
- Pass the parsed `PRState?` to `AnalyzeAllUseCase.execute(state:)`

**Completed.** Added shared `parseStateFilter(_:)` helper in `PRRadarMacCLI.swift` that both `AnalyzeAllCommand` and `RefreshCommand` use. The helper maps `"all"` or `nil` → `nil`, valid state strings → `PRState`, and unrecognized values → `ValidationError` with a message listing valid options. Updated help text on both commands to include "draft". `RefreshCommand` defaults to `.open` when no `--state` is provided (preserving existing behavior).

## - [x] Phase 4: MacApp UI — State Filter in Filter Bar

Add a single-select state picker in the PR list filter bar. Per the SwiftUI MV pattern, state lives in `@AppStorage` for persistence and the view reads it directly.

**ContentView changes** (`MacApp/UI/ContentView.swift`):

- Add `@AppStorage("selectedPRState")` property storing a string (default: `"ALL"`)
  - Compute a `PRState?` from this: `"ALL"` → `nil`, otherwise parse via `PRState(rawValue:)`
- Add a state filter `Menu` (or `Picker`) in `prListFilterBar`, positioned after the days-lookback menu:
  - Options: All, Open, Draft, Closed, Merged
  - Display the current selection as the menu label (e.g., "All" or "Open")
  - Style to match the existing days-lookback menu (compact, `.controlSize(.small)`)
- Update `filteredPRModels` to also filter by the selected state:
  - If `selectedPRState` is nil (All), no state filtering
  - Otherwise, parse each PR's `metadata.state` into `PRState` and check it matches

**Architecture notes (per swift-swiftui):** The state filter is view-level presentation state (which PRs to show), not business logic. `@AppStorage` is appropriate for persisting UI preferences.

**Completed.** Added `@AppStorage("selectedPRState")` with `"ALL"` default, a `Menu` using `PRState.allCases` with `displayName` labels positioned after the days-lookback menu, and state filtering in `filteredPRModels` that matches `PRState(rawValue: metadata.state.uppercased())` against the selection. Inherits `.controlSize(.small)` from the parent `HStack`.

## - [x] Phase 5: MacApp UI — Wire State Filter into Analyze All & Refresh

Connect the UI state filter to the analyze-all and refresh operations.

**Analyze All popover** (`ContentView.analyzeAllPopover`):
- Show the currently selected state filter as a label (e.g., "State: Open" or "State: All") so the user knows what will be analyzed
- Pass the selected `PRState?` to `AllPRsModel.analyzeAll()`

**AllPRsModel changes** (`MacApp/Models/AllPRsModel.swift`):
- Update `analyzeAll(since:)` to accept `state: PRState? = nil` parameter
- Remove the unused `stateFilter: String` property
- Pass `state` through to `AnalyzeAllUseCase.execute(state:)`
- Update `refresh(since:)` to also accept and pass through `state: PRState? = nil`

**ContentView refresh button:**
- Pass selected state filter to `allPRs?.refresh(since:state:)` so the refresh fetches PRs matching the current filter

**Architecture notes (per swift-architecture):** `AllPRsModel` is `@Observable` in the Apps layer — it invokes use cases and relays progress. The model doesn't interpret the state; it passes it through to the Feature layer use case.

**Completed.** Updated `AllPRsModel` with `state prState: PRState? = nil` parameters on both `analyzeAll(since:state:)` and `refresh(since:state:)`, using external/internal parameter naming to avoid shadowing the `self.state` property. Removed the unused `stateFilter: String` property. Updated `ContentView` to pass `selectedPRStateFilter` to both refresh and analyze-all calls. The analyze-all popover now displays the current state alongside the date range (e.g., "Last 7 days · State: Open").

## - [x] Phase 6: Architecture Validation

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
- `PRState?` flows down through layers correctly (Apps → Features → Services)

**Completed.** Reviewed all 13 skill files from `swift-app-architecture` (7 architecture + 6 SwiftUI) against 5 commits (Phases 1–5). All changes conform to conventions:
- Layer dependencies are strictly downward (SDKs ← Services ← Features ← Apps)
- `@Observable` only on `AllPRsModel` in Apps layer; use cases are `Sendable` structs in Features
- `PRState` shared type lives in `PRRadarModels` (Services layer)
- `PRState?` flows correctly: Apps (`ContentView`/CLI commands) → Features (`AnalyzeAllUseCase`/`FetchPRListUseCase`) → Services (`GitHubService`)
- Imports are alphabetically ordered in all changed files
- `parseStateFilter` CLI parsing helper correctly placed in Apps layer
- `@AppStorage` used for UI filter preference per MV pattern
- No violations found; no corrections needed. Build passes.

## - [x] Phase 7: Validation

**Automated testing:**
- `swift build` — verify the project compiles
- `swift test` — all existing tests pass (230+ tests)

**Unit test additions:**
- Test `PRState.apiStateValue` mapping
- Test `PRState.fromCLIString` parsing
- Test client-side post-filtering with `enhancedState` (e.g., `.draft` filter only returns drafts, `.merged` only returns merged)

**Manual verification (CLI):**
```bash
cd pr-radar-mac
swift run PRRadarMacCLI analyze-all --since 2025-01-01 --state open --config test-repo --limit 5
swift run PRRadarMacCLI analyze-all --since 2025-01-01 --state draft --config test-repo --limit 5
swift run PRRadarMacCLI analyze-all --since 2025-01-01 --state merged --config test-repo --limit 5
swift run PRRadarMacCLI analyze-all --since 2025-01-01 --state all --config test-repo --limit 5
```

**Manual verification (MacApp):**
- Launch MacApp, verify state filter picker appears in filter bar
- Select each state option and confirm the PR list filters accordingly
- Open analyze-all popover, confirm it shows current state selection
- Run analyze-all with a specific state selected

**Completed.** All validation passed:
- `swift build` succeeds
- `swift test` passes with 254 tests in 35 suites (23 new PRState tests added)
- Added `PRStateBehaviorTests.swift` with tests for: `apiStateValue` mapping (4 cases), `fromCLIString` parsing (valid, case-insensitive, unrecognized), `enhancedState` computation (open, draft, closed, merged, unknown, nil), post-filtering scenarios (draft-only, merged-only, open-excludes-drafts, closed-excludes-merged, nil-returns-all), `displayName`, and raw values
- CLI manual verification: `--state open` found 3 open PRs, `--state draft` found 0 (no drafts in test repo), `--state merged` found 0 (no merged in test repo), `--state all` found 3 PRs including closed PR #2
