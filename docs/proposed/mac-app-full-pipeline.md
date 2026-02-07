## Background

The pr-radar-mac Swift package currently only implements Phase 1 (Fetch PR Diff) in the UI. The Python `prradar` CLI supports a full 6-phase pipeline:

1. **DIFF** — Fetch and parse PR data (diff-parsed.json, effective-diff)
2. **RULES** — Generate focus areas, load rules, create evaluation tasks (Claude Haiku)
3. **EVALUATE** — Run rule evaluations against code (Claude Sonnet)
4. **REPORT** — Aggregate results into summary reports
5. **COMMENT** — Post inline comments to GitHub PR
6. **ANALYZE** — Chain all phases in one command

The Mac app needs to support all phases with:
- SwiftUI views for each phase's output (using well-formed Swift models)
- A CLI target that calls the same lower-level logic as the GUI
- Multi-repo/output path settings (currently hardcoded to one repo)
- Reusable diff/blame/code views copied from RefactorApp's GitUI toolkit
- An effective diff viewer and comment approval flow before posting to GitHub

### Current Architecture (pr-radar-mac)

```
Sources/
├── apps/MacApp/          # SwiftUI app (Phase 1 only)
├── features/             # PRReviewFeature (FetchDiffUseCase only)
├── sdks/PRRadarMacSDK/   # CLI command definitions (all 7 subcommands defined)
├── services/
│   ├── PRRadarCLIService/    # Subprocess execution + file reading
│   └── PRRadarConfigService/ # Path resolution, environment, phase directories
```

The SDK layer already defines all 7 agent subcommands (diff, rules, evaluate, report, comment, analyze, status). The services layer has `DataPathsService` with a `PRRadarPhase` enum for all 6 phases and `OutputFileReader` for reading phase output files. Only `FetchDiffUseCase` (Phase 1) exists in the features layer.

### RefactorApp Views to Reuse

The RefactorApp at `/Users/bill/Developer/personal/RefactorApp` has a `GitUI` toolkit with 4 production-ready SwiftUI views:

| View | Purpose | Lines |
|------|---------|-------|
| `SimpleDiffView` | Raw diff text with copy button | 82 |
| `CodeView` | Code viewer with blame sidebar, author popovers, line highlight | 620 |
| `ChangeInfoView` | Card showing who/when/why a line changed | 227 |
| `CreatePullRequestSheet` | Modal for creating PRs | 180 |

These depend on models from the `GitClient` SDK: `GitDiff`, `Hunk`, `FileBlameData`, `BlameSection`, `Ownership`, `GitAuthor`.

### Python Domain Models to Mirror in Swift

Each phase produces structured JSON outputs. The Mac app needs Swift `Codable` models to parse these:

- **Phase 1:** `GitDiff` (hunks, line types), `EffectiveDiffMoves` (move detection report)
- **Phase 2:** `FocusArea` (file_path, start_line, end_line, description, focus_type)
- **Phase 3:** `Rule` (name, description, category, applies_to patterns, grep patterns)
- **Phase 4:** `EvaluationTask` (task_id, rule, focus_area pair)
- **Phase 5:** `RuleEvaluation` (violates_rule, score 1-10, comment, file_path, line_number), `EvaluationSummary`
- **Phase 6:** `ReviewReport` (summary stats, violations list), `ViolationRecord`

---

## Phases

## - [x] Phase 1: Domain Models for All Phase Outputs

Create Swift `Codable` models in a new `PRRadarModels` target (services layer) that mirror the Python domain models. These are the foundation — every view and CLI output formatter depends on having well-formed, type-safe models.

### Completed

Created `Sources/services/PRRadarModels/` with 6 model files:

- `DiffOutput.swift` — `PRDiffOutput`, `ParsedHunk`, `EffectiveDiffOutput` (typealias), `MoveReport`, `MoveDetail`
- `FocusAreaOutput.swift` — `FocusArea`, `FocusType` enum
- `RuleOutput.swift` — `ReviewRule`, `AppliesTo`, `GrepPatterns`, `AllRulesOutput`
- `TaskOutput.swift` — `EvaluationTaskOutput`, `TaskRule` (subset of Rule fields as serialized in task JSON)
- `EvaluationOutput.swift` — `RuleEvaluation`, `RuleEvaluationResult`, `EvaluationSummary`
- `ReportOutput.swift` — `ReviewReport`, `ReportSummary`, `ViolationRecord`, `AnyCodableValue` (for heterogeneous `by_method` dict)

### Package.swift changes

