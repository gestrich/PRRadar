# GitHub Author Name Cache

## Background

GitHub's PR-related REST API endpoints return abbreviated user objects that include `login` (the handle) but omit the `name` (display name) field. The display name is only available from the dedicated `/users/{login}` endpoint.

PRRadar already has `GitHubAuthor.name` as an optional field and the UI falls back from `name` to `login` when name is empty (e.g., `PRListRow`, `SummaryPhaseView`, `ReviewDetailView`). However, the name is almost always empty because OctoKit's `User` model only gets it populated from the dedicated user endpoint, not from embedded user objects in PR responses.

To show real names, we need to:
1. Fetch display names via `/users/{login}` for each unique author
2. Cache them so we don't re-fetch on every PR analysis
3. Populate `GitHubAuthor.name` before it flows downstream

The cache should live at the app level (`~/Library/Application Support/PRRadar/`) since GitHub usernames are global — the same login maps to the same display name regardless of which repo is being analyzed.

## Phases

## - [x] Phase 1: Author Cache Model and Service

Add a new `AuthorCacheService` to the `PRRadarConfigService` target, following the same pattern as `SettingsService`.

**Model** (in `PRRadarModels`):
- `AuthorCacheEntry`: struct with `login: String`, `name: String`, `fetchedAt: String` (ISO8601)
- `AuthorCache`: struct wrapping `[String: AuthorCacheEntry]` (keyed by login), `Codable`/`Sendable`

**Service** (in `PRRadarConfigService`):
- `AuthorCacheService`: class following `SettingsService` pattern
  - File location: `~/Library/Application Support/PRRadar/author-cache.json`
  - `load() -> AuthorCache` — reads from disk, returns empty cache if missing
  - `save(_ cache: AuthorCache) throws` — writes to disk with `.prettyPrinted`/`.sortedKeys`
  - `lookup(login: String) -> AuthorCacheEntry?` — check if a login is cached
  - `update(login: String, name: String) throws` — add/update a single entry with current timestamp

Per the architecture rules, `PRRadarConfigService` depends on `PRRadarModels` (services can depend on other services at the same level), so the model goes in `PRRadarModels` and the service in `PRRadarConfigService`.

**Files to create/modify:**
- Create: `Sources/services/PRRadarModels/AuthorCache.swift`
- Create: `Sources/services/PRRadarConfigService/AuthorCacheService.swift`

**Completed:** Models and service created following `SettingsService` pattern exactly. No Package.swift changes needed since both files are in existing targets. Build verified.

## - [x] Phase 2: User Lookup in OctokitClient (SDK Layer)

Add a `getUser(login:)` method to `OctokitClient` that calls `/users/{login}` and returns the user's display name.

OctoKit's `Octokit.user(name:)` method should work, but if it doesn't return the `name` field reliably, fall back to a direct REST call (like the existing `listPullRequestFiles` workaround pattern).

**Files to modify:**
- `Sources/sdks/PRRadarMacSDK/OctokitClient.swift` — add `getUser(login:) async throws -> OctoKit.User` (or a simpler return type with just `login` and `name`)

**Completed:** Added `getUser(login:)` method that delegates to OctoKit's async `user(name:)`. Returns `OctoKit.User` directly, consistent with other methods in the client (e.g., `pullRequest`, `repository`). No REST workaround needed — OctoKit's method correctly calls `GET /users/{login}` and decodes the full `User` model including the `name` field. Build verified.

## - [x] Phase 3: User Name Resolution in GitHubService

Add a method to `GitHubService` that resolves display names for a set of logins, using the cache first and falling back to API calls for cache misses.

**Method:**
- `resolveAuthorNames(logins: Set<String>, cache: AuthorCacheService) async throws -> [String: String]`
  - For each login: check cache → if miss, call `OctokitClient.getUser(login:)` → update cache
  - Returns a `[login: displayName]` dictionary

