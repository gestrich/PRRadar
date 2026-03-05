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

The old `ChangeKind` conflated two orthogonal dimensions into one enum:

1. **Content change** — what happened to the line's content
2. **Location change** — whether the line was moved, and which side of the move it is

This caused `MoveInfo` to be bolted on as a separate property, and led to cases like `.changed` only appearing within move blocks, and `.unchanged` being overloaded for context lines, verbatim moves, and whitespace-only modifications.

### This plan

1. Replaces `ChangeKind` with two independent properties on `PRLine`: `contentChange: ContentChange` and `pairing: Pairing?`
2. Adds in-place paired modification detection via `buildPairedModifications()`, replacing `buildWhitespaceOnlySet()` — so that all in-place `-`/`+` pairs are classified as `.modified` (or left as `.deleted`/`.added` when unpaired)
3. Fixes silent fallback on pipeline failure

### New type model

```swift
public struct Counterpart: Codable, Sendable, Equatable {
    public let filePath: String
    public let lineNumber: Int?  // nil when exact line pairing isn't known yet
}

public struct Pairing: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable, Equatable {
        case before  // old/removed side
        case after   // new/added side
    }
    public let role: Role
    public let counterpart: Counterpart
}

public enum ContentChange: String, Codable, Sendable, Equatable {
    case unchanged
    case added
    case deleted
    case modified
}
```

Two orthogonal dimensions on `PRLine`:

- `contentChange` — what happened to the line's content
- `pairing` — whether this line has a counterpart, and which side it is (`.before` = old/removed, `.after` = new/added)

| `contentChange` | `pairing` | Meaning |
|---|---|---|
| `.unchanged` | nil | Regular context line |
| `.unchanged` | `.before` | Verbatim move source (no content change) |
| `.unchanged` | `.after` | Verbatim move destination (no content change) |
| `.added` | nil | Genuinely new line |
| `.deleted` | nil | Genuinely deleted line |
| `.modified` | `.before` | Old version of an edit (in-place or moved) |
| `.modified` | `.after` | New version of an edit (in-place or moved) |

Cross-file move? `pairing.counterpart.filePath` differs from the line's own `filePath`. In-place edit? Same `filePath`, different `lineNumber`.

### Key behavioral change

`PRHunk.newCodeLines` (filters `contentChange == .added`) will no longer include in-place modifications — they become `.modified`. This is the intended fix: rules with `newCodeLinesOnly: true` should only match genuinely new lines, not modifications of existing code. `changedLines` (filters `contentChange != .unchanged`) is unaffected since `.modified`, `.added`, and `.deleted` all pass that filter.

### Full classification grid

| `diffType` | `contentChange` | `pairing` | Source | Meaning |
|------------|----------------|-----------|--------|---------|
| `.added` | `.added` | nil | no move, unpaired | Genuinely new code |
| `.added` | `.added` | nil | move, addedInMove | New insertion within moved block |
| `.added` | `.modified` | `.after` | move, changedInMove | New version of modification in move |
| `.added` | `.modified` | `.after` | no move, paired | New version of in-place modification |
| `.added` | `.unchanged` | `.after` | move, verbatim | Verbatim move destination |
| `.removed` | `.deleted` | nil | no move, unpaired | Genuinely deleted code |
| `.removed` | `.deleted` | nil | move, changedSourceLines .deleted | Deleted within moved block |
| `.removed` | `.modified` | `.before` | move, changedSourceLines .replaced | Old version of modification in move |
| `.removed` | `.modified` | `.before` | no move, paired | Old version of in-place modification |
| `.removed` | `.unchanged` | `.before` | move, verbatim | Verbatim move source |
| `.context` | `.unchanged` | nil | — | Unchanged context line |

### Consumer mapping

| Current expression | New expression | Used in |
|-------------------|---------------|---------|
| `changeKind == .added` | `contentChange == .added` | `newCodeLines`, `hasNewCode`, `DiffStats.linesAdded` |
| `changeKind == .removed` | `contentChange == .deleted` | `DiffStats.linesRemoved` |
| `changeKind == .changed` | `contentChange == .modified` | `DiffStats.linesChanged` |
| `changeKind != .unchanged` | `contentChange != .unchanged` | `changedLines` |
| `changeKind == .unchanged` | `contentChange == .unchanged` | reconstruction filter |
| `move != nil && changeKind == .unchanged` | `contentChange == .unchanged && pairing != nil` | `isMoved`, reconstruction, `DiffStats.linesMoved` |
| `changeKind == .changed && move != nil` | `contentChange == .modified && pairing?.counterpart.filePath != line.filePath` | `hasChangesInMove` |

