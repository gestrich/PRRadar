# Paired Modification Classification

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules (placement, dependency rules) |
| `/swift-testing` | Test style guide and conventions |

## Background

PRRadar's effective diff pipeline classifies each diff line with a `ChangeKind` (`.added`, `.removed`, `.changed`, `.unchanged`). Currently, when a line is modified in place (not moved), the unified diff produces a `-` line and a `+` line. The classification assigns `.removed` and `.added` respectively — making in-place modifications **indistinguishable from genuinely new code**.

The `.changed` kind is only assigned within detected move blocks (via re-diff analysis). This means rules with `newCodeLinesOnly: true` match modified lines as if they were brand new, causing false positives. For example, changing `* parentView` to `*parentView` (whitespace-only) or adding a parameter to an existing function signature both appear as "new code."

Phase 2 of the [whitespace false-positives spec](2026-03-03-a-false-positive-whitespace-changes.md) added `buildWhitespaceOnlySet()` to handle the whitespace-only subset. This plan generalizes that approach to **all** in-place modifications by detecting paired `-`/`+` runs within hunks.

### Approach

1. **Pair `-`/`+` line runs** within hunks (sequential 1:1, matching how git pairs them)
2. **Classify** paired `+` lines as `.changed` instead of `.added`; whitespace-only pairs stay `.unchanged`
3. **Classify** paired `-` lines as `.changed` instead of `.removed`; whitespace-only pairs stay `.unchanged`
4. **Replace** `buildWhitespaceOnlySet()` with the new general mechanism

### Key behavioral change

`PRHunk.newCodeLines` (filters `.added`) will no longer include in-place modifications — they become `.changed`. This is the intended fix: rules with `newCodeLinesOnly: true` should only match genuinely new lines, not modifications of existing code. `changedLines` (filters `!= .unchanged`) is unaffected since `.changed` already passes that filter.

### Files involved

| File | Change |
|------|--------|
| `PRRadarLibrary/Sources/services/PRRadarModels/EffectiveDiff/ClassifiedDiffLine.swift` | Add `buildPairedModifications()`, modify `classifyLines()`, remove `buildWhitespaceOnlySet()` and `collapseWhitespace()` |
| `PRRadarLibrary/Tests/PRRadarModelsTests/LineClassificationTests.swift` | Update existing + add new tests |

## Phases

### - [ ] Phase 1: Paired modification detection and classification

**Skills to read**: `/swift-app-architecture:swift-architecture`

Add a pairing function and wire it into the classification pipeline, replacing `buildWhitespaceOnlySet()`.

**Changes** in `PRRadarLibrary/Sources/services/PRRadarModels/EffectiveDiff/ClassifiedDiffLine.swift`:

1. Add `buildPairedModifications(from:)` function:
   - Walk each hunk and identify consecutive runs of removed lines followed by added lines ("change groups")
   - Pair them 1:1 sequentially (removed[0]↔added[0], removed[1]↔added[1], etc.)
   - Surplus lines (when counts differ) remain unpaired
   - For each pair, check if the modification is whitespace-only using `collapseWhitespace()` (strip all whitespace, compare)
   - Return two lookups: `byOldLine: [String: [Int: Bool]]` and `byNewLine: [String: [Int: Bool]]` (filePath → lineNumber → isWhitespaceOnly)

2. Modify `classifyLines()` to use paired modifications:
   - Replace `buildWhitespaceOnlySet()` call with `buildPairedModifications()`
   - For `.removed` lines: if paired AND whitespace-only → `.unchanged`; if paired AND non-trivial → `.changed`
   - For `.added` lines: if paired AND whitespace-only → `.unchanged` (preserves existing behavior); if paired AND non-trivial → `.changed`
   - Move checks still take priority (checked first in the chain)

3. Delete `buildWhitespaceOnlySet()` and `collapseWhitespace()` — subsumed by the new mechanism

**Classification priority (`.added` lines) after change:**
```
1. addedInMoveLines       → (.added, move present)
2. changedInMoveLines     → (.changed, move present)
3. targetMovedLines       → (.unchanged, move present)
4. paired (whitespace-only) → (.unchanged, no move)
5. paired (non-trivial)     → (.changed, no move)  ← NEW
6. fallthrough              → (.added, no move)
```

**Classification priority (`.removed` lines) after change:**
```
1. sourceMovedLines (changed) → (changedSourceLines kind, move present)
2. sourceMovedLines (other)   → (.unchanged, move present)
3. paired (whitespace-only)   → (.unchanged, no move)  ← NEW
4. paired (non-trivial)       → (.changed, no move)    ← NEW
5. fallthrough                → (.removed, no move)
```

### - [ ] Phase 2: Validation

**Skills to read**: `/swift-testing`

1. Run `swift test` — all existing tests must pass
2. Update existing `LineClassificationTests` for cases where `.added` becomes `.changed`
3. Add new tests:
   - Pairing logic — equal run counts, surplus removals, surplus additions, context lines separating change groups
   - `classifyLines()` integration — paired modifications get `.changed`, whitespace-only stays `.unchanged`, unpaired lines stay `.added`/`.removed`, move detection takes priority over pairing
4. Verify against PR #19024 using the local validation steps in the [whitespace spec](2026-03-03-a-false-positive-whitespace-changes.md#local-validation-steps)
