## Background

The MacApp currently has four navigation tabs: Summary, Diff, Rules, and Report. The Rules tab shows focus areas, available rules, and evaluation tasks in a standalone view (`RulesPhaseView`). However, this information is most useful when viewed in the context of the files being reviewed. By merging task/rule information directly into the Diff view — showing which tasks ran on each file and their results — we can reduce tab-switching and provide contextual review data where it matters most.

The Diff view already has a two-column layout: a file list sidebar on the left and diff content on the right. Tasks are already associated with files via `EvaluationTaskOutput.focusArea.filePath`, making it natural to group and display tasks per file.

After this change, the standalone Rules navigation tab will be removed since all its information will be accessible from the Diff view.

## Phases

## - [x] Phase 1: Add per-file task detail section to the Diff view

When a file is selected in the diff view's sidebar, add a collapsible "Tasks" section between the summary bar and the diff content. This section shows all `EvaluationTaskOutput` entries whose `focusArea.filePath` matches the selected file.

**Files to modify:**
- [DiffPhaseView.swift](pr-radar-mac/Sources/apps/MacApp/UI/PhaseViews/DiffPhaseView.swift) — Main changes here

**Tasks:**
1. Accept `tasks: [EvaluationTaskOutput]` as a new parameter on `DiffPhaseView` (passed from `ReviewDetailView`)
2. Add a computed property that filters tasks for the currently selected file: `tasksForSelectedFile -> [EvaluationTaskOutput]`
3. When no file is selected, show a summary of all tasks grouped by file (or show nothing — keep it clean)
4. When a file is selected and tasks exist for it, render a collapsible section above the diff content area:
   - Section header: "Tasks ({count})" with a disclosure toggle
   - Each task row shows:
     - **Rule name** (headline) + **category badge** (capsule)
     - **Rule description** (secondary text)
     - **Focus area**: description, line range (`startLine-endLine`), focus type badge
     - Expandable: full rule content (monospaced, in a background box) + documentation link if present
5. Add a task count badge next to each file name in the sidebar (similar to the existing violation badge) — only shown when tasks data is available. Use a distinct style (e.g., blue capsule) to differentiate from violation badges.

**Architecture notes (swift-architecture):**
- `DiffPhaseView` is a View in the Apps layer — it can accept data from `@Observable` models
- No new models needed; the view receives tasks as a plain array parameter
- Business logic (filtering tasks by file) is a simple computed property, appropriate for the view layer since it's purely presentational filtering

**SwiftUI notes (swift-swiftui):**
- Use `DisclosureGroup` for the collapsible tasks section (consistent with existing patterns in `RulesPhaseView`)
- Use `@State private var showTasks = false` for the disclosure state
- Keep the section visually lightweight — collapsed by default so the diff content remains the primary focus

## - [x] Phase 2: Wire task data through from ReviewDetailView

Pass the tasks data from `PRModel.rules?.tasks` into `DiffPhaseView` through `ReviewDetailView`.

**Files to modify:**
- [ReviewDetailView.swift](pr-radar-mac/Sources/apps/MacApp/UI/ReviewDetailView.swift) — Pass tasks to `DiffPhaseView`

**Tasks:**
1. In `diffOutputView`, pass `prModel.rules?.tasks ?? []` to the new `tasks` parameter on `DiffPhaseView`
2. The diff view should gracefully handle an empty tasks array (no tasks section shown)

**Architecture notes:**
- `ReviewDetailView` already has access to `prModel` which holds both `diff` and `rules` data
- This is a simple wiring change — the model already loads both phase outputs in `loadDetail()`

## - [x] Phase 3: Remove the standalone Rules navigation tab

Since all rules/tasks information is now accessible from the Diff view, remove the Rules tab from the navigation.

**Files to modify:**
- [PipelineStatusView.swift](pr-radar-mac/Sources/apps/MacApp/UI/PipelineStatusView.swift) — Remove `.rules` from `NavigationPhase`
- [ReviewDetailView.swift](pr-radar-mac/Sources/apps/MacApp/UI/ReviewDetailView.swift) — Remove `.rules` case handling from `phaseOutputView`

**Tasks:**
1. Remove `.rules` from the `NavigationPhase` enum
2. Move the `.focusAreas`, `.rules`, `.tasks` phases into the `.diff` case's `representedPhases` so the Diff tab status indicator reflects all underlying phases
3. Remove `rulesOutputView` from `ReviewDetailView`
4. Update `PhaseInputView` usage for `.diff` to also include the rules secondary phase if needed
5. Keep `RulesPhaseView.swift` file for now (it can be deleted in a follow-up cleanup if desired, or retained as a reference)

