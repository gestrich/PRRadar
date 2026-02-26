## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules, layer responsibilities, dependency rules |
| `/swift-testing` | Test style guide |

## Background

The task-operation-lifecycle spec introduced `TaskEvaluation` in the app layer (`MacApp/Models/`) and `LiveTranscriptAccumulator` as a nested struct in `PRModel.swift`. These types are not inherently app-layer concerns — streaming AI output applies equally to the CLI, and `TaskEvaluation` as a "request + outcome" pair is a natural services-layer concept.

Meanwhile, `PRReviewResult` (features layer) stores evaluations and tasks as parallel arrays (`evaluations: [RuleOutcome]` + `tasks: [RuleRequest]`) that must be joined by `taskId`. This join appears in:
- `comments` computed property: builds `taskMap` dictionary, looks up each `RuleOutcome.taskId`
- `appendResult`: finds existing evaluation index by `taskId`
- `ReportGeneratorService.loadViolations`: builds separate `taskMetadata` dictionary, joins by `taskId`

By moving `TaskEvaluation` to the services layer and adopting it in `PRReviewResult`, each task's request and outcome live together — no joining needed.

### Scope

- Move `LiveTranscriptAccumulator` and `TaskEvaluation` to `PRRadarModels/`
- Replace `PRReviewResult`'s `evaluations: [RuleOutcome]` + `tasks: [RuleRequest]` with `taskEvaluations: [TaskEvaluation]`
- Update `AnalyzeUseCase`, `AnalyzeCommand`, `PRModel`, and `ReportGeneratorService`

### What stays unchanged

- `RuleOutcome`, `RuleRequest`, `RuleResult`, `RuleError` — domain types untouched
- `TaskProgress` — streaming events untouched
- `AnalyzeSingleTaskUseCase` — produces `TaskProgress` stream, not `PRReviewResult`
- On-disk format — JSON files for evaluations and tasks remain separate; only in-memory representation changes

## Phases

## - [x] Phase 1: Extract `LiveTranscriptAccumulator` to PRRadarModels

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Moved streaming transcript accumulator from app layer to services layer (PRRadarModels) where it belongs as a domain type. Made public and Sendable per architecture conventions.

**Skills to read**: `/swift-app-architecture:swift-architecture`

Move `LiveTranscriptAccumulator` from its current location as a nested struct in `PRModel.swift` to `PRRadarModels/Transcripts/LiveTranscriptAccumulator.swift` (or an appropriate location within PRRadarModels).

1. Create `PRRadarModels/Transcripts/LiveTranscriptAccumulator.swift` with the struct extracted from `PRModel.swift:725-760`. Make it `public` and `Sendable`.
2. Remove the nested `struct LiveTranscriptAccumulator` from `PRModel.swift`.
3. Update `PRModel.swift` references — remove the `PRModel.` prefix from type annotations (the type is now top-level).
4. Update `TaskEvaluation.swift` — change `PRModel.LiveTranscriptAccumulator` to just `LiveTranscriptAccumulator`. Remove the explicit type annotation in the `transcript` computed property.

Verify build succeeds. No behavioral change.

## - [ ] Phase 2: Move `TaskEvaluation` to PRRadarModels

**Skills to read**: `/swift-app-architecture:swift-architecture`

Move `TaskEvaluation` from `MacApp/Models/TaskEvaluation.swift` to `PRRadarModels/Evaluations/TaskEvaluation.swift`.

