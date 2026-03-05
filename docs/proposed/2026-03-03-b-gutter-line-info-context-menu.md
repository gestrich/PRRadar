# Gutter Line Info Context Menu

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules (placement, dependency rules) |
| `/swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns, observable model conventions |
| `/swift-testing` | Test style guide and conventions |

## Background

When debugging false positives in rule evaluation (e.g., whitespace-only changes flagged as new code), there's no way to inspect how PRRadar classified a diff line without digging into the JSON output files. Adding a right-click context menu on the diff gutter that shows a "Line Info" popover would surface this debug data directly in the GUI.

**Current state:** `DiffLineRowView` accepts a `PRLine` (the unified line model from `PRDiff`) and renders the gutter (line numbers, move indicator). The full classification data — `contentChange`, `pairing`, `isSurroundingWhitespaceOnlyChange` — is already on `PRLine` and is directly accessible in the view. `EffectiveDiffView` and `DiffPhaseView` both take `PRDiff`, so classified data flows through to the line-level views without any additional threading needed.

**Note:** Prerequisite work (replacing the old `DiffLineData`/`HunkLineParser` view models, threading classified hunks through `EffectiveDiffView`, removing `MovedLineLookup`) was completed as part of the unified diff model consolidation (`2026-03-04-b-unified-diff-models.md`). The classification model was also updated to use `contentChange`/`pairing` instead of `changeKind`/`inMovedBlock` (`2026-03-04-c-classification-model-consolidation.md`).

## Phases

### - [ ] Phase 1: Add gutter context menu with Line Info popover

**Skills to read**: `/swift-app-architecture:swift-swiftui`

Add a right-click context menu on the gutter area of `DiffLineRowView` with a "Line Info" item that shows classification debug data.

**File**: `PRRadarLibrary/Sources/apps/MacApp/UI/GitViews/RichDiffViews.swift`

In `DiffLineRowView`:
- Add `.contextMenu` to the gutter `HStack` with a "Line Info" button
- When tapped, show a popover (using `@State private var showLineInfo = false` + `.popover(isPresented:)`)
- The popover shows a `LineInfoPopoverView` containing:
  - **Content Change**: `.added` / `.modified` / `.deleted` / `.unchanged` (from `line.contentChange`)
  - **Pairing Role**: `.before` / `.after` / none (from `line.pairing?.role`)
  - **Counterpart**: file path and line number of the paired line, if any (from `line.pairing?.counterpart`)
  - **Surrounding Whitespace Only**: yes/no (from `line.isSurroundingWhitespaceOnlyChange`)
  - **Diff Type**: `.added` / `.removed` / `.context` (from `line.diffType`)
  - **Old Line #** / **New Line #**
  - **File Path**
  - **Raw Line**: the original diff line text
- Use a compact, monospaced layout (similar to existing popover patterns in `CodeView.swift`)

### - [ ] Phase 2: Validation

**Skills to read**: `/swift-testing`

1. Run `swift build` to verify compilation
2. Run `swift test` to verify existing tests pass
3. Manual verification:
   - Run `swift run MacApp`
   - Open a PR with classified hunks
   - Right-click on the gutter of a diff line
   - Verify "Line Info" appears in the context menu
   - Verify the popover shows correct classification data
   - Check that surrounding-whitespace-only lines show `contentChange = modified`, `isSurroundingWhitespaceOnlyChange = true`
   - Check that verbatim moved lines show `contentChange = unchanged`, `pairing != nil`
   - Check that genuinely added lines show `contentChange = added`, `pairing = nil`
