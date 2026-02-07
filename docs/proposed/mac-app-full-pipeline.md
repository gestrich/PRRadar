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

## - [x] Phase 2: Copy RefactorApp Git Views and Models

Copy the 4 SwiftUI views from RefactorApp's GitUI toolkit and their supporting models into pr-radar-mac. These provide diff viewing, code+blame viewing, and change info display — all needed for reviewing phase outputs.

### Completed

Copied 5 model files and 4 view files from RefactorApp:

**Models** → `Sources/services/PRRadarModels/GitDiffModels/`:
- `GitAuthor.swift` — Author name/email struct
- `Ownership.swift` — Blame ownership with commit info
- `FileBlameData.swift` — File content + blame sections
- `Hunk.swift` — Single diff hunk with line ranges and parsing
- `GitDiff.swift` — Complete diff with hunks, file sections, changed line tracking; also `DiffSection`, `DiffLine`, `DiffLineType`

**Views** → `Sources/apps/MacApp/UI/GitViews/`:
- `SimpleDiffView.swift` — Raw diff text display with copy button
- `CodeView.swift` — Code viewer with line numbers, blame sidebar, author popovers, line highlighting; includes `CodeLineView` and `AuthorSectionView`
- `ChangeInfoView.swift` — Card showing who/when/why a line changed, with copy and diff sheet
- `CreatePullRequestSheet.swift` — PR creation modal (simplified)

### Adaptations made

- Replaced `import GitClient` with `import PRRadarModels` in all views
- Removed `import GitUI` self-import from `ChangeInfoView.swift`
- Simplified `CreatePullRequestSheet.swift` to remove `GithubService`/`OctoKit` dependency — replaced with a callback-based API using `PullRequestDraft` struct and `onCreate` closure, letting the caller handle actual PR submission
- Removed preview providers that depended on external types (kept views clean)
- No Package.swift changes needed — model files are auto-included in `PRRadarModels` target, views are auto-included in `MacApp` target

### Technical notes

- All 5 model types are `public`, `Codable`, and `Sendable` — ready for use across the package
- `GitDiff.fromDiffContent(_:)` provides diff parsing without external dependencies
- `BlameSection` is not `Equatable` (uses `Binding` in views for selection tracking via `startLine`)
- `DiffSection` and `DiffLine` use `UUID` for `Identifiable` conformance (not `Codable`)
- Build verified: `swift build` succeeds with all new files

---

## - [x] Phase 3: Settings Model and Multi-Repo Configuration View

Replace the single repo/output config with a settings model that supports multiple repo configurations. Each configuration bundles a repo path, output directory, rules directory, and optional defaults.

### Completed

Created settings model, persistence service, and configuration management UI:

**Model:** `Sources/services/PRRadarConfigService/RepoConfiguration.swift`
- `RepoConfiguration`: Codable/Sendable/Identifiable/Hashable struct with id (UUID), name, repoPath, outputDir, rulesDir, isDefault
- `AppSettings`: Codable struct holding array of RepoConfigurations with `defaultConfiguration` computed property

**Service:** `Sources/services/PRRadarConfigService/SettingsService.swift`
- `SettingsService`: Sendable class with load/save, add/remove/update/setDefault operations
- Persists to `~/Library/Application Support/PRRadar/settings.json`
- First added configuration automatically becomes default
- Removing the default configuration promotes the next available one

**View:** `Sources/apps/MacApp/UI/SettingsView.swift`
- List of saved repo configurations with name, path, default badge
- Add/edit/delete with inline icon buttons
- Set default via star button
- Edit sheet with text fields for all 4 paths (name, repoPath, outputDir, rulesDir)
- Folder picker (NSOpenPanel) browse buttons for all path fields
- ContentUnavailableView when no configurations exist

**Model update:** `Sources/apps/MacApp/Models/PRReviewModel.swift`
- Replaced individual `repoPath`/`outputDir` UserDefaults properties with `selectedConfiguration` (persisted by UUID in UserDefaults)
- Added `settings: AppSettings` property backed by SettingsService
- Added configuration management methods: `addConfiguration`, `removeConfiguration`, `updateConfiguration`, `setDefault`, `selectConfiguration`
- `selectConfiguration` resets phase state to `.idle`
- `runDiff()` reads repoPath/outputDir from the selected configuration

