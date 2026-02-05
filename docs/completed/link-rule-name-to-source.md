## Background

When posting GitHub comments for violations, the rule name appears at the top of the comment (e.g., `**nullability-m-objc**`). This should be a clickable link to the rule's source file in its GitHub repository.

The challenge is that rules can live in any git repository, and we need to:
1. Determine which repository the rule file belongs to
2. Find the relative path within that repository
3. Construct the GitHub URL to link to the file

Current state:
- Rules have `file_path` (absolute path, e.g., `/Users/bill/Developer/work/ios/code-review-rules/nullability-m-objc.md`)
- We already auto-detect the PR's repo via `gh.get_repository()`
- The `--rules-dir` argument specifies where to load rules from

## Phases

## - [x] Phase 1: Add git helper to detect repo URL from file path

Add a utility function that, given an absolute file path:
1. Runs `git -C <dir> remote get-url origin` to get the remote URL
2. Runs `git -C <dir> rev-parse --show-toplevel` to get repo root
3. Computes the relative path from repo root
4. Runs `git -C <dir> rev-parse --abbrev-ref HEAD` to get current branch
5. Converts SSH URLs to HTTPS format if needed

Location: `scripts/infrastructure/git_utils.py` (new file)

Returns a dataclass:
```python
@dataclass
class GitFileInfo:
    repo_url: str           # https://github.com/owner/repo
    relative_path: str      # code-review-rules/nullability-m-objc.md
    branch: str             # main, develop, etc.

    def to_github_url(self) -> str:
        return f"{self.repo_url}/blob/{self.branch}/{self.relative_path}"
```

**Implementation Notes:**
- Created `plugin/skills/pr-review/scripts/infrastructure/git_utils.py`
- Exports: `get_git_file_info()`, `GitFileInfo`, `GitError`
- Handles both SSH (`git@github.com:owner/repo.git`) and HTTPS URL formats
- `GitError` exception raised when file is not in a git repo or commands fail

## - [x] Phase 2: Add rule_url to Rule model

Extend the `Rule` model to include an optional `rule_url` field that gets populated during rule loading. This keeps URL generation close to where the file path is known.

Files to modify:
- `scripts/domain/rule.py` - Add `rule_url: str | None` field
- `scripts/services/rule_loader.py` - Populate `rule_url` when loading rules using the git helper

**Fail-fast behavior**: The rules directory MUST be in a git repository with a valid GitHub remote. On startup, the app should:
1. Derive the repo URL from `--rules-dir` using the git helper
2. Exit immediately with a clear error if:
   - The directory isn't in a git repo
   - The git commands fail
   - The remote URL isn't a GitHub URL

This ensures misconfiguration is caught early rather than silently producing comments without links.

**Implementation Notes:**
- Added `rule_url: str | None = None` field to `Rule` dataclass
- Updated `Rule.from_dict()` to deserialize `rule_url`
- Modified `RuleLoaderService` to require `GitFileInfo` - now stores git info at construction time
- `RuleLoaderService.create()` now validates:
  - Directory is in a git repository (raises `ValueError` with clear message if not)
  - Remote URL contains `github.com` (validates it's a GitHub repo)
- `load_all_rules()` calls `_build_rule_url()` to populate `rule_url` for each loaded rule
- Note: `to_dict()` serialization will be added in Phase 3 when threading through to violations

## - [x] Phase 3: Thread rule_url through to CommentableViolation

Add `rule_url` to the violation so it's available when composing comments.

Files to modify:
- `scripts/commands/agent/comment.py` - Add `rule_url: str | None` to `CommentableViolation`
- `scripts/services/violation_service.py` - Pass `rule.rule_url` when creating violations
- `scripts/domain/rule.py` - Include `rule_url` in `to_dict()` serialization

**Implementation Notes:**
- Added `rule_url: str | None = None` field to `CommentableViolation` dataclass
- Updated `ViolationService.create_violation()` to pass `task.rule.rule_url`
- Added `rule_url` to `Rule.to_dict()` (only included when not None)
- Updated `load_violations()` to extract `rule_url` from task metadata for JSON-based loading

## - [x] Phase 4: Update compose_comment to link rule name

Modify `CommentableViolation.compose_comment()` to make the rule name a link when `rule_url` is available.

Change from:
```python
f"**{self.rule_name}**"
```

To:
```python
f"**[{self.rule_name}]({self.rule_url})**" if self.rule_url else f"**{self.rule_name}**"
```

**Implementation Notes:**
- Modified `compose_comment()` in `scripts/commands/agent/comment.py`
- Creates `rule_header` variable with conditional link formatting
- Falls back to plain bold text when `rule_url` is None

## - [x] Phase 5: Validation

- Run existing unit tests to ensure no regressions
- Manual test with a real rule directory to verify:
  - URL is correctly generated for rules in a git repo
  - Graceful fallback when rules aren't in a git repo
  - Link renders correctly in GitHub comment preview

**Validation Results:**
- All 74 unit tests pass (`test_diff_parser.py` and `test_services.py`)
- `git_utils.get_git_file_info()` correctly generates GitHub URLs for files in a git repo
  - Example: `https://github.com/gestrich/PRRadar/blob/main/plugin/skills/pr-review/scripts/domain/rule.py`
- `RuleLoaderService.create()` correctly fails fast with clear error messages:
  - Non-git directory: "Rules directory must be in a git repository with a valid remote"
  - Non-GitHub remote: "Rules directory must be in a GitHub repository"
- `compose_comment()` produces correctly formatted markdown:
  - With `rule_url`: `**[rule-name](https://github.com/...)**` (clickable link)
  - Without `rule_url`: `**rule-name**` (plain bold text)
- All modules import successfully - no syntax or import errors
