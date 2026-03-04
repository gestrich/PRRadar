# Inline Change Detection

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules (placement, dependency rules) |
| `/swift-testing` | Test style guide and conventions |

## Background

`PRLine` already has an `inlineChanges: [InlineChangeSpan]?` field, but it is never populated — it's always `nil`. This plan adds the computation that populates it with character-level inline change data for paired modifications.

**Prerequisite**: [Paired Modification Classification](2026-03-04-b-paired-modification-classification.md) must be completed first. That spec introduces `buildPairedModifications()` which identifies `-`/`+` line pairs within hunks and classifies them as `.changed`. This spec builds on that pairing infrastructure to compute **what** changed within each paired line.

### Approach

1. **Compute inline diffs** using Swift's `CollectionDifference` (Myers algorithm, built into stdlib — no external dependencies)
2. **Store inline change spans** on `PRLine.inlineChanges` showing exactly which character ranges were inserted or deleted
3. **Optionally replace** the whitespace-only check in `buildPairedModifications()` with a span-based `isWhitespaceOnly` check

### Existing model

`InlineChangeSpan` is already defined in `PRRadarLibrary/Sources/services/PRRadarModels/PRDiff/PRLine.swift`:

```swift
public struct InlineChangeSpan: Codable, Sendable, Equatable {
    public let range: Range<Int>    // character index range within the line's content
    public let kind: Kind

    public enum Kind: String, Codable, Sendable, Equatable {
        case added      // characters inserted (present on new side only)
        case removed    // characters deleted (present on old side only)
    }
}
```

Spans mark only the changed ranges — characters not covered by any span are implicitly unchanged. For a new-side (`+`) line, spans have `kind: .added` marking inserted characters. For an old-side (`-`) line, spans have `kind: .removed` marking deleted characters.

Example:
```
Old: "function foo(x, y) {"
New: "function foo(x, y, z) {"
New-side spans: [InlineChangeSpan(range: 17..<20, kind: .added)]  // ", z"
Old-side spans: []  // nothing was deleted, only inserted
```

### Files involved

| File | Change |
|------|--------|
| `PRRadarLibrary/Sources/services/PRRadarModels/EffectiveDiff/InlineDiff.swift` | **New** — inline diff computation using `CollectionDifference` |
| `PRRadarLibrary/Sources/services/PRRadarModels/EffectiveDiff/ClassifiedDiffLine.swift` | Wire inline spans into `classifyLines()` for paired lines |
| `PRRadarLibrary/Tests/PRRadarModelsTests/LineClassificationTests.swift` | Add inline diff tests |

## Phases

### - [ ] Phase 1: Inline diff computation

**Skills to read**: `/swift-app-architecture:swift-architecture`

Create a pure function that computes inline change spans between two strings using Swift's built-in `CollectionDifference` (Myers diff algorithm from stdlib — no external dependencies).

**New file**: `PRRadarLibrary/Sources/services/PRRadarModels/EffectiveDiff/InlineDiff.swift`

1. `func computeInlineSpans(old: String, new: String) -> (oldSpans: [InlineChangeSpan], newSpans: [InlineChangeSpan])`
   - Converts both strings to `[Character]` arrays
   - Calls `newChars.difference(from: oldChars)` to get the `CollectionDifference`
   - Walks the diff to build `InlineChangeSpan` entries:
     - Old side: spans with `kind: .removed` at character positions where deletions occurred
     - New side: spans with `kind: .added` at character positions where insertions occurred
   - Adjacent changes of the same kind are merged into a single span
   - Returns spans for both sides

This is a pure function with no state — takes two strings, returns structured spans.

### - [ ] Phase 2: Wire inline spans into classification

**Skills to read**: `/swift-app-architecture:swift-architecture`

Populate `PRLine.inlineChanges` for paired lines in `classifyLines()`.

**Changes** in `PRRadarLibrary/Sources/services/PRRadarModels/EffectiveDiff/ClassifiedDiffLine.swift`:

1. Expand `buildPairedModifications()` (from the paired modification spec) to also store the old and new content strings for each pair
2. In `classifyLines()`, for each paired line:
   - Call `computeInlineSpans(old:new:)` with the paired contents
   - Attach the appropriate spans to the `PRLine` via `inlineChanges:`
   - `.removed` lines get old-side spans; `.added`/`.changed` lines get new-side spans

**Optional enhancement**: Add an `isWhitespaceOnly` computed property on `[InlineChangeSpan]` that checks whether all spans contain only whitespace characters. This could replace the `collapseWhitespace()` comparison in `buildPairedModifications()` for a more precise whitespace-only check.

### - [ ] Phase 3: Validation

**Skills to read**: `/swift-testing`

1. Run `swift test` — all existing tests must pass
2. Add new tests for `computeInlineSpans()`:
   - Identical strings → empty spans on both sides
   - Completely different strings → single span covering entire content
   - Partial changes — word added, word removed, word replaced
   - Whitespace-only differences → spans contain only whitespace
   - Empty strings (one or both sides)
3. Add integration tests verifying `PRLine.inlineChanges` is populated for paired modifications after `classifyLines()`
4. Verify spans are `nil` for unpaired lines, context lines, and moved lines
