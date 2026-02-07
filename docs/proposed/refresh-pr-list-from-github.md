## Background

The Mac app's PR list currently only discovers PRs from the local output directory (scanning for `gh-pr.json` files already on disk). The refresh button (`arrow.clockwise`) calls `PRDiscoveryService.discoverPRs()` which scans the filesystem — it does not fetch anything from GitHub. This means a user can only see PRs they've already manually fetched via the `+` button.

Bill wants the refresh button to fetch recent pull requests (last 50) from GitHub, saving their metadata to disk so they appear in the list. This should:

1. Go through the Python CLI (consistent with how all other operations work)
2. Be callable from both the Mac GUI and the Swift CLI
3. Show a spinner in the GUI during the fetch
4. Refresh the list after completion

The Python app currently has no command to list/fetch multiple PRs — all agent commands operate on a single PR number. A new `agent list-prs` command is needed.

### Design decisions

**What the new command does:** The `list-prs` command fetches recent PR metadata from GitHub via `gh pr list` and saves each PR's metadata as `gh-pr.json` in the existing output directory structure (`{output-dir}/{pr-number}/phase-1-pull-request/gh-pr.json`). This is intentionally lightweight — it only fetches PR metadata (not diffs, comments, or repo info). This reuses the exact same file the `diff` command writes, so `PRDiscoveryService.discoverPRs()` already knows how to read it.

**Filtering:** The `gh pr list` command supports `--state` (open/closed/merged/all), `--limit`, and `--search` (GitHub search syntax which can filter by date). The Python command will expose `--limit` (default 50) and `--state` (default `open`). The Mac app refresh button will call it with defaults. The Swift CLI will expose the same options.

**Repo context:** The Python `gh pr list` command runs in the working directory of the repo (same as `gh pr diff`), so it automatically targets the correct repository. The `--repo-path` from the Mac app config sets the working directory.

---

## Phases

## - [x] Phase 1: Python `agent list-prs` command

Add a new `list-prs` subcommand to the agent command group that fetches recent PRs from GitHub and saves their metadata.

**Files to modify:**
- `prradar/infrastructure/github/runner.py` — Add `list_pull_requests(limit, state)` method to `GhCommandRunner` using `gh pr list --json <fields> --limit <N> --state <state>`
- `prradar/commands/agent/__init__.py` — Register the `list-prs` subparser with `--limit` (default 50), `--state` (default "open") arguments. Note: no `pr_number` positional arg (unlike other commands)
- `prradar/commands/agent/list_prs.py` — New file implementing `cmd_list_prs(output_dir, limit, state)`. For each PR returned, write `gh-pr.json` into `{output_dir}/{pr.number}/phase-1-pull-request/`. Also write `gh-repo.json` once (shared for all PRs from `gh.get_repository()`).
- `prradar/commands/agent/__init__.py` — Update `cmd_agent()` dispatch to handle `list-prs`. Since `list-prs` has no `pr_number`, the dispatch needs to handle this command before calling `ensure_output_dir` (which requires `pr_number`).

**`gh pr list` fields to fetch:** Use the same `_PR_FIELDS` already defined in `runner.py` (number, title, author, state, headRefName, createdAt, etc.) so the output is compatible with the existing `gh-pr.json` format.

**Key detail:** The `cmd_agent` function currently expects `args.pr_number` for all commands. The `list-prs` command doesn't have one. Handle this by checking `args.agent_command == "list-prs"` early in `cmd_agent`, before the `pr_number` / `ensure_output_dir` call.

**Expected CLI usage:**
```bash
prradar agent --output-dir code-reviews list-prs
prradar agent --output-dir code-reviews list-prs --limit 20 --state all
```

**Completed.** `list_pull_requests()` parses the JSON array from `gh pr list` into `PullRequest` domain objects using the existing `from_dict` factory. The `cmd_list_prs` function writes both `gh-pr.json` and `gh-repo.json` per PR into the standard phase-1 directory structure, so `PRDiscoveryService.discoverPRs()` picks them up automatically. The `--state` arg uses `choices` validation to restrict to valid `gh` values.

## - [x] Phase 2: Python tests for `list-prs`

**Files to create/modify:**
- `tests/commands/agent/test_list_prs.py` — New file with unit tests for `cmd_list_prs`:
  - Test that PR metadata files are written to the correct directory structure
  - Test with mocked `GhCommandRunner` returning sample PR list
  - Test `--limit` and `--state` arguments are passed through
  - Test behavior when `gh pr list` returns empty results
- `tests/infrastructure/github/test_runner.py` — Add test for the new `list_pull_requests` method (verify correct `gh` command construction)

**Completed.** 16 tests total (10 for `cmd_list_prs`, 6 for `GhCommandRunner.list_pull_requests`). Tests use `patch` on `GhCommandRunner` constructor to inject mocks, and `PullRequest.from_dict`/`Repository.from_dict` factories for realistic test data with `raw_json` populated. Tests also verify roundtrip: saved JSON files can be parsed back into domain models via `from_file`.

## - [x] Phase 3: Swift SDK + CLI Service layer

Add the `ListPRs` command to the Swift SDK and ensure the CLI runner can execute it.

**Files to modify:**
- `pr-radar-mac/Sources/sdks/PRRadarMacSDK/PRRadar.swift` — Add `PRRadar.Agent.ListPRs` struct with `@Option("--limit")`, `@Option("--state")` (no `@Positional` prNumber)
- `pr-radar-mac/Sources/services/PRRadarCLIService/PRRadarCLIRunner.swift` — Verify the `execute` method works for commands without a `prNumber` positional. The runner injects `--output-dir` after "agent" which should still work fine since `list-prs` doesn't need `pr_number`.

