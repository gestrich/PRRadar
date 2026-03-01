## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules, placement guidance, dependency rules |
| `/swift-testing` | Test style guide and conventions |

## Compatibility

No backwards compatibility is needed for any data formats, APIs, or serialized outputs. Existing models can be changed freely without migration concerns.

## Background

PRRadar's effective diff pipeline produces rich information about what happened to each line — was it moved, changed within a move, or genuinely new? But this information is scattered across multiple overlapping systems that each track lines differently:

| System | Location | What it tracks | Granularity |
|--------|----------|---------------|-------------|
| `DiffLineType` | `Hunk.swift` | added/removed/context/header | Per-line, no move awareness |
| `TaggedLineType` | `LineMatching.swift` | added/removed (only changed lines) | Per-line, used for matching |
| `TaggedDL` | `DiffReconstruction.swift` | kept: Bool | Per-line, internal only |
| `HunkClassification` | `DiffReconstruction.swift` | moveRemoved/moveAdded/unchanged | Per-hunk only |
| `DisplayDiffLineType` | `GitDiff.swift` | addition/deletion/context | Per-line, no move awareness |
| `MovedLineLookup` | `RichDiffViews.swift` (MacApp) | isSource/isTarget move | Per-line, UI layer only |

The problem: to answer "is this line genuinely new code?" you have to combine data from multiple systems. The reconstructed effective diff strips moved lines but also strips new lines added inside moved blocks. The `EffectiveDiffResult.hunks` has the re-diffed changes but doesn't tag lines with their classification. The UI layer (`MovedLineLookup`) does per-line move detection but lives in the app layer and doesn't distinguish "moved" from "changed within move."

The fix: make per-line classification the **single source of truth**. Every diff line gets a classification (moved, changed-within-move, new, etc.) computed once from the effective diff results. Higher-level constructs — hunk classification, UI display, filtering — are all derived from these classified lines rather than computed independently.

### Test repo

A test repository is available at `/Users/bill/Developer/personal/PRRadar-TestRepo` with the CLI config `test-repo`:
```bash
cd PRRadarLibrary
swift run PRRadarMacCLI diff 1 --config test-repo
```
The `/pr-radar-verify-work` skill can also be used to run the CLI against the test repo.

## Phases

## - [x] Phase 1: Define `LineClassification` enum and `ClassifiedDiffLine` model

**Skills to read**: `/swift-app-architecture:swift-architecture`

Create the unified per-line classification model in `PRRadarModels`. This is the new source of truth for what happened to each line.

**New types:**

```swift
public enum LineClassification: String, Codable, Sendable {
    case new               // Genuinely new added line (not part of any move)
    case moved             // Line moved from one location to another, unchanged
    case changedInMove     // Line added/modified inside a moved block (from re-diff)
    case removed           // Line deleted (not part of a move)
    case movedRemoval      // Line removed as part of a move (the source side)
    case context           // Unchanged context line
}

public struct ClassifiedDiffLine: Sendable {
    public let content: String
    public let rawLine: String
    public let lineType: DiffLineType       // Original git diff type (added/removed/context)
    public let classification: LineClassification  // What actually happened
    public let newLineNumber: Int?
    public let oldLineNumber: Int?
    public let filePath: String
    public let moveCandidate: MoveCandidate?  // Which move this belongs to, if any
}
```

The `lineType` preserves the raw git diff info (added/removed/context), while `classification` captures the semantic meaning after effective diff analysis.

**Tasks:**
- Create `LineClassification` enum in `PRRadarModels`
- Create `ClassifiedDiffLine` struct in `PRRadarModels`
- Place in a new file `PRRadarModels/EffectiveDiff/ClassifiedDiffLine.swift`

**Files to create:**
- `PRRadarLibrary/Sources/services/PRRadarModels/EffectiveDiff/ClassifiedDiffLine.swift`

## - [x] Phase 2: Build the classification function

**Skills to read**: `/swift-app-architecture:swift-architecture`

Create the function that takes an original diff and the effective diff results and produces classified lines. This replaces the scattered logic in `filterMovedLines()`, `MovedLineLookup`, and `classifyHunk()`.

