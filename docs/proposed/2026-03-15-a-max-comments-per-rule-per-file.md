## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture rules and placement guidance |
| `swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns for Mac app UI changes |
| `swift-testing` | Test style guide for unit tests |
| `pr-radar-debug` | Debugging guide for reproducing issues via CLI |

## Background

Currently, a single rule can produce many comments of the same type on a single file (e.g., "import order is wrong" flagged on 15 lines). This creates noise for PR authors and can overwhelm the review. Each rule can define its own `max_comments_per_file: N` in its YAML frontmatter to cap the number of posted comments per file, while still surfacing the full count to the author.

**Core behavior:**
- When a rule produces more than `N` violations on a single file, only the first `N` comments (by line order) are posted to GitHub.
- The Nth (last posted) comment includes a **limiting indicator** appended to the body, e.g. *"X other instances of this issue found in this file but limiting to N comments."*
- Comments beyond the limit are **suppressed** — they still appear in CLI output and Mac app views but with a `SUPPRESSED` label, and are never posted to GitHub.
- The `limiting` role is stored in the existing hidden HTML `<!-- prradar:v1 ... -->` metadata block (not parsed from freeform text). The suppressed count is **not** stored in metadata — it's derived at runtime from the current pending violations and rendered in visible markdown only.
- When a previously-posted limiting comment is **resolved** (thread resolved) on GitHub, we treat the PR as no longer having a limiting comment for that rule+file group. The next run should propose a new limiting comment on the next pending comment.

**Scoping clarification — "per rule per file":**
The limit applies per `(ruleName, filePath)` tuple. A rule that flags 3 files with 10 violations each would post up to `N` comments per file, not `N` total.

## Phases

## - [x] Phase 1: Metadata v2 — Add limiting/suppression fields

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Extended v1 format with optional field for backward compatibility; added 5 tests covering round-trip, graceful absence, and unknown values

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

## - [x] Phase 2: PRComment and ReviewComment — Add suppression state

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Added suppression role to models without runtime-only display data; computed properties on ReviewComment check pending first then fall back to posted metadata

**Skills to read**: `swift-app-architecture:swift-architecture`

Add suppression awareness to the comment models so that downstream code (posting, display) can distinguish normal, limiting, and suppressed comments.

**PRComment changes:**
- Add `suppressionRole: SuppressionRole?` property (default `nil`)
- Add a method to create a copy with suppression info applied: `func withSuppression(role: SuppressionRole) -> PRComment`

**ReviewComment changes:**
- Add computed property `suppressionRole` that checks:
  1. If there's a pending comment, use its `suppressionRole`
  2. If posted-only, check the parsed metadata's `suppressionRole`
- Add computed property `isSuppressed: Bool` for convenience

**Files to modify:**
- `PRRadarModels/PRComment.swift`
- `PRRadarModels/ReviewComment.swift`

## - [x] Phase 3: Suppression logic — Apply limits before posting

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Stateless Sendable struct in Services layer following ViolationService pattern; pure transformation with no side effects

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

## - [x] Phase 4: Integrate suppression into PostCommentsUseCase

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Per-rule limits flow from rule YAML through ReviewRule → TaskRule → PRComment; suppression service reads limits from comments rather than a global parameter; CommentService batch methods handle suppression indicators while single-comment methods stay clean; used CommentToPost model instead of dictionaries

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

**Model changes (per-rule limits instead of global config):**
- `maxCommentsPerFile: Int?` added to `ReviewRule` (parsed from `max_comments_per_file` YAML frontmatter), `TaskRule`, and `PRComment`
- `CommentSuppressionService` reads limits from each group's comments instead of a global parameter
- `FetchReviewCommentsUseCase` unchanged — suppression applied in `PostCommentsUseCase`

**Files modified:**
- `PRReviewFeature/usecases/PostCommentsUseCase.swift`
- `PRRadarCLIService/CommentService.swift`
- `PRRadarCLIService/CommentSuppressionService.swift`
- `PRRadarModels/RuleOutput.swift`
- `PRRadarModels/RuleRequest.swift`
- `PRRadarModels/PRComment.swift`

## - [x] Phase 5: GitHub thread resolution detection

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: GraphQL query in SDK layer (stateless), enrichment in Services layer; outdated detection via REST `position == null` avoids extra API call; suppression service excludes both resolved and outdated from count

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

## - [x] Phase 6: Configuration — per-rule maxCommentsPerFile setting

**Completed in Phase 4.** The limit is defined per-rule in the rule's YAML frontmatter as `max_comments_per_file: N`, rather than as a global repository config. This was implemented as part of Phase 4:
- `ReviewRule` parses `max_comments_per_file` from frontmatter
- Flows through `TaskRule` → `PRComment` → `CommentSuppressionService`
- Rules without the field have no limit (nil = unlimited)

## - [x] Phase 7: CLI display — Show suppressed comments

**Skills used**: none
**Principles applied**: Grouped suppressed comments by rule name so each rule shows its per-file limit; both dry-run and post paths use consistent per-rule grouping

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

## - [x] Phase 8: Mac app — Show suppressed comments with distinct treatment

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: SuppressionBadge in its own file; suppressedCount helper on both [PRComment] and [ReviewComment] to avoid duplicated filtering logic; suppressed comments excluded from violation navigation

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

## - [x] Phase 9: Rename needsPosting to isPending

**Skills to read**: `swift-app-architecture:swift-architecture`

`ReviewComment.needsPosting` is misleading — a suppressed comment has `needsPosting == true` but will never be posted. Rename to clarify the reconciliation state vs posting intent.

**Renames:**
- `ReviewComment.needsPosting` → `isPending` (means `.new` or `.needsUpdate` — a reconciliation state, not a posting decision)
- Add `ReviewComment.readyForPosting: Bool` = `isPending && !isSuppressed` (the actual posting intent)

**Update all call sites:**
- `CommentSuppressionService` uses `needsPosting` to find pending comments *before* suppression → change to `isPending`
- `PRModel.orderedViolations` currently uses `needsPosting && !isSuppressed` → change to `readyForPosting`
- `DiffPhaseView` uses `needsPosting` for violation counts and navigation → evaluate each usage: if it should exclude suppressed, use `readyForPosting`; if it counts all pending, use `isPending`
- `ReviewComment.debugSummary` references `needsPosting` → update to `isPending`
- Any other call sites found via search

**Files to modify:**
- `PRRadarModels/ReviewComment.swift`
- `PRRadarCLIService/CommentSuppressionService.swift`
- `MacApp/Models/PRModel.swift`
- `MacApp/UI/PhaseViews/DiffPhaseView.swift`
- Any other files referencing `needsPosting`

## - [x] Phase 10: Validation

**Skills used**: `swift-testing`, `pr-radar-debug`
**Principles applied**: Arrange-Act-Assert test style; comprehensive unit tests for CommentSuppressionService and suppression model properties; integration tests via CLI with test-repo PR

**Bugs found and fixed during validation:**
- `RuleLoaderService.ruleWithURL()` dropped `maxCommentsPerFile` when reconstructing rule with git URL
- `CommentService.buildBodyWithSuppression()` showed wrong "Limiting to X" count (used `suppressedCount + 1` instead of `maxCommentsPerFile`)
- `CommentMetadata.stripMetadata()` didn't strip suppression indicator Note line, causing perpetual `needsUpdate` on re-runs

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

## - [x] Phase 11: Fix limiting indicator not appearing on posted comments

**Skills used**: `pr-radar-debug`
**Principles applied**: When `remaining <= 0`, promote last active posted comment to `needsUpdate` with `.limiting` role; extracted duplicated sort-by-line into `sortedByLine` helper; `applyLimitingRole` now handles `.redetected` → `.needsUpdate` promotion; removed redundant `promoteToLimiting`

**Skills to read**: `pr-radar-debug`

**Problem:** After posting comments with `max_comments_per_file: 2`, the limiting comment on GitHub is missing both:
1. The visible `> **Note:** X other instances...` blockquote
2. The `suppression_role: limiting` field in the hidden metadata

See PR #19 on PRRadar-TestRepo (closed) — the comment at `DataProcessor.swift:14` should show the limiting indicator but doesn't: https://github.com/gestrich/PRRadar-TestRepo/pull/19#discussion_r2936845122

**How to reproduce:**
1. PR #19 was closed but the posted comments are still visible. Or create a new test branch:
   ```bash
   cd /Users/bill/Developer/personal/PRRadar-TestRepo
   git checkout -b test-limiting-indicator main
   # Copy DataProcessor.swift from the closed PR (has 5 force unwraps + 8 return nils)
   git add DataProcessor.swift && git commit -m "test" && git push -u origin test-limiting-indicator
   GH_TOKEN=$(gh auth token --user gestrich) gh pr create --title "Test limiting" --body "test" --base main
   ```
2. Run the pipeline and post:
   ```bash
   cd /Users/bill/Developer/personal/PRRadar/PRRadarLibrary
   swift run PRRadarMacCLI run <PR> --config test-repo
   swift run PRRadarMacCLI comment <PR> --config test-repo
   ```
3. Check the comment body on GitHub — the limiting comment should have the Note blockquote and `suppression_role: limiting` in metadata, but likely won't.

**What's known so far:**

The dry-run output is correct — it shows `(limiting: 4 more suppressed)` for the right comments. The `CommentSuppressionService` correctly assigns `.limiting` role. The issue is somewhere in the posting/editing path.

**Investigation angles:**

1. **`buildBodyWithSuppression` receives `suppressedCount == 0`?** — The `categorize()` method in `PostCommentsUseCase` builds `CommentToPost` with `suppressedCount` from `suppressedCountForLimiting()`. This helper returns 0 unless `comment.suppressionRole == .limiting`. Check whether the pending comment's `suppressionRole` is actually `.limiting` at categorization time. Add a log statement in `categorize()` to print each comment's suppression role.

2. **Suppression applied AFTER categorization?** — Check the order: `applySuppression()` is called on line 71 of `PostCommentsUseCase`, then `categorize()` on line 73. The suppression should already be applied. But verify by logging `allComments` after line 71 to confirm limiting roles are present.

3. **The `comment` command re-fetches from GitHub before posting?** — If `PostCommentsUseCase.run()` calls `FetchReviewCommentsUseCase` with `cachedOnly: false` (refreshing from GitHub), the fresh fetch could overwrite the cached comments and change reconciliation results. Check which overload is called and whether a sync during posting could change the comment states.

4. **Edit path vs. new path** — During Phase 10 testing, the first post used the old buggy code (wrong "Limiting to 5" text). Then after the code fix, an edit was performed. Check whether the edit path (`editViolations`) correctly passes `suppressedCount` through `buildBodyWithSuppression`. The edit may have matched the comment as `redetected` (body now matches after `stripMetadata` fix) instead of `needsUpdate`, causing it to skip the edit entirely on subsequent runs.

**Second issue: GraphQL thread resolution not working via CLI**

The `sync` command fetches comments but `isResolved` stays `false` for all comments, even after resolving a thread on GitHub. The GraphQL query works fine via `gh api graphql` with the gestrich token.

Root cause: `PRAcquisitionService.refreshComments()` line 77 uses `try?` which silently swallows errors from `fetchResolvedReviewCommentIDs()`. The `CredentialResolver` likely resolves a different token than the `gh` CLI's gestrich account.

**To debug:** Temporarily change `try?` to `try` on line 77 of `PRAcquisitionService.swift` and run `swift run PRRadarMacCLI sync <PR> --config test-repo` to see the actual error message. Alternatively, add a log statement before the call to print the resolved token prefix.

## - [x] Phase 12: End-to-end demonstration of comment suppression

**Skills used**: `pr-radar-debug`
**Principles applied**: Discovered and fixed idempotency bug where `applyLimitingRole` promoted already-limiting `.redetected` comments to `.needsUpdate`; added regression test

**Skills to read**: `pr-radar-debug`

Demonstrate the full suppression lifecycle with a fresh PR on PRRadar-TestRepo. The test-repo rules `detect-force-unwrap` and `no-return-nil` both have `max_comments_per_file: 2`.

### Setup

Create a test file with exactly **3** force unwraps (1 over the limit of 2) so the result is clear and simple:

```bash
cd /Users/bill/Developer/personal/PRRadar-TestRepo
git checkout -b demo-suppression main
```

Create `SuppressionDemo.swift`:
```swift
import Foundation

