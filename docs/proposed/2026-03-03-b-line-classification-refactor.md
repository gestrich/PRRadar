# Line Classification Refactor: Two-Axis Model

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules (placement, dependency rules) |
| `/swift-testing` | Test style guide and conventions |

## Background

The current `LineClassification` enum has 6 cases that represent combinations of two independent concepts:

```swift
public enum LineClassification: String, Codable, Sendable, Equatable {
    case new            // added + not in move
    case moved          // unchanged + in move (target side)
    case changedInMove  // added OR changed + in move (conflates modifications and insertions)
    case removed        // removed + not in move
    case movedRemoval   // removed + in move (source side, conflates verbatim/modified/deleted)
    case context        // unchanged + not in move
}
```

Problems:
1. **`.changedInMove` conflates two things**: a modified line within a moved block (old content replaced) and a genuinely new insertion inside a moved block (no old content). These have different semantics for `newCodeLinesOnly` filtering.
2. **`.movedRemoval` conflates three things**: a line moved verbatim (content unchanged at destination), a line modified at destination, and a line deleted from the moved block.
3. **Adding new permutations doesn't scale**. The script analysis plan (2026-03-03-a) already surfaced the question of whether to add `.newInMove`, `.modifiedInMove`, `.removedInMove`, etc. — this combinatorial approach leads to an ever-growing enum.

### Proposed Model

Replace the single enum with two orthogonal axes:

1. **`ChangeKind`**: What happened to the content — `.added`, `.changed`, `.removed`, `.unchanged`
2. **`inMovedBlock: Bool`**: Whether this line is part of a detected code move

```
                    inMovedBlock: false          inMovedBlock: true
                    ──────────────────           ──────────────────
   .added           genuinely new line           new insertion inside moved block
   .changed         (future use)                 modified line in moved block
   .removed         genuinely deleted line       deleted from moved block
   .unchanged       context line                 verbatim moved line
```

`changeKind` describes what happened to the **content**, not how the line appears in the diff. The raw diff line type (`DiffLineType`: `.added`/`.removed`/`.context`) is already stored separately on `ClassifiedDiffLine` as `lineType`.

### How `newCodeLinesOnly` maps

- `newCodeLinesOnly: true` → `changeKind == .added` (regardless of `inMovedBlock`). This catches genuinely new lines AND new insertions inside moved blocks, but NOT modified lines.
- `newCodeLinesOnly: false` → `changeKind != .unchanged`. This is "you touched it, you own it" — any added, changed, or removed line qualifies.

### How the re-diff provides the information

The re-diff (from `computeEffectiveDiffForCandidate`) already contains exactly the information needed:

**Target side (`+` lines in re-diff):**
- Hunk with `oldLength == 0` (only `+` lines) → pure insertion → `changeKind: .added`
- Hunk with both `-` and `+` lines → first `min(removedCount, addedCount)` `+` lines are replacements → `changeKind: .changed`; surplus `+` lines beyond that count are insertions → `changeKind: .added`

**Source side (`-` lines in re-diff):**
- Source line appearing as `-` in re-diff with a corresponding `+` → modified at destination → `changeKind: .changed`
- Source line appearing as `-` in re-diff with no corresponding `+` → deleted from move → `changeKind: .removed`
- Source line NOT in re-diff (or appearing as context) → moved verbatim → `changeKind: .unchanged`

### Mapping old → new

| Old Classification | New Model |
|---|---|
| `.new` | `ChangeKind.added, inMovedBlock: false` |
| `.moved` | `ChangeKind.unchanged, inMovedBlock: true` |
| `.changedInMove` (modification) | `ChangeKind.changed, inMovedBlock: true` |
| `.changedInMove` (insertion) | `ChangeKind.added, inMovedBlock: true` |
| `.removed` | `ChangeKind.removed, inMovedBlock: false` |
| `.movedRemoval` (verbatim) | `ChangeKind.unchanged, inMovedBlock: true` |
| `.movedRemoval` (modified at dest) | `ChangeKind.changed, inMovedBlock: true` |
| `.movedRemoval` (deleted from move) | `ChangeKind.removed, inMovedBlock: true` |
| `.context` | `ChangeKind.unchanged, inMovedBlock: false` |

### Consumers to update

