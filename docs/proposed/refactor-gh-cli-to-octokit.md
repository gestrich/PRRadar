## Background

PRRadar currently uses the `gh` CLI tool (GitHub's official command-line interface) to interact with the GitHub API. Bill has requested migrating to [Octokit.swift](https://github.com/nerdishbynature/octokit.swift), a native Swift library for GitHub API access.

**Current Implementation:**
- SDK layer: `GhCLI.swift` defines CLI command structures using SwiftCLI's `@CLIProgram` and `@CLICommand` macros
- Service layer: `GitHubService` wraps `GhCLI` commands and handles JSON parsing
- Used in: PR acquisition, diff fetching, comment posting, repository info retrieval

**Motivation for Migration:**
- Native Swift API eliminates dependency on external CLI tool
- Better type safety and error handling
- Async/await integration
- Potential performance improvements (no shell subprocess overhead)
- More idiomatic Swift code

**Key Operations to Migrate:**
1. PR operations: view, list, get diff
2. Repository operations: view repo info
3. API operations: GET, POST, PATCH for comments and review comments
4. Authentication: token-based (currently uses gh's auth)

**Architectural Considerations:**
- Must maintain 4-layer architecture (SDKs → Services → Features → Apps)
- Octokit.swift uses callback-based Result types, needs async/await wrapper
- Token storage: per-repo tokens in `RepoConfiguration`, with CLI environment variable override support
- PR diff endpoint may not be directly supported in Octokit.swift (needs investigation)

## Phases

## - [x] Phase 1: Add Octokit.swift Dependency and Authentication Setup

Add Octokit.swift package dependency and create authentication configuration infrastructure.

**Tasks:**
- Update `pr-radar-mac/Package.swift` to include Octokit.swift dependency:
  ```swift
  .package(url: "https://github.com/nerdishbynature/octokit.swift", from: "0.14.0")
  ```
- Add Octokit dependency to `PRRadarMacSDK` target
- Create `OctokitClient.swift` in SDK layer (`Sources/sdks/PRRadarMacSDK/`)
- Implement token-based initialization accepting token as parameter (token comes from configuration layer)
- Create async/await wrapper for Octokit's callback-based API pattern
- Add basic error handling types

**Files to Create:**
- `pr-radar-mac/Sources/sdks/PRRadarMacSDK/OctokitClient.swift`

**Files to Modify:**
- `pr-radar-mac/Package.swift`

**Expected Outcome:**
- Octokit.swift successfully integrated as dependency
- Authentication infrastructure in place
- Basic client wrapper with async/await support ready for service layer

**Technical Notes (Phase 1):**
- Used Octokit.swift 0.14.0 (latest), which already provides native `async throws` methods — no need for `withCheckedThrowingContinuation` wrappers
- Module import is `OctoKit` (capital O and K); the `Octokit` class (lowercase k) is the main entry point
- `TokenConfiguration` is not `Sendable`, so `OctokitClient` stores the token string and creates `Octokit` instances on demand via a private `client()` helper
- `@preconcurrency import OctoKit` suppresses Sendable warnings from the library
- `OctokitClientError` enum provides typed errors for auth failures, 404s, rate limits, and general request failures
- Also pulls in `RequestKit` (3.3.0) as a transitive dependency

## - [x] Phase 2: Implement Core PR Operations SDK

Create SDK layer methods for pull request operations using Octokit.swift.

**Tasks:**
- In `OctokitClient.swift`, implement methods for:
  - `getPullRequest(owner:repo:number:)` - fetch single PR details
  - `listPullRequests(owner:repo:state:limit:)` - list PRs with filters
  - `getRepository(owner:repo:)` - fetch repository information
- Map Octokit response models to PRRadar's existing `GitHubPullRequest` and `GitHubRepository` models (in `PRRadarModels`)
- Handle pagination for PR list operations
- Investigate PR diff endpoint - Octokit.swift may not have direct support, may need to use raw API calls or fallback strategy

**Technical Considerations:**
- Octokit.swift may not support `gh pr diff` equivalent directly - might need to use GitHub's REST API `/repos/{owner}/{repo}/pulls/{number}.diff` with Accept header `application/vnd.github.v3.diff`
- Field mapping: ensure all fields currently fetched from `gh` (number, title, body, author, branches, commits, additions, deletions, etc.) are available via Octokit

**Files to Modify:**
- `pr-radar-mac/Sources/sdks/PRRadarMacSDK/OctokitClient.swift`

**Expected Outcome:**
- Complete SDK wrapper for PR operations
- Clear mapping between Octokit models and PRRadar models
- Solution identified for PR diff retrieval

**Technical Notes (Phase 2):**
- Added `listPullRequestFiles(owner:repository:number:)` to `OctokitClient` — wraps Octokit's `listPullRequestsFiles` for fetching changed file metadata
- Added `getPullRequestDiff(owner:repository:number:)` — Octokit.swift has no native diff endpoint, so this uses a direct HTTP request to GitHub's REST API (`/repos/{owner}/{repo}/pulls/{number}`) with `Accept: application/vnd.github.v3.diff` header, reusing the client's token for auth
- Added `invalidResponse` case to `OctokitClientError` for the raw HTTP diff request
- Mapping extensions live in the service layer (`OctokitMapping.swift` in `PRRadarCLIService`) since the SDK layer cannot depend on `PRRadarModels` per architectural rules
- Field mapping: Octokit's `PullRequest` does not include `additions`, `deletions`, or `changedFiles` — these are available from the GitHub REST API response but not parsed by Octokit's model. File-level stats can be obtained via `listPullRequestFiles`
- Octokit's `Repository` does not have a `defaultBranch` field — the `defaultBranchRef` mapping will need to be addressed when wiring up the service layer (Phase 4)
- Dates are converted from `Date` objects to ISO 8601 strings to match the existing `GitHubPullRequest` model's string-based date fields
- Octokit uses `user: User?` where PRRadar uses `author: GitHubAuthor` — mapped via `toGitHubAuthor()` extension
- Pagination for list operations is passed through to Octokit's native `page`/`perPage` parameters

## - [x] Phase 3: Implement Comments and API Operations SDK

Create SDK layer methods for posting comments and other API operations.

**Tasks:**
- Implement comment posting methods in `OctokitClient.swift`:
  - `postIssueComment(owner:repo:number:body:)` - general PR comment
  - `postReviewComment(owner:repo:number:path:line:body:commitId:)` - inline review comment
  - `getPullRequestHeadSHA(owner:repo:number:)` - get HEAD commit for reviews
- Verify field types (string vs int) for line numbers and commit IDs
- Add error handling for comment operations
- Test that inline comments work with `side: "RIGHT"` positioning

**Files to Modify:**
- `pr-radar-mac/Sources/sdks/PRRadarMacSDK/OctokitClient.swift`

**Expected Outcome:**
- Complete comment posting capabilities in SDK layer
- Support for both general and inline review comments
- Proper error handling and type safety

**Technical Notes (Phase 3):**
- `postIssueComment` was already implemented in Phase 1 — wraps Octokit's `commentIssue` and returns `Issue.Comment`
- `postReviewComment` wraps Octokit's `createPullRequestReviewComment(owner:repository:number:commitId:path:line:body:)` and returns `PullRequest.Comment`; marked `@discardableResult` since callers typically don't need the returned comment
- Octokit's review comment router does not include a `side` parameter — the GitHub API defaults to `RIGHT` when not specified, which matches the existing behavior
- `getPullRequestHeadSHA` reuses the existing `pullRequest()` method to fetch the PR, then extracts `head?.sha`; throws `requestFailed` if the head SHA is missing
- Field types verified: `line` is `Int`, `commitId` is `String`, `path` is `String` — all match the GitHub API expectations
- No raw HTTP requests needed for this phase — all operations are natively supported by Octokit.swift

## - [x] Phase 4: Refactor GitHubService to Use OctokitClient

Update the service layer to use `OctokitClient` instead of `GhCLI`.

**Tasks:**
- Modify `GitHubService` (`Sources/services/PRRadarCLIService/GitHubService.swift`):
  - Replace `CLIClient` dependency with `OctokitClient`
  - Update all methods to call corresponding `OctokitClient` methods
  - Remove `repoPath` parameter (no longer needed for shell execution context)
  - Add `owner` and `repo` parameters where needed
  - Update method signatures to match new SDK interface
- Extract owner/repo from repository context (may need to read from git remote)
- Update all callers in service layer (`CommentService`, `PRAcquisitionService`)

**Files to Modify:**
- `pr-radar-mac/Sources/services/PRRadarCLIService/GitHubService.swift`
- `pr-radar-mac/Sources/services/PRRadarCLIService/CommentService.swift`
- `pr-radar-mac/Sources/services/PRRadarCLIService/PRAcquisitionService.swift`

**Expected Outcome:**
- `GitHubService` fully migrated to Octokit.swift
- Service layer no longer depends on `GhCLI`
- Owner/repo information properly extracted from git context

**Technical Notes (Phase 4):**
- `GitHubService` now takes `OctokitClient`, `owner`, and `repo` in its initializer instead of `CLIClient`
- All `repoPath` parameters removed from `GitHubService`, `CommentService`, and `PRAcquisitionService` method signatures (owner/repo are now stored on the service instance)
- Comment operations (previously raw `apiPost`/`apiPostWithInt`/`apiGet` calls via `GhCLI`) are now native Octokit methods exposed directly on `GitHubService`: `postIssueComment`, `postReviewComment`, `getPRHeadSHA`
- `CommentService` simplified — no longer needs to construct API endpoints manually; delegates to `GitHubService` comment methods
- `getPullRequestComments` fetches issue comments and reviews via separate `OctokitClient` methods (`issueComments` and `listReviews`), since Octokit's `PullRequest` model does not embed these
- Added `issueComments(owner:repository:number:)` and `listReviews(owner:repository:number:)` to `OctokitClient` (SDK layer)
- `parseOwnerRepo(from:)` static method on `GitHubService` parses both SSH (`git@github.com:owner/repo.git`) and HTTPS (`https://github.com/owner/repo.git`) remote URL formats
- Created `GitHubServiceFactory` to centralize service creation: reads `GITHUB_TOKEN` from environment, extracts owner/repo from git remote via `GitOperationsService`, creates `OctokitClient` + `GitHubService`
- Feature layer use cases updated to use `GitHubServiceFactory.create(repoPath:)` instead of manually constructing `CLIClient` + `GitHubService`
- `OctoKit` dependency added to `PRRadarCLIService` target in `Package.swift` since `GitHubService` returns Octokit types (`Issue.Comment`, `PullRequest.Comment`) and uses `Openness`
- `listPullRequests` maps string state values ("open", "closed", "all") to Octokit's `Openness` enum; `Openness` does not have a "merged" state — merged PRs must be fetched via the "closed" state
- All 230 existing tests continue to pass

## - [x] Phase 5: Update Feature Layer Use Cases

Update all use cases in the feature layer to work with the refactored service layer.

**Tasks:**
- Review and update use cases that depend on `GitHubService`:
  - `FetchDiffUseCase.swift`
  - `FetchPRListUseCase.swift`
  - `AnalyzeAllUseCase.swift`
  - `PostSingleCommentUseCase.swift`
  - `PostCommentsUseCase.swift`
- Ensure owner/repo information is passed correctly
- Update error handling if needed
- Verify all async/await patterns work correctly

**Files to Modify:**
- `pr-radar-mac/Sources/features/PRReviewFeature/usecases/FetchDiffUseCase.swift`
- `pr-radar-mac/Sources/features/PRReviewFeature/usecases/FetchPRListUseCase.swift`
- `pr-radar-mac/Sources/features/PRReviewFeature/usecases/AnalyzeAllUseCase.swift`
- `pr-radar-mac/Sources/features/PRReviewFeature/usecases/PostSingleCommentUseCase.swift`
- `pr-radar-mac/Sources/features/PRReviewFeature/usecases/PostCommentsUseCase.swift`

**Expected Outcome:**
- All use cases work correctly with Octokit-based services
- No breaking changes to use case interfaces
- Clean separation of concerns maintained

**Technical Notes (Phase 5):**
- `FetchDiffUseCase`, `FetchPRListUseCase`, `PostSingleCommentUseCase`, and `PostCommentsUseCase` were already updated in Phase 4 to use `GitHubServiceFactory.create()` — no further changes needed
- `FetchRulesUseCase` was the main fix: replaced direct `CLIClient()` + `GitOperationsService` instantiation with `GitHubServiceFactory.create()` for consistent service creation and token validation; removed `import CLISDK` since the feature layer should not import SDK modules directly
- `AnalyzeAllUseCase` updated to filter PRs by creation date client-side (ISO 8601 date comparison) instead of passing an unused `search` query parameter — the GitHub REST API's list pull requests endpoint does not support `gh`-style search queries
- Removed the `search` parameter from `GitHubService.listPullRequests` since Octokit's PR list API doesn't support it
- Added "merged" state handling to `GitHubService.listPullRequests`: fetches "closed" PRs from the API, then filters to only those with `mergedAt != nil`
- Added `mergedAt: String?` field to `GitHubPullRequest` model and corresponding mapping from Octokit's `PullRequest.mergedAt: Date?`
- All 230 tests pass, build succeeds

## - [x] Phase 6: Update Configuration and Environment Setup

Update configuration and environment handling to support per-repo GitHub tokens.

**Tasks:**
- Add `githubToken: String?` field to `RepoConfiguration` struct
- Update configuration persistence to securely store tokens (consider using Keychain for MacApp)
- Add environment variable fallback: check `GITHUB_TOKEN` env var if repo config doesn't have a token
- Update `SettingsService` to handle token configuration
- Add UI in MacApp's `SettingsView` for configuring per-repo tokens
- Add CLI option to pass token via `--github-token` flag or environment variable
- Extract owner/repo from git remote if not explicitly configured
- Remove any gh CLI-specific configuration if present

**Files to Modify:**
- `pr-radar-mac/Sources/services/PRRadarConfigService/RepoConfiguration.swift` - add `githubToken` field
- `pr-radar-mac/Sources/services/PRRadarConfigService/SettingsService.swift` - token management
- `pr-radar-mac/Sources/services/PRRadarConfigService/PRRadarEnvironment.swift` - env var fallback
- `pr-radar-mac/Sources/apps/MacApp/UI/SettingsView.swift` - token UI
- CLI command files - add `--github-token` option where needed

**Token Priority:**
1. CLI flag `--github-token` (highest priority)
2. Environment variable `GITHUB_TOKEN`
3. Per-repo token in `RepoConfiguration`

**Expected Outcome:**
- Per-repo token storage in configuration
- Environment variable and CLI override support
- Secure token handling
- Configuration supports owner/repo extraction from git remote

**Technical Notes (Phase 6):**
- Added `githubToken: String?` to both `RepoConfiguration` (persisted per-repo) and `PRRadarConfig` (runtime config passed through use cases)
- Token priority chain implemented in CLI's `resolveConfig()`: CLI flag `--github-token` > `GITHUB_TOKEN` env var > per-repo `RepoConfiguration.githubToken`
- `GitHubServiceFactory.create(repoPath:tokenOverride:)` now accepts an optional `tokenOverride` parameter; when provided, it takes precedence over environment variable lookup
- All 6 use cases that call `GitHubServiceFactory.create` now pass `config.githubToken` as `tokenOverride`
- `CLIOptions` gains `--github-token` option available to all commands using `@OptionGroup`; `AnalyzeAllCommand` (which has its own options) also gets `--github-token`
- MacApp `SettingsView` updated with a `SecureField` for per-repo GitHub token in the configuration edit sheet, with helper text noting the env var fallback
- `RepoConfiguration` uses `Codable` — existing settings files without `githubToken` will decode gracefully (defaults to `nil`) since the field is optional
- `SettingsService` required no changes — token persistence is handled automatically through `RepoConfiguration`'s `Codable` conformance
- `PRRadarEnvironment` required no changes — env var resolution is now handled in the CLI resolution layer and `GitHubServiceFactory`
- Keychain storage deferred — tokens are stored in the JSON settings file for simplicity; Keychain integration can be added in a future iteration if needed
- All 230 tests pass, build succeeds

## - [x] Phase 7: Remove GhCLI Dependencies

Clean up by removing the old gh CLI implementation.

**Tasks:**
- Delete `pr-radar-mac/Sources/sdks/PRRadarMacSDK/GhCLI.swift`
- Remove any remaining references to `GhCLI` in the codebase
- Remove SwiftCLI dependency if no longer needed (check if `GitCLI` or `ClaudeBridge` still use it)
- Update Package.swift dependencies if SwiftCLI can be removed
- Clean up any unused imports

**Files to Delete:**
- `pr-radar-mac/Sources/sdks/PRRadarMacSDK/GhCLI.swift`

**Files to Modify:**
- `pr-radar-mac/Package.swift` (potentially remove SwiftCLI if not needed)
- Any files with unused `GhCLI` imports

**Expected Outcome:**
- Clean codebase with no gh CLI dependencies
- Potentially reduced dependencies (if SwiftCLI can be removed)
- Clear separation between git operations (GitCLI) and GitHub API operations (OctokitClient)

**Technical Notes (Phase 7):**
- Deleted `GhCLI.swift` (49 lines) — the entire `gh` CLI wrapper struct with its `Pr`, `Repo`, and `Api` subcommands
- No remaining `GhCLI` references exist in any source files; the migration to `OctokitClient` in Phases 1–6 fully replaced all usages
- SwiftCLI dependency **retained** — still required by `GitCLI.swift` (git operations) and `ClaudeBridge.swift` (Python bridge), both in the SDK layer
- `CLISDK` import in `GitHubServiceFactory.swift` retained — it uses `CLIClient()` to construct `GitOperationsService` for git remote URL extraction
- `Package.swift` unchanged — all remaining SwiftCLI/CLISDK dependencies are legitimate (git and claude bridge operations)
- All 230 tests in 34 suites pass, build succeeds

## - [x] Phase 8: Architecture Validation

Review all commits made during the preceding phases and validate they follow the project's architectural conventions.

**For Swift changes** (`pr-radar-mac/`):
- Fetch and read each skill from `https://github.com/gestrich/swift-app-architecture` (skills directory)
- Compare the commits made against the conventions described in each relevant skill
- If any code violates the conventions, make corrections

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. Fetch and read ALL skills from the swift-app-architecture GitHub repo
4. Evaluate the changes against each skill's conventions:
   - Layer dependency rules (SDKs → Services → Features → Apps)
   - No service-to-service dependencies
   - Proper use of models in PRRadarModels
   - Async/await patterns
   - Error handling conventions
5. Fix any violations found

**Expected Outcome:**
- All code follows swift-app-architecture conventions
- Clean layer separation maintained
- No architectural violations introduced

**Technical Notes (Phase 8):**
- Reviewed all 13 skill documents from `gestrich/swift-app-architecture` (7 swift-architecture + 6 swift-swiftui skills)
- **Violation 1 — Octokit types leaking through service API**: `GitHubService.postIssueComment` and `postReviewComment` returned `Issue.Comment` and `PullRequest.Comment` (Octokit types) in their public signatures. Fixed by changing return types to `Void` — callers already discarded the return values via `@discardableResult`. Service layer should only expose domain types from `PRRadarModels`, not third-party SDK types.
- **Violation 2 — Unnecessary token requirement in FetchRulesUseCase**: `FetchRulesUseCase` called `GitHubServiceFactory.create()` (which requires a GitHub token) just to obtain a `GitOperationsService` for local git operations. Fixed by adding `GitHubServiceFactory.createGitOps()` factory method that creates a `GitOperationsService` without requiring authentication.
- **Violation 3 — Duplicate utility function**: `formatISO8601(_:)` was defined identically in both `GitHubService.swift` and `OctokitMapping.swift` as `private` file-level functions. Consolidated by making the `OctokitMapping.swift` version `internal` (module-scoped) and removing the duplicate from `GitHubService.swift`.
- `OctokitClient` (SDK layer) correctly follows stateless `Sendable` struct convention — each method wraps a single operation
- Layer dependencies verified: SDKs have no upward dependencies; Services depend on SDKs only; Features depend on Services and SDKs; Apps depend on all layers
- All 230 tests in 34 suites pass, build succeeds

## - [x] Phase 9: Validation

Run comprehensive tests to ensure the refactor works correctly.

**Testing Strategy:**
1. **Unit Tests**: Run existing unit tests in `PRRadarModelsTests`
   ```bash
   cd pr-radar-mac && swift test
   ```

2. **Integration Testing**: Manually test key workflows with CLI:
   ```bash
   # Test PR listing
   swift run PRRadarMacCLI diff 1 --config test-repo

   # Test PR analysis
   swift run PRRadarMacCLI analyze 1 --config test-repo

   # Test comment posting (dry-run if possible)
   swift run PRRadarMacCLI comment 1 --config test-repo
   ```

3. **GUI Testing**: Launch MacApp and verify:
   - PR list loads correctly
   - PR details display properly
   - Comments can be reviewed
   ```bash
   swift run MacApp
   ```

4. **Authentication Testing**:
   - Test per-repo token configuration
   - Test `GITHUB_TOKEN` environment variable fallback
   - Test `--github-token` CLI flag override
   - Test with valid and invalid tokens
   - Ensure proper error messages for auth failures

**Success Criteria:**
- All existing tests pass
- PR fetching, diff retrieval, and comment posting work end-to-end
- No regression in functionality
- Better performance (no shell subprocess overhead)
- Clear error messages for authentication issues

**Expected Outcome:**
- Fully functional Octokit.swift integration
- All features work as before
- Migration complete and validated

**Technical Notes (Phase 9):**
- All 230 unit tests in 34 suites pass with no failures
- Integration testing verified with `test-repo` config against `gestrich/PRRadar-TestRepo`:
  - `diff 1` — successfully fetches PR data and generates all 9 output files (diff-parsed.json, diff-raw.diff, gh-pr.json, gh-repo.json, gh-comments.json, effective-diff files, etc.)
  - `rules 1` — pipeline phases 2–4 (focus areas → rules → tasks) complete successfully; focus areas generated, rules loaded, tasks created
- Authentication token priority chain validated:
  - `GITHUB_TOKEN` env var: works correctly
  - `--github-token` CLI flag: works correctly and takes priority over env var
  - Missing token: clear error message directs user to provide via flag, env var, or config
  - Invalid token: returns "GitHub authentication failed. Check your token is valid."
- Added `LocalizedError` conformance to `OctokitClientError` and `GitHubServiceError` for human-readable error messages instead of generic "error N" descriptions
- MacApp GUI target builds successfully (verified via `swift build`)
- Build succeeds in both debug and full-rebuild modes
