# Hidden Metadata in PR Comments

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules for proper placement of new types/logic |
| `/swift-testing` | Test style guide for unit tests on reconciliation logic |
| `/pr-radar-verify-work` | Verify changes work against the test repo |

## Background

Currently, PRRadar's duplicate comment detection (`ViolationService.reconcile()`) matches pending violations against posted GitHub comments using three criteria:

1. **File path** — exact match on `path`
2. **Line number** — exact match on `line`
3. **Rule name** — `body.contains(ruleName)` substring check on the comment body

This approach is fragile:
- If a rule is renamed, old comments become orphaned and the "same" violation gets re-posted
- If lines shift due to new commits (e.g., code added above), the same violation appears as new
- No way to correlate a posted comment back to a specific rule version or PR commit
- The `body.contains(ruleName)` check can false-match if one rule name is a substring of another

**Goals**:
1. Embed structured, hidden metadata in each posted comment so reconciliation can be smarter — detecting when a violation moved lines, when the same rule fires on a newer commit, and avoiding duplicate posts more reliably.
2. **Edit existing comments in-place** when the rule output changes (e.g., tweaked violation message, updated score) rather than posting a duplicate. GitHub supports `PATCH` on both review comments and issue comments — PRRadar currently only creates comments, never edits them.

### Prior Art

- **Graphite** uses `<i class='graphite__hidden'>` HTML tags with embedded UUIDs and links
- **Mergify** uses HTML comments `<!--MERGIFY-CI-INSIGHTS-REPORT-->` as identifier tags

For PRRadar, **HTML comments (`<!-- -->`)** are the best fit — they're completely invisible in GitHub's rendered markdown, easy to parse, and don't affect the visible comment at all.

### Proposed Metadata Format

Each posted comment will include a trailing HTML comment block:

```html
<!-- prradar:v1
rule_id: service-locator-usage
rule_hash: a1b2c3d4
file: Sources/App/ServiceLocator.swift
line: 42
pr_head_sha: abc123def456
file_blob_sha: 789xyz
-->
```

Fields:
| Field | Source | Purpose |
|-------|--------|---------|
| `rule_id` | `PRComment.ruleName` | Stable rule identifier |
| `rule_hash` | Hash of rule file contents (`RuleRequest.ruleBlobHash`) | Detect rule changes between runs |
| `file` | `PRComment.filePath` | File where violation was found |
| `line` | `PRComment.lineNumber` | Line number at time of posting |
| `pr_head_sha` | PR head commit SHA (already fetched in `CommentService`) | Know which commit the review ran against |
| `file_blob_sha` | Git blob SHA of the file at `pr_head_sha` | Detect if file content changed between runs |

### Version Scheme

- **v0 (implicit)** — Comments posted before this feature. No `<!-- prradar:... -->` block. Matched using the legacy heuristic (file + line + `body.contains(ruleName)`). When matched, they are always `.needsUpdate` — the edit adds the v1 metadata block, effectively upgrading them. This means the first run after this feature ships will edit all existing matched comments to embed metadata.
- **v1** — Comments with the `<!-- prradar:v1 ... -->` block. Matched using structured metadata fields.

### Smarter Reconciliation Strategy

With metadata available, reconciliation can be upgraded:

**v1 comments (have metadata):**
1. **Exact match, same content** — same `rule_id` + `file` + `line`, comment body unchanged → `.redetected` (skip entirely)
2. **Exact match, content changed** — same `rule_id` + `file` + `line`, but comment body differs (rule output was tweaked) → `.needsUpdate` (edit the existing comment in-place via PATCH)
3. **Line-shifted match** — same `rule_id` + `file` + `file_blob_sha`, different `line` → `.redetected` (file unchanged, line just shifted in diff context)
4. **Same rule, file changed** — same `rule_id` + `file`, different `file_blob_sha` → `.new` (file was modified, re-evaluate is warranted)
5. **Stale commit** — posted comment's `pr_head_sha` matches current → definitely skip; differs → use other fields to decide

**v0 comments (no metadata, legacy):**
1. **Legacy match** — same file + line + `body.contains(ruleName)` → `.needsUpdate` (always edit to upgrade with metadata block + refresh body)
2. **No match** → `.postedOnly` (orphaned old comment)