**UI integration (ContentView.swift):**
- Configuration picker (Picker dropdown) replaces repo path text field
- Gear icon button opens SettingsView as a sheet
- Read-only repo path display below picker
- Run button disabled when no configuration is selected

### Technical notes

- Settings persisted as JSON (not UserDefaults) — supports the structured array of configurations
- Selected configuration ID persisted in UserDefaults for fast lookup across launches
- `SettingsService` is `Sendable` (immutable after init) for safe use across actors
- No changes to Package.swift — new files auto-included in existing targets
- Removed `repoPath` and `outputDir` UserDefaults persistence (migration not needed — fresh feature)

---

## - [x] Phase 4: Use Cases for Phases 2–6 (Features Layer)

Create use cases in the features layer for each remaining pipeline phase. These follow the same pattern as `FetchDiffUseCase` — execute via `PRRadarCLIRunner`, track progress with an `AsyncThrowingStream`, and parse output files into domain models.

### Completed

Created 8 new files across 3 targets:

**Progress model:** `Sources/features/PRReviewFeature/models/PhaseProgress.swift`
- Generic `PhaseProgress<Output: Sendable>` enum with `.running(phase:)`, `.completed(output:)`, `.failed(error:, logs:)` cases
- Replaces the non-generic `FetchDiffProgress` pattern with a reusable generic

**Use cases in `Sources/features/PRReviewFeature/usecases/`:**

- `FetchRulesUseCase.swift` — Executes `PRRadar.Agent.Rules`, parses focus area type files from phase-2, all-rules.json from phase-3, and task JSONs from phase-4. Returns `RulesPhaseOutput` (focusAreas, rules, tasks).

- `EvaluateUseCase.swift` — Executes `PRRadar.Agent.Evaluate`, parses individual evaluation JSONs and summary.json from phase-5. Returns `EvaluationPhaseOutput` (evaluations, summary).

- `GenerateReportUseCase.swift` — Executes `PRRadar.Agent.Report`, parses summary.json and summary.md from phase-6. Returns `ReportPhaseOutput` (report, markdownContent).

- `PostCommentsUseCase.swift` — Executes `PRRadar.Agent.Comment` with `-n` (non-interactive) flag. Supports dry-run mode. Returns `CommentPhaseOutput` (cliOutput, posted).

- `AnalyzeUseCase.swift` — Executes `PRRadar.Agent.Analyze` with all pipeline options (rules-dir, stop-after, skip-to, min-score, etc.). Collects output files from all phases. Returns `AnalyzePhaseOutput` (cliOutput, files by phase).

**Output file parsing:** `Sources/services/PRRadarCLIService/PhaseOutputParser.swift`
- `PhaseOutputParser` enum with generic JSON parsing utilities
- `parsePhaseOutput<T: Decodable>(config:, prNumber:, phase:, filename:)` — single file decode
- `parseAllPhaseFiles<T: Decodable>(config:, prNumber:, phase:, fileExtension:)` — batch decode all matching files
- `readPhaseFile(config:, prNumber:, phase:, filename:)` — raw Data access
- `readPhaseTextFile(config:, prNumber:, phase:, filename:)` — String access
- `listPhaseFiles(config:, prNumber:, phase:)` — directory listing
- `PhaseOutputError` enum for fileNotFound and unreadableFile errors

**New model:** `Sources/services/PRRadarModels/FocusAreaTypeOutput.swift`
- `FocusAreaTypeOutput` struct wrapping the per-type focus area JSON files (method.json, file.json) with their metadata (pr_number, generated_at, focus_type, total_hunks_processed, generation_cost_usd)

### Technical notes

- No Package.swift changes needed — `PRReviewFeature` already had `PRRadarModels` as a dependency
- All use cases follow the same pattern as `FetchDiffUseCase`: init with config + environment, execute returns `AsyncThrowingStream`
- `CommentPhaseOutput` returns raw CLI output rather than structured data, since the comment command's output is textual (not JSON)
- `AnalyzeUseCase` always passes `-n` (noInteractive) since the Mac app can't respond to CLI prompts
- Focus areas are parsed from per-type files (method.json, file.json) and aggregated into a flat array
- All-rules.json is a bare JSON array (not wrapped in an object), decoded directly as `[ReviewRule]`
- Evaluation files exclude summary.json when parsing individual results to avoid double-counting

