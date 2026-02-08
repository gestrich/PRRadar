## Background

PRRadar currently has a **dual-language architecture**: a Python CLI (`prradar/`) that contains all business logic and pipeline orchestration, and a Swift Mac app (`pr-radar-mac/`) that acts as a thin client invoking the Python CLI and parsing its JSON output. This architecture is unnecessarily complex — every feature must be implemented twice (Python logic + Swift bindings), the Swift app depends on a Python virtual environment at runtime, and the bridge layer (`PRRadarCLIService`, `PRRadarMacSDK`) exists solely to shuttle data between the two languages.

**Goal:** Rewrite the entire app in Swift. The Python app (`prradar/`, `tests/`, `pyproject.toml`, `agent.sh`) will be deleted. All business logic will live natively in the Swift package.

**What stays in Python:** Only the Claude Agent SDK bridge — a minimal Python script that wraps the two `query()` call sites (focus generation and rule evaluation). This is necessary because the Claude Agent SDK is Python-only. The script will be invoked from Swift via `SwiftCLI` (the same `CLIClient` mechanism already used).

**What uses Foundation:** All file I/O (reading/writing JSON, markdown, diff files, directory scanning).

**What uses SwiftCLI:** All external CLI tools — `git` operations, `gh` CLI operations, and the Claude Agent SDK Python bridge — are invoked uniformly via SwiftCLI's `@CLIProgram`/`CLIClient` pattern.

**No backwards compatibility required.** This is a clean rewrite. Old APIs, dead code, unused types, and Python-era shims should be removed outright — not deprecated, not re-exported, not kept behind flags. If a type or method only existed to bridge Python CLI output, delete it or reshape it for native use. There are no external consumers of these APIs.

**Both targets must build at every phase.** The Swift package has two executable targets — `MacApp` (SwiftUI GUI) and `PRRadarMacCLI` (command-line). Both must compile successfully (`swift build`) after every phase. If a phase changes shared code (models, services, features), verify both targets still build before considering the phase complete.

**Verification:** All phases can be verified by running against PR #1 in the test repo at `/Users/bill/Developer/personal/PRRadar-TestRepo` as described in `.claude/commands/pr-radar-verify-work.md`.

### Architecture Reference (REQUIRED before each phase)

