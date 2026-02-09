# Posted Comment Count Badges

## Background

Currently, the PR list view shows an analysis badge with the violation count (orange capsule) and the file list in the diff view shows task badges (blue) and violation badges (severity-colored). There is no indication of how many comments have been **posted** to GitHub vs. how many are still **pending**.

This plan adds two new badge types:
1. **PR list badge** — Shows the number of posted (not pending) review comments for each PR, styled with a distinct color from the existing orange violation badge.
2. **Per-file badge** — Shows the number of posted review comments for each file in the diff view's file list sidebar.

### Data Model Context

- **Pending comments** (`PRComment`) come from the evaluation phase and are stored in `evaluation?.comments`. These are violations that haven't been posted to GitHub yet.
- **Posted comments** (`GitHubReviewComment`) come from the GitHub API and are stored in `postedComments?.reviewComments` (loaded from `gh-comments.json` on disk).
- The `DiffCommentMapping` already separates posted comments per file via `postedByFileAndLine` and `postedUnmatchedByFile`.

### Key Challenge

Posted comment data (`gh-comments.json`) is currently only loaded during `loadDetail()`, which runs on-demand when a PR is selected. The PR list renders before any PR is selected, so we need a lightweight mechanism to surface the posted comment count without loading full detail data for every PR.

## Phases

## - [x] Phase 1: Add Posted Comment Count to PRModel's Lightweight Load

**Goal:** Make the posted comment count available in `PRModel` before `loadDetail()` is called, so the PR list can display it.

**Tasks:**
- In `PRModel.loadAnalysisSummary()`, after loading the `EvaluationSummary`, also attempt to parse `gh-comments.json` from the `.pullRequest` phase directory and count `reviewComments`
- Add a `postedCommentCount: Int` field to the `AnalysisState.loaded` case (alongside the existing `violationCount` and `evaluatedAt`)
- If `gh-comments.json` doesn't exist or fails to parse, default the count to 0

**Files to modify:**
- [PRModel.swift](../../pr-radar-mac/Sources/apps/MacApp/Models/PRModel.swift) — Update `AnalysisState.loaded` case and `loadAnalysisSummary()`

**Architecture notes:**
- Per the swift-architecture guide, `@Observable` models live in the Apps layer and own state transitions. Adding a field to `AnalysisState` is the correct place since this is presentation state derived from on-disk data.
- The lightweight load pattern already established with `EvaluationSummary` is the right approach — just extend it to include posted comment count.

**Completed:** Added `postedCommentCount: Int` as the third associated value in `AnalysisState.loaded`. The count is derived from `GitHubPullRequestComments.reviewComments.count` parsed from `gh-comments.json` in the `.pullRequest` phase directory. Falls back to 0 if the file is missing or unparseable. Updated all existing pattern matches in `PRModel.swift` (`hasPendingComments`) and `PRListRow.swift` (`analysisBadge`) to use the three-value tuple.

## - [x] Phase 2: Add Posted Comment Badge to PR List Row

**Goal:** Display a badge on each PR in the list showing the number of posted review comments, styled distinctly from the existing orange violation badge.

**Tasks:**
- Add a `postedCommentsBadge` computed property to `PRListRow` that reads from `prModel.analysisState`
- When `postedCommentCount > 0`, show a capsule badge with the count using a distinct color (green — indicating "completed/posted" — to contrast with orange for pending violations)
- Place the badge between the analysis badge and the timestamp in the HStack
- When both violation count and posted comment count are present, show both badges side by side

**Color scheme:**
- Orange capsule = pending violations (existing)
- Green capsule = posted comments (new)

**Files to modify:**
- [PRListRow.swift](../../pr-radar-mac/Sources/apps/MacApp/UI/PRListRow.swift) — Add `postedCommentsBadge` and update the HStack layout

**Architecture notes:**
- Per the swift-swiftui guide, views connect directly to `@Observable` models. `PRListRow` already reads from `prModel.analysisState`, so adding another field to that enum is a natural extension.

**Completed:** Added `postedCommentsBadge` computed property using a `switch` with a `where` guard on `postedCommentCount > 0`. The badge uses a green capsule (`.background(.green, in: Capsule())`) matching the same font/padding style as the existing orange violation badge. Placed between `analysisBadge` and the timestamp in the HStack. When `postedCommentCount` is 0 or analysis state is not `.loaded`, renders `EmptyView()`.

## - [x] Phase 3: Add Posted Comment Badges Per File in Diff View

**Goal:** Show a per-file badge in the file list sidebar indicating how many posted review comments exist for that file.

**Tasks:**
- Add a `postedCommentCountsByFile(mapping:)` helper to `DiffPhaseView` that aggregates posted comment counts per file from `DiffCommentMapping.postedByFileAndLine` and `postedUnmatchedByFile`
- Add a `postedCommentBadge(count:)` view builder in `DiffPhaseView` — green capsule matching the PR list badge style
- In `annotatedFileList`, display the posted comment badge for each file (after the violation badge)
- In `plainFileList`, also display the posted comment badge when available (the `postedReviewComments` data is passed into `DiffPhaseView` already)

**Badge ordering in file rows:**
- Task badge (blue) → Violation badge (severity-colored) → Posted comment badge (green) → Hunk count (gray text)

**Files to modify:**
- [DiffPhaseView.swift](../../pr-radar-mac/Sources/apps/MacApp/UI/PhaseViews/DiffPhaseView.swift) — Add `postedCommentCountsByFile()`, `postedCommentBadge()`, and update both file list variants

**Architecture notes:**
- The `DiffCommentMapping` already has `postedByFileAndLine` and `postedUnmatchedByFile` populated by the mapper, so this is purely a view-layer change aggregating existing data.

**Completed:** Added `postedCommentCountsByFile(mapping:)` helper that aggregates counts from both `postedByFileAndLine` and `postedUnmatchedByFile`. Added `postedCommentBadge(count:)` green capsule view matching the same font/padding style as existing badges. In `annotatedFileList`, the posted badge appears after violation badges; the hunk count fallback now only shows when both violation and posted counts are 0. In `plainFileList`, posted counts are computed from the comment mapping (only when `postedReviewComments` is non-empty) and the green badge displays before the hunk count.

## - [ ] Phase 4: Architecture Validation

Review all commits made during the preceding phases and validate they follow the project's architectural conventions:

**For Swift changes** (`pr-radar-mac/`):
- Re-read the `swift-architecture` and `swift-swiftui` skills from `https://github.com/gestrich/swift-app-architecture` (`plugin/skills/`)
- Compare the commits made against the conventions described in each skill
- If any code violates the conventions, make corrections

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. Fetch and read ALL skills from the swift-app-architecture repo
4. Evaluate the changes against each skill's conventions
5. Fix any violations found

## - [ ] Phase 5: Validation

**Build:**
- Run `swift build` in `pr-radar-mac/` to verify compilation

**Tests:**
- Run `swift test` in `pr-radar-mac/` to verify all existing tests pass

**Manual verification:**
- Launch `swift run MacApp` and confirm:
  - PR list shows green posted comment count badges for PRs with posted comments
  - PRs without posted comments show no green badge
  - File list shows green per-file posted comment badges in annotated mode
  - Badge colors are visually distinct (orange for pending, green for posted)

**Success criteria:**
- Build succeeds with no warnings in changed files
- All existing tests pass
- Badges display correctly in the UI
