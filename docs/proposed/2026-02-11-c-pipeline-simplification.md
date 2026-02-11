# Pipeline Simplification — Phase Coalescing & Rename

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | Layer responsibilities and dependency rules — ensures rename respects layer boundaries |
| `/swift-app-architecture:swift-swiftui` | Model-View patterns — guides how phase state changes flow to UI |
| `/swift-testing` | Test conventions — for updating phase behavior tests |

## Background

The current pipeline has **6 phases** (`PRRadarPhase` enum in `DataPathsService.swift`):

```
pullRequest → focusAreas → rules → tasks → evaluations → report
```

This creates confusion in several ways:
1. **"diff"/"pullRequest"** is misleading — the phase fetches PR metadata, comments, reviews, the diff, effective diff, and move detection. Not just a diff.
2. **Phases 2-4 are already coalesced in code** — `FetchRulesUseCase` runs all three as one unit, and the CLI `rules` command triggers all three. Having 3 separate enum cases for what is functionally one operation adds noise.
3. **"evaluations"** is less intuitive than **"analysis"** / **"analyze"** for the AI evaluation step.
4. **"report"** (phase 6) is purely aggregation/formatting with no AI calls — it may not warrant being a full pipeline phase.
5. The CLI command descriptions already have numbering inconsistencies (`evaluate` says "Phase 3", `report` says "Phase 4") because the 6-phase model doesn't match the 4-command reality.

### Target: 4 Phases

| # | New Name | Old Phases | What It Does |
|---|----------|------------|--------------|
| 1 | **sync** | pullRequest | Fetch all PR data (diff, metadata, comments, reviews, effective diff, moves) |
| 2 | **prepare** | focusAreas + rules + tasks | Generate focus areas (AI), load rules, match rules to focus areas → produce tasks |
| 3 | **analyze** | evaluations | AI evaluates each task against the code |
| 4 | **report** | report | Generate summary report and markdown output |

### Naming Alternatives to Discuss

**Phase 1** — collecting PR data:
| Name | Button Label | Verb Form | Notes |
|------|-------------|-----------|-------|
| **sync** | "Sync PR" | syncing | Implies bringing local data up-to-date with remote. Feels natural for re-running. |
| **fetch** | "Fetch PR" | fetching | Simple and clear. Already used in "Fetch Diff" button. Might be confused with git fetch. |
| **collect** | "Collect PR" | collecting | Accurate but slightly unusual as a button label. |

**Phase 2** — preparing evaluation tasks:
| Name | Button Label | Verb Form | Notes |
|------|-------------|-----------|-------|
| **prepare** | "Prepare" | preparing | Clear intent — setting up for analysis. Not overloaded with other meanings. |
| **plan** | "Plan" | planning | The output is literally a plan of what to evaluate. Short and intuitive. |
| **stage** | "Stage" | staging | Bill's initial thought. Risk: confusion with git staging. |
| **triage** | "Triage" | triaging | Interesting metaphor (sorting what needs attention) but may feel unfamiliar. |
| **map** | "Map Rules" | mapping | Describes the matching process but misses the focus area generation step. |

**Phase 3** — AI evaluation:
| Name | Button Label | Verb Form | Notes |
|------|-------------|-----------|-------|
| **analyze** | "Analyze" | analyzing | Bill's preference. Clear, simple, widely understood. |

### What Must Be Preserved

- Independent execution: sync can run alone, prepare requires sync, analyze requires prepare
- Selective analysis: re-run analysis on specific files/rules/focus areas (already works via `SelectiveEvaluateUseCase`)
- Phase state tracking: running/completed/failed per phase in the UI
- Output caching: each phase's output is persisted and reloadable
- CLI commands: `diff`→`sync`, `rules`→`prepare`, `evaluate`→`analyze`, `report`→stays, `analyze`→orchestrates all (rename to `run` or `full`)
- Incremental re-runs: re-syncing PR data, re-preparing tasks, re-analyzing

