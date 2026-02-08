## Background

Currently, PRRadar analyzes one PR at a time via `prradar agent analyze <pr_number>`. Bill wants the ability to analyze all PRs created since a given date in a single invocation — a batch analysis mode. This is useful for periodic review sweeps (e.g., "review everything opened this week").

Key requirements:
- **Date-based filtering**: Fetch PRs by creation date using `gh pr list --search "created:>=YYYY-MM-DD"`
- **Full analysis per PR**: Each discovered PR gets the full pipeline (diff → rules → evaluate → report)
- **No commenting by default**: Commenting is OFF by default; an explicit `--comment` flag enables it
- **Cross-stack support**: Python CLI first, then Mac SwiftUI app ("Analyze All" button) and Mac CLI command
- **Thin client principle**: Mac app invokes the Python CLI; no business logic in Swift

The `analyze-all` command reuses the existing `cmd_analyze()` for each PR, running in non-interactive batch mode. The `gh pr list --search` qualifier handles server-side date filtering so we don't over-fetch.

## Phases

## - [x] Phase 1: Add `--search` support to GitHub runner

Add a `search` parameter to `GhCommandRunner.list_pull_requests()` so it can pass `--search` to `gh pr list`.

**Files modified:**
- `prradar/infrastructure/github/runner.py` — Added optional `search: str | None = None` parameter to `list_pull_requests()`. When provided, appends `["--search", search]` to the command.
- `tests/infrastructure/github/test_runner.py` — Added 2 tests: `test_appends_search_flag_when_specified` and `test_omits_search_flag_when_none`.

**Notes:**
- All 558 tests pass after changes
- Existing callers unaffected since `search` defaults to `None`

## - [x] Phase 2: Add `analyze-all` Python CLI command

Create the `analyze-all` subcommand that fetches PRs since a date and runs the full pipeline on each.

**Files created:**
- `prradar/commands/agent/analyze_all.py` — New command module with `cmd_analyze_all()` function