func processItems(_ items: [String?]) -> [String] {
    let first = items.first!
    let second = items[1]!
    let third = items[2]!
    return [first, second, third]
}
```

This gives 3 force unwraps on one file. With `max_comments_per_file: 2`:
- Line with `items.first!` → normal comment (posted)
- Line with `items[1]!` → limiting comment (posted, with indicator: "1 other instance...")
- Line with `items[2]!` → suppressed (not posted)

Push and create the PR:
```bash
git add SuppressionDemo.swift
git commit -m "Add file with force unwraps for suppression demo"
git push -u origin demo-suppression
GH_TOKEN=$(gh auth token --user gestrich) gh pr create --title "Demo: comment suppression" --body "Testing max_comments_per_file limiting" --base main
```

### Demonstration 1: Dry run — verify suppression split

```bash
cd /Users/bill/Developer/personal/PRRadar/PRRadarLibrary
swift run PRRadarMacCLI analyze <PR> --config test-repo
swift run PRRadarMacCLI comment <PR> --dry-run --config test-repo
```

**Expected output:**
- 1 new comment would be posted (normal)
- 1 new comment would be posted with `(limiting: 1 more suppressed)`
- 1 comment suppressed for `detect-force-unwrap` (limit: 2 per file)

### Demonstration 2: Post and verify on GitHub

```bash
swift run PRRadarMacCLI comment <PR> --config test-repo
```

**Verify on GitHub:**
1. 2 comments posted on the PR
2. The second comment includes the blockquote: `> **Note:** 1 other instance of this issue found in this file. Limiting to 2 comments per rule.`
3. The second comment's hidden metadata includes `suppression_role: limiting`
4. No third comment was posted

### Demonstration 3: Re-run is idempotent

```bash
swift run PRRadarMacCLI comment <PR> --dry-run --config test-repo
```

**Expected:** "All violations already posted — nothing new to comment" (the 2 posted are `redetected`, the suppressed one stays suppressed)

### Cleanup

Close the PR and delete the branch after verification:
```bash
GH_TOKEN=$(gh auth token --user gestrich) gh pr close <PR>
git checkout main
git branch -D demo-suppression
git push origin --delete demo-suppression
```
