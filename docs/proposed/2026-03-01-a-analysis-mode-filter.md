## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules, placement guidance, dependency rules |
| `/swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns, observable model conventions |
| `/swift-testing` | Test style guide and conventions |

## Background

PRRadar now supports both regex-based and AI-based rule evaluation (see `2026-03-01-a-regex-analysis.md`). Currently there's no way to run only one type — every analysis run evaluates all matching rules regardless of whether they're regex or AI. Bill wants to add an `AnalysisMode` option (regex-only, AI-only, or both) to both the CLI and the Mac app, so he can quickly run just the cheap regex rules or just the AI rules as needed.

The routing decision already exists in `AnalyzeSingleTaskUseCase` (checks `task.rule.violationRegex`). The new feature adds a pre-filter step that drops tasks before they reach the evaluation loop.

## Phases

## - [x] Phase 1: Add `AnalysisMode` enum to PRRadarModels

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Placed enum in Services layer (PRRadarModels) for cross-layer availability; used own file per Bill's preference

**Skills to read**: `/swift-app-architecture:swift-architecture`

Add a new `AnalysisMode` enum at the Services layer (PRRadarModels) so it's available to all layers.

**Tasks:**
- Create `AnalysisMode` enum with cases: `.all` (default), `.regexOnly`, `.aiOnly`
- Add a `func matches(_ task: RuleRequest) -> Bool` method that filters based on `task.rule.isRegexOnly`
- Place in existing `RuleFilter.swift` or a new file alongside it in `PRRadarModels/`

**Enum definition:**
```swift
public enum AnalysisMode: String, Sendable, CaseIterable {
    case all
    case regexOnly
    case aiOnly

    public func matches(_ task: RuleRequest) -> Bool {
        switch self {
        case .all: return true
        case .regexOnly: return task.rule.isRegexOnly
        case .aiOnly: return !task.rule.isRegexOnly
        }
    }
}
```

**Files to modify:**
- `PRRadarLibrary/Sources/services/PRRadarModels/RuleFilter.swift` (add enum to existing file)

## - [x] Phase 2: Thread `AnalysisMode` through the analysis pipeline

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Added field with default value to preserve backward compatibility; filter applied at pipeline entry points so downstream code stays unchanged

**Skills to read**: `/swift-app-architecture:swift-architecture`

Add `analysisMode` to `PRReviewRequest` and apply the filter in `AnalyzeUseCase` before evaluating tasks.

**Tasks:**
- Add `analysisMode: AnalysisMode` to `PRReviewRequest` (default `.all`)
- In `AnalyzeUseCase.executeFullRun()`, filter `allTasks` through `analysisMode.matches()` before passing to `runEvaluations()`
- In `AnalyzeUseCase.executeFiltered()`, apply `analysisMode.matches()` alongside the existing `filter.matches()` — both must pass (AND logic)
- The rest of the pipeline (`AnalyzeSingleTaskUseCase`, `RegexAnalysisService`, `AnalysisService`) stays unchanged — tasks that don't match the mode simply never reach them

**Files to modify:**
- `PRRadarLibrary/Sources/features/PRReviewFeature/models/PRReviewRequest.swift` (add `analysisMode` field)
- `PRRadarLibrary/Sources/features/PRReviewFeature/usecases/AnalyzeUseCase.swift` (filter tasks by mode)

## - [x] Phase 3: Add `--mode` CLI option to `AnalyzeCommand`

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Used `ExpressibleByArgument` conformance in CLI target to keep ArgumentParser out of Services layer; set CLI-friendly raw values ("regex", "ai") on enum for automatic parsing

**Skills to read**: `/swift-app-architecture:swift-architecture`

Add a `--mode` option to the `analyze` CLI command that maps to `AnalysisMode`.

**Tasks:**
- Add `@Option(name: .long, help: ...) var mode: String?` to `AnalyzeCommand` — accepts `"regex"`, `"ai"`, or `"all"` (default)
- Parse the string to `AnalysisMode` (error if unrecognized value)
- Pass the resolved `AnalysisMode` into `PRReviewRequest`
- Print the active mode in the output when not `.all` (e.g., "Analyzing PR #1 (regex rules only)...")

**Usage:**
```bash
swift run PRRadarMacCLI analyze 1 --config test-repo --mode regex
swift run PRRadarMacCLI analyze 1 --config test-repo --mode ai
swift run PRRadarMacCLI analyze 1 --config test-repo           # default: all
```

**Files to modify:**
- `PRRadarLibrary/Sources/apps/MacCLI/Commands/AnalyzeCommand.swift`

## - [x] Phase 4: Add analysis mode options to MacApp UI

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: Added analysisMode parameter with default value to preserve existing call sites; mode filtering applied at entry point (startSelectiveAnalysis) so downstream code stays unchanged

**Skills to read**: `/swift-app-architecture:swift-swiftui`

Add "Run All Regex Rules" and "Run All AI Rules" buttons alongside the existing "Run All Rules" in both the context menu and the analysis dropdown menu in `DiffPhaseView`.

**Tasks:**
- In `fileContextMenu(for:)` (~line 275): After the existing "Run All Rules" button, add "Run All Regex Rules" and "Run All AI Rules" buttons
- In `fileAnalysisMenu(for:)` (~line 300): Same — add the two new buttons after "Run All Rules", before the divider
- Both new buttons call `prModel.startSelectiveAnalysis(filter:analysisMode:)` with the appropriate mode
- Add `analysisMode` parameter to `PRModel.startSelectiveAnalysis(filter:analysisMode:)` (default `.all`)
- Thread `analysisMode` through `runFilteredAnalysis()` → `PRReviewRequest` → `AnalyzeUseCase`
- For `runSingleAnalysis()`, no mode filtering needed (it's already a single task)

**Files to modify:**
- `PRRadarLibrary/Sources/apps/MacApp/UI/PhaseViews/DiffPhaseView.swift` (add menu items)
- `PRRadarLibrary/Sources/apps/MacApp/Models/PRModel.swift` (thread `analysisMode` through)

## - [ ] Phase 5: Validation

**Skills to read**: `/swift-testing`

**Tasks:**
- Add unit tests for `AnalysisMode.matches()` — verify `.regexOnly` matches only tasks with `violationRegex`, `.aiOnly` only tasks without, `.all` matches everything
- Add unit test for `AnalyzeUseCase` mode filtering (if there's an existing pattern for use case tests, follow it; otherwise test the mode filtering logic directly)
- Run full test suite: `cd PRRadarLibrary && swift test`
- Build check: `cd PRRadarLibrary && swift build`
- End-to-end verification against test repo:
  ```bash
  cd PRRadarLibrary
  swift run PRRadarMacCLI analyze 1 --config test-repo --mode regex
  swift run PRRadarMacCLI analyze 1 --config test-repo --mode ai
  swift run PRRadarMacCLI analyze 1 --config test-repo
  ```
- Verify that `--mode regex` only evaluates regex rules (fast, $0 cost) and `--mode ai` only evaluates AI rules
