# Reduce PhaseProgress Stream Consumer Duplication in PRModel

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture — confirms models should be thin with minimal boilerplate |
| `/swift-testing` | Test style guide for validation |

## Background

`PRModel` has 6 methods that consume `PhaseProgress` streams with nearly identical switch statements (`refreshDiff`, `runComments`, `runPrepare`, `runAnalyze`, `runSelectiveAnalysis`, `runReport`). Each switch has 11 cases, but most are `break` — only 2–4 cases do meaningful work per consumer. This creates ~200 lines of duplicated boilerplate.

The shared pattern across all 6 consumers:
- `.running`, `.progress` → always `break`
- `.log(text)` → always `appendLog(text, to: phase)`
- `.completed(output)` → mark phase completed, reload detail
- `.failed(error, logs)` → mark phase failed

The per-consumer differences:
- **Which AI events are handled** — prepare events (`.prepareOutput`, `.prepareToolUse`) vs task events (`.taskOutput`, `.taskPrompt`, `.taskToolUse`, `.taskCompleted`) vs neither
- **Completion side-effects** — clearing `currentLivePhase`, `inProgressAnalysis`, `activeAnalysisFilePath`, `selectiveAnalysisInFlight`
- **State system** — `runComments` uses `commentPostingState` instead of `phaseStates`
- **Cancellation** — `refreshDiff` has Task-based cancellation logic

## Approach

Extract three small lifecycle helpers — `startPhase`, `completePhase`, `failPhase` — that handle the repeated state transitions. Each phase runner keeps its own `for try await` loop and switch statement, but the `.completed` and `.failed` cases become one-liners. The switch bodies stay explicit so each method's intent is immediately readable.

This targets all 6 phase runners. Each runner still owns its full stream loop, so unique patterns (Task cancellation in `refreshDiff`, `commentPostingState` in `runComments`) stay in place without any awkward workarounds.

## Phases

## - [x] Phase 1: Add lifecycle helpers to PRModel

**Skills to read**: `/swift-app-architecture:swift-architecture`

Add three private helpers in the `// MARK: - Helpers` section of PRModel:

```swift
private func startPhase(_ phase: PRRadarPhase, logs: String = "", tracksLiveTranscripts: Bool = false) {
    phaseStates[phase] = .running(logs: logs)
    if tracksLiveTranscripts {
        liveAccumulators = [:]
        currentLivePhase = phase
    }
}

private func completePhase(_ phase: PRRadarPhase, tracksLiveTranscripts: Bool = false) {
    if tracksLiveTranscripts { currentLivePhase = nil }
    let logs = runningLogs(for: phase)
    reloadDetail()
    phaseStates[phase] = .completed(logs: logs)
}

private func failPhase(_ phase: PRRadarPhase, error: String, logs: String, tracksLiveTranscripts: Bool = false) {
    if tracksLiveTranscripts { currentLivePhase = nil }
    phaseStates[phase] = .failed(error: error, logs: logs)
}
```

**File modified:**
- `Sources/apps/MacApp/Models/PRModel.swift`

**Notes:** Added after `appendAIToolUse` in the Helpers section. The spec used `[:]` for `liveAccumulators` but the actual type is `[LiveTranscriptAccumulator]`, so `[]` was used instead. Build passes.

## - [ ] Phase 2: Rewrite the 4 standard phase runners to use the helpers

**Skills to read**: `/swift-app-architecture:swift-architecture`

Replace the setup, completion, and failure logic in `runPrepare`, `runAnalyze`, `runReport`, and `runSelectiveAnalysis` with calls to the lifecycle helpers. Each method keeps its own stream loop and switch but the boilerplate cases shrink.

**`runPrepare`** — before/after for the key cases:
```swift
// Before:
phaseStates[.prepare] = .running(logs: "")
liveAccumulators = [:]
currentLivePhase = .prepare

// After:
startPhase(.prepare, tracksLiveTranscripts: true)

// Before (.completed):
currentLivePhase = nil
let logs = runningLogs(for: .prepare)
reloadDetail()
phaseStates[.prepare] = .completed(logs: logs)

// After (.completed):
completePhase(.prepare, tracksLiveTranscripts: true)

// Before (.failed):
currentLivePhase = nil
phaseStates[.prepare] = .failed(error: error, logs: logs)

// After (.failed):
failPhase(.prepare, error: error, logs: logs, tracksLiveTranscripts: true)
```

**`runAnalyze`** — same pattern, plus per-method side effects stay inline:
```swift
startPhase(.analyze, logs: "Running evaluations...\n", tracksLiveTranscripts: true)
// ...
case .completed:
    inProgressAnalysis = nil
    activeAnalysisFilePath = nil
    completePhase(.analyze, tracksLiveTranscripts: true)
case .failed(let error, let logs):
    activeAnalysisFilePath = nil
    failPhase(.analyze, error: error, logs: logs, tracksLiveTranscripts: true)
```

**`runReport`** — simplest case:
```swift
startPhase(.report, logs: "Generating report...\n")
// ...
case .completed:
    completePhase(.report)
case .failed(let error, let logs):
    failPhase(.report, error: error, logs: logs)
```

**`runSelectiveAnalysis`** — uses `startPhase` but has its own completion logic (clearing `selectiveAnalysisInFlight`, no `reloadDetail` on completion via the standard path). If the existing completion path doesn't match `completePhase` exactly, keep the inline code and only use `startPhase` and `failPhase`.

**File to modify:**
- `Sources/apps/MacApp/Models/PRModel.swift`

## - [ ] Phase 3: Apply helpers to `refreshDiff` and `runComments` where they fit

These two methods have unique patterns but still share some boilerplate with the helpers.

**`refreshDiff`** — uses `startPhase(.diff)` and `completePhase(.diff)`. The failure path concatenates existing logs with new logs, so it may need to stay inline or use `failPhase` with the concatenated string.

**`runComments`** — uses `commentPostingState` instead of `phaseStates`, so the lifecycle helpers don't apply directly. Only adopt the helpers if it's a clean fit; otherwise leave as-is.

**File to modify:**
- `Sources/apps/MacApp/Models/PRModel.swift`

## - [ ] Phase 4: Validation

**Skills to read**: `/swift-testing`

- `swift build` — confirm no compile errors
- `swift test` — all tests pass
- Verify each phase runner uses the lifecycle helpers for state transitions
- Verify the switch statements are preserved (each method still handles its own AI events)
- Verify `runComments` is unchanged if the helpers didn't apply cleanly
- Count total lines in PRModel — expect ~60–80 fewer lines (less than the closure approach, but the code is clearer)
