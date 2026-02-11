## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture rules, layer responsibilities, dependency rules |
| `swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns, enum-based state, observable model conventions |
| `swift-testing` | Test style guide and conventions |

## Background

On large PRs with many evaluation tasks (hundreds of rule×focus-area pairs), the current AI output approach doesn't scale:

1. **All streaming text accumulates in a single `aiOutputText: String`** on PRModel — this grows unbounded and mixes output from every task together.
2. **AI output is shown globally** via a sheet with `AIOutputStreamView` — you can't see which output corresponds to which file or task.
3. **All transcripts load into memory at once** via `savedTranscripts: [PRRadarPhase: [BridgeTranscript]]` on PRModel — with hundreds of transcripts, this is expensive.
4. **No per-file output browsing** — you can't click a file and see its specific evaluation output.

### Design Goals

- **Per-evaluation log files** — each AI evaluation already writes `ai-transcript-{taskId}.json`, so the on-disk structure is fine. The change is in how we consume them.
- **Per-file output display** — when clicking a file in DiffPhaseView, show AI output/transcripts for that file only.
- **Lazy loading** — transcripts are NOT part of PRModel. They're fetched on demand when a file is selected, stored in local view state.
- **Live streaming** — when a file's task is actively running, show the streaming output in real-time in that file's detail area.

### Current Architecture (What Changes)

**PRModel currently holds:**
- `aiOutputText: String` — accumulated text from all AI tasks (remove)
- `aiCurrentPrompt: String` — last prompt sent (remove)
- `savedTranscripts: [PRRadarPhase: [BridgeTranscript]]` — all transcripts in memory (remove)

**PRModel should instead expose:**
- A way to know which task IDs are currently being evaluated (for streaming)
- A per-task streaming channel (so a view can subscribe to a specific task's output)

**Views that change:**
- `ReviewDetailView` — remove the global "AI Output" sheet button
- `DiffPhaseView` — add per-file transcript viewing when a file is selected
- `AIOutputStreamView` — reuse for per-task streaming, but scoped to one task
- `AITranscriptView` — reuse for per-task historical viewing

## - [ ] Phase 1: Per-Task Streaming Infrastructure on PRModel

**Skills to read**: `swift-app-architecture:swift-architecture`, `swift-app-architecture:swift-swiftui`

Replace the single `aiOutputText` accumulator with a per-task streaming model.

### Changes to PRModel

1. **Remove** these properties:
   - `aiOutputText: String`
   - `aiCurrentPrompt: String`
   - `savedTranscripts: [PRRadarPhase: [BridgeTranscript]]`

2. **Add** a per-task streaming state:
   ```swift
   // Tracks which tasks are currently running and their accumulated output
   private(set) var activeTaskStreams: [String: TaskStreamState] = [:]

   struct TaskStreamState {
       var text: String = ""
       var prompt: String = ""
       var isRunning: Bool = true
   }
   ```

3. **Update `runEvaluate()`** to populate `activeTaskStreams` per task ID instead of appending to a single string. The `PhaseProgress` events already carry task context — we need to thread the task ID through. Today the `.aiOutput(text:)` case doesn't identify which task the text belongs to. We need to add a task identifier to the relevant `PhaseProgress` cases.

### Changes to PhaseProgress

Add task context to AI-related cases:

```swift
case aiOutput(text: String, taskId: String?)
case aiPrompt(text: String, taskId: String?)
case aiToolUse(name: String, taskId: String?)
```

The `taskId` is optional so existing phases (like focus generation in phase 2) that don't have per-task granularity continue to work.

### Changes to EvaluateUseCase

Thread the `taskId` through when yielding `.aiOutput`, `.aiPrompt`, `.aiToolUse` events during evaluation. The task ID is already available as `task.taskId` in the evaluation loop.

### Changes to FetchRulesUseCase

For the rules/focus phase, pass `nil` for `taskId` (single AI call, no per-task breakdown needed).

## - [ ] Phase 2: Lazy Transcript Loading Service

**Skills to read**: `swift-app-architecture:swift-architecture`

Create a service (or extend an existing one) that loads transcripts on demand by task ID, without holding them all in memory.

### New: TranscriptLoadingService (Services layer)

```swift
struct TranscriptLoadingService {
    /// Load a single transcript by task ID from the evaluations phase directory
    func loadTranscript(taskId: String, config: PRRadarConfig, prNumber: Int) throws -> BridgeTranscript?

    /// Load all transcript IDs available for a PR's evaluation phase (lightweight — just filenames)
    func listTranscriptIds(config: PRRadarConfig, prNumber: Int) throws -> [String]