### Eliminating MoveInfo

`MoveInfo` is removed from `PRLine`. Everything it provided is now captured by `Pairing`:

| Old (`MoveInfo`) | New (`Pairing`) | Notes |
|------------------|----------------|-------|
| `sourceFile` / `targetFile` | `pairing.counterpart.filePath` | The counterpart's file |
| `isSource` | `pairing.role == .before` | `.before` = source/old side |
| `move != nil` check | `pairing != nil` | Lines with pairings were part of a move or modification |

### Serialization note

`ContentChange` and `Pairing.Role` are `String` `RawRepresentable` — derived `Codable` conformance works. `Pairing` uses derived conformance. Any persisted `PRLine` data must be re-generated after this change.

### Files involved

| File | Change |
|------|--------|
| `ClassifiedDiffLine.swift` | Add `Counterpart`, `Pairing`, `ContentChange`; add `buildPairedModifications()`; remove `buildWhitespaceOnlySet()` and `collapseWhitespace()`; update `classifyLines()` |
| `BlockExtension.swift` | Update `RediffAnalysis.changedSourceLines` values; update `analyzeRediffHunks()` |
| `PRLine.swift` | Remove `MoveInfo`, remove `changeKind: ChangeKind`, remove `verbatimMoveCounterpart`; add `contentChange: ContentChange`, add `pairing: Pairing?`; update init |
| `PRHunk.swift` | Update computed property filters |
| `DiffStats.swift` | Update `compute()` |
| `DiffReconstruction.swift` | Update filter |
| `RichDiffViews.swift` | Replace `MoveInfo` references with `pairing` lookups |
| `PRAcquisitionService.swift` | Fix silent fallback on pipeline failure |
| `LineClassificationTests.swift` | Update all assertions, add pairing tests |

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

**Effect**: This reintroduces the original `parentView` false positive from PR #19024 because that line's change is now correctly treated as a real modification (not whitespace-only). The subsequent phases (paired modification detection) will fix this properly by classifying it as `.modified` instead of `.added`.

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

### - [x] Phase 3: Define new types (interim)

**Skills used**: `/swift-app-architecture:swift-architecture`
**Principles applied**: Added `Counterpart` struct and rewrote `ChangeKind` enum with associated values (`.new`, `.deleted`, `.replaced(counterpart:)`, `.replacement(counterpart:)`, `.context`). Added custom `Codable` conformance and convenience helpers (`isReplaced`, `isReplacement`, `counterpart`, `description`). Added `verbatimMoveCounterpart: Counterpart?` to `PRLine` (kept `MoveInfo` for Phase 5 removal). Updated `analyzeRediffHunks()` with `targetFile` parameter to produce `.replaced(counterpart:)` and `.deleted`. Updated all consumers (PRHunk, DiffStats, DiffReconstruction, RichDiffViews) and all test files to use new case names. 655 tests pass.

This phase defined an interim type model. Phase 5 replaces it with the final `ContentChange` + `Pairing` model.

### - [x] Phase 4: Add paired modification detection

**Skills used**: `/swift-app-architecture:swift-architecture`
**Principles applied**: Added `PairedModification` struct (counterpartLineNumber only) and `buildPairedModifications(from:)` which positionally pairs removed[i]↔added[i] within contiguous change groups. Deleted `buildWhitespaceOnlySet()` and `stripAllWhitespace()`. All paired lines fall through to `.deleted`/`.new` for now; Phase 6 promotes them to `.modified`. The `isSurroundingWhitespaceOnlyChange` indicator is deferred to Phase 11.

Add `buildPairedModifications()` to `ClassifiedDiffLine.swift`, replacing `buildWhitespaceOnlySet()`. This detects all in-place `-`/`+` pairs within hunks, not just whitespace-only ones.

