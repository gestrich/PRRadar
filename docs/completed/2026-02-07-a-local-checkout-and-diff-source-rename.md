## Background

The diff phase currently has two modes — GitHub API and local git — but they're poorly named and the local mode doesn't actually check out the PR branch. The new design separates two concerns:

1. **Branch checkout** — Always happens. Both modes fetch and checkout the PR branch locally. This sets up the repo for future operations that need local git state.
2. **Diff source** — Where the diff text comes from. Local git diff is the new default (handles large diffs). GitHub API diff is opt-in via a `--github-diff` flag.

This means `--repo-path` (defaults to `.`) is independent from `--github-diff` (optional — overrides diff source). The `DiffSource` enum, providers, and CLI are renamed to match.

### Files to modify

- `prradar/services/git_operations.py` — new checkout/restore methods
- `prradar/infrastructure/diff_provider/local_source.py` — add checkout flow
- `prradar/infrastructure/diff_provider/factory.py` — update factory for new defaults
- `prradar/domain/diff_source.py` — rename enum values
- `prradar/commands/agent/__init__.py` — rename CLI flags, flip default
- `prradar/commands/agent/diff.py` — require `local_repo_path`, always checkout
- `prradar/commands/agent/analyze.py` — same
- `prradar/infrastructure/diff_provider/github_source.py` — checkout before fetching diff
- `tests/test_git_operations_service.py` — new method tests
- `tests/test_local_git_repo.py` — updated workflow tests
- `tests/test_github_repo.py` — updated for checkout behavior
- `tests/test_diff_source.py` — renamed enum values
- `tests/test_diff_provider_factory.py` — updated for new defaults

## Phases

## - [x] Phase 1: Add checkout_commit to GitOperationsService and head_ref_oid to PullRequest

> Skills: `/python-architecture:creating-services`, `/python-architecture:testing-services`, `/python-architecture:domain-modeling`

Add to `prradar/services/git_operations.py`:

- `GitCheckoutError` exception class
- `checkout_commit(sha)` — runs `git checkout <sha>` (detached HEAD, no branch created)

Add to `prradar/domain/github.py` `PullRequest` dataclass:

- `head_ref_oid: str = ""` — the HEAD commit SHA of the PR (from GitHub API `.headRefOid`)
- Update `from_dict()` to parse this field

Add ~4 tests to `tests/test_git_operations_service.py` for `checkout_commit` (success, failure, not a repo).

**Completed.** Added `GitCheckoutError` exception and `checkout_commit(sha)` method following the same guard/subprocess/raise pattern as existing methods. Added `head_ref_oid` field to `PullRequest` with `from_dict` parsing `headRefOid`. Four tests added: command verification, failure error, not-a-repo error, and detached HEAD (no `-b` flag) verification. All 332 tests pass.

## - [x] Phase 2: Add checkout flow to LocalGitDiffProvider

> Skills: `/python-architecture:creating-services`, `/python-architecture:testing-services`

Rewrite `get_pr_diff()` in `prradar/infrastructure/diff_provider/local_source.py`:

```
1. Get PR metadata from GitHub API (base/head branch names + head SHA)
2. check_working_directory_clean()
3. fetch_branch(base), fetch_branch(head)
4. checkout_commit(head_sha)  # detached HEAD at PR's latest commit
5. return get_branch_diff(base, head)
```

No branch creation, no switch-back. The repo is left at the PR's head commit.

Update tests in `tests/test_local_git_repo.py`:
- Workflow order: `check_clean → fetch × 2 → checkout_commit → diff`

**Completed.** Added `checkout_commit(head_sha)` step between fetch and diff in `LocalGitDiffProvider.get_pr_diff()`. Updated all existing tests to supply `head_ref_oid` on mock PRs. Added two new tests: `test_get_pr_diff_checks_out_head_commit` (verifies correct SHA passed) and `test_get_pr_diff_aborts_on_checkout_failure` (verifies `GitCheckoutError` propagates and diff is not attempted). Workflow order test updated to verify `check_clean → fetch × 2 → checkout_commit → diff`. All 334 tests pass.

## - [x] Phase 3: Add checkout flow to GitHubDiffProvider

> Skills: `/python-architecture:dependency-injection`, `/python-architecture:creating-services`, `/python-architecture:testing-services`

Update `get_pr_diff()` in `prradar/infrastructure/diff_provider/github_source.py` to also checkout the branch. It needs a `GitOperationsService` dependency injected (same as local provider already has).

New flow:
```
1. Get PR metadata from GitHub API (base/head branch names + head SHA)
2. check_working_directory_clean()
3. fetch_branch(base), fetch_branch(head)
4. checkout_commit(head_sha)  # detached HEAD at PR's latest commit
5. return diff from gh pr diff (existing behavior)
```

