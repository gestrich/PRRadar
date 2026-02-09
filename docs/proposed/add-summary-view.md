## Background

PR-level comments (issue comments on a PR, not inline review comments) currently display in the Evaluations diff view, which is misleading since they have no file/line association. We need a dedicated **Summary** tab that appears before the Diff tab in the navigation pipeline. This view will show PR metadata (title, author, description) and PR-level comments in one place.

The PR description (`body`) is already available in the `GitHubPullRequest` model (from `gh-pr.json`) but is not currently exposed through `PRMetadata`. We need to thread it through.

### Architecture & SwiftUI Conventions Applied

From [swift-app-architecture](https://github.com/gestrich/swift-app-architecture):

- **Summary is a UI-only concern** — no new use cases or services needed; all data already exists in `PRModel`
- **`@Observable` stays in Apps layer** — `PRModel` already holds `metadata` and `postedComments`; the new view just reads these
- **Models span many views (MV, not MVVM)** — no new model needed; `SummaryPhaseView` reads directly from `PRModel` properties
- **No silent fallbacks** — if body is nil, show nothing rather than "No description"
- **File organization**: properties → init → computed → methods → nested types
- **Imports**: alphabetical order

From [swift-swiftui](https://github.com/gestrich/swift-app-architecture) guide:

- **No view-scoped model** needed — Summary view is stateless, just reads from `PRModel`
- **Parent/child: views access state through the model** — `SummaryPhaseView` receives `PRModel` directly

### Key Decision: NavigationPhase vs PipelinePhase

Summary is **not** a pipeline phase (no computation, no run button). It should be a `NavigationPhase` case that does NOT map to any `PRRadarPhase`. This avoids touching `PRRadarPhase` (which drives the analysis pipeline) and keeps the change scoped to the UI layer.

## Phases

## - [x] Phase 1: Add `body` to PRMetadata and thread it through

**Goal**: Make the PR description available in `PRModel.metadata.body`.

**Files to modify**:

1. `pr-radar-mac/Sources/services/PRRadarModels/PRMetadata.swift`
   - Add `public let body: String?` property
   - Add `body` parameter to `init` (with default `nil` to preserve existing call sites)
   - Add `body` to `fallback(number:)` as `nil`

2. `pr-radar-mac/Sources/services/PRRadarModels/GitHubModels.swift`
   - Update `toPRMetadata()` to pass `body: body`

3. `pr-radar-mac/Sources/services/PRRadarConfigService/PRDiscoveryService.swift`
   - Update the `PRMetadata(...)` construction (line 29-39) to include `body: ghPR.body`

## - [x] Phase 2: Add `summary` NavigationPhase and wire up the tab

**Goal**: Add a Summary tab before Diff in the pipeline navigation bar.

**Files to modify**:

1. `pr-radar-mac/Sources/apps/MacApp/UI/PipelineStatusView.swift`
   - Add `.summary` case to `NavigationPhase` (before `.diff`)
   - `displayName`: `"Summary"`
   - `primaryPhase`: This needs special handling since Summary doesn't map to a `PRRadarPhase`. Options:
     - Return `.pullRequest` (reuse; summary shares the same pipeline phase data)
   - `representedPhases`: return empty `[]` (no pipeline phases to track)
   - The `phaseNode` button sets `prModel.selectedPhase` — but `selectedPhase` is `PRRadarPhase`, which has no summary case. Instead, add a `selectedNavigationPhase: NavigationPhase?` property to `PRModel` (or handle at the `ReviewDetailView` level with a `@State` for navigation selection)

   **Better approach**: Since `NavigationPhase` is a UI-only concern (Apps layer), use a `@State private var selectedNavPhase: NavigationPhase` in `ReviewDetailView` instead of overloading `PRModel.selectedPhase`. This keeps the non-pipeline navigation state out of the model.

   Update `PipelineStatusView`:
   - Accept a `Binding<NavigationPhase>` instead of reading `prModel.selectedPhase` directly
   - Button action sets the binding
   - Highlight uses the binding for selection state
   - `combinedState` for `.summary`: always return `.completed` (always available, no run state)

2. `pr-radar-mac/Sources/apps/MacApp/UI/ReviewDetailView.swift`
   - Add `@State private var selectedNavPhase: NavigationPhase = .summary`
   - Pass `$selectedNavPhase` to `PipelineStatusView`
   - Replace `PhaseInputView` + `phaseOutputView` switch to key off `selectedNavPhase`:
     - `.summary` → `SummaryPhaseView(prModel: prModel)`
     - `.diff` → existing `PhaseInputView` + `diffOutputView`
     - `.rules` → existing `PhaseInputView` + `rulesOutputView`
     - `.evaluate` → existing `PhaseInputView` + `evaluationsOutputView`
     - `.report` → existing `PhaseInputView` + `reportOutputView`
   - For non-summary phases, derive the `PRRadarPhase` from `selectedNavPhase.primaryPhase` for `PhaseInputView`
   - Keep `prModel.selectedPhase` synced: when `selectedNavPhase` changes (if not `.summary`), update `prModel.selectedPhase = selectedNavPhase.primaryPhase`

3. `pr-radar-mac/Sources/apps/MacApp/Models/PRModel.swift`
   - No changes needed if we use `@State` in `ReviewDetailView` for navigation

## - [ ] Phase 3: Create SummaryPhaseView

**Goal**: Build the new Summary view showing PR metadata and PR-level comments.

**New file**: `pr-radar-mac/Sources/apps/MacApp/UI/PhaseViews/SummaryPhaseView.swift`

**Structure** (following existing phase view patterns like `DiffPhaseView`, `ReportPhaseView`):

```swift
struct SummaryPhaseView: View {
    let metadata: PRMetadata
    let postedComments: [GitHubComment]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                prInfoSection
                if !postedComments.isEmpty {
                    commentsSection
                }
            }
            .padding()
        }
    }
}
```

**PR Info Section**:
- PR number + title (headline)
- Author name/login
- Branch name, state, created date
- PR description/body rendered as text (if non-nil and non-empty)

**Comments Section**:
- Section header "PR Comments" with count
- Each comment shows: author, timestamp, body, and "View on GitHub" link
- Reuse the green accent styling from `InlinePostedCommentView` (left green bar, green tinted background)
- Since `InlinePostedCommentView` takes `GitHubReviewComment` (not `GitHubComment`), create comment rows inline in `SummaryPhaseView` using the same visual pattern rather than trying to share the view (the types differ)

## - [ ] Phase 4: Remove PR-level comments from EvaluationsPhaseView

**Goal**: Since PR-level comments now have their own home in the Summary view, stop passing them to the Evaluations phase view.

**Files to modify**:

1. `pr-radar-mac/Sources/apps/MacApp/UI/ReviewDetailView.swift`
   - In `evaluationsOutputView`, change `postedGeneralComments: prModel.postedComments?.comments ?? []` to `postedGeneralComments: []`
   - Or remove the parameter entirely if the evaluations view handles empty gracefully

**Note**: Keep `postedReviewComments` (inline diff comments) in the evaluations view — those are correctly placed there.

## - [ ] Phase 5: Architecture Validation

Review all commits made during the preceding phases and validate they follow the project's architectural conventions:

**For Swift changes** (`pr-radar-mac/`):
- Fetch and read each skill from `https://github.com/gestrich/swift-app-architecture` (skills directory)
- Compare the commits made against the conventions described in each relevant skill
- If any code violates the conventions, make corrections

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. For each relevant skill, fetch and read from the swift-app-architecture repo
4. Evaluate the changes against each skill's conventions
5. Fix any violations found

**Key conventions to validate:**
- `@Observable` only in Apps layer (no new observable models in Services/Features)
- Imports alphabetically ordered
- File organization: properties → init → computed → methods → nested types
- No unnecessary default parameter values (body default `nil` is acceptable since it's genuinely optional)
- No type aliases or re-exports
- Layer dependency rules respected (Summary view is Apps layer, PRMetadata is Services layer)

## - [ ] Phase 6: Validation

1. **Build**: `cd pr-radar-mac && swift build` — must compile cleanly
2. **Tests**: `cd pr-radar-mac && swift test` — all existing tests must pass
3. **Manual verification**: Run `swift run MacApp`, select a PR that has PR-level comments (e.g., from the test-repo config), and confirm:
   - Summary tab appears first in the navigation bar
   - PR title, author, description display correctly
   - PR-level comments appear in the Summary view with green styling
   - PR-level comments no longer appear in the Evaluations view
   - Clicking Diff/Rules/Evaluate/Report tabs still works as before
   - Phase run buttons still work correctly