**`buildPairedModifications(from:)` function:**
- Walk each hunk and identify consecutive runs of removed lines followed by added lines ("change groups")
- Pair them 1:1 sequentially (removed[0]↔added[0], removed[1]↔added[1], etc.)
- Surplus lines (when counts differ) remain unpaired
- Return two lookups:
  - `byOldLine: [String: [Int: PairedModification]]` (filePath → oldLineNumber → pairing info)
  - `byNewLine: [String: [Int: PairedModification]]` (filePath → newLineNumber → pairing info)
- Where `PairedModification` captures only: `counterpartLineNumber: Int`

No whitespace comparison is performed — all paired lines are in-place modifications regardless of how much the content changed.

### - [ ] Phase 5: Introduce `ContentChange` + `Pairing` model and update classification pipeline

**Skills to read**: `/swift-app-architecture:swift-architecture`

#### Design intent

The interim `ChangeKind` enum (Phase 3) conflates two independent questions into one:

1. **What happened to the content?** — Was the line added, deleted, modified, or unchanged?
2. **Does this line have a counterpart?** — Was it paired with another line (as part of a move or an in-place edit), and is it the old or new side?

These are orthogonal. A verbatim move has unchanged content but a counterpart. An in-place edit has modified content but no location change. A moved-and-modified line has both. Encoding all combinations into one enum forces callers to pattern-match on implementation details rather than asking clean questions.

The fix is two independent properties on `PRLine`:

```swift
public let contentChange: ContentChange   // what happened to the content
public let pairing: Pairing?              // nil if no counterpart; non-nil with role if paired
```

**Example** — `@property (weak) RouteEditIPadView * parentView;` (space removed before `parentView`):

| Property | Value | Meaning |
|---|---|---|
| `contentChange` | `.modified` | The content changed (interior whitespace) |
| `pairing` | `Pairing(role: .after, counterpart: Counterpart("RouteTokenDelegateDataSource.h", 27))` | This is the new version; the old version is at line 27 of the same file |

A rule using `newCodeLinesOnly: true` filters on `contentChange == .added` — `.modified` does not match, so the false positive is eliminated.

#### New types

```swift
public enum ContentChange: String, Codable, Sendable, Equatable {
    case unchanged
    case added
    case deleted
    case modified
}

public struct Pairing: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable, Equatable {
        case before  // old/removed side
        case after   // new/added side
    }
    public let role: Role
    public let counterpart: Counterpart
}
```

(`Counterpart` remains unchanged from Phase 3. Both new types use `String` raw values — derived `Codable` conformance works, no custom implementation needed.)

#### Changes in `ClassifiedDiffLine.swift`

1. Remove `ChangeKind` enum and all its helpers (`isReplaced`, `isReplacement`, `counterpart`)
2. Add `ContentChange` and `Pairing` as above
3. Update `classifyLines()` to produce `ContentChange` and `Pairing` values (see logic below)
4. Remove `moveInfo` local variable — replaced by `pairing`

**`.removed` lines:**
```
1. sourceMovedLines (changedSourceLines has .modified) → contentChange=.modified, pairing=Pairing(.before, Counterpart(targetFile, nil))
2. sourceMovedLines (changedSourceLines has .deleted)  → contentChange=.deleted, pairing=nil
3. sourceMovedLines (no changedSourceLines entry)      → contentChange=.unchanged, pairing=Pairing(.before, Counterpart(targetFile, nil))
4. paired (any content change)                         → contentChange=.modified, pairing=Pairing(.before, Counterpart(filePath, pairedNewLineNum))
5. fallthrough                                         → contentChange=.deleted, pairing=nil
```

**`.added` lines:**
```
1. addedInMoveLines   → contentChange=.added, pairing=nil
2. changedInMoveLines → contentChange=.modified, pairing=Pairing(.after, Counterpart(sourceFile, nil))
3. targetMovedLines   → contentChange=.unchanged, pairing=Pairing(.after, Counterpart(sourceFile, nil))
4. paired             → contentChange=.modified, pairing=Pairing(.after, Counterpart(filePath, pairedOldLineNum))
5. fallthrough        → contentChange=.added, pairing=nil
```

**`.context` lines:**
```
1. always             → contentChange=.unchanged, pairing=nil
```

Move checks (steps 1–3) take priority over in-place pairing (step 4).

Also update `PRHunk.fromHunk()` mapping:
- `.added` → `contentChange=.added, pairing=nil`
- `.removed` → `contentChange=.deleted, pairing=nil`
- `.context`/`.header` → `contentChange=.unchanged, pairing=nil`