| File | Current usage | New usage |
|---|---|---|
| `ClassifiedDiffLine.swift` | `classifyLines()`, helpers (`changedLines`, `newCodeLines`, `isMoved`, etc.) | Produce new model; update helpers |
| `RegexAnalysisService.swift` | Checks `.new`, `.changedInMove` for `newCodeLinesOnly` | Check `changeKind == .added` |
| `DiffReconstruction.swift` | Strips `.moved` and `.movedRemoval` | Strip `inMovedBlock && changeKind == .unchanged` |
| `RichDiffViews.swift` | Looks up `.movedRemoval`, `.moved`, `.changedInMove` for UI coloring | Look up `inMovedBlock` + `changeKind` |
| `RuleLoaderService.swift` | Comment referencing `.new`, `.removed`, `.changedInMove` | Update comment |
| `LineClassificationTests.swift` | Asserts on old enum cases | Update to new model |
| `RegexAnalysisTests.swift` | Tests `newCodeLinesOnly` with old cases | Update to new model |

### Dependency

The script analysis plan (2026-03-03-a) Phase 1 includes a `newCodeLinesOnly` fix that changes `RegexAnalysisService` to exclude `.changedInMove`. **This refactor supersedes that fix** — once the two-axis model is in place, the `newCodeLinesOnly` semantics fall out naturally from `changeKind == .added`. The script analysis plan should remove that section from Phase 1 and list this refactor as a prerequisite.

## Phases

## - [x] Phase 1: Introduce new data model alongside existing enum

**Skills used**: `/swift-app-architecture:swift-architecture`
**Principles applied**: Re-diff analysis computed at effective diff creation time (inside `computeEffectiveDiffForCandidate`) rather than as post-processing; backward-compatible initializer bridges old `LineClassification` to new fields

**Skills to read**: `/swift-app-architecture:swift-architecture`

1. **Create `ChangeKind` enum** in `PRRadarModels/EffectiveDiff/ClassifiedDiffLine.swift`:
   ```swift
   public enum ChangeKind: String, Codable, Sendable, Equatable {
       case added
       case changed
       case removed
       case unchanged
   }
   ```

2. **Add `changeKind` and `inMovedBlock` properties to `ClassifiedDiffLine`** as stored properties alongside the existing `classification: LineClassification`. Provide a backward-compatible initializer that derives the new fields from the old `LineClassification`.

3. **Add `RediffAnalysis` struct and `analyzeRediffHunks` function** to `BlockExtension.swift`. The analysis classifies re-diff hunk lines as insertions vs modifications (target side) and modified vs deleted (source side), using absolute file coordinates. This is computed at effective diff creation time inside `computeEffectiveDiffForCandidate`.

4. **Add `rediffAnalysis: RediffAnalysis` to `EffectiveDiffResult`**. The analysis is computed alongside the re-diff hunks — not as a post-processing step — so the region start coordinates (`extendBlockRange`) are only computed once.

5. **Update `classifyLines()`** to read pre-computed `result.rediffAnalysis` instead of re-parsing hunks.

## - [x] Phase 2: Create `AnnotatedDiff` model

**Skills used**: `/swift-app-architecture:swift-architecture`
**Principles applied**: New services-layer model bundles diff data for threading through all layers; backward-compat computed properties on SyncSnapshot preserve existing callers during migration

**Skills to read**: `/swift-app-architecture:swift-architecture`

Currently, diff-related data (`fullDiff`, `effectiveDiff`, `moveReport`, `classifiedHunks`) is bundled at the feature layer inside `SyncSnapshot` but flows as **separate arguments** through services and views. There is no services-layer model that keeps all diff data together, which forces every consumer to accept `classifiedHunks` (and often `moveReport`) as extra parameters alongside the diff itself.

1. **Create `AnnotatedDiff` struct** in `PRRadarModels/GitDiffModels/AnnotatedDiff.swift`:
   ```swift
   public struct AnnotatedDiff: Codable, Sendable {
       public let fullDiff: GitDiff
       public let effectiveDiff: GitDiff?
       public let moveReport: MoveReport?
       public let classifiedHunks: [ClassifiedHunk]
   }
   ```
   This lives in the services layer (`PRRadarModels`) so all layers — services, features, apps — can depend on it.

   `commitHash` is already on `fullDiff.commitHash` and comes for free — no need for a separate field.

2. **Update `SyncSnapshot`** to hold an `AnnotatedDiff?` instead of four separate fields. Add **backward-compatible computed properties** so existing callers continue to compile during the migration:
   ```swift
   public struct SyncSnapshot: Sendable {
       public let annotatedDiff: AnnotatedDiff?
       // ... other PR metadata fields (files, commentCount, etc.)

       // Backward-compat bridges (removed in Phase 4)
       public var fullDiff: GitDiff? { annotatedDiff?.fullDiff }
       public var effectiveDiff: GitDiff? { annotatedDiff?.effectiveDiff }
       public var moveReport: MoveReport? { annotatedDiff?.moveReport }
       public var classifiedHunks: [ClassifiedHunk] { annotatedDiff?.classifiedHunks ?? [] }
   }
   ```

