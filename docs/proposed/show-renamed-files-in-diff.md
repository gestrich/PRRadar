# Show Moved/Renamed Files in Diff View

## Background

Moved or renamed files are not currently displayed in the diff view. This affects both the MacApp UI and the CLI output. The root cause is that the `GitDiff.fromDiffContent()` parser only creates `Hunk` objects for files that have `@@` sections. Pure renames (100% similarity, no content changes) produce no `@@` hunks in the raw diff, so they are invisible. Renames with content changes *do* appear but only under their new name — the old path is not shown.

**Example**: PR #18730 in ff-ios contains moved files that don't appear in the diff.

### Root Cause in the Parser

The `fromDiffContent()` parser (in `GitDiff.swift`) only writes a `Hunk` when `currentHunk` is non-empty (i.e., when `@@` lines were found). For pure renames, no `@@` section exists, so `currentHunk` stays empty and the file is silently dropped. Additionally, `rename from` / `rename to` header lines don't match any condition in the parser and are silently skipped.

### Git Diff Format for Renames

**Rename with changes:**
```
diff --git a/old/path.swift b/new/path.swift
similarity index 95%
rename from old/path.swift
rename to new/path.swift
index abc123..def456 100644
--- a/old/path.swift
+++ b/new/path.swift
@@ -1,5 +1,6 @@
 ... changes ...
```

**Pure rename (no content changes):**
```
diff --git a/old/path.swift b/new/path.swift
similarity index 100%
rename from old/path.swift
rename to new/path.swift
```
(No `@@` hunks follow — the parser creates no Hunk, so the file is lost.)

### Approach

