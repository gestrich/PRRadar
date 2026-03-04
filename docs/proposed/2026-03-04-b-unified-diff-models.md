# Unified Diff Model Consolidation

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules (placement, dependency rules) |
| `/swift-testing` | Test style guide and conventions |

## Background

PRRadar currently has **29 diff-related types** spread across 12 files. Many overlap in purpose — there are 3 line-type enums, 2 line structs, 2 hunk structs, dual move report models (internal vs serializable), and display-only wrappers. Client code (views, analysis services, use cases) must navigate this maze to find the right type, and the relationships between them aren't obvious.

The root problem: the models evolved incrementally as features were added (move detection, classification, inline changes). Each feature introduced its own models rather than enriching existing ones. The result is a "sidecar" architecture where move data, classification data, and display data live in parallel structures that must be manually correlated.

### Current model count by concern

| Concern | Types | Notes |
|---------|-------|-------|
| Raw diff parsing | `GitDiff`, `Hunk`, `DiffLine`, `DiffLineType` | These are fine as primitives |
| Move detection internals | `TaggedLine`, `TaggedLineType`, `LineMatch`, `MoveCandidate`, `EffectiveDiffResult`, `RediffAnalysis`, `RediffFunction` | Algorithm internals — ok to keep internal |
| Classification | `ClassifiedDiffLine`, `ClassifiedHunk`, `ChangeKind` | The "enriched" models consumers actually need |
| Move reports (internal) | `EffectiveDiffMoveDetail`, `EffectiveDiffMoveReport` | Duplicates of serializable versions |
| Move reports (serializable) | `MoveDetail`, `MoveReport` | JSON output models |
| Display | `DisplayDiffSection`, `DisplayDiffLine`, `DisplayDiffLineType` | Thin wrappers, barely used |
| View helpers | `MovedLineLookup`, `MovedLineInfo`, `DiffCommentMapping`, `DiffCommentMapper`, `DiffLayout` | View-layer utilities |
| Composite | `AnnotatedDiff`, `EffectiveDiffPipelineResult` | Bundles of the above |
| Config/SDK | `DiffSource`, `GitCLI.Diff` | Unrelated, keep as-is |

### Goal

**Get raw diff data → Process through pipeline → Return one rich, unified model that all consumers use.**

Specifically:
1. One line model with all details (raw content, diff type, change kind, move status, inline changes)
2. One hunk model grouping those lines
3. One diff model containing those hunks plus move summary data baked in
4. Lower-level models (`GitDiff`, `DiffLine`, `Hunk`) remain as internal primitives — used during pipeline processing, then discarded
5. Fewer total models at the public API boundary
6. No backward compatibility required — this is an internal refactor with no external consumers. Old serialization formats, old types, and old APIs can be deleted outright once migrated. No dual-format support needs to persist after the plan is complete.
7. **Single entry point for callers.** A single use case should be the only way clients get a `PRDiff`. That use case handles fetching the raw diff, running the effective diff pipeline, and returning the fully-formed `PRDiff`. Callers (views via app models, CLI commands, analysis services) never coordinate raw fetching + processing themselves — they call one method and get back a `PRDiff`. This replaces the current pattern where `PRAcquisitionService`, `PhaseOutputParser`, and `AnnotatedDiff` are stitched together by each consumer.

### Naming convention

Using the **`PR` prefix** — app-branded and concise: `PRLine`, `PRHunk`, `PRDiff`.

### Target model shapes (illustrative)

