## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-swiftui` | Observable model conventions, state management |
| `/swift-testing` | Test style guide |

## Background

In a previous refactor, we unified `PRModel`'s dual in-flight tracking (`activeAnalysisFilePath: String?` and `selectiveAnalysisInFlight: Set<String>`) into a single `tasksInFlight: Set<RuleRequest>`. Both `DiffPhaseView` and `RichDiffViews` now use `tasksInFlight` exclusively to show per-file and per-focus-area spinners.

However, `activeAnalysisFilePath` still exists as a computed property (`liveAccumulators.last?.filePath`) and is passed to `AITranscriptView` to show a spinner next to the file group header that is currently streaming. The problem: this only tracks a single file path (the last accumulator's), so if multiple `RuleRequest`s are being evaluated concurrently (e.g. during `runFilteredAnalysis`), only the most recently started file shows a spinner.

Since `tasksInFlight` already correctly tracks all in-flight `RuleRequest`s, `AITranscriptView` should use it too — making `activeAnalysisFilePath` unnecessary and fully removing the last vestige of the old single-cursor tracking.

## Phases

## - [x] Phase 1: Pass `tasksInFlight` to `AITranscriptView`

**Skills to read**: `/swift-app-architecture:swift-swiftui`

In `AITranscriptView`:
- Replace `var activeFilePath: String?` with `var tasksInFlight: Set<RuleRequest> = []`
- Change the spinner check at line 182 from `if activeFilePath == group.filePath` to `if tasksInFlight.contains(where: { $0.focusArea.filePath == group.filePath })`
- This means all file groups with in-flight tasks show spinners simultaneously, not just the last one to start streaming

In `ReviewDetailView` (lines 186-188):
- Change `activeFilePath: prModel.activeAnalysisFilePath` to `tasksInFlight: prModel.tasksInFlight`
- The non-streaming call sites (lines 190, 192) don't pass either parameter, so they need no change

**Completed**: Both `AITranscriptView` and `ReviewDetailView` updated. The non-streaming call sites (lines 190, 192) correctly use the default empty set since they omit the parameter.

## - [x] Phase 2: Remove `activeAnalysisFilePath`

**Skills to read**: none

In `PRModel`:
- Delete the `activeAnalysisFilePath` computed property (lines 30-32)
- Verify no other files reference it (the grep from earlier showed only `AITranscriptView` and `ReviewDetailView`, both updated in Phase 1)

**Completed**: Deleted the `activeAnalysisFilePath` computed property from `PRModel`. Grep confirmed no remaining references in source code. Build passes cleanly.

## - [ ] Phase 3: Validation

**Skills to read**: `/swift-testing`

- `swift build` — verify no compile errors
- `swift test` — all existing tests pass
- Manual spot-check: during full analysis, the transcript sidebar shows spinners on all file group headers that have pending `RuleRequest`s, not just the currently-streaming one
- Manual spot-check: selective analysis still shows spinners correctly in both the diff view and transcript view
