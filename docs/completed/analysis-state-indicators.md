# Analysis State Indicators - Planning Doc

## Current Problem

The PR list rows show confusing status indicators:

1. **Green circle** - Shows PR is OPEN (GitHub state), not analysis status
2. Remove green checkmark - Instead use Open/Draft/Merged/Closed
3. Focus area part too slow.
   1. When analyzing by file, no AI should be needed.

4. When teh rules phase results in no tasks, the "Evaluate" phase fails with error "No tasks found. Run rules phase first"
   1. It seems if no tasks generate, that stops the pipeline as no files are written (expectes tasks to be written to suggest phase complete)
   2. We may need another way to indicate phse complete. Maybe a json file with a simple compltion timestapm and success indicator (Bool). That file can represnt we finished the task phase.
   3. Then the Evaluet phase would be a pass and simlarly consider something to indicate complete even though no evaluation done.
   4. A report shoudl still generate in tehse cases.
Add search filter for PR states: MERGED, CLOSED, OPEN, DRAFT




1. **Analysis badge** - Only appears when `summary.json` exists (analysis complete)
   - Green checkmark = 0 violations found
   - Orange badge with count = violations found
   - Nothing shown = no analysis or loading

### Issues Identified

- Not clear what the green circle means (users think it's analysis status)
- When clicking a PR with no analysis, diff doesn't show until "Run" is clicked
- No visual indicator when analysis is in progress
- No distinction between:
  - Not started (no analysis run yet)
  - In progress (phases running)
  - Partial (some phases complete, not all)
  - Complete with violations
  - Complete without violations
  - Failed with error

## Current State Model

```swift
enum AnalysisState {
    case loading
    case loaded(violationCount: Int, evaluatedAt: String)
    case unavailable
}
```

Currently loads from `summary.json` in phase-5-evaluations directory.

## Proposed Changes

### 1. Enhanced AnalysisState

```swift
enum AnalysisState {
    case notStarted
    case inProgress(lastPhase: PRRadarPhase)
    case completed(violationCount: Int, evaluatedAt: String)
    case failed(error: String, lastCompletedPhase: PRRadarPhase?)
}
```

### 2. Visual Indicators

#### PR State Circle (keep as-is)
- Green = OPEN
- Purple = MERGED
- Red = CLOSED
- Gray = unknown

Add tooltip: "PR Status: Open/Merged/Closed"

#### Analysis Badge (new design)

**Not Started:**
- Icon: `circle.dashed` or no badge
- Color: gray/secondary
- Tooltip: "No analysis run"

**In Progress:**
- Icon: `arrow.triangle.2.circlepath` (animated?)
- Color: blue
- Tooltip: "Analysis in progress (at {phase})"

**Partial/Failed:**
- Icon: `exclamationmark.triangle.fill`
- Color: yellow
- Tooltip: "Analysis incomplete or failed"

**Complete - Clean:**
- Icon: `checkmark.circle.fill`
- Color: green
- Tooltip: "Analysis complete - no violations"

**Complete - Violations:**
- Badge with count
- Color: orange/red
- Tooltip: "{count} violation(s) found"

### 3. Detection Logic

Check phase completion using `DataPathsService.allPhaseStatuses()`:
- If no phases exist → `notStarted`
- If report complete → `completed`
- If any phase running (from phaseStates) → `inProgress`
- If evaluations failed → `failed`
- If phases exist but report incomplete → depends on implementation choice

### 4. Implementation Notes

- `loadAnalysisSummary()` should check all phase statuses, not just summary.json
- Need to determine if we show "in progress" for partial runs or just "not started"
- Consider whether to auto-load detail view when clicking PR with no analysis

## Questions to Answer

1. Should partially complete analysis show as "in progress" or have its own state?
2. When should we show the "Run" button vs auto-loading available data?
3. Should the badge show phase progress (e.g., "3/6 phases")?
4. Do we need to distinguish between "analysis never run" vs "analysis outdated"?
5. Should we use colors or just icons for accessibility?

## Implementation Tasks

- [ ] Update `AnalysisState` enum
- [ ] Rewrite `loadAnalysisSummary()` to check all phase statuses
- [ ] Update `PRListRow.analysisBadge` with new indicators
- [ ] Add tooltips for both state circle and analysis badge
- [ ] Handle state transitions when phases are running
- [ ] Test with PRs in different states
