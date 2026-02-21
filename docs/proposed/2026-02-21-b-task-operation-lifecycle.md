## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-swiftui` | Observable model conventions, state management |
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

## Proposal: `TaskOperation`

Introduce a `TaskOperation` type that unifies the lifecycle state of a single analysis task into one object.

### The type

Nested inside PRModel (app-layer UI state):

```swift
struct TaskOperation: Identifiable {
    enum Status { case queued, streaming, completed }

    var id: String { request.taskId }
    let request: RuleRequest
    var status: Status = .queued
    var accumulator: LiveTranscriptAccumulator?

    mutating func startStreaming(prompt: String, identifier: String) {
        status = .streaming
        accumulator = LiveTranscriptAccumulator(
            identifier: identifier,
            prompt: prompt,
            filePath: request.focusArea.filePath,
            ruleName: request.rule.name,
            startedAt: Date()
        )
    }
}
```

### PRModel changes

Replace `tasksInFlight` + `liveAccumulators` with a single dictionary:

```swift
private(set) var taskOperations: [String: TaskOperation] = [:]
```

Rewrite `handleTaskEvent` to route events by taskId:

```swift
private func handleTaskEvent(_ task: RuleRequest, _ event: TaskProgress) {
    switch event {
    case .prompt(let text):
        let count = taskOperations.values.filter { $0.accumulator != nil }.count
        taskOperations[task.taskId]?.startStreaming(prompt: text, identifier: "task-\(count + 1)")
    case .output(let text):
        taskOperations[task.taskId]?.accumulator?.textChunks += text
    case .toolUse(let name):
        taskOperations[task.taskId]?.accumulator?.flushTextAndAppendToolUse(name)
    case .completed(let result):
        taskOperations[task.taskId]?.status = .completed
        inProgressAnalysis?.appendResult(result, prNumber: prNumber)
    }
}
```

Remove `appendAIPrompt`, `appendAIOutput`, `appendAIToolUse` methods.

The `liveTranscripts` computed property becomes:

```swift
var liveTranscripts: [PRRadarPhase: [ClaudeAgentTranscript]] {
    guard let phase = currentLivePhase else { return [:] }
    let transcripts = taskOperations.values
        .sorted(by: { $0.request < $1.request })
        .compactMap { $0.accumulator?.toClaudeAgentTranscript() }
    return transcripts.isEmpty ? [:] : [phase: transcripts]
}
```

### UI helper methods

Expose query methods instead of the raw dictionary:

```swift
func isFileStreaming(_ filePath: String) -> Bool {
    taskOperations.values.contains { $0.status == .streaming && $0.request.focusArea.filePath == filePath }
}

func isFocusAreaStreaming(_ focusId: String) -> Bool {
    taskOperations.values.contains { $0.status == .streaming && $0.request.focusArea.focusId == focusId }
}
```

### Lifecycle integration

| Method | Current | After |
|---|---|---|
| `runAnalyze()` | `tasksInFlight = Set(tasks)` | `for task in tasks { taskOperations[task.taskId] = TaskOperation(request: task) }` |
| `startSelectiveAnalysis()` | `tasksInFlight.formUnion(matchingTasks)` | Same pattern as above |
| Cleanup paths | `tasksInFlight = []` | `taskOperations = [:]` |
| `resetAfterDataDeletion` | `liveAccumulators = []; tasksInFlight = []` | `taskOperations = [:]` |

### `LiveTranscriptAccumulator` changes

Move `flushTextAndAppendToolUse` logic from the current index-based mutation in `appendAIToolUse` into a `mutating` method on the struct:

```swift
mutating func flushTextAndAppendToolUse(_ name: String) {
    if !textChunks.isEmpty {
        events.append(ClaudeAgentTranscriptEvent(type: .text, content: textChunks))
        textChunks = ""
    }
    events.append(ClaudeAgentTranscriptEvent(type: .toolUse, toolName: name))
}
```

### Files to modify

| File | Change |
|---|---|
| PRModel.swift | Replace `tasksInFlight` + `liveAccumulators` with `taskOperations`; rewrite event handling; add query methods |
| AITranscriptView.swift | Replace `tasksInFlight.contains(where:)` with `prModel.isFileStreaming()` |
| DiffPhaseView.swift | Replace `tasksInFlight.contains` with helper methods |
| RichDiffViews.swift | Replace `tasksInFlight.contains` with `prModel.isFocusAreaStreaming()` |

### Ordering consideration

Current `liveAccumulators` array preserves insertion order (processing order). A dictionary sorted by `RuleRequest` (filePath then ruleName) gives alphabetical order instead. This is a minor behavioral difference in the transcript sidebar.

### Future possibilities

With explicit `queued`/`streaming`/`completed` states, we could:
- Show "N tasks remaining" in the UI
- Show a progress bar (completed / total)
- Style queued vs streaming differently in the diff view
- Support concurrent task evaluation with correct per-task output routing
