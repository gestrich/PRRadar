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

## - [ ] Phase 1: Unified Evaluation Output Model

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

- Add a conversion method `ClaudeAgentTranscript.toEvaluationOutput()` for backward compatibility with existing saved transcripts
- File naming: `output-{identifier}.json` and `output-{identifier}.md`
- Keep reading old `ai-transcript-*.json` files for backward compatibility during loading

## - [ ] Phase 2: Generate Output for Regex and Script Evaluations

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

## - [ ] Phase 3: Update AI Evaluation to Write Unified Output

**Skills to read**: `swift-app-architecture:swift-architecture`

Update the AI evaluation path (`AnalysisService.analyzeTask()`) to write `EvaluationOutput` files instead of (or in addition to) `ClaudeAgentTranscript` files. The `LiveTranscriptAccumulator` should produce `EvaluationOutput` via conversion.

Ensure backward compatibility:
- Loading: read both `output-*.json` and legacy `ai-transcript-*.json`
- Writing: write only `output-*.json` going forward

## - [ ] Phase 4: Add Duration to Summary Displays

**Skills to read**: `swift-app-architecture:swift-swiftui`

`PRReviewSummary.totalDurationMs` already exists but isn't displayed. Add it to:

- **DiffPhaseView summary bar**: Add a "Duration:" item showing formatted time (e.g. "12.3s" or "2m 05s")
- **ReportPhaseView summary cards**: Add a "Duration" card
- **CLI analyze command output**: Already shows `Duration:` — verify it works
- **CLI report output**: Add duration to the report summary section

Add a shared duration formatting helper (e.g. `formatDuration(_ ms: Int) -> String`) in `PRRadarModels` or a shared utility.

## - [ ] Phase 5: Update Output View for All Modes

**Skills to read**: `swift-app-architecture:swift-swiftui`

Rename `AITranscriptView` to `EvaluationOutputView` (or similar) and update it to handle all modes:

- Accept `[PRRadarPhase: [EvaluationOutput]]` instead of `[PRRadarPhase: [ClaudeAgentTranscript]]`
- For AI outputs: show the same detailed event view (text, tool use, result)
- For script outputs: show the command, stdout, stderr, and parsed results
- For regex outputs: show the pattern, matched lines, and results
- Show **duration** in the detail header for all modes
- Show **mode badge** (AI/Script/Regex) in the sidebar row
- The row subtitle should show duration instead of (or alongside) cost for non-AI modes

Update `PRModel` to store `[PRRadarPhase: [EvaluationOutput]]` and load from disk accordingly.

## - [ ] Phase 6: Update CLI Transcript Command

Update `TranscriptCommand` to:
- List all evaluation outputs (AI, script, regex) — not just AI transcripts
- Show mode, duration, cost in the listing
- Display script/regex output detail when `--task` is specified
- Consider renaming to `output` subcommand (with `transcript` as an alias for backward compatibility)

## - [ ] Phase 7: Integrate Output with Task Evaluations in UI

Wire the output into the task evaluation flow so users can click on any evaluated task (not just AI ones) to see its output:

- `TaskEvaluation` already has `savedTranscript: ClaudeAgentTranscript?` — replace with `savedOutput: EvaluationOutput?`
- The "Run Analysis" button context menu and per-task output link should work for all modes
- When clicking a regex/script evaluation in the file list, open the output view scrolled to that entry

## - [ ] Phase 8: Validation

**Skills to read**: `swift-testing`

- Add unit tests for `EvaluationOutput` encoding/decoding
- Add unit tests for the `ClaudeAgentTranscript` → `EvaluationOutput` conversion
- Add unit tests for the duration formatting helper
- Test via CLI:
  - `swift run PRRadarMacCLI analyze <PR> --config ios --mode script` — verify output files written
  - `swift run PRRadarMacCLI transcript <PR>` — verify script/regex outputs appear in listing
- Test in Mac app:
  - Run analysis with experimental rules (mix of AI, script, regex)
  - Verify output view shows entries for all modes
  - Verify duration appears in Diff summary bar and Report summary
  - Verify clicking a script/regex task opens the output view
