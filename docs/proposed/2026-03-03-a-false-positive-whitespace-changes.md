# Investigation: False Positive on Whitespace-Only Line Changes

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules (placement, dependency rules) |
| `/swift-testing` | Test style guide and conventions |

## Background

PR #19024 in ff-ios was flagged by the `nullability-h-objc` regex rule on line R27 of `RouteTokenDelegateDataSource.h`:

```objc
@property (weak) RouteEditIPadView *parentView;
```

This line lacks a nullability annotation, so the regex pattern matched. However, the line was **not genuinely new** — it was a whitespace-only modification. The base branch had `* parentView` (space before variable name) and the head had `*parentView` (no space). The declaration itself was unchanged.

### Root Cause Analysis

The investigation revealed **four separate issues**:

#### Issue 1: Stale local refs — PRRadar did not fetch before diffing (FIXED)

The initial hypothesis was that PRRadar diffed per-commit rather than merge-base → head. This was **incorrect**. The code already uses `git diff origin/{base}...origin/{head}` (three-dot diff), which IS a full PR diff equivalent to GitHub's "Files changed" view.

The actual problem: `LocalGitHistoryProvider.getRawDiff()` ran `git diff` against **stale local remote-tracking refs** without fetching first. If commits were pushed after the last `git fetch`, the local `origin/{head}` pointed to an older commit — so changes from newer commits (like the whitespace reformatting) were missing from the diff.

This explains why the parentView whitespace change appeared on GitHub but not in the app: the local `origin/{head}` hadn't been updated to include the commit that reformatted the spacing.

**Fix applied**: Added `git fetch` for both base and head branches in `LocalGitHistoryProvider.getRawDiff()` before computing the diff. Verified against the test repo — both branches are now fetched and the diff matches GitHub's output.

Evidence:
- `LocalGitHistoryProvider.getRawDiff()` had no fetch calls (confirmed via grep)
- After adding fetch, sync output shows both branches being fetched before diff
- `gh pr diff 19024` confirms the full diff includes `-@property (weak) RouteEditIPadView * parentView;` / `+@property (weak) RouteEditIPadView *parentView;`

#### Issue 2: Whitespace-only changes are treated as genuinely new code

The parentView line is an **in-place modification** — the removed and added lines appear in the same hunk, same file, same location. It is NOT a move. The only difference is whitespace formatting.

**How classification works for non-moved lines:**

The `classifyLines()` function in `ClassifiedDiffLine.swift` processes each diff line through a chain of checks. The move-detection infrastructure (effective diff pipeline, `findExactMatches()`, `findMoveCandidates()`, re-diff analysis) is **only relevant when moves are detected**. When `effectiveResults` is empty (no moves), the move lookup tables (`sourceMovedLines`, `targetMovedLines`, `addedInMoveLines`, `changedInMoveLines`) are all empty dictionaries and every check against them returns false.

For non-moved lines, classification reduces to:
- `.removed` diff lines → `changeKind = .removed`
- `.added` diff lines → `changeKind = .added`
- `.context` diff lines → `changeKind = .unchanged`

The `.changed` changeKind is **only assigned inside moved blocks** (via `changedInMoveLines`). A normal in-place modification (like changing `* parentView` to `*parentView`) shows up in the unified diff as a `-` line followed by a `+` line, classified as `.removed` + `.added` respectively.

**Why the false positive occurs:**

1. The raw diff has `-@property (weak) RouteEditIPadView * parentView;` and `+@property (weak) RouteEditIPadView *parentView;`
2. The `+` line hits the final else in `classifyLines()`: `changeKind = .added, inMovedBlock = false`
3. Downstream, `relevantLines(newCodeLinesOnly: true)` filters to only `.added` lines
4. The regex rule matches this "added" line → false positive

Note: `findExactMatches()` uses `normalize()` which only trims leading/trailing whitespace. The `* parentView` vs `*parentView` difference is *interior* whitespace, so these lines are NOT considered exact matches by the existing normalization. Even if they were, `findMoveCandidates()` requires `minBlockSize = 3`, so a single matched line wouldn't qualify as a move candidate.