- Added `PRRadarModels` target with no dependencies (pure Foundation/Codable models)
- Added `PRRadarModels` as dependency to `PRRadarCLIService`, `PRReviewFeature`, and `MacApp`

### Technical notes

- All models are `Codable` + `Sendable` structs with explicit `CodingKeys` for snake_case JSON mapping
- `EffectiveDiffOutput` is a typealias to `PRDiffOutput` since they share the same JSON structure
- `TaskRule` is a separate struct (not `ReviewRule`) because Python's `EvaluationTask.to_dict()` only serializes a subset of Rule fields (name, description, category, model, content, documentation_link)
- `AnyCodableValue` enum handles the heterogeneous `by_method` dictionary in `ReportSummary`
- Optional fields match Python's conditional inclusion behavior (fields omitted from JSON when null/empty)
- `evaluatedAt` / `generatedAt` stored as `String` (ISO 8601) rather than `Date` to avoid decoder configuration coupling

---

## - [ ] Phase 2: Copy RefactorApp Git Views and Models

Copy the 4 SwiftUI views from RefactorApp's GitUI toolkit and their supporting models into pr-radar-mac. These provide diff viewing, code+blame viewing, and change info display — all needed for reviewing phase outputs.

### Files to copy

**From** `/Users/bill/Developer/personal/RefactorApp/ui-toolkits/GitUI/Sources/GitUI/`:
- `SimpleDiffView.swift` → `Sources/apps/MacApp/UI/GitViews/SimpleDiffView.swift`
- `CodeView.swift` → `Sources/apps/MacApp/UI/GitViews/CodeView.swift`
- `ChangeInfoView.swift` → `Sources/apps/MacApp/UI/GitViews/ChangeInfoView.swift`
- `CreatePullRequestSheet.swift` → `Sources/apps/MacApp/UI/GitViews/CreatePullRequestSheet.swift`

**From** `/Users/bill/Developer/personal/RefactorApp/sdks/GitClient/Sources/GitClient/`:
- `DiffParsing/GitDiff.swift` → `Sources/services/PRRadarModels/GitDiffModels/GitDiff.swift`
- `DiffParsing/Hunk.swift` → `Sources/services/PRRadarModels/GitDiffModels/Hunk.swift`
- `Models/FileBlameData.swift` → `Sources/services/PRRadarModels/GitDiffModels/FileBlameData.swift`
- `Models/Ownership.swift` → `Sources/services/PRRadarModels/GitDiffModels/Ownership.swift`
- `Models/GitAuthor.swift` → `Sources/services/PRRadarModels/GitDiffModels/GitAuthor.swift`

### Adaptations needed

- Remove `import GitClient` from views → models are now in `PRRadarModels`
- Remove `import GithubService` from `CreatePullRequestSheet.swift` → may need to stub or simplify the GitHub service dependency (or skip this view initially since we have our own comment flow)
- Update any relative package references to use the new target names
- Verify macOS 15+ API compatibility (should be fine since both target macOS 15)

### Package.swift changes

- Add copied model files to `PRRadarModels` target
- `MacApp` target already depends on models via features layer

---

## - [ ] Phase 3: Settings Model and Multi-Repo Configuration View

Replace the single repo/output config with a settings model that supports multiple repo configurations. Each configuration bundles a repo path, output directory, rules directory, and optional defaults.

### New files

**Model:** `Sources/services/PRRadarConfigService/RepoConfiguration.swift`
- `RepoConfiguration`: Codable struct with id (UUID), name, repoPath, outputDir, rulesDir, isDefault
- `AppSettings`: Codable struct holding array of RepoConfigurations
- Persistence via JSON file in Application Support directory (not UserDefaults — too structured)

**Service:** `Sources/services/PRRadarConfigService/SettingsService.swift`
- `SettingsService`: Load/save AppSettings, add/remove/update configurations
- File-based persistence with `FileManager`

**View:** `Sources/apps/MacApp/UI/SettingsView.swift`
- List of saved repo configurations (name, path, rules dir)
- Add/edit/delete configurations
- Set default configuration
- Each config row shows repo name and path
- Edit sheet with text fields for all paths + folder picker buttons

**Model update:** `Sources/apps/MacApp/Models/PRReviewModel.swift`
- Replace individual `repoPath`/`outputDir` stored properties with selected `RepoConfiguration`
- Add `SettingsService` dependency
- Add `configurations` list and `selectedConfiguration` binding
- Remove UserDefaults persistence for individual fields

### UI integration

