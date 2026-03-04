# Gutter Line Info Context Menu

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules (placement, dependency rules) |
| `/swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns, observable model conventions |
| `/swift-testing` | Test style guide and conventions |

## Background

When debugging false positives in rule evaluation (e.g., whitespace-only changes flagged as new code), there's no way to inspect how PRRadar classified a diff line without digging into the JSON output files. Adding a right-click context menu on the diff gutter that shows a "Line Info" popover would surface this debug data directly in the GUI.

**Current state:** `DiffLineRowView` renders the gutter (line numbers, move indicator) but only receives basic display data via `DiffLineData` (a view-only model created by `HunkLineParser` from raw `Hunk` data). The full classification data (`ClassifiedDiffLine` with `changeKind`, `inMovedBlock`) lives in `AnnotatedDiff.classifiedHunks` but is not wired to the line-level views — only move detection is bridged via `MovedLineLookup`.

**Key insight:** `ClassifiedDiffLine` is a superset of `DiffLineData` — it has all the same fields plus `changeKind`, `inMovedBlock`, `rawLine`, and `filePath`. Classified data is always created upstream during the sync phase (`PRAcquisitionService.runEffectiveDiff()`), so we can replace the view-layer `DiffLineData` / `HunkLineParser` with `ClassifiedDiffLine` / `ClassifiedHunk` directly.

**Callers of `AnnotatedDiffContentView`:**
1. `DiffPhaseView` — already has `annotatedDiff` with `classifiedHunks`
2. `EffectiveDiffView` — currently only receives raw `GitDiff`, but its caller (`ReviewDetailView:150`) has the full `annotatedDiff`. Just needs to be threaded through.

## Phases

### - [ ] Phase 1: Replace DiffLineData/HunkLineParser with ClassifiedDiffLine/ClassifiedHunk in views

**Skills to read**: `/swift-app-architecture:swift-swiftui`

Replace the view-layer data model with the existing domain model.

**File**: `PRRadarLibrary/Sources/apps/MacApp/UI/GitViews/RichDiffViews.swift`

- Delete `DiffLineData` struct and `HunkLineParser` enum — no longer needed
- Change `AnnotatedHunkContentView` to accept `ClassifiedHunk` instead of `Hunk`
  - Replace `private var diffLineData: [DiffLineData]` with iteration over `ClassifiedHunk.lines`
  - Use `ClassifiedDiffLine.newLineNumber`, `.oldLineNumber`, `.content`, `.lineType` where `DiffLineData` fields were used
  - Map `DiffLineType` → `DisplayDiffLineType` for `DiffLineRowView` (or update `DiffLineRowView` to use `DiffLineType` directly)
- Change `AnnotatedDiffContentView` to accept `[ClassifiedHunk]` alongside (or instead of) `GitDiff`
  - Iterate over classified hunks grouped by file path instead of `diff.getHunks(byFilePath:)`
- Pass `ClassifiedDiffLine` to `DiffLineRowView` (as a new parameter) so it has the full classification data available
- `MovedLineLookup` may become unnecessary since `ClassifiedDiffLine.inMovedBlock` is now directly available on each line. Evaluate whether it can be removed or simplified.

### - [ ] Phase 2: Thread ClassifiedHunks through EffectiveDiffView

**Skills to read**: `/swift-app-architecture:swift-swiftui`

Wire the classified hunks through the one callsite that currently lacks them.

**Files to modify**:
- `PRRadarLibrary/Sources/apps/MacApp/UI/ReviewViews/EffectiveDiffView.swift` — accept `classifiedHunks: [ClassifiedHunk]` parameter and pass to `AnnotatedDiffContentView`
- `PRRadarLibrary/Sources/apps/MacApp/UI/ReviewDetailView.swift` (line ~150) — pass `annotatedDiff.classifiedHunks` when constructing `EffectiveDiffView`

### - [ ] Phase 3: Add gutter context menu with Line Info popover

**Skills to read**: `/swift-app-architecture:swift-swiftui`

Add a right-click context menu on the gutter area of `DiffLineRowView` with a "Line Info" item that shows classification debug data.

**File**: `PRRadarLibrary/Sources/apps/MacApp/UI/GitViews/RichDiffViews.swift`

In `DiffLineRowView`:
- Add `.contextMenu` to the gutter `HStack` with a "Line Info" button
- When tapped, show a popover (using `@State private var showLineInfo = false` + `.popover(isPresented:)`)
- The popover shows a `LineInfoPopoverView` containing:
  - **Change Kind**: `.added` / `.changed` / `.removed` / `.unchanged`
  - **Line Type**: `.added` / `.removed` / `.context`
  - **In Moved Block**: yes/no
  - **Old Line #** / **New Line #**
  - **File Path**
  - **Raw Line**: the original diff line text
- Use a compact, monospaced layout (similar to existing popover patterns in `CodeView.swift`)

### - [ ] Phase 4: Validation

**Skills to read**: `/swift-testing`

1. Run `swift build` to verify compilation
2. Run `swift test` to verify existing tests pass
3. Manual verification:
   - Run `swift run MacApp`
   - Open a PR with classified hunks
   - Right-click on the gutter of a diff line
   - Verify "Line Info" appears in the context menu
   - Verify the popover shows correct classification data
   - Check that whitespace-only lines show `changeKind = unchanged` (ties into the Phase 2 fix from the false-positive spec)
   - Check that moved lines show `inMovedBlock = true`
   - Check that genuinely added lines show `changeKind = added`
