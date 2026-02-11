## Background

When the analysis pipeline runs multiple times on the same PR, violations that were already posted as GitHub review comments reappear as "pending" (blue) comments in the diff view. The user sees a green posted comment and an identical blue pending comment for the same violation.

The current data model treats pending and posted comments as completely separate collections (`[PRComment]` vs `[GitHubReviewComment]`), threaded through `DiffCommentMapping` as five independent dictionaries and rendered by different views. This separation makes deduplication awkward and confines the matching logic to the UI layer, where it can't be reused by the CLI for auto-commenting.

This plan introduces a `ReviewComment` model that **pairs the pending and posted state for a given rule+line together in one structure**. The model and reconciliation logic live in the **Services layer** so both the MacApp and CLI can use them. The CLI's `PostCommentsUseCase` can filter to `.new` only (skip already-posted), and the MacApp views switch rendering based on each comment's state.

### Architecture placement

```
PRRadarModels (Models layer)
  └── ReviewComment                — the unified model

PRRadarCLIService (Services layer)
  └── ViolationService             — reconcile(pending:posted:) → [ReviewComment]
  └── PRAcquisitionService         — fetches posted comments from GitHub, caches to disk
  └── PhaseOutputParser            — loads cached posted comments from disk

PRReviewFeature (Features layer)
  └── FetchReviewCommentsUseCase   — loads pending + posted, calls reconcile() → [ReviewComment]
  └── PostCommentsUseCase          — uses FetchReviewCommentsUseCase, only posts .new

MacApp (Apps layer)                — calls FetchReviewCommentsUseCase
  └── DiffCommentMapper            — maps [ReviewComment] to diff line positions (no matching logic)
  └── Views                        — render based on ReviewComment.state

MacCLI (Apps layer)                — calls FetchReviewCommentsUseCase (same use case)
```

`FetchReviewCommentsUseCase` is the shared entry point. Both the MacApp and CLI call it to get `[ReviewComment]`. It handles:
1. Loading pending violations from evaluation output on disk (via `ViolationService.loadViolations()`)
2. Loading posted comments from cached `gh-comments.json` (via `PhaseOutputParser`)
3. Reconciling them (via `ViolationService.reconcile()`)
4. Returning `[ReviewComment]`

### Key files to modify

| File | Layer | What changes |
|------|-------|-------------|
| [PRRadarModels/](PRRadarLibrary/Sources/services/PRRadarModels/) | Models | New `ReviewComment.swift` model |
| [ViolationService.swift](PRRadarLibrary/Sources/services/PRRadarCLIService/ViolationService.swift) | Services | New `reconcile()` method that matches `[PRComment]` + `[GitHubReviewComment]` → `[ReviewComment]` |
| New `FetchReviewCommentsUseCase.swift` | Features | Shared use case: loads pending + posted, reconciles, returns `[ReviewComment]` |
| [PostCommentsUseCase.swift](PRRadarLibrary/Sources/features/PRReviewFeature/usecases/PostCommentsUseCase.swift) | Features | Uses `FetchReviewCommentsUseCase`, only posts `.new` |
| [DiffCommentMapper.swift](PRRadarLibrary/Sources/apps/MacApp/UI/GitViews/DiffCommentMapper.swift) | Apps | Simplified — maps `[ReviewComment]` to diff positions, no matching |
| [RichDiffViews.swift](PRRadarLibrary/Sources/apps/MacApp/UI/GitViews/RichDiffViews.swift) | Apps | Unified `[ReviewComment]` rendering |
| [InlinePostedCommentView.swift](PRRadarLibrary/Sources/apps/MacApp/UI/GitViews/InlinePostedCommentView.swift) | Apps | Add `isRedetected` indicator |
| [InlineCommentView.swift](PRRadarLibrary/Sources/apps/MacApp/UI/GitViews/InlineCommentView.swift) | Apps | Remove `isAlreadyPostedOnGitHub` |
| [DiffPhaseView.swift](PRRadarLibrary/Sources/apps/MacApp/UI/PhaseViews/DiffPhaseView.swift) | Apps | Update helper methods for sidebar counts/badges |

