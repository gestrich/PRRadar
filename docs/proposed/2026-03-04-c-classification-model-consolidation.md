# Classification Model Consolidation

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules (placement, dependency rules) |
| `/swift-testing` | Test style guide and conventions |

## Background

### The original bug

PR #19024 in ff-ios was flagged by the `nullability-h-objc` regex rule on line R27 of `RouteTokenDelegateDataSource.h`:

```objc
@property (weak) RouteEditIPadView *parentView;
```

This line lacks a nullability annotation, so the regex pattern matched. However, the line was **not genuinely new** — it was a whitespace-only modification. The base branch had `* parentView` (space before variable name) and the head had `*parentView` (no space). The declaration itself was unchanged.

The `+` line hit the fallthrough in `classifyLines()` → `changeKind = .added`. Downstream, `relevantLines(newCodeLinesOnly: true)` included it, and the regex rule matched → false positive.

### Root cause

The classification model has no concept of "in-place modification." A `-`/`+` pair that modifies a line in place gets `.removed`/`.added`, identical to genuinely new/deleted code. The `.changed` kind only exists within detected move blocks.

Phase 2 of the [whitespace false-positives spec](2026-03-03-a-false-positive-whitespace-changes.md) added `buildWhitespaceOnlySet()` to handle whitespace-only modifications, but non-whitespace in-place modifications (variable renames, added parameters, type changes) remain undetected and still cause false positives with `newCodeLinesOnly: true` rules.

### Additional issues discovered during investigation

**Silent fallback on pipeline failure**: When `git merge-base` fails (e.g., commit not fetched locally), the effective diff pipeline silently returns empty classified hunks instead of erroring. `classified-hunks.json` contains `[]` even though the diff has hunks. The analyze step finds 0 tasks and reports "No tasks to evaluate" with no error shown. Location: `PRAcquisitionService.runEffectiveDiff()` catch block.

### Broader model problems

1. **`.changed` conflates content modification with move context** — only appears within detected move blocks
2. **`.unchanged` is overloaded** — covers context lines, verbatim moves, and whitespace-only modifications
3. **No distinction between old and new versions** — both `-` and `+` sides of a changed-in-move get `.changed`
4. **`MoveInfo` is mostly redundant** — `isSource` is derivable from `diffType`, and one of sourceFile/targetFile is always the line's own `filePath`

### This plan

1. Restructures `ChangeKind` into an enum with associated values, where `.replaced` and `.replacement` carry a `Counterpart` that links to the paired line, eliminating `MoveInfo` entirely
2. Adds in-place paired modification detection via `buildPairedModifications()`, replacing `buildWhitespaceOnlySet()` — so that all in-place `-`/`+` pairs are classified as `.replaced`/`.replacement` (or demoted to `.context` if whitespace-only)
3. Fixes silent fallback on pipeline failure

### New ChangeKind

```swift
public struct Counterpart: Codable, Sendable, Equatable {
    public let filePath: String
    public let lineNumber: Int?  // nil when exact line pairing isn't known yet
}

public enum ChangeKind: Codable, Sendable, Equatable {
    case new
    case deleted
    case replaced(counterpart: Counterpart)
    case replacement(counterpart: Counterpart)
    case context
}
```

| Case | Meaning |
|------|---------|
| `.new` | Genuinely new line (no counterpart) |
| `.deleted` | Genuinely deleted line (no counterpart) |
| `.replaced(counterpart)` | Old version of a modification — counterpart points to the `+` side |
| `.replacement(counterpart)` | New version of a modification — counterpart points to the `-` side |
| `.context` | No meaningful change (context, demoted verbatim move, demoted whitespace-only) |

Cross-file move? `counterpart.filePath` differs from the line's own `filePath`. Same-file modification? Same `filePath`, different `lineNumber`.

### Key behavioral change