**Architecture notes:**
- The `NavigationPhase` enum drives the tab bar — removing a case cleanly removes the tab
- Phase states for `.focusAreas`, `.rules`, `.tasks` should roll up into the `.diff` navigation phase so the status indicator still shows when those pipeline phases are running/completed/failed

**Completion notes:**
- Removed `.rules` case from `NavigationPhase` enum (3 tabs now: Summary, Diff, Report)
- Merged `.focusAreas`, `.rules`, `.tasks` into `.diff`'s `representedPhases` so the Diff tab status indicator reflects those pipeline phases
- Changed `PhaseInputView` secondary phase from `.evaluations` to `.rules` — the Diff tab now shows a "Rules & Tasks" run button alongside the diff fetch
- Removed `rulesOutputView` and its `.rules` case from `phaseOutputView` in `ReviewDetailView`
- `RulesPhaseView.swift` retained as planned

## - [x] Phase 4: Show "all files" task summary when no file is selected

When no file is selected in the sidebar, the tasks section should show a summary view of all tasks grouped by file — giving an overview before drilling into a specific file.

**Files to modify:**
- [DiffPhaseView.swift](pr-radar-mac/Sources/apps/MacApp/UI/PhaseViews/DiffPhaseView.swift)

**Tasks:**
1. When `selectedFile == nil` and tasks are non-empty, show a summary section above the diff content:
   - Group tasks by `focusArea.filePath`
   - Show each file with its task count
   - Tapping a file in this summary selects it in the sidebar (sets `selectedFile`)
2. This provides a quick overview of where review effort was concentrated

**Completion notes:**
- Added `tasksByFile` computed property that groups tasks by file path, sorted by task count descending (most tasks first)
- Added `allFilesTaskSummary()` view shown in `diffContent` when no file is selected and tasks exist
- Summary shows a "Tasks by File" header with a scrollable list of files, each displaying the filename and a blue task count badge
- Tapping a file row sets `selectedFile`, navigating to that file's diff and per-file task details
- Reuses the existing `taskBadge` helper for consistent styling

## - [x] Phase 5: Architecture Validation

Review all commits made during the preceding phases and validate they follow the project's architectural conventions.

**For Swift changes** (`pr-radar-mac/`):
- Re-read the `swift-architecture` and `swift-swiftui` skills from `https://github.com/gestrich/swift-app-architecture` (`plugin/skills/`)
- Compare the commits made against the conventions described in each skill
- If any code violates the conventions, make corrections

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. Fetch and read ALL skills from the `swift-app-architecture` repo
4. Evaluate the changes against each skill's conventions:
   - `@Observable` models only in Apps layer
   - Views receive data as parameters, no business logic in views
   - Dependency flow only downward (Apps → Features → Services → SDKs)
   - Enum-based state patterns
   - Proper use of `DisclosureGroup`, `@State`, and view composition
5. Fix any violations found

**Completion notes:**
- Reviewed all 13 skill files from `swift-app-architecture` (7 architecture + 6 SwiftUI)
- Evaluated 4 changed/new files across 3 commits (812a108, 69a839e, dc84c85)
- **No violations found.** All changes conform to conventions:
  - All modified/new files are Views in the Apps layer (`apps/MacApp/UI/`)
  - Dependencies flow downward only (imports: `PRRadarModels`, `PRRadarConfigService`, `PRReviewFeature`, `SwiftUI`)
  - No new `@Observable` models — views receive data as parameters
  - `@State` used correctly for local UI state (`showTasks`, `isExpanded`, `selectedFile`)
  - `DisclosureGroup` used consistently for collapsible sections
  - `TaskRowView` properly extracted as a separate view for composition
  - `NavigationPhase` enum cleanly updated (`.rules` removed, phases consolidated into `.diff`)
  - Import ordering alphabetical in all files
  - File organization follows Properties → init → computed → methods convention
- Build succeeds, all 265 tests pass

## - [ ] Phase 6: Validation

**Automated testing:**
```bash
cd pr-radar-mac
swift build
swift test
```

**Manual verification:**
1. Launch MacApp and select a PR that has completed the rules pipeline phase
2. Verify the Diff tab shows:
   - Task count badges on files in the sidebar
   - Collapsible tasks section when a file is selected
   - Rule info (name, category, description, content) and focus area details for each task
3. Verify the Rules tab is no longer visible in the navigation bar
4. Verify the Diff tab's status indicator reflects focus areas / rules / tasks phase states
5. Verify the "no file selected" state shows the all-files task summary
6. Verify that when no tasks data exists (rules phase hasn't been run), the diff view works exactly as before with no tasks section shown