## Phases

## - [x] Phase 1: Define `ReviewComment` Model in PRRadarModels

Create a new file [PRRadarModels/ReviewComment.swift](PRRadarLibrary/Sources/services/PRRadarModels/ReviewComment.swift):

```swift
public struct ReviewComment: Sendable, Identifiable {
    public let id: String
    public let pending: PRComment?
    public let posted: GitHubReviewComment?

    public enum State: Sendable {
        case new           // pending only — not yet posted
        case redetected    // both — posted and still flagged in latest analysis
        case postedOnly    // posted only — not in latest analysis
    }

    public var state: State {
        switch (pending, posted) {
        case (.some, .some): return .redetected
        case (.some, .none): return .new
        case (.none, .some): return .postedOnly
        case (.none, .none): return .postedOnly
        }
    }
}
```

This is a domain model — it belongs in PRRadarModels alongside `PRComment` and `GitHubReviewComment`, the two types it composes.

**Complication — ID uniqueness:** For `ForEach` to work, each `ReviewComment` needs a unique stable ID.
- `.new` (pending only): use `pending!.id`
- `.postedOnly` (posted only): use `posted!.id`
- `.redetected` (both): use `"matched-\(posted!.id)"` — the GitHub ID is stable across refreshes whereas the pending ID changes each analysis run

**Convenience accessors** (needed by downstream consumers):
```swift
public var filePath: String { pending?.filePath ?? posted?.path ?? "" }
public var lineNumber: Int? { pending?.lineNumber ?? posted?.line }
public var score: Int? { pending?.score }
public var ruleName: String? { pending?.ruleName }
```

**Completed.** `id` is a computed property (not stored) to derive the correct value per state. Build verified.

## - [x] Phase 2: Add Reconciliation to `ViolationService`

Add a new method to [ViolationService.swift](PRRadarLibrary/Sources/services/PRRadarCLIService/ViolationService.swift) that takes pending violations and posted comments and returns reconciled `[ReviewComment]`:

```swift
public static func reconcile(
    pending: [PRComment],
    posted: [GitHubReviewComment]
) -> [ReviewComment]
```

### Matching algorithm

1. **Index posted comments** into a mutable working dictionary keyed by `(filePath, lineNumber)`. For file-level comments (no line), key by `(filePath, nil)`.
2. **Iterate pending comments:**
   - Look up posted comments at the same (file, line).
   - **Matching heuristic:** `posted.path == pending.filePath && posted.line == pending.lineNumber && posted.body.contains(pending.ruleName)` (same as existing `isAlreadyPostedOnGitHub`).
   - If matched: create `ReviewComment(pending:, posted:)` → `.redetected`. **Remove the posted comment from the working set** so it isn't matched again.
   - If no match: create `ReviewComment(pending:, posted: nil)` → `.new`.
3. **Collect remaining unmatched posted** → create `ReviewComment(pending: nil, posted:)` → `.postedOnly`.

**Complication — multiple pending matching one posted:** If two pending comments at the same line have different rules but the posted body happens to `contains()` both rule names, only the first should match. Removing matched posted comments from the working set (step 2) ensures each is consumed exactly once.

**Complication — file-level matching:** For pending comments with no line number, match against posted comments also with no line number for the same file. Same `body.contains(ruleName)` heuristic.

This method is a pure transformation — no I/O, no side effects. Easy to unit test.

**Completed.** Implemented as a static method on `ViolationService` using a `[String: [Int?: [GitHubReviewComment]]]` working dictionary keyed by `(path, line)`. The `Int?` key naturally handles file-level (nil line) matching. 12 unit tests added in `ViolationReconciliationTests.swift` covering all spec scenarios. Build and all 330 tests pass.

## - [x] Phase 3: Add `FetchReviewCommentsUseCase` (Features layer)

New file: `PRRadarLibrary/Sources/features/PRReviewFeature/usecases/FetchReviewCommentsUseCase.swift`

This is the shared entry point that both the MacApp and CLI use to get reconciled `[ReviewComment]`. It orchestrates loading from disk and reconciliation:

