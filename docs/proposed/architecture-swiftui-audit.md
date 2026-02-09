## Background

An audit of the MacApp layer against the project's architectural conventions (`swift-architecture` and `swift-swiftui` skills from [swift-app-architecture](https://github.com/gestrich/swift-app-architecture)). The goal is to identify and fix violations of the established patterns — enum-based state, model composition, dependency injection, code style, and layer responsibilities.

The three primary files audited:
- `PRRadarLibrary/Sources/apps/MacApp/Models/PRModel.swift`
- `PRRadarLibrary/Sources/apps/MacApp/Models/AllPRsModel.swift`
- `PRRadarLibrary/Sources/apps/MacApp/UI/ContentView.swift`

Supporting files: `PRRadar/PRRadarApp.swift`, `ReviewDetailView.swift`

## Phases

## - [x] Phase 1: Root model ownership — move from ContentView to App struct

**Violation**: `model-composition.md` and `dependency-injection.md` say "Store root models in the `App` struct to avoid re-initialization on view rebuilds." Currently `ContentView` owns all root state (`@State private var allPRs: AllPRsModel?`, settings, selected config/PR) and creates `AllPRsModel` in `createModelForConfig()`.

**Changes:**

1. **Create `AppModel`** (`Models/AppModel.swift`) — a root `@Observable @MainActor` model that owns:
   - `settings: AppSettings`
   - `settingsService: SettingsService`
   - `selectedConfig: RepoConfiguration?` (with `didSet` creating/destroying `AllPRsModel`)
   - `allPRsModel: AllPRsModel?` (optional child model per `model-composition.md`)
   - `selectedPR: PRModel?`
   - Config management methods (add/remove/update/setDefault)
   - `bridgeScriptPath: String`

2. **Update `PRRadarApp`** — create `AppModel` as `@State` and inject via `.environment()`:
   ```swift
   @State private var appModel: AppModel
   var body: some Scene {
       WindowGroup {
           ContentView()
               .environment(appModel)
       }
   }
   ```

3. **Update `ContentView`** — replace `@State` properties with `@Environment(AppModel.self)`. View-only state (`showSettings`, `showNewReview`, popovers, `@AppStorage`) stays on the view. Model state (selected config, selected PR, allPRs) moves to `AppModel`.

**References**: `dependency-injection.md` (Environment injection), `model-composition.md` (optional child models, parent/child composition)

**Technical notes:**
- `AppModel` is `public` so the Xcode app target (which imports `MacApp`) can reference it
- `AppModel.init(bridgeScriptPath:)` creates `SettingsService` internally, keeping it out of the app target
- `selectedConfig` didSet creates/destroys `AllPRsModel` and clears `selectedPR`
- Config management methods (`addConfiguration`, `removeConfiguration`, `updateConfiguration`, `setDefault`) were duplicated from `AllPRsModel` to `AppModel` since they operate on `AppModel.settings` now; `AllPRsModel` still has them for backward compatibility until Phase 4 cleanup
- `SettingsView` takes `AppModel` directly instead of `@Binding var settings`, eliminating the need to sync settings back
- `ContentView` uses convenience computed properties (`allPRs`, `selectedConfig`, `selectedPR`) that delegate to `appModel`, minimizing diff churn
- The `.onChange(of: selectedConfig)` handler no longer calls `createModelForConfig()` since `AppModel.selectedConfig.didSet` handles model creation

## - [x] Phase 2: Enum-based state — replace `isAnalyzing: Bool` on PRModel

**Violation**: `model-state.md` says "Use enums to represent model state rather than multiple independent properties." `PRModel.isAnalyzing` (line 44) is a standalone `Bool` that tracks whether `runAnalysis()` is in progress, independent of `phaseStates`.

**Changes:**

1. **Add an `OperationMode` enum** to PRModel:
   ```swift
   enum OperationMode {
       case idle
       case refreshing
       case analyzing
   }
   ```

2. **Replace `isAnalyzing: Bool`** with `private(set) var operationMode: OperationMode = .idle`