**Algorithm:**

1. Build lookup sets from `[EffectiveDiffResult]`:
   - `movedRemovedLines`: `[filePath: Set<Int>]` — old line numbers that are source-side of a move
   - `movedAddedLines`: `[filePath: Set<Int>]` — new line numbers that are target-side of a move
2. For each `DiffLine` in the original diff:
   - If `.removed` and old line number is in `movedRemovedLines` → `.movedRemoval`
   - If `.added` and new line number is in `movedAddedLines` → `.moved`
   - If `.added` and NOT in any move → `.new`
   - If `.removed` and NOT in any move → `.removed`
   - If `.context` → `.context`
3. Additionally, extract `.added` lines from each `EffectiveDiffResult.hunks` (the re-diffed move hunks) → `.changedInMove`

These re-diffed lines represent modifications made inside a moved block. They need file path and line number mapping back to the target file coordinates.

**Tasks:**
- Add a `classifyLines()` function (or method on a new `LineClassifier` struct) that takes `GitDiff` + `[EffectiveDiffResult]` → `[ClassifiedDiffLine]`
- Reuse the same moved-line set-building logic currently in `reconstructEffectiveDiff()` and `filterMovedLines()`
- Handle the re-diffed hunks from `EffectiveDiffResult.hunks` to produce `.changedInMove` lines
- Attach `MoveCandidate` reference to lines that are part of moves

**Files to modify/create:**
- `PRRadarLibrary/Sources/services/PRRadarModels/EffectiveDiff/ClassifiedDiffLine.swift` (add classification function)

**Completed:** Added `classifyLines(originalDiff:effectiveResults:)` free function. Builds six lookup dictionaries (source/target moved lines, changed-in-move lines, and per-line MoveCandidate references). Re-diff hunk line numbers are mapped to absolute target file coordinates via `extendBlockRange`. `.changedInMove` is checked before `.moved` since they're mutually exclusive subsets of the target move range. Header lines are skipped (no classification case for metadata).

## - [ ] Phase 3: Derive `ClassifiedHunk` from classified lines

**Skills to read**: `/swift-app-architecture:swift-architecture`

Create a hunk-level container that groups classified lines. Hunk classification is now derived from its lines rather than computed independently.

**New type:**

```swift
public struct ClassifiedHunk: Sendable {
    public let filePath: String
    public let oldStart: Int
    public let newStart: Int
    public let lines: [ClassifiedDiffLine]

    // Derived from lines, replaces HunkClassification
    public var isMoved: Bool { ... }
    public var hasNewCode: Bool { ... }
    public var hasChangesInMove: Bool { ... }

    // Filtering helpers
    public var newCodeLines: [ClassifiedDiffLine] { ... }
    public var changedLines: [ClassifiedDiffLine] { ... }
}
```

**Tasks:**
- Create `ClassifiedHunk` in `PRRadarModels`
- Add computed properties that derive hunk-level classification from lines
- Add a function to group `[ClassifiedDiffLine]` into `[ClassifiedHunk]` (splitting at file/hunk boundaries)
- The existing `HunkClassification` enum becomes derivable from a `ClassifiedHunk`'s lines

**Files to modify/create:**
- `PRRadarLibrary/Sources/services/PRRadarModels/EffectiveDiff/ClassifiedDiffLine.swift` (add ClassifiedHunk)

## - [ ] Phase 4: Wire into the effective diff pipeline output

**Skills to read**: `/swift-app-architecture:swift-architecture`

Add classified lines/hunks to the pipeline result so consumers have access to them.

**Tasks:**
- Add `classifiedLines: [ClassifiedDiffLine]` and/or `classifiedHunks: [ClassifiedHunk]` to `EffectiveDiffPipelineResult`
- Call the classification function at the end of `runEffectiveDiffPipeline()`, after reconstruction
- Ensure this doesn't change the existing `effectiveDiff` or `moveReport` outputs (additive change)

