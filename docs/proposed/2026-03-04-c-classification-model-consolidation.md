# Classification Model Consolidation

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules (placement, dependency rules) |
| `/swift-testing` | Test style guide and conventions |

## Background

PRRadar's line classification model uses `ChangeKind` (`.added`, `.removed`, `.changed`, `.unchanged`) combined with an optional `MoveInfo` struct to describe what happened to each diff line. This creates several conceptual problems:

1. **`.changed` conflates content modification with move context** — it only appears on lines within detected move blocks, making "modified content" and "part of a move" inseparable.
2. **`.unchanged` is overloaded** — it covers genuine context lines, verbatim moves (demoted), and whitespace-only modifications (demoted). Consumers must check `move != nil` alongside `changeKind` to distinguish these.
3. **No distinction between old and new versions of a modification** — both the `-` and `+` sides of a changed-in-move get `.changed`, making it impossible to tell which is the old version and which is the new.
4. **In-place modifications are invisible** — a `-`/`+` pair that modifies a line in place gets `.removed`/`.added`, indistinguishable from genuinely new/deleted code.
5. **`MoveInfo` is mostly redundant** — it carries `sourceFile`, `targetFile`, and `isSource`, but `isSource` is derivable from `diffType`, and one of the two files is always the line's own `filePath`. The only unique info is "the other file."

This plan restructures `ChangeKind` into an enum with associated values, where `.replaced` and `.replacement` carry a `Counterpart` that links to the paired line. This eliminates `MoveInfo` entirely — the counterpart *is* the link. No new detection logic is added — existing behavior is preserved with cleaner semantics.

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

### Full classification grid

| `diffType` | `changeKind` | Current equivalent | Meaning |
|------------|-------------|-------------------|---------|
| `.added` | `.new` | `.added`, no move | Genuinely new code |
| `.added` | `.new` | `.added`, move present | New insertion within moved block |
| `.added` | `.replacement(counterpart)` | `.changed`, move present | New version of modification in move |
| `.added` | `.context` | `.unchanged`, move present | Verbatim move destination (demoted) |
| `.added` | `.context` | `.unchanged`, no move | Whitespace-only modification (demoted) |
| `.removed` | `.deleted` | `.removed`, no move | Genuinely deleted code |
| `.removed` | `.deleted` | `.removed` from `changedSourceLines` | Deleted within moved block |
| `.removed` | `.replaced(counterpart)` | `.changed` from `changedSourceLines` | Old version of modification in move |
| `.removed` | `.context` | `.unchanged`, move present | Verbatim move source (demoted) |
| `.context` | `.context` | `.unchanged`, no move | Unchanged context line |

### Consumer mapping

Since `ChangeKind` now has associated values, `==` comparisons change to pattern matching:

| Current expression | New expression | Used in |
|-------------------|---------------|---------|
| `changeKind == .added` | `changeKind == .new` | `newCodeLines`, `hasNewCode`, `DiffStats.linesAdded` |
| `changeKind == .removed` | `changeKind == .deleted` | `DiffStats.linesRemoved` |
| `changeKind == .changed` | `changeKind.isReplaced \|\| changeKind.isReplacement` | `DiffStats.linesChanged` |
| `changeKind != .unchanged` | `changeKind != .context` | `changedLines` |
| `changeKind == .unchanged` | `changeKind == .context` | reconstruction filter |
| `move != nil && changeKind == .unchanged` | `changeKind.counterpart != nil` (on `.context` lines, see note) | `isMoved`, reconstruction, `DiffStats.linesMoved` |
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
| `ClassifiedDiffLine.swift` | New `Counterpart` struct, rewrite `ChangeKind` as enum with associated values, update `classifyLines()` |
| `BlockExtension.swift` | Update `RediffAnalysis.changedSourceLines` values, update `analyzeRediffHunks()` |
| `PRLine.swift` | Remove `MoveInfo`, add `verbatimMoveCounterpart: Counterpart?`, update init |
| `PRHunk.swift` | Update computed property filters to use pattern matching |
| `DiffStats.swift` | Update `compute()` to use new cases |
| `DiffReconstruction.swift` | Update filter to use `verbatimMoveCounterpart` |
| `RichDiffViews.swift` | Replace `MoveInfo` references with counterpart lookups |
| `LineClassificationTests.swift` | Update all assertions |

### Serialization note

`ChangeKind` is no longer `String` `RawRepresentable` — it's an enum with associated values requiring custom `Codable` conformance. Any persisted `PRLine` data must be re-generated.

## Phases

### - [ ] Phase 1: Define new types

**Skills to read**: `/swift-app-architecture:swift-architecture`

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

### - [ ] Phase 2: Update classification pipeline

**Skills to read**: `/swift-app-architecture:swift-architecture`

Update `classifyLines()` in `ClassifiedDiffLine.swift` to produce the new `ChangeKind` values and populate `verbatimMoveCounterpart`. Remove the `moveInfo` local variable — its information is now split between the `ChangeKind` associated value and `verbatimMoveCounterpart`.

**`.removed` lines:**
```
1. sourceMovedLines (changedSourceLines has .replaced) → .replaced(counterpart) from changedSourceLines
2. sourceMovedLines (changedSourceLines has .deleted)  → .deleted
3. sourceMovedLines (no changedSourceLines entry)      → .context, verbatimMoveCounterpart = Counterpart(targetFile, nil)
4. fallthrough                                         → .deleted
```

**`.added` lines:**
```
1. addedInMoveLines       → .new
2. changedInMoveLines     → .replacement(counterpart: Counterpart(sourceFile, nil))
3. targetMovedLines       → .context, verbatimMoveCounterpart = Counterpart(sourceFile, nil)
4. whitespaceOnlyAdded    → .context
5. fallthrough            → .new
```

**`.context` lines:**
```
1. always                 → .context
```

The `PRLine` init call changes: drop `move:`, add `verbatimMoveCounterpart:`.

Also update `PRHunk.fromHunk()` mapping:
- `.added` → `.new`
- `.removed` → `.deleted`
- `.context`/`.header` → `.context`
- `verbatimMoveCounterpart` = nil for all (no move detection in this path)

### - [ ] Phase 3: Update consumers

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

### - [ ] Phase 4: Update tests

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

### - [ ] Phase 5: Validation

**Skills to read**: `/swift-testing`

1. Run `swift test` — all tests must pass
2. Run `swift build` — no compilation errors
3. Verify against test repo:
   ```bash
   cd PRRadarLibrary
   swift run PRRadarMacCLI diff 1 --config test-repo
   swift run PRRadarMacCLI analyze 1 --config test-repo
   ```
4. Spot-check that classification output uses new model and behavior matches pre-refactor output