```swift
// The one line model everyone uses
struct PRLine {
    let content: String           // stripped content
    let rawLine: String           // original with +/- prefix
    let diffType: DiffLineType    // .added, .removed, .context
    let changeKind: ChangeKind    // .added, .changed, .removed, .unchanged
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let filePath: String
    let move: MoveInfo?           // nil if not in a move (baked in, not sidecar)
    let inlineChanges: [InlineChangeSpan]?  // character-level diff
}

struct MoveInfo {
    let sourceFile: String
    let targetFile: String
    let isSource: Bool            // is this the removal side?
}

// The one hunk model
struct PRHunk {
    let filePath: String
    let oldStart: Int
    let newStart: Int
    let rawText: String           // original hunk text (header + diff lines)
    let lines: [PRLine]

    // Convenience (derived from lines)
    var isMoved: Bool
    var hasNewCode: Bool
    var newCodeLines: [PRLine]
    var changedLines: [PRLine]
}

// The one diff model
struct PRDiff {
    let commitHash: String
    let rawText: String           // full raw diff output
    let hunks: [PRHunk]
    let moves: [MoveDetail]       // summary of all detected moves
    let stats: DiffStats          // lines added/removed/moved counts

    // File-level queries
    var changedFiles: [String]
    func hunks(forFile:) -> [PRHunk]
}
```

### What gets eliminated

| Current type | Fate |
|-------------|------|
| `ClassifiedDiffLine` | → Replaced by `PRLine` |
| `ClassifiedHunk` | → Replaced by `PRHunk` |
| `AnnotatedDiff` | → Replaced by `PRDiff` |
| `EffectiveDiffPipelineResult` | → Pipeline returns `PRDiff` directly |
| `DisplayDiffLine` | → Removed (views use `PRLine` directly) |
| `DisplayDiffSection` | → Removed (views use `PRHunk` grouped by file) |
| `DisplayDiffLineType` | → Removed (use `DiffLineType.displayType` or `PRLine.diffType`) |
| `MovedLineLookup` | → Removed (move info is on each `PRLine`) |
| `MovedLineInfo` | → Removed (replaced by `MoveInfo` on the line) |
| `EffectiveDiffMoveDetail` | → Made internal to pipeline (not public) |
| `EffectiveDiffMoveReport` | → Made internal to pipeline (not public) |

**Net reduction: ~11 public types eliminated**, consolidated into 3-4 new types.

### What stays as-is

| Type | Why |
|------|-----|
| `GitDiff`, `Hunk`, `DiffLine`, `DiffLineType` | Good primitives. Used during pipeline processing, then discarded. |
| `MoveDetail`, `MoveReport` | Already Codable. Baked into `PRDiff.moves`. |
| `ChangeKind` | Semantic classification enum. Used by `PRLine.changeKind`. |
| `TaggedLine`, `LineMatch`, `MoveCandidate`, etc. | Algorithm internals. Never exposed to consumers. Already internal. |
| `DiffSource`, `GitCLI.Diff` | Unrelated config/SDK types. |
| `DiffCommentMapping`, `DiffCommentMapper` | View-layer utility, orthogonal to this refactor. |

## Phases

## - [x] Phase 1: Define unified models

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Models placed in Services layer (PRRadarModels), all types are Codable/Sendable/Equatable, factory methods for migration from old types

**Skills to read**: `/swift-app-architecture:swift-architecture`

Create new model types in `PRRadarModels/` using the chosen naming prefix. These are additive — nothing is deleted yet.

**New file**: `PRRadarLibrary/Sources/services/PRRadarModels/UnifiedDiff/` (directory)

1. Create `PRLine.swift` (or chosen prefix):
   - All properties from `ClassifiedDiffLine` plus `move: MoveInfo?` (baked-in move data)
   - `MoveInfo` struct with `sourceFile`, `targetFile`, `isSource`
   - Keep `inlineChanges: [InlineChangeSpan]?` (from the inline change detection spec)
   - Factory method `init(from classifiedLine:, moveInfo:)` for migration
   - Codable, Sendable, Equatable

