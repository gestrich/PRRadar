# Diff Source Abstraction

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules — layer placement, dependency rules, protocol placement |
| `/swift-testing` | Test style guide for unit tests |

## Background

Running PRRadar in CI on large repositories is expensive because the pipeline requires full git history for operations like `git show <commit>:<file>`, `git merge-base`, `git rev-parse <commit>:<file>`, and `git fetch pull/<N>/head`. In CI (e.g., GitHub Actions), repos are typically shallow-cloned, so these operations either fail or require an expensive `fetch-depth: 0`.

The solution is to abstract the git-history-dependent operations behind a protocol so callers don't know whether they're talking to the local git CLI or the GitHub REST API. A CLI flag (`--diff-source`) lets users choose which backend to use.

**Key constraint from Bill:** The repo will always be available locally (for working directory operations like `git status`, `git remote`, `git rev-parse --show-toplevel`). Only the *git diff/history* may not be available. So the abstraction only needs to cover history-dependent operations, not all git operations.

### Prior Art: ffm-static-analyzer

The `ffm-static-analyzer` repo (`~/Developer/work/ffm-static-analyzer`) already implements this exact pattern in Python with a `GitRepoSource` abstract base class and two implementations:

- **`LocalGitRepo`** — uses `subprocess` to call `git diff`, `git show`, etc.
- **`GithubRepo`** — uses GitHub REST API endpoints

Key API patterns from that repo we should reuse:

| Operation | GitHub API Endpoint | ffm-static-analyzer Pattern |
|-----------|--------------------|-----------------------------|
| File content at commit | `GET /repos/{owner}/{repo}/contents/{path}?ref={commit}` | Uses `Accept: application/vnd.github.v3.raw` header to get raw file content directly (no base64 decoding needed) |
| Merge base / compare | `GET /repos/{owner}/{repo}/compare/{base}...{head}` | Three-dot syntax; response includes `merge_base_commit.sha` |
| Blob SHA | `GET /repos/{owner}/{repo}/contents/{path}?ref={commit}` | JSON response includes `sha` field for the blob |
| PR diff | `GET /repos/{owner}/{repo}/pulls/{number}` with `Accept: application/vnd.github.v3.diff` | Already used in PRRadar's `OctokitClient.getPullRequestDiff` |

The `GithubRepo` implementation also demonstrates URL-encoding file paths (handles spaces/special chars) and the factory auto-detects GitHub vs local based on `GITHUB_TOKEN` availability.

### Git Operations Inventory

**History-dependent (need abstraction):**

| Operation | Current Location | Used By |
|-----------|-----------------|---------|
| `getFileContent(commit:filePath:repoPath:)` | `GitOperationsService:125` | `PRAcquisitionService.runEffectiveDiff` (lines 314-315) |
| `getMergeBase(commit1:commit2:repoPath:)` | `GitOperationsService:157` | `PRAcquisitionService.runEffectiveDiff` (line 305) |
| `getBlobHash(commit:filePath:repoPath:)` | `GitOperationsService:177` | `TaskCreatorService.createTasks` (lines 49, 145) |
| `fetchBranch(remote:branch:repoPath:)` | `GitOperationsService:56` | `PrepareUseCase.execute` (line 125) — fetches `pull/<N>/head` |

**NOT history-dependent (no abstraction needed):**
- `getRemoteURL`, `getRepoRoot`, `getCurrentBranch`, `isGitRepository` — repo metadata only
- `checkWorkingDirectoryClean`, `clean`, `checkoutCommit` — working directory ops
- `diffNoIndex` — arbitrary text comparison, no history needed

### GitHub API Coverage for Replacements

| Git Operation | GitHub API Replacement | Notes |
|---------------|----------------------|-------|
| `getFileContent(commit, filePath)` | `GET /repos/{owner}/{repo}/contents/{path}?ref={commit}` | Use `Accept: application/vnd.github.v3.raw` for raw content (no base64); 1 MB limit per file |
| `getMergeBase(commit1, commit2)` | `GET /repos/{owner}/{repo}/compare/{base}...{head}` | Response includes `merge_base_commit.sha` |
| `getBlobHash(commit, filePath)` | `GET /repos/{owner}/{repo}/git/trees/{commit}?recursive=1` | Find file in tree, read `sha`; OR use contents API `sha` field |
| `fetchBranch` (for PR ref) | Not needed — API-based operations don't require local refs | Skip entirely when using GitHub source |

## Phases

## - [x] Phase 1: Define the `GitHistoryProvider` Protocol

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Protocol placed in Services layer (consumers are services); local implementation is a stateless Sendable struct per SDK conventions; `getRawDiff()` added to unify diff sourcing alongside history operations

**Skills to read**: `/swift-app-architecture:swift-architecture`