## Phases

## - [x] Phase 1: Rename PRRadarPhase enum and coalesce cases ✅

**Skills to read**: `/swift-app-architecture:swift-architecture`

Modify `PRRadarPhase` in `DataPathsService.swift`:

```swift
// Before: 6 cases
case pullRequest, focusAreas, rules, tasks, evaluations, report

// After: 4 cases
case sync = "phase-1-sync"
case prepare = "phase-2-prepare"
case analyze = "phase-3-analyze"
case report = "phase-4-report"
```

Key changes:
- Update `displayName` property: "Sync PR", "Prepare", "Analyze", "Report"
- Update `requiredPredecessor`: sync → nil, prepare → sync, analyze → prepare, report → analyze
- Update `phaseNumber`: 1, 2, 3, 4
- Remove `focusAreas`, `rules`, `tasks`, `evaluations` cases (coalesced into sync/prepare/analyze)
- Update `DataPathsService.phaseDirectory()` for new raw values
- Update all `PhaseResult` and `PhaseStatus` references

**No backward compatibility**: Old output directories (`phase-1-pull-request/`, etc.) can be deleted. No migration, no aliasing — just use the new names everywhere.

### Technical Notes

- Added subdirectory infrastructure to `DataPathsService` for the coalesced `prepare` phase: `prepareFocusAreasSubdir` ("focus-areas"), `prepareRulesSubdir` ("rules"), `prepareTasksSubdir` ("tasks"), plus `phaseSubdirectory()` helper
- Added subdirectory-aware overloads to `OutputFileReader` and `PhaseOutputParser` so callers can read from prepare's nested directories
- `FetchRulesUseCase` was simplified from 3 separate `PhaseResultWriter.writeSuccess()` calls to 1 call for `.prepare`
- `PRModel.runRules()` was simplified from tracking 3 separate phase states to tracking 1 `.prepare` state
- All 371 tests pass, build succeeds

## - [x] Phase 2: Update output types and use cases ✅

**Skills to read**: `/swift-app-architecture:swift-architecture`

Rename output types to match new phase names:
- `DiffPhaseSnapshot` → `SyncSnapshot` (or `PRSnapshot`)
- `RulesPhaseOutput` → `PrepareOutput` (or `PreparationOutput`)
- `EvaluationPhaseOutput` → `AnalysisOutput`
- `ReportPhaseOutput` → stays as-is (name still fits)

Update use cases:
- `FetchDiffUseCase` → `SyncPRUseCase` (or `FetchPRUseCase`)
- `FetchRulesUseCase` → `PrepareUseCase`
- `EvaluateUseCase` → `AnalyzeUseCase` (note: current `AnalyzeUseCase` is the orchestrator — rename that to `RunPipelineUseCase` or `FullAnalysisUseCase`)
- `SelectiveEvaluateUseCase` → `SelectiveAnalyzeUseCase`
- `GenerateReportUseCase` → stays as-is
- `LoadExistingOutputsUseCase` → update phase references

Update `PhaseProgress<Output>` references where `.running(phase:)` uses old phase cases.

### Technical Notes

- Renamed 7 use case files via `git mv` for clean history tracking
- Output type renames: `DiffPhaseSnapshot` → `SyncSnapshot`, `RulesPhaseOutput` → `PrepareOutput`, `EvaluationPhaseOutput` → `AnalysisOutput`, `AnalyzePhaseOutput` → `RunPipelineOutput`, `AnalyzeAllOutput` → `RunAllOutput`
- Use case renames: `FetchDiffUseCase` → `SyncPRUseCase`, `FetchRulesUseCase` → `PrepareUseCase`, `EvaluateUseCase` → `AnalyzeUseCase`, `SelectiveEvaluateUseCase` → `SelectiveAnalyzeUseCase`, `AnalyzeUseCase` (orchestrator) → `RunPipelineUseCase`, `AnalyzeAllUseCase` → `RunAllUseCase`
- `PipelineSnapshot` property renames: `diff` → `sync`, `rules` → `preparation`, `evaluation` → `analysis`
- `PhaseProgress<Output>` required no changes — `.running(phase:)` already uses `PRRadarPhase` cases (renamed in Phase 1)
- All 371 tests pass, build succeeds

