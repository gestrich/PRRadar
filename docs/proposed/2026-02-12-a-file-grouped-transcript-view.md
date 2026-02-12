## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules, dependency rules, placement guidance |
| `/swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns, observable model conventions |
| `/swift-testing` | Test style guide for writing/modifying tests |

## Background

The AI transcript view (`AITranscriptView`) currently shows a flat list of tasks ("task-1", "task-2") in the left sidebar. When reviewing a PR that touches multiple files, this flat list makes it hard to understand which evaluations apply to which files. The user wants the sidebar reorganized to group transcripts **by file**, with **tasks (rule evaluations) as subsections** under each file — making the review output much easier to follow.

This requires threading file path and rule name metadata from the analysis pipeline through to the transcript model, then redesigning the sidebar to use grouped sections for the analyze phase.

### Backward compatibility

No backward compatibility needed for saved transcript JSON files. Old analysis data can be deleted and re-run. This means new fields on `ClaudeAgentTranscript` do not need to be optional — they can be required.

### Key data relationships discovered during exploration

- **Saved transcripts** use `task.taskId` as the `identifier` (e.g., `"guard-for-early-return-swift_file-1-5"`) — can match to `AnalysisTaskOutput` for metadata
- **Live transcripts** use sequential `"task-N"` identifiers — no metadata currently
- `AnalysisTaskOutput` has `focusArea.filePath` and `rule.name` — the data we need
- `PhaseProgress.aiPrompt(text:)` carries only the prompt text — no task context
- `AnalysisService.analyzeTask` has the task in scope when calling `onPrompt` but doesn't pass it through

## Phases

## - [x] Phase 1: Add metadata fields to ClaudeAgentTranscript

**Skills to read**: `/swift-app-architecture:swift-architecture`

Add `filePath` and `ruleName` fields to `ClaudeAgentTranscript` for metadata embedding.

- **File**: `PRRadarLibrary/Sources/services/PRRadarModels/ClaudeAgentTranscript.swift`
- Added `public let filePath: String` and `public let ruleName: String`
- Updated `init` with default values (`""`) so existing call sites compile unchanged until Phase 2 threads real values
- Added to `CodingKeys` enum (`file_path`, `rule_name`)
- Updated JSON decode tests to include `file_path`/`rule_name` fields; added encoding/round-trip assertions for new fields
- Build: all targets compile. Tests: 431 tests in 46 suites pass.

## - [ ] Phase 2: Thread metadata through the pipeline

**Skills to read**: `/swift-app-architecture:swift-architecture`

Carry file path and rule name from task evaluation through the event pipeline to the UI layer.

### 2a. `PhaseProgress.swift`
- Add `AIPromptContext` struct: `text: String`, `filePath: String?`, `ruleName: String?`
- Change `case aiPrompt(text: String)` → `case aiPrompt(AIPromptContext)`
- ~14 wildcard `case .aiPrompt: break` sites compile unchanged

### 2b. `AnalysisService.swift`
- Change `onPrompt` callback in `analyzeTask` and `runBatchAnalysis`: `((String) -> Void)?` → `((String, AnalysisTaskOutput) -> Void)?`
- In `analyzeTask`: call `onPrompt?(prompt, task)` instead of `onPrompt?(prompt)`
- In `ClaudeAgentTranscript` construction (line ~158): pass `filePath: task.focusArea.filePath, ruleName: task.rule.name`

### 2c. Use case updates (emit sites)
- `AnalyzeUseCase.swift` (line 136): `onPrompt: { text, task in .aiPrompt(AIPromptContext(text: text, filePath: task.focusArea.filePath, ruleName: task.rule.name)) }`
- `SelectiveAnalyzeUseCase.swift` (line 92-93): same pattern
- `RunPipelineUseCase.swift` (lines 79-80, 111-112): destructure context, re-emit
- `RunAllUseCase.swift` (lines 74-75): destructure context, re-emit

### 2d. `PRModel.swift`
- Add `filePath: String?` and `ruleName: String?` to `LiveTranscriptAccumulator`
- Update `appendAIPrompt` to accept `AIPromptContext` and extract fields
- Update `toClaudeAgentTranscript()` to pass through `filePath`/`ruleName`
- Update `runPrepare()` and `runAnalyze()` switch arms (lines 520, 559) to destructure `AIPromptContext`

## - [ ] Phase 3: Redesign AITranscriptView sidebar

**Skills to read**: `/swift-app-architecture:swift-swiftui`

Reorganize the left sidebar to group transcripts by file for the analyze phase.

- **File**: `PRRadarLibrary/Sources/apps/MacApp/UI/PhaseViews/AITranscriptView.swift`
- Add `tasks: [AnalysisTaskOutput]` parameter for fallback metadata resolution
- Use `transcript.filePath` and `transcript.ruleName` directly (required fields)
- Add `FileGroup` struct: `filePath: String`, `transcripts: [ClaudeAgentTranscript]`
- For **analyze** phase: group transcripts by resolved filePath, render as `Section` per file with shortened filename as header
- For **prepare** phase: keep flat list (prepare transcripts aren't per-task)
- Show rule name as row label instead of raw identifier
- Keep existing detail pane, header, and event rendering unchanged

## - [ ] Phase 4: Wire up ReviewDetailView

- **File**: `PRRadarLibrary/Sources/apps/MacApp/UI/ReviewDetailView.swift`
- Pass `prModel.preparation?.tasks ?? []` to `AITranscriptView` in each `aiOutputView` branch (4 call sites, lines 185-191)

## - [ ] Phase 5: Validation

**Skills to read**: `/swift-testing`

- `swift build` — confirm compilation across all targets
- `swift test` — confirm no regressions (230 tests across 34 suites)
- Run `swift run MacApp` and open AI Output for a PR with saved transcripts — verify:
  - Analyze phase groups by file with rule names as subsection labels
  - Prepare phase still shows flat list
  - Selecting a task still shows transcript detail on the right
- Run a live analysis to verify streaming works: `swift run PRRadarMacCLI analyze 1 --config test-repo`, then open AI Output during execution