2. Create `PRHunk.swift`:
   - Properties: `filePath`, `oldStart`, `newStart`, `lines: [PRLine]`
   - Computed properties migrated from `ClassifiedHunk`: `isMoved`, `hasNewCode`, `hasChangesInMove`, `newCodeLines`, `changedLines`
   - `relevantLines(newCodeLinesOnly:)` and `relevantLineNumbers(newCodeLinesOnly:)` methods
   - Static `filterForFocusArea()` method (migrated from `ClassifiedHunk`)
   - Codable, Sendable, Equatable

3. Create `PRDiff.swift`:
   - Properties: `commitHash`, `hunks: [PRHunk]`, `moves: [MoveDetail]`
   - Convenience: `changedFiles`, `hunks(forFile:)`, stats
   - Factory method that builds from pipeline output
   - Codable, Sendable, Equatable

4. Create `DiffStats.swift` (simple struct with line counts — added, removed, moved, changed)

## - [x] Phase 2: Update pipeline to produce unified models

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Dual output for migration — pipeline produces both old and new models. PRDiff serialized to pr-diff.json alongside existing files.

**Skills to read**: `/swift-app-architecture:swift-architecture`

Modify the effective diff pipeline to output the new unified models alongside existing ones (dual output for migration).

1. Update `runEffectiveDiffPipeline()` in `EffectiveDiffPipeline.swift`:
   - After existing processing, build `PRDiff` from the `classifiedHunks` + `moveReport`
   - Add `prDiff: PRDiff` to `EffectiveDiffPipelineResult`
   - The move info from `MoveReport` gets distributed to individual `PRLine`s based on line ranges

2. Update `PRAcquisitionService.runEffectiveDiff()`:
   - Serialize the new `PRDiff` to disk (e.g., `pr-diff.json`)
   - Keep existing serialization temporarily (removed in Phase 6)

3. Update `PhaseOutputParser.loadAnnotatedDiff()`:
   - Add method to load `PRDiff` from disk
   - Keep existing `AnnotatedDiff` loading temporarily (removed in Phase 6)

4. Add `prDiff: PRDiff?` to `AnnotatedDiff` (temporary bridge — removed in Phase 6 when `AnnotatedDiff` itself is deleted. No backward compat needed since there are no external consumers.)

## - [x] Phase 3: Create single-entry-point use case

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Single entry point via `LoadPRDiffUseCase`; PRDiff threaded through existing data flow (SyncSnapshot → PRDetail → PRModel); no direct PhaseOutputParser calls from client code

**Skills to read**: `/swift-app-architecture:swift-architecture`

Create a single use case that is the **only way clients get a `PRDiff`**. Callers never coordinate raw diff fetching, pipeline processing, or disk loading themselves. **`PhaseOutputParser.loadPRDiff()` must never be called directly by client code** — only `LoadPRDiffUseCase` may call it.

1. Create `LoadPRDiffUseCase` in features/PRReviewFeature/usecases/:
   - Wraps `PhaseOutputParser.loadPRDiff()` — this is the only caller of that method
   - Returns a fully-formed `PRDiff?`
   - This is the single call point — all consumers go through here or receive `PRDiff` as a parameter from a caller that already obtained it

2. Thread `PRDiff` through the standard data flow:
   - Add `prDiff: PRDiff?` to `SyncSnapshot` — loaded via `LoadPRDiffUseCase` in `SyncPRUseCase.parseOutput()`
   - Add `prDiff: PRDiff?` to `PRDetail` — surfaced from `SyncSnapshot`
   - Fix `PhaseOutputParser.loadAnnotatedDiff()` to populate `AnnotatedDiff.prDiff` from disk (Phase 2 gap)

3. `PRModel` (the app-layer observable model) obtains `PRDiff` through `detail?.prDiff` — it does not assemble diff data from multiple sources.

4. Later phases must follow the same rule: if a use case or service needs `PRDiff`, it receives it as a parameter from its caller (who got it from `LoadPRDiffUseCase` or from the `SyncSnapshot`/`PRDetail` data flow). No direct `PhaseOutputParser.loadPRDiff()` calls.

