## Background

The code-review skill currently has Claude parse raw `gh pr diff` output manually to extract line numbers for violations. This led to a bug where Claude counted cumulative lines through the entire diff (2416 lines) instead of reading hunk headers to get actual target file line numbers (e.g., reporting line 2411 instead of line 5).

The `ffm-static-analyzer` repo at `/Users/bill/Developer/work/ffm-static-analyzer/repo_tools/` has proven Python tools (`Hunk`, `GitDiff`) that deterministically parse diff hunk headers using regex. Integrating these tools will:

1. Provide Claude with structured JSON containing correct `new_start` line numbers
2. Eliminate manual hunk header parsing errors
3. Give each file segment an anchor point for line number calculations

The code will be added to `.claude/skills/code-review/scripts/` following the existing architecture:
- `domain/` - Type-safe models with `from_dict()` factory methods
- `infrastructure/` - External system interactions (diff parsing)
- `commands/` - Thin CLI command orchestrators
- `__main__.py` - Command dispatcher

## Phases

- [x] Phase 1: Add domain models for diff parsing

Create domain models in `scripts/domain/diff.py`:
- `Hunk` dataclass with `file_path`, `new_start`, `new_length`, `old_start`, `old_length`, `content`
- `GitDiff` dataclass with `hunks: list[Hunk]`, `raw_content`, `commit_hash`
- Factory method `Hunk.from_hunk_lines()` to parse hunk header regex
- Factory method `GitDiff.from_diff_content()` to split raw diff into hunks

Adapt from `/Users/bill/Developer/work/ffm-static-analyzer/repo_tools/hunk.py` and `git_diff.py`, following PRRadar's code style (type hints, section headers, `from __future__ import annotations`).

**Completed:** Added `scripts/domain/diff.py` with `Hunk` and `GitDiff` dataclasses. Key enhancements over the reference implementation:
- Added `to_dict()` methods for JSON serialization
- Improved regex to handle single-line hunks (e.g., `@@ -0,0 +1 @@` without the optional length)
- Added `get_unique_files()` helper method
- Exported from `scripts/domain/__init__.py`

- [x] Phase 2: Add infrastructure for diff input

Create `scripts/infrastructure/diff_parser.py`:
- Function to read diff from stdin or file
- Function to output parsed hunks as JSON
- Handle edge cases (empty diff, binary files, rename operations)

Update `scripts/infrastructure/__init__.py` to export new functions.

**Completed:** Added `scripts/infrastructure/diff_parser.py` with:
- `read_diff()`, `read_diff_from_stdin()`, `read_diff_from_file()` for input handling
- `format_diff_as_json()` and `format_diff_as_text()` for output formatting
- Edge case helpers: `has_content()`, `is_binary_file_marker()`, `is_rename_operation()`
- All functions exported from `scripts/infrastructure/__init__.py`

- [x] Phase 3: Add parse-diff command

Create `scripts/commands/parse_diff.py`:
- `cmd_parse_diff(input_file: str | None, output_format: str)` function
- Read diff from stdin (default) or file
- Output JSON with hunks including `new_start` for each file section
- Support `--format json` (default) and `--format text` for debugging

Output format:
```json
{
  "hunks": [
    {
      "file_path": "test-files/FFLogger.h",
      "new_start": 1,
      "new_length": 10,
      "old_start": 0,
      "old_length": 0,
      "content": "+#import <Foundation/Foundation.h>\n..."
    }
  ]
}
```

**Completed:** Added `scripts/commands/parse_diff.py` with:
- `cmd_parse_diff(input_file, output_format)` orchestrator function
- Follows thin command pattern - delegates to infrastructure for I/O and domain for parsing
- Returns exit code 0 on success, 1 on failure
- Exported from `scripts/commands/__init__.py`
- Note: CLI dispatcher wiring is Phase 4

- [x] Phase 4: Register command in CLI dispatcher

Update `scripts/__main__.py`:
- Import `cmd_parse_diff` from commands
- Add `parse-diff` subparser with arguments:
  - `--input-file` (optional, default stdin)
  - `--format` (json/text, default json)
- Wire up to command function

**Completed:** Updated `scripts/__main__.py` to register the `parse-diff` command:
- Added import for `cmd_parse_diff` from commands
- Added subparser with `--input-file` and `--format` arguments
- Wired routing to call `cmd_parse_diff(input_file, output_format)`
- Fixed Python 3.9 compatibility: replaced `Self` type annotations with class names in `diff.py`, `mention.py`, and `review.py` (since `Self` requires Python 3.11+)

- [x] Phase 5: Update SKILL.md with usage instructions

Update `.claude/skills/code-review/SKILL.md`:
- Add section on using `parse-diff` command before review
- Show example workflow: `gh pr diff 7 | python -m scripts parse-diff`
- Update "Calculating Line Numbers" section to reference the tool
- Add note that `new_start` from JSON output is the anchor for line calculations

**Completed:** Updated `SKILL.md` with new "Using the parse-diff Tool" subsection under "Calculating Line Numbers from Diffs":
- Added command examples for stdin, file input, and text debugging output
- Documented JSON output format showing `new_start`, `new_length`, etc.
- Explained that `new_start` is the anchor point for line number calculations
- Build verified: `python3 -m scripts --help` and `python3 -m scripts parse-diff --help` succeed

- [x] Phase 6: Validation

**Automated testing:**
- Create `scripts/tests/test_diff_parser.py` with:
  - Test parsing new file hunk (`@@ -0,0 +1,10 @@`)
  - Test parsing modified file hunk (`@@ -118,98 +118,36 @@`)
  - Test multi-file diff parsing
  - Test edge cases (empty diff, binary file markers)

**Manual validation:**
- Run `gh pr diff 7 --repo gestrich/PRRadar | python -m scripts parse-diff`
- Verify FFLogger.h shows `new_start: 1` (not 2407)
- Verify output JSON is valid and contains all files from diff

**Completed:** Created comprehensive test suite in `scripts/tests/test_diff_parser.py` with 23 tests:
- `TestHunkParsing`: 7 tests covering new file hunks, modified file hunks, single-line hunks, empty paths, to_dict serialization, and property accessors
- `TestGitDiffParsing`: 10 tests covering multi-file diffs, multiple hunks per file, empty diffs, commit hash preservation, to_dict serialization, get_unique_files, get_hunks_by_extension, and get_hunks_by_file
- `TestInfrastructureFunctions`: 3 tests for binary file detection, rename operations, and content validation
- `TestOutputFormatting`: 3 tests for JSON and text output formats
- `TestQuotedFilePaths`: 1 test for file paths with spaces

Manual validation confirmed:
- FFLogger.h correctly shows `new_start: 1` (not 2407)
- JSON output is valid with all 20 files from PR #7 diff
- Build verified with `python3 -m scripts --help` and `python3 -m scripts parse-diff --help`