Rather than introducing new model types, we add a single `renameFrom: String?` property to `Hunk` (matching git's own `rename from` terminology) and fix the parser to:
1. Parse `rename from` / `rename to` headers
2. Create a `Hunk` for pure renames even when there are no `@@` sections

This keeps renamed files as first-class `Hunk` objects in the pipeline. They appear in `diff.changedFiles`, can be selected as focus areas, assigned tasks, and eventually evaluated by rules (e.g., file naming convention checks). A pure rename is simply a hunk with `renameFrom` set and empty `diffLines` — no special cases needed downstream.

## Phases

## - [x] Phase 1: Hunk Model + Parser — Support Renames

**Completed**: Added `renameFrom: String?` to `Hunk` (optional, backward-compatible with existing JSON). Updated `fromDiffContent()` parser to recognize `rename from`/`rename to` headers and emit hunks for pure renames (no `@@` sections). Added `renamedFiles` computed property on `GitDiff`. All 273 tests pass (8 new rename-specific tests added in `GitDiffRenameTests.swift`).

### Hunk.swift (Services/PRRadarModels layer)

Add `renameFrom: String?` to `Hunk`:
- Default to `nil` in the existing `init` (no breaking changes to call sites)
- Include in `CodingKeys` so it persists in `diff-parsed.json`
- For renames with changes, `renameFrom` is set AND the hunk has normal `@@` content
- For pure renames, `renameFrom` is set but there are no `@@` sections (`diffLines` returns empty)

### GitDiff.swift (Services/PRRadarModels layer)

Update `fromDiffContent()`:

1. **Parse `rename from` / `rename to` lines** — Add these prefixes to the header-line conditions (alongside `similarity`, `new file`, `deleted file`). Track the `renameFrom` path per file during parsing.

2. **Create hunks for pure renames** — Currently, the parser only emits a hunk when `!currentHunk.isEmpty`. Add logic so that when a new `diff --git` is encountered (or end-of-file), if the previous file had `rename from` / `rename to` headers but no `@@` sections, a `Hunk` is still created with:
   - `filePath` = the new path (from `b/` in `diff --git`)
   - `renameFrom` = the old path (from `rename from` header)
   - `content` = the header lines only
   - `rawHeader` = the collected header lines
   - `oldStart`/`oldLength`/`newStart`/`newLength` = 0

3. **Pass `renameFrom` through for renames with changes** — When a rename also has `@@` hunks, set `renameFrom` on those hunks too.

### Convenience on GitDiff

Add a computed property for easy access:
```swift
public var renamedFiles: [(from: String, to: String)] {
    hunks.compactMap { hunk in
        hunk.renameFrom.map { (from: $0, to: hunk.filePath) }
    }
}
```

### Tests

Add unit tests in `PRRadarModelsTests` for:
- Parsing a pure rename (100% similarity, no `@@`) — verify a `Hunk` is created with `renameFrom` set and empty `diffLines`
- Parsing a rename with content changes — verify `renameFrom` is set AND `diffLines` are populated
- Parsing a mix of renamed, added, modified, and deleted files — verify all appear in `changedFiles`
- Verify `renamedFiles` convenience returns the correct pairs
- Verify existing non-rename diffs still parse identically (no regressions)

**Architecture note**: `Hunk` and `GitDiff` are shared data models in the Services layer — correct placement per the architecture guide. No @Observable, no orchestration.

## - [ ] Phase 2: UI — Display Renamed Files in Diff View

### DiffPhaseView.swift (Apps layer)

1. **File sidebar** — Update `plainFileList(for:)` and `annotatedFileList(for:)`:
   - `diff.changedFiles` (derived from hunks) will now include pure renames automatically
   - For files where a hunk has `renameFrom != nil`, show a rename annotation in the sidebar (e.g., the filename with a `→` indicator or a subtitle showing the old path)
   - Use a tooltip or secondary line to show the full old path when the filename itself didn't change (directory move)

2. **Diff content pane** — Update `diffContent(for:)`:
   - When a pure-rename file is selected (hunks exist but have no `@@` content), show a placeholder like "File renamed from `old/path.swift` — no content changes"
   - When a rename-with-changes file is selected, show the diff as normal but add a header bar indicating `Renamed from old/path.swift`

3. **Summary bar** — `summaryItems(for:)` already uses `diff.changedFiles.count` which will now include pure renames automatically

### SwiftUI architecture notes:
- Views connect directly to `GitDiff` data — no per-view ViewModel needed
- `@State` for `selectedFile` is appropriate for transient UI selection
- No @Observable model needed since `GitDiff` is a parameter

## - [ ] Phase 3: Architecture Validation

Review all commits made during the preceding phases and validate they follow the project's architectural conventions.

**For Swift changes** (`pr-radar-mac/`):
- Re-read the `swift-architecture` and `swift-swiftui` skills from `https://github.com/gestrich/swift-app-architecture` (`plugin/skills/`)
- Compare the commits made against the conventions described in each skill
- If any code violates the conventions, make corrections

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. Fetch and read ALL skills from the swift-app-architecture repo
4. Evaluate the changes against each skill's conventions
5. Fix any violations found

Key validations:
- `Hunk.renameFrom` is in the Services/Models layer (correct for shared data models)
- No @Observable annotations outside the Apps layer
- UI changes are in the Apps layer only
- No unnecessary new types or abstractions

## - [ ] Phase 4: Validation

### Automated Testing
```bash
cd pr-radar-mac
swift build    # Verify compilation
swift test     # Run all unit tests including new parser tests
```

### Manual Verification
Run the CLI against a PR with renamed files to verify end-to-end:
```bash
cd pr-radar-mac
swift run PRRadarMacCLI diff <PR_WITH_RENAMES> --config <config>
```

Verify:
- Pure renames appear in the diff output JSON (`renameFrom` field populated in hunks)
- Renames with changes show `renameFrom` alongside normal diff content
- `changedFiles` includes pure-rename file paths
- MacApp sidebar shows renamed files with annotation
- Selecting a pure rename shows the rename placeholder (not an empty view)
- Existing PRs without renames continue to work normally (no regressions)

### Success Criteria
- All existing tests pass
- New parser tests pass for rename scenarios
- Pure renames visible in both MacApp sidebar and CLI output
- Renames with changes show old path annotation
- No architectural violations