#### Changes in `PRLine.swift`

1. Remove `MoveInfo` struct
2. Remove `move: MoveInfo?` property
3. Remove `changeKind: ChangeKind` property
4. Remove `verbatimMoveCounterpart: Counterpart?` property
5. Add `contentChange: ContentChange`
6. Add `pairing: Pairing?`
7. Update `init` accordingly

#### Changes in `BlockExtension.swift`

Update `RediffAnalysis.changedSourceLines` type values:
- Source lines in mixed hunks: produce `contentChange = .modified` with a `.before` pairing pointing to target file (lineNumber nil)
- Source lines in removal-only hunks: produce `contentChange = .deleted` with no pairing

Update `analyzeRediffHunks()` accordingly.

**Note**: This phase must be completed atomically with the consumer updates in Phase 6. After `PRLine` drops `changeKind`, the project will not compile until all call sites are updated.

### - [ ] Phase 6: Update consumers

**Skills to read**: `/swift-app-architecture:swift-architecture`

Update all code that reads `ChangeKind`, `MoveInfo`, or `verbatimMoveCounterpart` to use the new `ContentChange` and `Pairing` properties.

**`PRHunk.swift`** — computed properties:

| Property | Current | New |
|----------|---------|-----|
| `isMoved` | `verbatimMoveCounterpart != nil` | `contentChange == .unchanged && pairing != nil` |
| `hasNewCode` | `changeKind == .new` | `contentChange == .added` |
| `hasChangesInMove` | `changeKind.isReplaced \|\| changeKind.isReplacement` | `contentChange == .modified && pairing?.counterpart.filePath != filePath` |
| `newCodeLines` | `changeKind == .new` | `contentChange == .added` |
| `changedLines` | `changeKind != .context` | `contentChange != .unchanged` |

**`DiffStats.swift`** — `compute()`:

```swift
switch line.contentChange {
case .added:     added += 1
case .deleted:   removed += 1
case .modified:  changed += 1
case .unchanged:
    if line.pairing != nil { moved += 1 }
}
```

**`DiffReconstruction.swift`**:

Replace `verbatimMoveCounterpart != nil` with `contentChange == .unchanged && pairing != nil` in both locations (the `hasMovedLines` check and the segment-splitting loop).

**`RichDiffViews.swift`**:

- Replace `line.move != nil` checks with `line.pairing != nil`
- Replace `line.move.sourceFile` / `line.move.targetFile` with `line.pairing?.counterpart.filePath`
- Replace `line.move.isSource` with `line.pairing?.role == .before`
- `changeKind.rawValue` display in `LineInfoPopoverView` — replace with `line.contentChange.rawValue` (and optionally show pairing role)

### - [ ] Phase 7: Fix silent fallback on pipeline failure

**Skills to read**: `/swift-app-architecture:swift-architecture`

The effective diff pipeline silently returns empty classified hunks when `git merge-base` fails. Fix in `PRAcquisitionService.runEffectiveDiff()` catch block:

1. Log a warning so the user knows classification was skipped
2. Fall back to classifying all diff lines from the raw diff (every `+` line → `contentChange=.added`, every `-` line → `contentChange=.deleted`, context → `contentChange=.unchanged`) instead of returning empty
3. Both

### - [ ] Phase 8: Update tests

**Skills to read**: `/swift-testing`

Update all test assertions in `LineClassificationTests.swift` to use `ContentChange` and `Pairing`.

Mapping for assertions:
- `changeKind == .new` → `contentChange == .added`
- `changeKind == .deleted` → `contentChange == .deleted`
- `changeKind == .replaced` → `contentChange == .modified && pairing?.role == .before`
- `changeKind == .replacement` → `contentChange == .modified && pairing?.role == .after`
- `changeKind == .context` → `contentChange == .unchanged`
- `verbatimMoveCounterpart != nil` → `contentChange == .unchanged && pairing != nil`
- `line.move.sourceFile` / `.targetFile` → `line.pairing?.counterpart.filePath`
- `line.move.isSource` → `line.pairing?.role == .before`