3. **Update `SyncPRUseCase.parseOutput()`** to assemble an `AnnotatedDiff` from the individual JSON files on disk (`diff-parsed.json`, `effective-diff-parsed.json`, `effective-diff-moves.json`, `classified-hunks.json`) and pass it to the `SyncSnapshot` initializer.

4. **Update `EffectiveDiffPipelineResult`** to produce an `AnnotatedDiff`. The pipeline already computes all four pieces — wrap them in `AnnotatedDiff` at the end of `runEffectiveDiffPipeline()`.

## - [x] Phase 3: Thread `AnnotatedDiff` through services

**Skills used**: `/swift-app-architecture:swift-architecture`
**Principles applied**: Consolidated 4-file AnnotatedDiff loading into `PhaseOutputParser.loadAnnotatedDiff()` (services layer) to eliminate duplication between use cases; services accept `AnnotatedDiff` instead of separate `classifiedHunks`/`commit` params

**Skills to read**: `/swift-app-architecture:swift-architecture`

Update service method signatures to accept `AnnotatedDiff` instead of a separate `classifiedHunks` parameter. Update each method's callers in the same step so the code compiles after each change.

1. **`TaskCreatorService.createTasks()`** and **`createAndWriteTasks()`**:
   - Replace `classifiedHunks: [ClassifiedHunk]` and `commit: String` with `annotatedDiff: AnnotatedDiff`
   - Inside: read `annotatedDiff.classifiedHunks` and `annotatedDiff.fullDiff.commitHash`
   - Update caller in `PrepareUseCase` (line 151): pass `diffSnapshot.annotatedDiff!` instead of separate `classifiedHunks:` and `commit:` args

2. **`RuleLoaderService.filterRulesForFocusArea()`**:
   - Replace `classifiedHunks: [ClassifiedHunk]` with `annotatedDiff: AnnotatedDiff`
   - Inside: read `annotatedDiff.classifiedHunks`
   - Update caller in `TaskCreatorService` (already updated above)

3. **`AnalysisService.runBatchAnalysis()`**:
   - Replace `classifiedHunks: [ClassifiedHunk]` with `annotatedDiff: AnnotatedDiff`
   - Inside: read `annotatedDiff.classifiedHunks`
   - Note: this method is currently only called from CLI commands — update those callers

4. **`AnalyzeSingleTaskUseCase.execute()`**:
   - Replace `classifiedHunks: [ClassifiedHunk]?` with `annotatedDiff: AnnotatedDiff?`
   - Replace `loadClassifiedHunks()` with a `loadAnnotatedDiff()` helper that reads all four JSON files (same pattern as `SyncPRUseCase.parseOutput()`)
   - Inside: read `annotatedDiff.classifiedHunks` when filtering for regex tasks
   - Update caller in `AnalyzeUseCase.runEvaluations()` (line 232): load `AnnotatedDiff` once before the loop and pass it through

5. **`AnalyzeUseCase.runEvaluations()`**:
   - Replace `classifiedHunks` loading (line 222) with `AnnotatedDiff` loading
   - Pass the loaded `AnnotatedDiff` to `AnalyzeSingleTaskUseCase.execute()` and `AnalysisService.runBatchAnalysis()`

## - [ ] Phase 4: Thread `AnnotatedDiff` through views and remove shims

**Skills to read**: `/swift-app-architecture:swift-architecture`

1. **`DiffPhaseView`**:
   - Replace `fullDiff: GitDiff`, `classifiedHunks: [ClassifiedHunk]?`, `moveReport: MoveReport?` with `annotatedDiff: AnnotatedDiff`
   - Inside: read `annotatedDiff.fullDiff`, pass `annotatedDiff` to `MovedLineLookup`
   - Update caller in `ReviewDetailView` (line 132)

2. **`ReviewDetailView`**:
   - Pass `prModel.syncSnapshot!.annotatedDiff!` to `DiffPhaseView`
   - Pass `annotatedDiff` to `EffectiveDiffView` instead of three separate props

3. **`EffectiveDiffView`**:
   - Replace `fullDiff: GitDiff`, `effectiveDiff: GitDiff`, `moveReport: MoveReport?` with `annotatedDiff: AnnotatedDiff`
   - Inside: read the individual fields from `annotatedDiff`

4. **`MovedLineLookup`**:
   - Replace `init(classifiedHunks: [ClassifiedHunk]?, moveReport: MoveReport?)` with `init(annotatedDiff: AnnotatedDiff?)`
   - Inside: read `annotatedDiff?.classifiedHunks` and `annotatedDiff?.moveReport`
   - Update `MovedLineLookup.empty` to use `init(annotatedDiff: nil)`

5. **Remove backward-compat computed properties** from `SyncSnapshot` (`fullDiff`, `effectiveDiff`, `moveReport`, `classifiedHunks`). All callers now use `annotatedDiff` directly. Fix any remaining compile errors.

