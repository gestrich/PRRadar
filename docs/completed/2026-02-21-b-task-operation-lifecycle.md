## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-swiftui` | Observable model conventions, state management |
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules, placement guidance |
| `/swift-testing` | Test style guide |

## Background

PRModel currently tracks in-flight analysis state across three separate collections:

| Collection | Purpose | Location |
|---|---|---|
| `tasksInFlight: Set<RuleRequest>` | Which tasks are actively streaming | PRModel.swift:31 |
| `liveAccumulators: [LiveTranscriptAccumulator]` | Streaming AI output per task | PRModel.swift:28 |
| `currentLivePhase: PRRadarPhase?` | Which phase is streaming | PRModel.swift:29 |

These are disconnected: `liveAccumulators` doesn't know which `RuleRequest` each accumulator belongs to (it stores `filePath` and `ruleName` separately), and the `appendAIOutput`/`appendAIToolUse` methods route events to the "last" accumulator rather than to a specific task. This works only because tasks are processed sequentially today.

If we add concurrent task evaluation in the future, the "last accumulator" pattern breaks — output from different tasks would interleave into the wrong accumulator.

Additionally, the completed state (`RuleOutcome` in `PRReviewResult`) and the in-progress state (`liveAccumulators` + `tasksInFlight`) are completely separate data paths. The `aiOutputView` in ReviewDetailView has 4 branches juggling `liveTranscripts` vs `savedTranscripts` and `isAIPhaseRunning` because there's no unified model.

### Design: `TaskEvaluation`

Introduce a `TaskEvaluation` struct in the app layer (`MacApp/Models/`) that represents the full lifecycle of a single task — applying a rule to a focus area and getting a result. It composes existing domain types without changing them.

`TaskEvaluation` is a **persistent per-task container** — created as soon as tasks are known (after prepare, or when loaded from disk) and present for the life of the PR's data. It holds all per-task state: saved transcripts, outcomes, and live streaming accumulators.

Views do not observe `TaskEvaluation` directly. PRModel owns the collection and exposes query methods; views continue to go through PRModel.

```swift
struct TaskEvaluation: Identifiable {
    let request: RuleRequest
    let phase: PRRadarPhase
    var accumulator: LiveTranscriptAccumulator?
    var savedTranscript: ClaudeAgentTranscript?
    var outcome: RuleOutcome?

    var id: String { request.taskId }

    var isStreaming: Bool { accumulator != nil && outcome == nil }
    var isComplete: Bool { outcome != nil }
    var isQueued: Bool { accumulator == nil && outcome == nil }

    var transcript: ClaudeAgentTranscript? {
        if let acc = accumulator {
            return acc.toClaudeAgentTranscript()
        }
        return savedTranscript
    }
}
```

```
TaskEvaluation (struct, app layer)
  ├── request: RuleRequest                     (services layer, unchanged)
  ├── phase: PRRadarPhase                      (services layer, unchanged)
  ├── accumulator: LiveTranscriptAccumulator?  (app layer, transient — live streaming)
  ├── savedTranscript: ClaudeAgentTranscript?  (services layer — loaded from disk)
  └── outcome: RuleOutcome?                    (services layer, unchanged)
                ├── .success(RuleResult)
                └── .error(RuleError)
```

Domain types (`RuleRequest`, `RuleResult`, `RuleError`, `RuleOutcome`, `ClaudeAgentTranscript`) stay unchanged. The CLI app works with `RuleOutcome` directly and never needs `TaskEvaluation`.

The prepare phase is a single AI call with no `RuleRequest`, so it gets a standalone `prepareAccumulator` on PRModel rather than a `TaskEvaluation`.

### Lifecycle

`TaskEvaluation` instances are created in `applyDetail()` whenever `preparation?.tasks` is available:

