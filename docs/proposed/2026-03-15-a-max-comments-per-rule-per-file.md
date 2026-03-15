## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture rules and placement guidance |
| `swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns for Mac app UI changes |
| `swift-testing` | Test style guide for unit tests |
| `pr-radar-debug` | Debugging guide for reproducing issues via CLI |

## Background

Currently, a single rule can produce many comments of the same type on a single file (e.g., "import order is wrong" flagged on 15 lines). This creates noise for PR authors and can overwhelm the review. We want to cap the number of posted comments per rule per file to a configurable limit `N`, while still surfacing the full count to the author.

**Core behavior:**
- When a rule produces more than `N` violations on a single file, only the first `N` comments (by line order) are posted to GitHub.
- The Nth (last posted) comment includes a **limiting indicator** appended to the body, e.g. *"X other instances of this issue found in this file but limiting to N comments."*
- Comments beyond the limit are **suppressed** — they still appear in CLI output and Mac app views but with a `SUPPRESSED` label, and are never posted to GitHub.
- The `limiting` role is stored in the existing hidden HTML `<!-- prradar:v1 ... -->` metadata block (not parsed from freeform text). The suppressed count is **not** stored in metadata — it's derived at runtime from the current pending violations and rendered in visible markdown only.
- When a previously-posted limiting comment is **resolved** (thread resolved) on GitHub, we treat the PR as no longer having a limiting comment for that rule+file group. The next run should propose a new limiting comment on the next pending comment.

**Scoping clarification — "per rule per file":**
The limit applies per `(ruleName, filePath)` tuple. A rule that flags 3 files with 10 violations each would post up to `N` comments per file, not `N` total.

## Phases

## - [ ] Phase 1: Metadata v2 — Add limiting/suppression fields

**Skills to read**: `swift-app-architecture:swift-architecture`

Extend `CommentMetadata` to support new fields for comment limiting. The metadata is embedded in the hidden HTML block on posted comments, so we need to add fields without breaking v1 parsing.

**Approach — extend v1 with optional fields** (preferred over bumping to v2, since the parser already ignores unknown fields):
- Add `suppression_role` field to `CommentMetadata` with values: `limiting` (absent = normal comment)
- No `suppressed_count` in metadata — the count is derived at runtime from current pending violations and only appears in visible markdown
- Update `CommentMetadata.toHTMLComment()` to emit `suppression_role` when present
- Update `CommentMetadata.parse(from:)` to read `suppression_role` (gracefully absent for existing v1 comments)

**Files to modify:**
- `PRRadarModels/CommentMetadata.swift` — add `suppressionRole: SuppressionRole?` enum

**New types:**
```swift
public enum SuppressionRole: String, Codable, Sendable {
    case limiting   // This is the last posted comment, carries the "N more" indicator
    case suppressed // This comment was not posted because the limit was exceeded
}
```

## - [ ] Phase 2: PRComment and ReviewComment — Add suppression state

**Skills to read**: `swift-app-architecture:swift-architecture`

Add suppression awareness to the comment models so that downstream code (posting, display) can distinguish normal, limiting, and suppressed comments.

**PRComment changes:**
- Add `suppressionRole: SuppressionRole?` property (default `nil`)
- Add `suppressedCount: Int?` property (default `nil`, only set when role is `.limiting`) — this is a runtime-only value for display, not persisted in metadata
- Add a method or factory to create a copy with suppression info applied: `func withSuppression(role: SuppressionRole, count: Int?) -> PRComment`

**ReviewComment changes:**
- Add computed property `suppressionRole` that checks:
  1. If there's a pending comment, use its `suppressionRole`
  2. If posted-only, check the parsed metadata's `suppressionRole`
- Add computed property `isSuppressed: Bool` for convenience

**Files to modify:**
- `PRRadarModels/PRComment.swift`
- `PRRadarModels/ReviewComment.swift`

## - [ ] Phase 3: Suppression logic — Apply limits before posting

**Skills to read**: `swift-app-architecture:swift-architecture`

This is the core logic phase. After reconciliation produces the `[ReviewComment]` list, apply the per-rule-per-file limit to decide which comments are normal, which is the limiting comment, and which are suppressed.

**New service: `CommentSuppressionService`** in `PRRadarCLIService/`

**Input:** `[ReviewComment]`, max comments per rule per file (Int)
**Output:** `[ReviewComment]` with suppression roles applied to their pending comments

**Algorithm:**
1. Group reconciled comments by `(ruleName, filePath)` — only groups with pending comments matter
2. For each group:
   a. Separate into **posted** (`.redetected`, `.postedOnly`) and **pending** (`.new`, `.needsUpdate`)
   b. Count already-posted non-resolved comments for this rule+file (these count toward the limit)
   c. Check if any posted comment already has `suppressionRole == .limiting` **and is not resolved**
   d. Sort pending comments by line number (ascending) for deterministic ordering
   e. Calculate how many more can be posted: `remaining = maxPerFile - postedCount`
   f. If `remaining >= pendingCount`: no suppression needed for this group
   g. If `remaining < pendingCount`:
      - The first `remaining - 1` pending comments → normal (no suppression role)
      - The `remaining`th pending comment → `limiting` with runtime `suppressedCount = pendingCount - remaining` (for display only)
      - All remaining pending comments → `suppressed`
   h. If an existing posted comment is already `limiting` but the visible indicator count is stale (count changed) → mark the corresponding `needsUpdate` comment with updated visible text
3. Return the modified list

**Resolved-comment handling:**
- When counting posted comments, exclude those where the GitHub thread is resolved (see Phase 5 for how we detect this)
- If a posted `limiting` comment is resolved, treat the group as having no limiter — a new pending comment gets the `limiting` role

**Files to create:**
- `PRRadarCLIService/CommentSuppressionService.swift`

## - [ ] Phase 4: Integrate suppression into PostCommentsUseCase

**Skills to read**: `swift-app-architecture:swift-architecture`

Wire the suppression logic into the comment posting pipeline.

**PostCommentsUseCase changes:**
- After `FetchReviewCommentsUseCase` returns reconciled comments, pass them through `CommentSuppressionService.applySuppression()`
- The `categorize()` method should:
  - Exclude `suppressed` comments from `newViolations` and `updatePairs` (they are never posted)
  - Include `limiting` comments in the appropriate category (new or needsUpdate)
- The dry-run output should list suppressed comments separately with a `[SUPPRESSED]` label

**CommentService changes:**
- When posting a `limiting` comment, append the indicator text to the visible markdown body: *"**Note:** X other instances of this issue found in this file. Limiting to N comments per rule."*
- Only `suppression_role: limiting` goes in the hidden metadata block — the count is only in visible text
- When editing an existing `limiting` comment where the count changed, update the visible text (metadata stays the same since it only has the role)

**FetchReviewCommentsUseCase changes:**
- Accept `maxCommentsPerRulePerFile` parameter (from config or CLI flag)
- Pass it through to suppression service

**Files to modify:**
- `PRReviewFeature/usecases/PostCommentsUseCase.swift`
- `PRRadarCLIService/CommentService.swift`
- `PRReviewFeature/usecases/FetchReviewCommentsUseCase.swift`

## - [ ] Phase 5: GitHub thread resolution detection

**Skills to read**: `swift-app-architecture:swift-architecture`

The GitHub REST API for review comments does NOT include thread resolution status. Thread resolution is a concept on `PullRequestReviewThread` in the GraphQL API. We need to detect resolved threads so that resolved `limiting` comments are handled correctly.

**Approach — GraphQL query via `gh api graphql`:**
- Add a method to `GitHubService` (or `OctokitClient`) that fetches review thread resolution status
- Query: `pullRequest.reviewThreads` with `isResolved` field, matching threads to comments by the thread's first comment ID
- This can be a lightweight supplemental fetch — only needed when we have `limiting` comments to check
- Map the `isResolved` status onto `GitHubReviewComment` via a new optional `isResolved: Bool?` field

**Alternative (simpler, may be sufficient):**
- If a posted `limiting` comment has metadata but no longer appears in the REST API response (because it was deleted or the thread was collapsed), treat it as resolved. However, resolved comments ARE still returned by the REST API — they're just collapsed in the UI. So this approach alone won't work.

**Recommended approach:**
- Add `isResolved: Bool` to `GitHubReviewComment` (default `false`)
- Add `fetchReviewThreadResolution(prNumber:)` to `GitHubService` using `gh api graphql`
- Call this after fetching comments, before reconciliation
- Cross-reference thread data with review comments to set `isResolved`

**Files to modify:**
- `PRRadarModels/GitHubModels.swift` — add `isResolved` field to `GitHubReviewComment`
- `GitHubSDK/OctokitClient.swift` or `PRRadarCLIService/GitHubService.swift` — add GraphQL query
- `PRRadarCLIService/PRAcquisitionService.swift` — call resolution fetch during `refreshComments()`

## - [ ] Phase 6: Configuration — maxCommentsPerRulePerFile setting

**Skills to read**: `swift-app-architecture:swift-architecture`

Add the limit as a configurable value.

**Options (in order of preference):**
1. **Per-repository configuration** — add `maxCommentsPerRulePerFile: Int?` to `RepositoryConfigurationJSON` (nil = unlimited, for backward compatibility)
2. **CLI flag override** — add `--max-comments-per-rule N` to the `comment` command
3. **Default value** — use a sensible default (e.g., 3) when not configured

**Files to modify:**
- `PRRadarConfigService/RepoConfiguration.swift` — add field to both JSON and resolved config
- `MacCLI/Commands/CommentCommand.swift` — add CLI flag
- Thread the value through `PostCommentsUseCase` → `CommentSuppressionService`

## - [ ] Phase 7: CLI display — Show suppressed comments

**Skills to read**: none

Update CLI output to clearly distinguish suppressed comments.

**CommentCommand dry-run output changes:**
```
Dry run: 3 new comments would be posted
  [8/10] Import Order - Sources/Foo.swift:12
  [7/10] Import Order - Sources/Foo.swift:25
  [7/10] Import Order - Sources/Foo.swift:38 (limiting: 5 more suppressed)
