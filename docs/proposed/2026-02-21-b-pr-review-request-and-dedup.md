## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture rules, layer placement, code style |
| `swift-testing` | Test style guide and conventions |

## Background

This continues the analysis domain rename effort (from `2026-02-21-a-analysis-domain-rename.md`, phases 1–8 complete). Two structural improvements remain:

1. **`PRReviewRequest`** — `AnalyzeUseCase.execute()` currently takes 4 loose parameters (`prNumber`, `filter`, `repoPath`, `commitHash`). Wrapping them in a request struct improves callsite clarity and makes future parameter additions non-breaking.

2. **Deduplicate `results` array** — `PRReviewSummary.results: [RuleOutcome]` duplicates `PRReviewResult.evaluations`. The summary should be a pure stats struct; the evaluation results already live on `PRReviewResult`.

No backward compatibility is needed — old cached/output data will be deleted.

### Current Signatures

**`AnalyzeUseCase.execute()`** (`PRReviewFeature/usecases/AnalyzeUseCase.swift`):
```swift
public func execute(
    prNumber: Int,
    filter: RuleFilter? = nil,
    repoPath: String? = nil,
    commitHash: String? = nil
) -> AsyncThrowingStream<PhaseProgress<PRReviewResult>, Error>
```

Callers:
- `AnalyzeCommand` — passes all 4 parameters
- `RunPipelineUseCase` — passes `prNumber`, `repoPath`, `commitHash`
- `PRModel.runAnalyze()` — passes `prNumber`, `commitHash`
- `PRModel.runFilteredAnalysis()` — passes `prNumber`, `filter`, `commitHash`

**`PRReviewSummary`** (`PRRadarModels/PRReviewSummary.swift`):
```swift
public struct PRReviewSummary: Codable, Sendable {
    public let prNumber: Int
    public let evaluatedAt: String
    public let totalTasks: Int
    public let violationsFound: Int
    public let totalCostUsd: Double
    public let totalDurationMs: Int
    public let results: [RuleOutcome]

    public var modelsUsed: [String] {
        Array(Set(results.map(\.modelUsed))).sorted()
    }
}
```

**`PRReviewResult`** (`PRReviewFeature/models/PRReviewResult.swift`):
```swift
public struct PRReviewResult: Sendable {
    public var evaluations: [RuleOutcome]
    public var tasks: [RuleRequest]
    public var summary: PRReviewSummary
    public var cachedCount: Int
}
```

### Files Affected

**Source files:**
- `PRReviewFeature/usecases/AnalyzeUseCase.swift` — execute() signature, summary construction (5+ sites)
- `PRReviewFeature/usecases/RunPipelineUseCase.swift` — caller
- `PRReviewFeature/models/PRReviewResult.swift` — gains `modelsUsed`, construction sites pass `results: []`
- `PRRadarModels/PRReviewSummary.swift` — remove `results`, remove `modelsUsed`
- `MacApp/Models/PRModel.swift` — 2 callers (runAnalyze, runFilteredAnalysis)
- `MacCLI/Commands/AnalyzeCommand.swift` — caller, reads `output.summary.modelsUsed`
- `MacApp/UI/PhaseViews/DiffPhaseView.swift` — reads `summary.modelsUsed`
- `MacApp/UI/PhaseViews/ReportPhaseView.swift` — reads `report.summary.modelsUsed`
- `PRRadarModels/ReportOutput.swift` — reads `summary.modelsUsed`

**Test files:**
- `AnalysisOutputTests.swift` — PRReviewSummary decode/round-trip tests with `results` array
- `AnalysisSummaryModelsUsedTests.swift` — tests `modelsUsed` computed property
- `LoadPRDetailUseCaseTests.swift` — constructs PRReviewSummary with `results`
- `AnalysisCacheServiceTests.swift` — constructs PRReviewSummary with `results`

## Phases

## - [x] Phase 1: Create `PRReviewRequest` and update `AnalyzeUseCase`

**Principles applied**: Confirmed `repoPath` was unused before removing; kept init defaults for convenient construction

- Create `PRReviewRequest.swift` in `PRReviewFeature/models/`:
  ```swift
  public struct PRReviewRequest: Sendable {
      public let prNumber: Int
      public let filter: RuleFilter?
      public let commitHash: String?
  }
  ```
- Note: `repoPath` is intentionally excluded — `AnalyzeUseCase` resolves it from `config` internally. Verify that `repoPath` is not used inside `execute()` before removing. If it IS used, either keep it in `PRReviewRequest` or refactor the internal usage to use `config`.
- Update `AnalyzeUseCase.execute()` to accept `PRReviewRequest`:
  ```swift
  public func execute(
      request: PRReviewRequest
  ) -> AsyncThrowingStream<PhaseProgress<PRReviewResult>, Error>
  ```