---

## - [x] Phase 5: Phase Output Views

Create SwiftUI views for displaying each phase's structured output. Each view takes the parsed domain model and renders it in a useful format.

### Completed

Created 8 new view files in `Sources/apps/MacApp/UI/PhaseViews/`:

**Shared components:**

- `SeverityBadge.swift` — Color-coded score capsule (green 1-4, orange 5-7, red 8-10)
- `PhaseSummaryBar.swift` — Reusable bar with label/value pairs on a `.bar` background
- `ViolationCard.swift` — Expandable card showing violation details (rule name, score badge, file:line, comment, method, docs link)

**Phase views:**

- `DiffPhaseView.swift` — Segmented control for Full/Effective diff, HSplitView with file sidebar (shows hunk count per file) and monospaced diff content. Clicking a file filters to its hunks only.
- `RulesPhaseView.swift` — Three-section List: focus areas grouped by file with DisclosureGroup, rules with expandable content/docs, tasks grouped by rule with count.
- `EvaluationsPhaseView.swift` — Filterable evaluation list with severity/file/rule Pickers. Each row shows SeverityBadge, rule name, file:line, and expandable detail (model, duration, cost).
- `ReportPhaseView.swift` — Summary cards (total tasks, violations, highest severity, cost), breakdown sections (by severity, file, rule), violations list using ViolationCard, "View Markdown" sheet for raw report.
- `CommentsPhaseView.swift` — Checkbox per violation for include/exclude, select all/deselect all, "Post Selected" button, severity badges, CLI output section. Shows ContentUnavailableView when no violations.

### Technical notes

- All views take parsed domain models as input (no fetching or state management) — they are pure presentation
- `DiffPhaseView` accepts optional `effectiveDiff` parameter; the Effective Diff tab only appears when provided
- `CommentsPhaseView` filters evaluations to only those with `violatesRule == true` for the comments list
- `ViolationCard` uses tap-to-expand pattern rather than `DisclosureGroup` for a cleaner card appearance
- `EvaluationsPhaseView` filter state is local (`@State`) — resets when the view is recreated
- No Package.swift changes needed — all files auto-included in existing MacApp target
- `CodeView` integration deferred to Phase 7 (Comment Approval Flow) where file content is available from the repo

---

## - [x] Phase 6: Pipeline Navigation and Status UI

Redesign the main app UI to support all phases with navigation, pipeline status tracking, and phase selection.

### Completed

Redesigned the app from a single-phase view into a full pipeline navigation UI:

**`Sources/apps/MacApp/Models/PRReviewModel.swift`** — Complete rewrite:
- `PhaseState` enum: `.idle`, `.running(logs:)`, `.completed(logs:)`, `.failed(error:logs:)`
- Per-phase state tracking via `phaseStates: [PRRadarPhase: PhaseState]` dictionary
- Typed phase outputs: `diffFiles`, `rulesOutput`, `evaluationOutput`, `reportOutput`, `commentOutput`
- `selectedPhase: PRRadarPhase` for sidebar navigation
- `runPhase(_:)` dispatches to the correct use case, `runAllPhases()` chains sequentially
- `canRunPhase(_:)` validates prerequisites (e.g., evaluations require tasks to be complete)
- `resetPhase(_:)` and `resetAllPhases()` for clearing state
- `runComments(dryRun:)` for the comment posting flow
- Removed old single-phase `State` enum and `isRunning` property

**`Sources/apps/MacApp/UI/ContentView.swift`** — Complete redesign:
- `NavigationSplitView` with sidebar (phase list) and detail (phase content)
- Sidebar shows all 6 phases with icons, names, phase numbers, and status badges (spinner/checkmark/error)
- Detail area: global input bar (config picker + PR number + "Run All") at top, phase input form, phase output view
- Phase output views wire the typed model outputs to the existing phase views (RulesPhaseView, EvaluationsPhaseView, ReportPhaseView)
- ContentUnavailableView placeholders when no data is available for a phase
- Settings gear in toolbar