`PRHunk.newCodeLines` (filters `.new`) will no longer include in-place modifications — they become `.replacement`. This is the intended fix: rules with `newCodeLinesOnly: true` should only match genuinely new lines, not modifications of existing code. `changedLines` (filters `!= .context`) is unaffected since `.replaced`/`.replacement` pass that filter.

### Full classification grid

| `diffType` | `changeKind` | Source | Meaning |
|------------|-------------|--------|---------|
| `.added` | `.new` | no move, unpaired | Genuinely new code |
| `.added` | `.new` | move, addedInMove | New insertion within moved block |
| `.added` | `.replacement(counterpart)` | move, changedInMove | New version of modification in move |
| `.added` | `.replacement(counterpart)` | no move, paired non-trivial | New version of in-place modification |
| `.added` | `.context` | move, verbatim | Verbatim move destination (demoted) |
| `.added` | `.replacement(counterpart)` | no move, paired whitespace-only | In-place modification (whitespace-only is still a modification) |
| `.removed` | `.deleted` | no move, unpaired | Genuinely deleted code |
| `.removed` | `.deleted` | move, changedSourceLines .deleted | Deleted within moved block |
| `.removed` | `.replaced(counterpart)` | move, changedSourceLines .replaced | Old version of modification in move |
| `.removed` | `.replaced(counterpart)` | no move, paired non-trivial | Old version of in-place modification |
| `.removed` | `.context` | move, verbatim | Verbatim move source (demoted) |
| `.removed` | `.replaced(counterpart)` | no move, paired whitespace-only | In-place modification (whitespace-only is still a modification) |
| `.context` | `.context` | — | Unchanged context line |

### Consumer mapping

Since `ChangeKind` now has associated values, `==` comparisons change to pattern matching:

| Current expression | New expression | Used in |
|-------------------|---------------|---------|
| `changeKind == .added` | `changeKind == .new` | `newCodeLines`, `hasNewCode`, `DiffStats.linesAdded` |
| `changeKind == .removed` | `changeKind == .deleted` | `DiffStats.linesRemoved` |
| `changeKind == .changed` | `changeKind.isReplaced \|\| changeKind.isReplacement` | `DiffStats.linesChanged` |
| `changeKind != .unchanged` | `changeKind != .context` | `changedLines` |
| `changeKind == .unchanged` | `changeKind == .context` | reconstruction filter |
| `move != nil && changeKind == .unchanged` | `verbatimMoveCounterpart != nil` | `isMoved`, reconstruction, `DiffStats.linesMoved` |
| `changeKind == .changed && move != nil` | `changeKind.isReplaced \|\| changeKind.isReplacement` (counterpart implies pairing) | `hasChangesInMove` |

**Convenience helpers** on `ChangeKind` to simplify pattern matching:

```swift
extension ChangeKind {
    var isReplaced: Bool {
        if case .replaced = self { return true }
        return false
    }
    var isReplacement: Bool {
        if case .replacement = self { return true }
        return false
    }
    var counterpart: Counterpart? {
        switch self {
        case .replaced(let c), .replacement(let c): return c
        default: return nil
        }
    }
}
```

### Eliminating MoveInfo

`MoveInfo` is removed from `PRLine`. Everything it provided is now captured by the `Counterpart` associated value:

| Old (`MoveInfo`) | New (`Counterpart`) | Notes |
|------------------|-------------------|-------|
| `sourceFile` / `targetFile` | `counterpart.filePath` | The counterpart's file — derivable as "the other file" |
| `isSource` | Implicit from case | `.replaced` = source side, `.replacement` = target side |
| `move != nil` check | `changeKind.counterpart != nil` | Lines with counterparts were paired |

**Trade-off**: Lines that are `.new` or `.deleted` within a moved block currently have `move != nil` (used by the UI to show a move indicator). These lose that per-line metadata. The move report still identifies which file ranges are moved, so the UI can derive this if needed.

### Handling verbatim moves and `isMoved`