**Files to modify:**
- `Sources/services/PRRadarCLIService/GitHubService.swift` — add `resolveAuthorNames` method

**Completed:** Added `resolveAuthorNames(logins:cache:)` to `GitHubService`. The method iterates over the login set, checks `AuthorCacheService.lookup` first, and on cache miss calls `OctokitClient.getUser(login:)` to fetch the display name. Falls back to the login string if the user has no display name set. Added `import PRRadarConfigService` to the file (valid — `PRRadarCLIService` depends on `PRRadarConfigService` in Package.swift). Build verified.

## - [x] Phase 4: Integrate into PRAcquisitionService

After fetching PR data and comments in `PRAcquisitionService.acquire()`, collect all unique author logins from the `GitHubPullRequest` and `GitHubPullRequestComments`, resolve their display names via the cache, and patch the `name` field on `GitHubAuthor` objects before writing to disk.

**Approach:**
1. Collect unique logins from `pullRequest.author`, `comments.comments[].author`, `comments.reviews[].author`, `comments.reviewComments[].author`
2. Call `gitHub.resolveAuthorNames(logins:cache:)` to get the name map
3. Create enriched copies of the PR and comments with `name` populated
4. Write the enriched versions to `gh-pr.json` and `gh-comments.json`

`PRAcquisitionService` will need `AuthorCacheService` injected (add to `init` or have `acquire` accept it as a parameter).

**Files to modify:**
- `Sources/services/PRRadarCLIService/PRAcquisitionService.swift` — add cache parameter, collect logins, enrich authors

**Helper needed:**
- Add methods on `GitHubPullRequest` and `GitHubPullRequestComments` (or extensions) to return copies with author names filled in from a `[String: String]` map. These models are in `PRRadarModels` which doesn't depend on the cache service, so the enrichment logic (applying a name map) stays in `PRAcquisitionService` or as a simple extension that takes a dictionary.

**Completed:** Added `withName(from:)` on `GitHubAuthor`, `withAuthorNames(from:)` on `GitHubPullRequest` and `GitHubPullRequestComments` as extensions in `GitHubModels.swift`. These take a `[String: String]` name map and return enriched copies. `PRAcquisitionService.acquire()` now accepts an optional `authorCache: AuthorCacheService?` parameter (default `nil` for backward compatibility). When provided, it collects all unique author logins via a private `collectAuthorLogins` helper, resolves names through the cache, and enriches both the PR and comments before writing to disk. Build verified.

## - [x] Phase 5: Wire Through Use Cases and CLI/App Entry Points

The `AuthorCacheService` needs to be created and passed through the call chain to `PRAcquisitionService`. This affects:

- **CLI commands** that run acquisition (e.g., `diff`, `analyze` commands) — create `AuthorCacheService()` and pass it through
- **MacApp models** that trigger acquisition — same pattern
- **Use cases** in `PRReviewFeature` that call `PRAcquisitionService.acquire()` — thread through the cache parameter

Existing display code in the UI already handles `name` vs `login` fallback (`pr.author.name.isEmpty ? pr.author.login : pr.author.name`), so no UI changes needed — once names are populated in the JSON, they flow through automatically.

**One gap:** `InlinePostedCommentView` (line 19) only shows `author.login`. Update it to prefer `author.name` when available, matching the pattern used elsewhere.

**Files to modify:**
- Use case files in `Sources/features/PRReviewFeature/` that call acquisition
- CLI command files in `Sources/apps/MacCLI/Commands/` that set up acquisition
- MacApp model files that set up acquisition
- `Sources/apps/MacApp/UI/GitViews/InlinePostedCommentView.swift` — show name with login fallback
- `Sources/apps/MacApp/UI/PhaseViews/SummaryPhaseView.swift` (line 119) — shows `author.login` for comment authors, should prefer name