## - [x] Phase 4: Migrate analysis consumers

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: All consumers receive PRDiff/PRHunk as parameters; no direct PhaseOutputParser.loadAnnotatedDiff calls from client code; pure type substitution since PRHunk/PRLine have identical API shapes to ClassifiedHunk/ClassifiedDiffLine

**Skills to read**: `/swift-app-architecture:swift-architecture`

Switch analysis services and use cases from `ClassifiedHunk`/`ClassifiedDiffLine` to `PRHunk`/`PRLine`. All consumers receive `PRDiff` (or its hunks) as parameters — they never load it themselves and never call `PhaseOutputParser` directly.

Consumers to migrate (in order of isolation — least dependencies first):

1. **`RegexAnalysisService.analyzeTask()`** — currently takes `[ClassifiedHunk]`, change to `[PRHunk]`. Reads `.relevantLines()` and `.content` — both exist on new types.

2. **`ScriptAnalysisService.analyzeTask()`** — currently takes `[ClassifiedHunk]`, change to `[PRHunk]`. Reads `.relevantLineNumbers()` — exists on new type.

3. **`AnalysisService.runBatchAnalysis()`** — currently takes `AnnotatedDiff?`, reads `.classifiedHunks`. Change to take `PRDiff` and use its hunks.

4. **`AnalyzeSingleTaskUseCase.execute()`** — currently loads `AnnotatedDiff` itself via `PhaseOutputParser`. Change to receive `PRDiff` as a parameter (provided by the caller). Remove `PhaseOutputParser.loadAnnotatedDiff()` call.

5. **`AnalyzeUseCase.runEvaluations()`** — currently calls `PhaseOutputParser.loadAnnotatedDiff()` at line 222 and passes to `AnalyzeSingleTaskUseCase`. Change to load `PRDiff` via `LoadPRDiffUseCase` and pass it down.

6. **`RuleLoaderService.filterRulesForFocusArea()`** — currently takes `AnnotatedDiff`, calls `ClassifiedHunk.filterForFocusArea()`. Change to take `PRDiff` and use `PRHunk.filterForFocusArea()`.

7. **`TaskCreatorService.createAndWriteTasks()`** — currently takes `AnnotatedDiff`, reads `.fullDiff.commitHash`. Change to take `PRDiff` and read `.commitHash`.

8. **`PrepareUseCase`** — currently gets `AnnotatedDiff` via `SyncPRUseCase.parseOutput()`. Change to get `PRDiff` from `SyncSnapshot.prDiff` (already available from Phase 3) and pass to task creator.

## - [x] Phase 5: Migrate view consumers

**Skills used**: `swift-app-architecture:swift-architecture`, `swift-app-architecture:swift-swiftui`
**Principles applied**: Views receive PRDiff/PRHunk/PRLine directly; MovedLineLookup/MovedLineInfo eliminated (move info baked into PRLine.move); views still accept GitDiff for structural display (hunk headers, rename detection, comment mapping) pending Phase 6 consolidation

**Skills to read**: `/swift-app-architecture:swift-architecture`, `/swift-app-architecture:swift-swiftui`

Switch MacApp views from `AnnotatedDiff`/`ClassifiedHunk`/`ClassifiedDiffLine` + `MovedLineLookup` to the unified models. Views get `PRDiff` from `PRModel`, which gets it from the single-entry-point use case.

1. **`PRModel.swift`** — replace `fullDiff`/`effectiveDiff`/`moveReport` forwarding properties with a single `prDiff: PRDiff?` property. Obtained via the use case — model does not assemble diff data itself.

2. **`AnnotatedDiffContentView`** — currently takes `AnnotatedDiff`, builds `MovedLineLookup`, correlates classified hunks to raw hunks. Simplify to take `PRDiff` directly. `MovedLineLookup` becomes unnecessary since move info is on each `PRLine`.