Key test suites to update:
- `ClassifyLinesTests` — core classification assertions (check counterpart values on `.modified` lines)
- `PRHunkPropertiesTests` — computed property checks
- `MovedMethodWithInteriorChangeTests` — complex move scenarios (verify `contentChange=.modified` + pairing role + counterpart file paths)
- `MoveInfoPopulationTests` — replace with pairing assertions (verify `pairing.counterpart.filePath` and `lineNumber`, verify `contentChange=.unchanged && pairing != nil` for verbatim moves)
- `DiffStatsComputeTests` — stat counting assertions
- `ClassificationReconstructionEquivalenceTests` — reconstruction correctness
- `PRDiffCodableTests` — JSON round-trip (`ContentChange` and `Pairing.Role` are `RawRepresentable` so derived conformance works)
- `PRDiffConvenienceTests` and `PRDiffFromPipelineTests` — end-to-end assertions

New tests for paired modification detection:
- `buildPairedModifications` — equal run counts, surplus removals, surplus additions, context lines separating change groups
- `classifyLines` integration — all paired modifications get `contentChange=.modified` with correct pairing role and counterpart line numbers, unpaired lines stay `.added`/`.deleted`, move detection takes priority over in-place pairing

### - [ ] Phase 9: Validate the bug is fixed

Re-run the same steps from Phase 2 against PR #19024. Expected results:

```bash
# Delete cached data and rebuild
rm -rf ~/Desktop/code-reviews/19024
cd PRRadarLibrary && swift build

# Run pipeline
swift run PRRadarMacCLI sync 19024 --config ios
swift run PRRadarMacCLI prepare 19024 --config ios
swift run PRRadarMacCLI analyze 19024 --config ios --mode regex

# Inspect — parentView should be contentChange=modified (in-place modification, not new code)
python3 -c "
import json
with open('$(ls ~/Desktop/code-reviews/19024/analysis/*/diff/classified-hunks.json)') as f:
    hunks = json.load(f)
for h in hunks:
    for line in h.get('lines', []):
        if 'parentView' in line.get('content', ''):
            print(f'{line.get(\"lineType\",\"\"):8} | contentChange={str(line.get(\"contentChange\",\"\")):15} | {line[\"content\"][:80]}')
"
```

**Expected**:
- `parentView` line → `contentChange=modified` — **false positive eliminated**
- `- (nonnull instancetype)initWithTripSummary:...` → `contentChange=added` — genuinely new code still caught
- `RouteTokenDelegateDataSource.h — nullability-h-objc` → no longer flagged
- All unit tests pass (`swift test`)
- 6 real violations in `.m` files still detected

### - [ ] Phase 10: Add `isSurroundingWhitespaceOnlyChange` to `PRLine`

**Skills to read**: `/swift-app-architecture:swift-architecture`

Add `isSurroundingWhitespaceOnlyChange: Bool` to `PRLine`. This flag is `true` when a paired `.modified` line differs from its counterpart only in leading/trailing whitespace (interior whitespace changes are NOT flagged). Always `false` for `.added`, `.deleted`, and `.unchanged` lines.

**Comparison**: `removed.content.trimmingCharacters(in: .whitespaces) == added.content.trimmingCharacters(in: .whitespaces)`

**Examples**:
- `"    Hello"` → `"Hello"` → `true` (leading whitespace only)
- `"Hello    "` → `"Hello"` → `true` (trailing whitespace only)
- `"* parentView"` → `"*parentView"` → `false` (interior change)
- `"Hello  World"` → `"Hello World"` → `false` (interior change)

**Changes**:
- Add `isSurroundingWhitespaceOnlyChange: Bool` to `PRLine` (default `false`)
- Record `isSurroundingWhitespaceOnly: Bool` in `PairedModification` (computed during `buildPairedModifications`) and propagate to `PRLine` in `classifyLines()`

### - [ ] Phase 11: Suppress surrounding-whitespace-only lines in regex and script analysis

**Skills to read**: `/swift-app-architecture:swift-architecture`

Update the analysis layer to skip lines where `isSurroundingWhitespaceOnlyChange == true` for regex and script rules. AI rules are unaffected — they receive the raw diff text and can reason about whitespace themselves.

**Changes**:
- `RegexAnalysisService`: skip lines where `isSurroundingWhitespaceOnlyChange == true`
- `ScriptAnalysisService` (or equivalent): same suppression
- Add tests confirming that surrounding-whitespace-only `.modified` lines are not flagged by regex rules