```swift
public struct FetchReviewCommentsUseCase: Sendable {
    private let config: PRRadarConfig

    public init(config: PRRadarConfig) {
        self.config = config
    }

    public func execute(prNumber: String, minScore: Int = 5) -> [ReviewComment] {
        let prOutputDir = "\(config.absoluteOutputDir)/\(prNumber)"

        // Load pending violations from evaluation output
        let evalsDir = "\(prOutputDir)/\(PRRadarPhase.evaluations.rawValue)"
        let tasksDir = "\(prOutputDir)/\(PRRadarPhase.tasks.rawValue)"
        let pending = ViolationService.loadViolations(
            evaluationsDir: evalsDir,
            tasksDir: tasksDir,
            minScore: minScore
        )

        // Load posted comments from cached gh-comments.json
        let posted: [GitHubReviewComment] = (try? PhaseOutputParser.parsePhaseOutput(
            config: config,
            prNumber: Int(prNumber) ?? 0,
            phase: .pullRequest,
            filename: "gh-comments.json"
        ) as GitHubPullRequestComments)?.reviewComments ?? []

        return ViolationService.reconcile(pending: pending, posted: posted)
    }
}
```

Both `PostCommentsUseCase` and the MacApp's `PRModel`/`DiffPhaseView` call this use case instead of loading pending and posted separately.

**Completed.** Implemented as specified. The use case is synchronous (no `AsyncThrowingStream`) since all data comes from disk — follows the same simple return pattern as `LoadExistingOutputsUseCase`. The `PhaseOutputParser.parsePhaseOutput` call uses `prNumber: String` (matching the actual API, not `Int` as shown in the pseudocode above). Build verified.

## - [x] Phase 4: Simplify `DiffCommentMapper` (Apps layer)

The mapper no longer does any pending/posted matching. It just maps `[ReviewComment]` to diff line positions for the view hierarchy.

### New `DiffCommentMapping`

Replace the current 5-field struct:

```swift
// BEFORE (5 fields, split by pending vs posted)
struct DiffCommentMapping {
    let commentsByFileAndLine: [String: [Int: [PRComment]]]
    let unmatchedByFile: [String: [PRComment]]
    let unmatchedNoFile: [PRComment]
    let postedByFileAndLine: [String: [Int: [GitHubReviewComment]]]
    let postedUnmatchedByFile: [String: [GitHubReviewComment]]
}

// AFTER (3 fields, unified)
struct DiffCommentMapping {
    let byFileAndLine: [String: [Int: [ReviewComment]]]
    let unmatchedByFile: [String: [ReviewComment]]
    let unmatchedNoFile: [ReviewComment]
}
```

### Rewritten `DiffCommentMapper.map()`

Input changes from `comments: [PRComment], postedReviewComments: [GitHubReviewComment]` to just `comments: [ReviewComment]` (already reconciled). The method only does diff-position mapping:

1. For each `ReviewComment`, check if its file is in the diff.
2. If yes and has a line number matching a hunk → `byFileAndLine`.
3. If yes but no hunk match (or no line number) → `unmatchedByFile`.
4. If file not in diff → `unmatchedNoFile`.

**Complication — ordering within a line:** Sort each line's array: `.postedOnly` first, then `.redetected`, then `.new`. Preserves the current UI order (green posted above blue pending).

**Completed.** Simplified `DiffCommentMapping` from 5 fields to 3, and `DiffCommentMapper.map()` from two input arrays to one `[ReviewComment]`. Also updated the downstream consumers required for compilation: `AnnotatedHunkContentView` and `AnnotatedDiffContentView` now render via a state-based switch on `ReviewComment.state`, and two separate file-level section helpers (`postedFileLevelSection` + `unmatchedSection`) were merged into one `fileLevelSection`. `DiffPhaseView` updated to accept `reviewComments: [ReviewComment]` (non-optional, defaults to `[]`), with helper methods (`filesWithViolationCounts`, `maxSeverity`, `postedCommentCountsByFile`) filtering by `.state`. `PRModel` gained a `reconciledComments` computed property that calls `ViolationService.reconcile()`. Build and all 330 tests pass.