Verbatim moves are currently identified by `move != nil && changeKind == .unchanged`. In the new model these are `.context` lines — but so are genuine context lines and whitespace-only demotions. To distinguish verbatim moves for reconstruction and stats:

**Option chosen**: Track verbatim move counterparts on `PRLine` via a separate lightweight property:

```swift
public struct PRLine {
    ...
    public let changeKind: ChangeKind
    public let verbatimMoveCounterpart: Counterpart?  // non-nil only for demoted verbatim moves
    ...
}
```

This preserves the ability to:
- Reconstruct effective diff: strip lines where `verbatimMoveCounterpart != nil`
- Count `linesMoved` in `DiffStats`: count lines where `verbatimMoveCounterpart != nil`
- Compute `isMoved` on `PRHunk`: all non-context `diffType` lines have `verbatimMoveCounterpart != nil`
- Show "moved from/to" in the UI using `verbatimMoveCounterpart.filePath`

### Files involved

| File | Change |
|------|--------|
| `ClassifiedDiffLine.swift` | New `Counterpart` struct, rewrite `ChangeKind` as enum with associated values, add `buildPairedModifications()`, remove `buildWhitespaceOnlySet()` and `collapseWhitespace()`, update `classifyLines()` |
| `BlockExtension.swift` | Update `RediffAnalysis.changedSourceLines` values, update `analyzeRediffHunks()` |
| `PRLine.swift` | Remove `MoveInfo`, add `verbatimMoveCounterpart: Counterpart?`, update init |
| `PRHunk.swift` | Update computed property filters to use pattern matching |
| `DiffStats.swift` | Update `compute()` to use new cases |
| `DiffReconstruction.swift` | Update filter to use `verbatimMoveCounterpart` |
| `RichDiffViews.swift` | Replace `MoveInfo` references with counterpart lookups |
| `PRAcquisitionService.swift` | Fix silent fallback on pipeline failure |
| `LineClassificationTests.swift` | Update all assertions, add pairing tests |

### Serialization note

`ChangeKind` is no longer `String` `RawRepresentable` — it's an enum with associated values requiring custom `Codable` conformance. Any persisted `PRLine` data must be re-generated.

## Phases

### - [x] Phase 1: Tighten whitespace-only detection to leading/trailing only

**Skills used**: `/swift-app-architecture:swift-architecture`, `/swift-testing`
**Principles applied**: Renamed `collapseWhitespace()` to `trimSurroundingWhitespace()` using `trimmingCharacters(in: .whitespaces)`. Added two tests: `leadingWhitespaceOnlyChangeClassifiedAsUnchanged` and `interiorWhitespaceChangeClassifiedAsAdded` (reproduces the `* parentView` case).

**Skills to read**: `/swift-app-architecture:swift-architecture`

The current `collapseWhitespace()` strips ALL whitespace, so `"* parentView"` and `"*parentView"` compare equal. This hides interior whitespace changes that are arguably real modifications (e.g., moving a `*` against the variable name changes pointer semantics in some contexts).

Change `collapseWhitespace()` (or replace it with a new comparison) to only consider **leading/trailing** whitespace differences as whitespace-only. Interior whitespace changes should be treated as real modifications.

**Changes in `ClassifiedDiffLine.swift`**:
- Replace `collapseWhitespace()` with a comparison that trims leading/trailing whitespace from both lines, then checks exact equality
- `"  foo bar"` vs `"foo bar"` → whitespace-only (leading whitespace)
- `"* parentView"` vs `"*parentView"` → NOT whitespace-only (interior change)
- `"foo  "` vs `"foo"` → whitespace-only (trailing whitespace)

**Effect**: This reintroduces the original `parentView` false positive from PR #19024 because that line's change is now correctly treated as a real modification (not whitespace-only). The subsequent phases (paired modification detection) will fix this properly by classifying it as `.replaced`/`.replacement` instead of `.added`.

