# SwiftUI Architecture Refactor

## Background

The PRRadar Mac app's `PRReviewModel` and `ContentView` were evaluated against the project's SwiftUI architecture principles defined in [swift-app-architecture/swift-ui.md](https://github.com/gestrich/swift-app-architecture/blob/main/docs/architecture/swift-ui.md). The sidebar (`configSidebar`) follows principles well, but the layout (detail pane, model state, phase output views) has several violations:

1. **No enum-based model state** — `PRReviewModel` uses ~12 independent optional properties (`fullDiff?`, `effectiveDiff?`, `rulesOutput?`, etc.) instead of an enum, allowing invalid state combinations (e.g., `fullDiff != nil` while `selectedPR == nil`)
2. **Model contains use-case-level logic** — 4 private parse methods (`parseDiffOutputs`, `parseRulesOutputs`, `parseEvaluationOutputs`, `parseReportOutputs`) do file I/O and JSON decoding in the Apps layer
3. **State ownership violation** — Use cases should own state data, but the model duplicates parsing logic that already exists in use cases
4. **`didSet` side effects** — `selectedPR.didSet` triggers `resetAllPhases()` + `loadExistingOutputs()` instead of explicit state transitions
5. **Prerequisite data violations** — Views check for nil internally (e.g., `phaseDetailView` checks `model.selectedPR != nil`) instead of requiring non-optional data from parents
6. **Monolithic ContentView** — ~370 lines with phase output views as inline computed properties
7. **No `.id()` usage** — No view identity management when switching PRs, allowing stale `@State` to persist
8. **Data not bundled** — Diff phase produces 4 separate optionals (`diffFiles`, `fullDiff`, `effectiveDiff`, `moveReport`) instead of a single struct

The refactor introduces `ModelState` enum with `ConfigContext`/`ReviewState`, moves parsing into use cases as `public static` methods, extracts `ReviewDetailView` from `ContentView`, and applies `.id()` for view identity. Backward-compatible computed properties on the model ensure `PipelineStatusView`, `PhaseInputView`, `SettingsView`, and `CommentApprovalView` compile without changes.

## Phases

## - [ ] Phase 1: Use Case Foundation

Move parsing logic out of the model into use cases. Additive changes except for `FetchDiffUseCase` return type.

### 1.1 Add `DiffPhaseSnapshot` to FetchDiffUseCase

**File:** `pr-radar-mac/Sources/features/PRReviewFeature/usecases/FetchDiffUseCase.swift`

- Add `import PRRadarModels`
- Define `DiffPhaseSnapshot` struct bundling `files: [String]`, `fullDiff: GitDiff?`, `effectiveDiff: GitDiff?`, `moveReport: MoveReport?`
- Add `public static func parseOutput(config: PRRadarConfig, prNumber: String) -> DiffPhaseSnapshot` — consolidates the parsing logic currently in `PRReviewModel.parseDiffOutputs()` (reads `diff-parsed.md`, `effective-diff-parsed.md`, `effective-diff-moves.json` via `PhaseOutputParser`)
- Change `execute` return type from `PhaseProgress<[String]>` to `PhaseProgress<DiffPhaseSnapshot>`
- In the `.completed` branch: call `Self.parseOutput(config:prNumber:)` instead of returning raw file names

### 1.2 Make parse methods `public static` on remaining use cases

For each of these files, change `private func parseOutput(prNumber:)` to `public static func parseOutput(config: PRRadarConfig, prNumber: String) throws -> OutputType`. The method body is identical but uses the `config` parameter instead of `self.config`. Each `execute` method updates its call to `try Self.parseOutput(config: config, prNumber: prNumber)`.

- `pr-radar-mac/Sources/features/PRReviewFeature/usecases/FetchRulesUseCase.swift` → `RulesPhaseOutput`
- `pr-radar-mac/Sources/features/PRReviewFeature/usecases/EvaluateUseCase.swift` → `EvaluationPhaseOutput`
- `pr-radar-mac/Sources/features/PRReviewFeature/usecases/GenerateReportUseCase.swift` → `ReportPhaseOutput`

No changes to `PostCommentsUseCase` or `AnalyzeUseCase` (they don't parse files from disk).

### 1.3 Create `LoadExistingOutputsUseCase`

**New file:** `pr-radar-mac/Sources/features/PRReviewFeature/usecases/LoadExistingOutputsUseCase.swift`

- Define `PipelineSnapshot` struct bundling optional `diff: DiffPhaseSnapshot?`, `rules: RulesPhaseOutput?`, `evaluation: EvaluationPhaseOutput?`, `report: ReportPhaseOutput?`
- `execute(prNumber:)` calls each use case's static parse method independently (no dependency chain — loads whatever exists on disk, matching current model behavior where each phase is loaded independently)
- Replaces model's `loadExistingOutputs()`, `parseDiffOutputs()`, `parseRulesOutputs()`, `parseEvaluationOutputs()`, `parseReportOutputs()`

### 1.4 Update model's `runDiff()` for new return type

**File:** `pr-radar-mac/Sources/apps/MacApp/Models/PRReviewModel.swift`

- In `runDiff()`, the `.completed` case now receives `DiffPhaseSnapshot` instead of `[String]`
- Assign `diffFiles`, `fullDiff`, `effectiveDiff`, `moveReport` from the snapshot properties
- Remove the `parseDiffOutputs(config:)` call from this code path

**Validation:** `cd pr-radar-mac && swift build` succeeds.

## - [ ] Phase 2: Model Refactor — Enum-Based State

Rewrite `PRReviewModel` internals with a `ModelState` enum. Keep backward-compatible computed properties so existing views compile unchanged.

### 2.1 Define new types

```swift
struct ConfigContext {
    var config: RepoConfiguration
    var prs: [PRMetadata]
    var review: ReviewState?
}

struct ReviewState {
    var pr: PRMetadata
    var phaseStates: [PRRadarPhase: PRReviewModel.PhaseState]
    var diff: DiffPhaseSnapshot?
    var rules: RulesPhaseOutput?
    var evaluation: EvaluationPhaseOutput?
    var report: ReportPhaseOutput?
    var comments: CommentPhaseOutput?
    var selectedPhase: PRRadarPhase
    init(pr: PRMetadata) { ... }
}

enum ModelState {
    case noConfig
    case hasConfig(ConfigContext)
}
```

Phase outputs within `ReviewState` remain optional because the pipeline is progressive (you can have diff but not rules). The key improvement: `config` and `pr` are non-optional prerequisites embedded in the enum structure, making invalid combinations unrepresentable.

### 2.2 Replace property bag with `ModelState`

Remove the ~12 independent properties (`phaseStates`, `discoveredPRs`, `selectedPR` with `didSet`, `diffFiles`, `fullDiff`, `effectiveDiff`, `moveReport`, `rulesOutput`, `evaluationOutput`, `reportOutput`, `commentOutput`, `selectedPhase`, `selectedConfiguration`).

Replace with: `private(set) var state: ModelState = .noConfig`

### 2.3 Add mutation helpers

```swift
private func mutateConfigContext(_ transform: (inout ConfigContext) -> Void)
private func mutateReview(_ transform: (inout ReviewState) -> Void)
```

These enable clean mutations like `mutateReview { $0.diff = snapshot }` without verbose enum unpacking.

### 2.4 Add backward-compatible computed properties

Computed getters (and setters where needed) for: `selectedConfiguration`, `discoveredPRs`, `selectedPR` (get/set — setter calls `selectPR`), `selectedPhase` (get/set), `phaseStates`, `fullDiff`, `effectiveDiff`, `moveReport`, `diffFiles`, `rulesOutput`, `evaluationOutput`, `reportOutput`, `commentOutput`.

These allow `PipelineStatusView`, `PhaseInputView`, `SettingsView`, `CommentApprovalView` to compile without changes.

### 2.5 Replace `didSet` with explicit methods

- `selectPR(_ pr: PRMetadata?)` — creates `ReviewState`, calls `LoadExistingOutputsUseCase`, sets phase states from snapshot, persists to UserDefaults
- `selectConfiguration(_ config:)` — creates `ConfigContext` with discovered PRs
- `refreshPRList()` — uses `mutateConfigContext`
- `restoreSelections()` — calls the above methods

### 2.6 Rewrite phase runners with `mutateReview`

Each runner (`runDiff`, `runRules`, `runEvaluate`, `runReport`, `runComments`) replaces direct property writes with `mutateReview { $0.diff = snapshot }` etc. Rewrite `appendLog` helper using `mutateReview`.

### 2.7 Update remaining methods

- Config management (`addConfiguration`, `removeConfiguration`) — update `state` instead of `selectedConfiguration`; `removeConfiguration` transitions to `.noConfig` if no fallback
- Query methods (`stateFor`, `canRunPhase`, `isAnyPhaseRunning`, `resetPhase`, `readFileFromRepo`) — read from enum state
- `startNewReview` — works through `mutateConfigContext` and `selectPR`

### 2.8 Delete dead code

Remove: `parseDiffOutputs`, `parseRulesOutputs`, `parseEvaluationOutputs`, `parseReportOutputs`, `loadExistingOutputs`, `resetAllPhases`.

**Validation:** `cd pr-radar-mac && swift build` succeeds. All views compile via backward-compatible computed properties.

## - [ ] Phase 3: View Refactor — Extract ReviewDetailView

Extract phase detail views from `ContentView`, apply prerequisite data pattern, add `.id()`.

### 3.1 Create `ReviewDetailView`

**New file:** `pr-radar-mac/Sources/apps/MacApp/UI/ReviewDetailView.swift`

- Takes `let config: RepoConfiguration` and `let review: ReviewState` as non-optional parameters (prerequisite data pattern)
- Reads phase output data from `review` parameter (e.g., `review.diff?.fullDiff`, `review.rules`, `review.evaluation`)
- Contains: `PipelineStatusView`, `PhaseInputView`, phase output switching, toolbar Run All button
- Owns `@State showEffectiveDiff`, `@State showCommentApproval` (moved from ContentView)
- Moves `diffOutputView`, `rulesOutputView`, `evaluationsOutputView`, `reportOutputView`, `runningLogView` from ContentView into this view

### 3.2 Refactor `ContentView`

- Remove `showEffectiveDiff`, `showCommentApproval` `@State` (moved to ReviewDetailView)
- Remove all inline phase output computed properties
- Detail column switches on `model.state`:
  - `.noConfig` → "Select a Configuration" placeholder
  - `.hasConfig(let ctx)` where `ctx.review != nil` → `ReviewDetailView(config: ctx.config, review: review)` with `.id(review.pr.number)`
  - `.hasConfig` where `ctx.review == nil` → "Select a Pull Request" placeholder
- PR list column: switch on `model.state` to access `ctx.prs` directly instead of checking `selectedConfiguration == nil`
- ContentView shrinks from ~370 lines to ~150 lines

### 3.3 Add `.id()` for view identity

`.id(review.pr.number)` on `ReviewDetailView` forces SwiftUI to destroy and recreate the view when switching PRs, resetting all `@State` in the detail pane (scroll position, sheet visibility, etc.).

**Files unchanged:** `PipelineStatusView`, `PhaseInputView`, `SettingsView`, `CommentApprovalView`, `PRListRow`, all phase views (DiffPhaseView, RulesPhaseView, etc.), all service/SDK files, `main.swift`, `Package.swift`.

## - [ ] Phase 4: Architecture Validation

Review all commits made during phases 1-3 and validate they follow the project's architectural conventions.

**For Swift changes** (`pr-radar-mac/`):
- Fetch and read each skill from `https://github.com/gestrich/swift-app-architecture` (skills directory)
- Compare the commits made against the conventions described in each relevant skill
- If any code violates the conventions, make corrections

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. Fetch and read ALL skills from the swift-app-architecture GitHub repo
4. Evaluate the changes against each skill's conventions
5. Fix any violations found

## - [ ] Phase 5: Validation

1. `cd pr-radar-mac && swift build` — must succeed
2. `swift run MacApp` — verify the 3-pane layout works:
   - Select a configuration → PR list populates (column 2)
   - Select a PR → detail pane shows with existing data loaded
   - Switch PRs → `.id()` forces detail reset (no stale state from previous PR)
   - Deselect PR → placeholder shown
3. Phase execution:
   - Run individual phases → progress/completion updates correctly
   - Run All → phases execute sequentially
   - Phase state indicators update in PipelineStatusView
4. Settings:
   - Add/remove/edit configurations still works
   - Default configuration selection persists across restarts
   - PR selection persists across restarts
