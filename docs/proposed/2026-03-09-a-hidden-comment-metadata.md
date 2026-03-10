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

## Phases

## - [ ] Phase 1: Define Comment Metadata Model

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

## - [ ] Phase 2: Embed Metadata When Posting Comments

**Skills to read**: `/swift-app-architecture:swift-architecture`

Update the comment posting flow to append metadata to each comment body:

1. **`PRComment`** — add fields needed for metadata: `prHeadSHA`, `fileBlobSHA`, `ruleHash`
2. **`PRComment.toGitHubMarkdown()`** — append `CommentMetadata.toHTMLComment()` to the end of the rendered markdown
3. **`CommentService.postViolations()`** — already fetches `commitSHA` (the PR head); pass it through to `PRComment` or construct metadata at posting time
4. **Populate `fileBlobSHA`** — use `git ls-tree <commit> <filepath>` (via existing `GitService`) to get the blob SHA for each file being commented on. Or alternatively, fetch it from the GitHub API.
5. **Populate `ruleHash`** — `RuleRequest` already has `ruleBlobHash` (optional). Ensure this flows through to `PRComment`.

Files to modify:
- `PRRadarModels/PRComment.swift` — add metadata fields, update `toGitHubMarkdown()`
- `PRRadarCLIService/CommentService.swift` — construct metadata, pass commit info
- Possibly `PRReviewFeature/usecases/PostCommentsUseCase.swift` — thread new data through

## - [ ] Phase 3: Parse Metadata from Posted Comments

**Skills to read**: `/swift-app-architecture:swift-architecture`

Update the reconciliation input path to extract metadata from existing GitHub comments:

1. **`GitHubReviewComment`** — add a computed property `metadata: CommentMetadata?` that calls `CommentMetadata.parse(from: body)`
2. **`FetchReviewCommentsUseCase`** — no changes needed if metadata is computed from body

Files to modify:
- `PRRadarModels/GitHubModels.swift` — add computed `metadata` property
- `PRRadarModels/CommentMetadata.swift` — ensure `parse()` handles edge cases (no metadata, malformed, wrong version)

## - [ ] Phase 4: Upgrade Reconciliation Logic

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

## - [ ] Phase 5: Add GitHub Comment Edit API Support

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

## - [ ] Phase 6: Populate File Blob SHA

**Skills to read**: `/swift-app-architecture:swift-architecture`

Add capability to resolve the git blob SHA for a file at a given commit. This is needed to detect whether a file's content changed between the commit a comment was posted on and the current PR head.

Options:
- **Git CLI**: `git ls-tree <commit> -- <filepath>` → parse blob SHA from output
- **GitHub API**: `GET /repos/{owner}/{repo}/git/trees/{sha}` — more complex, may need recursive calls

Prefer the git CLI approach since PRRadar already shells out to git extensively via `GitService`.

Files to modify:
- `PRRadarMacSDK` or `PRRadarCLIService/GitService.swift` — add `blobSHA(for:at:)` method
- Wire into the comment posting flow from Phase 2

## - [ ] Phase 7: Validation

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