**Tests**: Update existing whitespace-only tests to match the tighter definition. Add tests for interior vs leading/trailing whitespace differences.

### - [x] Phase 2: Reproduce the original bug

**Note**: PR #19024's branch has been deleted from the remote (old merged PR), so the full pipeline sync can't run. The bug is confirmed reproduced at the unit test level — `interiorWhitespaceChangeClassifiedAsAdded` directly tests `"* parentView"` vs `"*parentView"` and asserts `changeKind == .added`.

Confirm the false positive on PR #19024 exists after tightening the whitespace definition. The `parentView` line should now be classified as `changeKind=added` (the bug is back), and other in-place modifications should also show as `added`.

```bash
# Delete cached analysis data so the pipeline re-runs from scratch
rm -rf ~/Desktop/code-reviews/19024

# Build
cd PRRadarLibrary && swift build

# Run phases in order
swift run PRRadarMacCLI sync 19024 --config ios
swift run PRRadarMacCLI prepare 19024 --config ios
swift run PRRadarMacCLI analyze 19024 --config ios --mode regex

# Inspect — expect parentView to show changeKind=added (bug reintroduced)
# and other in-place modifications also showing changeKind=added
python3 -c "
import json
with open('$(ls ~/Desktop/code-reviews/19024/analysis/*/diff/classified-hunks.json)') as f:
    hunks = json.load(f)
for h in hunks:
    for line in h.get('lines', []):
        if line.get('lineType') in ('added', 'removed'):
            ck = line.get('changeKind', '')
            if ck == 'added':
                print(f'BUG: {line[\"content\"][:80]}')
"
```

Use `--config ios` (saved configuration pointing to local ff-ios checkout). Use `--mode regex` to skip Claude API calls.

### - [x] Phase 3: Define new types

**Skills used**: `/swift-app-architecture:swift-architecture`
**Principles applied**: Added `Counterpart` struct and rewrote `ChangeKind` enum with associated values (`.new`, `.deleted`, `.replaced(counterpart:)`, `.replacement(counterpart:)`, `.context`). Added custom `Codable` conformance and convenience helpers (`isReplaced`, `isReplacement`, `counterpart`, `description`). Added `verbatimMoveCounterpart: Counterpart?` to `PRLine` (kept `MoveInfo` for Phase 5 removal). Updated `analyzeRediffHunks()` with `targetFile` parameter to produce `.replaced(counterpart:)` and `.deleted`. Updated all consumers (PRHunk, DiffStats, DiffReconstruction, RichDiffViews) and all test files to use new case names. 655 tests pass.

Define the new `Counterpart` struct and rewrite `ChangeKind` as an enum with associated values. Add convenience helpers. Remove `MoveInfo`.

**Changes in `ClassifiedDiffLine.swift`**:

1. Add `Counterpart` struct:
   ```swift
   public struct Counterpart: Codable, Sendable, Equatable {
       public let filePath: String
       public let lineNumber: Int?
   }
   ```

2. Rewrite `ChangeKind`:
   ```swift
   public enum ChangeKind: Codable, Sendable, Equatable {
       case new
       case deleted
       case replaced(counterpart: Counterpart)
       case replacement(counterpart: Counterpart)
       case context
   }
   ```

3. Add convenience extension with `isReplaced`, `isReplacement`, `counterpart` helpers.

**Changes in `PRLine.swift`**:

1. Remove `MoveInfo` struct
2. Remove `move: MoveInfo?` property
3. Add `verbatimMoveCounterpart: Counterpart?` property
4. Update `init` parameters accordingly

**Changes in `BlockExtension.swift`**:

