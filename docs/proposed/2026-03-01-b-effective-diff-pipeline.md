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

**Files to modify:**
- `PRRadarLibrary/Sources/services/PRRadarCLIService/PRAcquisitionService.swift`

**Key considerations:**
- The `rediff` parameter type is `RediffFunction` — check `BlockExtension.swift` for the expected signature
- Need to read file contents at both base and head commits for moved-code detection
- This may require new methods on `GitOperationsService` to read file contents at specific commits (e.g., `git show <commit>:<path>`)
- The pipeline might be slow for large diffs — consider logging progress and keeping the fallback path solid

## - [ ] Phase 3: Verify effective diff with test repo and MacApp

**Skills to read**: `/swift-app-architecture:swift-swiftui`

With the pipeline wired up, verify end-to-end using the test repo at `/Users/bill/Developer/personal/PRRadar-TestRepo`.

**Tasks:**
- Run `swift run PRRadarMacCLI diff 1 --config test-repo` and inspect the output files to verify the effective diff differs from the full diff when moves exist
- Inspect `effective-diff-parsed.json` and `effective-diff-moves.json` to confirm they contain real pipeline data (not just a copy of the full diff)
- Compare hunk counts between `diff-parsed.json` and `effective-diff-parsed.json` — they should differ if the PR contains moved code
- Launch the MacApp, load the test-repo PR, and verify the "View Effective Diff" button appears and the sheet shows distinct content for the two tabs
- Check that the move report section in the left panel populates correctly with source/target files, matched line counts, and scores
- Fix any display or data-binding issues found

**Files potentially affected:**
- `PRRadarLibrary/Sources/apps/MacApp/UI/ReviewViews/EffectiveDiffView.swift`
- `PRRadarLibrary/Sources/apps/MacApp/UI/ReviewDetailView.swift`
- `PRRadarLibrary/Sources/apps/MacApp/Models/PRModel.swift`

## - [ ] Phase 4: Validation

**Skills to read**: `/swift-testing`

**Tasks:**
- Run existing effective diff tests to confirm nothing is broken: `cd PRRadarLibrary && swift test --filter EffectiveDiff`
- Run full test suite: `cd PRRadarLibrary && swift test`
- Build check: `cd PRRadarLibrary && swift build`
- Run the CLI against the test repo to confirm end-to-end: `cd PRRadarLibrary && swift run PRRadarMacCLI diff 1 --config test-repo`
- Verify effective diff output files contain real pipeline results (not just a copy of the full diff)