- Update all internal references within `AnalyzeUseCase` that read `prNumber`, `filter`, `repoPath`, `commitHash` to read from `request.*`
- `swift build` to verify (callers will fail — that's expected, fixed in Phase 2)

## - [x] Phase 2: Update all callers of `AnalyzeUseCase.execute()`

**Principles applied**: Also removed unused `repoPath` from `RunPipelineUseCase.execute()` since it was only passed through

Update each caller to construct a `PRReviewRequest` and pass it:

- **`AnalyzeCommand`** (`MacCLI/Commands/AnalyzeCommand.swift`):
  ```swift
  let request = PRReviewRequest(
      prNumber: options.prNumber,
      filter: filter.isEmpty ? nil : filter,
      commitHash: options.commit
  )
  let stream = useCase.execute(request: request)
  ```
  If `repoPath` was kept in `PRReviewRequest`, include `options.repoPath` here.

- **`RunPipelineUseCase`** (`PRReviewFeature/usecases/RunPipelineUseCase.swift`):
  ```swift
  let request = PRReviewRequest(
      prNumber: prNumber,
      filter: nil,
      commitHash: commitHash
  )
  for try await progress in evalUseCase.execute(request: request) {
  ```
  If `repoPath` was kept, include it. If removed, also remove it from `RunPipelineUseCase.execute()` parameters if it was only passed through.

- **`PRModel.runAnalyze()`** (`MacApp/Models/PRModel.swift`):
  ```swift
  let request = PRReviewRequest(prNumber: prNumber, filter: nil, commitHash: currentCommitHash)
  for try await progress in useCase.execute(request: request) {
  ```

- **`PRModel.runFilteredAnalysis()`** (`MacApp/Models/PRModel.swift`):
  ```swift
  let request = PRReviewRequest(prNumber: prNumber, filter: filter, commitHash: currentCommitHash)
  for try await progress in useCase.execute(request: request) {
  ```

- `swift build` and `swift test` to verify

## - [ ] Phase 3: Remove `results` from `PRReviewSummary`

**Skills to read**: `swift-app-architecture:swift-architecture`

- Edit `PRReviewSummary.swift`: remove the `results: [RuleOutcome]` property and its init parameter
- Remove the `modelsUsed` computed property (it moves to `PRReviewResult` in Phase 4)
- Update every site that constructs `PRReviewSummary` to stop passing `results`:
  - `AnalyzeUseCase.executeFullRun()` — 2 construction sites (empty init and final output)
  - `AnalyzeUseCase.buildMergedOutput()` — 1 construction site
  - `AnalyzeUseCase.parseOutput()` — 1 construction site
  - `PRReviewResult.empty` — static constant
  - `PRReviewResult(streaming:)` — convenience init
  - `PRReviewResult.appendResult()` — rebuilds summary inline
  - `PRReviewResult.cumulative()` — builds summary
- `swift build` to verify (consumers of `modelsUsed` will fail — fixed in Phase 4)

## - [ ] Phase 4: Move `modelsUsed` to `PRReviewResult` and update consumers

**Skills to read**: `swift-app-architecture:swift-architecture`

- Add `modelsUsed` as a computed property on `PRReviewResult`:
  ```swift
  public var modelsUsed: [String] {
      Array(Set(evaluations.map(\.modelUsed))).sorted()
  }
  ```
- Update all consumers that read `summary.modelsUsed` to read from the result/output directly:
  - **`AnalyzeCommand`** (`MacCLI/Commands/AnalyzeCommand.swift`): `output.summary.modelsUsed` → `output.modelsUsed`
  - **`DiffPhaseView`** (`MacApp/UI/PhaseViews/DiffPhaseView.swift`): reads `summary.modelsUsed` — trace where `summary` comes from. It may need to read from the parent `PRReviewResult` or `PRDetail` instead.
  - **`ReportPhaseView`** (`MacApp/UI/PhaseViews/ReportPhaseView.swift`): reads `report.summary.modelsUsed` — `report` is a `ReviewReport`, which has its own `summary: ReportSummary` (different from `PRReviewSummary`). Check whether this is actually `PRReviewSummary.modelsUsed` or `ReportSummary.modelsUsed`. If it's `ReportSummary`, it's unaffected.
  - **`ReportOutput`** (`PRRadarModels/ReportOutput.swift`): reads `summary.modelsUsed` — same investigation as above, determine if this is `PRReviewSummary` or `ReportSummary`.
- `swift build` and `swift test` to verify

## - [ ] Phase 5: Update tests

**Skills to read**: `swift-testing`

- **`AnalysisOutputTests.swift`**: Update PRReviewSummary JSON decode tests — remove `"results"` from JSON fixtures, remove assertions on `summary.results`. Update round-trip test to not include `results`.
- **`AnalysisSummaryModelsUsedTests.swift`**: This entire suite tests `PRReviewSummary.modelsUsed`. Since `modelsUsed` now lives on `PRReviewResult`, rewrite these tests to construct `PRReviewResult` instances and verify `modelsUsed` there instead.
- **`LoadPRDetailUseCaseTests.swift`**: Update `PRReviewSummary` construction to remove `results` parameter.
- **`AnalysisCacheServiceTests.swift`**: Update `PRReviewSummary` construction to remove `results` parameter.
- `swift test` to verify all pass

## - [ ] Phase 6: Validation

**Skills to read**: `swift-testing`

- `swift build` — clean build succeeds
- `swift test` — all tests pass
- Verify no stale references: grep for old type names (`AnalysisTaskOutput`, `AnalysisOutput`, `RuleEvaluationResult`, `RuleEvaluation`, `AnalysisFilter`, `EvaluationSuccess`, `EvaluationError`, `AnalysisSummary`) in source and test files
- Verify `PRReviewSummary` no longer has a `results` property or `modelsUsed` computed property
- Verify JSON compatibility: run `swift run PRRadarMacCLI analyze 1 --config test-repo` against test repo to confirm pipeline still works end-to-end