Create a protocol in the **Services layer** (since `GitOperationsService` lives in the SDK layer but the consumers are services) that abstracts the history-dependent operations. The protocol should live in a services module so both the git-CLI implementation and the GitHub API implementation can conform.

**Protocol definition** (in `PRRadarCLIService` or a new small module):

```swift
public protocol GitHistoryProvider: Sendable {
    /// Get the raw unified diff for the PR.
    func getRawDiff() async throws -> String

    /// Get the content of a file at a specific commit.
    func getFileContent(commit: String, filePath: String) async throws -> String

    /// Find the merge base between two commits.
    func getMergeBase(commit1: String, commit2: String) async throws -> String

    /// Get the blob hash of a file at a specific commit (for caching).
    func getBlobHash(commit: String, filePath: String) async throws -> String
}
```

Note: the protocol drops `repoPath` from method signatures — each implementation captures that context at initialization time. `getRawDiff()` takes no parameters because each implementation captures its PR context (PR number for GitHub API, base/head branches for local git) at initialization.

**Tasks:**
- Create `GitHistoryProvider` protocol in `PRRadarCLIService`
- Create `LocalGitHistoryProvider` struct wrapping `GitOperationsService` (delegates to existing methods, captures `repoPath`)
- Confirm the protocol compiles and the local implementation passes type checking

## - [x] Phase 2: Add GitHub API Endpoints to `OctokitClient`

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: SDK-level methods are stateless single-operation wrappers; no business logic; follows existing OctokitClient patterns (direct URLSession with Bearer auth, standard error handling)

**Skills to read**: `/swift-app-architecture:swift-architecture`

Extend `OctokitClient` in the **SDK layer** (`GitHubSDK`) with the GitHub REST API endpoints needed to replace local git history operations.

**New methods on `OctokitClient`:**