3. **Update `runAnalysis()`** — set `operationMode = .analyzing` / `.idle`

4. **Update `refreshPRData()`** — set `operationMode = .refreshing` / `.idle`

5. **Update ContentView toolbar** — use `operationMode` instead of `isAnalyzing` and the `isPullRequestPhaseRunning && !isAnalyzing` compound check. The refresh button spinner becomes `pr.operationMode == .refreshing`, analyze button spinner becomes `pr.operationMode == .analyzing`.

6. **Remove `isPullRequestPhaseRunning`** computed property — no longer needed since `operationMode` captures intent directly.

**References**: `model-state.md` (enum-based state, impossible invalid states)

**Technical notes:**
- `OperationMode` is a nested enum on `PRModel` with three cases: `.idle`, `.refreshing`, `.analyzing`
- `refreshPRData()` wraps its body with `operationMode = .refreshing` / `.idle` via `defer`
- `runAnalysis()` wraps its body with `operationMode = .analyzing` / `.idle` via `defer`
- The compound toolbar check `pr.isPullRequestPhaseRunning && !pr.isAnalyzing` is replaced by the single check `pr.operationMode == .refreshing`, eliminating the possibility of conflicting boolean states
- `isPullRequestPhaseRunning` removed — `operationMode` captures the same intent more precisely

## - [x] Phase 3: Eliminate duplicated state extraction — expose filtered PRs from model

**Violation**: `model-composition.md` says "Parent models must not duplicate child state — access through the child model reference."

Currently `ContentView` has its own `currentPRModels` computed property (line 408) that reaches into `AllPRsModel.state` to extract `[PRModel]`, duplicating the same logic already in `AllPRsModel.currentPRModels` (line 230, private). Then `filteredPRModels` calls `allPRs?.filteredPRs(currentPRModels, ...)` passing the extracted models back.

**Changes:**

1. **Make `AllPRsModel.currentPRModels` public** (or internal) — remove the duplicate in ContentView.

2. **Add a computed `filteredPRModels` to AllPRsModel** that uses its own `currentPRModels`, `sinceDate`, and `selectedPRStateFilter`:
   ```swift
   var filteredPRModels: [PRModel] {
       guard let models = currentPRModels else { return [] }
       return filteredPRs(models, since: sinceDate, state: prStateFilter)
   }
   ```
   This requires the model to know the current filter values. Move `sinceDate` computation (from `daysLookBack`) and `selectedPRStateFilter` into AllPRsModel (or AppModel, depending on Phase 1 outcome).

3. **Simplify ContentView** — replace `filteredPRModels` and `currentPRModels` computed properties with direct access to the model's computed properties.

4. **Update `filteredPRs()` signature** — make the `models` parameter optional with a default of `currentPRModels`, so callers don't need to extract state themselves.

**References**: `model-composition.md` (single source of truth), `model-state.md` (state ownership)

**Technical notes:**
- `AllPRsModel.currentPRModels` changed from `private` to `internal` so `ContentView` can access it directly
- Added `filteredPRModels(since:state:)` method on `AllPRsModel` that internally calls `currentPRModels` and delegates to existing `filteredPRs(_:since:state:)` — this keeps the model as the single source of truth for state extraction
- `ContentView.currentPRModels` simplified to a one-line delegation: `allPRs?.currentPRModels ?? []`
- `ContentView.filteredPRModels` simplified to delegate to `allPRs?.filteredPRModels(since:state:) ?? []`
- Filter values (`sinceDate`, `selectedPRStateFilter`) remain on `ContentView` as `@AppStorage`-derived properties since they are view-level persistence concerns; the model accepts them as parameters rather than owning them
- The existing `filteredPRs(_:since:state:)` method is preserved for internal callers (e.g., `refresh(since:state:)`) that already have an explicit model array

## - [x] Phase 4: Remove dead code and fix misused state

**Violations found during audit:**