## - [ ] Phase 5: Migrate classification consumers to `changeKind`/`inMovedBlock`

**Skills to read**: `/swift-app-architecture:swift-architecture`

With `AnnotatedDiff` threaded through, migrate consumers from the old `LineClassification` enum to the new two-axis fields. These consumers now access classification data via `annotatedDiff.classifiedHunks`.

1. **`ClassifiedHunk` helpers** — update computed properties:
   - `changedLines` → `lines.filter { $0.changeKind != .unchanged }`
   - `newCodeLines` → `lines.filter { $0.changeKind == .added }` (naturally includes new insertions inside moved blocks)
   - `isMoved` → `lines.filter { $0.changeKind != .unchanged }.isEmpty && lines.contains { $0.inMovedBlock }` (all non-context lines are verbatim moves)
   - `hasNewCode` → `lines.contains { $0.changeKind == .added }`
   - `hasChangesInMove` → `lines.contains { $0.changeKind == .changed && $0.inMovedBlock }`

2. **`RegexAnalysisService.analyzeTask`**:
   - `newCodeLinesOnly: true` → `filter { $0.changeKind == .added }`
   - `newCodeLinesOnly: false` → `filter { $0.changeKind != .unchanged }` (uses `changedLines` helper)

3. **`DiffReconstruction.reconstructEffectiveDiff`**:
   - Currently strips `.moved` and `.movedRemoval` → change to strip `inMovedBlock && changeKind == .unchanged`
   - Lines that are `inMovedBlock: true` but `changeKind: .changed` or `.added` or `.removed` survive — they represent actual content changes within the moved block

4. **`MovedLineLookup`**:
   - Deletion side: check `inMovedBlock == true` (replaces `classification == .movedRemoval`)
   - Addition side: check `inMovedBlock == true` (replaces `classification == .moved || classification == .changedInMove`)
   - The UI can now optionally distinguish `.changed` from `.added` within moved blocks for richer coloring

5. **`RuleLoaderService`**: Update comment to reference new model.

## - [ ] Phase 6: Remove old `LineClassification` enum

**Skills to read**: `/swift-app-architecture:swift-architecture`

1. **Remove `classification: LineClassification` field** from `ClassifiedDiffLine`
2. **Remove `LineClassification` enum** entirely
3. **Remove the backward-compatible initializer** added in Phase 1
4. **Update `ClassifiedDiffLine.init`** to only accept `changeKind` and `inMovedBlock`
5. **Verify all `Codable` serialization** works with the new fields — intermediate JSON files (classified hunks) will use the new format

## - [ ] Phase 7: Update tests

**Skills to read**: `/swift-testing`

1. **`LineClassificationTests`**:
   - Update all assertions from old enum cases to new `(changeKind, inMovedBlock)` pairs
   - Add new test: insertion inside moved block → `(.added, true)` — uses the `largeMethodMovedWithOneLineAdded` fixture, now distinguished from modification
   - Add new test: modification inside moved block → `(.changed, true)` — uses the `movedMethodWithModifiedLine` fixture
   - Add new test: source line modified at destination → `(.changed, true)` on source side
   - Add new test: source line deleted from move → `(.removed, true)` on source side
   - Verify verbatim moved lines are `(.unchanged, true)` on both source and target sides

2. **`RegexAnalysisTests`**:
   - Update `newCodeLinesOnly` tests to use new model
   - Add test: `newCodeLinesOnly: true` with `(.added, inMovedBlock: true)` line → violation IS detected (new insertion in move passes the filter)
   - Add test: `newCodeLinesOnly: true` with `(.changed, inMovedBlock: true)` line → violation NOT detected (modification excluded)

3. **Effective diff end-to-end tests**: Verify that the full pipeline (parse diff → find moves → re-diff → classify) produces correct `(changeKind, inMovedBlock)` pairs.

4. **`DiffReconstruction` tests**: Verify that lines with `(.changed, true)` and `(.added, true)` survive reconstruction while `(.unchanged, true)` are stripped.

5. **`AnnotatedDiff` tests**: Verify that `SyncPRUseCase.parseOutput()` correctly assembles an `AnnotatedDiff` from disk, and that services/views can read its fields.

## - [ ] Phase 8: Validation

**Skills to read**: `/swift-testing`

1. Run full test suite: `cd PRRadarLibrary && swift test`
2. Run build: `cd PRRadarLibrary && swift build`
3. Verify the MacApp builds and the rich diff view still renders correctly with moved-block highlighting
4. Run a sample analysis to verify `newCodeLinesOnly` filtering works: `swift run PRRadarMacCLI analyze 1 --config test-repo`
