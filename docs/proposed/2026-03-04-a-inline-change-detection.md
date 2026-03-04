# Inline Change Detection and Paired Modification Classification

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules (placement, dependency rules) |
| `/swift-testing` | Test style guide and conventions |

## Background

PRRadar's effective diff pipeline classifies each diff line with a `ChangeKind` (`.added`, `.removed`, `.changed`, `.unchanged`). Currently, when a line is modified in place (not moved), the unified diff produces a `-` line and a `+` line. The classification assigns `.removed` and `.added` respectively — making in-place modifications **indistinguishable from genuinely new code**.

The `.changed` kind is only assigned within detected move blocks (via re-diff analysis). This means rules with `newCodeLinesOnly: true` match modified lines as if they were brand new, causing false positives. For example, changing `* parentView` to `*parentView` (whitespace-only) or adding a parameter to an existing function signature both appear as "new code."

Phase 2 of the [whitespace false-positives spec](2026-03-03-a-false-positive-whitespace-changes.md) added `buildWhitespaceOnlySet()` to handle the whitespace-only subset. This plan generalizes that approach to **all** in-place modifications and adds structured inline change data showing exactly which characters changed.

### Approach

1. **Pair `-`/`+` line runs** within hunks (sequential 1:1, matching how git pairs them)
2. **Compute inline diffs** using Swift's `CollectionDifference` (Myers algorithm, built into stdlib — no external dependencies)
3. **Store inline change spans** on `ClassifiedDiffLine` showing exactly which character ranges were inserted/deleted/unchanged
4. **Classify** paired `+` lines as `.changed` instead of `.added`; whitespace-only pairs stay `.unchanged`
5. **Replace** `buildWhitespaceOnlySet()` with the new general mechanism

### Key behavioral change

`ClassifiedHunk.newCodeLines` (filters `.added`) will no longer include in-place modifications — they become `.changed`. This is the intended fix: rules with `newCodeLinesOnly: true` should only match genuinely new lines, not modifications of existing code. `changedLines` (filters `!= .unchanged`) is unaffected since `.changed` already passes that filter.

### Files involved

| File | Change |
|------|--------|
| `PRRadarModels/EffectiveDiff/ClassifiedDiffLine.swift` | Add models, modify `classifyLines()`, remove whitespace-only functions |
| `PRRadarModels/EffectiveDiff/InlineDiff.swift` | **New** — inline diff computation using `CollectionDifference` |
| `Tests/PRRadarModelsTests/LineClassificationTests.swift` | Update existing + add new tests |

## Phases

### - [ ] Phase 1: Inline change model

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

### - [ ] Phase 2: Inline diff computation

**Skills to read**: `/swift-app-architecture:swift-architecture`

Create a pure function that computes inline change spans between two strings using Swift's built-in `CollectionDifference` (Myers diff algorithm from stdlib — no external dependencies).

**New file**: `PRRadarLibrary/Sources/services/PRRadarModels/EffectiveDiff/InlineDiff.swift`

1. `func computeInlineSpans(old: String, new: String) -> (oldSpans: [InlineChangeSpan], newSpans: [InlineChangeSpan])`
   - Converts both strings to `[Character]` arrays
   - Calls `new.difference(from: old)` to get the `CollectionDifference`
   - Walks the diff to build contiguous spans of `.equal`, `.inserted`, `.deleted` text
   - Returns spans for both the old side (equal + deleted) and new side (equal + inserted)

This is a pure function with no state — takes two strings, returns structured spans.

### - [ ] Phase 3: Paired modification detection and classification

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
   - For `.added` lines: if paired AND `spans.isWhitespaceOnly` → `changeKind = .unchanged` (preserves existing behavior); if paired AND non-trivial → `changeKind = .changed`, `inlineChanges = newSpans`
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

### - [ ] Phase 4: Validation

**Skills to read**: `/swift-testing`

1. Run `swift test` — all existing tests must pass
2. Update existing `LineClassificationTests` for cases where `.added` becomes `.changed`
3. Add new tests:
   - `computeInlineSpans()` — identical strings, completely different, partial changes (word added/removed), whitespace-only
   - Pairing logic — equal run counts, surplus removals, surplus additions, context lines separating change groups
   - `classifyLines()` integration — paired modifications get `.changed`, whitespace-only stays `.unchanged`, unpaired lines stay `.added`/`.removed`, move detection takes priority over pairing
4. Verify against PR #19024 using the local validation steps in the [parent spec](2026-03-03-a-false-positive-whitespace-changes.md#local-validation-steps)