## - [x] Phase 3: Update CLI commands ✅

Rename CLI commands and update descriptions:
- `DiffCommand` → `SyncCommand` (or keep `diff` as alias for familiarity?)
- `RulesCommand` → `PrepareCommand`
- `EvaluateCommand` → `AnalyzeCommand` (current `AnalyzeCommand` becomes `RunAllCommand` or `FullCommand`)
- `ReportCommand` → stays as-is
- `StatusCommand` → update phase references

Update command abstracts to use new terminology:
- "Sync PR data (Phase 1)"
- "Prepare evaluation tasks (Phase 2)"
- "Analyze code against rules (Phase 3)"
- "Generate summary report (Phase 4)"

### Technical Notes

- Renamed 5 command files via `git mv` for clean history tracking
- Command renames: `diff` → `sync`, `rules` → `prepare`, `evaluate` → `analyze`, `analyze` (orchestrator) → `run`, `analyze-all` → `run-all`
- Struct renames: `DiffCommand` → `SyncCommand`, `RulesCommand` → `PrepareCommand`, `EvaluateCommand` → `AnalyzeCommand`, `AnalyzeCommand` → `RunCommand`, `AnalyzeAllCommand` → `RunAllCommand`
- `CommentCommand` abstract updated to remove "Phase 5" reference (comment is a post-pipeline action, not a pipeline phase)
- `StatusCommand` required no changes — it already uses `PRRadarPhase.allCases` dynamically
- `ReportCommand` required no changes — name and abstract already match the 4-phase model
- All user-facing messages updated (status logs, error messages, completion summaries)
- Both `PRRadarMacCLI` and `MacApp` targets build successfully

## - [x] Phase 4: Update PRModel and UI ✅

**Skills to read**: `/swift-app-architecture:swift-swiftui`

Update `PRModel.swift`:
- Rename stored properties: `diff` → `syncSnapshot` (or `prData`), `rules` → `preparation`, `evaluation` → `analysis`
- Update `canRunPhase()` switch for 3 cases
- Update `runPhase()` switch
- Rename `runDiff()` → `runSync()`, `runRules()` → `runPrepare()`, `runEvaluate()` → `runAnalyze()`
- Update `runAnalysis()` orchestrator for new phase names
- Update `startSelectiveEvaluation` → `startSelectiveAnalysis`

Update views:
- `ReviewDetailView.swift` — toolbar button labels: "Sync PR", "Prepare", "Analyze"
- `DiffPhaseView.swift` — all references to evaluation/tasks terminology
- `PipelineStatusView.swift` — update `NavigationPhase` mappings and status display
- `RulesPhaseView.swift` → rename to `PreparePhaseView.swift`?
- Phase-specific views may need renaming

Update `NavigationPhase`:
- `.diff` → `.diff` (still shows the diff, name is fine for navigation)
- Or reconsider whether NavigationPhase needs renaming too

### Technical Notes

