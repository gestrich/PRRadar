# Refactor PR Models to MV Architecture

## Background

The current `PRReviewModel` and `ReviewModel` architecture violates MV principles by:

1. **Mixed responsibilities**: `PRReviewModel` manages both the PR list AND selected PR details
2. **Manual initialization**: `ReviewModel.loadExistingOutputs()` requires explicit calls from views
3. **Missing hierarchy**: No dedicated model per PR that owns its analysis status
4. **Lazy status loading**: Analysis status only loads when PR is selected, preventing badge display in list view

We need to refactor to a proper two-model architecture:

- **AllPRsModel**: Root observable model managing the collection of PRs, handles GitHub refresh
- **PRModel**: Child observable model representing a single PR, owns both lightweight analysis status (for badges) and heavy detail state (for full review)

This aligns with the swift-app-architecture principles:
- Self-initialization on `init`
- Enum-based state management
- Parent models hold child models
- Background loading for heavy state
- Clear ownership hierarchy

The refactor will enable showing violation count badges in the PR list by loading lightweight analysis summaries in the background.

## Phases

## - [x] Phase 1: Create PRModel with Lightweight Analysis State

Create the new `PRModel` class that represents a single PR with self-initializing analysis status.

**Tasks:**
- Create `Sources/apps/MacApp/Models/PRModel.swift`
- Implement `@Observable @MainActor final class PRModel: Identifiable`
- Add `metadata: PRMetadata` property
- Add `config: PRRadarConfig` property
- Define `AnalysisState` enum:
  - `.loading`
  - `.loaded(violationCount: Int, evaluatedAt: String)`
  - `.unavailable`
- Add `analysisState: AnalysisState = .loading` property
- Implement `init(metadata:config:)` that kicks off `Task { await loadAnalysisSummary() }`
- Implement `loadAnalysisSummary()` that:
  - Reads `{outputDir}/{prNumber}/phase-5-evaluations/summary.json`
  - Decodes `EvaluationSummary`
  - Sets `analysisState = .loaded(violationCount:evaluatedAt:)` if found
  - Sets `analysisState = .unavailable` if not found

**Files to create:**
- `Sources/apps/MacApp/Models/PRModel.swift`

**Expected outcome:**
- PRModel exists and self-loads lightweight analysis status on init
- Analysis state can be observed by views for badge display

**Technical notes:**
- `id` property requires `nonisolated` keyword for Swift 6.2 strict concurrency — `Identifiable` conformance on `@MainActor` classes needs nonisolated `id` since the protocol requirement is nonisolated
- Uses `PhaseOutputParser.parsePhaseOutput` to decode `EvaluationSummary` from `summary.json`, catching any error (file not found, decode failure) as `.unavailable`

## - [x] Phase 2: Add Detail State to PRModel

Add the heavy detail state loading to PRModel with on-demand initialization.

**Tasks:**
- Define `DetailState` enum in PRModel:
  - `.unloaded`
  - `.loading`
  - `.loaded(ReviewSnapshot)`
  - `.failed(String)`
- Create `ReviewSnapshot` struct to hold phase outputs:
  - `diff: DiffPhaseSnapshot?`
  - `rules: RulesPhaseOutput?`
  - `evaluation: EvaluationPhaseOutput?`
  - `report: ReportPhaseOutput?`
- Add `detailState: DetailState = .unloaded` property
- Implement `loadDetail() async` method that:
  - Guards against re-loading if already loaded
  - Sets `detailState = .loading`
  - Uses `LoadExistingOutputsUseCase` to load all phase outputs
  - Sets `detailState = .loaded(ReviewSnapshot(...))`
- Copy phase execution methods from `ReviewModel`:
  - `phaseStates: [PRRadarPhase: PhaseState]`
  - `PhaseState` enum definition
  - `runDiff()`, `runRules()`, `runEvaluate()`, `runReport()`
  - `submitSingleComment(_:)`
  - Helper methods for log management

**Files to modify:**
- `Sources/apps/MacApp/Models/PRModel.swift`

**Expected outcome:**
- PRModel can load full review details on-demand
- PRModel owns all phase execution logic
- Complete migration of ReviewModel functionality into PRModel

**Technical notes:**
- `ReviewSnapshot` includes a `comments: CommentPhaseOutput?` field in addition to the four spec'd fields, since ReviewModel tracked comment state too
- `init` now takes a third parameter `repoConfig: RepoConfiguration` (needed by `runRules()` for `rulesDir` and `submitSingleComment()` for `repoPath`/`repoSlug`)
- `loadDetail()` is synchronous — `LoadExistingOutputsUseCase.execute()` is a synchronous disk read, so no `async` needed
- All phase execution methods, comment submission, file access, and helper methods migrated verbatim from ReviewModel
- `selectedPhase` property added to PRModel so it can own phase tab selection (previously on ReviewModel)

