## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules, placement guidance |
| `/swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns, @AppStorage, observable models |
| `/swift-testing` | Test style guide for validation phase |

## Background

PRRadar currently filters PRs by date (lookback period), state, and pending comments. Two additional filters are needed:

1. **Base branch filter** — Filter PRs by their target branch (e.g., only show PRs targeting `main`). Every repo has a primary branch, so a `defaultBaseBranch` should be a required config field. CLI commands and the Mac app should be able to override this default.

2. **GitHub user/author filter** — Filter PRs by who authored them. The CLI accepts a GitHub login handle (`--author octocat`). The Mac app shows a dropdown with cached author names (from `AuthorCacheService`) and persists the selection via `@AppStorage`.

Additionally, the base branch should appear in PR list displays and report output. Currently `PRMetadata` is missing `baseRefName` even though `GitHubPullRequest` has it — this gap must be fixed first.

### Current State

- `GitHubPullRequest.baseRefName: String?` exists (from GitHub API)
- `PRMetadata` has `headRefName` but **no `baseRefName`** — base branch is lost on caching
- `RepositoryConfiguration` has no `defaultBaseBranch` field
- `PRFilterOptions` (CLI) supports `--since`, `--lookback-hours`, `--updated-since`, `--updated-lookback-hours`, `--state`
- Mac app `ContentView` uses `@AppStorage` for `daysLookBack`, `selectedPRState`, `selectedRuleFilePaths`
- `AuthorCacheService` caches author `login -> name` mappings
- `AllPRsModel.filteredPRs()` filters by date, state, and pending comments
- `ReviewReport.toMarkdown()` shows PR number but no base branch

## - [x] Phase 1: Add `baseRefName` to `PRMetadata`

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Made `toPRMetadata()` throwing with per-field guard statements instead of silently falling back to empty strings. Consolidated duplicate `PRMetadata` construction in `PRDiscoveryService` to use `toPRMetadata()`. Added `PRMetadataConversionError` for descriptive error messages.

**Skills to read**: `swift-app-architecture:swift-architecture`

- Add `baseRefName: String` to `PRMetadata` in `PRMetadata.swift` (non-optional, no backward compat needed — missing data is an error)
- Update `GitHubPullRequest.toPRMetadata()` in `GitHubModels.swift` to populate `baseRefName` from `self.baseRefName`
- Update any existing `PRMetadata` initializers / test fixtures

## - [ ] Phase 2: Add `defaultBaseBranch` to config

**Skills to read**: `swift-app-architecture:swift-architecture`

- Add `defaultBaseBranch: String` to both `RepositoryConfiguration` and `RepositoryConfigurationJSON` (required, no backward compat needed)
- Update serialization/deserialization between the two types
- Manually update existing config files: `develop` for the iOS repo, `main` for PRRadar-DemoApp
- Update the config `list` CLI command output to show the new field if desired

## - [ ] Phase 3: Extend filter logic with base branch and author

**Skills to read**: `swift-app-architecture:swift-architecture`

- Add `baseBranch: String?` and `authorLogin: String?` parameters to the filter function in `AllPRsModel.filteredPRs()` (or wherever the shared filter logic lives)
- When `baseBranch` is non-nil and non-empty, filter PRs where `metadata.baseRefName == baseBranch`
- When `authorLogin` is non-nil and non-empty, filter PRs where `metadata.author.login == authorLogin`
- If the filter logic is duplicated between CLI and Mac app, consider whether it should be consolidated into the services layer

## - [ ] Phase 4: CLI `--base-branch` and `--author` options

**Skills to read**: `swift-app-architecture:swift-architecture`

- Add `--base-branch` option to `PRFilterOptions` in `PRFilterOptions.swift` (optional `String?`)
- Add `--author` option to `PRFilterOptions` (optional `String?`, expects GitHub login handle)
- Update `buildFilter()` to include the new fields
- When `--base-branch` is not specified, fall back to the config's `defaultBaseBranch`
- When `--base-branch` is explicitly set to `"all"` or empty, skip base branch filtering entirely
- Wire filters through to wherever PRs are fetched/filtered in CLI commands (e.g., `RunAllCommand`, `StatusCommand`, etc.)

## - [ ] Phase 5: Mac app base branch and author filters

**Skills to read**: `swift-app-architecture:swift-swiftui`

- Add `@AppStorage("baseBranchFilter") private var baseBranchFilter: String = ""` to `ContentView`
  - Empty string means "use config default"; a value overrides it
- Add `@AppStorage("authorFilter") private var authorFilter: String = ""` to `ContentView`
  - Empty string means "all authors"; stores GitHub login handle
- Reorganize the filter bar into 2 rows to accommodate the growing number of filter options
- Add a text field for base branch in the filter bar
- Add an author dropdown/picker populated from authors seen in the current PR list + `AuthorCacheService`
  - Display format: `"Full Name (login)"` or just `"login"` if no name cached
  - Include an "All" option that clears the filter
- Wire both filters to `filteredPRs()` in `AllPRsModel`

## - [ ] Phase 6: Display base branch in PR list and reports

**Skills to read**: `swift-app-architecture:swift-swiftui`

- Display base branch in the PR Summary view (not in `PRListRow`)
- Add `baseRefName` field to `ReviewReport` (populated from `PRMetadata`)
- Update `ReviewReport.toMarkdown()` to include base branch in the header, e.g., `"PR #123: feature/foo -> main"`
- Update any CLI status/report output that shows PR info to include base branch

## - [ ] Phase 7: Validation

**Skills to read**: `swift-testing`

- Add unit tests for `PRMetadata` decoding with and without `baseRefName` (backward compat)
- Add unit tests for filter logic with base branch and author parameters
- Run full test suite: `cd PRRadarLibrary && swift test`
- Build check: `swift build`
- Manual verification with test repo:
  - `swift run PRRadarMacCLI status 1 --config test-repo` — confirm base branch appears
  - `swift run PRRadarMacCLI status 1 --config test-repo --base-branch main` — confirm filter works
  - `swift run PRRadarMacCLI status 1 --config test-repo --author <some-login>` — confirm author filter works
  - Launch Mac app and verify filters persist across restarts