```swift
// In applyDetail(_:)
if let tasks = newDetail.preparation?.tasks {
    let outcomeMap = Dictionary(
        (newDetail.analysis?.evaluations ?? []).map { ($0.taskId, $0) },
        uniquingKeysWith: { _, new in new }
    )
    let transcriptMap = Dictionary(
        (newDetail.savedTranscripts[.analyze] ?? []).map {
            ("\($0.filePath):\($0.ruleName)", $0)
        },
        uniquingKeysWith: { _, new in new }
    )
    var newEvaluations: [String: TaskEvaluation] = [:]
    for task in tasks {
        var eval = TaskEvaluation(request: task, phase: .analyze)
        eval.outcome = outcomeMap[task.taskId]
        eval.savedTranscript = transcriptMap["\(task.focusArea.filePath):\(task.rule.name)"]
        newEvaluations[task.taskId] = eval
    }
    evaluations = newEvaluations
}
```

This means `evaluations` is populated whenever task data exists — not just during streaming. When streaming starts, the existing evaluations get their `accumulator` set. When streaming completes and detail reloads, `applyDetail` refreshes them with saved data from disk.

`TaskProgress` (features layer) drives streaming state transitions:

| `TaskProgress` event | `TaskEvaluation` effect |
|---|---|
| `.prompt(text)` | Creates accumulator → `isStreaming` becomes true |
| `.output(text)` | Appends to accumulator |
| `.toolUse(name)` | Appends to accumulator |
| `.completed(result: RuleOutcome)` | Sets `outcome` → `isComplete` becomes true |

### `allTranscripts` — single source, no merging

Since `TaskEvaluation` holds both live and saved transcripts, `allTranscripts` derives purely from the data — no merge of separate collections:

```swift
var allTranscripts: [PRRadarPhase: [ClaudeAgentTranscript]] {
    var result: [PRRadarPhase: [ClaudeAgentTranscript]] = [:]

    // Prepare phase
    if let acc = prepareAccumulator {
        result[.prepare] = [acc.toClaudeAgentTranscript()]
    } else if let prepareTranscripts = savedTranscripts[.prepare], !prepareTranscripts.isEmpty {
        result[.prepare] = prepareTranscripts
    }

    // Analyze phase — from evaluations
    let analyzeTranscripts = evaluations.values
        .sorted(by: { $0.request < $1.request })
        .compactMap { $0.transcript }
    if !analyzeTranscripts.isEmpty {
        result[.analyze] = analyzeTranscripts
    }

    return result
}
```

The analyze phase is fully derived from `evaluations`. The prepare phase still needs a fallback to `savedTranscripts` since it doesn't go through `TaskEvaluation`.

This eliminates the 4-branch `aiOutputView` in ReviewDetailView — it becomes:

```swift
AITranscriptView(transcriptsByPhase: prModel.allTranscripts, isStreaming: prModel.isAIPhaseRunning)
```

### What gets removed from PRModel

| Current | Replaced by |
|---|---|
| `tasksInFlight: Set<RuleRequest>` | `evaluations.values.filter { $0.isStreaming }` |
| `liveAccumulators: [LiveTranscriptAccumulator]` | Each `TaskEvaluation` owns its `accumulator` |
| `currentLivePhase: PRRadarPhase?` | Derived from `evaluations` + `prepareAccumulator` |
| `liveTranscripts` computed property | `allTranscripts` derives from `evaluations` |
| `appendAIPrompt`, `appendAIOutput`, `appendAIToolUse` | `handleTaskEvent` mutates through `evaluations` dictionary |
| `tracksLiveTranscripts` on `startPhase`/`completePhase`/`failPhase` | Removed — transcript state lives on `TaskEvaluation` |

### Ordering consideration

Current `liveAccumulators` array preserves insertion order (processing order). A dictionary sorted by `RuleRequest` (filePath then ruleName) gives alphabetical order instead. This is a minor behavioral difference in the transcript sidebar.

## Phases

## - [x] Phase 1: Create `TaskEvaluation` struct and add `flushTextAndAppendToolUse` to `LiveTranscriptAccumulator`

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: New struct placed in Apps layer (MacApp/Models/) per architecture rules; composes existing domain types without modifying them

