## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-testing` | Test style guide and conventions |
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules |

## Background

The pipeline writes all phase outputs into `<output>/<prNumber>/phase-N-*/`. When a re-run produces different tasks than a prior run, stale files survive and get picked up by downstream phases — causing phantom violations in reports posted to GitHub.

Root cause investigation: [2026-02-10-c-stale-evaluation-line-numbers.md](../completed/2026-02-10-c-stale-evaluation-line-numbers.md)

### New approach: commit-scoped analysis directories

Instead of cleaning up stale files, isolate each analysis run by the PR's head commit hash. PR-level metadata (comments, description, repo info) lives separately since it's not commit-specific.

### Current structure

```
<output>/<prNumber>/
├── phase-1-sync/          # Mix of PR metadata + commit-specific diff
├── phase-2-prepare/
├── phase-3-analyze/       # Stale files accumulate here
└── phase-4-report/
```

### Proposed structure

```
<output>/<prNumber>/
├── metadata/              # PR-level (not commit-specific)
│   ├── gh-pr.json
│   ├── gh-comments.json
│   ├── gh-repo.json
│   ├── images/
│   └── image-url-map.json
└── analysis/
    ├── abc1234/           # Commit-scoped snapshot
    │   ├── diff/
    │   │   ├── diff-raw.diff
    │   │   ├── diff-parsed.json
    │   │   ├── diff-parsed.md
    │   │   ├── effective-diff-parsed.json
    │   │   ├── effective-diff-parsed.md
    │   │   └── effective-diff-moves.json
    │   ├── prepare/
    │   │   ├── focus-areas/
    │   │   ├── rules/
    │   │   └── tasks/
    │   ├── evaluate/
    │   │   ├── data-<taskId>.json
    │   │   ├── task-<taskId>.json
    │   │   ├── summary.json
    │   │   └── ai-transcript-*
    │   └── report/
    │       ├── summary.json
    │       └── summary.md
    └── def5678/           # New commit = new directory
        └── ...
```

**Why this works:**
- Stale files can't pollute new runs — each commit is isolated
- History is preserved — compare results across commits
- PR metadata is fetched once and shared across commits
- Caching still works — look at previous commit dirs for matching blob hashes

### Key design decisions

**Sync splits into two writes.** `PRAcquisitionService` fetches PR metadata first (gets `headRefOid`), writes to `metadata/`, then writes diff artifacts to `analysis/<commit>/diff/`.

**Phase enum changes.** `PRRadarPhase` gains a `.metadata` case and renames `.sync` → `.diff`. The metadata phase is PR-scoped; diff/prepare/analyze/report are commit-scoped.

**Dual blob hash caching.** Each `AnalysisTaskOutput` stores two blob hashes: `gitBlobHash` (source file) and `ruleBlobHash` (rule file). Both are computed via `git ls-tree <commit>:<path>`. A cached evaluation is only valid if both hashes match — a changed source file OR a changed rule file invalidates the cache. Rules live in the repo, so they have commit hashes just like source code. For rules loaded from an external directory (not the PR repo), fall back to a content hash (SHA256).

**Cross-commit caching.** `AnalysisCacheService` scans `analysis/*/evaluate/` for prior results with matching blob hashes. A file unchanged between commits reuses its cached evaluation. Cached `data-<taskId>.json` files are copied into the new commit's evaluate dir so each commit dir is self-contained.