### Comment Editing

When a matched comment's body has changed (state `.needsUpdate`), PRRadar will **edit the existing GitHub comment** using:
- `PATCH /repos/{owner}/{repo}/pulls/comments/{comment_id}` — for inline review comments
- `PATCH /repos/{owner}/{repo}/issues/comments/{comment_id}` — for general PR comments

This keeps the conversation thread intact (preserving replies and reactions) while updating the violation text. The metadata block is also updated with the new `rule_hash` and `pr_head_sha`.

This is a meaningful upgrade from the current "file + line + body contains rule name" approach.

### Backward Compatibility

**Serialized data (cached tasks/evaluations on disk):** No backward compatibility needed. Old cached files that lack new required fields will fail to decode and be re-evaluated — this is fine.

**GitHub comments (v0):** Must remain supported. Comments posted before this feature won't have the `<!-- prradar:... -->` block. The reconciliation logic (Phase 4) handles these via the legacy heuristic and upgrades them on first match.

## Phases

## - [x] Phase 1: Define Comment Metadata Model

**Completed in prior session** (commit `37a9c8d`)
**Skills used**: `/swift-app-architecture:swift-architecture`
**Notes**: Model uses nested `RuleInfo`/`FileInfo` structs for clean grouping. Regex-based parsing with `RegexBuilder`.

**Skills to read**: `/swift-app-architecture:swift-architecture`

Add a `CommentMetadata` struct to `PRRadarModels`:

```swift
public struct CommentMetadata: Codable, Sendable, Equatable {
    public let version: Int           // Schema version (start at 1)
    public let ruleId: String         // Rule name/identifier
    public let ruleHash: String?      // Hash of rule file contents
    public let file: String           // File path
    public let line: Int?             // Line number
    public let prHeadSHA: String      // PR head commit at time of posting
    public let fileBlobSHA: String?   // Git blob SHA of the file
}
```

