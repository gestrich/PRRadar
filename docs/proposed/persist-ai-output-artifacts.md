# Persist AI Output as Artifacts

## Background

Currently, when the Claude bridge executes during Phase 2 (focus area generation via Haiku) and Phase 5 (rule evaluation via Sonnet), the AI's reasoning text and tool use events are printed to stdout by `ClaudeBridgeClient` but **never saved to disk**. Only the final structured JSON output (focus areas, evaluation results) is persisted as artifacts. This means the AI's thought process — its reasoning, codebase exploration, and intermediate conclusions — is lost after each run.

This plan adds first-class support for persisting AI transcripts as artifacts alongside existing phase outputs, viewing them after completion in both the MacApp and CLI, and streaming them in real-time during live runs.

**Phases that produce AI output:**
- **Phase 2 (Focus Areas):** Claude Haiku called per diff hunk to identify methods/functions
- **Phase 5 (Evaluations):** Claude Sonnet called per task (rule × focus area) with tool access

**Key architectural note:** Per the swift-architecture conventions, streaming data flows through `AsyncThrowingStream` from Features (use cases) to Apps (models/CLI). The bridge client lives in the Services layer as a stateless utility. New transcript models go in the Services/Models layer. UI state and `@Observable` models stay in the Apps layer.

## Phases

## - [ ] Phase 1: Transcript Model and File Format

Add a `BridgeTranscriptEvent` model to `PRRadarModels` for representing individual streaming events from the bridge, and a `BridgeTranscript` model for the complete transcript of a single bridge invocation.

**Tasks:**
- Add `BridgeTranscript.swift` to `Sources/services/PRRadarModels/` with:
  ```swift
  struct BridgeTranscriptEvent: Codable, Sendable {
      let type: EventType  // .text, .toolUse, .result
      let content: String? // text content
      let toolName: String? // tool_use name
      let timestamp: Date

      enum EventType: String, Codable, Sendable {
          case text, toolUse, result
      }
  }

  struct BridgeTranscript: Codable, Sendable {
      let identifier: String  // e.g., "task-1", "hunk-0"
      let model: String
      let startedAt: String
      let events: [BridgeTranscriptEvent]
      let costUsd: Double
      let durationMs: Int
  }
  ```
- The transcript will be saved as JSON (`.json`) for structured access, and as Markdown (`.md`) for human-readable browsing
- File naming convention in phase directories:
  - `phase-2-focus-areas/ai-transcript-hunk-{n}.json`
  - `phase-2-focus-areas/ai-transcript-hunk-{n}.md`
  - `phase-5-evaluations/ai-transcript-{taskId}.json`
  - `phase-5-evaluations/ai-transcript-{taskId}.md`
- Add a `BridgeTranscriptWriter` to `PRRadarCLIService` with methods:
  - `static func write(_ transcript: BridgeTranscript, to directory: String)` — saves both `.json` and `.md`
  - `static func renderMarkdown(_ transcript: BridgeTranscript) -> String` — converts events to readable markdown
- The markdown rendering should format text blocks as quoted content, tool use as collapsible sections with the tool name, and include a summary footer with model/cost/duration

**Architecture notes:**
- `BridgeTranscript` and `BridgeTranscriptEvent` are domain models → Services/Models layer (`PRRadarModels`)
- `BridgeTranscriptWriter` is a stateless service utility → Services layer (`PRRadarCLIService`)

## - [ ] Phase 2: Bridge Client Streaming

Modify `ClaudeBridgeClient` to support real-time streaming of bridge events, enabling callers to process events as they arrive rather than waiting for the process to complete.

**Tasks:**
- Add a `BridgeStreamEvent` enum to `ClaudeBridgeClient.swift`:
  ```swift
  enum BridgeStreamEvent: Sendable {
      case text(String)
      case toolUse(name: String)
      case result(BridgeResult)
  }
  ```
- Add a new streaming method to `ClaudeBridgeClient`:
  ```swift
  func stream(_ request: BridgeRequest) -> AsyncThrowingStream<BridgeStreamEvent, Error>
  ```
  This method:
  - Launches the Python bridge process as before
  - Reads stdout **line by line** asynchronously using `FileHandle.bytes.lines` (instead of `waitUntilExit` + `readDataToEndOfFile`)
  - Parses each JSON-line and yields the corresponding `BridgeStreamEvent`
  - Yields `.result` for the final result message
- Reimplement the existing `execute()` method on top of `stream()` to preserve backward compatibility — it collects all events, prints text to stdout (existing behavior), and returns the final `BridgeResult`
- Ensure the streaming implementation properly handles process termination and stderr capture for error reporting