**Files modified:**
- `prradar/commands/agent/__init__.py` — Registered `analyze-all` subparser with all arguments and wired up `cmd_agent()` dispatch (handled before `ensure_output_dir` since there's no `pr_number`, same pattern as `list-prs`)

**CLI interface:**
```
prradar agent analyze-all --since YYYY-MM-DD [options]
```

**Arguments:**
- `--since` (required): Date string in `YYYY-MM-DD` format. Passed to `gh pr list --search "created:>=DATE"`
- `--rules-dir`: Same as `analyze` (default: `code-review-rules`)
- `--repo-path`: Same as `analyze` (default: `.`)
- `--repo`: Repository in owner/repo format (auto-detected if omitted)
- `--github-diff`: Use GitHub API for diff text
- `--min-score`: Minimum score threshold (default: 5)
- `--comment`: Flag that enables commenting. When present, sets `interactive=False, dry_run=False` on per-PR analyze calls. When absent (default), sets `interactive=False, dry_run=True`.
- `--limit`: Maximum PRs to process (default: 50, safety cap)
- `--state`: PR state filter (default: `all` — different from `list-prs` default of `open`, since date-based queries should include merged/closed PRs)

**`cmd_analyze_all()` function signature:**
```python
def cmd_analyze_all(
    output_dir: str,
    since: str,
    rules_dir: str,
    repo: str,
    comment: bool = False,
    limit: int = 50,
    state: str = "all",
    min_score: int = 5,
    source: DiffSource = DiffSource.LOCAL,
    repo_path: str = ".",
) -> int:
```

**Implementation flow:**
1. Build search query: `f"created:>={since}"`
2. Call `gh.list_pull_requests(limit=limit, state=state, search=search_query, repo=repo)` to get matching PRs
3. Print summary: "Found N PRs created since {since}"
4. For each PR, call `cmd_analyze()` with:
   - `interactive=False` (always batch mode for multi-PR)
   - `dry_run=not comment` (only post when `--comment` flag is set)
   - `stop_after=None, skip_to=None` (full pipeline)
   - All other params passed through
5. Track per-PR success/failure, print aggregate summary at end
6. Return 0 if all succeeded, 1 if any failed

**Notes:**
- All 558 existing tests pass after changes
- Per-PR exceptions are caught and tracked without stopping the batch
- Dispatch follows the same pattern as `list-prs` (handled before `ensure_output_dir` since no `pr_number`)
- Each PR uses `ensure_output_dir` to create its own subdirectory: `{output_dir}/{pr_number}/`

**Output structure:** Each PR gets its own subdirectory as usual: `{output_dir}/{pr_number}/`

## - [x] Phase 3: Tests for `analyze-all` command

**Files created:**
- `tests/commands/agent/test_analyze_all.py` — 13 tests covering all specified test cases

**Test cases (all passing):**
- `test_passes_correct_search_query_to_list_pull_requests` — verifies search query `created:>=YYYY-MM-DD`
- `test_each_pr_triggers_cmd_analyze_with_correct_params` — verifies per-PR analyze calls with all params
- `test_comment_false_sets_dry_run_true` — default comment=False → dry_run=True, interactive=False
- `test_comment_true_sets_dry_run_false` — comment=True → dry_run=False, interactive=False
- `test_failure_in_one_pr_does_not_stop_remaining` — exception in PR 2 doesn't prevent PR 3
- `test_nonzero_exit_code_tracked_as_failure` — non-zero exit code counted as failure
- `test_returns_zero_when_all_succeed` / `test_returns_one_when_any_fail` — aggregate exit codes
- `test_default_state_is_all` — state defaults to "all"
- `test_returns_zero_for_empty_pr_list` — no PRs → exit 0, no cmd_analyze calls
- `test_returns_one_when_pr_list_fetch_fails` — GitHub fetch error → exit 1
- `test_custom_limit_and_state_passed_through` — limit/state forwarded to list_pull_requests
- `test_creates_output_dir_per_pr` — ensure_output_dir called per PR

**Notes:**
- All 571 tests pass (558 existing + 13 new)
- Tests mock GhCommandRunner, cmd_analyze, and ensure_output_dir at the module level
- Follows same patterns as test_list_prs.py (setUp/tearDown with patchers)

## - [ ] Phase 4: Mac app SDK and CLI command

Add the `analyze-all` command to the Swift SDK layer and Mac CLI.

**Files to modify:**
- `pr-radar-mac/Sources/sdks/PRRadarMacSDK/PRRadar.swift` — Add `AnalyzeAll` struct inside `PRRadar.Agent`:
  ```swift
  @CLICommand
  public struct AnalyzeAll {
      @Option("--since") public var since: String
      @Option("--rules-dir") public var rulesDir: String?
      @Option("--repo-path") public var repoPath: String?
      @Flag("--github-diff") public var githubDiff: Bool = false
      @Option("--min-score") public var minScore: String?
      @Option("--repo") public var repo: String?
      @Flag("--comment") public var comment: Bool = false
      @Option("--limit") public var limit: String?
      @Option("--state") public var state: String?
      @Option("--output-dir") public var outputDir: String?
  }
  ```

**Files to create:**
- Mac CLI command for `analyze-all` (in `Sources/apps/MacCLI/Commands/` or wherever CLI commands live) — mirrors the Python CLI parameters, invokes via `PRRadarCLIRunner`

## - [ ] Phase 5: Mac app use case and UI

Add an `AnalyzeAllUseCase` in the features layer and an "Analyze All" button in the SwiftUI app.

**Files to create:**
- `pr-radar-mac/Sources/features/PRReviewFeature/usecases/AnalyzeAllUseCase.swift`

**Use case design:**
```swift
public struct AnalyzeAllUseCase: Sendable {
    public func execute(
        since: String,
        rulesDir: String? = nil,
        repoPath: String? = nil,
        githubDiff: Bool = false,
        minScore: String? = nil,
        repo: String? = nil,
        comment: Bool = false,
        limit: String? = nil,
        state: String? = nil
    ) -> AsyncThrowingStream<PhaseProgress<AnalyzeAllOutput>, Error>
}

public struct AnalyzeAllOutput: Sendable {
    public let cliOutput: String
    public let prNumbers: [Int]
}
```

**Files to modify:**
- `pr-radar-mac/Sources/apps/MacApp/Models/PRReviewModel.swift` — Add:
  - `analyzeAllState` property (idle/running/completed/failed)
  - `analyzeAll(since:)` async method that invokes `AnalyzeAllUseCase` and refreshes the PR list on completion
- `pr-radar-mac/Sources/apps/MacApp/UI/ContentView.swift` — Add "Analyze All" toolbar button (in the PR list column toolbar, alongside the existing Refresh button). Clicking it presents a date picker popover/sheet for selecting the "since" date, then triggers `model.analyzeAll(since:)`. Show a spinner/progress indicator while running.

**UI behavior:**
- Button labeled "Analyze All" in the PR list toolbar
- Tapping opens a popover with a date picker and "Start" button
- While running, button shows spinner and is disabled
- On completion, automatically refreshes the PR list to show newly analyzed PRs
- Logs are streamable (same `PhaseProgress` pattern as other use cases)

## - [ ] Phase 6: Architecture Validation

Review all commits made during the preceding phases and validate they follow the project's architectural conventions:

**For Python changes** (`prradar/`, `tests/`):
- Fetch and read each skill from `https://github.com/gestrich/python-architecture` (skills directory)
- Compare the commits made against the conventions described in each relevant skill
- If any code violates the conventions, make corrections

**For Swift changes** (`pr-radar-mac/`):
- Fetch and read each skill from `https://github.com/gestrich/swift-app-architecture` (skills directory)
- Compare the commits made against the conventions described in each relevant skill
- If any code violates the conventions, make corrections

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. Determine which languages were touched (Python, Swift, or both)
4. For each relevant language, fetch and read ALL skills from the corresponding GitHub repo
5. Evaluate the changes against each skill's conventions
6. Fix any violations found

## - [ ] Phase 7: Validation

**Python tests:**
- Run `python -m pytest tests/ -v` — all existing tests must pass
- Run `python -m pytest tests/commands/agent/test_analyze_all.py -v` — new tests must pass
- Run `python -m pytest tests/infrastructure/github/test_runner.py -v` — updated runner tests must pass

**Swift build:**
- Run `cd pr-radar-mac && swift build` — must compile cleanly

**Manual smoke test (optional):**
- Run `python -m prradar agent analyze-all --since 2025-01-01 --rules-dir ./code-review-rules --repo gestrich/PRRadar` with a known repo to verify end-to-end flow
