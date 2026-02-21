## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-swiftui` | Observable model conventions, state management |
| `/swift-testing` | Test style guide |

## Background

During the analyze phase, the pipeline evaluates a list of `RuleRequest` values (each a rule + focus area pairing, identified by a `taskId: String`). `PRModel` has two parallel mechanisms for tracking which `RuleRequest`s are currently being evaluated:

1. **`activeAnalysisFilePath: String?`** — a single-cursor `String` set to the current `RuleRequest`'s `focusArea.filePath` in `appendAIPrompt` and cleared in `handleTaskEvent(.completed)`. Points to whichever file is being processed *right now*. Used by `DiffPhaseView.isFileInFlight` and `AITranscriptView` to show spinners.

2. **`selectiveAnalysisInFlight: Set<String>`** — a `Set` of `RuleRequest.taskId` values populated upfront when a selective analysis starts, drained as individual `RuleRequest`s complete. Used by `DiffPhaseView.isFileInFlight`, `isFocusAreaInFlight`, and `RichDiffViews.hunkActions` to show spinners.

Both serve the same purpose (tell the UI which files/areas are active) but use different data shapes and are managed in different code paths. Full analysis only populates `activeAnalysisFilePath`; selective analysis only populates `selectiveAnalysisInFlight`. `isFileInFlight` has to check both, which is the clearest symptom of the duplication.

The fix: use a single `Set<RuleRequest>` for all analysis modes (full and selective), and derive `activeAnalysisFilePath` from `liveAccumulators`.

## Phases

## - [x] Phase 1: Make `RuleRequest` Hashable and unify tracking into `tasksInFlight`

**Skills to read**: `/swift-app-architecture:swift-swiftui`

Add `Hashable` conformance to `RuleRequest` (hash/equality by `taskId` since it's already unique per rule+focusArea pairing). Also add `Hashable` to `TaskRule` and `FocusArea` if they don't already conform (needed transitively, or just implement `hash(into:)` and `==` on `RuleRequest` using `taskId` only).

Replace `selectiveAnalysisInFlight: Set<String>` with `tasksInFlight: Set<RuleRequest>`.

In `runAnalyze()` (full analysis):
- Before the stream loop, insert all `RuleRequest`s from `preparation?.tasks` into `tasksInFlight`
- In `handleTaskEvent` when `.completed`, remove the `RuleRequest` from `tasksInFlight`
- On stream `.completed` / `.failed` / `catch`, clear `tasksInFlight`

In `runFilteredAnalysis()` and `runSingleAnalysis()`:
- Replace `selectiveAnalysisInFlight` references with `tasksInFlight`, inserting/removing `RuleRequest` values instead of task ID strings

In `startSelectiveAnalysis(filter:)`:
- Change `selectiveAnalysisInFlight.formUnion(matchingTaskIds)` to `tasksInFlight.formUnion(matchingTasks)`

Remove `activeAnalysisFilePath` stored property. Replace it with a computed property:

```swift
var activeAnalysisFilePath: String? {
    liveAccumulators.last?.filePath
}
```

This preserves the existing behavior where `activeAnalysisFilePath` points to the *currently streaming* task's file (set in `appendAIPrompt`), not all in-flight files. The transcript view needs "which file is streaming right now" which `liveAccumulators.last?.filePath` already captures.

**Completed.** `RuleRequest` now conforms to `Hashable` via explicit `==` and `hash(into:)` on `taskId`. `TaskRule`/`FocusArea` did not need `Hashable` since `RuleRequest` hashes by `taskId` only. `runAnalyze()` now populates `tasksInFlight` before streaming and drains per-task on `.completed`. View-layer `isFileInFlight`/`isFocusAreaInFlight` and `hunkActions` inline check updated to query `tasksInFlight` directly. All 488 tests pass.

## - [ ] Phase 2: Simplify `isFileInFlight` and related checks

**Skills to read**: none

`DiffPhaseView.isFileInFlight` currently checks two sources:

```swift
if prModel.activeAnalysisFilePath == file { return true }
let fileTaskIds = ...
return !fileTaskIds.isDisjoint(with: prModel.selectiveAnalysisInFlight)
```

After Phase 1, both full and selective analysis populate `tasksInFlight`, so this collapses to checking the set directly. Since we now store `RuleRequest` values, the view can filter by file path on the set itself:

```swift
private func isFileInFlight(_ file: String) -> Bool {
    prModel.tasksInFlight.contains { $0.focusArea.filePath == file }
}
```

Same simplification for `isFocusAreaInFlight`:

```swift
private func isFocusAreaInFlight(_ focusAreaId: String) -> Bool {
    prModel.tasksInFlight.contains { $0.focusArea.focusId == focusAreaId }
}
```

And the inline check in `RichDiffViews.hunkActions` — filter `tasksInFlight` by focus area ID instead of cross-referencing task ID strings.

Also update `isSelectiveAnalysisRunning` → rename or remove. If other code distinguishes "selective vs full," keep a separate boolean or check `operationMode`. If nothing needs that distinction, remove it.

## - [ ] Phase 3: Clean up `resetAfterDataDeletion` and other bookkeeping

**Skills to read**: none

- Remove `activeAnalysisFilePath = nil` from `handleTaskEvent(.completed)`, `runAnalyze()` completion/failure, and `runSingleAnalysis()` — it's now computed
- In `resetAfterDataDeletion`, replace `selectiveAnalysisInFlight = []` with `tasksInFlight = []`
- Remove `activeAnalysisFilePath = task.focusArea.filePath` from `appendAIPrompt` — no longer needed since the computed property derives it from `liveAccumulators`

## - [ ] Phase 4: Validation

**Skills to read**: `/swift-testing`

- `swift build` — verify no compile errors
- `swift test` — all existing tests pass
- Manual spot-check: full analysis shows per-file spinners in DiffPhaseView as each task runs, same as before
- Manual spot-check: selective analysis (right-click a file → "Run Analysis") shows spinners on targeted files, same as before
- Verify `AITranscriptView` still shows a spinner next to the currently-streaming file