Update `analyzeRediffHunks()` to produce new case names in `changedSourceLines`:
- Source lines in mixed hunks: `.replaced(counterpart:)` with counterpart pointing to target file (lineNumber nil for now since exact pairing within re-diff isn't tracked 1:1)
- Source lines in removal-only hunks: `.deleted`

Update `RediffAnalysis.changedSourceLines` type from `[Int: ChangeKind]` — values change from `.changed`/`.removed` to `.replaced(counterpart:)`/`.deleted`.

### - [x] Phase 4: Add paired modification detection

**Skills used**: `/swift-app-architecture:swift-architecture`
**Principles applied**: Added `PairedModification` struct (counterpartLineNumber only — no whitespace classification) and `buildPairedModifications(from:)` which positionally pairs removed[i]↔added[i] within contiguous change groups. Deleted `buildWhitespaceOnlySet()` and `stripAllWhitespace()`. All paired lines fall through to `.deleted`/`.new` for now; Phase 5 promotes them to `.replaced`/`.replacement`. The `isSurroundingWhitespaceOnlyChange` indicator is deferred to Phase 10.

Add `buildPairedModifications()` to `ClassifiedDiffLine.swift`, replacing `buildWhitespaceOnlySet()`. This detects all in-place `-`/`+` pairs within hunks, not just whitespace-only ones.

**Add `buildPairedModifications(from:)` function:**
- Walk each hunk and identify consecutive runs of removed lines followed by added lines ("change groups")
- Pair them 1:1 sequentially (removed[0]↔added[0], removed[1]↔added[1], etc.)
- Surplus lines (when counts differ) remain unpaired
- Return two lookups:
  - `byOldLine: [String: [Int: PairedModification]]` (filePath → oldLineNumber → pairing info)
  - `byNewLine: [String: [Int: PairedModification]]` (filePath → newLineNumber → pairing info)
- Where `PairedModification` captures only: `counterpartLineNumber: Int`

No whitespace comparison is performed — all paired lines are in-place modifications regardless of how much the content changed. The `newCodeLinesOnly` fix comes purely from the `.replacement` classification in Phase 5, not from any whitespace check.

**Delete `buildWhitespaceOnlySet()`** — subsumed by the new mechanism.

### - [ ] Phase 5: Update classification pipeline

**Skills to read**: `/swift-app-architecture:swift-architecture`

Update `classifyLines()` in `ClassifiedDiffLine.swift` to produce the new `ChangeKind` values and populate `verbatimMoveCounterpart`. Remove the `moveInfo` local variable — its information is now split between the `ChangeKind` associated value and `verbatimMoveCounterpart`. Replace the `buildWhitespaceOnlySet()` call with `buildPairedModifications()`.

**`.removed` lines:**
```
1. sourceMovedLines (changedSourceLines has .replaced) → .replaced(counterpart) from changedSourceLines
2. sourceMovedLines (changedSourceLines has .deleted)  → .deleted
3. sourceMovedLines (no changedSourceLines entry)      → .context, verbatimMoveCounterpart = Counterpart(targetFile, nil)
4. paired (any content change)                         → .replaced(counterpart: Counterpart(filePath, pairedNewLineNum))
5. fallthrough                                         → .deleted
```

**`.added` lines:**
```
1. addedInMoveLines     → .new
2. changedInMoveLines   → .replacement(counterpart: Counterpart(sourceFile, nil))
3. targetMovedLines     → .context, verbatimMoveCounterpart = Counterpart(sourceFile, nil)
4. paired (any content change) → .replacement(counterpart: Counterpart(filePath, pairedOldLineNum))
5. fallthrough          → .new
```

**`.context` lines:**
```
1. always                 → .context
```

Note: Move checks (steps 1-3) take priority over in-place pairing (steps 4-5). A line that's part of a detected move is classified by the move logic, not the pairing logic.

The `PRLine` init call changes: drop `move:`, add `verbatimMoveCounterpart:`.

Also update `PRHunk.fromHunk()` mapping:
- `.added` → `.new`
- `.removed` → `.deleted`
- `.context`/`.header` → `.context`
- `verbatimMoveCounterpart` = nil for all (no move detection in this path)

### - [ ] Phase 6: Update consumers

**Skills to read**: `/swift-app-architecture:swift-architecture`

Update all code that reads `ChangeKind` or `MoveInfo` to use the new types.

**`PRHunk.swift`** — computed properties:

| Property | Current | New |
|----------|---------|-----|
| `isMoved` | `move != nil && changeKind == .unchanged` | `verbatimMoveCounterpart != nil` |
| `hasNewCode` | `changeKind == .added` | `changeKind == .new` |
| `hasChangesInMove` | `changeKind == .changed && move != nil` | `changeKind.isReplaced \|\| changeKind.isReplacement` (counterpart with different filePath implies move) |
| `newCodeLines` | `changeKind == .added` | `changeKind == .new` |
| `changedLines` | `changeKind != .unchanged` | `changeKind != .context` |

**`DiffStats.swift`** — `compute()`:

```swift
switch line.changeKind {
case .new: added += 1
case .deleted: removed += 1
case .replaced, .replacement: changed += 1
case .context:
    if line.verbatimMoveCounterpart != nil { moved += 1 }
}
```

**`DiffReconstruction.swift`**:

Replace `move != nil && changeKind == .unchanged` with `verbatimMoveCounterpart != nil` in both locations (the `hasMovedLines` check and the segment-splitting loop).

**`RichDiffViews.swift`**:

- Replace `line.move != nil` checks with `line.changeKind.counterpart != nil || line.verbatimMoveCounterpart != nil`
- Replace `line.move.sourceFile` / `line.move.targetFile` lookups with counterpart file path
- The `findMoveDetail(for:)` helper may need to derive source/target from counterpart + line's own filePath
- `changeKind.rawValue` display in `LineInfoPopoverView` — since `ChangeKind` no longer has raw values, display using a computed description property or switch

### - [ ] Phase 7: Fix silent fallback on pipeline failure

**Skills to read**: `/swift-app-architecture:swift-architecture`

The effective diff pipeline silently returns empty classified hunks when `git merge-base` fails. Fix in `PRAcquisitionService.runEffectiveDiff()` catch block:

1. Log a warning so the user knows classification was skipped
2. Fall back to classifying all diff lines from the raw diff (every `+` line → `.new`, every `-` line → `.deleted`, context → `.context`) instead of returning empty
3. Both

### - [ ] Phase 8: Update tests

**Skills to read**: `/swift-testing`

Update all test assertions in `LineClassificationTests.swift` to use the new `ChangeKind` cases.

Mapping for assertions:
- `.added` → `.new`
- `.removed` → `.deleted`
- `.changed` → `.replaced(counterpart:)` (for `-` lines) or `.replacement(counterpart:)` (for `+` lines)
- `.unchanged` → `.context`
- `line.move != nil` → `line.verbatimMoveCounterpart != nil` or `line.changeKind.counterpart != nil`
- `line.move.sourceFile` / `.targetFile` / `.isSource` → derive from counterpart

Key test suites to update:
- `ClassifyLinesTests` — core classification assertions (check counterpart values on `.replaced`/`.replacement`)
- `PRHunkPropertiesTests` — computed property checks
- `MovedMethodWithInteriorChangeTests` — complex move scenarios (`.changed` splits into `.replaced`/`.replacement` based on `diffType`, verify counterpart file paths)
- `MoveInfoPopulationTests` — replace with counterpart assertions (verify filePath and lineNumber on paired lines, verify verbatimMoveCounterpart on demoted lines)
- `DiffStatsComputeTests` — stat counting assertions
- `ClassificationReconstructionEquivalenceTests` — reconstruction correctness
- `PRDiffCodableTests` — JSON round-trip (custom Codable for associated-value enum)
- `PRDiffConvenienceTests` and `PRDiffFromPipelineTests` — end-to-end assertions

New tests for paired modification detection:
- `buildPairedModifications` — equal run counts, surplus removals, surplus additions, context lines separating change groups
- `classifyLines` integration — all paired modifications get `.replaced`/`.replacement` with correct counterpart line numbers (regardless of whether the change is whitespace-only), unpaired lines stay `.new`/`.deleted`, move detection takes priority over in-place pairing

### - [ ] Phase 9: Validate the bug is fixed

Re-run the same steps from Phase 1 against PR #19024. Expected results:

```bash
# Delete cached data and rebuild
rm -rf ~/Desktop/code-reviews/19024
cd PRRadarLibrary && swift build

# Run pipeline
swift run PRRadarMacCLI sync 19024 --config ios
swift run PRRadarMacCLI prepare 19024 --config ios
swift run PRRadarMacCLI analyze 19024 --config ios --mode regex

# Inspect — parentView should be changeKind=replacement (in-place modification, not new code)
# Other in-place modifications should also be changeKind=replacement
# Genuinely new lines (like _Nonnull additions) should still be changeKind=new
python3 -c "
import json
with open('$(ls ~/Desktop/code-reviews/19024/analysis/*/diff/classified-hunks.json)') as f:
    hunks = json.load(f)
for h in hunks:
    for line in h.get('lines', []):
        if 'parentView' in line.get('content', ''):
            print(f'{line.get(\"lineType\",\"\"):8} | changeKind={str(line.get(\"changeKind\",\"\")):30} | {line[\"content\"][:80]}')
"
```

**Expected**:
- `parentView` line → `changeKind = replacement` (in-place modification, not new code) — **false positive eliminated**
- `- (nonnull instancetype)initWithTripSummary:...` → `changeKind = new` — genuinely new code still caught
- `RouteTokenDelegateDataSource.h — nullability-h-objc` → no longer flagged
- All unit tests pass (`swift test`)
- 6 real violations in `.m` files still detected

### - [ ] Phase 10: Add `isSurroundingWhitespaceOnlyChange` to `PRLine`

**Skills to read**: `/swift-app-architecture:swift-architecture`

Add `isSurroundingWhitespaceOnlyChange: Bool` to `PRLine`. This flag is `true` when a paired `-`/`+` line differs from its counterpart only in leading/trailing whitespace (interior whitespace changes are NOT flagged). It is always `false` for `.new`, `.deleted`, and `.context` lines.

**Comparison**: `removed.content.trimmingCharacters(in: .whitespaces) == added.content.trimmingCharacters(in: .whitespaces)`

**Examples**:
- `"    Hello"` → `"Hello"` → `true` (leading whitespace only)
- `"Hello    "` → `"Hello"` → `true` (trailing whitespace only)
- `"* parentView"` → `"*parentView"` → `false` (interior change)
- `"Hello  World"` → `"Hello World"` → `false` (interior change)

**Changes**:
- Add `isSurroundingWhitespaceOnlyChange: Bool` to `PRLine` (default `false`)
- Populate it in `classifyLines()` for paired `.replaced`/`.replacement` lines using the trimmed comparison
- Record `isSurroundingWhitespaceOnly: Bool` in `PairedModification` (computed during `buildPairedModifications`) and propagate to the `PRLine`

### - [ ] Phase 11: Suppress surrouding-whitespace-only lines in regex and script analysis

**Skills to read**: `/swift-app-architecture:swift-architecture`

Update the analysis layer to skip lines where `isSurroundingWhitespaceOnlyChange == true` for regex and script rules. AI rules are unaffected — they receive the raw diff text and can reason about whitespace themselves.

**Changes**:
- `RegexAnalysisService`: skip lines where `isSurroundingWhitespaceOnlyChange == true`
- `ScriptAnalysisService` (or equivalent): same suppression
- Add tests confirming that surrounding-whitespace-only `.replacement` lines are not flagged by regex rules
