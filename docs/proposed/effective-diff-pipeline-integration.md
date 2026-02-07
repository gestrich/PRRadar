## Background

The effective diff module (`prradar/infrastructure/effective_diff.py`) detects moved code blocks and produces reduced diffs containing only meaningful changes. It is fully implemented and tested (144+ unit tests, 13 fixture scenarios), but not yet wired into the pipeline. This plan integrates it into Phase 1 (`agent diff`) so it runs automatically alongside existing diff acquisition and outputs its results using the same file naming conventions.

The effective diff pipeline chains four internal stages: line-level exact matching, block aggregation/scoring, block extension + re-diff via `git diff --no-index`, and diff reconstruction. It requires old/new file contents to extend matched blocks with surrounding context. The `DiffProvider` interface already has `get_file_content(file_path, commit_hash)` on both local and GitHub providers, so file content fetching is straightforward.

Output files are **required** for Phase 1 completion. Even when zero moves are detected, the effective diff equals the original diff and the move report shows `moves_detected: 0` — files are always written.

### Key files

- `prradar/infrastructure/effective_diff.py` — standalone functions for the 4-stage pipeline
- `prradar/commands/agent/diff.py` — Phase 1 command that fetches/stores diff artifacts
- `prradar/services/phase_sequencer.py` — phase constants, `DiffPhaseChecker`
- `prradar/domain/diff.py` — `GitDiff` model with `to_dict()`, `to_markdown()`, `get_unique_files()`
- `prradar/infrastructure/diff_provider/base.py` — `DiffProvider.get_file_content()`

### Existing patterns to follow

- Python code style from `gestrich/python-architecture`: public functions before private, section headers for grouping, `to_dict()` for serialization (matching `Hunk.to_dict()`, `GitDiff.to_dict()`)
- Module-level function organization: dataclasses first, public API functions, then private helpers
- Frozen dataclasses for immutable value objects

## Phases

## - [x] Phase 1: Add serialization and pipeline function to effective_diff.py

Add `to_dict()` methods on `MoveDetail` and `MoveReport` for JSON serialization, following the `Hunk.to_dict()` pattern already used in the codebase.

Add `run_effective_diff_pipeline()` as the public entry point that chains the four internal stages:

```python
def run_effective_diff_pipeline(
    git_diff: GitDiff,
    old_files: dict[str, str],
    new_files: dict[str, str],
) -> tuple[GitDiff, MoveReport]:
```

This mirrors the `_run_pipeline()` helper in `tests/infrastructure/effective_diff/test_end_to_end.py`: `extract_tagged_lines` → `find_exact_matches` → `find_move_candidates` → `compute_effective_diff_for_candidate` (per candidate) → `reconstruct_effective_diff` + `build_move_report`.

**Files**: `prradar/infrastructure/effective_diff.py`

**Completed**: `MoveDetail.to_dict()` serializes tuples as lists for JSON compatibility. `MoveReport.to_dict()` delegates to `MoveDetail.to_dict()` for each move. `run_effective_diff_pipeline()` added as a "Pipeline Entry Point" section at the end of the module. All 485 tests pass.

## - [ ] Phase 2: Add filename constants and update DiffPhaseChecker

Add three filename constants to `phase_sequencer.py` after the existing Phase 1 constants:

- `EFFECTIVE_DIFF_PARSED_JSON_FILENAME = "effective-diff-parsed.json"`
- `EFFECTIVE_DIFF_PARSED_MD_FILENAME = "effective-diff-parsed.md"`
- `EFFECTIVE_DIFF_MOVES_FILENAME = "effective-diff-moves.json"`

Add all three to `DiffPhaseChecker.REQUIRED_FILES`.

**Files**: `prradar/services/phase_sequencer.py`

## - [ ] Phase 3: Integrate effective diff into cmd_diff()

After PR metadata is fetched and stored in `cmd_diff()`, add:

1. **Collect file contents** — For each file in `git_diff.get_unique_files()`, fetch old and new versions via `provider.get_file_content()`. Base ref is `origin/{pr.base_ref_name}` for LOCAL source, `{pr.base_ref_name}` for GITHUB source. Head ref is `pr.head_ref_oid`. Catch `GitFileNotFoundError` for new/deleted files (skip gracefully — file simply not included in the dict).

2. **Run pipeline** — Call `run_effective_diff_pipeline(git_diff, old_files, new_files)`.

3. **Write output files**:
   - `effective-diff-parsed.json` via `effective_diff.to_dict(annotate_lines=True)`
   - `effective-diff-parsed.md` via `effective_diff.to_markdown()`
   - `effective-diff-moves.json` via `move_report.to_dict()`

4. **Print summary** — Log moves detected, lines moved, lines effectively changed.

Errors propagate normally (no try/except wrapper) since these files are required for phase completion.

**Files**: `prradar/commands/agent/diff.py`

## - [ ] Phase 4: Validation

Run existing tests to ensure nothing is broken:

```bash
source .venv/bin/activate && python -m pytest tests/ -v
```

Update any phase sequencer tests that assert on `DiffPhaseChecker.REQUIRED_FILES` to include the three new filenames.

Verify the `run_effective_diff_pipeline()` function works end-to-end by confirming the existing `test_end_to_end.py` tests still pass (they exercise the same pipeline stages internally).