## - [x] Phase 5: Update View Hierarchy (`RichDiffViews.swift`)

### `AnnotatedHunkContentView`

Replace two separate params with one:

```swift
// BEFORE
let commentsAtLine: [Int: [PRComment]]
let postedAtLine: [Int: [GitHubReviewComment]]

// AFTER
let commentsAtLine: [Int: [ReviewComment]]
```

Replace the two separate rendering blocks with a single state-based switch:

```swift
if let comments = commentsAtLine[newLine] {
    ForEach(comments) { rc in
        switch rc.state {
        case .new:
            if let prModel {
                InlineCommentView(comment: rc.pending!, prModel: prModel)
            }
        case .redetected:
            InlinePostedCommentView(
                comment: rc.posted!, isRedetected: true,
                imageURLMap: imageURLMap, imageBaseDir: imageBaseDir
            )
        case .postedOnly:
            InlinePostedCommentView(
                comment: rc.posted!,
                imageURLMap: imageURLMap, imageBaseDir: imageBaseDir
            )
        }
    }
}
```

### `AnnotatedDiffContentView`

**Complication — merging file-level sections:** Currently has two separate helper methods:
- `postedFileLevelSection(_ comments: [GitHubReviewComment])` — green background
- `unmatchedSection(_ comments: [PRComment], title: String)` — orange background

With unified model, replace both with a single `fileLevelSection(_ comments: [ReviewComment])` that renders each `ReviewComment` by state (same switch pattern).

The call site simplifies from:

```swift
if let postedUnmatched = commentMapping.postedUnmatchedByFile[filePath] {
    postedFileLevelSection(postedUnmatched)
}
if let unmatched = commentMapping.unmatchedByFile[filePath] {
    unmatchedSection(unmatched, title: "File-level comments")
}
```

To:

```swift
if let fileLevel = commentMapping.unmatchedByFile[filePath], !fileLevel.isEmpty {
    fileLevelSection(fileLevel)
}
```

**Completed.** The structural changes (unified `[ReviewComment]` params, single state-based switch, merged `fileLevelSection`) were done in Phase 4 for compilation. This phase added the `isRedetected` distinction: `.redetected` comments now pass `isRedetected: true` to `InlinePostedCommentView`, which shows an orange "Still detected in latest analysis" label. The `isRedetected: Bool = false` property was added to `InlinePostedCommentView` with a default so existing call sites are unaffected. Build verified.

## - [x] Phase 6: Update `DiffPhaseView` Helpers

These helpers in [DiffPhaseView.swift](PRRadarLibrary/Sources/apps/MacApp/UI/PhaseViews/DiffPhaseView.swift) access fields on the old `DiffCommentMapping`. Update them to work with `ReviewComment`:

**`DiffPhaseView` inputs** — the view currently takes `comments: [PRComment]?` and `postedReviewComments: [GitHubReviewComment]`. These can be replaced with `reviewComments: [ReviewComment]?` (provided by the caller via `FetchReviewCommentsUseCase`). Or the view can call the use case itself.

**`commentMapping(for:)`** — passes already-reconciled `[ReviewComment]` to the mapper:

```swift
private func commentMapping(for diff: GitDiff) -> DiffCommentMapping {
    DiffCommentMapper.map(diff: diff, comments: reviewComments ?? [])
}
```

**`filesWithViolationCounts`** — count only `.new` state:
```swift
counts += comments.filter { $0.state == .new }.count
```

**`postedCommentCountsByFile`** — count `.postedOnly` + `.redetected`:
```swift
counts += comments.filter { $0.state != .new }.count
```

**`maxSeverity`** — use `ReviewComment.score`, only consider `.new` comments.

**`filesNotInDiff`** — use `ReviewComment.filePath` accessor.

**Completed.** All changes were implemented during Phase 4 for compilation. `DiffPhaseView` accepts `reviewComments: [ReviewComment]` (non-optional, defaults to `[]`). The caller (`ReviewDetailView`) passes `prModel.reconciledComments`. All helper methods already filter by `.state`: `filesWithViolationCounts` counts `.new` only, `postedCommentCountsByFile` counts non-`.new`, `maxSeverity` considers `.new` only, and `filesNotInDiff` uses `ReviewComment.filePath`. Build verified.

