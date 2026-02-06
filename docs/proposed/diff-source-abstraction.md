# Diff Source Abstraction Implementation Plan

## Overview

Create an abstraction layer that allows switching between GitHub API and local git for diff acquisition. Both sources must produce identical hunk format to feed into the same downstream pipeline.

### PR-Centric Workflow (Important!)

**PRRadar is fundamentally a PR review tool.** This means:

1. **Always start with a PR number** - Users provide PR number as argument
2. **Always use GitHub API for metadata** - Get branch names, base/head commits from GitHub
3. **Local git is optional** - Only checkout locally if user passes `--source local` flag
4. **Default is GitHub API** - Keeps workflow simple, no local repo required

**Example workflow:**
```bash
# Default: Use GitHub API for everything
prradar agent analyze 123

# Optional: Use local git for diff (still gets PR metadata from GitHub)
prradar agent analyze 123 --source local
```

This enables:
- **Local development workflow**: Test rules against local branches before pushing
- **Large diff handling**: Local git can handle arbitrarily large diffs
- **Safety**: Local checkout only happens when explicitly requested
- **Flexibility**: Choose the most appropriate source for each use case

## Existing Code Reference

**Excellent news!** Bill's `/Users/bill/Downloads/ff-ffm-static-analyzer` repo already has a working implementation of this pattern in the `repo_tools/` directory:

> **Note on Architecture:** This implementation should follow patterns from Bill's [python-architecture](https://github.com/gestrich/python-architecture) skills. Each task below references relevant skills where applicable (domain modeling, dependency injection, CLI architecture, testing, etc.).

- **`git_repo_source.py`** - Abstract base class defining the provider interface
- **`local_git_repo.py`** - Local git implementation using subprocess
- **`github_repo.py`** - GitHub API implementation using requests library
- **`git_diff.py`** - Domain model for parsed diffs with hunk parsing

This code can be adapted and brought into PRRadar, saving significant implementation time.

### Key Features of Existing Code

✅ **Abstract provider pattern** - `GitRepoSource` ABC with `get_commit_diff()` and `get_file_content()`
✅ **Local git support** - Uses `git diff` and `git show` via subprocess
✅ **GitHub API support** - Supports PRs, commits, and branch comparisons
✅ **File content retrieval** - Both sources can fetch full file content at specific commits
✅ **Unified diff parsing** - `GitDiff.from_diff_content()` parses raw diffs into structured hunks

### Adaptation Strategy

1. Copy `repo_tools/` files into PRRadar's `plugin/skills/pr-review/scripts/infrastructure/`
2. Update imports to match PRRadar's structure
3. Integrate with existing `domain/diff.py` and `domain/hunk.py` models
4. Add CLI flags to `commands/agent/diff.py` for source selection
5. Replace current `gh pr diff` usage with the provider pattern

## Phases

## - [x] Phase 1: Copy Existing Code from ff-ffm-static-analyzer ✅

Copy the proven implementation from Bill's existing repo to jumpstart the implementation.