**Architecture notes:**
- `ClaudeBridgeClient` is in the Services layer — it wraps the Python bridge (a single CLI invocation per method call), which aligns with the SDK/Services boundary
- The stream method is stateless — each call creates a new process and stream

## - [ ] Phase 3: Service-Layer Transcript Capture

Update `EvaluationService` and `FocusGeneratorService` to use the streaming bridge client, capture all events into `BridgeTranscript` objects, save them to disk, and forward AI text to callers.

**Tasks:**
- **`EvaluationService`** changes:
  - Add an `onAIText: ((String) -> Void)?` callback parameter to `evaluateTask()` for forwarding AI text in real-time
  - Switch from `bridgeClient.execute()` to `bridgeClient.stream()`
  - Collect all `BridgeStreamEvent`s into a `BridgeTranscript` with `identifier: taskId`
  - After the stream completes, save the transcript using `BridgeTranscriptWriter.write()` to the evaluations phase directory
  - Add `transcriptDir: String?` parameter to `evaluateTask()` and `runBatchEvaluation()` for specifying where to save transcripts
  - Pass `onAIText` callback through `runBatchEvaluation` to each task evaluation

- **`FocusGeneratorService`** changes:
  - Add an `onAIText: ((String) -> Void)?` callback parameter to `generateFocusAreasForHunk()`
  - Switch from `bridgeClient.execute()` to `bridgeClient.stream()`
  - Collect events into a `BridgeTranscript` with `identifier: "hunk-{hunkIndex}"`
  - Save transcript to the focus areas phase directory
  - Add `transcriptDir: String?` parameter for specifying save location
  - Thread `onAIText` through `generateAllFocusAreas()`

**Architecture notes:**
- Services coordinate the bridge invocation and persist artifacts — this is appropriate for the Services layer
- The `onAIText` callback pattern keeps Services stateless while allowing callers to react to streaming output

## - [ ] Phase 4: Use Case Progress Stream Enhancement

Update the Feature-layer use cases to surface AI text output through the `PhaseProgress` stream, enabling both the CLI and MacApp to display it.

**Tasks:**
- Add a new case to `PhaseProgress`:
  ```swift
  case aiOutput(text: String)
  ```
  This distinguishes AI reasoning text from pipeline status logs (`.log`), allowing consumers to display them differently (e.g., separate pane in the MacApp, different formatting in CLI)

- **`EvaluateUseCase`** changes:
  - Compute the evaluations phase directory path and pass it to `EvaluationService.runBatchEvaluation()` as `transcriptDir`
  - Pass an `onAIText` closure that yields `.aiOutput(text:)` to the continuation
  - The existing `.log` events continue to report progress (e.g., "[1/5] Evaluating rule...")

- **`FetchRulesUseCase`** changes:
  - Compute the focus areas phase directory path and pass it to `FocusGeneratorService` as `transcriptDir`
  - Pass an `onAIText` closure that yields `.aiOutput(text:)` to the continuation

- **`AnalyzeUseCase`** changes:
  - Forward `.aiOutput` events from child use case streams to its own continuation (same as it already does for `.log` events)

**Architecture notes:**
- Per the swift-architecture conventions, use cases orchestrate multi-step operations and stream progress. Adding `.aiOutput` to `PhaseProgress` is the correct way to surface AI text to the Apps layer.
- Use cases should not own `@Observable` state — they just emit progress events.

## - [ ] Phase 5: MacApp UI — Transcript Viewing and Streaming

Add AI transcript browsing and real-time streaming display to the MacApp.

**Tasks:**
- **PRModel changes:**
  - Add `private(set) var aiOutputText: String = ""` for accumulating real-time AI output during a live run
  - In each `runXxx()` method, handle `.aiOutput(text:)` by appending to `aiOutputText`
  - Reset `aiOutputText` when a new phase starts running
  - Add `private(set) var savedTranscripts: [PRRadarPhase: [BridgeTranscript]] = [:]` for loaded transcripts
  - In `loadDetail()`, load saved transcripts from disk for each completed phase that has `ai-transcript-*.json` files

- **New `AITranscriptView`** in `Sources/apps/MacApp/UI/PhaseViews/`:
  - A view that displays a `BridgeTranscript` in a readable format:
    - Text events rendered as the AI's reasoning in a monospaced font
    - Tool use events shown as collapsible items with the tool name
    - Footer with model, cost, and duration metadata
  - A list/sidebar mode for browsing multiple transcripts in a phase (e.g., per-task transcripts for evaluations)

- **New `AIOutputStreamView`** in `Sources/apps/MacApp/UI/PhaseViews/`:
  - A real-time streaming view for AI output during a live run
  - Shows the accumulated `aiOutputText` from `PRModel` in a scrolling monospaced text view
  - Auto-scrolls to bottom as new text arrives (follows the existing `runningLogView` pattern in `ReviewDetailView`)
  - Shows a "Running..." indicator when active