5 comments suppressed (limit: 3 per rule per file)
  [SUPPRESSED] [6/10] Import Order - Sources/Foo.swift:45
  [SUPPRESSED] [6/10] Import Order - Sources/Foo.swift:52
  ...
```

**Files to modify:**
- `PRReviewFeature/usecases/PostCommentsUseCase.swift` — update `logDryRun()` and `CategorizedComments`

## - [ ] Phase 8: Mac app — Show suppressed comments with distinct treatment

**Skills to read**: `swift-app-architecture:swift-swiftui`

Update the Mac app views to show suppressed comments with visual distinction.

**CommentsPhaseView changes:**
- Show suppressed comments in a separate section or with a dimmed/strikethrough style
- Add a "SUPPRESSED" badge similar to the existing `SeverityBadge`
- Suppressed comments should not have a "Submit" button

**InlineCommentView changes:**
- If the comment is suppressed, show it with reduced opacity and a "Suppressed" label instead of the Submit button
- Limiting comments should show an indicator like "3 more instances suppressed"

**DiffCommentMapper changes:**
- Still map suppressed comments to diff lines (so they're visible in context) but with the distinct treatment

**Files to modify:**
- `MacApp/UI/PhaseViews/CommentsPhaseView.swift`
- `MacApp/UI/GitViews/InlineCommentView.swift`
- Possibly `MacApp/UI/GitViews/DiffCommentMapper.swift`

## - [ ] Phase 9: Validation

**Skills to read**: `swift-testing`, `pr-radar-debug`

**Unit tests:**
- `CommentMetadata` round-trip with new suppression fields
- `CommentSuppressionService` with various scenarios:
  - Under limit: no suppression applied
  - At limit: last comment becomes limiting
  - Over limit: correct split of limiting + suppressed
  - Already-posted comments count toward limit
  - Resolved posted comment doesn't count toward limit
  - Existing limiting comment with stale visible count → needsUpdate
  - Multiple rules on same file → independent limits
  - Multiple files for same rule → independent limits
- `PRComment.withSuppression()` produces correct copies
- `ReviewComment.suppressionRole` computed property

**Integration testing via CLI:**
- Use the test-repo to run `comment --dry-run` with a rule that produces many violations on one file
- Verify CLI output shows the correct split of posted/limiting/suppressed
- Verify that re-running after posting shows correct reconciliation with limiting metadata

**Build verification:**
```bash
cd PRRadarLibrary && swift build && swift test
```