**Files to modify:**
- `PRRadarLibrary/Sources/services/PRRadarModels/EffectiveDiff/EffectiveDiffPipeline.swift`

## - [ ] Phase 5: Migrate `MovedLineLookup` to use classified lines

**Skills to read**: `/swift-app-architecture:swift-architecture`

Replace the UI layer's independent move-detection lookup with the classified line data. `MovedLineLookup` currently rebuilds move ranges from `MoveReport` — instead, it should consume the pre-computed classifications.

**Tasks:**
- Refactor `MovedLineLookup` to build from `[ClassifiedDiffLine]` or `[ClassifiedHunk]` instead of `MoveReport`
- Or simplify: pass classified hunks directly to the diff views, eliminating `MovedLineLookup` entirely if the classified data is sufficient
- Update `AnnotatedHunkContentView` and `DiffLineRowView` to use `ClassifiedDiffLine.classification` for move indicators
- Verify the orange move indicator still works correctly in the MacApp

**Files to modify:**
- `PRRadarLibrary/Sources/apps/MacApp/UI/GitViews/RichDiffViews.swift`
- Possibly other MacApp view files that consume `MovedLineLookup`

## - [ ] Phase 6: Migrate `reconstructEffectiveDiff` to use classified lines

**Skills to read**: `/swift-app-architecture:swift-architecture`

The effective diff reconstruction (`reconstructEffectiveDiff()` / `filterMovedLines()`) currently does its own per-line filtering using the internal `TaggedDL` struct. This can be simplified to filter by classification.

**Tasks:**
- Refactor `reconstructEffectiveDiff()` to use `[ClassifiedDiffLine]` — effective diff hunks are just lines where `classification != .moved && classification != .movedRemoval`
- Remove `TaggedDL` struct (replaced by `ClassifiedDiffLine.classification`)
- Remove `filterMovedLines()` or simplify it to a filter on classification
- Ensure the existing effective diff output (`GitDiff`) is unchanged in content
- Consider whether `classifyHunk()` and `HunkClassification` can be deprecated in favor of `ClassifiedHunk` derived properties

**Files to modify:**
- `PRRadarLibrary/Sources/services/PRRadarModels/EffectiveDiff/DiffReconstruction.swift`

## - [ ] Phase 7: Update the regex analysis plan

Update `2026-03-01-a-regex-analysis.md` Phase 2 to reference the unified classification model. The "new code lines only" filtering becomes trivial: filter `ClassifiedDiffLine` where `classification == .new` (or `.new` and `.changedInMove` depending on desired behavior).

**Tasks:**
- Rewrite Phase 2 of the regex analysis plan to use `ClassifiedDiffLine` instead of ad-hoc extraction from two sources
- Simplify Phase 4 (regex service) to operate on `[ClassifiedDiffLine]` filtered by classification
- Remove references to `EffectiveDiffResult.hunks` as a separate data source

**Files to modify:**
- `docs/proposed/2026-03-01-a-regex-analysis.md`

## - [ ] Phase 8: Validation

**Skills to read**: `/swift-testing`

**Tasks:**
- Add unit tests for `LineClassification`:
  - Genuinely new added line → `.new`
  - Added line that's part of a move → `.moved`
  - Added line from re-diffed move hunk → `.changedInMove`
  - Removed line that's part of a move → `.movedRemoval`
  - Removed line not part of a move → `.removed`
  - Context line → `.context`
- Add unit tests for `ClassifiedHunk` derived properties (`isMoved`, `hasNewCode`, `newCodeLines`, etc.)
- Add unit tests for the moved-method-with-interior-change scenario: a large method is moved, one line is added in the middle — verify that line is classified as `.changedInMove`
- Add unit tests for classification → effective diff reconstruction equivalence (verify the new path produces the same effective diff as the old path)
- Verify MacApp move indicators still work: `swift run MacApp` and inspect a PR with moved code
- Run full test suite: `cd PRRadarLibrary && swift test`
- Build check: `cd PRRadarLibrary && swift build`
- End-to-end check: `cd PRRadarLibrary && swift run PRRadarMacCLI diff 1 --config test-repo`