**Skills to read**: `/swift-app-architecture:swift-architecture`

Create `MacApp/Models/TaskEvaluation.swift` with the struct definition from the design section above (including `savedTranscript` and the `transcript` computed property).

Add a `mutating func flushTextAndAppendToolUse(_ name: String)` method to the existing `LiveTranscriptAccumulator` struct in PRModel.swift:

```swift
mutating func flushTextAndAppendToolUse(_ name: String) {
    if !textChunks.isEmpty {
        events.append(ClaudeAgentTranscriptEvent(type: .text, content: textChunks))
        textChunks = ""
    }
    events.append(ClaudeAgentTranscriptEvent(type: .toolUse, toolName: name))
}
```

Verify build succeeds. The new type is not used yet — no behavioral change.

## - [x] Phase 2: Replace PRModel state with `evaluations` + `prepareAccumulator`

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: @Observable state stays in Apps layer; evaluations populated in applyDetail() for persistent lifecycle; query methods expose streaming state to views

**Skills to read**: `/swift-app-architecture:swift-swiftui`

In `MacApp/Models/PRModel.swift`:

1. Replace `tasksInFlight: Set<RuleRequest>`, `liveAccumulators: [LiveTranscriptAccumulator]`, and `currentLivePhase: PRRadarPhase?` with:
   ```swift
   private(set) var evaluations: [String: TaskEvaluation] = [:]
   private var prepareAccumulator: LiveTranscriptAccumulator?
   ```

2. Populate evaluations in `applyDetail()` — when `preparation?.tasks` exists, create `TaskEvaluation` per task, attaching saved transcripts (matched by filePath + ruleName) and outcomes (matched by taskId). See the lifecycle code in the design section.

3. Replace `isAIPhaseRunning` computed property:
   ```swift
   var isAIPhaseRunning: Bool {
       prepareAccumulator != nil || evaluations.values.contains { $0.isStreaming }
   }
   ```

4. Replace `liveTranscripts` with `allTranscripts` — for the analyze phase, derive purely from `evaluations.values.compactMap { $0.transcript }`. For prepare, use `prepareAccumulator` with fallback to `savedTranscripts[.prepare]`. See the design section for the full implementation.

5. Rewrite `handleTaskEvent` to route through the dictionary by taskId:
   ```swift
   private func handleTaskEvent(_ task: RuleRequest, _ event: TaskProgress) {
       switch event {
       case .prompt(let text):
           let count = evaluations.values.filter { $0.accumulator != nil }.count
           evaluations[task.taskId]?.accumulator = LiveTranscriptAccumulator(
               identifier: "task-\(count + 1)",
               prompt: text,
               filePath: task.focusArea.filePath,
               ruleName: task.rule.name,
               startedAt: Date()
           )
       case .output(let text):
           evaluations[task.taskId]?.accumulator?.textChunks += text
       case .toolUse(let name):
           evaluations[task.taskId]?.accumulator?.flushTextAndAppendToolUse(name)
       case .completed(let result):
           evaluations[task.taskId]?.outcome = result
           inProgressAnalysis?.appendResult(result, prNumber: prNumber)
       }
   }
   ```

6. Remove `appendAIPrompt`, `appendAIOutput`, `appendAIToolUse` methods.

7. Add query methods for views:
   ```swift
   func isFileStreaming(_ filePath: String) -> Bool {
       evaluations.values.contains { $0.isStreaming && $0.request.focusArea.filePath == filePath }
   }
   func isFocusAreaStreaming(_ focusId: String) -> Bool {
       evaluations.values.contains { $0.isStreaming && $0.request.focusArea.focusId == focusId }
   }
   ```

8. Update `runPrepare()` to handle `.prepareOutput`/`.prepareToolUse` directly on `prepareAccumulator` (lazily created on first output). Remove `tracksLiveTranscripts` parameter from `startPhase`, `completePhase`, `failPhase`.

