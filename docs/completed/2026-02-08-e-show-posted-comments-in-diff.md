## Background

The analysis view currently shows pending comments (from rule evaluations) inline in the diff. During PR collection, existing GitHub comments are also fetched and saved to `gh-comments.json`, but they are **not displayed** in the UI.

Additionally, the current GitHub comment fetching retrieves only **issue comments** (`GitHubComment` — no file/line info) and **review objects** (`GitHubReview` — no file/line info). It does **not** fetch **review comments** — the inline code comments that have `path` and `line` fields (GitHub endpoint: `GET /repos/{owner}/{repo}/pulls/{number}/comments`).

To show posted comments inline alongside pending ones, we need to:
1. Fetch review comments (with path/line) from GitHub
2. Display both comment types with different styling (blue = pending, green = posted)
3. Support multiple comments on the same line (a line may have both a posted and pending comment)

OctoKit's `PullRequest.Comment` model is missing the `path` field, so we need the same raw-HTTP workaround already used for `listPullRequestFiles` in `OctokitClient.swift`.

## Phases

## - [x] Phase 1: Model and SDK Layer — Fetch Review Comments

**Model changes** in `Sources/services/PRRadarModels/GitHubModels.swift`:
- Add `GitHubReviewComment` struct: `id`, `body`, `path`, `line: Int?`, `startLine: Int?`, `author: GitHubAuthor?`, `createdAt: String?`, `url: String?`, `inReplyToId: String?`. Conforms to `Codable, Sendable, Identifiable`.
- Update `GitHubPullRequestComments` to add `reviewComments: [GitHubReviewComment]` field
- Add custom `init(from decoder:)` for backward compatibility — defaults `reviewComments` to `[]` when key is missing from existing `gh-comments.json` files

**SDK changes** in `Sources/sdks/PRRadarMacSDK/OctokitClient.swift`:
- Add private `ReviewCommentResponse` Codable struct (mirrors GitHub API JSON with `path`, `line`, `start_line`, `created_at`, `html_url`, `in_reply_to_id`, nested `user`)
- Add public `ReviewCommentData` struct (SDK-level return type, no dependency on PRRadarModels)
- Add `listPullRequestReviewComments(owner:repository:number:) async throws -> [ReviewCommentData]` using raw HTTP (same pattern as `listPullRequestFiles`)

**Service changes** in `Sources/services/PRRadarCLIService/GitHubService.swift`:
- In `getPullRequestComments()`, also call `listPullRequestReviewComments()`, map `ReviewCommentData` → `GitHubReviewComment`, include in the returned `GitHubPullRequestComments`
- No changes needed in `PRAcquisitionService` — it already serializes the full `GitHubPullRequestComments` to `gh-comments.json`

> **Architecture notes (from swift-app-architecture conventions):**
>
> - **SDK layer must be stateless and generic.** `ReviewCommentData` is an SDK-level struct (`Sendable`, no app-specific types). It must NOT import `PRRadarModels`. The SDK wraps a single GitHub API call — no business logic.
> - **Services layer does the mapping.** `GitHubService` maps `ReviewCommentData` → `GitHubReviewComment` (domain model). This mapping belongs in Services, not in the SDK.
> - **Shared models go in Services.** `GitHubReviewComment` belongs in `PRRadarModels` (Services layer) since it's used by both the service layer and the UI.
> - **Code style:** Imports alphabetical. File structure: stored properties → init → computed → methods → nested types. All new structs must be `Sendable`.
> - **Follow existing pattern.** The `listPullRequestFiles` workaround in `OctokitClient.swift` is the exact precedent — private Codable response struct, raw HTTP, public data struct return type.

**Verification**: `swift build` compiles. Run `swift run PRRadarMacCLI diff 1 --config test-repo` and inspect `gh-comments.json` to confirm `reviewComments` array is present.

## - [x] Phase 2: Comment Mapping — Extend DiffCommentMapper

