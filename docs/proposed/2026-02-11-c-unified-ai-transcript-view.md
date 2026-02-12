## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules, layer placement guidance |
| `/swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns, observable model conventions, state management |

## Background

During live AI streaming in the MacApp, multiple AI calls (one per evaluation task) have their prompts and text responses mixed together. `PRModel` stores output as two flat strings: `aiCurrentPrompt` (overwritten per prompt) and `aiOutputText` (concatenated across all calls). This means the live "AI Output" sheet shows one prompt with one giant text blob.

The stored/completed transcript view (`AITranscriptView`) already displays correctly — sidebar list of transcripts, detail view with prompt + structured events (text, tool use, result), and metadata header. Bill wants the live streaming view to look exactly like this stored view.

**Goal**: Eliminate `AIOutputStreamView` entirely. Always use `AITranscriptView` for AI output, building up `BridgeTranscript` objects during live streaming.

### Key Context

- `BridgeTranscript` has `let` properties (immutable, `Codable`, `Sendable`) — needs a mutable accumulator to build up during streaming
- Event flow: `.aiPrompt` arrives once per AI call, followed by many `.aiOutput` text chunks and occasional `.aiToolUse` events
- `PRModel` is `@Observable @MainActor` — all state mutations are main-thread safe
- `AITranscriptView` takes `[PRRadarPhase: [BridgeTranscript]]`

## Phases

## - [x] Phase 1: Add live transcript accumulator to PRModel

**Skills to read**: `/swift-app-architecture:swift-swiftui`

Add a private `LiveTranscriptAccumulator` struct inside `PRModel` to hold mutable streaming state per AI call:
- `identifier: String` — e.g. "task-1", "task-2"
- `prompt: String`
- `textChunks: String` — accumulated `.aiOutput` text
- `events: [BridgeTranscriptEvent]` — flushed text + tool use events
- `startedAt: Date`
- `toBridgeTranscript() -> BridgeTranscript` — converts to immutable form for display

Add private state:
- `liveAccumulators: [LiveTranscriptAccumulator]`
- `currentLivePhase: PRRadarPhase?`

Add computed property:
- `liveTranscripts: [PRRadarPhase: [BridgeTranscript]]` — converts accumulators for view consumption

Remove: `aiOutputText: String` and `aiCurrentPrompt: String`

**Files**: [PRModel.swift](PRRadarLibrary/Sources/apps/MacApp/Models/PRModel.swift)

**Completed notes**: Also updated `runPrepare()` and `runAnalyze()` event handlers (originally Phase 2 scope) since removing `aiOutputText`/`aiCurrentPrompt` required it for compilation. Added `appendAIPrompt`, `appendAIOutput`, and `appendAIToolUse` helper methods. Updated `ReviewDetailView.hasAIOutput` and `aiOutputView` to use `liveTranscripts` instead of removed properties, replacing `AIOutputStreamView` usage with `AITranscriptView`.

## - [x] Phase 2: Update event handlers in runPrepare() and runAnalyze()

**Skills to read**: none (straightforward state management changes)

In both `runPrepare()` and `runAnalyze()`:

Reset at start:
```
liveAccumulators = []
currentLivePhase = .prepare  // or .analyze
```

Handle events:
- `.aiPrompt(text)`: Append new accumulator with identifier "task-\(count+1)" and the prompt
- `.aiOutput(text)`: Append text to last accumulator's `textChunks` (create prompt-less entry if none exists)
- `.aiToolUse(name)`: Flush accumulated text as a `.text` event, then add `.toolUse` event to last accumulator

On completion: clear `currentLivePhase` (so `liveTranscripts` returns empty, letting `savedTranscripts` take over)

**Files**: [PRModel.swift](PRRadarLibrary/Sources/apps/MacApp/Models/PRModel.swift)

**Completed notes**: Already implemented in Phase 1 — removing `aiOutputText`/`aiCurrentPrompt` required updating the event handlers for compilation. All event handling logic (`appendAIPrompt`, `appendAIOutput`, `appendAIToolUse`) and phase lifecycle (reset at start, clear `currentLivePhase` on completion/failure) was included in the Phase 1 commit.

## - [x] Phase 3: Add streaming support to AITranscriptView

**Skills to read**: `/swift-app-architecture:swift-swiftui`

Add `isStreaming: Bool = false` parameter to `AITranscriptView`.

When `isStreaming`:
- Show "AI is running..." banner at top (reuse the style from current `AIOutputStreamView`)
- Auto-select the last transcript in the sidebar as new ones arrive
- Auto-scroll to bottom of the detail pane as text streams in

**Files**: [AITranscriptView.swift](PRRadarLibrary/Sources/apps/MacApp/UI/PhaseViews/AITranscriptView.swift)

**Completed notes**: Added `isStreaming: Bool = false` parameter. When streaming: displays "AI is running..." banner with progress spinner (matching `AIOutputStreamView` style), auto-selects last transcript via `onChange(of: transcripts.count)`, auto-scrolls detail pane via `ScrollViewReader` with `onChange(of: transcript.events.count)`. Sidebar and header show streaming-appropriate metadata (event count instead of model/cost). Updated `ReviewDetailView.aiOutputView` to pass `isStreaming: true` when `isAIPhaseRunning`.

## - [x] Phase 4: Simplify ReviewDetailView

**Skills to read**: none

Replace the three-way branching in `aiOutputView` with unified logic:
- If `isAIPhaseRunning`: show `AITranscriptView(transcriptsByPhase: liveTranscripts, isStreaming: true)`
- Else if `savedTranscripts` not empty: show `AITranscriptView(transcriptsByPhase: savedTranscripts)`
- Else if `liveTranscripts` not empty: show `AITranscriptView(transcriptsByPhase: liveTranscripts)`
- Else: `ContentUnavailableView`

Update `hasAIOutput` to check `liveTranscripts` instead of `aiOutputText`.

**Files**: [ReviewDetailView.swift](PRRadarLibrary/Sources/apps/MacApp/UI/ReviewDetailView.swift)

**Completed notes**: No code changes needed — this was already implemented during Phase 1. When `aiOutputText` and `aiCurrentPrompt` were removed, `ReviewDetailView` was updated with the unified `aiOutputView` logic (four-way branch: streaming live → saved → stale live → unavailable) and `hasAIOutput` was updated to check `liveTranscripts`. Verified build succeeds.

## - [ ] Phase 5: Delete AIOutputStreamView

**Skills to read**: none

Remove [AIOutputStreamView.swift](PRRadarLibrary/Sources/apps/MacApp/UI/PhaseViews/AIOutputStreamView.swift) — no longer needed.

## - [ ] Phase 6: Validation

**Skills to read**: `/swift-testing`

1. `cd pr-radar-mac && swift build` — confirms compilation with no errors
2. `cd pr-radar-mac && swift test` — all existing tests pass
3. Manual: Run MacApp, trigger Analyze on a multi-task PR, verify:
   - AI Output sheet shows sidebar with one entry per AI call appearing as they start
   - Detail view shows prompt disclosure + streaming text
   - "AI is running..." banner visible during streaming
   - After completion, view switches to saved transcripts with full metadata (model, cost, duration)