1. **`getFileContent(owner:repository:path:ref:)`** → `String`
   - Calls `GET /repos/{owner}/{repo}/contents/{path}?ref={ref}`
   - Uses `Accept: application/vnd.github.v3.raw` header to get raw file content directly (pattern from ffm-static-analyzer's `GithubRepo.get_file_content`). This avoids JSON parsing and base64 decoding entirely.
   - URL-encode the `path` parameter (handles spaces and special characters in file paths)
   - Throws for files > 1 MB (GitHub API limit)

2. **`compareCommits(owner:repository:base:head:)`** → `CompareResult`
   - Calls `GET /repos/{owner}/{repo}/compare/{base}...{head}` (three-dot syntax)
   - Returns merge base commit SHA from `merge_base_commit.sha` in response
   - Strip `origin/` prefix from ref names before passing to API (GitHub expects bare branch names)
   - Pattern from ffm-static-analyzer's `GithubRepo.get_compare_diff`

3. **`getFileSHA(owner:repository:path:ref:)`** → `String` (blob SHA)
   - Calls `GET /repos/{owner}/{repo}/contents/{path}?ref={commit}` with standard JSON accept header
   - Reads the `sha` field from the JSON response (same endpoint as file content, different accept header)
   - Simpler than the trees API (one call per file)

**Tasks:**
- Add the three methods to `OctokitClient`
- Add corresponding model types if needed (`CompareResult`, `ContentsMetadata`)
- URL-encode file paths in all three methods
- Keep these as SDK-level concerns — no business logic

## - [x] Phase 3: Create `GitHubAPIHistoryProvider`

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Stateless Sendable struct at Services layer; thin wrapper methods on GitHubService follow existing delegation pattern; removed `ensureRefAvailable` from protocol — ref fetching is a local-only concern, not part of the abstraction

Create a `GitHubAPIHistoryProvider` in `PRRadarCLIService` that conforms to `GitHistoryProvider` and delegates to `GitHubService` / `OctokitClient`.

```swift
public struct GitHubAPIHistoryProvider: GitHistoryProvider {
    private let gitHub: GitHubService
    private let prNumber: Int

    public func getRawDiff() async throws -> String {
        // Delegate to gitHub.getPRDiff(number:)
    }

    public func getFileContent(commit: String, filePath: String) async throws -> String {
        // Delegate to gitHub.getFileContent(path:ref:)
    }

    public func getMergeBase(commit1: String, commit2: String) async throws -> String {
        // Delegate to gitHub.compareCommits(base:head:) → mergeBaseCommitSHA
    }

    public func getBlobHash(commit: String, filePath: String) async throws -> String {
        // Delegate to gitHub.getFileSHA(path:ref:)
    }
}
```

**Tasks:**
- Create `GitHubAPIHistoryProvider` conforming to `GitHistoryProvider`
- Wire to `GitHubService` (add thin wrapper methods on `GitHubService` if needed)
- Handle error mapping (GitHub API errors → `GitHistoryProvider` errors)

## - [x] Phase 4: Refactor Consumers to Use `GitHistoryProvider`

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Services accept protocol, not concrete types; `repoPath` removed from method signatures where provider captures it; `PrepareUseCase` uses optional provider parameter for forward compatibility with Phase 5 factory wiring; `fetchBranch` conditional on `is LocalGitHistoryProvider` check; rule blob hashes remain on concrete `GitOperationsService` (always local)

Refactor the three call sites that depend on git history to accept `GitHistoryProvider` instead of `GitOperationsService`:

### 4a: `PRAcquisitionService.acquire` and `runEffectiveDiff`

`acquire()` currently calls `gitHub.getPRDiff(number:)` for the raw diff. `runEffectiveDiff()` calls `gitOps.getMergeBase(...)` and `gitOps.getFileContent(...)`.

- Change the `PRAcquisitionService` initializer to accept `GitHistoryProvider` alongside the existing `GitOperationsService` (still needed for `diffNoIndex`)
- Replace `gitHub.getPRDiff(number:)` with `historyProvider.getRawDiff()` in `acquire()`
- Update `runEffectiveDiff` to use `historyProvider.getMergeBase(...)` and `historyProvider.getFileContent(...)`
- Keep `gitOps.diffNoIndex(...)` on the concrete `GitOperationsService` — it doesn't need the protocol (no history required)

### 4b: `TaskCreatorService`

Currently calls `gitOps.getBlobHash(...)` (lines 49, 145) and `gitOps.isGitRepository/getRepoRoot` (lines 122-123).

- Change `TaskCreatorService` to accept `GitHistoryProvider` for blob hash operations
- Keep `GitOperationsService` for `isGitRepository` and `getRepoRoot` (not history-dependent)
- The `resolveRuleBlobHash` method also uses `getBlobHash` on the rules repo — this still uses local git since rules are always local. Use a separate `GitHistoryProvider` instance for the rules repo, or keep using `GitOperationsService` directly for rule blob hashes (simpler, since rules repo is always local).

### 4c: `PrepareUseCase`

Currently calls `gitOps.fetchBranch(remote: "origin", branch: "pull/\(prNumber)/head")` (line 125).

- Keep `gitOps.fetchBranch()` call on `GitOperationsService` directly — ref fetching is a local-only concern, not part of the `GitHistoryProvider` abstraction
- When using GitHub API source, skip the fetch (check diff source or wrap in a conditional)

**Tasks:**
- Update `PRAcquisitionService` init to accept `GitHistoryProvider`
- Replace `gitHub.getPRDiff(number:)` with `historyProvider.getRawDiff()` in `acquire()`
- Update `runEffectiveDiff` to use `historyProvider.getMergeBase(...)` and `historyProvider.getFileContent(...)`
- Update `TaskCreatorService` to use `GitHistoryProvider` for source file blob hashes
- Update `PrepareUseCase` to skip `fetchBranch` when using GitHub API source
- Keep rules repo blob hashes on concrete `GitOperationsService` (always local)

## - [x] Phase 5: Add `--diff-source` CLI Flag and Factory Wiring

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: DiffSource enum in Services layer (PRRadarConfigService) since it's a shared config type; factory method on GitHubServiceFactory keeps provider construction centralized; both SyncPRUseCase and PrepareUseCase use the factory consistently; CLI override pattern matches existing repoPath/outputDir override approach; backward-compatible JSON decoding defaults to `.git`

Add a CLI option to select the diff source and wire it through configuration to the use cases.

### CLI Flag

Add to `CLIOptions`:
```swift
@Option(name: .long, help: "Diff source: 'git' (local git history) or 'github-api' (GitHub REST API). Default: git")
var diffSource: DiffSource?
```

Where `DiffSource` is an enum:
```swift
public enum DiffSource: String, Codable, Sendable, ExpressibleByArgument {
    case git
    case githubAPI = "github-api"
}
```

### Factory

Update `GitHubServiceFactory` (or create a new factory) to build the appropriate `GitHistoryProvider`:

```swift
public static func createHistoryProvider(
    diffSource: DiffSource,
    repoPath: String,
    gitHub: GitHubService,
    gitOps: GitOperationsService
) -> GitHistoryProvider {
    switch diffSource {
    case .git:
        return LocalGitHistoryProvider(gitOps: gitOps, repoPath: repoPath)
    case .githubAPI:
        return GitHubAPIHistoryProvider(gitHub: gitHub)
    }
}
```

### Wiring

- Pass `DiffSource` through `RepositoryConfiguration` or as a separate parameter to use cases
- `SyncPRUseCase` and `PrepareUseCase` use the factory to get the right provider
- Default to `.git` when flag is not specified (preserves existing behavior)

### Mac App Setting

Add a diff source picker to the Mac app's configuration UI so users can toggle between `git` and `github-api` for debugging. Store the selection in `RepositoryConfiguration` alongside the CLI flag so both entry points share the same setting.

**Tasks:**
- Define `DiffSource` enum in `PRRadarModels` or `PRRadarConfigService`
- Add `--diff-source` to `CLIOptions`
- Add `diffSource` field to `RepositoryConfiguration` (persisted, defaults to `.git`)
- Update `resolveConfigFromOptions` to pass diff source through
- Update `GitHubServiceFactory` with `createHistoryProvider()`
- Wire through `SyncPRUseCase` and `PrepareUseCase` to pass `GitHistoryProvider` to services
- Add diff source picker to Mac app configuration view

## - [x] Phase 6: Validation

**Skills used**: `swift-testing`
**Principles applied**: Arrange-Act-Assert pattern with `// Arrange`, `// Act`, `// Assert` comments; `MockGitHistoryProvider` with call tracking for verifying delegation; factory tests verify correct concrete type returned; SyncPRUseCase audit replaced silent `?? "main"` / `?? "HEAD"` defaults with guard/throw

**Skills to read**: `/swift-testing`

### Unit Tests

- Test `LocalGitHistoryProvider` delegates correctly to `GitOperationsService` methods
- Test `GitHubAPIHistoryProvider` calls the right GitHub API endpoints
- Test that `DiffSource` enum parses correctly from CLI strings
- Test `TaskCreatorService` works with a mock `GitHistoryProvider`
- Test `PRAcquisitionService.runEffectiveDiff` works with a mock `GitHistoryProvider`
- Audit `SyncPRUseCase` fallback defaults for `baseRefName`/`headRefName` — these should always be present from the GitHub API; replace defensive `?? "main"` / `?? "HEAD"` with a thrown error if nil

### Build Verification

```bash
cd PRRadarLibrary
swift build
swift test
```

### Manual Smoke Test

```bash
# Default (git source — existing behavior)
swift run PRRadarMacCLI analyze 1 --config test-repo

# Explicit git source
swift run PRRadarMacCLI analyze 1 --config test-repo --diff-source git

# GitHub API source
swift run PRRadarMacCLI analyze 1 --config test-repo --diff-source github-api
```

Verify that both diff sources produce the same (or equivalent) output for the test repo PR.

## - [ ] Phase 7: End-to-End CI Validation with PRRadar-TestRepo

Validate the full GitHub API diff source in CI by updating the test repo workflow, creating a PR with violations, and confirming comments are posted.

### 7a: Update the Workflow in PRRadar-TestRepo

The current workflow at `/Users/bill/Developer/personal/PRRadar-TestRepo/.github/workflows/pr-review.yml` uses `fetch-depth: 0` (full git history). Update it to:

1. **Change checkout depth to shallow clone** — set `fetch-depth: 1` for the test repo checkout step (line 50). This proves the GitHub API source works without git history.

2. **Add `--diff-source github-api`** to the `sync` and `prepare` commands:
   ```yaml
   - name: Run sync
     run: |
       cd prradar-tool/PRRadarLibrary
       swift run -c release PRRadarMacCLI sync ${{ steps.pr.outputs.number }} \
         --config ci \
         --output-dir /tmp/prradar-output \
         --diff-source github-api

   - name: Run prepare
     run: |
       cd prradar-tool/PRRadarLibrary
       swift run -c release PRRadarMacCLI prepare ${{ steps.pr.outputs.number }} \
         --config ci \
         --output-dir /tmp/prradar-output \
         --diff-source github-api
   ```

3. **Push the workflow change** to the `main` branch of PRRadar-TestRepo.

### 7b: Create a Test PR with Intentional Violations

Create a branch in PRRadar-TestRepo with code that triggers existing rules:

- Add a force-unwrap (`let x = optional!`) to trigger `detect-force-unwrap.md`
- Add a bare division without error handling to trigger `guard-divide-by-zero.md`
- Open a PR from this branch against `main`

### 7c: Verify CI Comments

After the workflow runs on the new PR:

1. Check the GitHub Actions run logs — confirm `sync` and `prepare` used the GitHub API source (no `git fetch` / `git show` commands)
2. Verify that inline review comments were posted on the PR for the violations
3. Confirm the effective diff output is equivalent to what the git source produces (compare artifacts if needed)

### Success Criteria

- Workflow runs to completion with `fetch-depth: 1` (shallow clone)
- No git history errors in logs
- Review comments posted on the PR matching expected violations
- The `--diff-source github-api` flag is the only change needed (no other workflow modifications)