- Add Settings button/gear icon to main toolbar
- Settings opens as a sheet or separate window
- Configuration picker (dropdown) in the main review view to switch between repos
- When switching configs, update all paths and clear current phase state

---

## - [ ] Phase 4: Use Cases for Phases 2–6 (Features Layer)

Create use cases in the features layer for each remaining pipeline phase. These follow the same pattern as `FetchDiffUseCase` — execute via `PRRadarCLIRunner`, track progress with an `AsyncThrowingStream`, and parse output files into domain models.

### New files in `Sources/features/PRReviewFeature/`

**Progress model:** `models/PhaseProgress.swift`
- Generalize the progress enum to work for any phase:
  ```swift
  enum PhaseProgress<Output: Sendable>: Sendable {
      case running(phase: PRRadarPhase)
      case completed(output: Output)
      case failed(error: String, logs: String)
  }
  ```

**Use cases:**

- `usecases/FetchRulesUseCase.swift` — Phase 2 (rules command)
  - Executes `PRRadar.Agent.Rules` with pr number and rules directory
  - Parses output: focus areas JSON, all-rules JSON, task JSONs
  - Returns: `RulesPhaseOutput` (focusAreas: [FocusArea], rules: [ReviewRule], tasks: [EvaluationTaskOutput])

- `usecases/EvaluateUseCase.swift` — Phase 3 (evaluate command)
  - Executes `PRRadar.Agent.Evaluate` with pr number
  - Parses output: evaluation JSONs + summary JSON
  - Returns: `EvaluationPhaseOutput` (evaluations: [RuleEvaluationResult], summary: EvaluationSummary)

- `usecases/GenerateReportUseCase.swift` — Phase 4 (report command)
  - Executes `PRRadar.Agent.Report` with pr number and min score
  - Parses output: summary.json and summary.md
  - Returns: `ReportPhaseOutput` (report: ReviewReport, markdownContent: String)

- `usecases/PostCommentsUseCase.swift` — Phase 5 (comment command)
  - Executes `PRRadar.Agent.Comment` with pr number, repo, dry-run flag
  - In dry-run mode: returns preview of comments to post
  - In live mode: posts comments and returns results
  - Returns: `CommentPhaseOutput` (comments: [CommentPreview], posted: Bool)

- `usecases/AnalyzeUseCase.swift` — Phase 6 (full pipeline)
  - Executes `PRRadar.Agent.Analyze` with all options
  - Streams progress across all phases
  - Returns: combined output from all phases

**Output file parsing:** `services/PhaseOutputParser.swift`
- Add to `PRRadarCLIService` target
- Generic JSON parsing of phase output directories
- `parsePhaseOutput<T: Decodable>(config:, prNumber:, phase:, filename:) throws -> T`
- `listPhaseFiles(config:, prNumber:, phase:) throws -> [String]`
- `readPhaseFile(config:, prNumber:, phase:, filename:) throws -> Data`

### Package.swift changes

- `PRReviewFeature` target already depends on `PRRadarCLIService` and `PRRadarConfigService`
- Add dependency on `PRRadarModels` for the output types

---

## - [ ] Phase 5: Phase Output Views

Create SwiftUI views for displaying each phase's structured output. Each view takes the parsed domain model and renders it in a useful format.

### New view files in `Sources/apps/MacApp/UI/`

**Phase 1 — Diff View:** `PhaseViews/DiffPhaseView.swift`
- Tab view with two tabs: "Full Diff" and "Effective Diff"
- Each tab uses `SimpleDiffView` (copied from RefactorApp) to display the raw diff
- File list sidebar showing changed files with hunk counts
- Tap a file to filter diff to just that file's hunks

**Phase 2 — Focus Areas & Rules View:** `PhaseViews/RulesPhaseView.swift`
- Three-section layout:
  - **Focus Areas**: List of identified focus areas grouped by file, showing method names and line ranges
  - **Rules**: List of loaded rules with name, category, description (expandable rows)
  - **Tasks**: Count of generated evaluation tasks, grouped by rule
- Summary bar: "X focus areas, Y rules, Z tasks created"

**Phase 3 — Evaluations View:** `PhaseViews/EvaluationsPhaseView.swift`
- List of evaluation results, color-coded by severity:
  - Green (1-4): minor/no issue
  - Orange (5-7): moderate violation
  - Red (8-10): severe violation
- Each row shows: rule name, file:line, score badge, short comment preview
- Expandable detail: full comment text, rule description, focus area context
- Filter controls: by severity, by file, by rule
- Summary header: total evaluated, violations found, cost