## - [x] Phase 7: Add "Still Detected" Indicator + Cleanup

### `InlinePostedCommentView` ([InlinePostedCommentView.swift](PRRadarLibrary/Sources/apps/MacApp/UI/GitViews/InlinePostedCommentView.swift))

Add `var isRedetected: Bool = false` (default false for backward compatibility). When true, render in the header HStack between the date and "View on GitHub" link:

```swift
if isRedetected {
    Label("Still detected in latest analysis", systemImage: "arrow.trianglehead.2.counterclockwise")
        .font(.caption2)
        .foregroundStyle(.orange)
}
```

### `InlineCommentView` ([InlineCommentView.swift](PRRadarLibrary/Sources/apps/MacApp/UI/GitViews/InlineCommentView.swift))

Remove `isAlreadyPostedOnGitHub` computed property entirely — deduplication is now handled in `ViolationService.reconcile()`. Simplify `isSubmitted`:

```swift
// BEFORE
private var isSubmitted: Bool {
    prModel.submittedCommentIds.contains(comment.id) || isAlreadyPostedOnGitHub
}

// AFTER
private var isSubmitted: Bool {
    prModel.submittedCommentIds.contains(comment.id)
}
```

**Completed.** The `isRedetected` indicator on `InlinePostedCommentView` was already added in Phase 5. This phase removed the `isAlreadyPostedOnGitHub` computed property from `InlineCommentView` and simplified `isSubmitted` to only check `submittedCommentIds` — deduplication is now fully handled by `ViolationService.reconcile()` in the Services layer. Build and all 330 tests pass.

## - [x] Phase 8: Validation

**Automated:**
```bash
cd pr-radar-mac
swift build
swift test
```

**Unit tests for `ViolationService.reconcile()`:**
- Pending only → all `.new`
- Posted only → all `.postedOnly`
- Matching pending + posted → `.redetected`, pending hidden
- Multiple pending, one posted → only first match consumed
- File-level (no line number) matching
- No false matches when rule names don't match

**Manual — verify deduplication in MacApp:**
1. Run analysis: `swift run PRRadarMacCLI analyze 1 --config test-repo`
2. Open MacApp, post a comment on a violation via the Submit button
3. Refresh: `swift run PRRadarMacCLI refresh-pr 1 --config test-repo`
4. Run analysis again: `swift run PRRadarMacCLI analyze 1 --config test-repo`
5. Verify in MacApp diff view:
   - The duplicate pending (blue) comment is gone
   - The posted (green) comment shows "Still detected in latest analysis" in orange
   - Sidebar violation count excludes the deduplicated violation
   - New violations (not previously posted) still show as blue pending comments

**Manual — verify no-evaluation mode still works:**
1. Open a PR in MacApp that has posted comments but no evaluation data
2. Verify posted comments still render normally (green, no indicator)
3. Verify the diff view works without evaluation data (plain diff, no comment annotations)

**Completed.** Build succeeds and all 330 tests pass across 43 suites. The 12 unit tests in `ViolationReconciliationTests.swift` cover all specified reconciliation scenarios: pending-only (`.new`), posted-only (`.postedOnly`), matched (`.redetected`), multiple-pending-one-posted consumption, file-level nil-line matching, and no-false-match guards for differing rule names, file paths, and line numbers. Manual verification (MacApp dedup, no-evaluation mode) deferred to user.

## - [x] Phase 9: CLI Round-Trip Validation (Post + Fetch)

Verify the full post-then-fetch cycle works end-to-end from the CLI against https://github.com/gestrich/PRRadar-TestRepo/pull/1.

1. Run analysis to generate violations: `swift run PRRadarMacCLI analyze 1 --config test-repo`
2. Post a comment via the CLI: `swift run PRRadarMacCLI comment 1 --config test-repo`
3. Refresh to pull posted comments from GitHub: `swift run PRRadarMacCLI refresh-pr 1 --config test-repo`
4. Run analysis again: `swift run PRRadarMacCLI analyze 1 --config test-repo`
5. Verify reconciliation output:
   - The violation that was just posted should come back as `.redetected` (not `.new`)
   - `PostCommentsUseCase` should skip it (already posted)
   - Any new violations not yet posted should remain `.new`