**Same-commit re-run.** Wipe the commit directory and start fresh. Same commit = same diff, so nothing is lost. (Rules may have changed, which is why you're re-running.)

**Short commit hash (7 chars) for directory names.** Readable in file browsers, standard git convention. Full hash stored in the diff JSON files.

### Open questions

1. **`phase_result.json` placement** — One per subdirectory (diff/, prepare/, evaluate/, report/) or one per commit directory?
2. **Metadata staleness** — PR metadata (comments, description) can change independently. Re-fetch on every `analyze` run, or only on explicit `sync`?
3. **Pruning old commits** — Add a `prune` command? Keep last N? Leave to user?

---

## - [x] Phase 1: Update `DataPathsService` path construction

**Skills to read**: `/swift-app-architecture:swift-architecture`

Update `DataPathsService` to support the new directory structure:

- Add `commitHash` parameter to `phaseDirectory()` for commit-scoped phases
- Add `metadataDirectory(outputDir:prNumber:)` for PR-level metadata
- Add `analysisDirectory(outputDir:prNumber:commitHash:)` for commit root
- Update `phaseExists`, `canRunPhase`, `phaseStatus` to handle both PR-scoped and commit-scoped phases
- Update or add a new case to `PRRadarPhase`: `.metadata` (PR-scoped), rename `.sync` → `.diff`

**Technical notes:**
- `PRRadarPhase` raw values changed: `metadata`, `diff`, `prepare`, `evaluate`, `report`
- `.metadata` and `.diff` are both independent roots (no required predecessor) — `.diff` doesn't depend on `.metadata` for backward compatibility during migration
- `phaseDirectory()` falls back to legacy flat layout (`<output>/<prNumber>/<phase>/`) when `commitHash` is nil, allowing incremental migration
- `OutputFileReader` and `PhaseOutputParser` pass through the optional `commitHash` parameter
- All switch statements on `PRRadarPhase` updated to include `.metadata` case
- `PRDiscoveryService` updated to read `gh-pr.json` from `metadata/` directory
- 381 tests pass, including new tests for `metadataDirectory`, `analysisDirectory`, commit-scoped paths, and legacy fallback

## - [x] Phase 2: Split sync phase writes

**Skills to read**: `/swift-app-architecture:swift-architecture`

Update `PRAcquisitionService.acquire()`:
- Fetch PR metadata first → extract `headRefOid` → this determines the commit directory
- Write PR metadata files (`gh-pr.json`, `gh-comments.json`, `gh-repo.json`, images) to `metadata/`
- Write diff files to `analysis/<commit>/diff/`
- Return commit hash in `AcquisitionResult` so downstream phases can use it

Update `SyncPRUseCase` to pass commit hash through its output.

**Technical notes:**
- `PRAcquisitionService.acquire()` now writes in two passes: metadata files to `metadata/` with a `.metadata` phase result, then diff artifacts to `analysis/<commit>/diff/` with a `.diff` phase result
- `AcquisitionResult` gains a `commitHash: String` field (7-char short hash)
- `SyncSnapshot` gains an optional `commitHash: String?` field, populated from `AcquisitionResult` during `execute()` or resolved from `metadata/gh-pr.json` during `parseOutput()`
- `SyncPRUseCase.resolveCommitHash()` reads `headRefOid` from `metadata/gh-pr.json`, falling back to scanning `analysis/` for the latest directory
- `PhaseResultWriter` accepts optional `commitHash` parameter, forwarded to `DataPathsService.phaseDirectory()`
- `PhaseOutputParser` and `OutputFileReader` already accepted optional `commitHash` (from Phase 1); all overloads now consistently pass it through
- `FetchReviewCommentsUseCase` updated to read `gh-comments.json` from `.metadata` instead of `.diff`
- 381 tests pass, build succeeds

## - [x] Phase 3: Add `ruleBlobHash` to task creation

**Skills to read**: `/swift-app-architecture:swift-architecture`

Update `AnalysisTaskOutput` and `TaskCreatorService`:
- Add `ruleBlobHash` field to `AnalysisTaskOutput`
- In `TaskCreatorService`, compute the rule file's blob hash via `GitOperationsService.getBlobHash(commit:filePath:)` when creating each task
- For rules from external directories (not in the PR repo), compute SHA256 of the file content as fallback

**Technical notes:**
- `AnalysisTaskOutput.ruleBlobHash` is `String?` (optional) for backward compatibility — existing JSON without `rule_blob_hash` decodes as `nil`
- `TaskCreatorService.createTasks()` and `createAndWriteTasks()` accept an optional `rulesDir` parameter for rule blob hash resolution
- Rule blob hash resolution strategy: if the rules directory is a git repo, uses `git rev-parse HEAD:<relativePath>` to get the blob hash; otherwise falls back to SHA256 content hash via CryptoKit
- `resolveRulesRepoInfo()` checks once per task creation batch whether the rules dir is a git repo and resolves its root path
- Rule blob hashes are cached per rule file path (same as source file blob hashes) to avoid redundant git/hash calls
- `PrepareUseCase` passes `rulesDir` through to `TaskCreatorService.createAndWriteTasks()`
- 384 tests pass, including 3 new tests for `ruleBlobHash` decode, backward compatibility, and factory method

## - [x] Phase 4: Update prepare/analyze/report use cases

**Skills to read**: `/swift-app-architecture:swift-architecture`

Thread `commitHash` through all commit-scoped use cases:
- `PrepareUseCase` — reads diff from `analysis/<commit>/diff/`, writes to `analysis/<commit>/prepare/`
- `AnalyzeUseCase` — reads tasks from `prepare/`, writes to `analysis/<commit>/evaluate/`
- `GenerateReportUseCase` — reads evaluations from `evaluate/`, writes to `analysis/<commit>/report/`
- `SelectiveAnalyzeUseCase` — same commit directory, selective within it
- `PostCommentsUseCase` — reads report from commit dir, reads PR metadata from `metadata/`

Each use case currently gets `outputDir` + `prNumber` and calls `DataPathsService.phaseDirectory()`. Add `commitHash` parameter.

**Technical notes:**
- `SyncPRUseCase.resolveCommitHash()` promoted from `private` to `public` so all use cases can resolve the commit hash when not explicitly provided
- Every use case's `execute()` and `parseOutput()` methods gain an optional `commitHash: String? = nil` parameter; if nil, they resolve it via `SyncPRUseCase.resolveCommitHash()`
- `AnalysisService.runBatchAnalysis()` parameter changed from `outputDir` + `transcriptDir` to a single `evalsDir` — callers now pass the commit-scoped evaluate directory directly
- `TaskCreatorService.createAndWriteTasks()` `outputDir` parameter now receives the prepare phase directory instead of the PR output directory; tasks subdirectory construction simplified accordingly
- `ReportGeneratorService.generateReport()` changed from single `outputDir` parameter to explicit `evalsDir`, `tasksDir`, `focusAreasDir` — callers construct these paths via `DataPathsService`
- `ReportGeneratorService.saveReport()` parameter renamed from `outputDir` to `reportDir` — callers pass the commit-scoped report directory
- `FetchReviewCommentsUseCase.execute()` gains `commitHash` parameter, uses `DataPathsService` for evaluate/tasks paths (already reads comments from `.metadata`)
- `PostCommentsUseCase.execute()` gains `commitHash` parameter, forwarded to `FetchReviewCommentsUseCase`
- `LoadExistingOutputsUseCase` unchanged — all `parseOutput()` calls already work with default `nil` commitHash (auto-resolved internally)
- All existing callers compile without changes due to default parameter values
- 384 tests pass, build succeeds

## - [x] Phase 5: Cross-commit caching

**Skills to read**: `/swift-app-architecture:swift-architecture`

Update `AnalysisCacheService.partitionTasks()`:
- Accept an optional `previousEvalsDir` parameter (path to a prior commit's evaluate directory)
- On a fresh commit: scan `analysis/*/evaluate/` to find the most recent prior commit dir with results
- Compare **both** `gitBlobHash` and `ruleBlobHash` — a changed source file OR a changed rule invalidates the cache
- Copy reused `data-<taskId>.json` into the new commit's evaluate dir (so each commit dir is self-contained)

**Technical notes:**
- `partitionTasks()` gains an optional `prOutputDir: String?` parameter; when provided, enables cross-commit cache scanning
- Cache lookup is two-tier: same-commit first (existing `evalsDir`), then cross-commit (`analysis/*/evaluate/` sorted by modification date, most recent first)
- `blobHashesMatch()` compares both `gitBlobHash` and `ruleBlobHash` — `nil == nil` is treated as a match for backward compatibility
- `findPriorEvalsDirs()` discovers prior commit evaluate directories, excludes the current commit's directory
- `lookupCrossCommitResult()` copies both `data-<taskId>.json` and `task-<taskId>.json` into the target evaluate directory so each commit dir is self-contained
- `AnalyzeUseCase` and `SelectiveAnalyzeUseCase` pass `prOutputDir` to `partitionTasks()` for cross-commit caching
- Default parameter (`prOutputDir: nil`) preserves backward compatibility for all existing callers
- 393 tests pass across 45 suites, including 12 new tests for dual blob hash checking, cross-commit cache hits/misses, file copying, and directory discovery

## - [x] Phase 6: Update `RunPipelineUseCase` orchestration

**Skills to read**: `/swift-app-architecture:swift-architecture`

Update `RunPipelineUseCase.execute()`:
- Sync phase returns commit hash
- Pass commit hash to prepare → analyze → report
- Phase dependency checking uses commit-scoped paths
- Output file collection uses new directory structure

**Technical notes:**
- `RunPipelineUseCase.execute()` now captures `SyncSnapshot` from the sync phase's `.completed(output:)` event instead of a bare `diffCompleted` boolean
- `commitHash` (type `String?`) extracted from `syncOutput.commitHash` and explicitly threaded to all downstream use cases: `PrepareUseCase`, `AnalyzeUseCase`, `GenerateReportUseCase`, and `PostCommentsUseCase`
- `OutputFileReader.files()` in the file collection loop now receives `commitHash` so it reads from commit-scoped directories
- Previously, each use case independently resolved the commit hash via `SyncPRUseCase.resolveCommitHash()` — now the pipeline passes it explicitly, avoiding redundant disk reads and ensuring all phases operate on the same commit
- `RunAllUseCase` unchanged — it delegates to `RunPipelineUseCase` which handles commit hash internally
- No API changes to `RunPipelineUseCase.execute()` — all callers (`RunCommand`, `RunAllUseCase`) compile without changes
- 393 tests pass across 45 suites, build succeeds

## - [x] Phase 7: Update CLI commands

**Skills to read**: `/swift-app-architecture:swift-architecture`

Update individual CLI commands (`DiffCommand`, `RulesCommand`, `EvaluateCommand`, `ReportCommand`, `StatusCommand`, `CommentCommand`):
- Commands that run a single phase need to resolve the commit hash (from latest metadata/gh-pr.json or a `--commit` flag)
- `StatusCommand` — show status for latest commit, list available commits
- `AnalyzeCommand` — full pipeline, gets commit hash from sync output

**Technical notes:**
- `CLIOptions` gains a `--commit` option (`String?`) available to all commands that use `@OptionGroup var options: CLIOptions`
- `SyncCommand` now captures and displays the commit hash from `SyncSnapshot`, and passes it to `DataPathsService.phaseDirectory()` for `--open`; JSON output includes `commitHash` field
- `PrepareCommand`, `AnalyzeCommand`, `ReportCommand`, `CommentCommand` all forward `options.commit` to their respective use case `execute()` calls; when nil, use cases auto-resolve via `SyncPRUseCase.resolveCommitHash()`
- `StatusCommand` resolves commit hash via `options.commit ?? SyncPRUseCase.resolveCommitHash()`, passes it to `allPhaseStatuses()`, displays `@ <commitHash>` in header, and lists all available commits when more than one exists; JSON output restructured to include `commitHash`, `availableCommits`, and `phases` fields
- `TranscriptCommand` resolves commit hash and passes it to `listPhaseFiles()` and `readPhaseFile()` so transcripts are read from the correct commit-scoped directory
- `RunCommand` unchanged — `RunPipelineUseCase` already threads commit hash internally (Phase 6)
- `RunAllCommand`, `RefreshCommand` don't use `CLIOptions` so unaffected; `RefreshPRCommand` uses `CLIOptions` but syncs fresh (commit is determined by sync)
- 393 tests pass across 45 suites, build succeeds

## - [x] Phase 8: Update Mac app

**Skills to read**: `/swift-app-architecture:swift-architecture`

Update `PRModel` and related views:
- `LoadExistingOutputsUseCase` — resolve which commit directory to load (latest by default)
- `PRModel` — track current commit hash, enable switching between commits
- Phase views — no structural changes needed (they render the same data, just from a different path)

**Technical notes:**
- `LoadExistingOutputsUseCase.execute()` gains optional `commitHash: String?` parameter; resolves commit hash once and passes it to all `parseOutput` calls
- `PRModel` gains `currentCommitHash: String?` and `availableCommits: [String]` properties
- `currentCommitHash` is resolved on first `loadDetail()` via `SyncPRUseCase.resolveCommitHash()` and updated when sync completes with a new commit
- `switchToCommit(_ commitHash:)` clears all cached phase data and reloads from the new commit directory
- `refreshAvailableCommits()` scans `analysis/` for commit directories
- All use case calls (`PrepareUseCase`, `AnalyzeUseCase`, `GenerateReportUseCase`, `PostCommentsUseCase`, `SelectiveAnalyzeUseCase`) now receive `currentCommitHash`
- `loadPhaseStates()`, `loadSavedTranscripts()`, `loadCachedDiff()`, `loadCachedNonDiffOutputs()`, `loadAnalysisSummary()` all pass `currentCommitHash` through
- PR-scoped files (`gh-comments.json`, `image-url-map.json`) read from `.metadata` phase instead of `.diff`
- `ReviewDetailView` adds a commit picker (Picker with `.menu` style) in the diff toolbar when multiple commits exist; single commit shown as monospaced text label
- 393 tests pass across 45 suites, build succeeds

## - [ ] Phase 9: Tests and validation

**Skills to read**: `/swift-testing`

Unit tests:
- `DataPathsService` path construction for metadata vs commit-scoped directories
- `AnalysisCacheService` cross-commit cache lookup
- Phase status checking with commit-scoped paths

Integration validation:
```bash
cd pr-radar-mac
swift build && swift test
swift run PRRadarMacCLI analyze 1 --config test-repo
```

Confirm:
- Output lands in `<output>/1/metadata/` and `<output>/1/analysis/<commit>/`
- A second run on the same commit reuses cache
- A run after a PR update creates a new commit directory with cross-commit cache hits
