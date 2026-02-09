## Implement Simplest Remaining TODO Item

### Background

The `docs/proposed/TODO.md` contains a backlog of improvements for PRRadar. Several items have already been completed (confirmed via git history):
- **Differentiate PR status in PR list view** — done (`ca01518`)
- **Hide PR-level comments from file view** — done (`6c351c5`)
- **Single diff view with inline analysis** — done (`b7e2e30` through `cb6d40c`)

The request is to identify the simplest remaining item and implement it. Candidate simple items include: "Show model used in report and cost displays", "Show GitHub real name in UI alongside handle", "Posted comments badge indicators", "Fix task counts display on rules view", and others. Phase 1 will confirm which items are truly not done and pick the simplest one.

## - [x] Phase 1: Interpret the Request

### Completed TODO Items (confirmed via git history + codebase)

| Item | Evidence |
|------|----------|
| Differentiate PR status in PR list view | Commit `ca01518` |
| Hide PR-level comments from file view | Commit `6c351c5` |
| Single diff view with inline analysis | Commits `b7e2e30` through `cb6d40c` |
| Effective diff fixes | 11+ commits (`0637520` through `ce27d51`) |
| Persist AI output as artifacts | Artifact handling already exists (`39e0b72`, `121b1e8`); `DataPathsService` and `LoadExistingOutputsUseCase` manage persistence |

### Remaining TODO Items (by complexity)

| Item | Complexity | Key Rationale |
|------|-----------|---------------|
| **Show model used in report and cost displays** | **Very Low** | `modelUsed` already in `RuleEvaluationResult`; just needs UI display in ~5 locations |
| Fix task counts display on rules view | Low | Single view (`RulesPhaseView`), but needs UX decision on what to show |
| Posted comments badge indicators | Low-Medium | Badge UI is simple but data not pre-loaded in list context |
| Show GitHub real name alongside handle | Medium | Requires GitHub API user profile fetch (new API call) |
| Show all GitHub comment details in Mac app comment preview | Medium | Multiple detail elements to surface |
| Render pending comments as markdown | Medium | Need to match posted comment rendering pipeline |
| Filter tasks/rules list by selected file | Medium | New filtering logic + UI wiring |
| Create Xcode project | Medium | Build system / project config changes |
| Show moved/renamed files in diff view | Medium | Diff parsing changes |
| Per-task evaluation with play button | Medium | Backend method exists, UI + wiring needed |
| Skip already-analyzed tasks during evaluation | Medium | Pipeline logic changes |
| Local triage runs | Large | New feature: cron, daily report, cost tracking |
| Audit PullRequests app for reusable ideas | Large | Research / exploration task |
| CI runs | Large | Infrastructure: shallow clone, GitHub Actions |

### Selected Item

**"Show model used in report and cost displays"** — the simplest remaining item.

**Why it's simplest**: The `modelUsed` field already exists in `RuleEvaluationResult` (populated by `EvaluationService`). It just needs to be surfaced in the UI/CLI locations where cost is already displayed. No new data fetching, no model changes, no business logic changes — purely additive display work.

### Relevant Source Files

| File | Role |
|------|------|
| `Sources/services/PRRadarModels/EvaluationOutput.swift` | Defines `modelUsed` on `RuleEvaluationResult` |
| `Sources/services/PRRadarCLIService/EvaluationService.swift` | Populates `modelUsed` during evaluation |
| `Sources/apps/MacApp/UI/ReviewViews/CommentApprovalView.swift` | Shows cost for individual comments |
| `Sources/apps/MacApp/UI/PhaseViews/ReportPhaseView.swift` | Shows total cost in summary cards |
| `Sources/apps/MacApp/UI/PhaseViews/DiffPhaseView.swift` | Shows cost in summary bar |
| `Sources/apps/MacCLI/Commands/EvaluateCommand.swift` | Prints total cost in CLI summary |
| `Sources/services/PRRadarModels/ReportOutput.swift` | Generates markdown report with cost |

## - [x] Phase 2: Gather Architectural Guidance

### Layers Touched

| Layer | Module | Files | Change Type |
|-------|--------|-------|-------------|
| **Services** | `PRRadarModels` | `PRComment.swift`, `ReportOutput.swift` | Add `modelUsed` field to `PRComment`; optionally add model info to report markdown |
| **Services** | `PRRadarCLIService` | `ReportGeneratorService.swift` | Pass `modelUsed` through to `ViolationRecord` |
| **Features** | `PRReviewFeature` | (none — `EvaluationPhaseOutput.comments` auto-maps via `PRComment.from()`) | No changes needed |
| **Apps** | `MacApp` | `CommentApprovalView.swift`, `ReportPhaseView.swift`, `DiffPhaseView.swift` | Display model next to existing cost |
| **Apps** | `MacCLI` | `EvaluateCommand.swift` | Print model in CLI summary |

