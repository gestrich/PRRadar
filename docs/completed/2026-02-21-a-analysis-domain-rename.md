## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture rules, layer placement, code style |
| `swift-testing` | Test style guide and conventions |

## Background

The analysis domain types have confusing, inconsistent names. Types like `AnalysisTaskOutput` (which is an input, not output), `RuleEvaluationResult` vs `RuleEvaluation` (triple "evaluation" nesting), and `AnalysisOutput` (vague — could mean one rule or the whole run) make the codebase harder to follow.

After discussion, we settled on three naming families:
- **PRReview** — the aggregate level (the whole PR review run)
- **Rule** — individual rule-level types (one rule applied to one focus area)
- **Verdict** distinguishes the AI's judgment from the wrapper types

We also identified two structural improvements:
1. Merge `EvaluationSuccess` + `RuleEvaluation` into a single `RuleResult` (eliminating a nesting level)
2. Deduplicate the `results: [RuleOutcome]` array that lives in both `PRReviewResult` and `PRReviewSummary`

The work is split into phases: safe renames first, then structural refactors. No backward compatibility with old on-disk JSON formats is needed — old cached/output data will be deleted.

### Rename Map

| Current | Proposed | Kind |
|---|---|---|
| `AnalysisTaskOutput` | `RuleRequest` | Rename |
| `AnalysisOutput` | `PRReviewResult` | Rename |
| `AnalysisSummary` | `PRReviewSummary` | Rename |
| `RuleEvaluationResult` | `RuleOutcome` | Rename |
| `RuleEvaluation` | `RuleFinding` | Rename |
| `AnalysisFilter` | `RuleFilter` | Rename |
| `EvaluationSuccess` + `RuleFinding` | `RuleResult` (merged) | Structural |
| `EvaluationError` | `RuleError` | Rename |
| *(new)* | `PRReviewRequest` | New type |

### Files Affected by Renames

**Definition files (will be renamed):**
- `PRRadarModels/TaskOutput.swift` — defines `AnalysisTaskOutput`
- `PRRadarModels/AnalysisSummary.swift` — defines `AnalysisSummary`
- `PRRadarModels/AnalysisFilter.swift` — defines `AnalysisFilter`
- `PRRadarModels/Evaluations/RuleEvaluationResult.swift` — defines `RuleEvaluationResult`
- `PRRadarModels/Evaluations/RuleEvaluation.swift` — defines `RuleEvaluation`
- `PRRadarModels/Evaluations/EvaluationSuccess.swift` — defines `EvaluationSuccess`
- `PRRadarModels/Evaluations/EvaluationError.swift` — defines `EvaluationError`
- `PRReviewFeature/models/AnalysisOutput.swift` — defines `AnalysisOutput`

**Source files referencing these types:**
- `PRReviewFeature/usecases/AnalyzeUseCase.swift`
- `PRReviewFeature/usecases/AnalyzeSingleTaskUseCase.swift`
- `PRReviewFeature/usecases/PrepareUseCase.swift`
- `PRReviewFeature/usecases/LoadPRDetailUseCase.swift`
- `PRReviewFeature/models/PhaseProgress.swift`
- `PRReviewFeature/models/TaskProgress.swift`
- `PRReviewFeature/models/PRDetail.swift`
- `PRRadarCLIService/AnalysisService.swift`
- `PRRadarCLIService/AnalysisCacheService.swift`
- `PRRadarCLIService/TaskCreatorService.swift`
- `PRRadarCLIService/ReportGeneratorService.swift`
- `PRRadarCLIService/ViolationService.swift`
- `PRRadarModels/PRComment.swift`
- `MacApp/Models/PRModel.swift`
- `MacApp/UI/PhaseViews/DiffPhaseView.swift`
- `MacApp/UI/PhaseViews/TaskRowView.swift`
- `MacApp/UI/PhaseViews/RulesPhaseView.swift`
- `MacApp/UI/PhaseViews/TasksPagerView.swift`
- `MacApp/UI/GitViews/RichDiffViews.swift`
- `MacCLI/Commands/AnalyzeCommand.swift`

**Test files:**
- `AnalysisOutputTests.swift`
- `AnalysisFilterTests.swift`
- `AnalysisCacheServiceTests.swift`
- `AnalysisSummaryModelsUsedTests.swift`
- `LoadPRDetailUseCaseTests.swift`
- `PRCommentModelUsedTests.swift`
- `TaskOutputTests.swift`
- `TaskBehaviorTests.swift`

## Phases