## - [x] Phase 3: Create AllPRsModel

Create the parent model that manages the collection of PRModels.

**Tasks:**
- Create `Sources/apps/MacApp/Models/AllPRsModel.swift`
- Implement `@Observable @MainActor final class AllPRsModel`
- Define `State` enum:
  - `.uninitialized`
  - `.loading`
  - `.ready([PRModel])`
  - `.refreshing([PRModel])` - keeps showing prior PRs while fetching
  - `.failed(String, prior: [PRModel]?)`
- Add `state: State = .uninitialized` property
- Add `config: PRRadarConfig` property
- Add `repoConfig: RepoConfiguration` property (needed for rules directory, repo path)
- Implement `init(config:repoConfig:)` that kicks off `Task { await load() }`
- Implement `load() async` that:
  - Sets `state = .loading`
  - Calls `PRDiscoveryService.discoverPRs(outputDir:repoSlug:)`
  - Maps metadata to PRModels: `metadata.map { PRModel(metadata: $0, config: config) }`
  - Sets `state = .ready(prModels)`
- Implement `refresh() async` that:
  - Guards current state is `.ready` or `.failed`
  - Sets `state = .refreshing(prior)`
  - Uses `FetchPRListUseCase` to fetch from GitHub
  - Consumes progress stream
  - Calls `await load()` when complete
- Implement `analyzeAll(since:) async` that uses `AnalyzeAllUseCase`
- Migrate configuration management methods from PRReviewModel:
  - `addConfiguration(_:)`, `removeConfiguration(id:)`, `updateConfiguration(_:)`, `setDefault(id:)`

**Files to create:**
- `Sources/apps/MacApp/Models/AllPRsModel.swift`

**Expected outcome:**
- AllPRsModel manages collection of PRModels
- Self-initializes and loads PR list on creation
- Handles GitHub refresh and analyze-all operations

**Technical notes:**
- `init` takes a third parameter `settingsService: SettingsService` (defaults to `SettingsService()`) to keep configuration management co-located with the model
- `AnalyzeAllState` enum migrated from `PRReviewModel` with same cases (idle, running, completed, failed)
- `refresh()` re-discovers PRs from disk after fetch completes (rather than using the fetched metadata directly) to stay consistent with `load()`
- `analyzeAll()` calls `reloadFromDisk()` after completion to pick up newly-written phase outputs
- `currentPRModels` computed property extracts the PR list from any active state for use in `refresh()` transitions
- PRModel creation passes `repoConfig` as third parameter (needed for phase execution in Phase 2)

## - [x] Phase 4: Update Views to Use New Models

Update all views to consume AllPRsModel and PRModel instead of PRReviewModel and ReviewModel.

**Tasks:**
- Update `ContentView.swift`:
  - Change `@State private var prReviewModel` to `@State private var allPRs: AllPRsModel`
  - Update view body to switch on `allPRs.state`
  - Pass individual `PRModel` instances to detail views
- Update `PRListRow.swift`:
  - Accept `PRModel` instead of `PRMetadata`
  - Add badge display based on `prModel.analysisState`
  - Show violation count when `.loaded(count, _)` where count > 0
- Update `ReviewDetailView.swift`:
  - Accept `PRModel` instead of `ReviewModel`
  - Call `prModel.loadDetail()` on appear if needed
  - Switch on `prModel.detailState` to show loading/content/error
  - Update all phase views to read from `prModel.detailState.snapshot`
- Update phase views:
  - `DiffPhaseView.swift`: Read from `prModel.detailState`
  - `RulesPhaseView.swift`: Read from `prModel.detailState`
  - `EvaluationsPhaseView.swift`: Read from `prModel.detailState`
  - `ReportPhaseView.swift`: Read from `prModel.detailState`
- Update `PhaseInputView.swift` to call methods on `prModel`
- Update `SettingsView.swift` to work with `AllPRsModel` for configuration management

**Files to modify:**
- `Sources/apps/MacApp/UI/ContentView.swift`
- `Sources/apps/MacApp/UI/PRListRow.swift`
- `Sources/apps/MacApp/UI/ReviewDetailView.swift`
- `Sources/apps/MacApp/UI/PhaseViews/*.swift`
- `Sources/apps/MacApp/UI/PhaseInputView.swift`
- `Sources/apps/MacApp/UI/SettingsView.swift`