- **Integration into `ReviewDetailView`:**
  - Add an "AI Output" navigation phase to the existing Summary / Diff / Report tabs
  - When a phase is running, show `AIOutputStreamView` with live text
  - When viewing completed results, show `AITranscriptView` with the saved transcript list for the selected phase
  - Allow selecting which phase's transcripts to view (Phase 2 focus areas, Phase 5 evaluations)

**Architecture notes:**
- Per the swift-swiftui conventions, `@Observable` models (like `PRModel`) live in the Apps layer and are `@MainActor`. Views connect directly to models — no separate ViewModels.
- The `AITranscriptView` and `AIOutputStreamView` are pure views that take data as parameters. State is managed in `PRModel`.

## - [ ] Phase 6: CLI — Transcript Display

Update the CLI to support displaying AI output both during live runs and when viewing completed results.

**Tasks:**
- **Live run AI output:**
  - In `AnalyzeCommand` (and individual commands like `EvaluateCommand`): handle the new `.aiOutput(text:)` case from `PhaseProgress`
  - By default, display AI output inline with a visual prefix/indent to distinguish it from pipeline status logs (e.g., `"    [AI] Analyzing the code changes..."`)
  - Add a `--quiet` flag that suppresses AI output (shows only status logs like "[1/5] Evaluating...")
  - Add a `--verbose` flag that shows full AI output including tool use events

- **Viewing saved transcripts:**
  - Add a new CLI command: `swift run PRRadarMacCLI transcript <prNumber> [--phase <phase>] [--task <taskId>]`
  - Lists available transcripts for a PR, or displays a specific transcript
  - `--phase` filters to a specific phase (e.g., `phase-2-focus-areas`, `phase-5-evaluations`)
  - `--task` displays a specific task's transcript
  - `--json` outputs the raw transcript JSON
  - `--markdown` outputs the rendered markdown version (default for terminal display)

**Architecture notes:**
- CLI commands are in the Apps layer. They consume `PhaseProgress` streams directly from use cases (per the swift-architecture data flow pattern for CLI).

## - [ ] Phase 7: Architecture Validation

Review all commits made during the preceding phases and validate they follow the project's architectural conventions.

**For Swift changes** (`pr-radar-mac/`):
- Re-read the `swift-architecture` and `swift-swiftui` skills from `https://github.com/gestrich/swift-app-architecture` (`plugin/skills/`)
- Compare the commits made against the conventions described in each skill
- If any code violates the conventions, make corrections

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. Fetch and read ALL skills from the swift-app-architecture GitHub repo
4. Evaluate the changes against each skill's conventions, specifically checking:
   - `BridgeTranscript` and `BridgeTranscriptEvent` are in the Services/Models layer (not Features or Apps)
   - `BridgeTranscriptWriter` is in the Services layer
   - Streaming logic in `ClaudeBridgeClient` stays stateless
   - `@Observable` state changes are only in `PRModel` (Apps layer)
   - New views don't have embedded business logic
   - No upward dependencies (Services don't import Features, Features don't import Apps)
   - `PhaseProgress` enum extension is in the Features layer where it's defined
5. Fix any violations found

## - [ ] Phase 8: Validation

**Automated testing:**
- Run `swift build` to verify compilation
- Run `swift test` to verify all existing tests pass
- Add unit tests for new models and services:
  - `BridgeTranscriptTests` — encoding/decoding, markdown rendering
  - `BridgeTranscriptWriterTests` — file writing, markdown generation
  - `ClaudeBridgeClient` streaming tests (mock process output, verify event parsing)

**Manual verification using the test repo:**
- Run `swift run PRRadarMacCLI analyze 1 --config test-repo` and verify:
  - AI transcript files are created in `phase-2-focus-areas/` and `phase-5-evaluations/` directories
  - Both `.json` and `.md` transcript files are present
  - AI text is displayed in the terminal during the run
- Run `swift run PRRadarMacCLI transcript 1 --config test-repo` and verify:
  - Saved transcripts are listed and viewable
- Launch `swift run MacApp` and verify:
  - AI Output tab shows saved transcripts for completed phases
  - During a live run (trigger via the MacApp's run button), AI output streams in real-time
  - Transcripts are browsable per-phase and per-task after completion

**Success criteria:**
- All existing tests pass (no regressions)
- New unit tests pass
- AI transcript `.json` and `.md` files are saved for every bridge invocation
- CLI displays AI output during live runs and can browse saved transcripts
- MacApp displays real-time streaming AI output and saved transcripts
- No architecture violations