3. **`AnnotatedHunkContentView`** — currently takes `ClassifiedHunk`. Change to `PRHunk`. Line iteration is the same.

4. **`DiffLineRowView`** — currently takes `ClassifiedDiffLine?` for popover info and `isMoved: Bool`. Change to take `PRLine`. Move status comes from `line.move != nil`.

5. **`LineInfoPopoverView`** — currently takes `ClassifiedDiffLine`. Change to `PRLine`. All fields are present.

6. **`DiffPhaseView`** and **`EffectiveDiffView`** — currently take `AnnotatedDiff`. Change to take `PRDiff`. The effective diff concept may become a filtered view of `PRDiff` (hunks where `!isMoved`) rather than a separate `GitDiff`.

7. **`ReviewDetailView`** — currently reads `annotatedDiff`. Change to read `prDiff`.

8. Remove `MovedLineLookup`, `MovedLineInfo`, `DisplayDiffLine`, `DisplayDiffSection`, `DisplayDiffLineType` once no longer referenced.

## - [ ] Phase 6: Remove old models and clean up

**Skills to read**: `/swift-app-architecture:swift-architecture`

Delete types that are no longer referenced after migration.

1. Delete `ClassifiedDiffLine` struct (replaced by `PRLine`)
2. Delete `ClassifiedHunk` struct (replaced by `PRHunk`)
3. Delete `AnnotatedDiff` struct (replaced by `PRDiff`)
4. Delete `EffectiveDiffPipelineResult` — pipeline returns `PRDiff` directly
5. Delete `DisplayDiffLine`, `DisplayDiffSection`, `DisplayDiffLineType`
6. Delete `MovedLineLookup`, `MovedLineInfo`
7. Make `EffectiveDiffMoveDetail` and `EffectiveDiffMoveReport` internal (remove `public`)
8. Remove old serialization files from `PRAcquisitionService` (effective-diff-parsed.json, classified-hunks.json) — replaced by `pr-diff.json`
9. Remove `loadAnnotatedDiff()` from `PhaseOutputParser` — replaced by `loadPRDiff()` (which is only called by `LoadPRDiffUseCase`)
10. Update all imports

## - [ ] Phase 7: Rename directory and audit

**Skills to read**: `/swift-app-architecture:swift-architecture`

1. Move new types from `UnifiedDiff/` to a permanent location (or rename directory to match chosen prefix, e.g., `PRDiff/`)
2. Audit all `public` types in `PRRadarModels` — ensure the diff-related public API is just:
   - Primitives: `GitDiff`, `Hunk`, `DiffLine`, `DiffLineType`
   - Unified: `PRDiff`, `PRHunk`, `PRLine`, `MoveInfo`, `DiffStats`
   - Enums: `ChangeKind`
   - Serializable: `MoveDetail`, `MoveReport`
3. Verify algorithm internals (`TaggedLine`, `LineMatch`, `MoveCandidate`, `EffectiveDiffResult`, `RediffAnalysis`) are not exposed as public

## - [ ] Phase 8: Validation

**Skills to read**: `/swift-testing`

1. Run `swift build` — must compile cleanly
2. Run `swift test` — all existing tests must pass
3. Update tests that referenced old types:
   - `LineClassificationTests` → use `PRLine`/`PRHunk`
   - `RegexAnalysisTests` → use `PRHunk`
   - `ScriptAnalysisTests` → use `PRHunk`
   - `GitHistoryProviderTests` → use `PRDiff`
   - `LoadPRDetailUseCaseTests` → use `PRDiff`
4. Add new tests:
   - `PRDiff` construction from pipeline output
   - `MoveInfo` population from `MoveReport` line ranges
   - `PRHunk` convenience properties match old `ClassifiedHunk` behavior
   - Round-trip serialization of `PRDiff`
5. Run `swift run PRRadarMacCLI analyze 1 --config test-repo` end-to-end to verify pipeline still works
6. Verify the MacApp builds and renders diffs correctly