**New: `Sources/apps/MacApp/UI/PipelineStatusView.swift`**
- Horizontal pipeline bar at the bottom of the window
- Phase nodes with status indicators (gray dot = idle, spinner = running, green checkmark = complete, red X = failed)
- Chevron arrows between phases
- Click any phase node to navigate to it
- Selected phase highlighted with accent color background

**New: `Sources/apps/MacApp/UI/PhaseInputView.swift`**
- Reusable input form shown above the output for each phase
- Shows phase title, description, and config info (repo name, rules dir when relevant)
- Run button with prerequisite validation and running state
- Completion/failure status indicators
- Collapsible logs section

**`Sources/apps/MacApp/main.swift`**
- Window size increased from 700x600 to 1000x700 to accommodate the split view layout

### Technical notes

- `PRRadarPhase` already conforms to `Hashable` via `String` raw value — works directly as `List` selection type
- Rules phases (focusAreas, rules, tasks) are grouped: running any of them triggers `FetchRulesUseCase` which updates all three phase states together
- The model removed the old `State` enum; all state is now per-phase in the `phaseStates` dictionary
- Phase outputs are stored as separate typed properties rather than using `Any` — provides type safety without casting
- `canRunPhase` enforces prerequisite chain: diff → rules → evaluations → report
- `runAllPhases` stops on first failure
- `selectConfiguration` resets all phase state since outputs are config-specific
- No Package.swift changes needed — new files auto-included in existing MacApp target

---

## - [x] Phase 7: Effective Diff and Comment Approval Flow

Integrate the copied RefactorApp views for the two key review workflows: viewing the effective diff (deduplicated diff for review) and approving comments before they're posted to the PR.

### Completed

Created 2 new view files in `Sources/apps/MacApp/UI/ReviewViews/` and updated the model and content view to wire them in:

**New: `EffectiveDiffView.swift`**
- Segmented toggle between "Full Diff" and "Effective Diff" (defaults to effective)
- HSplitView with file sidebar (hunk count per file) and monospaced diff content
- Move detection panel: lists each code move with source/target files, matched line count, and match score percentage
- Clicking a file filters the diff; clicking a move filters to source+target file hunks
- Summary section showing moves detected, lines moved, and effective changes count

**New: `CommentApprovalView.swift`**
- HSplitView: violations list on left, detail panel on right
- Left panel: checkbox per violation for approve/reject, severity badge, rule name, file location, 2-line comment preview
- Right panel: rule info (severity, model, duration, cost), editable comment text (TextEditor), and code context via `CodeView` with line highlighting at the violation line
- Toolbar: "Post Approved (N)" button with count, select all/deselect all
- All violations start approved; user can deselect individual items before posting
- Uses `PRReviewModel.readFileFromRepo()` to load file content from the configured repo path

**Updated: `PRReviewModel.swift`**
- Added `fullDiff: GitDiff?`, `effectiveDiff: GitDiff?`, `moveReport: MoveReport?` properties
- New `parseDiffOutputs(config:)` method reads `diff-parsed.md`, `effective-diff-parsed.md`, and `effective-diff-moves.json` from phase-1 output after diff fetch completes
- New `readFileFromRepo(_:)` for loading file content at relative paths from the repo
- Reset methods updated to clear new diff properties
- Added `import PRRadarCLIService` for `PhaseOutputParser` access

**Updated: `ContentView.swift`**
- Phase 1 output: shows parsed `DiffPhaseView` when diff data is available, with "View Effective Diff" button opening `EffectiveDiffView` as a sheet
- Phase 5 output: shows "Review & Approve Comments" button (when violations exist) opening `CommentApprovalView` as a sheet
- Falls back to file list display when parsed diff is unavailable

**Updated: `Package.swift`**
- Added `PRRadarCLIService` as dependency to `MacApp` target (needed for `PhaseOutputParser` import)

### Technical notes

- Diff content is parsed from `.md` files (human-readable format) via `GitDiff.fromDiffContent()`, not from the structured `.json` files — this provides raw diff text suitable for display
- `MoveReport` is parsed from `effective-diff-moves.json` (structured JSON with `Codable`)
- `CodeView` integration reads files directly from the repo filesystem path — this shows the current HEAD version, not the exact PR commit version (sufficient for review context)
- `CommentApprovalView` receives the `PRReviewModel` via environment for file access
- The approval flow currently posts all comments via `PostCommentsUseCase` (not per-comment selective posting) — the checkbox state tracks user intent but the underlying CLI posts in bulk
- No new Package.swift targets needed — all files auto-included in existing `MacApp` target