All changes respect the dependency rule (Apps → Features → Services → SDKs). No cross-layer violations.

### Data Flow for `modelUsed`

```
ClaudeBridgeClient → EvaluationService (sets modelUsed on RuleEvaluationResult)
  → persisted as JSON in evaluations/
  → loaded by EvaluateUseCase.parseOutput() into EvaluationPhaseOutput
  → EvaluationPhaseOutput.comments maps via PRComment.from(evaluation:task:)
  → PRComment consumed by CommentApprovalView, DiffPhaseView, etc.
```

**Key observation**: `PRComment.from()` already copies `costUsd` from `RuleEvaluationResult` but does **not** copy `modelUsed`. Adding `modelUsed` to `PRComment` and updating `PRComment.from()` is the central change that flows model info to all UI consumers.

### Existing Cost Display Patterns (to mirror for model display)

1. **CommentApprovalView** (detail panel, `ruleInfoSection`): Shows `"Cost: $0.0045"` in an `HStack` with `.font(.caption)` when `costUsd` is non-nil. Model should be shown adjacently.
2. **DiffPhaseView** (`summaryItems`): Appends `PhaseSummaryBar.Item(label: "Cost:", value: "$0.0045")` from `evaluationSummary.totalCostUsd`. Model display here needs a different approach since there's no single model on `EvaluationSummary` — we'd show the distinct models used.
3. **ReportPhaseView** (`summaryCards`): Shows `"Cost"` as a summary card with `String(format: "$%.4f", totalCostUsd)`. Could add a "Model" card.
4. **EvaluateCommand** (CLI): Prints `"Cost: $0.0045"` in the summary block. Can add a model line.
5. **ReportOutput.toMarkdown()**: Includes `"**Total Cost:** $0.0045"` in the summary section. Could add a model line.
6. **PRComment.toGitHubMarkdown()**: Includes cost in the footer `"(cost $0.0045)"`. Could append model info.

### Model Name Formatting

`modelUsed` is stored as the raw API model ID (e.g., `"claude-sonnet-4-20250514"`). For display, a short human-readable form like `"Sonnet 4"` or `"Haiku 4.5"` would be cleaner. A small helper to extract a display name from the model ID would be useful, placed in `PRRadarModels` (Services layer) since it operates on model data.

### Aggregate Model Info

`EvaluationSummary` has no `modelUsed` field — it aggregates across multiple evaluations that may each use different models (rules can override the default model). For summary displays (DiffPhaseView summary bar, ReportPhaseView cards, CLI summary, markdown report), we should collect the **distinct set of models** from the individual `RuleEvaluationResult` entries in `EvaluationSummary.results`.

### Test Conventions

- Swift Testing framework (`@Test`, `#expect`, `@Suite`)
- Arrange-Act-Assert pattern with `// Arrange`, `// Act`, `// Assert` comments
- Tests live in `Tests/PRRadarModelsTests/`
- Existing `EvaluationOutputTests.swift` already tests `modelUsed` on `RuleEvaluationResult` — no new tests needed for the model field there
- New tests needed: `PRComment.from()` should copy `modelUsed`; model display name helper

### Architecture Skill Conventions

- Alphabetical import ordering
- File organization: properties → init → computed → methods → nested types
- Avoid type aliases and re-exports
- Require data explicitly (no default/fallback values)
- `@Observable` only in Apps layer
- SDKs are stateless `Sendable` structs

## - [x] Phase 3: Plan the Implementation

### Implementation Overview

The feature threads `modelUsed` from `RuleEvaluationResult` through to all cost display locations. There are two main data paths:

1. **Per-comment path**: `RuleEvaluationResult.modelUsed` → `PRComment.modelUsed` → individual comment UIs (CommentApprovalView, toGitHubMarkdown)
2. **Aggregate path**: `EvaluationSummary.results[*].modelUsed` → collect distinct models → summary UIs (DiffPhaseView, ReportPhaseView, EvaluateCommand, ReportOutput.toMarkdown)

A model display name helper converts raw API IDs (e.g. `"claude-sonnet-4-20250514"`) to human-readable names (e.g. `"Sonnet 4"`).

### Phases

## - [x] Phase 4: Add model display name helper and thread `modelUsed` through models

### What to implement

1. **Model display name helper** in `PRRadarModels` — a function `displayName(forModelId:)` that maps raw API model IDs to short human-readable names. Examples:
   - `"claude-sonnet-4-20250514"` → `"Sonnet 4"`
   - `"claude-haiku-4-5-20251001"` → `"Haiku 4.5"`
   - `"claude-opus-4-20250514"` → `"Opus 4"`
   - Unknown IDs → return the raw ID as-is

