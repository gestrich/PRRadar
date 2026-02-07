## Background

The Mac app currently uses a 2-column `NavigationSplitView`: a sidebar listing the 6 pipeline phases, and a detail pane showing the selected phase's input/output plus a global input bar (config picker + PR number text field). Users must manually type a PR number and select a config from a dropdown.

We want to refactor to a modern 3-column `NavigationSplitView` where:
- **Column 1 (Sidebar)**: List of repo configurations
- **Column 2 (Content)**: List of pull requests for the selected config, derived by scanning the config's output directory for PR subdirectories containing `gh-pr.json`
- **Column 3 (Detail)**: The current phase view (pipeline status + phase input + phase output)

This eliminates the manual PR number text field and config dropdown — both are now selected via navigation. The `gh-pr.json` file in each PR's `phase-1-pull-request/` directory provides the PR title, number, author, state, etc. for display in the PR list rows.

## Phases

## - [x] Phase 1: PR metadata model and directory scanning service

Create the data layer for discovering PRs from output directories.

**New model** — `PRMetadata` in `PRRadarModels`:
- Parse from `gh-pr.json` (which is the raw GitHub CLI output)
- Properties needed for list display: `number` (Int), `title` (String), `author` (String), `state` (String, e.g. "OPEN"/"CLOSED"/"MERGED"), `headRefName` (String, branch name), `createdAt` (String)
- Make it `Codable`, `Sendable`, `Identifiable` (id = number), `Hashable`
- Use `CodingKeys` for the JSON field names from `gh-pr.json` (they're already camelCase from `gh pr view --json`)

**New service** — `PRDiscoveryService` in `PRRadarConfigService`:
- `static func discoverPRs(outputDir: String) -> [PRMetadata]`
- Enumerate subdirectories of `outputDir` (each named by PR number)
- For each, check if `{prNumber}/phase-1-pull-request/gh-pr.json` exists
- If yes, decode `PRMetadata` from it
- If no `gh-pr.json`, still include the PR with just the number (title = "PR #\(number)", fallback display)
- Sort by PR number descending (most recent first)

Files to create/modify:
- Create `Sources/services/PRRadarModels/PRMetadata.swift`
- Create `Sources/services/PRRadarConfigService/PRDiscoveryService.swift`

**Technical notes:**
- `author` is modeled as a nested `PRMetadata.Author` struct (with `login` and `name`) to match the actual `gh pr view --json` output format, rather than a flat string
- `PRRadarConfigService` now depends on `PRRadarModels` in `Package.swift` since `PRDiscoveryService` returns `[PRMetadata]`
- `PRMetadata.fallback(number:)` factory method creates a minimal instance for PR directories that lack `gh-pr.json`

## - [x] Phase 2: Model layer changes

Update `PRReviewModel` to support the 3-pane selection flow.

**New state properties**:
- `selectedConfiguration` — keep existing, but make it drive PR list refresh
- `discoveredPRs: [PRMetadata]` — populated by scanning the selected config's output directory
- `selectedPR: PRMetadata?` — replaces the `prNumber` text field

**New methods**:
- `refreshPRList()` — calls `PRDiscoveryService.discoverPRs()` using the selected config's output directory, updates `discoveredPRs`
- Update `selectConfiguration(_:)` to call `refreshPRList()` after resetting phases

**Changes to `prNumber`**:
- Derive `prNumber` from `selectedPR?.number` instead of `UserDefaults`
- Make `prNumber` a computed property: `String(selectedPR?.number ?? 0)` or keep it writable for manual entry as a fallback

**Selection flow**: Selecting a config → refreshes PR list → selecting a PR → loads that PR's existing phase data from disk (if any outputs already exist, show them immediately without re-running)

**Auto-load existing outputs**: When a PR is selected, check if phase output files already exist on disk and parse them. This way previously-run reviews show their results immediately.

Files to modify:
- `Sources/apps/MacApp/Models/PRReviewModel.swift`

**Technical notes:**
- `prNumber` is now a computed property: returns `String(selectedPR.number)` when a PR is selected, falls back to a private `manualPRNumber` for backward-compatible text field binding
- `selectedPR`'s `didSet` calls `resetAllPhases()` so phase outputs are cleared when switching PRs
- `selectConfiguration(_:)` now sets `selectedPR = nil` and calls `refreshPRList()` to populate `discoveredPRs`
- UserDefaults-backed `prNumber` storage removed; manual entry stored in an in-memory `manualPRNumber` property
- Existing `globalInputBar` text field binding (`$model.prNumber`) still works via the writable computed property — will be removed in Phase 3

## - [x] Phase 3: Three-column ContentView refactor

Refactor `ContentView` from 2-column to 3-column `NavigationSplitView`.

**New layout**:
```
NavigationSplitView {
    // Column 1: Configs sidebar
    configSidebar
} content: {
    // Column 2: PR list for selected config
    prListView
} detail: {
    // Column 3: Phase view for selected PR
    phaseDetailView
}
```

**Column 1 — Config Sidebar**:
- List of `model.settings.configurations` with selection binding to `model.selectedConfiguration`
- Each row shows config name + repo path (similar to current `ConfigurationRow` but simpler — just name and subtitle)
- Toolbar button ("+") to add new config, gear icon for settings
- `navigationSplitViewColumnWidth(min: 150, ideal: 180)`

**Column 2 — PR List**:
- List of `model.discoveredPRs` with selection binding to `model.selectedPR`
- Each row shows: PR number badge, title, branch name, author, state indicator (open/closed/merged colors)
- If no config selected, show `ContentUnavailableView("Select a Configuration")`
- If config selected but no PRs found, show `ContentUnavailableView("No Reviews Found")`
- Toolbar: "Refresh" button to re-scan directories, text field for manual PR number entry (to run a new review)
- `navigationSplitViewColumnWidth(min: 200, ideal: 280)`

**Column 3 — Phase Detail**:
- Remove the `globalInputBar` (config and PR are now selected via navigation columns)
- Keep `PipelineStatusView` at top as the phase selector (it's already clickable)
- Below that: `PhaseInputView` + phase output views (same as current detail pane)
- Add a "Run All" button in the toolbar or in the pipeline status area
- If no PR selected, show `ContentUnavailableView("Select a Pull Request")`

**Remove from current ContentView**:
- `globalInputBar` (config picker + PR number text field) — replaced by columns 1 and 2
- The phase sidebar (column 1 of current NavigationSplitView) — replaced by `PipelineStatusView` as phase selector

Files to modify:
- `Sources/apps/MacApp/UI/ContentView.swift`

**Technical notes:**
- Config sidebar uses a custom `Binding<RepoConfiguration?>` that calls `model.selectConfiguration(_:)` on set, which triggers PR list refresh
- PR row displays inline: number badge (capsule), state color indicator (green/purple/red/gray circle), title (2-line limit), branch name (monospaced), and author name
- `globalInputBar` fully removed — config selection is column 1, PR selection is column 2, "Run All" moved to detail toolbar
- Old phase sidebar (list of 6 pipeline phases) removed — `PipelineStatusView` horizontal bar serves as the phase selector in the detail column
- `PipelineStatusView` moved from bottom of the old layout to top of the detail column (above `PhaseInputView`)
- Gear/settings toolbar button moved to column 1 sidebar toolbar

## - [x] Phase 4: PR list row view

Create a dedicated view for PR list rows in column 2.

**`PRListRow` view**:
- PR number in a rounded badge (e.g., `#1234`)
- PR title as primary text (bold, 2-line limit)
- Branch name in monospaced caption font
- Author name
- State indicator: green circle for OPEN, purple for MERGED, red for CLOSED
- Subtle timestamp (relative, e.g. "2 days ago")

**For PRs without `gh-pr.json`** (fallback):
- Show just "PR #\(number)" as title
- Gray state indicator
- No author/branch info

Files to create:
- `Sources/apps/MacApp/UI/PRListRow.swift`

**Technical notes:**
- Extracted inline `prRow(_:)` and `stateIndicator(_:)` methods from `ContentView` into a standalone `PRListRow` view
- Relative timestamp uses `ISO8601DateFormatter` (with fractional seconds fallback) to parse `createdAt`, then `RelativeDateTimeFormatter` with `.abbreviated` style
- Fallback PRs detected by checking empty `author.login`, `headRefName`, and `state` — title rendered without bold weight
- Removed unused `PRRadarModels` import from `ContentView` since `PRMetadata` is no longer directly referenced there
- Includes SwiftUI `#Preview` blocks for both normal and fallback PR rows

## - [x] Phase 5: Auto-load existing phase outputs on PR selection

When a PR is selected from the list, immediately load any existing phase outputs from disk rather than requiring the user to re-run phases.

**Implementation in `PRReviewModel`**:
- Add `func loadExistingOutputs()` that checks each phase directory for the selected PR
- For phase 1: try to parse `diff-parsed.md`, `effective-diff-parsed.md`, `effective-diff-moves.json` → populate `fullDiff`, `effectiveDiff`, `moveReport`
- For phases 2-4: try to parse focus areas, rules, tasks → populate `rulesOutput`
- For phase 5: try to parse evaluations + summary → populate `evaluationOutput`
- For phase 6: try to parse report + markdown → populate `reportOutput`
- Set `phaseStates` to `.completed` for phases that have existing outputs
- Call this from the `selectedPR` setter after `resetAllPhases()`

This reuses the existing `PhaseOutputParser` and `parseDiffOutputs()` logic. The key insight is that the Python CLI writes files to disk, so any previously-run review already has its outputs available.

Files to modify:
- `Sources/apps/MacApp/Models/PRReviewModel.swift`

**Technical notes:**
- `loadExistingOutputs()` is called from `selectedPR`'s `didSet` after `resetAllPhases()`, so phases are cleared first then re-populated from disk
- Each phase is parsed independently with `try?` — if one phase's files are missing or corrupt, later phases can still load
- Phase 1 reuses the existing `parseDiffOutputs(config:)` method; phases 2-6 use new private helpers (`parseRulesOutputs`, `parseEvaluationOutputs`, `parseReportOutputs`)
- Added `public init` to `RulesPhaseOutput`, `EvaluationPhaseOutput`, and `ReportPhaseOutput` — their memberwise initializers were `internal` by default, preventing construction from the App layer
- Rules phase requires at least focus areas or rules to be present to count as completed (empty results are treated as no output)

## - [x] Phase 6: Wire up new PR creation flow

Since the PR number text field is removed from the main UI, add a way to initiate a review for a new PR.

**Approach**: Add a toolbar button or menu item in column 2 that presents a small popover/sheet:
- Text field for PR number
- "Start Review" button
- This creates the output directory, runs the diff phase, and adds the PR to `discoveredPRs`

Alternatively, add a text field at the top of the PR list (similar to a search field) where users can type a PR number and press Enter to start a new review.

Files to modify:
- `Sources/apps/MacApp/UI/ContentView.swift`
- `Sources/apps/MacApp/Models/PRReviewModel.swift`

**Technical notes:**
- "+" toolbar button in column 2 opens a popover with a PR number text field and "Start Review" button
- Popover supports Enter key submission via `.onSubmit` and `.keyboardShortcut(.defaultAction)`
- `PRReviewModel.startNewReview(prNumber:)` creates a fallback `PRMetadata`, inserts it into `discoveredPRs`, selects it, runs the diff phase, then refreshes the PR list to pick up the real `gh-pr.json` metadata
- If the PR already exists in `discoveredPRs`, it is selected without creating a duplicate
- Button is disabled when no configuration is selected

## - [x] Phase 7: Update window sizing and cleanup

**Window sizing**:
- Update `defaultSize` in `main.swift` to accommodate 3 columns (e.g., `width: 1200, height: 750`)
- Ensure minimum window size works well with all 3 columns visible

**Cleanup**:
- Remove the config picker dropdown code from `ContentView` (now in sidebar)
- Remove `prNumber` UserDefaults persistence (now driven by selection)
- Keep `selectedConfigID` UserDefaults for restoring last-selected config on launch
- Add UserDefaults persistence for `selectedPR` number to restore on launch
- Verify `SettingsView` sheet still works correctly from the new toolbar location

Files to modify:
- `Sources/apps/MacApp/main.swift`
- `Sources/apps/MacApp/UI/ContentView.swift`
- `Sources/apps/MacApp/Models/PRReviewModel.swift`

**Technical notes:**
- Window `defaultSize` updated from 1000×700 to 1200×750 to accommodate the third column
- `prNumber` simplified from a writable computed property (with `manualPRNumber` backing) to a read-only computed property — the setter was only needed for the old text field binding which was removed in Phase 3
- `selectedPR` number persisted to UserDefaults key `"selectedPRNumber"` via `didSet`
- New `restoreSelections()` method called from `init` — refreshes the PR list for the saved config, then restores the saved PR selection if it exists in the discovered PRs
- `SettingsView` sheet verified working correctly from the gear button in the config sidebar toolbar — no changes needed
- Config picker dropdown and `prNumber` UserDefaults were already removed in earlier phases (Phases 2-3)

## - [ ] Phase 8: Architecture Validation

Review all commits made during the preceding phases and validate they follow the project's architectural conventions.

**For Swift changes** (`pr-radar-mac/`):
- Fetch and read each skill from `https://github.com/gestrich/swift-app-architecture` (skills directory)
- Compare the commits made against the conventions described in each relevant skill
- If any code violates the conventions, make corrections

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. For each relevant language, fetch and read ALL skills from the corresponding GitHub repo
4. Evaluate the changes against each skill's conventions
5. Fix any violations found

## - [ ] Phase 9: Validation

**Build verification**:
- `cd pr-radar-mac && swift build` must succeed with no errors

**Manual verification checklist**:
- 3-column layout renders correctly with proper column widths
- Selecting a config in column 1 populates the PR list in column 2
- PR list shows correct metadata (title, number, author, state) from `gh-pr.json`
- PRs without `gh-pr.json` show fallback display
- Selecting a PR loads existing phase outputs immediately
- Phase selection via `PipelineStatusView` works
- Running individual phases and "Run All" works for the selected PR
- Settings sheet opens and config changes reflect in column 1
- New PR creation flow works
- Window resizing and column collapse behavior is reasonable
