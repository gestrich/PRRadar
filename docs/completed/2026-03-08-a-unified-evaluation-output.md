## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules for placement and dependency guidance |
| `/swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns for the output view UI |
| `/swift-testing` | Test style guide for new model tests |
| `/pr-radar-debug` | Debugging context for reproducing issues via CLI |

## Background

Currently, AI evaluations produce transcripts (`ai-transcript-*.json` / `.md`) that can be viewed in the Mac app's output view and listed via `swift run PRRadarMacCLI transcript`. However, regex and script evaluations produce no equivalent output — their results are stored only in the `data-*.json` evaluation files with no way to inspect what happened during the run.

Bill wants:
1. Regex/script evaluations to produce viewable output (what the script returned, what the regex matched)
2. The output infrastructure to be **mode-agnostic** — not AI-specific
3. **Timing information** shown in the output view, the Diff summary bar, and the Report summary
4. All of this accessible via CLI as well as the Mac app

The current `ClaudeAgentTranscript` model is tightly coupled to AI (model name, cost, streaming events with tool use). We need a unified output model that works for all evaluation modes.

## Phases

## - [x] Phase 1: Unified Evaluation Output Model

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Model placed in Services/PRRadarModels layer; used `EvaluationSource` enum with associated values for mode-specific data instead of optional fields; reused existing `RuleAnalysisType`; no backward compatibility with `ClaudeAgentTranscript`

**Skills to read**: `swift-app-architecture:swift-architecture`

Create a new mode-agnostic output model to replace `ClaudeAgentTranscript` for the purpose of storing and displaying evaluation output.

**New model** in `PRRadarModels`:

```swift
struct EvaluationOutput: Codable, Sendable {
    let identifier: String
    let filePath: String
    let ruleName: String
    let mode: EvaluationMode       // .ai, .regex, .script
    let startedAt: String
    let durationMs: Int
    let costUsd: Double            // 0 for regex/script
    let entries: [OutputEntry]     // The actual output content

    // AI-specific (nil for regex/script)
    let model: String?
    let prompt: String?
}

enum EvaluationMode: String, Codable, Sendable {
    case ai, regex, script
}

struct OutputEntry: Codable, Sendable {
    let type: EntryType
    let content: String?
    let label: String?             // e.g. tool name, regex pattern, script path
    let timestamp: Date