**Phase 4 — Report View:** `PhaseViews/ReportPhaseView.swift`
- Summary cards: total tasks, violations found, highest severity, total cost
- Breakdown tables: by severity, by file, by rule (matching Python's summary.md layout)
- Violations list: detailed violation cards with rule name, score, file, comment
- Option to view raw markdown report in a text view

**Phase 5 — Comments Preview View:** `PhaseViews/CommentsPhaseView.swift`
- List of comments that will be posted (dry-run output)
- Each comment shows: file, line number, rule name, comment body
- Checkbox per comment to include/exclude from posting
- "Post Selected" / "Post All" buttons
- Uses `CodeView` (from RefactorApp) to show the code context around each comment location
- This is the approval flow — user reviews before posting

### Shared components

- `PhaseViews/PhaseSummaryBar.swift` — Reusable summary bar showing phase name, status, timing
- `PhaseViews/SeverityBadge.swift` — Color-coded score badge (green/orange/red)
- `PhaseViews/ViolationCard.swift` — Reusable card for displaying a single violation

---

## - [ ] Phase 6: Pipeline Navigation and Status UI

Redesign the main app UI to support all phases with navigation, pipeline status tracking, and phase selection.

### Files to modify

**`Sources/apps/MacApp/UI/ContentView.swift`** — Complete redesign:
- **Sidebar**: List of phases (1-6) with status indicators (not started, running, completed, failed)
  - Phase icons and names
  - Completion checkmarks or spinners
  - Click to navigate to phase view
- **Detail area**: Shows the selected phase's input form + output view
- **Toolbar**: Configuration picker (from Phase 3), settings gear, "Run All" button
- Pipeline status bar at bottom showing overall progress

**`Sources/apps/MacApp/Models/PRReviewModel.swift`** — Expand to manage all phases:
- Track state per phase: `[PRRadarPhase: PhaseState]`
- `PhaseState` enum: idle, running(logs), completed(output: Any), failed(error, logs)
- Methods: `runPhase(_ phase: PRRadarPhase)`, `runAllPhases()`, `resetPhase(_ phase:)`
- Pipeline sequencing: validate prerequisites before running a phase
- Store typed outputs: `diffOutput`, `rulesOutput`, `evaluationOutput`, `reportOutput`, `commentOutput`

**New:** `Sources/apps/MacApp/UI/PhaseInputView.swift`
- Reusable form for phase-specific inputs
- Phase 1: repo path, PR number, output dir (existing fields)
- Phase 2: rules directory path (+ browse button)
- Phase 3: optional rule filter, repo path for codebase exploration
- Phase 4: min score threshold slider
- Phase 5: repo (owner/name), dry-run toggle
- Phase 6: all options combined

**New:** `Sources/apps/MacApp/UI/PipelineStatusView.swift`
- Horizontal pipeline visualization: Phase 1 → Phase 2 → ... → Phase 6
- Each phase node shows status (dot color: gray/blue/green/red)
- Arrows between phases
- Click to jump to phase

### Navigation pattern

- `NavigationSplitView` with sidebar (phase list) and detail (phase content)
- Each phase detail is a `VStack` with input form on top, output view below
- "Run Phase" button per phase (disabled if prerequisites not met)
- Logs panel (toggleable) showing raw CLI output for any phase

---

## - [ ] Phase 7: Effective Diff and Comment Approval Flow

Integrate the copied RefactorApp views for the two key review workflows: viewing the effective diff (deduplicated diff for review) and approving comments before they're posted to the PR.

### Effective Diff Viewer

**New:** `Sources/apps/MacApp/UI/ReviewViews/EffectiveDiffView.swift`
- Prominent entry point from Phase 1 output view ("View Effective Diff" button)
- Uses `SimpleDiffView` to show the effective diff content
- Side panel showing move detection report:
  - List of detected code moves (source file:lines → destination file:lines)
  - Each move is clickable to highlight in the diff
- Toggle between "Full Diff" and "Effective Diff"
- File filter to focus on specific files

### Comment Approval Flow

**New:** `Sources/apps/MacApp/UI/ReviewViews/CommentApprovalView.swift`
- Dedicated review screen accessed from Phase 5 or after evaluation
- Split view:
  - **Left**: List of pending comments with severity badges and file paths
  - **Right**: Detail view showing:
    - The code context using `CodeView` (with line highlighting at the violation line)
    - The proposed comment text (editable before posting)
    - Rule information (name, description, documentation link)
    - Approve/reject toggle per comment
- Bottom bar: "Post Approved Comments" button with count
- Calls `PostCommentsUseCase` with only approved comments (filters via `--min-score` or selective posting)

### Integration points

- Phase 1 output view gets "View Effective Diff" button → opens `EffectiveDiffView`
- Phase 3 output view gets "Review & Approve Comments" button → opens `CommentApprovalView`
- Phase 5 view is essentially the `CommentApprovalView` in post mode
- `CodeView` needs the file content at the PR's head commit — read from the repo path using the file_path from evaluations

---

## - [ ] Phase 8: CLI Target

Add a command-line executable target that calls the same use cases as the GUI app. This lets users run phases from the terminal with structured output.

### Package.swift changes

- Add new executable target: `PRRadarMacCLI`
- Dependencies: `PRReviewFeature`, `PRRadarConfigService`, `PRRadarModels`, `ArgumentParser`
- Add `swift-argument-parser` as a package dependency

### New files

**`Sources/apps/MacCLI/`:**

- `PRRadarMacCLI.swift` — Root command using ArgumentParser
  ```
  pr-radar-mac <subcommand> [options]
  ```

- `Commands/DiffCommand.swift` — Phase 1
  - Arguments: pr-number, --repo-path, --output-dir
  - Calls `FetchDiffUseCase`, prints file list and summary
  - `--json` flag: output parsed DiffOutput as JSON
  - `--open`: open output directory in Finder after completion

- `Commands/RulesCommand.swift` — Phase 2
  - Arguments: pr-number, --rules-dir, --output-dir
  - Calls `FetchRulesUseCase`, prints focus areas/rules/task counts
  - `--json` flag: output as JSON

- `Commands/EvaluateCommand.swift` — Phase 3
  - Arguments: pr-number, --repo-path, --output-dir, --rules (filter)
  - Calls `EvaluateUseCase`, prints evaluation results with color-coded severity
  - Progress: prints each evaluation as it completes

- `Commands/ReportCommand.swift` — Phase 4
  - Arguments: pr-number, --min-score, --output-dir
  - Calls `GenerateReportUseCase`, prints markdown report to stdout
  - `--json` flag: output ReviewReport as JSON

- `Commands/CommentCommand.swift` — Phase 5
  - Arguments: pr-number, --repo, --min-score, --dry-run, --output-dir
  - Calls `PostCommentsUseCase`
  - In dry-run: prints comment previews
  - Without dry-run: posts and confirms

- `Commands/AnalyzeCommand.swift` — Phase 6
  - Arguments: pr-number + all options from above
  - Calls `AnalyzeUseCase`, streams progress for each phase
  - `--stop-after`, `--skip-to` flags matching Python CLI

- `Commands/StatusCommand.swift` — Pipeline status
  - Arguments: pr-number, --output-dir
  - Reads phase directories and prints pipeline status table
  - Shows: phase name, status (complete/partial/missing), file count

### Output formatting

- Default: human-readable colored terminal output (using ANSI codes)
- `--json`: machine-readable JSON output (using the domain models' Codable conformance)
- Progress indicators for long-running phases (evaluate)
- Error output to stderr, results to stdout

---

## - [ ] Phase 9: Architecture Validation

Review all commits made during the preceding phases and validate they follow the project's architectural conventions:

**For Swift changes** (`pr-radar-mac/`):
- Fetch and read each skill from `https://github.com/gestrich/swift-app-architecture` (skills directory)
- Compare the commits made against the conventions described in each relevant skill
- If any code violates the conventions, make corrections

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. Fetch and read ALL skills from the swift-app-architecture GitHub repo
4. Evaluate the Swift changes against each skill's conventions
5. Fix any violations found

---

## - [ ] Phase 10: Validation

### Build verification
- `swift build` for the full package (both MacApp and MacCLI targets)
- Resolve any compilation errors from copied views or new code

### Functional testing
- Run each CLI command with a test PR number and verify output
- Launch the Mac app and verify:
  - Settings view: add/edit/delete repo configurations
  - Phase navigation: sidebar shows all phases, clicking navigates correctly
  - Phase 1: run diff, view output, view effective diff
  - Phase 2: run rules, view focus areas/rules/tasks
  - Phase 3: run evaluate, view results with severity badges
  - Phase 4: run report, view summary and violation details
  - Phase 5: review comments in approval view, test dry-run
  - Pipeline status bar updates correctly

### Unit tests
- Add test target `PRRadarModelsTests` with JSON parsing tests for each model
- Use sample JSON fixtures from actual Python pipeline output files
- Verify all models round-trip through encode/decode correctly