    /// Load transcripts for a set of task IDs (for a specific file)
    func loadTranscripts(taskIds: [String], config: PRRadarConfig, prNumber: Int) throws -> [BridgeTranscript]
}
```

This reads from the existing `phase-5-evaluations/ai-transcript-{taskId}.json` files. No new file format needed.

### Task-to-File Mapping

We need to efficiently map files → task IDs. The `EvaluationPhaseOutput` already has the task list with `focusArea.filePath`. We can build this index from the evaluation output (which is already loaded as `evaluation` on PRModel) without loading transcripts:

```swift
// On PRModel or a helper
func taskIds(forFile filePath: String) -> [String] {
    guard let evaluation = evaluation else { return [] }
    return evaluation.tasks
        .filter { $0.focusArea.filePath == filePath }
        .map { $0.taskId }
}
```

## - [ ] Phase 3: Per-File Transcript View in DiffPhaseView

**Skills to read**: `swift-app-architecture:swift-swiftui`

When a file is selected in DiffPhaseView, show its AI output below (or beside) the diff content.

### View Design

In `DiffPhaseView`, when a file is selected and has evaluation tasks:

1. **If any task for this file is actively streaming** (check `prModel.activeTaskStreams[taskId]?.isRunning`):
   - Show `AIOutputStreamView` scoped to that task's accumulated text
   - Auto-scroll as new text arrives

2. **If tasks are completed** (not streaming):
   - Show a "View AI Output" expandable section or tab
   - When expanded, **lazily load** transcripts for this file's task IDs
   - Use `TranscriptLoadingService.loadTranscripts(taskIds:...)`
   - Store the loaded transcripts in a `@State` var on the view (not on PRModel)
   - Display using the existing `AITranscriptView` component (already handles multi-transcript display)

3. **If no tasks exist for this file**: Show nothing (no AI section)

### State Management

```swift
// In the file detail view (inside DiffPhaseView or a new subview)
@State private var loadedTranscripts: [BridgeTranscript]? = nil

// Load when file changes
.task(id: selectedFile) {
    loadedTranscripts = nil  // Clear previous
    let taskIds = prModel.taskIds(forFile: selectedFile)
    if !taskIds.isEmpty {
        loadedTranscripts = try? transcriptService.loadTranscripts(taskIds: taskIds, ...)
    }
}
```

This ensures:
- Transcripts only load when a file is selected (lazy)
- Previous file's transcripts are released when switching files
- PRModel doesn't hold transcript data

## - [ ] Phase 4: Remove Global AI Output Sheet

**Skills to read**: `swift-app-architecture:swift-swiftui`

Remove the global "AI Output" button and sheet from `ReviewDetailView`.

### Changes to ReviewDetailView

1. **Remove** the `showAIOutput` state and the "AI Output" toolbar button (lines ~102-114)
2. **Remove** the `.sheet` presentation that shows `AIOutputStreamView` / `AITranscriptView` globally
3. **Remove** the `hasAIOutput` computed property

### Changes to PRModel

1. **Remove** `loadSavedTranscripts()` method (no longer needed — transcripts load lazily per-file)
2. **Remove** `savedTranscripts` dictionary cleanup in `loadDetail()`

### Consideration: Focus Area Phase (Phase 2) Output

The focus generation phase also has AI transcripts but isn't per-file in the same way evaluations are. Options:
- Keep a simpler version of transcript viewing for focus/rules phases in their respective phase views
- Or just let those be viewable via the phase log (already shown in `PhaseInputView`)

Recommendation: For this iteration, focus area and rules phase AI output can remain viewable through the phase logs. Only evaluation transcripts need the per-file UX since that's where the scaling problem exists.

## - [ ] Phase 5: Handle Mixed Streaming + Completed State

**Skills to read**: `swift-app-architecture:swift-swiftui`

During an evaluation run, some files will have completed tasks while others are still streaming. The view needs to handle this mixed state.

### Streaming Indicator per File

In the file list sidebar of DiffPhaseView, add a visual indicator when a file has tasks currently being evaluated:

```swift
// File list item
HStack {
    Text(file.displayName)
    if prModel.hasActiveStreams(forFile: file.path) {
        ProgressView()
            .controlSize(.small)
    }
}
```

### Mixed Display in File Detail

When viewing a file's detail during an active evaluation run:
- Show completed task transcripts (loaded lazily) in the transcript viewer
- Show actively streaming tasks with live `AIOutputStreamView`
- Group them clearly (e.g., "Completed Evaluations" section + "Running" section)

### Cleanup After Phase Completion

When the evaluation phase finishes:
- Clear `activeTaskStreams` from PRModel
- The lazily-loaded transcripts remain in the view's `@State` until the user navigates away

## - [ ] Phase 6: Validation

**Skills to read**: `swift-testing`

### Unit Tests

1. **TranscriptLoadingService tests** — verify it correctly loads transcripts by task ID from disk, handles missing files gracefully
2. **Task-to-file mapping tests** — verify `taskIds(forFile:)` correctly filters tasks by file path
3. **PhaseProgress task ID threading** — verify evaluation use case yields correct task IDs with AI events

### Integration Verification

1. Build the project (`swift build`)
2. Run existing tests (`swift test`) — ensure nothing breaks
3. Manual verification with test repo:
   - Run `swift run PRRadarMacCLI analyze 1 --config test-repo`
   - Open MacApp, select the PR
   - Click through files and verify per-file transcript loading
   - Verify streaming output appears per-file during a live evaluation run
   - Verify memory doesn't grow with number of files (transcripts load/unload per selection)