**Downstream data flow:**

```
classifiedHunks (from diff phase, written to classified-hunks.json)
  → loaded by PhaseOutputParser.loadAnnotatedDiff()
  → passed to AnalyzeSingleTaskUseCase
  → ClassifiedHunk.filterForFocusArea() narrows to relevant hunks
  → relevantLines(newCodeLinesOnly: rule.newCodeLinesOnly)
    → newCodeLinesOnly: true  → only .added lines (newCodeLines)
    → newCodeLinesOnly: false → all non-.unchanged lines (changedLines)
  → RegexAnalysisService / ScriptAnalysisService check those lines
```

#### Issue 3: Silent fallback on effective diff pipeline failure

During investigation, we discovered that when `git merge-base` fails (e.g., the commit isn't fetched locally), the effective diff pipeline **silently returns empty classified hunks** instead of erroring. This means:
- `classified-hunks.json` contains `[]` (0 hunks) even though the diff has 51 hunks
- The analyze step finds 0 tasks and reports "No tasks to evaluate"
- No error is shown to the user

This was caused by the commit not existing locally (`git merge-base origin/develop e0ff387` → "fatal: Not a valid commit name"). After `git fetch origin e0ff387`, the pipeline works correctly.

#### Issue 4: All in-place modifications are treated as genuinely new code

The whitespace-only fix (Issue 2) handles one special case, but the underlying problem is broader: **any** in-place modification — variable renames, added parameters, type changes — is classified as `.removed` + `.added`. The `.changed` changeKind only exists within detected move blocks (via re-diff analysis).

This means a line like `function foo(x, y) {` changed to `function foo(x, y, z) {` shows up as genuinely new code. Rules with `newCodeLinesOnly: true` will match it, even though it's a modification of existing code, not a new line.

The fix: generalize the whitespace-only detection into a full **paired modification detector** that:
1. Matches `-`/`+` line pairs within hunks (sequential 1:1 pairing, same as git)
2. Computes **inline diffs** using Swift's `CollectionDifference` (Myers algorithm, stdlib) to show exactly which characters changed
3. Classifies paired `+` lines as `.changed` instead of `.added`
4. Subsumes whitespace-only detection — whitespace-only becomes a derivable property from the inline diff spans

This gives downstream consumers structured data about what parts of a line changed (character ranges of insertions/deletions), enabling smarter rule evaluation and UI highlighting.

### Diff Source Behavior

Both diff sources now produce the full PR diff (merge-base → head):
- `diff source: git` — runs `git diff origin/{base}...origin/{head}` after fetching both branches
- `diff source: github-api` — calls GitHub REST API with `Accept: application/vnd.github.v3.diff`

These should produce equivalent output. The stale-refs issue (Issue 1) has been fixed.

## Phases

### - [x] Phase 1: Fix stale local refs (COMPLETED)

Added `git fetch` for both base and head branches in `LocalGitHistoryProvider.getRawDiff()` before computing the diff. This ensures `diff source: git` always uses up-to-date remote-tracking refs, matching what GitHub shows.

**Change**: `PRRadarLibrary/Sources/services/PRRadarCLIService/LocalGitHistoryProvider.swift`

### - [x] Phase 2: Exclude whitespace-only modifications (VALIDATED)

**Decision**: Option B — exclude whitespace-only modifications from being classified as new code.

**Implementation**: Added `buildWhitespaceOnlySet()` in `ClassifiedDiffLine.swift`. This function scans each hunk for removed/added line pairs that differ only in whitespace (using `collapseWhitespace()` which strips ALL whitespace, not just leading/trailing). Matched added lines are classified as `changeKind = .unchanged` instead of `.added`, so they're excluded from both `newCodeLinesOnly: true` and `newCodeLinesOnly: false` rule checks.

The check is inserted in `classifyLines()` after all move-related checks and before the final `.added` fallthrough. This means move detection takes priority — if a line is part of a detected move, it uses the move classification. Only non-moved lines are checked for whitespace-only modifications.

**Changes**:
- `PRRadarLibrary/Sources/services/PRRadarModels/EffectiveDiff/ClassifiedDiffLine.swift` — added `buildWhitespaceOnlySet()`, `collapseWhitespace()`, and whitespace check branch in `classifyLines()`

**Validation result against PR #19024**:
- `@property (weak) RouteEditIPadView *parentView;` → `changeKind = unchanged` (was `added`) — false positive eliminated
- `- (nonnull instancetype)initWithTripSummary:...` → `changeKind = added` — genuinely new code still caught
- `RouteTokenDelegateDataSource.h — nullability-h-objc` → OK (no longer flagged)
- 6 real violations still detected in `.m` files
- All 636 existing tests pass

### - [ ] Phase 3: Fix silent fallback on pipeline failure

**Skills to read**: `/swift-app-architecture:swift-architecture`

The effective diff pipeline silently returns empty classified hunks when `git merge-base` fails. This should either:
1. Log a warning so the user knows classification was skipped
2. Fall back to classifying all diff lines from the raw diff (every `+` line → `.added`, every `-` line → `.removed`, context → `.unchanged`) instead of returning empty
3. Both

Location: `PRAcquisitionService.runEffectiveDiff()` catch block (line ~330).

### - [ ] Phase 4: Validation

**Skills to read**: `/swift-testing`

1. If any code changes are made, run `swift test` to verify existing tests pass
2. Add a test case for whitespace-only modifications
3. Verify the fix against PR #19024 using the steps below
4. Confirm the parentView line is not flagged while genuinely new lines (like the `_Nonnull` additions) are still caught

### - [ ] Phase 5: Inline change model

**Skills to read**: `/swift-app-architecture:swift-architecture`

Add the data model for representing character-level inline changes within a line.

**Changes** in `PRRadarLibrary/Sources/services/PRRadarModels/EffectiveDiff/ClassifiedDiffLine.swift`:

1. Add `InlineChangeKind` enum with cases `.equal`, `.inserted`, `.deleted` (Codable, Sendable, Equatable)
2. Add `InlineChangeSpan` struct with `kind: InlineChangeKind` and `text: String` — represents a contiguous span of characters that are equal, inserted, or deleted
3. Add `inlineChanges: [InlineChangeSpan]?` field to `ClassifiedDiffLine` (default `nil` for backward compatibility — all existing call sites compile unchanged)
4. Add `isWhitespaceOnly` computed property on `[InlineChangeSpan]` — returns `true` when all non-equal spans contain only whitespace characters

Example representation:
```
Old: "function foo(x, y) {"
New: "function foo(x, y, z) {"
New-side spans: [equal("function foo(x, y"), inserted(", z"), equal(") {")]
```

### - [ ] Phase 6: Inline diff computation

**Skills to read**: `/swift-app-architecture:swift-architecture`

Create a pure function that computes inline change spans between two strings using Swift's built-in `CollectionDifference` (Myers diff algorithm from stdlib — no external dependencies).

**New file**: `PRRadarLibrary/Sources/services/PRRadarModels/EffectiveDiff/InlineDiff.swift`

1. `func computeInlineSpans(old: String, new: String) -> (oldSpans: [InlineChangeSpan], newSpans: [InlineChangeSpan])`
   - Converts both strings to `[Character]` arrays
   - Calls `new.difference(from: old)` to get the `CollectionDifference`
   - Walks the diff to build contiguous spans of `.equal`, `.inserted`, `.deleted` text
   - Returns spans for both the old side (equal + deleted) and new side (equal + inserted)

This is a pure function with no state — takes two strings, returns structured spans.

### - [ ] Phase 7: Paired modification detection and classification

**Skills to read**: `/swift-app-architecture:swift-architecture`

Wire the inline diff into the classification pipeline. This replaces `buildWhitespaceOnlySet()` with a general paired modification detector.

**Changes** in `PRRadarLibrary/Sources/services/PRRadarModels/EffectiveDiff/ClassifiedDiffLine.swift`:

1. Add `PairedModification` struct holding old/new line numbers and computed inline spans
2. Add `buildPairedModifications(from:)` function:
   - Walk each hunk and identify consecutive runs of removed lines followed by added lines ("change groups")
   - Pair them 1:1 sequentially (removed[0]↔added[0], removed[1]↔added[1], etc.)
   - Surplus lines (when counts differ) remain unpaired
   - For each pair, call `computeInlineSpans()` to get character-level diff
   - Return lookup keyed by `[filePath: [lineNumber: PairedModification]]` for both old and new sides
3. Modify `classifyLines()` to use paired modifications:
   - Replace `buildWhitespaceOnlySet()` call with `buildPairedModifications()`
   - For `.removed` lines: if paired → `changeKind = .changed`, `inlineChanges = oldSpans`
   - For `.added` lines: if paired AND `spans.isWhitespaceOnly` → `changeKind = .unchanged` (preserves Phase 2 behavior); if paired AND non-trivial → `changeKind = .changed`, `inlineChanges = newSpans`
   - Move checks still take priority (checked first in the chain)
4. Delete `buildWhitespaceOnlySet()` and `collapseWhitespace()` — subsumed by the new mechanism

**Classification priority (`.added` lines) after change:**
```
1. addedInMoveLines       → (.added, inMovedBlock: true)
2. changedInMoveLines     → (.changed, inMovedBlock: true)
3. targetMovedLines       → (.unchanged, inMovedBlock: true)
4. paired (whitespace-only) → (.unchanged, inMovedBlock: false, inlineChanges: spans)
5. paired (non-trivial)     → (.changed, inMovedBlock: false, inlineChanges: spans)  ← NEW
6. fallthrough              → (.added, inMovedBlock: false)
```

**Key behavioral change**: `ClassifiedHunk.newCodeLines` (filters `.added`) will no longer include in-place modifications — they become `.changed`. This is the intended fix: rules with `newCodeLinesOnly: true` should only match genuinely new lines, not modifications of existing code. `changedLines` (filters `!= .unchanged`) is unaffected since `.changed` already passes that filter.

### - [ ] Phase 8: Validation

**Skills to read**: `/swift-testing`

1. Run `swift test` — all existing tests must pass
2. Update existing `LineClassificationTests` for cases where `.added` becomes `.changed`
3. Add new tests:
   - `computeInlineSpans()` — identical strings, completely different, partial changes (word added/removed), whitespace-only
   - Pairing logic — equal run counts, surplus removals, surplus additions, context lines separating change groups
   - `classifyLines()` integration — paired modifications get `.changed`, whitespace-only stays `.unchanged`, unpaired lines stay `.added`/`.removed`, move detection takes priority over pairing
4. Verify against PR #19024 using the local validation steps below

## Local Validation Steps

Use `--mode regex` to skip Claude API calls — it only runs regex-based rules and is much faster for iteration.

```bash
# 1. Delete cached analysis data so the pipeline re-runs from scratch
rm -rf ~/Desktop/code-reviews/19024

# 2. Build
cd PRRadarLibrary && swift build

# 3. Run phases in order — analyze alone skips earlier phases if metadata is cached
swift run PRRadarMacCLI sync 19024 --config ios
swift run PRRadarMacCLI prepare 19024 --config ios
swift run PRRadarMacCLI analyze 19024 --config ios --mode regex

# 4. Inspect classified hunks to verify parentView is now changeKind=unchanged
python3 -c "
import json
with open('$(ls ~/Desktop/code-reviews/19024/analysis/*/diff/classified-hunks.json)') as f:
    hunks = json.load(f)
for h in hunks:
    for line in h.get('lines', []):
        if 'parentView' in line.get('content', '') and line.get('lineType') in ('added', 'removed'):
            print(f'{line[\"lineType\"]:8} | changeKind={line[\"changeKind\"]:10} | {line[\"content\"][:80]}')
"
```

The `--config ios` flag uses the saved "ios" configuration pointing to the local ff-ios checkout. The `--mode regex` flag skips Claude API calls and only runs regex-based rules — much faster for iteration. Run phases in order (`sync` → `prepare` → `analyze`) since `analyze` alone may skip phases if it finds partial cached data.