2. **Add `modelUsed: String?` to `PRComment`** — new optional property, populated from `RuleEvaluationResult.modelUsed` in the `from()` factory method.

3. **Add `modelsUsed: [String]` computed property to `EvaluationSummary`** — returns the sorted distinct set of `modelUsed` values from `results`. This is a computed property, not stored/coded, since the data is already in `results`.

4. **Add `modelsUsed: [String]` to `ReportSummary`** — a stored property (needs to be Codable) that captures the distinct models. Populated by `ReportGeneratorService.calculateSummary()`.

### Files to modify

| File | Change |
|------|--------|
| `Sources/services/PRRadarModels/ModelDisplayName.swift` | **New file** — `public func displayName(forModelId:) -> String` |
| `Sources/services/PRRadarModels/PRComment.swift` | Add `modelUsed: String?` property, update `init`, update `from()` to copy `evaluation.modelUsed` |
| `Sources/services/PRRadarModels/EvaluationOutput.swift` | Add computed `modelsUsed` on `EvaluationSummary` |
| `Sources/services/PRRadarModels/ReportOutput.swift` | Add `modelsUsed: [String]` to `ReportSummary`, update `init` and `CodingKeys` |
| `Sources/services/PRRadarCLIService/ReportGeneratorService.swift` | Collect distinct models in `loadViolations` and pass to `calculateSummary` |

### Acceptance criteria

- `PRComment.from()` copies `modelUsed` from the evaluation result
- `EvaluationSummary.modelsUsed` returns distinct sorted model IDs from results
- `ReportSummary.modelsUsed` populated by `ReportGeneratorService`
- `displayName(forModelId:)` returns short names for known models
- Unit tests pass for `PRComment.from()` model copying, display name helper, and `EvaluationSummary.modelsUsed`

## - [x] Phase 5: Display model in all UI and CLI locations

### What to implement

Add model display to all 6 locations where cost is currently shown:

1. **CommentApprovalView** (`ruleInfoSection`) — show model next to cost: `"Cost: $0.0045 · Sonnet 4"`
2. **DiffPhaseView** (`summaryItems`) — add a `"Model:"` item showing the distinct models (e.g. `"Sonnet 4"` or `"Sonnet 4, Haiku 4.5"`)
3. **ReportPhaseView** (`summaryCards`) — add a `"Model"` summary card showing distinct models
4. **EvaluateCommand** (CLI) — print `"  Model: Sonnet 4"` in the summary block
5. **ReportOutput.toMarkdown()** — add `"- **Models Used:** Sonnet 4"` in the summary section
6. **PRComment.toGitHubMarkdown()** — append model to cost in footer: `"(cost $0.0045 · Sonnet 4)"`

### Files to modify

| File | Change |
|------|--------|
| `Sources/apps/MacApp/UI/ReviewViews/CommentApprovalView.swift` | Show `modelUsed` in `ruleInfoSection` next to cost |
| `Sources/apps/MacApp/UI/PhaseViews/DiffPhaseView.swift` | Add model summary item using `evaluationSummary.modelsUsed` |
| `Sources/apps/MacApp/UI/PhaseViews/ReportPhaseView.swift` | Add model summary card using `report.summary.modelsUsed` |
| `Sources/apps/MacCLI/Commands/EvaluateCommand.swift` | Print model line in CLI summary using `output.summary.modelsUsed` |
| `Sources/services/PRRadarModels/ReportOutput.swift` | Add models used line in `toMarkdown()` |
| `Sources/services/PRRadarModels/PRComment.swift` | Append model to cost in `toGitHubMarkdown()` footer |

### Acceptance criteria

- All 6 display locations show model information when available
- Display uses human-readable model names via `displayName(forModelId:)`
- Multiple distinct models shown as comma-separated list
- Model display gracefully handles nil/empty cases

## - [x] Phase 6: Testing and Verification

### What to do

1. Run `swift build` — must succeed with no errors
2. Run `swift test` — all tests must pass
3. Mark TODO item as done in `docs/proposed/TODO.md` (change `- [ ]` to `- [x]` for "Show model used in report and cost displays")

### Acceptance criteria

- `swift build` succeeds
- `swift test` passes (all existing + new tests)
- TODO item marked as completed in `docs/proposed/TODO.md`

## - [x] Phase 7: Create Pull Request

### What to do

1. Run `gh auth switch -u gestrich`
2. Create a draft PR with `gh pr create --draft` targeting `main`
3. PR title: "Show model used in report and cost displays"
4. PR body summarizes the changes across model threading, display helper, and all UI/CLI display locations

### Acceptance criteria

- Draft PR created successfully
- PR targets `main` branch