1. **`selectedPhase` on PRModel is dead code** — declared at line 28 (`var selectedPhase: PRRadarPhase = .pullRequest`), written to by `ReviewDetailView` (line 45) but never read anywhere. This is view-specific navigation state that doesn't belong on the model.
   - **Fix**: Remove `selectedPhase` from PRModel. If ReviewDetailView needs to persist phase selection across view rebuilds, use `@SceneStorage` or keep it as local `@State` (which it already has as `selectedNavPhase`).

2. **`runComments()` overwrites evaluations phase state** — line 375 sets `phaseStates[.evaluations] = .running(logs: "Posting comments...\n")` but comments are not evaluations. This means posting comments destroys the evaluations phase state.
   - **Fix**: Comments should not hijack the evaluations phase. Either add a dedicated phase state or track comment posting state separately (perhaps as part of the `OperationMode` from Phase 2, or a separate enum).

3. **Default parameter in `AllPRsModel.init`** — `settingsService: SettingsService = SettingsService()` violates `code-style.md` ("Avoid default and fallback values", "Prefer requiring data explicitly").
   - **Fix**: Remove the default value. All callers should pass the service explicitly.

**References**: `code-style.md` (no default parameter values), `model-state.md` (enum-based state)

**Technical notes:**
- `selectedPhase` removed from `PRModel`; the `.onChange(of: selectedNavPhase)` handler in `ReviewDetailView` that wrote to it was also removed since `selectedNavPhase` (a `@State` on the view) already drives navigation correctly
- `runComments()` now uses a dedicated `commentPostingState: CommentPostingState` property instead of hijacking `phaseStates[.evaluations]`, with a new `CommentPostingState` enum (`.idle`, `.running`, `.completed`, `.failed`) mirroring the subset of `PhaseState` cases needed for comment posting
- Private helpers `commentPostingLogs` and `appendCommentLog(_:)` added to manage log accumulation for the comment posting state, paralleling the existing `runningLogs(for:)` and `appendLog(_:to:)` pattern
- Default value removed from `AllPRsModel.init(config:repoConfig:settingsService:)` — the only caller (`AppModel.selectedConfig.didSet`) already passes `settingsService` explicitly

## - [x] Phase 5: Architecture Validation

Review all commits made during the preceding phases and validate they follow the project's architectural conventions:

- Re-read the `swift-architecture` and `swift-swiftui` skills from `https://github.com/gestrich/swift-app-architecture` (`plugin/skills/`)
- Compare the commits made against the conventions described in each skill
- If any code violates the conventions, make corrections

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. Evaluate the changes against each skill's conventions
4. Fix any violations found

**Technical notes:**

Three violations found and corrected:

1. **`selectedConfig` and `selectedPR` stored on `AppModel` violated `view-state.md`** — The convention states "Selection belongs in the view" and "The view owns the selection and tells the model to load data via `.onChange`." Moved both properties back to `ContentView` as `@State`, with `.onChange(of: selectedConfig)` calling `appModel.selectConfig(_:)` to create/destroy the child `AllPRsModel`. This eliminated the need for `@Bindable` workarounds in `configSidebar` and `prListView`.

2. **Dead configuration management methods on `AllPRsModel`** — Phase 1 moved config management to `AppModel` but left duplicate methods (`addConfiguration`, `removeConfiguration`, `updateConfiguration`, `setDefault`, `persistSettings`) on `AllPRsModel` for backward compatibility. Phase 4 was supposed to clean these up but didn't. Removed all five methods along with the now-unused `settingsService` and `settings` properties from `AllPRsModel.init`.

3. **Extra blank lines in `PRModel.swift`** — Two consecutive blank lines at line 83-84 (left over from removing `isPullRequestPhaseRunning`) reduced to one.

## - [ ] Phase 6: Validation

- `swift build` succeeds in `pr-radar-mac/`
- `swift test` passes in `pr-radar-mac/`
- Manual verification:
  - Refresh button shows spinner only during refresh, not during analysis
  - Analyze button shows spinner only during analysis, not during refresh
  - PR list filtering works correctly
  - Config switching works (model recreated properly)
  - Selected PR persists across sessions via AppStorage