**Completed.** Added `PRRadar.Agent.ListPrs` struct (named `ListPrs` not `ListPRs` so the CLISDK kebab-case macro produces `list-prs` matching the Python subcommand). Both `limit` and `state` are optional `String?` `@Option` properties. No `@Positional` prNumber needed. `PRRadarCLIRunner.execute` required no changes — it inserts `--output-dir` after `"agent"` generically, which works correctly for commands with or without positional arguments.

## - [x] Phase 4: Swift Feature layer — `FetchPRListUseCase`

Create a new use case following the existing `FetchDiffUseCase` pattern.

**Files to create:**
- `pr-radar-mac/Sources/features/PRReviewFeature/usecases/FetchPRListUseCase.swift` — New use case that:
  - Takes `config`, `environment`, `limit` (optional), `state` (optional)
  - Constructs `PRRadar.Agent.ListPRs` command
  - Executes via `PRRadarCLIRunner`
  - Streams progress events (`running`, `log`, `completed`, `failed`)
  - On completion, calls `PRDiscoveryService.discoverPRs()` to return the updated `[PRMetadata]` list
  - Output type: `[PRMetadata]` (the refreshed list)

**Progress type:** Use `PhaseProgress<[PRMetadata]>` to match the existing pattern.

**Completed.** Created `FetchPRListUseCase` following the exact `FetchDiffUseCase` pattern. The `execute` method takes optional `limit`, `state`, and `repoSlug` parameters. It constructs `PRRadar.Agent.ListPrs` (matching the SDK struct name), streams CLI output via `CLIOutputStream`, and on success calls `PRDiscoveryService.discoverPRs(outputDir:repoSlug:)` to return the refreshed `[PRMetadata]` list. Uses `config.absoluteOutputDir` for the discovery call since `PRDiscoveryService` expects an absolute path. No `parseOutput` static method — the list-prs command writes files to disk and discovery reads them.

## - [x] Phase 5: Mac App — Model + UI integration

Wire the use case into `PRReviewModel` and update the refresh button.

**Files to modify:**
- `pr-radar-mac/Sources/apps/MacApp/Models/PRReviewModel.swift`:
  - Add `isRefreshing: Bool` property (for spinner state)
  - Replace `refreshPRList()` with an async method that:
    1. Sets `isRefreshing = true`
    2. Creates `FetchPRListUseCase` and executes it
    3. On completion, updates `ctx.prs` with the returned list
    4. Sets `isRefreshing = false`
  - Keep the old synchronous filesystem-only refresh as a private helper (still useful after `startNewReview`)

- `pr-radar-mac/Sources/apps/MacApp/UI/ContentView.swift`:
  - Update the refresh button to call the new async `refreshPRList()`
  - Add `ProgressView()` overlay or replace the button icon with a spinner when `model.isRefreshing` is true
  - Disable the refresh button while refreshing

**Completed.** `PRReviewModel.refreshPRList()` is now async — it creates a `FetchPRListUseCase` with the current config, derives the `repoSlug` for filtering, and streams the result. On `.completed`, the PR list is updated in the `ConfigContext`. The old synchronous filesystem-only refresh was renamed to `refreshPRListFromDisk()` (private) and is still used by `startNewReview` after the diff completes. In `ContentView`, the refresh button wraps the call in a `Task`, replaces the icon with a `ProgressView` spinner while `model.isRefreshing` is true, and is disabled when refreshing or when no config is selected.

## - [x] Phase 6: Swift CLI — `RefreshCommand`

Add a CLI command so the Swift CLI can also fetch recent PRs.

**Files to create/modify:**
- `pr-radar-mac/Sources/apps/MacCLI/Commands/RefreshCommand.swift` — New command:
  ```
  pr-radar-mac refresh [--config <name>] [--repo-path <path>] [--output-dir <dir>] [--limit <N>] [--state <state>]
  ```
  - Resolves config from options (same pattern as other commands)
  - Creates `FetchPRListUseCase` and streams output
  - Prints fetched PR count on completion

- `pr-radar-mac/Sources/apps/MacCLI/PRRadarMacCLI.swift` — Add `RefreshCommand.self` to the subcommands list

**Completed.** Created `RefreshCommand` with its own option properties (no `CLIOptions` `@OptionGroup` since there's no `prNumber`). Config resolution follows the same pattern as `resolveConfigFromOptions` — resolves named config, falls back to CLI overrides, then defaults. The command derives `repoSlug` from the resolved repo path via `PRDiscoveryService.repoSlug()` for filtering. Supports `--json` for structured output (array of PR summaries) and human-readable output listing each PR with number, title, and author. Registered as `RefreshCommand.self` in `PRRadarMacCLI` subcommands.

## - [ ] Phase 7: Architecture Validation

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

## - [ ] Phase 8: Validation

**Python tests:**
```bash
python -m pytest tests/ -v
python -m pytest tests/commands/agent/test_list_prs.py -v
```

**Swift build:**
```bash
cd pr-radar-mac && swift build
```

**Manual smoke test (Python):**
```bash
cd <any-github-repo>
prradar agent --output-dir /tmp/test-list list-prs --limit 5
ls /tmp/test-list/  # Should show numbered directories
```

**Manual smoke test (Swift CLI):**
```bash
cd pr-radar-mac
swift run PRRadarMacCLI refresh --config <config-name> --limit 5
```

**Success criteria:**
- All Python tests pass
- Swift project builds without errors
- `prradar agent list-prs` fetches PRs and writes `gh-pr.json` files
- Mac app refresh button shows spinner, fetches PRs, and updates the list
- Swift CLI `refresh` command works end-to-end