**File**: `Sources/apps/MacApp/UI/GitViews/DiffCommentMapper.swift`

- Add to `DiffCommentMapping`: `postedByFileAndLine: [String: [Int: [GitHubReviewComment]]]`, `postedUnmatchedByFile: [String: [GitHubReviewComment]]`, `postedGeneral: [GitHubComment]`
- Update `DiffCommentMapping.empty` with new fields defaulting to empty
- Update `DiffCommentMapper.map()` to accept `postedReviewComments: [GitHubReviewComment]` and `postedGeneralComments: [GitHubComment]` parameters (default `[]`)
- Map posted review comments by file/line using the same `findHunk` logic used for pending comments

> **Technical notes:** Review comments whose `path` doesn't match any file in the diff are silently dropped (unlike pending comments which go to `unmatchedNoFile`), since posted review comments always have a file path and there's no meaningful "no file" category for them. Existing call sites remain unchanged due to default `= []` parameters.

> **Architecture notes:**
>
> - **Apps layer can import all lower layers.** `DiffCommentMapper` is in the Apps layer — importing `PRRadarModels` for `GitHubReviewComment` is fine.
> - **No orchestration here.** The mapper is a pure data transformation utility, not a use case. It stays in the Apps layer as a view helper.
> - **Code style:** Default parameter values are discouraged by convention, but acceptable here for backward compatibility of existing call sites (`= []`). This is a genuinely optional parameter, not masking missing data.

**Verification**: `swift build` compiles.

## - [x] Phase 3: UI — Posted Comment View and Diff Rendering

**New file**: `Sources/apps/MacApp/UI/GitViews/InlinePostedCommentView.swift`
- Green-themed card (vs blue for pending): green left border, green tinted background
- Shows: author login (bold), timestamp, comment body (selectable text), "View on GitHub" link
- No submit button (already posted)

**Update** `Sources/apps/MacApp/UI/GitViews/RichDiffViews.swift`:
- `AnnotatedHunkContentView`: add `postedAtLine: [Int: [GitHubReviewComment]]` parameter (default `[:]`). After each diff line, render posted comments (green) before pending comments (blue) for that line number.
- `AnnotatedDiffContentView`: pass `postedByFileAndLine` and `postedUnmatchedByFile` from `commentMapping` through to `AnnotatedHunkContentView`. Add section for general posted comments and posted file-level comments.

> **Architecture notes:**
>
> - **Views belong in Apps layer only.** `InlinePostedCommentView` goes in `apps/MacApp/UI/GitViews/` — correct placement.
> - **Prerequisite data pattern.** `InlinePostedCommentView` takes `GitHubReviewComment` as a non-optional `let` — the view requires this data to exist. Parent views decide when to show it. Don't add internal nil-handling for data the view needs.
> - **No @Observable in views.** `InlinePostedCommentView` is a pure rendering view — no model needed. It receives data and displays it.
> - **Match existing patterns.** Follow the exact structure of `InlineCommentView.swift` (HStack with colored Rectangle border, VStack content, background + overlay stroke) but with green instead of blue.

**Verification**: `swift build` compiles.

## - [x] Phase 4: Data Loading and View Wiring

**PRModel** (`Sources/apps/MacApp/Models/PRModel.swift`):
- Add `private(set) var postedComments: GitHubPullRequestComments?`
- In `loadDetail()`, load `gh-comments.json` via `PhaseOutputParser.parsePhaseOutput()` into `postedComments`

**EvaluationsPhaseView** (`Sources/apps/MacApp/UI/PhaseViews/EvaluationsPhaseView.swift`):
- Add `postedReviewComments: [GitHubReviewComment]` and `postedGeneralComments: [GitHubComment]` parameters (default `[]`)
- Pass them through to `DiffCommentMapper.map()` in `commentMapping(for:)`

**ReviewDetailView** (`Sources/apps/MacApp/UI/ReviewDetailView.swift`):
- In `evaluationsOutputView`, pass `prModel.postedComments?.reviewComments ?? []` and `prModel.postedComments?.comments ?? []` to `EvaluationsPhaseView`