---

## - [x] Phase 8: CLI Target

Add a command-line executable target that calls the same use cases as the GUI app. This lets users run phases from the terminal with structured output.

### Completed

Created `Sources/apps/MacCLI/` with 8 files:

**Root command:** `PRRadarMacCLI.swift`
- `@main` entry point using `AsyncParsableCommand` from ArgumentParser
- Shared `CLIOptions`, `CLIError`, `resolveConfig()`, `resolveEnvironment()`, `printError()` helpers
- `resolveConfig()` uses `#filePath` to locate `.venv/bin` (same pattern as MacApp's `main.swift`)
- Defaults repo path to current directory and output dir to `code-reviews` when not specified

**Subcommands in `Commands/`:**

- `DiffCommand.swift` — Calls `FetchDiffUseCase`, prints file list. `--json` outputs file list as JSON. `--open` opens output dir in Finder via `/usr/bin/open`.
- `RulesCommand.swift` — Calls `FetchRulesUseCase`, prints focus area/rule/task counts and details. `--json` outputs counts as JSON.
- `EvaluateCommand.swift` — Calls `EvaluateUseCase`, prints summary stats and color-coded violations. `--json` outputs `EvaluationSummary` as JSON.
- `ReportCommand.swift` — Calls `GenerateReportUseCase`, prints markdown report to stdout. `--json` outputs `ReviewReport` as JSON.
- `CommentCommand.swift` — Calls `PostCommentsUseCase` with `--dry-run` flag for preview mode.
- `AnalyzeCommand.swift` — Calls `AnalyzeUseCase` with full set of options (`--stop-after`, `--skip-to`, `--no-dry-run`, `--min-score`, `--repo`, `--github-diff`). `--json` outputs files-by-phase.
- `StatusCommand.swift` — Reads phase directories directly via `OutputFileReader`, prints status table with colored indicators (checkmark/tilde/X). `--json` outputs structured status array.

### Package.swift changes

- Added `swift-argument-parser` (from 1.5.0) as package dependency
- Added `PRRadarMacCLI` executable product and target
- Dependencies: `PRReviewFeature`, `PRRadarCLIService`, `PRRadarConfigService`, `PRRadarModels`, `ArgumentParser`

### Technical notes

- All commands use `AsyncParsableCommand` for async use case execution
- Each command creates its own `PRRadarConfig` and environment (no shared state needed)
- `severityColor()` returns ANSI escape codes for color-coded terminal output (green 1-4, yellow 5-7, red 8+)
- Error output goes to stderr via `printError()`, results go to stdout
- `--json` mode suppresses all progress messages to keep output machine-parsable
- The `CLIOptions` struct is defined but commands declare their own arguments to avoid carrying unused options (e.g. `--rules-dir` only on rules/analyze)
- `StatusCommand` reads phase directories directly via `OutputFileReader` without running any CLI command — it's a local-only operation

---

## - [x] Phase 9: Architecture Validation

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

### Completed

Reviewed all 8 commits (74e3d6c..2a5f436) against 3 swift-app-architecture skills: architecture, swiftui, and skill-authoring.

**Skills evaluated:**
- **architecture** — 4-layer structure, dependency rules, placement guidance, code style
- **swiftui** — Model-View pattern, enum-based state, @Observable conventions, state ownership
- **skill-authoring** — Not applicable (no skill files modified)

**Validation results by convention:**

| Convention | Status | Notes |
|-----------|--------|-------|
| Layer boundaries (Package.swift) | Pass | All dependencies flow downward: Apps → Features → Services → SDKs |
| SDKs stateless, Sendable structs | Pass | `PRRadarMacSDK` is command definitions only |
| Services: no orchestration | Pass | `PRRadarCLIRunner`, `OutputFileReader`, `PhaseOutputParser`, `SettingsService` all single-concern |
| Features: use case structs with `AsyncThrowingStream` | Pass | All 6 use cases are `Sendable` structs returning streams |
| Apps: `@Observable` only in Apps layer | Pass | `PRReviewModel` is the only `@Observable` type, in `apps/MacApp/Models/` |
| Apps: `@MainActor` on observable models | Pass | `PRReviewModel` has `@MainActor` |
| Apps: root model stored in App struct | Pass | `@State private var model` in `PRRadarMacApp` |
| Apps: CLI uses use cases directly | Pass | All CLI commands create use cases and consume streams directly |
| SwiftUI: enum-based state | Pass | `PhaseState` enum with `.idle`, `.running`, `.completed`, `.failed` |
| SwiftUI: models consume use case streams | Pass | Phase runner methods iterate streams and assign state |
| Features don't depend on other features | Pass | `PRReviewFeature` has no feature-to-feature dependencies |

**Violation found and fixed:**

- `FetchDiffUseCase` used a legacy `FetchDiffProgress` enum (from Phase 1) instead of the generic `PhaseProgress<T>` introduced in Phase 4. All other use cases consistently used `PhaseProgress<T>`. Migrated `FetchDiffUseCase` to return `PhaseProgress<[String]>`, updated consumers in `PRReviewModel.runDiff()` and `DiffCommand`, and deleted `FetchDiffProgress.swift`.

### Technical notes

- The multi-phase pipeline uses a `[PRRadarPhase: PhaseState]` dictionary rather than a single top-level state enum. This is an intentional deviation — each phase has independent lifecycle state, and a single enum would require combinatorial cases. The per-phase `PhaseState` enum still satisfies the "enum-based state" convention.
- Phase output types (`RulesPhaseOutput`, `EvaluationPhaseOutput`, etc.) are co-located with their use cases in the Features layer. The architecture permits "feature-specific types" in features, and these are simple DTOs tied directly to use case return values.
- `SettingsService` is a `final class` (not a struct) because it manages file I/O state (file URL). It's `Sendable` with an immutable `fileURL`. This is acceptable for a Services-layer utility.

---

## - [x] Phase 10: Validation

### Completed

**Build verification:**
- `swift build` passes for the full package (MacApp, MacCLI, and PRRadarModelsTests targets)
- No compilation errors — all targets build cleanly

**Unit tests:**
- Added `PRRadarModelsTests` test target to Package.swift with dependency on `PRRadarModels`
- Created 5 test files in `Tests/PRRadarModelsTests/`:

| File | Models Tested | Tests |
|------|--------------|-------|
| `DiffOutputTests.swift` | `ParsedHunk`, `PRDiffOutput`, `EffectiveDiffOutput`, `MoveDetail`, `MoveReport` | 9 |
| `FocusAreaOutputTests.swift` | `FocusType`, `FocusArea`, `FocusAreaTypeOutput` | 6 |
| `RuleOutputTests.swift` | `AppliesTo`, `GrepPatterns`, `ReviewRule`, `AllRulesOutput` | 7 |
| `TaskOutputTests.swift` | `TaskRule`, `EvaluationTaskOutput` | 5 |
| `EvaluationOutputTests.swift` | `RuleEvaluation`, `RuleEvaluationResult`, `EvaluationSummary` | 7 |
| `ReportOutputTests.swift` | `ViolationRecord`, `ReportSummary`, `ReviewReport`, `AnyCodableValue` | 12 |

- **46 tests total**, all passing
- JSON fixtures match actual Python `to_dict()` output format (snake_case keys, optional field omission, null handling)
- Round-trip (encode → decode) tests verify bidirectional fidelity for key models
- Edge cases covered: empty arrays, null optional fields, missing optional keys, bare JSON arrays (all-rules.json format), heterogeneous `by_method` dictionary via `AnyCodableValue`

**Functional testing:**
- Functional testing of the GUI and CLI requires a live PR number and configured repo — deferred to manual acceptance testing

### Technical notes

- Uses Swift Testing framework (`@Suite`, `@Test`, `#expect`) — not XCTest
- Test target has no dependencies beyond `PRRadarModels` (pure model parsing tests)
- `AnyCodableValue` gets `Equatable` conformance via test-only extension for assertion convenience
- Package.swift change: added single `.testTarget` entry for `PRRadarModelsTests`
