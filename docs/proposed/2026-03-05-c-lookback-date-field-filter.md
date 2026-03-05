## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture rules, placement guidance |
| `swift-testing` | Test style guide and conventions |
| `pr-radar-verify-work` | Verify changes against the test repo |

## Background

Currently, `--lookback-hours` and `--since` filter PRs by **creation date only**. The `GitHubService.listPullRequests()` sorts by `.created` and compares `createdAt >= since`. This misses PRs that were created before the lookback window but received new commits or activity within it.

For daily reviews, you typically want **both**: new PRs (created recently) and active PRs (updated recently). Rather than bolting on a second flag, we'll introduce a first-class `PRDateFilter` enum with the cutoff date as an associated value. The service layer derives sort order, field comparison, and log messages all from the enum case.

There are two orthogonal filtering axes:
- **Date filter**: which date field to apply the lookback to — `created`, `updated`, `merged`, `closed`
- **Current state** (`--state`): what the PR is *right now* — `open`, `draft`, `merged`, `closed`

The CLI uses self-describing flags per date field rather than a generic `--filter` + `--lookback-hours` pair. This makes the relationship between flag and field explicit:
- `--since` / `--lookback-hours` — filter by **created** date (existing, backward compatible)
- `--updated-since` / `--updated-lookback-hours` — filter by **updated** date (new)
- Future: `--merged-since`, `--closed-since` when needed (model supports all four, CLI exposes only what's needed now)

Example: `--updated-lookback-hours 24 --state open` means "PRs that are currently open AND were updated in the last 24 hours." This prevents returning a PR that was updated recently but has since been merged.

### Design

Introduce a composable `PRFilter` struct that wraps sub-filters. This is the single filter type passed through all layers — extensible for future criteria (author, label, base branch, etc.) without changing method signatures.

```swift
public struct PRFilter: Sendable {
    public var dateFilter: PRDateFilter?
    public var state: PRState?
    // extensible: author, label, baseBranch, etc.
}

public enum PRDateFilter: Sendable {
    case createdSince(Date)
    case updatedSince(Date)
    case mergedSince(Date)
    case closedSince(Date)
}
```

`PRDateFilter` bundles "which field" and "since when" into a single value — you can't accidentally pass a date field without a date or vice versa. The service layer derives the sort order, API state to fetch, and comparison field from the enum case.

`PRFilter` composes the date filter with state (and future filters). Each layer receives one `PRFilter` instead of a growing parameter list.

`PRDateFilter` case mapping:
| Case | API sort | API state | PR field compared | Early stop on |
|------|----------|-----------|-------------------|---------------|
| `createdSince` | `.created` | from `filter.state` | `createdAt` | `createdAt` |
| `updatedSince` | `.updated` | from `filter.state` | `updatedAt` | `updatedAt` |
| `mergedSince` | `.updated` | `.closed` | `mergedAt` | `updatedAt` |
| `closedSince` | `.updated` | `.closed` | `closedAt` | `updatedAt` |

For `mergedSince`/`closedSince`, the API must fetch closed PRs regardless of `filter.state`, since merged/closed PRs have API state "closed". The `filter.state` post-filter still applies afterward.

**Pagination optimization for all cases**: `mergedSince`/`closedSince` sort by `.updated` and early-stop when `updatedAt < cutoff`. This is sound because merging/closing a PR always sets `updatedAt >= mergedAt/closedAt` — so any PR merged/closed after the cutoff must also have been updated after the cutoff. The early stop may fetch some extra PRs (updated but not merged/closed in the window) but will never miss results.

This flows through all layers:
- **CLI**: Builds a `PRFilter` from self-describing flags (`--since`/`--lookback-hours`, `--updated-since`/`--updated-lookback-hours`, `--state`). One object constructed at the edge
- **Use case**: Accepts `PRFilter` (replaces separate `since: String` + `state: PRState?` parameters)
- **Service**: `GitHubService.listPullRequests()` accepts `PRFilter`, extracts sort order, API state, date comparison, and state post-filter from it
- **daily-review.sh**: Uses `--updated-lookback-hours 24 --state open` to catch both new and active open PRs

### Key decisions

1. **Composable `PRFilter` struct** — wraps `PRDateFilter` + `PRState` + future criteria. One parameter through all layers. Adding a new filter dimension (author, label) means adding a field to `PRFilter`, not changing every method signature.
2. **Associated value on `PRDateFilter`** — the date and field travel together as one type. Impossible to misconfigure.
3. **Two orthogonal axes** — `dateFilter` controls the date dimension, `state` controls the current-state dimension. They compose freely; no validation needed — an empty intersection is a valid (empty) result.
4. **All cases have pagination optimization** — `createdSince` sorts by `.created`, the other three sort by `.updated`. Early stop uses the sort field. For `mergedSince`/`closedSince`, this is sound because merging/closing always updates `updatedAt`, so `updatedAt >= mergedAt/closedAt`.
5. **Self-describing CLI flags** — `--updated-since` / `--updated-lookback-hours` instead of a generic `--filter` + `--lookback-hours` pair. The flag name tells you which date field it applies to. No ambiguity.
6. **Existing flags unchanged** — `--since` / `--lookback-hours` continue to filter by created date. No breaking changes.
7. **Ship only `updated`** — the model supports all four date fields, but the CLI only exposes `--updated-since` / `--updated-lookback-hours` for now. Add `--merged-since`, `--closed-since` later when needed.
8. **Script uses `updated` + `open`** — `updatedSince` is a superset of `createdSince` for open PRs, so one run covers both new and active PRs while excluding merged/closed.
9. **Replaces `since: String` and `state: PRState?`** — the use case no longer accepts loose parameters. The CLI constructs a `PRFilter` from parsed arguments, pushing all parsing to the edge.

## Phases

## - [x] Phase 1: Add `PRFilter` / `PRDateFilter` models and update `GitHubService`

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Used model-layer-safe booleans (`sortsByCreated`, `requiresClosedAPIState`) instead of importing OctoKit types into PRRadarModels, respecting layer dependency rules. Added `closedAt` to `GitHubPullRequest` for the `closedSince` filter case.

**Skills to read**: `swift-app-architecture:swift-architecture`

Add the filter types to `PRRadarModels` and thread through the service layer:

1. **Add types** to `PRRadarModels/PRMetadata.swift`:
   ```swift
   public struct PRFilter: Sendable {
       public var dateFilter: PRDateFilter?
       public var state: PRState?

       public init(dateFilter: PRDateFilter? = nil, state: PRState? = nil) {
           self.dateFilter = dateFilter
           self.state = state
       }
   }

   public enum PRDateFilter: Sendable {
       case createdSince(Date)
       case updatedSince(Date)
       case mergedSince(Date)
       case closedSince(Date)
   }
   ```
   Add computed helpers on `PRDateFilter`:
   - `date` — extracts the associated `Date`
   - `fieldLabel` — returns `"created"`, `"updated"`, `"merged"`, or `"closed"` for log messages
   - `sortType` — returns the OctoKit `SortType` (`.created` for `createdSince`, `.updated` for the other three)
   - `apiState` — returns the API state override if needed (`nil` for created/updated, `.closed` for merged/closed)
   - `dateExtractor` — `(GitHubPullRequest) -> String?` that picks the right date field (`createdAt`, `updatedAt`, `mergedAt`, `closedAt`)
   - `earlyStopExtractor` — `(GitHubPullRequest) -> String?` that picks the sort-aligned field for pagination early stop (`createdAt` for `createdSince`, `updatedAt` for the other three)

2. **Update `GitHubService.listPullRequests()`** in `PRRadarCLIService/GitHubService.swift`:
   - Replace `(limit:state:since:)` with `(limit:filter:)` accepting a `PRFilter`
   - Extract `dateFilter` and `state` from the filter struct
   - Use `dateFilter.sortType` for the OctoKit sort parameter
   - Use `dateFilter.earlyStopExtractor` to decide when to stop paginating
   - Use `dateFilter.dateExtractor` to filter individual PRs
   - If `dateFilter.apiState` is non-nil, override the API state parameter
   - Apply `filter.state` as a post-filter on `enhancedState`

3. **`OctokitClient.listPullRequests()`** — no changes needed, already accepts `sort: SortType` with `.created` and `.updated` cases

## - [x] Phase 2: Thread `PRFilter` through use cases

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Pushed all date/state parsing to the CLI edge (Apps layer). Use cases accept a single `PRFilter` — no loose parameters. Log messages derive labels from `filter.dateFilter?.fieldLabel`.

**Skills to read**: `swift-app-architecture:swift-architecture`

Update the feature layer to accept the unified filter:

1. **`RunAllUseCase.execute()`** — replace `since: String` + `state: PRState?` with `filter: PRFilter`. Remove the internal `ISO8601DateFormatter` date-string parsing. Pass to `gitHub.listPullRequests(limit:filter:)`
2. **`FetchPRListUseCase.execute()`** — replace `since: Date?` + `state: PRState?` with `filter: PRFilter`. Pass to `gitHub.listPullRequests(limit:filter:)`
3. Update log messages to use `filter.dateFilter?.fieldLabel` (e.g., "Fetching PRs updated since ..." vs "Fetching PRs created since ...")

## - [x] Phase 3: Build `PRFilter` in CLI commands

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: All date/state parsing pushed to the CLI edge via `PRFilterOptions` ParsableArguments. Commands use `@OptionGroup` for shared filter options — one place to maintain. Mutual exclusivity validation prevents misconfiguration.

**Skills to read**: `swift-app-architecture:swift-architecture`

The CLI constructs a `PRFilter` from parsed arguments — all parsing stays at the edge. Use swift-argument-parser's `ParsableArguments` to define the filter options once and include them in any command that needs them.

1. **Create `PRFilterOptions`** (new file in `MacCLI/`, e.g. `PRFilterOptions.swift`):
   ```swift
   struct PRFilterOptions: ParsableArguments {
       @Option(name: .long, help: "Date in YYYY-MM-DD format (filter by created date)")
       var since: String?

       @Option(name: .long, help: "PRs created in the last N hours")
       var lookbackHours: Int?

       @Option(name: .long, help: "Date in YYYY-MM-DD format (filter by updated date)")
       var updatedSince: String?

       @Option(name: .long, help: "PRs updated in the last N hours")
       var updatedLookbackHours: Int?

       @Option(name: .long, help: "PR state filter: open, draft, closed, merged, all")
       var state: String?

       func buildFilter() throws -> PRFilter {
           let dateFilter: PRDateFilter?
           if let updatedSince {
               dateFilter = .updatedSince(parseDate(updatedSince))
           } else if let hours = updatedLookbackHours {
               dateFilter = .updatedSince(Date.now.addingTimeInterval(-Double(hours) * 3600))
           } else if let since {
               dateFilter = .createdSince(parseDate(since))
           } else if let hours = lookbackHours {
               dateFilter = .createdSince(Date.now.addingTimeInterval(-Double(hours) * 3600))
           } else {
               dateFilter = nil
           }
           let stateFilter: PRState? = try parseStateFilter(state)
           return PRFilter(dateFilter: dateFilter, state: stateFilter)
       }
   }
   ```
   - Validates mutually exclusive date options (not both `--since` and `--updated-since`)
   - `buildFilter()` produces a `PRFilter` — shared logic, one place to maintain

2. **Update `RunAllCommand`**:
   - Replace individual `since`, `lookbackHours`, `state` properties with `@OptionGroup var filterOptions: PRFilterOptions`
   - In `run()`: `let prFilter = try filterOptions.buildFilter()`
   - Pass `prFilter` to `RunAllUseCase.execute(filter:)`
   - For `RunAllCommand` specifically, validate that a date filter was provided (it's required here but optional in other commands)

3. **Update `RefreshCommand`**:
   - Replace `state` property with `@OptionGroup var filterOptions: PRFilterOptions`
   - In `run()`: `let prFilter = try filterOptions.buildFilter()`

4. Update `CommandConfiguration.abstract` on both commands to reflect the new capability

## - [x] Phase 4: Update `daily-review.sh`

**Principles applied**: Switched to `--updated-lookback-hours 24` so one run covers both new and active open PRs. Fixed `set -e`/`EXIT_CODE=$?` bug by wrapping CLI call with `set +e`/`set -e`.

Switch to `--updated-lookback-hours` — `updatedSince` is a superset of `createdSince` (any newly created PR is also recently updated), so a single run covers both new and active PRs:

```bash
"$CLI" run-all \
  --config "ios" \
  --updated-lookback-hours 24 \
  --mode regex \
  --state open
```

Also fix the `set -e` / `EXIT_CODE=$?` bug (line 81 is unreachable on failure).

## - [x] Phase 5: Tests and validation

**Skills used**: `swift-testing`, `pr-radar-verify-work`
**Principles applied**: Tests follow Arrange-Act-Assert pattern with `@Test` and `#expect`. PRDateFilter tests verify all computed properties for all four cases. PRFilter tests verify composition and filtering behavior on PR arrays. Integration verified with both `--lookback-hours` and `--updated-lookback-hours` against test repo.

**Skills to read**: `swift-testing`, `pr-radar-verify-work`

1. **Unit tests** for `PRDateFilter`:
   - Verify `date`, `fieldLabel`, `sortType`, `apiState` computed properties for all four cases
   - Verify `dateExtractor` and `earlyStopExtractor` return the correct fields for each case

2. **Unit tests** for `PRFilter` composition:
   - Verify `PRFilter(dateFilter: .updatedSince(...), state: .open)` correctly composes both axes
   - Verify nil fields behave as "no filter" for that axis

3. **Unit tests** for `GitHubService.listPullRequests()` filter behavior:
   - `.createdSince` filters on `createdAt`, sorts by `.created`, early stops on `createdAt`
   - `.updatedSince` filters on `updatedAt`, sorts by `.updated`, early stops on `updatedAt`
   - `.mergedSince` filters on `mergedAt`, fetches closed PRs, sorts by `.updated`, early stops on `updatedAt`
   - `.closedSince` filters on `closedAt`, fetches closed PRs, sorts by `.updated`, early stops on `updatedAt`
   - Verify `state` post-filter composes correctly with date filter (e.g., `.updatedSince` + state `.open` excludes merged PRs)

4. **Integration verification** using the test repo:
   ```bash
   swift run PRRadarMacCLI run-all --config test-repo --lookback-hours 720 --state open
   swift run PRRadarMacCLI run-all --config test-repo --updated-lookback-hours 720 --state open
   ```
   Verify the two runs return different (or overlapping) PR sets based on the date filter used.