**Expected outcome:**
- All views updated to use new model structure
- PR list shows violation badges
- Detail view loads on-demand
- App compiles and runs with new architecture

**Technical notes:**
- `PRModel` gained `Hashable` conformance (with `nonisolated` `==` and `hash(into:)` based on `id`) to support `List(selection:)` binding with `@State private var selectedPR: PRModel?`
- Views switched from `@Environment(ReviewModel.self)` / `@Environment(PRReviewModel.self)` to explicit `prModel: PRModel` parameters — keeps data flow explicit rather than implicit environment
- `InlineCommentView` and `CommentApprovalView` now take `prModel` as an init parameter instead of reading from `@Environment`
- `AnnotatedHunkContentView`, `AnnotatedDiffContentView`, and `EvaluationsPhaseView` gained optional `prModel: PRModel?` parameter to thread through to `InlineCommentView` for comment submission
- `main.swift` updated to create `AllPRsModel` using `SettingsService` to load the default configuration, constructing `PRRadarConfig` and `RepoConfiguration` from settings
- `ContentView` selection is now `@State private var selectedPR: PRModel?` (was `PRMetadata?`); `loadDetail()` is called in `onChange(of: selectedPR)` for on-demand loading
- `SettingsView` compares selected config by `config.id == model.repoConfig.id` (was `model.selectedConfiguration?.id`)
- Old `PRReviewModel` and `ReviewModel` remain in the project (unused) — to be removed in Phase 6

## - [ ] Phase 5: Update App Entry Point

Update the main app entry point to initialize AllPRsModel instead of PRReviewModel.

**Tasks:**
- Update `Sources/apps/MacApp/main.swift`:
  - Create `AllPRsModel` instead of `PRReviewModel`
  - Pass to ContentView
  - Ensure proper initialization with config and repo config

**Files to modify:**
- `Sources/apps/MacApp/main.swift`

**Expected outcome:**
- App properly initializes with new model structure
- Self-initialization works on app launch

## - [ ] Phase 6: Remove Old Models

Delete the old PRReviewModel and ReviewModel files now that they're replaced.

**Tasks:**
- Delete `Sources/apps/MacApp/Models/PRReviewModel.swift`
- Delete `Sources/apps/MacApp/Models/ReviewModel.swift`
- Verify no remaining references to these classes
- Clean up any unused imports

**Files to delete:**
- `Sources/apps/MacApp/Models/PRReviewModel.swift`
- `Sources/apps/MacApp/Models/ReviewModel.swift`

**Expected outcome:**
- Old models removed
- Clean architecture with only new models
- No compilation errors

## - [ ] Phase 7: Architecture Validation

Review all commits made during the preceding phases and validate they follow the project's architectural conventions.

**For Swift changes** (`pr-radar-mac/`):
- Fetch and read each skill from `https://github.com/gestrich/swift-app-architecture` (skills directory)
- Compare the commits made against the conventions described in each relevant skill
- Pay special attention to:
  - MV pattern compliance (no ViewModels)
  - `@Observable` usage
  - Enum-based state management
  - Self-initialization patterns
  - Model hierarchy (parent holds child models)
  - Background loading patterns
- If any code violates the conventions, make corrections

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. Fetch and read ALL skills from the swift-app-architecture repo
4. Evaluate the changes against each skill's conventions
5. Fix any violations found

## - [ ] Phase 8: Validation

Test the refactored models to ensure functionality is preserved.

**Testing approach:**

1. **Build verification:**
   - Run `swift build` to ensure clean compilation
   - Verify no warnings or errors

2. **Manual UI testing:**
   - Launch the MacApp
   - Verify PR list displays correctly
   - Check that violation badges appear for analyzed PRs
   - Select a PR and verify detail view loads
   - Run each phase (diff, rules, evaluate, report) on a test PR
   - Verify comment submission still works
   - Test GitHub refresh functionality
   - Test analyze-all functionality
   - Test configuration management (add/remove/update configs)

3. **State management verification:**
   - Observe that analysis badges load asynchronously after list appears
   - Verify detail state loads on-demand when PR selected
   - Check that phase state updates trigger view refreshes
   - Confirm enum states prevent invalid states

**Success criteria:**
- App builds without errors
- All existing functionality works as before
- Violation badges now appear in PR list
- Self-initialization works correctly
- Background loading performs well
- No crashes or UI freezes
- State transitions are smooth and predictable