**Tasks:**
- ✅ Copy the following files from `/Users/bill/Downloads/ff-ffm-static-analyzer/repo_tools/`:
  - `git_repo_source.py` → `infrastructure/repo_source.py`
  - `local_git_repo.py` → `infrastructure/local_git_repo.py`
  - `github_repo.py` → `infrastructure/github_repo.py`
  - `git_diff.py` (copied as reference - will be adapted to PRRadar's domain models)
  - `hunk.py` (copied as reference - will be adapted to PRRadar's domain models)

**Files created:**
- `plugin/skills/pr-review/scripts/infrastructure/repo_source.py`
- `plugin/skills/pr-review/scripts/infrastructure/local_git_repo.py`
- `plugin/skills/pr-review/scripts/infrastructure/github_repo.py`
- `plugin/skills/pr-review/scripts/infrastructure/git_diff.py`
- `plugin/skills/pr-review/scripts/infrastructure/hunk.py`

**Technical notes:**
- All files copied with minimal modifications (only import adjustments)
- Updated `infrastructure/__init__.py` to export new classes
- All new modules import successfully
- Build passes: 110/111 tests pass (1 unrelated failure due to missing claude_agent_sdk)
- Code ready for adaptation in Phase 2

**Expected outcomes:**
- ✅ Existing code copied into PRRadar structure
- ✅ Ready for adaptation in next phase

---

## - [x] Phase 2: Adapt Code to PRRadar Structure ✅

**Skills to reference:**
- [python-architecture:domain-modeling](https://github.com/gestrich/python-architecture) for adapting domain models
- [python-architecture:creating-services](https://github.com/gestrich/python-architecture) for service layer patterns

Adapt the copied code to work with PRRadar's architecture and PR-centric workflow.

**Tasks:**
- ✅ Rename `GitRepoSource` → `DiffProvider`
- ✅ Update method signatures to match PRRadar's needs:
  - `get_commit_diff(commit_hash)` → `get_pr_diff(pr_number) -> str`
  - Keep `get_file_content(file_path, commit_hash)` for future focus area work
- ✅ **PR-centric workflow changes:**
  - Both providers always fetch PR metadata from GitHub first (base/head branches)
  - GitHub provider: Uses diff from API response (via `gh pr diff`)
  - Local provider: Uses branch names to compute `git diff origin/base...origin/head`
- ✅ Update imports to use PRRadar's `domain/diff.py` and `domain/hunk.py` models
- ✅ Replace `requests` library calls with `gh` CLI (for consistency with existing PRRadar code)
- ✅ Add error handling consistent with PRRadar's patterns
- ✅ **Add safety checks to LocalGitRepo:**
  - Check for uncommitted changes before any git operations (`git status --porcelain`)
  - Abort with clear error if working directory is dirty
  - Detect if running in valid git repository
  - Provide helpful error messages

**Architecture: Git Operations Service Layer (IMPORTANT!)**

Following python-architecture patterns, **all raw git commands must be put behind a service**:

- ✅ **Create `GitOperationsService`** in `services/git_operations.py`:
  - Encapsulates all `subprocess` calls to git commands
  - Returns domain models (not raw strings) where relevant
  - Reusable across the entire application
  - Single source of truth for git operations

- ✅ **DO NOT call git commands directly** from providers:
  ```python
  # ❌ WRONG - Raw git command in provider
  subprocess.run(['git', 'status', '--porcelain'], ...)

  # ✅ RIGHT - Delegate to GitOperationsService
  self.git_service.check_working_directory_clean()
  ```

- ✅ **Return domain models** from git service:
  ```python
  class GitOperationsService:
      def get_branch_diff(self, base: str, head: str) -> str:
          """Returns raw diff text."""

      def check_working_directory_clean(self) -> bool:
          """Returns True if clean, raises exception if dirty."""

      def fetch_branch(self, branch_name: str) -> None:
          """Fetches branch from remote."""
  ```

- **Benefits of service layer**:
  - ✅ Reusable git operations across all of PRRadar
  - ✅ Testable with mocks (don't need actual git repo for tests)
  - ✅ Single place to update git command patterns
  - ✅ Clear separation: Providers orchestrate, GitService executes

**Files modified:**
- `infrastructure/repo_source.py` (renamed to DiffProvider interface)
- `infrastructure/local_git_repo.py` (PR workflow + GitOperationsService integration)
- `infrastructure/github_repo.py` (gh CLI implementation)
- `services/git_operations.py` (new git command service layer)
- `services/__init__.py` (export GitOperationsService and exceptions)
- `infrastructure/__init__.py` (export DiffProvider)

**Technical notes:**
- **GitOperationsService created** with comprehensive git operations:
  - `check_working_directory_clean()` - Safety checks for dirty working directory
  - `fetch_branch()` - Fetch branches from remote
  - `get_branch_diff()` - Generate diff between branches
  - `is_git_repository()` - Validate git repository
  - `get_file_content()` - Retrieve file content at specific commit
  - All methods include proper error handling with custom exceptions
- **LocalGitRepo updated** to use PR-centric workflow:
  - Constructor-based dependency injection of GitOperationsService
  - Fetches PR metadata from GitHub API using `gh pr view`
  - Safety checks via GitOperationsService before git operations
  - Uses local git for diff generation via service layer
  - No raw subprocess calls in provider code
- **GithubRepo simplified** to use gh CLI:
  - Removed requests library dependency
  - Uses `gh pr diff` for PR diffs
  - Uses `gh api` for file content retrieval
  - Consistent with PRRadar's existing patterns
- **DiffProvider interface** updated with `get_pr_diff()` method
- **Custom exceptions** added for all git operation error cases
- **Build succeeds**: 110/111 tests pass (1 unrelated failure due to missing claude_agent_sdk)

**Expected outcomes:**
- ✅ Code adapted to PRRadar conventions
- ✅ PR-centric workflow implemented
- ✅ Safety checks in place for local git operations
- ✅ Git operations behind reusable service layer
- ✅ Both providers ready to use

---

## - [x] Phase 3: Create Provider Factory and Domain Enum ✅

**Skills to reference:** [python-architecture:dependency-injection](https://github.com/gestrich/python-architecture) for factory pattern

Create the factory pattern and enum for selecting diff sources.

**Tasks:**
- ✅ Add `DiffSource` enum to domain: `GITHUB_API`, `LOCAL_GIT`
- ✅ Create factory function in `infrastructure/diff_provider_factory.py`
- ✅ Update domain/__init__.py to export DiffSource
- ✅ Update infrastructure/__init__.py to export create_diff_provider

**Files created:**
- `domain/diff_source.py` (enum with from_string method)
- `infrastructure/diff_provider_factory.py` (factory function)

**Technical notes:**
- **DiffSource enum** provides two values: GITHUB_API and LOCAL_GIT
- **from_string() class method** for parsing CLI arguments (case-insensitive)
- **Factory function** follows dependency injection pattern:
  - GitHub provider: Simple construction with repo_owner/repo_name
  - Local provider: Creates GitOperationsService and injects into LocalGitRepo
  - Accepts **kwargs for extensibility (e.g., local_repo_path)
- **Clean abstractions**:
  - Factory handles GitOperationsService instantiation
  - Consumers only work with DiffProvider interface
  - Easy to add new source types in the future
- **Build succeeds**: 110/111 tests pass (1 unrelated failure due to missing claude_agent_sdk)
- All new modules import successfully and are exported correctly

**Expected outcomes:**
- ✅ Clean dependency injection pattern
- ✅ GitOperationsService properly injected into LocalGitRepo
- ✅ Easy to switch between providers
- ✅ Extensible for future sources

---

## - [x] Phase 4: CLI Integration ✅

**Skills to reference:** [python-architecture:cli-architecture](https://github.com/gestrich/python-architecture) for command structure

Integrate the provider pattern into the CLI commands.

**Tasks:**
- ✅ Update `commands/agent/diff.py` to accept `--source github|local` flag (default: github)
- ✅ Add `--local-repo-path` optional argument (defaults to current directory)
- ✅ Replace direct `gh pr diff` calls with provider pattern
- ✅ Ensure output format remains unchanged for downstream compatibility
- ✅ **Workflow implementation:**
  1. Parse PR number from arguments
  2. Create provider using factory (based on --source flag)
  3. Provider fetches PR metadata from GitHub API (both sources do this)
  4. Provider fetches diff (GitHub API or local git, depending on source)
  5. Write diff to output file (same format regardless of source)

**Files modified:**
- `commands/agent/__init__.py` (added CLI arguments for --source and --local-repo-path)
- `commands/agent/diff.py` (updated to use provider factory instead of direct gh pr diff)
- `commands/agent/analyze.py` (updated to pass source arguments through pipeline)

**Technical notes:**
- **CLI arguments added to both `diff` and `analyze` commands:**
  - `--source {github,local}` - Choose diff source (default: github)
  - `--local-repo-path` - Optional path to local git repo (default: current directory)
- **cmd_diff updated to use provider pattern:**
  - Auto-detects repository from gh CLI (`gh repo view`)
  - Parses DiffSource enum from CLI argument
  - Creates appropriate provider via factory
  - Handles exceptions from provider operations
  - Output format unchanged - same artifacts produced
- **cmd_analyze passes arguments through:**
  - Added source and local_repo_path parameters to signature
  - Passes through to cmd_diff call in Phase 1
  - Full pipeline supports both diff sources
- **Backward compatibility maintained:**
  - Default behavior unchanged (GitHub API)
  - Existing workflows continue to work
  - Optional flags only affect behavior when specified
- **Build succeeds:** 110/111 tests pass (1 unrelated failure due to missing claude_agent_sdk)

**Expected outcomes:**
- ✅ Users can choose diff source via CLI flag
- ✅ Default behavior unchanged (GitHub API)
- ✅ Local git support available when needed
- ✅ Same output format regardless of source

**Usage examples:**
```bash
# Default: Use GitHub API for diff
prradar agent diff 123

# Use local git for diff
prradar agent diff 123 --source local

# Full pipeline with local git
prradar agent analyze 123 --source local

# Specify explicit repo path
prradar agent diff 123 --source local --local-repo-path ~/my-project
```

---

## - [ ] Phase 5: Testing and Validation

**Skills to reference:** [python-architecture:testing-services](https://github.com/gestrich/python-architecture) for service testing patterns

Thoroughly test both providers and ensure safety checks work correctly.

**Tasks:**

**Unit tests:**
- Test `DiffSource` enum
- Test factory creates correct provider types
- **Test `GitOperationsService` with mocked subprocess:**
  - Mock subprocess calls, verify correct commands
  - Test error handling (dirty repo, fetch failures)
  - Test domain exception raising
- **Test providers with mocked `GitOperationsService`:**
  - Mock git_service methods in LocalGitRepo
  - Verify provider orchestrates service correctly
  - Mock GitHub API calls in GithubRepo

**Integration tests:**
- Test GitHub provider with existing PRs
- Test local provider in a cloned repository
- Verify both produce identical diff format
- **Test GitOperationsService in real git repo:**
  - Test with clean working directory
  - Test with dirty working directory (should fail)
  - Test branch fetching

**Safety check tests (critical!):**
- Test with uncommitted changes → should abort with error
- Test with staged changes → should abort with error
- Test with clean working directory → should proceed
- Verify error messages are clear and actionable

**Error case tests:**
- Missing repo / not in git directory
- Invalid PR number
- Network failures (GitHub API)
- Branch doesn't exist locally
- No permission to fetch branch

**Manual validation:**
- Run `prradar agent diff <pr-number>` (default GitHub)
- Run `prradar agent diff <pr-number> --source local` (local git)
- Compare outputs - should be identical
- Test with dirty working directory - should fail with clear message
- Test full pipeline: `prradar agent analyze <pr-number> --source local`

**Files created:**
- `tests/test_diff_provider_factory.py`
- `tests/test_github_repo.py`
- `tests/test_local_git_repo.py`
- `tests/test_git_operations_service.py` (unit tests with mocked subprocess)
- `tests/integration/test_git_operations_integration.py` (real git repo tests)

**Expected outcomes:**
- ✅ All tests passing
- ✅ GitOperationsService thoroughly tested in isolation
- ✅ Both providers produce identical output
- ✅ Safety checks prevent data loss
- ✅ Clear error messages for all failure modes
- ✅ Service layer properly mocked in provider tests
- ✅ Ready for production use

---

## Implementation Details

### GitOperationsService (New - Core Service)

**Skills reference:** [python-architecture:creating-services](https://github.com/gestrich/python-architecture)

All raw git commands must go through this service. This is a **Core Service** that provides reusable git operations.

```python
import subprocess
from pathlib import Path
from typing import Optional


class GitOperationsService:
    """Core service for git command operations.

    Encapsulates all subprocess calls to git commands.
    Returns domain models where relevant.
    Reusable across the entire application.
    """

    def __init__(self, repo_path: str = '.'):
        """Initialize with repository path.

        Args:
            repo_path: Path to git repository (default: current directory)
        """
        self.repo_path = Path(repo_path)

    def check_working_directory_clean(self) -> bool:
        """Check if working directory has uncommitted changes.

        Returns:
            True if clean

        Raises:
            GitDirtyWorkingDirectoryError: If uncommitted changes detected
        """
        result = subprocess.run(
            ['git', 'status', '--porcelain'],
            cwd=self.repo_path,
            capture_output=True,
            text=True,
            check=True
        )

        if result.stdout.strip():
            raise GitDirtyWorkingDirectoryError(
                "Cannot proceed - uncommitted changes detected. "
                "Commit or stash your changes:\n"
                "  git stash\n"
                "  git commit -am 'WIP'\n"
                "Then try again."
            )

        return True

    def fetch_branch(self, branch_name: str, remote: str = 'origin') -> None:
        """Fetch branch from remote.

        Args:
            branch_name: Branch to fetch
            remote: Remote name (default: origin)

        Raises:
            GitFetchError: If fetch fails
        """
        try:
            subprocess.run(
                ['git', 'fetch', remote, branch_name],
                cwd=self.repo_path,
                capture_output=True,
                text=True,
                check=True
            )
        except subprocess.CalledProcessError as e:
            raise GitFetchError(f"Failed to fetch {remote}/{branch_name}: {e.stderr}")

    def get_branch_diff(self, base_branch: str, head_branch: str, remote: str = 'origin') -> str:
        """Get diff between two branches.

        Args:
            base_branch: Base branch name
            head_branch: Head branch name
            remote: Remote name (default: origin)

        Returns:
            Raw unified diff text

        Raises:
            GitDiffError: If diff command fails
        """
        try:
            result = subprocess.run(
                ['git', 'diff', f'{remote}/{base_branch}...{remote}/{head_branch}'],
                cwd=self.repo_path,
                capture_output=True,
                text=True,
                check=True
            )
            return result.stdout
        except subprocess.CalledProcessError as e:
            raise GitDiffError(f"Failed to compute diff: {e.stderr}")

    def is_git_repository(self) -> bool:
        """Check if current directory is a git repository.

        Returns:
            True if valid git repo, False otherwise
        """
        try:
            subprocess.run(
                ['git', 'rev-parse', '--git-dir'],
                cwd=self.repo_path,
                capture_output=True,
                check=True
            )
            return True
        except subprocess.CalledProcessError:
            return False

    def get_file_content(self, file_path: str, commit_hash: str) -> str:
        """Get file content at specific commit.

        Args:
            file_path: Path to file in repository
            commit_hash: Git commit SHA or branch name

        Returns:
            File content as string

        Raises:
            GitFileNotFoundError: If file doesn't exist at commit
        """
        try:
            result = subprocess.run(
                ['git', 'show', f'{commit_hash}:{file_path}'],
                cwd=self.repo_path,
                capture_output=True,
                text=True,
                check=True
            )
            return result.stdout
        except subprocess.CalledProcessError as e:
            raise GitFileNotFoundError(
                f"File {file_path} not found at {commit_hash}: {e.stderr}"
            )
```

**Usage in LocalGitRepo provider:**

```python
class LocalGitRepo(DiffProvider):
    def __init__(self, repo_owner: str, repo_name: str, local_path: str = '.'):
        self.repo_owner = repo_owner
        self.repo_name = repo_name
        # Inject GitOperationsService
        self.git_service = GitOperationsService(local_path)

    def get_pr_diff(self, pr_number: int) -> str:
        # Step 1: Safety check via service
        self.git_service.check_working_directory_clean()

        # Step 2: Get PR metadata from GitHub
        pr_details = self._get_pr_metadata_from_github(pr_number)
        base_branch = pr_details['base_branch']
        head_branch = pr_details['head_branch']

        # Step 3: Fetch branches via service
        self.git_service.fetch_branch(base_branch)
        self.git_service.fetch_branch(head_branch)

        # Step 4: Get diff via service
        return self.git_service.get_branch_diff(base_branch, head_branch)
```

**Key benefits:**
- ✅ **Reusable**: Any part of PRRadar can use GitOperationsService
- ✅ **Testable**: Mock the service in tests, not subprocess calls
- ✅ **Maintainable**: Update git command patterns in one place
- ✅ **Type-safe**: Returns domain models, not raw subprocess results

---

### DiffProvider Interface (from existing code)

The existing `GitRepoSource` from ff-ffm-static-analyzer provides the pattern:

```python
from abc import ABC, abstractmethod

class GitRepoSource(ABC):
    """Abstract base class for git repository sources."""

    @abstractmethod
    def get_commit_diff(self, commit_hash: str) -> GitDiff:
        """Get the diff for a specific commit."""
        pass

    @abstractmethod
    def get_file_content(self, file_path: str, commit_hash: str) -> str:
        """Get the content of a file at a specific commit."""
        pass
```

**Adaptation for PRRadar:** Extend this to add PR-specific methods:

```python
from abc import ABC, abstractmethod
from domain.diff_source import DiffSource

class DiffProvider(ABC):
    @abstractmethod
    def get_pr_diff(self, pr_number: int) -> str:
        """
        Fetch unified diff for the given PR.

        Returns raw unified diff text in git format.
        Both implementations must return identical format.
        """
        pass

    @abstractmethod
    def get_file_content(self, file_path: str, commit_hash: str) -> str:
        """Get full file content at specific commit (for focus area generation)."""
        pass

    @abstractmethod
    def get_source_type(self) -> DiffSource:
        """Return the source type for this provider."""
        pass
```

### LocalGitRepo Implementation (existing code reference)

The existing implementation uses subprocess for git operations:

```python
class LocalGitRepo(GitRepoSource):
    def get_commit_diff(self, commit_hash: str) -> GitDiff:
        subprocess.run(['git', 'fetch', "origin", commit_hash], ...)
        result = subprocess.run(['git', 'diff', f"{commit_hash}^", f"{commit_hash}"], ...)
        return GitDiff.from_diff_content(result.stdout, commit_hash=commit_hash)
```

**For PRRadar - PR-centric workflow adaptation (with GitOperationsService):**

```python
class LocalGitRepo(DiffProvider):
    def __init__(self, repo_owner: str, repo_name: str, git_service: GitOperationsService):
        """Initialize with dependencies.

        Args:
            repo_owner: GitHub repository owner
            repo_name: GitHub repository name
            git_service: Service for git operations (injected)
        """
        self.repo_owner = repo_owner
        self.repo_name = repo_name
        self.git_service = git_service  # Injected dependency

    def get_pr_diff(self, pr_number: int) -> str:
        # Step 1: Get PR metadata from GitHub API (ALWAYS uses GitHub)
        pr_details = self._get_pr_metadata_from_github(pr_number)
        base_branch = pr_details['base_branch']
        head_branch = pr_details['head_branch']

        # Step 2: Safety check via GitOperationsService
        self.git_service.check_working_directory_clean()

        # Step 3: Fetch branches via GitOperationsService
        self.git_service.fetch_branch(base_branch)
        self.git_service.fetch_branch(head_branch)

        # Step 4: Get diff via GitOperationsService
        return self.git_service.get_branch_diff(base_branch, head_branch)

    def _get_pr_metadata_from_github(self, pr_number: int) -> dict:
        """Fetch PR metadata from GitHub API using gh CLI."""
        # Implementation uses gh CLI to get branch names
        ...
```

**Key changes:**
1. **Always fetches PR metadata from GitHub** - Gets branch names from API
2. **GitOperationsService injected via constructor** - Follows dependency injection pattern
3. **No raw subprocess calls** - Delegates all git operations to service
4. **Safety checks via service** - `git_service.check_working_directory_clean()`
5. **Uses branch names, not commit SHAs** - `git diff origin/base...origin/head`
6. **No actual checkout** - Can diff remote branches without checking out
7. **Returns raw diff string** - Same format as GitHub API
8. **Testable** - Can mock `git_service` in tests

### GithubRepo Implementation (existing code reference)

The existing implementation has both PR and commit support:

```python
class GithubRepo(GitRepoSource):
    def get_pull_request_diff(self, pr_number: int) -> GitDiff:
        url = f"https://api.github.com/repos/{self.owner}/{self.repo}/pulls/{pr_number}"
        response = requests.get(url, headers=self.headers)
        git_diff = GitDiff.from_diff_content(response.text, commit_hash=head_sha)
        return git_diff
```

**For PRRadar - simplified, using gh CLI:**

```python
class GithubRepo(DiffProvider):
    def __init__(self, repo_owner: str, repo_name: str):
        self.repo_owner = repo_owner
        self.repo_name = repo_name

    def get_pr_diff(self, pr_number: int) -> str:
        """
        Fetch PR diff from GitHub API.
        This is the default and simplest path - no local repo required.
        """
        # Use gh CLI (already handles auth, simpler than requests)
        result = subprocess.run(
            ['gh', 'pr', 'diff', str(pr_number), '--repo', f'{self.repo_owner}/{self.repo_name}'],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout
```

**For PRRadar:** Using `gh` CLI is recommended because:
- ✅ Already used by PRRadar (consistency)
- ✅ Handles authentication automatically
- ✅ Simpler than managing API tokens with `requests`
- ✅ Same output format as `requests` approach

### Usage Example

```bash
# Default: Use GitHub API for everything (no local repo needed)
prradar agent diff 123

# Use local git for diff (still gets PR metadata from GitHub)
# Must be run from within the git repository
prradar agent diff 123 --source local

# Use local git with explicit repo path
prradar agent diff 123 --source local --local-repo-path ~/my-project

# Full pipeline examples
prradar agent analyze 123                    # GitHub API (default)
prradar agent analyze 123 --source local     # Local git for large diffs
```

**Important workflow notes:**
1. **PR number is always required** - This is a PR review tool
2. **GitHub API is always used for metadata** - Gets branch names, PR details
3. **--source local only affects diff acquisition** - Everything else uses GitHub
4. **Safety:** Local source checks for uncommitted changes before proceeding
5. **Default is safest:** GitHub API requires no local setup or repo

## Open Questions

### Adaptation Decisions

1. **GitHub API approach:** Should we use:
   - **`requests` library** (as existing code does) - More direct, but requires token management
   - **`gh` CLI tool** (as PRRadar currently uses) - Simpler auth, consistent with existing code
   - **Recommendation:** Start with `gh` CLI for consistency, can add `requests` option later

2. **Local git strategy (UPDATED - No checkout needed!):**
   - **✅ Recommended: Fetch only, no checkout** - Use `git diff origin/base...origin/head`
   - **Advantages:**
     - No working directory modification
     - No risk of overwriting user work (but still check for safety)
     - Can diff remote branches without local checkout
     - Faster and safer than actual checkout
   - **When to actually checkout:**
     - Only if we need to run tests or scripts on the PR branch (future feature)
     - For now, just fetch remote branches and diff them
   - **Safety check still required:** Even without checkout, verify clean working directory before running git operations

3. **Domain model integration:** Should we:
   - **Keep both** - Use existing `GitDiff` model alongside PRRadar's `Diff/Hunk` models
   - **Merge models** - Consolidate into single set of domain models
   - **Convert at boundary** - Providers return `GitDiff`, convert to PRRadar `Diff` at service layer
   - **Recommendation:** Convert at boundary - keeps provider code simple, maintains PRRadar conventions

### Implementation Questions

4. **Error handling:** How should we handle cases where:
   - Local repo is dirty (uncommitted changes)?
   - PR branch doesn't exist locally?
   - Base branch is outdated?
   - **Existing code approach:** Prints error and exits. PRRadar may want more graceful handling.

5. **Performance:** Should we cache local checkouts/worktrees between runs for the same PR?
   - Existing code fetches on each run (safe but slower)
   - Could cache and only re-fetch if PR has new commits

6. **Repository path detection:** When using local git:
   - Should we auto-detect from current directory (as existing code assumes)?
   - Require explicit `--local-repo-path` argument?
   - Search upward for `.git` directory?

## Dependencies

None - this is a foundational phase that other features will build upon.

## Follow-up Work

Once diff source abstraction is complete, it enables:
- **Focus Area Generation** (Phase 3): Can analyze full file content from local checkout
- **Large diff handling**: Local git can handle arbitrarily large diffs
- **Interactive development**: Test rules on local branches before pushing

## Benefits of Using Existing Code

Adapting the ff-ffm-static-analyzer code provides several advantages:

1. **✅ Proven implementation** - Code is already tested and working in production
2. **✅ Time savings** - Reduces implementation from ~2-3 days to ~0.5-1 day
3. **✅ Both sources implemented** - Gets local AND GitHub support immediately
4. **✅ File content support** - `get_file_content()` already exists for focus area work
5. **✅ Clean architecture** - Abstract base class pattern matches PRRadar's style
6. **✅ Error handling** - Basic error handling already in place
7. **✅ PR metadata** - GitHub provider already has `get_pull_request_details()`

## Next Steps

1. Review existing code in `/Users/bill/Downloads/ff-ffm-static-analyzer/repo_tools/`
2. Decide on adaptation approach (see Open Questions)
3. Copy and adapt code following Tasks section
4. Test with both GitHub and local sources
5. Update documentation

## References

- **Existing code location:** `/Users/bill/Downloads/ff-ffm-static-analyzer/repo_tools/`
  - `git_repo_source.py` - Abstract base class
  - `local_git_repo.py` - Local git implementation
  - `github_repo.py` - GitHub API implementation
  - `git_diff.py` - Diff parsing (for reference)
  - `hunk.py` - Hunk parsing (for reference)

- **Original research:** Bill mentioned checking `~/Developer/personal/` for existing git diff code. The `git-tools` repo has general git operations but not unified diff parsing. The ff-ffm-static-analyzer repo has the complete implementation we need.