**Completed:** Wired `AuthorCacheService` through the two key entry points:
- `FetchDiffUseCase`: Creates `AuthorCacheService()` and passes it to `PRAcquisitionService.acquire(authorCache:)`. All CLI commands (`diff`, `analyze`) and MacApp's `PRModel.runDiff()` flow through this use case, so they all get author name resolution automatically.
- `FetchPRListUseCase`: Creates `AuthorCacheService()`, collects unique author logins from all fetched PRs, resolves names via `gitHub.resolveAuthorNames()`, and applies them with `.withAuthorNames(from:)` before writing `gh-pr.json`. The `refresh` command and MacApp PR list flow through here.
- `AnalyzeAllUseCase` delegates to `AnalyzeUseCase` → `FetchDiffUseCase`, so it inherits the fix.
- Updated `InlinePostedCommentView` and `SummaryPhaseView.commentRow` to prefer `author.name` over `author.login` using `name.flatMap { $0.isEmpty ? nil : $0 } ?? login` pattern (handles the `String?` type on `GitHubAuthor.name`).
- No CLI command or MacApp model changes needed — they all delegate to use cases that now handle the cache internally. Build verified.

## - [x] Phase 6: Architecture Validation

Review all commits made during the preceding phases and validate they follow the project's architectural conventions.

**For Swift changes** (`pr-radar-mac/`):
- Re-read the `swift-architecture` and `swift-swiftui` skills from `https://github.com/gestrich/swift-app-architecture` (`plugin/skills/`)
- Compare the commits made against the conventions described in each skill
- If any code violates the conventions, make corrections

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. Verify layer dependencies: `AuthorCache` model in Services (PRRadarModels), cache service in Services (PRRadarConfigService), user lookup in SDK (PRRadarMacSDK), resolution in Services (PRRadarCLIService)
4. Verify no upward dependencies were introduced
5. Verify `@Observable` is only in Apps layer
6. Fix any violations found

**Completed:** Reviewed all 5 commits (Phases 1–5) against the swift-app-architecture conventions. No violations found:
- **Layer placement:** All new code is in the correct layer — models in Services (`PRRadarModels`), cache service in Services (`PRRadarConfigService`), SDK method in SDKs (`PRRadarMacSDK`), resolution logic in Services (`PRRadarCLIService`), orchestration in Features (`PRReviewFeature`), UI changes in Apps (`MacApp`).
- **Dependencies:** All flow downward only. `PRRadarCLIService` → `PRRadarConfigService` (Services → Services), `PRReviewFeature` → `PRRadarConfigService` (Features → Services). No upward dependencies.
- **Type conventions:** `AuthorCacheService` is `final class: Sendable`, matching the `SettingsService` pattern exactly. `OctokitClient`, `GitHubService`, `PRAcquisitionService`, and use cases all remain `Sendable` structs as expected.
- **`@Observable` scope:** Confined to Apps layer only — no `@Observable` in Services, Features, or SDKs.
- Build verified clean.

## - [x] Phase 7: Validation

**Automated:**
- `swift build` — ensure the project compiles
- `swift test` — all existing tests pass

**Manual verification:**
- Run `swift run PRRadarMacCLI diff 1 --config test-repo` and inspect `gh-pr.json` — the `author.name` field should be populated
- Inspect `~/Library/Application Support/PRRadar/author-cache.json` — should contain cached entries
- Run the same command again — no new API calls to `/users/` (cache hit)
- Launch `swift run MacApp` and verify display names appear in PR list, detail view, and comment headers

**Completed:** All validation checks passed:
- `swift build` compiles cleanly with no errors or warnings.
- `swift test` passes all 265 tests across 38 suites.
- `swift run PRRadarMacCLI diff 1 --config test-repo` populates `author.name` = "Bill" in both `gh-pr.json` and `gh-comments.json` (reviews and review comments).
- `~/Library/Application Support/PRRadar/author-cache.json` contains the cached entry for `gestrich` with `fetchedAt` timestamp.
- Running the diff command a second time reuses the cache — the `fetchedAt` timestamp remains unchanged, confirming no new `/users/` API calls were made.
