## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules, placement guidance, dependency rules |
| `/swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns, observable model conventions |
| `/swift-testing` | Test style guide and conventions |

## Background

The effective diff system in PRRadar is designed to detect **moved code blocks** in a diff and produce a reduced diff showing only real changes (not relocated code). The algorithms are fully implemented in `PRRadarModels/EffectiveDiff/` (5 source files) with line matching, block aggregation, re-diffing, and reconstruction. There are also comprehensive tests (6 test files).

However, the pipeline is **not wired up** in the acquisition service. `PRAcquisitionService.swift` (lines 195-205) currently just copies the full diff as the effective diff and writes an empty move report. This means:
- The "View Effective Diff" button in the MacApp shows identical content for both tabs
- The move report section is always empty

This plan connects the existing effective diff pipeline so it runs during PR acquisition and produces real results, viewable through the MacApp's Effective Diff view. This is a prerequisite for the regex-based analysis feature planned in `2026-03-01-a-regex-analysis.md`.

### Scope: view-only, no impact on analysis

The effective diff is **view-only** in this plan — it must not change how the main analysis pipeline works. Currently `PrepareUseCase.swift:40` prefers the effective diff over the full diff:
```swift
guard let fullDiff = diffSnapshot.effectiveDiff ?? diffSnapshot.fullDiff else {
```
This line must be changed to always use `fullDiff` so that focus area generation, rule matching, and AI evaluation continue to operate on the full diff. The effective diff output files are written separately and consumed only by the MacApp's `EffectiveDiffView`.

### Test repo

A test repository is available at `/Users/bill/Developer/personal/PRRadar-TestRepo` with the CLI config `test-repo`. Use this to verify changes against real PR diffs:
```bash
cd PRRadarLibrary
swift run PRRadarMacCLI diff 1 --config test-repo
```
The `/pr-radar-verify-work` skill can also be used to run the CLI against the test repo.

### Key findings from codebase exploration

1. **`runEffectiveDiffPipeline()`** in `EffectiveDiffPipeline.swift` takes: `gitDiff`, `oldFiles` (path → content), `newFiles` (path → content), and a `rediff` function. Returns `EffectiveDiffPipelineResult` with the effective `GitDiff` and `EffectiveDiffMoveReport`.

2. **`RediffFunction`** type is defined in `BlockExtension.swift` — need to check its exact signature to implement the `rediff` callback using `git diff --no-index`.

3. **`PRAcquisitionService.acquire()`** already has the full diff parsed as `GitDiff` and knows the commit hash. It needs to additionally read old/new file contents for changed files to feed the pipeline.

4. **`EffectiveDiffView`** in the MacApp is fully built with file list, move report panel, and diff rendering. It just needs real data.

5. **Existing tests** cover line matching, block aggregation, reconstruction, re-diffing, scoring, and end-to-end. The pipeline logic itself is well-tested — this work is about integration.

## Phases

## - [x] Phase 1: Ensure analysis pipeline uses full diff, not effective diff

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Minimal change — removed effective diff fallback so analysis pipeline always uses full diff, preventing silent behavior change when real effective diffs are produced.

**Skills to read**: `/swift-app-architecture:swift-architecture`

Before wiring up the real effective diff, fix `PrepareUseCase` so it always uses the full diff for analysis. Currently it prefers the effective diff (`diffSnapshot.effectiveDiff ?? diffSnapshot.fullDiff`), which would silently change analysis behavior once real effective diffs are produced.

**Tasks:**
- In `PrepareUseCase.swift:40`, change `diffSnapshot.effectiveDiff ?? diffSnapshot.fullDiff` to `diffSnapshot.fullDiff`
- Verify the full pipeline still works: `cd PRRadarLibrary && swift run PRRadarMacCLI analyze 1 --config test-repo`

**Files to modify:**
- `PRRadarLibrary/Sources/features/PRReviewFeature/usecases/PrepareUseCase.swift`

## - [x] Phase 2: Wire up effective diff pipeline in PRAcquisitionService

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: SDK layer gets `MergeBase` command and `getMergeBase()` method (single git operation, stateless). Service layer orchestrates pipeline call with graceful fallback. Rediff function implemented as file-level helper matching test pattern.

**Skills to read**: `/swift-app-architecture:swift-architecture`

Currently `PRAcquisitionService` writes the full diff as the effective diff (lines 195-205). This phase connects the real pipeline. The effective diff output is separate from the full diff and is only consumed by the MacApp's `EffectiveDiffView`.

**Tasks:**
- In `PRAcquisitionService.swift`, after parsing the full diff, call `runEffectiveDiffPipeline()` to produce a real effective diff and move report
- The pipeline requires `oldFiles` and `newFiles` dictionaries (file path → content). Use `gitOps` to read old (base) and new (head) file contents for all changed files in the diff
- The pipeline also requires a `rediff` function — implement this using `git diff --no-index` (already available via `gitOps`)
- Write the real effective diff JSON and move report to the same file paths currently used
- Keep the full diff separate (`diff-parsed.json`) and write the effective diff to `effective-diff-parsed.json`
- Convert the algorithm-internal `EffectiveDiffMoveReport` to the Codable `MoveReport` using `.toMoveReport()` before writing
- Handle errors gracefully: if the effective diff pipeline fails, fall back to the current behavior (full diff as effective diff with empty move report)
- After implementation, run `swift run PRRadarMacCLI diff 1 --config test-repo` against the test repo and inspect the output `effective-diff-parsed.json` and `effective-diff-moves.json` to confirm they differ from the full diff

**Files modified:**
- `PRRadarLibrary/Sources/services/PRRadarCLIService/PRAcquisitionService.swift` (pipeline call, `runEffectiveDiff` method)
- `PRRadarLibrary/Sources/sdks/GitSDK/GitOperationsService.swift` (`getMergeBase`, `getFileContent` methods)

## - [x] Phase 3: Verify effective diff with test repo and MacApp

**Skills used**: `swift-app-architecture:swift-swiftui`, `swift-app-architecture:swift-architecture`
**Principles applied**: Verification against the test repo revealed two issues that were fixed in this phase: (1) the reconstruction algorithm dropped non-moved changes that shared a hunk with moved code — switched from hunk-level to line-level filtering; (2) the diff viewer had no visual indicator for moved lines — added orange arrow gutter icons that open the EffectiveDiffView pre-focused on the relevant move.

**Skills to read**: `/swift-app-architecture:swift-swiftui`

With the pipeline wired up, verify end-to-end using the test repo at `/Users/bill/Developer/personal/PRRadar-TestRepo`.

**Tasks:**
- Run `swift run PRRadarMacCLI diff 1 --config test-repo` and inspect the output files to verify the effective diff differs from the full diff when moves exist
- Inspect `effective-diff-parsed.json` and `effective-diff-moves.json` to confirm they contain real pipeline data (not just a copy of the full diff)
- Compare hunk counts between `diff-parsed.json` and `effective-diff-parsed.json` — they should differ if the PR contains moved code
- Launch the MacApp, load the test-repo PR, and verify the "View Effective Diff" button appears and the sheet shows distinct content for the two tabs
- Check that the move report section in the left panel populates correctly with source/target files, matched line counts, and scores
- Fix any display or data-binding issues found

**Issues found and fixed:**

1. **Reconstruction dropped non-moved changes** — the original hunk-level approach classified entire hunks as move-removed or move-added, which lost legitimate changes sharing a hunk with moved code. Switched `DiffReconstruction` to line-level filtering using `MoveCandidate` line numbers, splitting hunks at boundaries to preserve correct line numbers. Also reduced `defaultContextLines` from 20 to 3 to avoid pulling unrelated code into re-diff regions.

2. **No visual indicator for moved lines in the diff viewer** — added `MovedLineLookup` to cross-reference the `MoveReport` with individual diff lines. Lines that are part of a detected code move now show an orange arrow icon in the gutter. Tapping it opens the `EffectiveDiffView` sheet pre-focused on the relevant move via the `initialMove` parameter.

3. **`diffNoIndex` was synchronous** — the rediff function used a manual `Process` spawn, inconsistent with the rest of the codebase. Replaced the synchronous free function `gitDiffNoIndex` with an async `GitOperationsService.diffNoIndex` method routed through `GitCLI.Diff(noIndex:noColor:)` via `CLIClient`.

**Files modified:**
- `PRRadarLibrary/Sources/services/PRRadarModels/EffectiveDiff/DiffReconstruction.swift` (line-level filtering)
- `PRRadarLibrary/Sources/services/PRRadarModels/EffectiveDiff/BlockExtension.swift` (async rediff signature)
- `PRRadarLibrary/Sources/services/PRRadarModels/EffectiveDiff/EffectiveDiffPipeline.swift` (async pipeline)
- `PRRadarLibrary/Sources/sdks/GitSDK/GitOperationsService.swift` (async `diffNoIndex`)
- `PRRadarLibrary/Sources/apps/MacApp/UI/GitViews/RichDiffViews.swift` (moved line gutter indicators, `MovedLineLookup`)
- `PRRadarLibrary/Sources/apps/MacApp/UI/ReviewDetailView.swift` (pass move report, handle move taps)
- `PRRadarLibrary/Sources/apps/MacApp/UI/ReviewViews/EffectiveDiffView.swift` (`initialMove` navigation)
- `PRRadarLibrary/Sources/apps/MacApp/UI/PhaseViews/DiffPhaseView.swift` (`onMoveTapped` callback)
- `PRRadarLibrary/Tests/PRRadarModelsTests/EffectiveDiffReconstructionTests.swift` (line-level filtering tests)
- `PRRadarLibrary/Tests/PRRadarModelsTests/EffectiveDiffRediffTests.swift` (async rediff tests)
- `PRRadarLibrary/Tests/PRRadarModelsTests/EffectiveDiffEndToEndTests.swift` (async pipeline tests)

## - [x] Phase 4: Validation

**Skills used**: `swift-testing`
**Principles applied**: Ran effective diff tests (141 tests in 24 suites) and full test suite (499 tests in 55 suites) — all passing.

**Skills to read**: `/swift-testing`

**Tasks:**
- Run existing effective diff tests to confirm nothing is broken: `cd PRRadarLibrary && swift test --filter EffectiveDiff`
- Run full test suite: `cd PRRadarLibrary && swift test`
- Build check: `cd PRRadarLibrary && swift build`
- Run the CLI against the test repo to confirm end-to-end: `cd PRRadarLibrary && swift run PRRadarMacCLI diff 1 --config test-repo`
- Verify effective diff output files contain real pipeline results (not just a copy of the full diff)
- Verify that the analysis pipeline (`swift run PRRadarMacCLI analyze 1 --config test-repo`) still uses the full diff, not the effective diff, for focus area generation and evaluation