1. Move the file and make the struct `public` and `Sendable`.
2. All fields (`request`, `phase`, `accumulator`, `savedTranscript`, `outcome`) and computed properties (`isStreaming`, `isComplete`, `isQueued`, `transcript`) become `public`.
3. Make `accumulator`, `savedTranscript`, and `outcome` setters `public` (they're mutated by PRModel).
4. Remove the old file from `MacApp/Models/`.
5. Update imports in `PRModel.swift` if needed (PRRadarModels is likely already imported).

Verify build succeeds. No behavioral change.

## - [ ] Phase 3: Refactor `PRReviewResult` to hold `[TaskEvaluation]`

**Skills to read**: `/swift-app-architecture:swift-architecture`

Replace the parallel arrays in `PRReviewResult` with a single `[TaskEvaluation]` array.

1. **Change stored properties**:
   ```swift
   // Before
   public var evaluations: [RuleOutcome]
   public var tasks: [RuleRequest]

   // After
   public var taskEvaluations: [TaskEvaluation]
   ```

2. **Update initializers**:
   - `init(streaming:)` — create `TaskEvaluation` per task with nil outcome
   - Replace `init(evaluations:tasks:summary:cachedCount:)` with a `taskEvaluations`-based initializer (or migrate all call sites in this phase so the legacy initializer can be deleted immediately)

3. **Simplify `comments`** — no more `taskMap` dictionary:
   ```swift
   public var comments: [PRComment] {
       taskEvaluations.compactMap { eval in
           eval.outcome?.violationComment(task: eval.request)
       }
   }
   ```

4. **Simplify `appendResult`** — find by `taskEvaluation.request.taskId`:
   ```swift
   public mutating func appendResult(_ result: RuleOutcome, prNumber: Int) {
       if let idx = taskEvaluations.firstIndex(where: { $0.request.taskId == result.taskId }) {
           taskEvaluations[idx].outcome = result
       } else {
           taskEvaluations.append(TaskEvaluation(request: ..., phase: .analyze, outcome: result))
       }
       // summary recalculation uses taskEvaluations.compactMap(\.outcome)
   }
   ```
   Note: the `else` branch needs a `RuleRequest` which may not be available for truly unknown taskIds. Check if this case actually occurs — if not, drop the else branch.

5. **Update `cumulative`** — takes `[RuleOutcome]` + `[RuleRequest]`, joins them into `[TaskEvaluation]`.

6. **Update `modelsUsed`** — derive from `taskEvaluations.compactMap(\.outcome)` (or equivalent helper).

7. **Update `empty` static** — use empty `taskEvaluations`.

This phase is intentionally source-breaking: compile errors from `evaluations`/`tasks` access should be fixed to use `taskEvaluations` in Phases 4-5.

## - [ ] Phase 4: Update `AnalyzeUseCase` to produce `TaskEvaluation` arrays

Update `AnalyzeUseCase` to construct `[TaskEvaluation]` directly instead of maintaining separate `[RuleOutcome]` + `[RuleRequest]` arrays.

1. **`executeFullRun`**: After collecting `allResults` and `allTasks`, build `[TaskEvaluation]` by joining outcomes to tasks, then pass to `PRReviewResult`.

2. **`buildMergedOutput`**: Same pattern — read evaluations from disk, read tasks from disk, join into `[TaskEvaluation]`.

3. **`parseOutput`**: Same — join evaluations and tasks into `[TaskEvaluation]`.

4. **`cumulative`**: If still needed, update to produce `[TaskEvaluation]`.

5. **Update `PRDetail` construction** in `LoadPRDetailUseCase` — ensure `analysis` field is built correctly.

Verify build succeeds after this phase.

## - [ ] Phase 5: Update CLI and app consumers

1. **`AnalyzeCommand`**:
   - Replace `output.evaluations.compactMap(\.violation)` with `output.taskEvaluations.compactMap { $0.outcome?.violation }`
   - Replace `output.evaluations.compactMap(\.error)` with `output.taskEvaluations.compactMap { $0.outcome?.error }`
   - Verify all accesses still compile

2. **`PRModel`**:
   - `inProgressAnalysis?.appendResult(result, prNumber: prNumber)` — already updated in Phase 3
   - `PRReviewResult(streaming: tasks)` calls — already updated in Phase 3
   - `applyDetail` — update logic that currently combines `preparation?.tasks` + `analysis?.evaluations` to use `analysis?.taskEvaluations` (or map from it)
   - Check if any view code references removed `analysis?.tasks` or `analysis?.evaluations` APIs

3. **`ReportGeneratorService`**:
   - Currently reads evaluation JSON files + task JSON files from disk independently, joins by taskId
   - This service reads from disk (not from `PRReviewResult`), so it's **not affected** by the PRReviewResult refactor
   - No changes needed here

4. **Test files**: Update any tests that construct `PRReviewResult` with the old initializer pattern.

## - [ ] Phase 6: Validation

**Skills to read**: `/swift-testing`

- Run `swift build` and fix any compilation errors
- Run `swift test` and verify all existing tests pass
- Grep for remaining references to the old `PRReviewResult` initializer patterns (`evaluations:.*tasks:` in init calls) — should all use the new form
- Grep for remaining `analysis?.evaluations`, `analysis?.tasks`, and `output.evaluations` call sites — should all be migrated
- Verify no circular dependencies between layers (PRRadarModels should have no imports of services/features/apps)