Before starting **every phase**, read the architecture documentation at [`https://github.com/gestrich/swift-app-architecture/tree/main/docs/architecture`](https://github.com/gestrich/swift-app-architecture/tree/main/docs/architecture). The following documents define the conventions all Swift code must follow:

| Document | Governs |
|---|---|
| `ARCHITECTURE.md` | Overall system design and layer overview |
| `Layers.md` | SDKs → Services → Features → Apps layer rules and dependency directions |
| `Dependencies.md` | How to declare and manage inter-target dependencies |
| `FeatureStructure.md` | How to structure Feature targets (use cases, models) |
| `Principles.md` | Core design principles (single responsibility, protocol-based, etc.) |
| `Configuration.md` | How configuration and environment setup works |
| `Examples.md` | Reference implementations showing correct patterns |
| `QuickReference.md` | Cheat sheet for common decisions |
| `code-style.md` | Naming conventions, formatting, Swift idioms |
| `swift-ui.md` | SwiftUI patterns (observable models, view structure, state) |
| `documentation.md` | Documentation expectations |

Every new file and every modification must conform to these documents. When in doubt about where code belongs (which layer/target), what a type should look like, or how dependencies should flow, consult the relevant doc **before writing code**.

### Current Python Module Inventory (to be ported)

| Python Module | Lines | Claude SDK? | Port Strategy |
|---|---|---|---|
| `domain/diff.py` (GitDiff parser) | ~530 | No | Swift already has `GitDiff` in `PRRadarModels` — verify parity, extend if needed |
| `infrastructure/effective_diff.py` | ~867 | No | Full port to Swift (pure computation + one `git diff --no-index` subprocess call) |
| `domain/rule.py` (YAML frontmatter + patterns) | ~382 | No | Port to Swift using Foundation + a YAML library or manual parsing |
| `domain/focus_area.py` | ~120 | No | Port to Swift |
| `domain/agent_outputs.py` (structured output schemas) | ~150 | No | Already partially exists in `PRRadarModels` |
| `services/phase_sequencer.py` | ~495 | No | Port to Swift using Foundation file operations |
| `services/rule_loader.py` | ~200 | No | Port to Swift |
| `services/focus_generator.py` | ~160 | **Yes** (Haiku) | Claude SDK bridge call |
| `services/evaluation_service.py` | ~200 | **Yes** (Sonnet) | Claude SDK bridge call |
| `services/report_generator.py` | ~285 | No | Port to Swift |
| `services/violation_service.py` | ~50 | No | Port to Swift |
| `services/git_operations.py` | ~100 | No | SwiftCLI git bindings |
| `infrastructure/github/runner.py` | ~150 | No | SwiftCLI gh bindings |
| `infrastructure/github/comment_service.py` | ~200 | No | Port to Swift using gh bindings |
| `commands/agent/*.py` (CLI commands) | ~800 | No | Replace existing Swift CLI commands to call native services |

## Phases

## - [x] Phase 1: SDK Layer — Git, GitHub, and Claude Agent Bindings

> **Completed.** All three SDK bindings created and both targets build.

### What was implemented:

**GitCLI** (`pr-radar-mac/Sources/sdks/PRRadarMacSDK/GitCLI.swift`):
- `@CLIProgram("git")` with commands: `Status`, `Fetch`, `Checkout`, `Clean`, `Diff`, `Show`, `RevParse`, `Remote`
- `Clean` and `Remote` use `@Positional public var args: [String]` for flexible argument composition (e.g., `git clean -ffd`)
- `Diff` uses flags for `--no-index` and `--no-color`, plus `@Positional args: [String]` for the diff range or file paths
- `RevParse` uses flags for `--git-dir`, `--show-toplevel`, `--abbrev-ref` plus optional positional ref
- Working directory is handled by `CLIClient.execute(_:workingDirectory:)`, not by `-C` flag in the command

**GhCLI** (`pr-radar-mac/Sources/sdks/PRRadarMacSDK/GhCLI.swift`):
- `@CLIProgram("gh")` with nested subcommands: `Pr.Diff`, `Pr.View`, `Pr.List`, `Repo.View`, `Api`
- `Api` command supports `-X` method, `--jq` filter, `-H` headers, `-f` string fields, `-F` raw fields (all as arrays for repeated flags)

**ClaudeBridge** (`pr-radar-mac/Sources/sdks/PRRadarMacSDK/ClaudeBridge.swift`):
- `@CLIProgram("python3")` with `scriptPath` positional — invokes the bridge script
- Services will pipe JSON to stdin and read JSON-lines from stdout via `CLIClient`

**Python bridge** (`pr-radar-mac/bridge/claude_bridge.py`, `bridge/requirements.txt`):
- ~80 lines: reads JSON request from stdin, calls `claude_agent_sdk.query()`, streams JSON-lines to stdout
- Supports: `prompt`, `model`, `tools`, `cwd`, `output_schema` fields
- Emits: `{"type": "text", ...}`, `{"type": "tool_use", ...}`, `{"type": "result", ...}`

---

## - [x] Phase 2: Domain Models Enhancement

> **Completed.** All models extended with behavior, 101 tests pass, both targets build.

### What was implemented:

**Rule model** (`RuleOutput.swift`):
- `AppliesTo.matchesFile(_:)` — glob/fnmatch-style matching via regex conversion (supports `*`, `**`, `?` patterns)
- `AppliesTo.fnmatch(_:pattern:)` — static helper converting glob patterns to `NSRegularExpression`
- `GrepPatterns.matches(_:)` — regex matching with `all` (AND) and `any` (OR) semantics using `.anchorsMatchLines`
- `GrepPatterns.hasPatterns` — computed property
- `ReviewRule.fromFile(_ url:)` — loads markdown rule files with YAML frontmatter parsing
- `ReviewRule.appliesToFile(_:)`, `matchesDiffContent(_:)`, `shouldEvaluate(filePath:diffText:)` — delegates to `AppliesTo`/`GrepPatterns`
- `ReviewRule.parseFrontmatter(_:)` and `parseSimpleYAML(_:)` — minimal YAML parser (no external dependency) supporting strings, inline arrays `["a", "b"]`, nested dicts, and sub-list items with `- "value"` syntax
- Memberwise `public init(...)` on all types; `Equatable` conformance added

**Focus area model** (`FocusAreaOutput.swift`):
- `FocusArea.getFocusedContent()` — extracts annotated lines within `[startLine, endLine]` from hunk content
- `FocusArea.getContextAroundLine(_:contextLines:)` — diff excerpt centered on a target line
- `FocusArea.contentHash()` — 8-character SHA-256 hex hash via `CryptoKit`
- Memberwise `public init(...)` and `Equatable` conformance

**Evaluation task model** (`TaskOutput.swift`):
- Memberwise `public init(...)` on `TaskRule` and `EvaluationTaskOutput`
- `EvaluationTaskOutput.from(rule:focusArea:)` — factory generating task ID from rule name + focus ID

**Phase state models** (`DataPathsService.swift`):
- `PRRadarPhase`: Added `phaseNumber`, `requiredPredecessor`, `displayName`
- New `PhaseStatus` struct with `completionPercentage`, `isPartial`, `summary`
- `DataPathsService`: Added `phaseExists()`, `canRunPhase()`, `validateCanRun()`, `phaseStatus()`, `allPhaseStatuses()`

**Hunk model** (`Hunk.swift`):
- New `DiffLineType` enum (`.added`, `.removed`, `.context`, `.header`) and `DiffLine` struct for pipeline use
- `Hunk.getAnnotatedContent()` — line number annotation format (`"  10: +code"`, `"   -: -deleted"`)
- `Hunk.getDiffLines()`, `getAddedLines()`, `getRemovedLines()`, `getChangedLines()`, `getChangedContent()`
- `Hunk.extractChangedContent(from:)` — static, handles both raw and annotated diff formats

**GitDiff model** (`GitDiff.swift`):
- Parser handles `new file`, `deleted file`, `similarity` header lines
- Renamed display types to `DisplayDiffSection`, `DisplayDiffLine`, `DisplayDiffLineType` to avoid collision with pipeline types in `Hunk.swift`
- Added `uniqueFiles` computed property

### Technical notes:
- No external YAML dependency — implemented a minimal parser covering the subset of YAML used in rule frontmatter (top-level keys, inline arrays, nested dicts with sub-lists)
- `fnmatch` glob matching converts patterns to regex: `*` → `[^/]*`, `**/` → `(?:.*/)?`, `**` (end) → `.*`, `?` → `[^/]`
- Display vs pipeline model separation: `DisplayDiffLine`/`DisplayDiffLineType` for SwiftUI views, `DiffLine`/`DiffLineType` for pipeline processing
- Added `PRRadarConfigService` dependency to test target for `DataPathsService` tests

### Test files added (5 files, 57 new tests):
- `RuleBehaviorTests.swift` — AppliesTo, GrepPatterns, ReviewRule, fnmatch, YAML parsing
- `FocusAreaBehaviorTests.swift` — getFocusedContent, getContextAroundLine, contentHash
- `TaskBehaviorTests.swift` — TaskRule init, EvaluationTaskOutput init, factory method
- `HunkBehaviorTests.swift` — annotated content, getDiffLines, extractChangedContent
- `PhaseBehaviorTests.swift` — PRRadarPhase, PhaseStatus, DataPathsService

---

## - [x] Phase 3: Services — Git Operations and GitHub Integration

> **Completed.** All three services created, GitHub domain models added, both targets build.

### What was implemented:

**GitHubModels** (`pr-radar-mac/Sources/services/PRRadarModels/GitHubModels.swift`):
- Full `Codable` model hierarchy matching Python's `domain/github.py`: `GitHubAuthor`, `GitHubLabel`, `GitHubFile`, `GitHubCommit`, `GitHubComment`, `GitHubReview`, `GitHubOwner`, `GitHubDefaultBranchRef`
- `GitHubPullRequest` — full PR metadata with all fields from `gh pr view --json`; includes `toPRMetadata()` bridge to existing `PRMetadata` model
- `GitHubPullRequestComments` — comments and reviews container
- `GitHubRepository` — repo metadata with computed `ownerLogin`, `defaultBranch`, `fullName`

**GitOperationsService** (`pr-radar-mac/Sources/services/PRRadarCLIService/GitOperationsService.swift`):
- Stateless `Sendable` struct wrapping `CLIClient` + `GitCLI` SDK commands
- All 10 methods ported: `checkWorkingDirectoryClean`, `fetchBranch`, `checkoutCommit`, `clean`, `getBranchDiff`, `isGitRepository`, `getFileContent`, `getRepoRoot`, `getCurrentBranch`, `getRemoteURL`
- `GitOperationsError` enum with typed error cases
- Uses `executeForResult` for `isGitRepository` (needs non-throwing exit code check), `execute` for all others (throws on failure)

**GitHubService** (`pr-radar-mac/Sources/services/PRRadarCLIService/GitHubService.swift`):
- Stateless `Sendable` struct wrapping `CLIClient` + `GhCLI` SDK commands
- All 8 methods ported: `getPRDiff`, `getPullRequest`, `getPullRequestComments`, `listPullRequests`, `getRepository`, `apiGet`, `apiPost`, `apiPostWithInt`, `apiPatch`
- Decodes JSON responses directly into `GitHubPullRequest`, `GitHubPullRequestComments`, `GitHubRepository` models
- Field lists match Python's `_PR_FIELDS`, `_PR_LIST_FIELDS`, `_PR_COMMENT_FIELDS`, `_REPO_FIELDS`

**PRAcquisitionService** (`pr-radar-mac/Sources/services/PRRadarCLIService/PRAcquisitionService.swift`):
- Composes `GitHubService` + `GitOperationsService` to replicate `diff_command.py` logic
- `acquire(prNumber:repoPath:outputDir:)` fetches all PR data and writes 9 phase-1 artifacts
- Returns typed `AcquisitionResult` with `pullRequest`, `diff`, `comments`, `repository`
- Effective diff writes identity copies as placeholders (algorithm ported in Phase 4)

**MoveReport** (`DiffOutput.swift`):
- Added memberwise `public init(...)` — was missing due to custom `CodingKeys`

### Technical notes:
- No Package.swift changes needed — new files are in existing target directories
- Services follow architecture conventions: stateless `Sendable` structs, constructor-based dependency injection of `CLIClient`
- `CLIClient.execute(_:)` returns trimmed stdout `String` and throws `CLIClientError.executionFailed` on non-zero exit
- `CLIClient.executeForResult(_:)` returns `ExecutionResult` without throwing — used for `isGitRepository` which needs to check exit code without throwing
- Multi-statement function bodies in Swift require explicit `return` for the trailing expression

---

## - [ ] Phase 4: Infrastructure — Effective Diff Algorithm

> **Pre-step:** Read all docs at `https://github.com/gestrich/swift-app-architecture/tree/main/docs/architecture` — especially `Layers.md` (which layer this belongs in), `Principles.md`, and `code-style.md`.

Port the entire `effective_diff.py` module (~867 lines) to Swift. This is the largest single piece of pure computation. The algorithm has 4 internal phases:

### Phase 4a: Line Matching
- Extract tagged lines from diff hunks (removed lines from old file, added lines from new file)
- Build index by normalized content (strip whitespace, lowercase)
- Find exact matches between removed and added lines across files
- Filter out distance-0 matches (in-place edits, not moves)

### Phase 4b: Block Aggregation and Scoring
- Group individual line matches into contiguous blocks with gap tolerance N=3
- Score blocks using: size factor, line uniqueness, match consistency, distance factor
- Minimum block size: 3 lines

### Phase 4c: Block Extension and Re-diff
- Extend matched blocks by ±20 context lines
- Extract regions from source files to temp files
- Call `git diff --no-index` (via `GitCLI` from Phase 1) to re-diff extracted regions
- Trim unrelated hunks from the re-diff output

### Phase 4d: Diff Reconstruction
- Replace move-source hunks with effective diffs showing the actual changes
- Drop removed-side hunks that were fully moved
- Produce a new `GitDiff` with the reconstructed hunks

### Key data structures to port:
- `TaggedLine` (file, line_number, content, normalized_content, line_type)
- `LineMatch` (removed_line, added_line, distance)
- `MatchBlock` (matches list, score)
- `MoveRegion` (source file/lines, dest file/lines)
- `MoveDetail` / `MoveReport` (already exists in Swift models)

### Files to create:
- `pr-radar-mac/Sources/services/PRRadarModels/EffectiveDiff/` — new directory with multiple files for each phase
- Unit tests porting the 144+ Python tests from `tests/infrastructure/effective_diff/`
- Copy the 13 `.diff` fixture files from `tests/infrastructure/effective_diff/fixtures/`

### Validation:
- Both targets build: `swift build` (MacApp + PRRadarMacCLI)
- All ported unit tests pass
- Run effective diff against test repo PR #1 diff and compare output to Python version
- End-to-end fixture tests produce identical results

---

## - [ ] Phase 5: Services — Rule Loading, Focus Generation, and Task Creation

> **Pre-step:** Read all docs at `https://github.com/gestrich/swift-app-architecture/tree/main/docs/architecture` — especially `Layers.md` (Services layer rules), `Dependencies.md`, and `Principles.md`.

Port the rule pipeline: loading rules from markdown files, generating focus areas via Claude, filtering rules by applicability, and creating evaluation tasks.

### Rule Loader (ports `services/rule_loader.py`)
- Scan a rules directory for `*.md` files
- Parse YAML frontmatter to create `ReviewRule` objects
- Filter rules by file pattern matching against changed files in the diff
- Filter rules by grep pattern matching against focus area content
- Use Foundation `FileManager` for directory scanning, `String` methods for pattern matching

### Focus Generator (ports `services/focus_generator.py`)
- For each diff hunk, call Claude Haiku via the bridge script (Phase 1) to identify methods/functions
- Parse the structured JSON output into `FocusArea` objects
- Create both "method" and "file" level focus areas
- Uses the Claude bridge with model `claude-haiku-4-5-20251001`, no tools, structured output schema

### Task Creator (ports task pairing from `services/phase_sequencer.py`)
- Pair each applicable rule with each relevant focus area
- Generate task IDs
- Write task files to the phase-4 output directory

### Files to create/modify:
- `pr-radar-mac/Sources/services/PRRadarCLIService/RuleLoaderService.swift` — new
- `pr-radar-mac/Sources/services/PRRadarCLIService/FocusGeneratorService.swift` — new
- `pr-radar-mac/Sources/services/PRRadarCLIService/TaskCreatorService.swift` — new
- `pr-radar-mac/Sources/services/PRRadarCLIService/ClaudeBridgeClient.swift` — new (Swift wrapper around the bridge script, handles JSON-lines streaming)
- Unit tests for rule loading and task creation

### Validation:
- Both targets build: `swift build` (MacApp + PRRadarMacCLI)
- Load rules from `/Users/bill/Developer/personal/PRRadar-TestRepo/rules/`
- Generate focus areas for test repo PR #1 diff
- Verify rule filtering produces expected matches
- Task files written match expected format

---

## - [ ] Phase 6: Services — Evaluation, Reporting, and Phase Orchestration

> **Pre-step:** Read all docs at `https://github.com/gestrich/swift-app-architecture/tree/main/docs/architecture` — especially `Layers.md` (Services layer rules), `Dependencies.md`, and `Principles.md`.

Port the remaining pipeline services: evaluation execution, report generation, violation filtering, and the overall phase sequencer.

### Evaluation Service (ports `services/evaluation_service.py`)
- For each evaluation task, call Claude Sonnet via the bridge script with:
  - The rule content + focus area diff as prompt
  - `allowed_tools: ["Read", "Grep", "Glob"]` and `cwd: repoPath`
  - Structured output schema for `RuleEvaluation`
- Parse streaming output (text blocks, tool use blocks, result)
- Track cost and duration per evaluation
- Write evaluation result files to phase-5 directory

### Report Generator (ports `services/report_generator.py`)
- Aggregate evaluation results into summary statistics
- Group violations by severity, file, and rule
- Calculate total cost and duration
- Render markdown summary
- Write `summary.json` and `summary.md` to phase-6 directory

### Violation Service (ports `services/violation_service.py`)
- Filter evaluations by score threshold (default: violations with score ≥ 1)

### Comment Service (ports `infrastructure/github/comment_service.py`)
- Post inline PR comments via `gh api`
- Format violation data into GitHub comment markdown
- Handle existing comment detection (avoid duplicates)

### Phase Sequencer (ports `services/phase_sequencer.py`)
- Manage the pipeline: DIFF → FOCUS_AREAS → RULES → TASKS → EVALUATIONS → REPORT
- Directory layout: `<output_dir>/<pr_number>/phase-N-<name>/`
- Dependency validation (e.g., can't evaluate without rules)
- Resume support (skip completed phases)
- Status reporting

### Files to create/modify:
- `pr-radar-mac/Sources/services/PRRadarCLIService/EvaluationService.swift` — new
- `pr-radar-mac/Sources/services/PRRadarCLIService/ReportGeneratorService.swift` — new
- `pr-radar-mac/Sources/services/PRRadarCLIService/ViolationService.swift` — new
- `pr-radar-mac/Sources/services/PRRadarCLIService/CommentService.swift` — new
- `pr-radar-mac/Sources/services/PRRadarCLIService/PhaseSequencer.swift` — new
- Unit tests for report generation, violation filtering

### Validation:
- Both targets build: `swift build` (MacApp + PRRadarMacCLI)
- Run full pipeline against test repo PR #1 with rules
- Evaluation results written to correct directories
- Report summary matches expected format
- Phase sequencer correctly handles resume (re-run skips completed phases)

---

## - [ ] Phase 7: Feature and App Layer Integration

> **Pre-step:** Read all docs at `https://github.com/gestrich/swift-app-architecture/tree/main/docs/architecture` — especially `FeatureStructure.md` (use case patterns), `Layers.md` (Features and Apps layer rules), `swift-ui.md` (observable model patterns), and `Dependencies.md`.

Update the Feature layer use cases and App layer (both CLI and GUI) to use the new native Swift services instead of invoking the Python CLI.

### Feature Layer Changes

Each use case currently follows this pattern:
1. Build a `PRRadar.Agent.Xxx` SDK command
2. Call `PRRadarCLIRunner.execute()` (invokes Python CLI)
3. Parse JSON output files with `PhaseOutputParser`

Change to:
1. Call the corresponding native Swift service directly
2. Services use `Codable` models and `JSONEncoder` to write output files — no need to match the old Python JSON format exactly; reshape as needed
3. Remove `PhaseOutputParser` and `PRRadarCLIRunner` — they only existed to bridge Python CLI output. Replace with direct `Codable` decoding in the services that read cross-phase data

Update these use cases:
- `FetchDiffUseCase` → use `PRAcquisitionService` + effective diff
- `FetchRulesUseCase` → use `FocusGeneratorService` + `RuleLoaderService` + `TaskCreatorService`
- `EvaluateUseCase` → use `EvaluationService`
- `GenerateReportUseCase` → use `ReportGeneratorService`
- `PostCommentsUseCase` → use `CommentService`
- `FetchPRListUseCase` → use `GitHubService.listPullRequests()` + `PRDiscoveryService`
- `AnalyzeUseCase` → use `PhaseSequencer` (full pipeline)

### CLI Target Changes

Update CLI commands (`DiffCommand`, `RulesCommand`, `EvaluateCommand`, etc.) to call the updated use cases. The commands themselves shouldn't change much since they already consume `AsyncThrowingStream<PhaseProgress>`.

### GUI Target Changes

The GUI models (`PRReviewModel`, `ReviewModel`) already call use cases, so they should work with minimal changes once the use cases are updated.

### Remove Python-bridge code:
- Delete `PRRadarMacSDK/PRRadar.swift` (the `@CLIProgram("prradar")` bindings to the Python CLI)
- Delete or repurpose `PRRadarCLIRunner.swift` (the Python CLI executor)
- The `PRRadarConfig.prradarPath` (path to Python binary) is no longer needed

### Package.swift changes:
- The `PRRadarMacSDK` target now contains `GitCLI`, `GhCLI`, `ClaudeBridge` instead of `PRRadar`
- Service targets gain new source files
- May need to reorganize targets if service layer grows too large

### Files to modify:
- All 10 use case files in `Sources/features/PRReviewFeature/usecases/`
- CLI commands in `Sources/apps/MacCLI/`
- `PRReviewModel.swift`, `ReviewModel.swift` in `Sources/apps/MacApp/Models/`
- `PRRadarConfig.swift` — remove Python-specific config (venvBinPath, prradarPath)
- `PRRadarEnvironment.swift` — simplify (no longer need venv path in PATH)
- `main.swift` — remove venv path computation
- `Package.swift` — update target dependencies
- Delete `PRRadarMacSDK/PRRadar.swift`

### Validation:
- Both targets build: `swift build` (MacApp + PRRadarMacCLI)
- Swift CLI `diff 1 --config test-repo` produces output
- Swift CLI `status 1 --config test-repo` shows correct phase statuses
- `swift run MacApp` launches and shows PR data

---

## - [ ] Phase 8: Python App Removal and Cleanup

> **Pre-step:** Read all docs at `https://github.com/gestrich/swift-app-architecture/tree/main/docs/architecture` — especially `documentation.md` (for CLAUDE.md rewrite) and `Configuration.md`.

Remove the Python app entirely and clean up any remaining references.

### Delete Python files:
- `prradar/` — entire directory
- `tests/` — entire directory (Python tests replaced by Swift tests)
- `pyproject.toml`
- `agent.sh`
- `.venv/` — if present in repo

### Keep:
- `pr-radar-mac/bridge/claude_bridge.py` — the minimal Claude SDK bridge
- `pr-radar-mac/bridge/requirements.txt`

### Update project files:
- `CLAUDE.md` — rewrite to reflect Swift-only architecture
- `plugin/` — update SKILL.md if it references the Python CLI
- `.gitignore` — remove Python-specific entries, add Swift-specific if needed
- `README.md` — if it exists, update

### Update the verification command:
- `.claude/commands/pr-radar-verify-work.md` — update to only reference Swift CLI commands

### Validation:
- No Python imports or references remain (except the bridge script)
- Both targets build: `swift build` (MacApp + PRRadarMacCLI)
- `swift test` passes
- Git status is clean (no accidentally deleted tracked files)

---

## - [ ] Phase 9: Architecture Validation

Review all commits made during the preceding phases and validate they follow the project's architectural conventions.

**For Swift changes** (`pr-radar-mac/`):
- Fetch and read each skill from `https://github.com/gestrich/swift-app-architecture` (skills directory)
- Compare the commits made against the conventions described in each relevant skill
- If any code violates the conventions, make corrections

**For the Python bridge script** (`pr-radar-mac/bridge/`):
- Fetch and read each skill from `https://github.com/gestrich/python-architecture` (skills directory)
- Verify the bridge script follows Python conventions
- If any code violates the conventions, make corrections

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. Fetch and read ALL skills from `https://github.com/gestrich/swift-app-architecture`
4. Evaluate the Swift changes against each skill's conventions
5. Fetch and read ALL skills from `https://github.com/gestrich/python-architecture`
6. Evaluate the bridge script against each skill's conventions
7. Fix any violations found

---

## - [ ] Phase 10: End-to-End Validation

Verify the full pipeline works end-to-end: create a fresh PR with a known violation, run analysis, post a comment, and confirm the comment actually appears on GitHub via the API.

### Step 1: Run unit tests

```bash
cd /Users/bill/Developer/personal/PRRadar/pr-radar-mac
swift test
```

### Step 2: Create a test PR with a known violation

The test repo at `/Users/bill/Developer/personal/PRRadar-TestRepo` has a `guard-divide-by-zero` rule (in `rules/guard-divide-by-zero.md`) that flags `*.swift` files containing division that returns `nil` instead of throwing. Create a PR that intentionally violates this rule:

```bash
cd /Users/bill/Developer/personal/PRRadar-TestRepo
git checkout main && git pull
git checkout -b test/swift-rewrite-validation
```

Add a Swift file with an intentional violation — a divide function that returns `nil` on error instead of throwing:

```swift
// MathHelper.swift
func divide(_ a: Int, _ b: Int) -> Double? {
    guard b != 0 else { return nil }
    return Double(a) / Double(b)
}
```

Commit, push, and open a PR:

```bash
git add . && git commit -m "Add MathHelper with optional division"
git push -u origin test/swift-rewrite-validation
gh pr create --title "Add MathHelper" --body "Test PR for Swift rewrite validation"
```

Note the PR number returned by `gh pr create`.

### Step 3: Clean output and run full analysis

```bash
rm -rf ~/Desktop/code-reviews
cd /Users/bill/Developer/personal/PRRadar/pr-radar-mac
swift run PRRadarMacCLI analyze <PR_NUMBER> --config test-repo
```

### Step 4: Verify pipeline output

Run `status` and confirm all 6 phases completed:

```bash
swift run PRRadarMacCLI status <PR_NUMBER> --config test-repo
```

Verify output structure — each phase directory contains expected files:
- `phase-1-pull-request/`: `diff-raw.diff`, `diff-parsed.json`, `effective-diff-parsed.json`, `gh-pr.json`
- `phase-2-focus-areas/`: `method.json`, `file.json`
- `phase-3-rules/`: `all-rules.json`
- `phase-4-tasks/`: individual task JSON files
- `phase-5-evaluations/`: individual evaluation JSON files
- `phase-6-report/`: `summary.json`, `summary.md`

Verify the report identifies a violation of the `guard-divide-by-zero` rule on `MathHelper.swift`.

### Step 5: Post comments to GitHub and verify via API

Post comments from the analysis to the PR:

```bash
swift run PRRadarMacCLI comment <PR_NUMBER> --config test-repo
```

Then verify the comment was actually posted by querying the GitHub API directly:

```bash
gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments --jq '.[].body'
```

Confirm at least one review comment references the `guard-divide-by-zero` rule violation on `MathHelper.swift`. This is the critical check — it proves the full pipeline works end-to-end from diff acquisition through AI evaluation to GitHub integration.

### Step 6: Clean up test PR

```bash
cd /Users/bill/Developer/personal/PRRadar-TestRepo
gh pr close <PR_NUMBER> --delete-branch
git checkout main
rm -rf ~/Desktop/code-reviews
```

### Success criteria:
- All Swift unit tests pass
- `analyze` completes all 6 pipeline phases without errors
- Report correctly identifies the intentional `guard-divide-by-zero` violation
- `comment` posts review comments to the GitHub PR
- `gh api` confirms the comment exists on the PR — not just local output, actually posted to GitHub
- No Python dependencies required at runtime (except the Claude bridge venv)