6. Inspect the cached `gh-comments.json` to confirm the posted comment data matches what was sent

**Completed.** Updated `PostCommentsUseCase` to use `FetchReviewCommentsUseCase` for reconciliation — it now loads all `ReviewComment`s, filters to `.new` only for posting, and reports `.redetected` as skipped. Added `skipped` field to `CommentPhaseOutput` (with default `0` for backward compatibility). Updated `CommentCommand` to display skip counts. Validated against test repo PR #1: the `guard-divide-by-zero` violation at `Calculator.swift:19` was correctly matched as `.redetected` against the posted GitHub comment, and the CLI reported "Skipping 1 already-posted comments" / "All violations already posted — nothing new to comment." Build and all 330 tests pass.

## - [x] Phase 10: Line-Shift Investigation (Stale Line Numbers)

Test what happens to posted comment line numbers when the diff changes underneath them. This determines whether `reconcile()` needs to account for shifted lines or if GitHub metadata already handles it.

1. Note the line number of a posted comment from Phase 9 (e.g., line 42 of `some-file.swift`)
2. In the test repo, push a commit that adds content **above** the violation area (e.g., add 5 blank lines at the top of the file), shifting the violation code downward
3. Refresh to pull updated comment data: `swift run PRRadarMacCLI refresh-pr 1 --config test-repo`
4. Inspect the fetched `gh-comments.json` for the previously-posted comment:
   - Does `line` still reflect the **original** line number when posted, or the **new** line number after the shift?
   - Does GitHub provide additional metadata (e.g., `original_line` vs `line`, `original_start_line` vs `start_line`, `position`, or `diff_hunk`) that distinguishes the two?
5. Run analysis again on the updated diff: `swift run PRRadarMacCLI analyze 1 --config test-repo`
6. Check whether `reconcile()` correctly matches the shifted pending violation (now at line 47) against the posted comment (which may still say line 42):
   - If GitHub updates `line` to the new position → matching works as-is
   - If GitHub keeps the original `line` → the matching heuristic needs adjustment (e.g., fall back to `body.contains(ruleName)` for same-file matches regardless of line, or use `diff_hunk` context)
7. Document findings — this may surface a follow-up task to improve the matching heuristic for line drift

**Completed.** Investigated against PR #1 (`Calculator.swift`, `guard-divide-by-zero` at original line 19).

### Findings

**GitHub updates `line` automatically.** When a commit shifts code, GitHub's API returns:
- `line: 26` (updated to reflect the new position after the shift)
- `original_line: 19` (preserved from when the comment was first posted)
- `commit_id` updated to the latest commit; `original_commit_id` preserved

However, **the AI evaluator reports stale line numbers.** When re-analyzing the updated diff, the Claude evaluator returned `line_number: 19` (the line number from the diff context, not the actual file line). This creates a mismatch: pending says line 19, posted says line 26 — `reconcile()` with exact `(file, line)` matching fails to find the match.

### Fix: Two-Pass Matching with Fuzzy Fallback

Updated `ViolationService.reconcile()` to use a two-pass strategy per pending comment:

1. **Pass 1 (exact):** Same file, same line, body contains rule name — unchanged from before
2. **Pass 2 (fuzzy):** Same file, **any** line, body contains rule name — new fallback for line drift

Constraints on the fuzzy fallback:
- Only activates when Pass 1 finds no match
- Only applies to line-specific comments (`lineNumber != nil`) — file-level comments (nil line) must match exactly
- Only considers line-specific posted comments (`line != nil`) — prevents file-level posted comments from being consumed by line-specific pending
- Still requires `body.contains(ruleName)` — prevents false matches across different rules

3 new unit tests added for the fuzzy fallback: exact-preferred-over-fuzzy, no-false-match-with-different-rules, and no-match-across-different-files. The existing "no match when line number differs" test was updated to "same file + same rule matches even when line number differs (line drift)". Build and all 333 tests pass.