9. Update `runAnalyze()` — evaluations already exist from `applyDetail()`. Reset accumulators for tasks being evaluated. On `.taskEvent`, call `handleTaskEvent`. On `.completed`, clear accumulators (evaluations persist — they'll be refreshed by the `reloadDetail` call). On error, clear accumulators.

10. Update `runFilteredAnalysis()` and `runSingleAnalysis()` with the same pattern — evaluations already exist, just reset accumulators for the tasks being re-run.

11. Update `resetAfterDataDeletion` — clear `evaluations` and `prepareAccumulator` instead of `liveAccumulators`, `tasksInFlight`, and `currentLivePhase`.

This phase will cause build errors in views that reference the removed properties — that's expected and fixed in Phase 3.

## - [x] Phase 3: Update views to use new PRModel API

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: Views consume PRModel query methods (`isFileStreaming`, `isFocusAreaStreaming`, `allTranscripts`) instead of accessing raw state; collapsed 4-branch aiOutputView into single unified call

**Skills to read**: `/swift-app-architecture:swift-swiftui`

1. **`ReviewDetailView.swift`** — Collapse the 4-branch `aiOutputView` into:
   ```swift
   AITranscriptView(transcriptsByPhase: prModel.allTranscripts, isStreaming: prModel.isAIPhaseRunning)
   ```
   Update `hasAIOutput` to check `!prModel.allTranscripts.isEmpty`.

2. **`AITranscriptView.swift`** — Replace `prModel.tasksInFlight.contains(where: { $0.focusArea.filePath == group.filePath })` with `prModel.isFileStreaming(group.filePath)`.

3. **`DiffPhaseView.swift`** — Replace `isFileInFlight` and `isFocusAreaInFlight` helper methods to use `prModel.isFileStreaming(_:)` and `prModel.isFocusAreaStreaming(_:)`.

4. **`RichDiffViews.swift`** — Replace `prModel.tasksInFlight.contains { $0.focusArea.focusId == area.focusId }` with `prModel.isFocusAreaStreaming(area.focusId)`.

Verify build succeeds after all view updates.

## - [x] Phase 4: Validate build and tests

**Skills used**: `swift-testing`
**Principles applied**: Verified build succeeds, all 488 tests pass, no remaining references to removed properties (tasksInFlight, liveAccumulators, currentLivePhase, liveTranscripts)

**Skills to read**: `/swift-testing`

- Run `swift build` and fix any compilation errors
- Run `swift test` and verify all existing tests pass
- Grep for any remaining references to `tasksInFlight`, `liveAccumulators`, `currentLivePhase`, or `liveTranscripts` — there should be none outside of test files (if any test files reference them, update those too)

## Future: Move `TaskEvaluation` to services layer and adopt in `PRReviewResult`

`TaskEvaluation` and `LiveTranscriptAccumulator` are not inherently app-layer concerns — streaming AI output applies to the CLI too. In a follow-up:

1. **Move `LiveTranscriptAccumulator`** from its current location as a nested struct in `PRModel.swift` to the services layer (e.g., `PRRadarModels/`).

2. **Move `TaskEvaluation`** to the services layer (e.g., `PRRadarModels/`). For persistence, `accumulator` and `savedTranscript` are transient (nil when serialized) — only `request` and `outcome` matter for the persisted form.

3. **Refactor `PRReviewResult`** to hold `[TaskEvaluation]` instead of separate `evaluations: [RuleOutcome]` + `tasks: [RuleRequest]`. This eliminates:
   - The separate `tasks` array
   - The `taskId` join in `comments` (`let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.taskId, $0) })`)
   - The `taskId` join in `appendResult` (`evaluations.firstIndex(where: { $0.taskId == result.taskId })`)

4. **CLI benefits** — `AnalyzeCommand` and other CLI consumers can also use `TaskEvaluation` as the unified per-task container instead of working with separate `RuleOutcome` + `RuleRequest` arrays.
