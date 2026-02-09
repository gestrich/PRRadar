# Single Diff View with Inline Analysis

## Background

Currently the PR diff is shown in two separate tabs:

- **Diff tab** (`DiffPhaseView`) — Shows the raw diff using `RichDiffContentView` with no analysis annotations
- **Evaluate tab** (`EvaluationsPhaseView`) — Shows the same diff again using `AnnotatedDiffContentView` with inline violation comments overlaid

This means the diff is duplicated across two views, and users must switch tabs to see analysis results in context. The goal is to combine these into a **single Diff tab** that starts as a plain diff and progressively decorates with inline analysis annotations once evaluation completes. The separate Evaluate tab is removed.

The rules view stays as-is. The report view stays as-is.

Key behavior:
- Before evaluation runs, the diff tab shows the plain diff (as it does today)
- After evaluation completes, the same diff tab shows inline violation comments, severity badges in the file sidebar, and per-file violation counts — all the functionality currently in `EvaluationsPhaseView`
- The evaluation summary bar (evaluated count, violations, cost) appears at the top of the diff view when evaluation data is available
- Pending comment submission (the "Submit" button on each inline comment) continues to work

## Phases

## - [x] Phase 1: Merge Diff and Evaluation Views into a Single Diff View

Replace `DiffPhaseView` with a new implementation that conditionally renders annotations when evaluation data is present.

### Tasks

1. **Update `DiffPhaseView`** to accept optional evaluation data:
   - Add optional parameters: `comments: [PRComment]?`, `evaluationSummary: EvaluationSummary?`, `prModel: PRModel?`, `postedReviewComments: [GitHubReviewComment]`, `postedGeneralComments: [GitHubComment]`
   - When evaluation data is present, show the `PhaseSummaryBar` with evaluation metrics (evaluated count, violations, cost) in addition to the existing diff metrics (files, hunks)
   - When evaluation data is present, use `AnnotatedDiffContentView` instead of `RichDiffContentView` for rendering the diff content
   - When evaluation data is present, show severity-colored violation badges in the file sidebar (migrating logic from `EvaluationsPhaseView`)

2. **Migrate file sidebar logic** from `EvaluationsPhaseView`:
   - The violation count badges with severity coloring (red/orange/yellow)
   - The "Files Not in Diff" section for comments referencing files outside the diff
   - The `commentMapping`, `filesWithViolationCounts`, `maxSeverity`, and `violationBadge` helper methods

3. **Keep the Full/Effective Diff picker** — it continues to toggle between the two diffs as it does today

### Files to modify
- `Sources/apps/MacApp/UI/PhaseViews/DiffPhaseView.swift` — Major rewrite to add conditional annotation rendering

### Architecture notes
- Per the SwiftUI Model-View architecture, `DiffPhaseView` remains a pure `View` struct with no `@Observable` — all data flows in from `ReviewDetailView` via parameters
- The view conditionally switches between `RichDiffContentView` (no analysis) and `AnnotatedDiffContentView` (with analysis) based on whether evaluation data is non-nil

### Completion notes
- `summaryItems(for:)` extracted as a non-`@ViewBuilder` helper to avoid mutating local variables inside a `@ViewBuilder` context (Swift compiler limitation)
- `hasEvaluationData` computed property gates both the file sidebar style and diff content rendering
- Existing call sites in `ReviewDetailView` continue to work without changes since new parameters all have defaults
- `EvaluationsPhaseView` is untouched — will be removed in Phase 4 after its callers are rewired in Phase 2

## - [x] Phase 2: Remove the Evaluate Navigation Tab

Remove the "Evaluate" tab from the pipeline navigation since its content is now integrated into the Diff tab.

### Tasks

1. **Update `NavigationPhase`** in `PipelineStatusView.swift`:
   - Remove the `.evaluate` case from the enum
   - Update `displayName`, `primaryPhase`, and `representedPhases` accordingly
   - The evaluation phase status indicator should move to the diff node (since the diff tab now owns evaluation display). Update `representedPhases` for `.diff` to include both `[.pullRequest]` and `[.evaluations]`, so the diff node shows the combined status

2. **Update `ReviewDetailView`**:
   - Remove the `.evaluate` case from the `phaseOutputView` switch
   - Update the `.diff` case (`diffOutputView`) to pass evaluation data into the new `DiffPhaseView`
   - Pass `prModel.evaluation?.comments`, `prModel.evaluation?.summary`, `prModel`, `prModel.postedComments?.reviewComments`, and posted general comments
   - Remove the `evaluationsOutputView` computed property

3. **Update `PhaseInputView`** (if it has evaluate-specific logic):
   - Ensure the run button for the diff tab can also trigger evaluation runs, or confirm that "Run All" from the toolbar still handles this

### Files to modify
- `Sources/apps/MacApp/UI/PipelineStatusView.swift` — Remove `.evaluate` case, merge phase tracking
- `Sources/apps/MacApp/UI/ReviewDetailView.swift` — Remove evaluate output view, pass data to diff view
- `Sources/apps/MacApp/UI/PhaseInputView.swift` — Audit for evaluate-specific input handling