Update factory in `prradar/infrastructure/diff_provider/factory.py` to inject `GitOperationsService` into `GitHubDiffProvider`.

Both providers now require `local_repo_path`. Update factory signature accordingly — `local_repo_path` becomes required for both.

Update tests in `tests/test_github_repo.py` and `tests/test_diff_provider_factory.py`.

**Completed.** Injected `GitOperationsService` into `GitHubDiffProvider` constructor (matching `LocalGitDiffProvider`'s signature). `get_pr_diff()` now fetches PR metadata, checks clean working directory, fetches branches, checks out head commit, then fetches diff via `gh pr diff`. Factory's `local_repo_path` parameter is now required (`str`, no longer `str | None`) since both providers need it for checkout. `cmd_diff` defaults `local_repo_path` to `"."` when not provided (pending Phase 4 CLI rename). Tests rewritten with full checkout workflow verification including order test (`check_clean → fetch × 2 → checkout_commit → pr_diff`), dirty directory abort, checkout failure propagation, and `GitOperationsService` injection for both factory paths. All 341 tests pass.

## - [x] Phase 4: Rename DiffSource enum and CLI flags

> Skills: `/python-architecture:domain-modeling`, `/python-architecture:cli-architecture`

**Rename enum** in `prradar/domain/diff_source.py`:
- `DiffSource.GITHUB_API` → `DiffSource.GITHUB` (value: `"github"`)
- `DiffSource.LOCAL_GIT` → `DiffSource.LOCAL` (value: `"local"`)

**Flip CLI default** in `prradar/commands/agent/__init__.py`:
- Replace `--local-repo-path` with `--repo-path` (defaults to `"."`) — always needed since both modes checkout
- Add `--github-diff` flag (boolean, `store_true`) — opt-in to use GitHub API for diff text
- Default behavior (no flag): local git diff

**Update dispatch** in `__init__.py`:
- `DiffSource.GITHUB if args.github_diff else DiffSource.LOCAL`

**Update cmd_diff / cmd_analyze signatures**:
- `local_repo_path` → `repo_path` (no longer optional, defaults to `"."`)
- Default `source` flips to `DiffSource.LOCAL`

Update `tests/test_diff_source.py` for renamed enum members. Update all references across codebase (`GITHUB_API` → `GITHUB`, `LOCAL_GIT` → `LOCAL`).

**Completed.** Renamed `DiffSource.GITHUB_API` → `GITHUB` and `DiffSource.LOCAL_GIT` → `LOCAL` (values unchanged: `"github"`, `"local"`). Replaced `--local-repo-path` with `--repo-path` (default `"."`) on both `diff` and `analyze` subcommands. Added `--github-diff` boolean flag (`store_true`) for opt-in GitHub API diff. Default behavior is now local git diff (`DiffSource.LOCAL`). Updated `cmd_diff` and `cmd_analyze` signatures: `local_repo_path: str | None` → `repo_path: str = "."`, default `source` flipped to `DiffSource.LOCAL`. Factory's internal `local_repo_path` parameter kept as-is (it's an internal detail). All tests updated for renamed enum members. All 341 tests pass.

## - [x] Phase 5: Validation

> Skills: `/python-architecture:testing-services`

1. `python -m pytest tests/ -v` — all tests pass
2. From `/Users/bill/Developer/work/ios`, run:
   - `agent.sh diff 18726` — default local diff mode, should checkout PR's head commit (detached HEAD) and generate diff
   - `agent.sh diff --github-diff 18726` — GitHub API diff mode, should also checkout PR's head commit and generate diff
3. Verify the ios repo is at the PR's head commit (detached HEAD) after each run
4. `diff -r` the two output directories to confirm identical diff content
5. Also compare against `/Users/bill/Desktop/code-reviews/18726` to confirm consistency with previous runs

**Completed.** Found and fixed a bug: `headRefOid` was missing from the `_PR_FIELDS` list in `GhCommandRunner` (`prradar/infrastructure/github/runner.py`), causing `checkout_commit` to receive an empty string. After adding `"headRefOid"` to `_PR_FIELDS`, all validation passed:
- All 341 tests pass
- Both `agent.sh diff 18726` (local) and `agent.sh diff --github-diff 18726` (GitHub) succeed
- Both modes leave the ios repo in detached HEAD at the correct PR commit (`4fb35c8a7f1`)
- `diff -r` of the two output directories shows identical content
- `headRefOid` is now properly persisted in the saved `gh-pr.json` artifact