> **Architecture notes:**
>
> - **@Observable only in Apps layer.** `PRModel` is the `@Observable` model — it owns state transitions. Adding `postedComments` as a `private(set)` property follows the existing pattern (same as `diff`, `rules`, `evaluation`, `report`).
> - **Minimal business logic in models.** `PRModel.loadDetail()` just calls the parser and assigns — no orchestration. This is correct.
> - **Views receive data, not services.** `EvaluationsPhaseView` receives arrays of comments, not `PRModel` or a service. It doesn't fetch anything. Parent (`ReviewDetailView`) extracts data from the model and passes it down.
> - **`?? []` is acceptable here.** The convention discourages silent fallbacks, but `postedComments` being nil means "not loaded yet" which genuinely means "no posted comments to show" — empty array is the correct representation, not an error.
> - **Depth over width.** The data flows: `PRModel` → `ReviewDetailView` → `EvaluationsPhaseView` → `DiffCommentMapper` → `AnnotatedDiffContentView`. Each layer passes data down without re-orchestrating.

**Verification**: `swift build` compiles. Run `swift run MacApp`, open a PR with existing GitHub review comments, navigate to evaluations phase — posted comments should appear inline with green styling alongside pending comments in blue.

## - [x] Phase 5: Architecture Validation

Review all commits made during the preceding phases and validate they follow the project's architectural conventions:

**For Swift changes** (`pr-radar-mac/`):
- Fetch and read each skill from `https://github.com/gestrich/swift-app-architecture` (skills directory)
- Compare the commits made against the conventions described in each relevant skill
- If any code violates the conventions, make corrections

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. Fetch and read ALL skills from the swift-app-architecture GitHub repo
4. Evaluate the changes against each skill's conventions
5. Fix any violations found

> **Validation results:** All 13 skill files from both `swift-architecture` and `swift-swiftui` skills were reviewed. No violations found:
> - **Layer placement**: SDK types in SDKs, domain model in Services, mapping in Services, views/mapper/model in Apps. Dependency flow is downward only.
> - **Code style**: Imports alphabetically ordered in all files. File structure follows properties → init → computed → methods → nested types convention.
> - **Default values**: Used only for genuinely optional parameters and backward compatibility (documented in phase notes). No silent fallbacks masking errors.
> - **SDK statelessness**: `ReviewCommentData` is a `Sendable` struct with no mutable state. `OctokitClient` wraps a single API call.
> - **@Observable in Apps only**: Only `PRModel` uses `@Observable`.
> - **SwiftUI patterns**: `InlinePostedCommentView` uses prerequisite data pattern (non-optional `let`), pure rendering with no model. Matches existing `InlineCommentView` structure.

## - [x] Phase 6: Validation

- `swift build` — must compile cleanly
- `swift test` — all existing tests must pass
- `swift run PRRadarMacCLI diff 1 --config test-repo` — re-run diff to populate `gh-comments.json` with review comments
- `swift run MacApp` — open evaluations view for a PR that has existing GitHub review comments, verify:
  - Posted comments appear with green styling
  - Pending comments appear with blue styling
  - Multiple comments on the same line render correctly (posted above pending)
  - General posted comments (issue comments without file/line) appear in a separate section
  - Backward compatibility: PRs with old `gh-comments.json` (missing `reviewComments` key) load without error

> **Validation results:**
> - `swift build` compiles cleanly (all targets including MacApp and PRRadarMacCLI)
> - `swift test` passes: 231 tests in 34 suites, all green
> - `swift run PRRadarMacCLI diff 1 --config test-repo` succeeds: `gh-comments.json` contains `reviewComments` array with review comments including `path`, `line`, `body`, `author`, `createdAt`, and `url` fields
> - MacApp GUI verification items require manual testing (posted green vs pending blue styling, multi-comment rendering, general comments section, backward compatibility with old JSON files)