    enum EntryType: String, Codable, Sendable {
        case text       // AI text, script stdout, regex match summary
        case toolUse    // AI tool use
        case result     // Final structured result
        case error      // stderr, errors
    }
}
```

- File naming: `output-{identifier}.json` and `output-{identifier}.md`
- Mode-specific metadata uses `EvaluationSource` enum with associated values (`.ai(model:prompt:)`, `.regex(pattern:)`, `.script(path:)`) instead of optional fields

## - [x] Phase 2: Generate Output for Regex and Script Evaluations

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Services build and return `EvaluationOutput` alongside `RuleOutcome` via tuples; writer placed in Services/PRRadarCLIService as a stateless enum; output entries capture full execution context (pattern/command, matched lines/stdout/stderr, violation summary)

**Skills to read**: `swift-app-architecture:swift-architecture`

Modify the regex and script evaluation services to produce `EvaluationOutput`:

**Script mode output entries:**
- `text` entry: the shell command that was run (script path + args)
- `text` entry: stdout from the script (the tab-delimited violations or empty)
- `error` entry: stderr if any
- `result` entry: parsed violations summary

**Regex mode output entries:**
- `text` entry: the regex pattern used
- `text` entry: matched lines with line numbers
- `result` entry: parsed violations summary

Both modes already track `durationMs` in `RuleResult`. Wire this through to the output.

Write the output files using the same writer service (updated from `ClaudeAgentTranscriptWriter` to a more general `EvaluationOutputWriter`).

## - [x] Phase 3: Update AI Evaluation to Write Unified Output

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Cascaded type migration through all layers (Services → Features → Apps); deleted ClaudeAgentTranscript/Writer and all tests (-1024 lines); LiveTranscriptAccumulator now produces EvaluationOutput directly; AnalysisCacheService updated to copy output-* files instead of ai-transcript-*

**Skills to read**: `swift-app-architecture:swift-architecture`

Update the AI evaluation path to write `EvaluationOutput` files instead of `ClaudeAgentTranscript` files:

- Replace `ClaudeAgentTranscriptWriter` with `EvaluationOutputWriter`
- Update `LiveTranscriptAccumulator` to produce `EvaluationOutput` directly (remove `toClaudeAgentTranscript()`)
- Update `AnalysisService.analyzeTask()` to use `EvaluationOutput`
- Update `FocusGeneratorService` transcript writing to use `EvaluationOutput`
- Delete `ClaudeAgentTranscript` and `ClaudeAgentTranscriptWriter` once all callers are migrated
- Delete old `ai-transcript-*.json` / `.md` reading — no backward compatibility needed

## - [x] Phase 4: Add Duration to Summary Displays

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: Created `DurationFormatter` enum in PRRadarModels with `format(milliseconds:)` static method; added `formattedDuration` computed properties on `PRReviewSummary` and `ReportSummary`; added `totalDurationMs` to `ReportSummary` with backward-compatible decoding; refactored `ReportGeneratorService.loadViolations` to use `EvaluationTotals` struct instead of tuple

**Skills to read**: `swift-app-architecture:swift-swiftui`

`PRReviewSummary.totalDurationMs` already exists but isn't displayed. Add it to:

- **DiffPhaseView summary bar**: Add a "Duration:" item showing formatted time (e.g. "12.3s" or "2m 05s")
- **ReportPhaseView summary cards**: Add a "Duration" card
- **CLI analyze command output**: Already shows `Duration:` — verify it works
- **CLI report output**: Add duration to the report summary section

Add a shared duration formatting helper (e.g. `formatDuration(_ ms: Int) -> String`) in `PRRadarModels` or a shared utility.

## - [x] Phase 5: Update Output View for All Modes

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: Renamed AITranscriptView to EvaluationOutputView; added mode badge (AI/Script/Regex) with color-coded pills to sidebar rows; detail header shows mode-specific source info (model name, regex pattern, script filename); duration formatted via DurationFormatter; streaming banner made mode-agnostic; ReviewDetailView references updated

**Skills to read**: `swift-app-architecture:swift-swiftui`

Rename `AITranscriptView` to `EvaluationOutputView` (or similar) and update it to handle all modes:

- Accept `[PRRadarPhase: [EvaluationOutput]]` (all references to `ClaudeAgentTranscript` should be gone by this phase)
- For AI outputs: show the same detailed event view (text, tool use, result)
- For script outputs: show the command, stdout, stderr, and parsed results
- For regex outputs: show the pattern, matched lines, and results
- Show **duration** in the detail header for all modes
- Show **mode badge** (AI/Script/Regex) in the sidebar row
- The row subtitle should show duration instead of (or alongside) cost for non-AI modes

Update `PRModel` to store `[PRRadarPhase: [EvaluationOutput]]` and load from disk accordingly.

## - [x] Phase 6: Update CLI Transcript Command

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Renamed TranscriptCommand → OutputCommand with `output` subcommand; all evaluation modes (AI/script/regex) already supported from previous phases; kept CLI registration alphabetically sorted

Update `TranscriptCommand` to:
- List all evaluation outputs (AI, script, regex) — not just AI transcripts
- Show mode, duration, cost in the listing
- Display script/regex output detail when `--task` is specified
- Rename to `output` subcommand (no backward compatibility alias needed)

## - [x] Phase 7: Integrate Output with Task Evaluations in UI

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: Added PRModel APIs (`evaluationState(forTaskId:)`, `firstOutputId(forFile:)`, `phaseForOutput(identifier:)`) to keep lookup logic out of views; TasksPagerView reads evaluation state via environment; `TaskEvaluationState` enum encapsulates evaluation lifecycle; `EvaluationOutputView` accepts `initialOutputId` for deep-linking

Wire the output into the task evaluation flow so users can click on any evaluated task (not just AI ones) to see its output:

- `TaskEvaluation.savedTranscript` → `savedOutput: EvaluationOutput?` (remove `ClaudeAgentTranscript` reference)
- The "Run Analysis" button context menu and per-task output link should work for all modes
- When clicking a regex/script evaluation in the file list, open the output view scrolled to that entry

## - [x] Phase 8: Validation

**Skills used**: `swift-testing`
**Principles applied**: Tests follow Arrange-Act-Assert pattern with section comments; used `@Suite` grouping and descriptive `@Test` names; round-trip encode/decode pattern for Codable validation; verified snake_case JSON key mapping

**Skills to read**: `swift-testing`

- Add unit tests for `EvaluationOutput` encoding/decoding
- Verify `ClaudeAgentTranscript` and `ClaudeAgentTranscriptWriter` are fully deleted
- Add unit tests for the duration formatting helper
- Test via CLI:
  - `swift run PRRadarMacCLI analyze <PR> --config my-repo --mode script` — verify output files written
  - `swift run PRRadarMacCLI transcript <PR>` — verify script/regex outputs appear in listing
- Test in Mac app:
  - Run analysis with experimental rules (mix of AI, script, regex)
  - Verify output view shows entries for all modes
  - Verify duration appears in Diff summary bar and Report summary
  - Verify clicking a script/regex task opens the output view