- `PRModel` stored property renames: `diff` → `syncSnapshot`, `rules` → `preparation`, `evaluation` → `analysis`
- `ReviewSnapshot` struct field renames match: `diff` → `syncSnapshot`, `rules` → `preparation`, `evaluation` → `analysis`
- Method renames: `runDiff()` → `runSync()`, `runRules()` → `runPrepare()`, `runEvaluate()` → `runAnalyze()`, `startSelectiveEvaluation()` → `startSelectiveAnalysis()`
- All computed properties updated: `reconciledComments` now reads from `analysis`, diff accessors read from `syncSnapshot`
- View updates across 4 files: `ReviewDetailView` (6 `prModel.diff` → `prModel.syncSnapshot`), `DiffPhaseView` (2 property refs + 6 `startSelectiveAnalysis` calls), `RichDiffViews` (`AnnotatedDiffContentView` — 1 property ref + 4 `startSelectiveAnalysis` calls)
- `NavigationPhase`, `PipelineStatusView`, `PhaseInputView`, `RulesPhaseView` required no changes — they already use `PRRadarPhase` enum cases (renamed in Phase 1) and don't directly access PRModel data properties
- Toolbar button labels were already correct from Phase 3: "Sync PR", "Prepare", "Analyze"
- All 371 tests pass, build succeeds

## - [x] Phase 5: Update services layer ✅

Update service references:
- `PRRadarCLIService` — any phase-specific service methods
- `PhaseOutputParser` — update phase directory parsing
- `PhaseResultWriter` — update phase result writing
- `DataPathsService` — output directory paths for new phase names
- `EvaluationCacheService` → `AnalysisCacheService`?

### Technical Notes

- File renames via `git mv` for clean history: `EvaluationService.swift` → `AnalysisService.swift`, `EvaluationCacheService.swift` → `AnalysisCacheService.swift`, `EvaluationFilter.swift` → `AnalysisFilter.swift`, `EvaluationOutput.swift` → `AnalysisOutput.swift`
- Type renames: `EvaluationService` → `AnalysisService`, `EvaluationCacheService` → `AnalysisCacheService`, `EvaluationFilter` → `AnalysisFilter`, `EvaluationSummary` → `AnalysisSummary`, `EvaluationTaskOutput` → `AnalysisTaskOutput`
- Public method renames: `evaluateTask()` → `analyzeTask()`, `runBatchEvaluation()` → `runBatchAnalysis()`
- Local variable renames: `evaluationService` → `analysisService` (in AnalyzeUseCase, SelectiveAnalyzeUseCase)
- PRModel private member renames: `mergeEvaluationResult` → `mergeAnalysisResult`, `selectiveEvaluationInFlight` → `selectiveAnalysisInFlight`, `runSelectiveEvaluation` → `runSelectiveAnalysis`, `isSelectiveEvaluationRunning` → `isSelectiveAnalysisRunning`
- `PhaseProgress` enum case rename: `.evaluationResult` → `.analysisResult`
- Types deliberately NOT renamed: `RuleEvaluation`, `RuleEvaluationResult` (these describe individual rule evaluations, not the pipeline phase)
- Private template strings (`evaluationPromptTemplate`, `evaluationOutputSchema`) kept as-is — they describe the AI evaluation operation, not the pipeline phase
- Test file renames: `EvaluationFilterTests.swift` → `AnalysisFilterTests.swift`, `EvaluationSummaryModelsUsedTests.swift` → `AnalysisSummaryModelsUsedTests.swift`, `EvaluationCacheServiceTests.swift` → `AnalysisCacheServiceTests.swift`, `EvaluationOutputTests.swift` → `AnalysisOutputTests.swift`
- All 371 tests pass, build succeeds

## - [ ] Phase 6: Update tests

**Skills to read**: `/swift-testing`

- `PhaseBehaviorTests.swift` — update phase number and predecessor assertions
- Any test that references specific phase cases
- Verify all 230+ tests still pass after rename
- Consider whether test file names need updating

## - [ ] Phase 7: Validation

**Skills to read**: `/swift-testing`

- `swift build` passes
- `swift test` — all tests pass
- CLI commands work with new names: `swift run PRRadarMacCLI sync 1 --config test-repo`
- GUI pipeline buttons work: Sync PR → Prepare → Analyze → Report
- Selective analysis still works from context menus
- Phase state tracking (running/completed/failed) displays correctly
- Output directories use new names
- Full pipeline (`analyze` CLI / `runAnalysis()`) runs all 4 phases in sequence
