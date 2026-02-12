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

## - [x] Phase 2: Thread metadata through the pipeline

**Skills to read**: `/swift-app-architecture:swift-architecture`

Carry file path and rule name from task evaluation through the event pipeline to the UI layer.

### 2a. `PhaseProgress.swift`
- Added `AIPromptContext` struct with `text: String`, `filePath: String?`, `ruleName: String?` and convenience init with nil defaults
- Changed `case aiPrompt(text: String)` → `case aiPrompt(AIPromptContext)`
- ~14 wildcard `case .aiPrompt: break` sites compiled unchanged (no associated value destructuring needed)

### 2b. `AnalysisService.swift`
- Changed `onPrompt` callback in both `analyzeTask` and `runBatchAnalysis`: `((String) -> Void)?` → `((String, AnalysisTaskOutput) -> Void)?`
- In `analyzeTask`: calls `onPrompt?(prompt, task)` to pass the task along
- In `ClaudeAgentTranscript` construction: passes `filePath: task.focusArea.filePath, ruleName: task.rule.name`

### 2c. Use case updates (emit sites)
- `AnalyzeUseCase.swift`: `onPrompt: { text, task in .aiPrompt(AIPromptContext(text: text, filePath: task.focusArea.filePath, ruleName: task.rule.name)) }`
- `SelectiveAnalyzeUseCase.swift`: same pattern
- `RunPipelineUseCase.swift`: two pass-through sites destructure context and re-emit as `.aiPrompt(context)`
- `RunAllUseCase.swift`: same pass-through pattern

### 2d. `PRModel.swift`
- Added `filePath: String?` and `ruleName: String?` to `LiveTranscriptAccumulator`
- `appendAIPrompt` now accepts `AIPromptContext` and extracts fields into the accumulator
- `toClaudeAgentTranscript()` passes through `filePath`/`ruleName` (defaulting `nil` to `""`)
- Updated `runPrepare()` and `runAnalyze()` switch arms to destructure `AIPromptContext`
- Build: all targets compile. Tests: 431 tests in 46 suites pass.

## - [x] Phase 3: Redesign AITranscriptView sidebar

**Skills to read**: `/swift-app-architecture:swift-swiftui`

Reorganize the left sidebar to group transcripts by file for the analyze phase.

- **File**: `PRRadarLibrary/Sources/apps/MacApp/UI/PhaseViews/AITranscriptView.swift`
- Added private `FileGroup` struct (Identifiable) with `filePath`, `transcripts`, and `displayName` (uses `NSString.lastPathComponent`)
- Added `fileGroups` computed property that groups transcripts by `filePath` preserving insertion order
- Added `useFileGrouping` computed property — `true` only for `.analyze` phase
- Added `rowLabel(for:)` method — shows `ruleName` when file-grouped and non-empty, otherwise falls back to `identifier`
- Extracted `transcriptRow(_:)` helper to share row rendering between flat and grouped lists
- `transcriptList` now branches: `groupedTranscriptList` for analyze (Sections per file with doc icon + filename header, tooltip shows full path), `flatTranscriptList` for prepare (unchanged flat list)
- No `tasks: [AnalysisTaskOutput]` parameter needed — `filePath`/`ruleName` are required fields on `ClaudeAgentTranscript` (set in Phase 1-2), so metadata is always available directly
- Detail pane, header, and event rendering unchanged
- Build: all targets compile. Tests: 431 tests in 46 suites pass.

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
