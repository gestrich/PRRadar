## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture rules — ensures changes respect layer boundaries |
| `swift-testing` | Test style guide — for updating test code |

## Background

PR numbers are integers (GitHub guarantees this), yet a significant portion of the codebase passes them as `String`. This creates:

- Unnecessary `Int(prNumber) ?? 0` and `guard let prNum = Int(prNumber)` conversions scattered across the features layer
- `String(prNumber)` conversions when services need to call into file I/O utilities
- A computed `PRModel.prNumber: String` property that wraps `metadata.number` (already `Int`)
- Fragile `.isEmpty` checks on `prNumber` that wouldn't be needed with `Int`

The domain models (`PRMetadata.number`, `GitHubPullRequest.number`) and service-layer consumers (`CommentService`, `FocusGeneratorService`, `ReportGeneratorService`, `PRAcquisitionService`) already use `Int`. The `String` type exists only in:

1. **Config/IO layer**: `DataPathsService`, `OutputFileReader`, `PhaseOutputParser`, `PhaseResultWriter`
2. **Features layer**: All use cases (`SyncPRUseCase`, `AnalyzeUseCase`, `PrepareUseCase`, etc.)
3. **Apps layer**: `CLIOptions.prNumber`, `PRModel.prNumber`, CLI commands, MacApp views

Since Swift string interpolation handles `Int` natively (`"\(prNumber)"`), there's no reason for `String` anywhere.

No backward compatibility is needed — all existing PR data will be deleted before running with the updated code.

## Phases

## - [x] Phase 1: Config and IO Layer (`PRRadarConfigService` + `PRRadarCLIService`)

**Skills to read**: `swift-app-architecture:swift-architecture`

Change `prNumber: String` → `prNumber: Int` in these files:

- **`DataPathsService.swift`** — All static methods: `metadataDirectory`, `analysisDirectory`, `phaseDirectory`, `phaseSubdirectory`, `phaseExists`, `canRunPhase`, `validateCanRun`, `phaseStatus`, `allPhaseStatuses`. String interpolation (`"\(prNumber)"`) works unchanged.
- **`OutputFileReader.swift`** — All 4 methods that take `prNumber: String`
- **`PhaseOutputParser.swift`** — All 9+ methods that take `prNumber: String`
- **`PhaseResultWriter.swift`** — All 4 methods that take `prNumber: String`

These are leaf utilities — changing them first establishes the `Int` contract that callers will adopt in later phases.

## - [x] Phase 2: Features Layer (Use Cases)

**Skills to read**: `swift-app-architecture:swift-architecture`

Change `prNumber: String` → `prNumber: Int` in all use case `execute()` and `parseOutput()` signatures:

- **`SyncPRUseCase`** — `execute(prNumber:)`, `parseOutput(config:prNumber:)`, `resolveCommitHash(config:prNumber:)`. Remove the `guard let prNum = Int(prNumber)` conversion inside `execute`.
- **`PrepareUseCase`** — `execute(prNumber:)`, `parseOutput(config:prNumber:)`. Remove `guard let prNum = Int(prNumber)`.
- **`AnalyzeUseCase`** — `execute(prNumber:)`, `parseOutput(config:prNumber:)`, `cumulative(...)`. Remove all `Int(prNumber) ?? 0` conversions.
- **`SelectiveAnalyzeUseCase`** — `execute(prNumber:)`, `loadExistingEvaluations(...)`, private helpers. Remove `Int(prNumber) ?? 0`.
- **`GenerateReportUseCase`** — `execute(prNumber:)`, `parseOutput(config:prNumber:)`. Remove `guard let prNum = Int(prNumber)`.
- **`PostCommentsUseCase`** — `execute(prNumber:)`. Remove `guard let prNum = Int(prNumber)`.
- **`PostSingleCommentUseCase`** — `execute(prNumber:)`. Remove `guard let prNum = Int(prNumber)`.
- **`FetchReviewCommentsUseCase`** — `execute(prNumber:)`.
- **`LoadPRDetailUseCase`** — `execute(prNumber:)` and private helpers.
- **`RunPipelineUseCase`** — `execute(prNumber:)`.
- **`DeletePRDataUseCase`** — Already uses `Int`! But calls `syncUseCase.execute(prNumber: String(prNumber))` — remove the `String()` wrapper once SyncPRUseCase is updated.

Also update `FetchPRListUseCase` which does `prNumber: String(pr.number)` — change to just `pr.number`.

## - [x] Phase 3: Apps Layer (CLI + MacApp)

**Skills to read**: `swift-app-architecture:swift-architecture`

**CLI**:
- **`CLIOptions`** in `PRRadarMacCLI.swift` — Change `var prNumber: String` to `var prNumber: Int`. Swift ArgumentParser natively supports `Int` arguments.
- **`StatusCommand.swift`** — `listAvailableCommits(outputDir:prNumber:)` param from `String` to `Int`. Update the path construction inside.
- All other CLI commands (`SyncCommand`, `PrepareCommand`, `AnalyzeCommand`, `ReportCommand`, `CommentCommand`, `RunCommand`, `RefreshPRCommand`, `TranscriptCommand`) — these pass `options.prNumber` to use cases, which will now accept `Int` with no further changes needed.

**MacApp**:
- **`PRModel.prNumber`** — Change from `var prNumber: String { String(metadata.number) }` to `var prNumber: Int { metadata.number }`.
- **Views that use `prNumber`**: Update string interpolation and remove `.isEmpty` checks:
  - `ContentView.swift`: `pr.prNumber.isEmpty` → use `metadata.number` or a different check (e.g., always enabled since we have a valid `PRModel`).
  - `PhaseInputView.swift`: `!prModel.prNumber.isEmpty` → remove or replace.
  - String interpolation like `"PR #\(pr.prNumber)"` works unchanged with `Int`.
- **`AllPRsModel.swift`** — `prModel.metadata.number` call already uses `Int`; `pr.prNumber` in the log string works fine as `Int`.

## - [x] Phase 4: Tests

**Skills to read**: `swift-testing`

- **`LoadPRDetailUseCaseTests.swift`** — Change `setupFullPR(outputDir:prNumber:commitHash:)` param from `String` to `Int`.
- Search for any other test files that pass `prNumber` as a string literal and update.
- Ensure all tests compile and pass.

## - [x] Phase 5: Validation

Build and run the full test suite:

```bash
cd PRRadarLibrary
swift build
swift test
```

Grep for any remaining `prNumber.*String` or `String(prNumber)` or `Int(prNumber)` patterns to confirm none were missed.

## Technical Notes

All 5 phases were completed atomically — the type change cascades through all layers since changing the leaf utilities breaks callers immediately. Key changes beyond the spec:

- **`PRAcquisitionService`** — Removed `let prNumberStr = String(prNumber)` intermediate; passes `prNumber: Int` directly.
- **`PRDiscoveryService`** — Updated `metadataDirectory` call to use `prNumber` (Int, already parsed from directory name) instead of `dirName` (String).
- **`RunAllUseCase`** — Changed `let prNumber = String(pr.number)` to `let prNumber = pr.number`.
- **`ContentView.swift` / `PhaseInputView.swift`** — Removed `.isEmpty` checks on `prNumber` (not meaningful for Int). These guards were redundant since a valid `PRModel` always has a valid PR number.
- **`ContentView.swift`** — Fixed optional Int interpolation: `selectedPR.map { "\($0.prNumber)" } ?? ""`.
- **488 tests pass**, zero remaining `prNumber: String`, `String(prNumber)`, or `Int(prNumber)` patterns.