Add serialization methods:
- `toHTMLComment() -> String` — renders the `<!-- prradar:v1 ... -->` block
- `static func parse(from body: String) -> CommentMetadata?` — extracts metadata from a comment body, returns nil for v0 comments (no metadata block present)
- `static func stripMetadata(from body: String) -> String` — removes the `<!-- prradar:... -->` block from a comment body, used for content comparison (so metadata differences don't trigger false `.needsUpdate`)

Files to modify/create:
- New file: `PRRadarLibrary/Sources/services/PRRadarModels/CommentMetadata.swift`

## - [x] Phase 2: Embed Metadata When Posting Comments

**Skills used**: `/swift-app-architecture:swift-architecture`
**Principles applied**: Made `ruleBlobHash` and `ruleHash` non-optional throughout the pipeline (RuleRequest → PRComment → CommentMetadata). Metadata constructed at posting time in CommentService where `prHeadSHA` is available. `contentHash` throws on missing rule file rather than returning a placeholder.

**Skills to read**: `/swift-app-architecture:swift-architecture`

Update the comment posting flow to append metadata to each comment body:

1. **`PRComment`** — add fields needed for metadata: `prHeadSHA`, `fileBlobSHA`, `ruleHash`
2. **`PRComment.toGitHubMarkdown()`** — append `CommentMetadata.toHTMLComment()` to the end of the rendered markdown
3. **`CommentService.postViolations()`** — already fetches `commitSHA` (the PR head); pass it through to `PRComment` or construct metadata at posting time
4. **Populate `fileBlobSHA`** — use `git ls-tree <commit> <filepath>` (via existing `GitService`) to get the blob SHA for each file being commented on. Or alternatively, fetch it from the GitHub API.
5. **Populate `ruleHash`** — `RuleRequest.ruleBlobHash` (non-optional) flows through to `PRComment.ruleHash`.

Files to modify:
- `PRRadarModels/PRComment.swift` — add metadata fields, update `toGitHubMarkdown()`
- `PRRadarCLIService/CommentService.swift` — construct metadata, pass commit info
- Possibly `PRReviewFeature/usecases/PostCommentsUseCase.swift` — thread new data through

## - [x] Phase 3: Parse Metadata from Posted Comments

**Skills used**: `/swift-app-architecture:swift-architecture`
**Principles applied**: Added computed properties directly on the model struct rather than modifying the fetch path. `bodyWithoutMetadata` added for content comparison in Phase 4.

**Skills to read**: `/swift-app-architecture:swift-architecture`

Update the reconciliation input path to extract metadata from existing GitHub comments:

1. **`GitHubReviewComment`** — add a computed property `metadata: CommentMetadata?` that calls `CommentMetadata.parse(from: body)`
2. **`FetchReviewCommentsUseCase`** — no changes needed if metadata is computed from body

Files to modify:
- `PRRadarModels/GitHubModels.swift` — add computed `metadata` property
- `PRRadarModels/CommentMetadata.swift` — ensure `parse()` handles edge cases (no metadata, malformed, wrong version)

## - [x] Phase 4: Upgrade Reconciliation Logic

**Skills used**: `/swift-app-architecture:swift-architecture`
**Principles applied**: Tiered matching (v1 metadata-aware, v0 legacy fallback). Made `state` a stored property on `ReviewComment` to support `.needsUpdate` alongside `.redetected`. Body comparison strips metadata before diffing. Added new phases to plan based on review feedback (enum refactor, single source of truth, `isActionable`/`isPosted` helpers).

**Skills to read**: `/swift-app-architecture:swift-architecture`

Replace the current `ViolationService.reconcile()` matching with metadata-aware logic:

**Current matching**: file + line + `body.contains(ruleName)` (fragile)

**New matching** (tiered):
1. If posted comment has metadata:
   - **Exact match, same body** → `.redetected` (skip)
   - **Exact match, different body** → `.needsUpdate` (edit existing comment)
   - **Line-shifted match**: same `ruleId` + `file` + same `fileBlobSHA`, different `line` → `.redetected` (file unchanged, line just moved)
   - **File-changed match**: same `ruleId` + `file`, different `fileBlobSHA` → `.new` (file was modified, violation should be re-posted)
2. If posted comment has NO metadata (v0/legacy):
   - Match using old heuristic: same `file` + `line` + `body.contains(ruleName)`
   - If matched → always `.needsUpdate` (edit to upgrade with v1 metadata block + refreshed body)
   - If no match → `.postedOnly`

Update `ReviewComment.State` to add `.needsUpdate` alongside `.new`, `.redetected`, `.postedOnly`. The `.needsUpdate` state carries the existing comment's GitHub ID so the posting flow knows which comment to PATCH.

To compare "same body vs different body", strip the metadata block from both the posted comment body and the newly generated body before comparing — the metadata itself will differ (different `pr_head_sha`, etc.) so it shouldn't be part of the content comparison.

Files to modify:
- `PRRadarCLIService/ViolationService.swift` — rewrite `reconcile()` with tiered matching
- `PRRadarModels/ReviewComment.swift` — add `.needsUpdate` state

## - [ ] Phase 5: Refactor ReviewComment to Enum with Associated Values

**Skills to read**: `/swift-app-architecture:swift-architecture`

Currently `ReviewComment` is a struct with `pending: PRComment?`, `posted: GitHubReviewComment?`, and `state: State` as independent properties. Each state implies a specific combination of optionals:

| State | `pending` | `posted` |
|-------|-----------|----------|
| `.new` | always set | always nil |
| `.redetected` | always set | always set |
| `.needsUpdate` | always set | always set |
| `.postedOnly` | always nil | always set |

This means consumers do unnecessary `if let` unwrapping on values guaranteed by the state. Refactor to an enum with associated values to make impossible states unrepresentable:

```swift
public enum ReviewComment: Sendable, Identifiable {
    case new(pending: PRComment)
    case redetected(pending: PRComment, posted: GitHubReviewComment)
    case needsUpdate(pending: PRComment, posted: GitHubReviewComment)
    case postedOnly(posted: GitHubReviewComment)
}
```

Add convenience computed properties (`filePath`, `lineNumber`, `score`, `ruleName`, `pending`, `posted`, `state`) to minimize churn at call sites. The `state` property returns a simple enum for switch sites that only care about the category (e.g., `$0.state == .new`).

Also add semantic query properties to eliminate repeated multi-case checks scattered across `DiffPhaseView`, `PRModel`, and `PostCommentsUseCase`:

- **`isActionable: Bool`** — `true` for `.new` and `.needsUpdate` (comments requiring user action: post or edit)
- **`isPosted: Bool`** — `true` for `.redetected` and `.postedOnly` (comments already on GitHub, no action needed)

This replaces patterns like `$0.state == .new || $0.state == .needsUpdate` and `$0.state == .redetected || $0.state == .postedOnly` with `$0.isActionable` and `$0.isPosted`, keeping the categorization logic in one place.

Files to modify:
- `PRRadarModels/ReviewComment.swift` — convert from struct to enum with associated values
- `PRRadarCLIService/ViolationService.swift` — update `reconcile()` to construct enum cases
- `apps/MacApp/UI/GitViews/RichDiffViews.swift` — update switch blocks to destructure associated values (removes `if let` guards)
- `apps/MacApp/UI/GitViews/DiffCommentMapper.swift` — update sort order extension
- `apps/MacApp/UI/PhaseViews/DiffPhaseView.swift` — update state checks
- `apps/MacApp/Models/PRModel.swift` — update `pendingCommentCount`
- `features/PRReviewFeature/usecases/PostCommentsUseCase.swift` — update state filters
- `Tests/PRRadarModelsTests/ViolationReconciliationTests.swift` — update test assertions

## - [ ] Phase 6: Add GitHub Comment Edit API Support

**Skills to read**: `/swift-app-architecture:swift-architecture`

Add PATCH support to the SDK and service layers for editing existing comments:

1. **`OctokitClient`** — add a generic `patchJSON()` method (mirrors existing `postJSON()`), then add:
   - `updateReviewComment(commentId:body:)` — `PATCH /repos/{owner}/{repo}/pulls/comments/{comment_id}`
   - `updateIssueComment(commentId:body:)` — `PATCH /repos/{owner}/{repo}/issues/comments/{comment_id}`
2. **`GitHubService`** — expose `updateReviewComment()` and `updateIssueComment()` wrappers
3. **`CommentService`** — update `postViolations()` (or add a new method) to handle `.needsUpdate` comments by calling the edit API instead of creating new ones. The comment's GitHub ID comes from the matched `GitHubReviewComment.id`.

Files to modify:
- `sdks/GitHubSDK/OctokitClient.swift` — add `patchJSON()`, `updateReviewComment()`, `updateIssueComment()`
- `services/PRRadarCLIService/GitHubService.swift` — add update wrappers
- `services/PRRadarCLIService/CommentService.swift` — handle `.needsUpdate` state
- `features/PRReviewFeature/usecases/PostCommentsUseCase.swift` — route `.needsUpdate` comments to edit flow

## - [ ] Phase 7: Populate File Blob SHA

**Skills to read**: `/swift-app-architecture:swift-architecture`

Add capability to resolve the git blob SHA for a file at a given commit. This is needed to detect whether a file's content changed between the commit a comment was posted on and the current PR head.

Options:
- **Git CLI**: `git ls-tree <commit> -- <filepath>` → parse blob SHA from output
- **GitHub API**: `GET /repos/{owner}/{repo}/git/trees/{sha}` — more complex, may need recursive calls

Prefer the git CLI approach since PRRadar already shells out to git extensively via `GitService`.

Files to modify:
- `PRRadarMacSDK` or `PRRadarCLIService/GitService.swift` — add `blobSHA(for:at:)` method
- Wire into the comment posting flow from Phase 2

## - [ ] Phase 8: Single Source of Truth for Submitted Comments

**Skills to read**: `/swift-app-architecture:swift-architecture`, `/swift-app-architecture:swift-swiftui`

### Problem

`PRModel` has two sources of truth for whether a comment was posted:

1. **`submittedCommentIds: Set<String>`** — local optimistic set populated immediately after a successful GitHub API post in `submitSingleComment()`. Used by `pendingCommentCount` and `InlineCommentView.isSubmitted` to update UI instantly.
2. **`ReviewComment.state`** — authoritative state from `ViolationService.reconcile()`, which compares pending violations against GitHub comments fetched to disk. Only updates when review comments are reloaded.

These can diverge: after posting, `submittedCommentIds` says "posted" but `reviewComments` still shows `.new` until a manual refresh happens.

### Solution

After successfully posting a comment, re-fetch review comments from GitHub so reconciliation becomes the single authority. Keep `submittedCommentIds` only as a brief optimistic bridge during the re-fetch.

### Implementation

1. **Add `refreshReviewCommentsFromGitHub()` helper** to `PRModel` — calls `FetchReviewCommentsUseCase.execute(cachedOnly: false)` to fetch from GitHub, assigns result to `reviewComments`, clears `submittedCommentIds`.

2. **Modify `submitSingleComment()`** (line ~486) — after the optimistic `submittedCommentIds.insert()`, call `await refreshReviewCommentsFromGitHub()`. The optimistic insert provides instant checkmark UI; the re-fetch then makes reconciliation authoritative and clears the set.

3. **Refactor `postManualComment()`** (lines ~509-517) — replace its inline fetch logic with a call to `refreshReviewCommentsFromGitHub()` to deduplicate.

4. **`pendingCommentCount`** — keep filtering on `$0.state == .new` only (not `.needsUpdate`). The `submittedCommentIds` check stays as the optimistic bridge during the fetch window.

### Post-submit flow

1. User taps Submit → spinner via `submittingCommentIds`
2. GitHub API post succeeds → `submittedCommentIds.insert()` → immediate checkmark
3. `refreshReviewCommentsFromGitHub()` fetches → reconciliation produces `.redetected` → `submittedCommentIds` cleared
4. Comment renders as `InlinePostedCommentView` instead of `InlineCommentView`

### Edge cases

- **Re-fetch fails**: Use `try?` so failure is silent. `submittedCommentIds` retains the ID, checkmark persists. Next manual reload picks it up.
- **Multiple rapid submissions**: Each triggers its own re-fetch. Since `@MainActor`, state updates are serialized. Last re-fetch wins (most up-to-date).

Files to modify:
- `apps/MacApp/Models/PRModel.swift` — add helper, modify `submitSingleComment()`, refactor `postManualComment()`

No changes needed to:
- `InlineCommentView.swift` — checkmark works via optimistic set, then view switches to `InlinePostedCommentView` after re-fetch
- `FetchReviewCommentsUseCase.swift` — existing `cachedOnly: false` path already does what we need

## - [ ] Phase 9: Validation

**Skills to read**: `/swift-testing`, `/pr-radar-verify-work`

### Unit Tests

Add tests for the new functionality in `PRRadarModelsTests` and/or a new `PRRadarCLIServiceTests`:

1. **`CommentMetadata` serialization round-trip** — `toHTMLComment()` → `parse()` produces identical struct
2. **`CommentMetadata.parse()` edge cases** — no metadata, partial metadata, wrong version, corrupted format
3. **Updated `reconcile()` logic**:
   - Exact metadata match, same body → `.redetected`
   - Exact metadata match, different body → `.needsUpdate`
   - Line-shifted match (same blob SHA) → `.redetected`
   - File-changed (different blob SHA) → `.new`
   - v0 comment (no metadata) matched via legacy heuristic → `.needsUpdate` (upgrade)
   - v0 comment with no match → `.postedOnly`
   - Mix of v0 and v1 comments in same reconciliation
4. **`toGitHubMarkdown()` includes metadata** — verify the HTML comment is appended
5. **Comment editing** — verify `.needsUpdate` comments call PATCH instead of POST, and the updated body includes refreshed metadata

### Integration Verification

Run the CLI against the test repo to verify end-to-end:
```bash
cd PRRadarLibrary
swift run PRRadarMacCLI comment 1 --config test-repo --dry-run
```

Verify:
- Comment bodies include the hidden metadata block
- Metadata is invisible in GitHub's rendered markdown (post a test comment manually if needed)
- Re-running `comment` correctly detects redetected violations via metadata