## - [x] Phase 1: Rename `AnalysisTaskOutput` → `RuleRequest`

**Skills to read**: `swift-app-architecture:swift-architecture`

Most widely referenced type (22+ files). Rename the type and its file.

- Rename `TaskOutput.swift` → `RuleRequest.swift`
- Find-and-replace `AnalysisTaskOutput` → `RuleRequest` across all source and test files
- Also rename the `TaskRule` sub-type's file if needed (it stays `TaskRule` but the file may need context)
- `swift build` to verify
- `swift test` to verify

## - [x] Phase 2: Rename `RuleEvaluationResult` → `RuleOutcome`

**Skills to read**: `swift-app-architecture:swift-architecture`

- Rename `RuleEvaluationResult.swift` → `RuleOutcome.swift`
- Find-and-replace `RuleEvaluationResult` → `RuleOutcome` across all source and test files
- `swift build` to verify

## - [x] Phase 3: Rename `RuleEvaluation` → `RuleFinding`

**Skills to read**: `swift-app-architecture:swift-architecture`

Must happen after Phase 2 since `RuleEvaluationResult` previously contained the substring `RuleEvaluation`.

- Rename `RuleEvaluation.swift` → `RuleFinding.swift`
- Find-and-replace `RuleEvaluation` → `RuleFinding` across all source and test files
- Update the `evaluation` property name on `EvaluationSuccess` to `finding`
- Update the `.evaluation` accessor on `RuleOutcome` (was `RuleEvaluationResult`) to `.finding`
- `swift build` to verify

## - [x] Phase 4: Rename `AnalysisOutput` → `PRReviewResult`

**Skills to read**: `swift-app-architecture:swift-architecture`

- Rename `AnalysisOutput.swift` → `PRReviewResult.swift`
- Find-and-replace `AnalysisOutput` → `PRReviewResult` across all source and test files
- `swift build` to verify

## - [x] Phase 5: Rename `AnalysisSummary` → `PRReviewSummary`

**Skills to read**: `swift-app-architecture:swift-architecture`

- Rename `AnalysisSummary.swift` → `PRReviewSummary.swift`
- Find-and-replace `AnalysisSummary` → `PRReviewSummary` across all source and test files
- `swift build` to verify

## - [x] Phase 6: Rename `AnalysisFilter` → `RuleFilter`

**Skills to read**: `swift-app-architecture:swift-architecture`

- Rename `AnalysisFilter.swift` → `RuleFilter.swift`
- Find-and-replace `AnalysisFilter` → `RuleFilter` across all source and test files
- Rename `AnalysisFilterTests.swift` → `RuleFilterTests.swift`
- `swift build` to verify

## - [x] Phase 7: Rename `EvaluationError` → `RuleError`

**Skills to read**: `swift-app-architecture:swift-architecture`

- Rename `EvaluationError.swift` → `RuleError.swift`
- Find-and-replace `EvaluationError` → `RuleError` across all source and test files
- `swift build` to verify

## - [x] Phase 8: Merge `EvaluationSuccess` + `RuleFinding` → `RuleResult`

**Skills to read**: `swift-app-architecture:swift-architecture`, `swift-testing`

Structural refactor: flatten the two-level nesting into a single `RuleResult` struct.

Current structure:
```swift
EvaluationSuccess {
    taskId, ruleName, filePath, modelUsed, durationMs, costUsd
    finding: RuleFinding { violatesRule, score, comment, filePath, lineNumber }
}
```

Target structure:
```swift
RuleResult {
    taskId, ruleName, filePath, modelUsed, durationMs, costUsd
    violatesRule, score, comment, lineNumber
}
```

Steps:
- Create `RuleResult.swift` with the merged properties
- Update `RuleOutcome` to use `.success(RuleResult)` instead of `.success(EvaluationSuccess)`
- Update `AnalysisService` where it constructs `EvaluationSuccess` + `RuleFinding` → construct `RuleResult`
- Update all callers that access `.evaluation.violatesRule`, `.evaluation.score`, etc. to access directly
- Update `PRComment.from(evaluation:task:)` signature — rename parameter from `evaluation` to `result`
- Remove `EvaluationSuccess.swift` and `RuleFinding.swift`
- No backward compatibility needed — old cached data will be deleted
- `swift build` and `swift test` to verify
- Update test helpers that construct `EvaluationSuccess` + `RuleFinding`

*Phase 9 (PRReviewRequest + dedup) and validation moved to `2026-02-21-b-pr-review-request-and-dedup.md`.*