### Architecture notes
- The pipeline status bar should still show the evaluation phase status. Since the diff tab now represents both diff and evaluate phases, the diff node's combined state should reflect both `[.pullRequest, .evaluations]`. If diff is complete but evaluation is running, the node should show the running indicator.

### Completion notes
- `NavigationPhase.evaluate` removed; `.diff` now has `representedPhases: [.pullRequest, .evaluations]` so the diff node reflects combined status
- `ReviewDetailView.evaluationsOutputView` removed; `diffOutputView` now passes all evaluation data (`comments`, `evaluationSummary`, `prModel`, `postedReviewComments`, `postedGeneralComments`) to `DiffPhaseView`
- `PhaseInputView` needed no changes — it still receives `.pullRequest` as the primary phase for the diff tab; "Run All" continues to trigger all phases including evaluation. Phase 3 will address adding an explicit "Run Evaluate" button to the diff tab's input view
- All 231 tests pass, build succeeds

## - [x] Phase 3: Pipeline Status Handling for Combined Diff+Evaluate

Ensure the `PhaseInputView` and pipeline controls work correctly for the combined diff tab.

### Tasks

1. **Audit `PhaseInputView`**: Currently each tab has a "Run Phase" button. The diff tab should now support running both the diff phase and the evaluate phase:
   - When diff data is not available, show "Run Diff" as it does today
   - When diff is complete but evaluation hasn't run, show a "Run Evaluate" button (or integrate this into the existing phase input controls)
   - This may require updating `PhaseInputView` to accept multiple phases or adding a secondary action

2. **Verify "Run All"** still works: The toolbar "Run All" button runs all phases sequentially. Confirm it still works correctly with the tab changes.

3. **Verify phase state display**: The `PipelineStatusView` combined state logic must correctly reflect the merged diff+evaluate status for the diff node.

### Files to modify
- `Sources/apps/MacApp/UI/PhaseInputView.swift` — Add evaluate phase support to the diff tab
- `Sources/apps/MacApp/UI/PipelineStatusView.swift` — Verify combined state logic

### Completion notes
- Added `secondaryPhase: PRRadarPhase?` optional parameter to `PhaseInputView`. When provided, the view renders a second section below the primary phase with its own title, description, run button, and state display — separated by a divider
- Refactored `runButton`, `stateView`, `phaseTitle`, and `phaseDescription` from computed properties to parameterized methods (`for targetPhase:`) so they can render for either the primary or secondary phase
- `ReviewDetailView` passes `secondaryPhase: .evaluations` only for the `.diff` tab; other tabs pass `nil`
- `PipelineStatusView.combinedState` already correctly handles `[.pullRequest, .evaluations]` — no changes needed
- "Run All" (`prModel.runAllPhases()`) is model-level and unaffected by tab changes — verified still works
- All 231 tests pass, build succeeds

## - [x] Phase 4: Clean Up Removed Code

Remove `EvaluationsPhaseView` and any dead code left over from the merge.

### Tasks

1. **Delete `EvaluationsPhaseView.swift`** — All its functionality is now in `DiffPhaseView`
2. **Audit imports and references** — Ensure nothing else references `EvaluationsPhaseView`
3. **Remove any unused helper methods** that were only used by the evaluations view and have been migrated

### Files to modify
- `Sources/apps/MacApp/UI/PhaseViews/EvaluationsPhaseView.swift` — Delete
- Any files that import or reference `EvaluationsPhaseView`

### Completion notes
- `EvaluationsPhaseView.swift` deleted — no source code references remained outside the file itself (all call sites were removed in Phase 2)
- No unused helper methods found — all helpers (`commentMapping`, `filesWithViolationCounts`, `maxSeverity`, `violationBadge`, etc.) were already migrated to `DiffPhaseView` in Phase 1
- All 231 tests pass, build succeeds

## - [ ] Phase 5: Architecture Validation

Review all commits made during the preceding phases and validate they follow the project's architectural conventions.

**For Swift changes** (`pr-radar-mac/`):
- Re-read the `swift-architecture` and `swift-swiftui` skills from `https://github.com/gestrich/swift-app-architecture` (`plugin/skills/`)
- Compare the commits made against the conventions described in each skill
- If any code violates the conventions, make corrections

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. Validate:
   - `@Observable` is only in the Apps layer (PRModel, AllPRsModel)
   - Views are pure structs with no business logic
   - No upward dependency violations (views don't import features or services incorrectly)
   - Enum-based state patterns are followed
   - Data flows downward from models to views via parameters
4. Fix any violations found

## - [ ] Phase 6: Validation

### Build and test
```bash
cd pr-radar-mac
swift build
swift test
```

### Manual verification
1. Open MacApp and select a PR that has evaluation data — confirm the diff tab shows inline analysis annotations
2. Select a PR that has only diff data (no evaluation) — confirm the diff tab shows the plain diff without errors
3. Confirm the Full/Effective Diff picker still works
4. Confirm the "Evaluate" tab is no longer visible in the pipeline status bar
5. Confirm "Run All" still executes all phases including evaluation
6. Confirm the severity badges appear in the file sidebar when evaluation data exists
7. Confirm inline comment submission (the "Submit" button) still works from the diff tab
