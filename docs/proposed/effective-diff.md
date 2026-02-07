## Background

When code is moved between files or reordered within a file, `git diff` produces noisy output — entire methods appear as fully deleted and fully re-added, even when only a single character changed. This makes automated analysis waste effort evaluating unchanged logic.

The "effective diff" feature detects moved code blocks and produces a reduced diff containing only the meaningful changes. It will later be integrated into the PRRadar pipeline, but this plan focuses solely on building and testing the standalone capability in the infrastructure layer. The goal is to demonstrate it works soundly across a wide range of move scenarios via comprehensive unit tests. Bill will handle host app integration separately.

### Algorithm Overview

The approach is bottom-up and multi-phase:

1. **Exact-match** removed lines against added lines using dict lookup (fast, handles ~85% of moved lines)
2. **Aggregate** consecutive matched lines into blocks, score them for confidence
3. **Extend** matched blocks by ±N lines using provided source file contents
4. **Re-diff** the extended old/new regions with `git diff --no-index` to find the actual changes (e.g., a renamed method signature)
5. **Trim** unrelated hunks that fall outside the matched block boundary

### Diff Tool Choice: `git diff --no-index`

We use `git diff --no-index` to diff the extracted code regions because:

- Produces standard unified diff output, directly compatible with the existing `GitDiff.from_diff_content()` parser
- Works on arbitrary files outside any git repository
- Battle-tested diff algorithm with good handling of whitespace, comments, and near-identical blocks
- Avoids introducing any new dependencies

**Mechanism**: Write the old-region and new-region to temporary files, then run:
```bash
git diff --no-index /tmp/old_block.txt /tmp/new_block.txt
```

Process substitution (`<(echo ...)`) also works but produces `/dev/fd/` paths in the output headers. Writing temp files with meaningful names (e.g., the original file paths) produces cleaner output that integrates better with downstream tooling. Exit code 1 means differences found (not an error).

### Source File Access

The service accepts full file contents as input (a dict of `{file_path: content}` for old and new versions). This keeps the service decoupled from git/GitHub — callers provide the file contents however they obtain them. In unit tests, these are simply inline strings.

## Phases

## - [x] Phase 1: Line-Level Exact Matching

Build the core matching engine that identifies removed lines appearing as added lines elsewhere in the diff.

**Input**: A `GitDiff` object (parsed from raw diff text)
**Output**: A list of line-level matches: `(removed_line_ref, added_line_ref, similarity)`

### Implementation Notes

- Module: `prradar/infrastructure/effective_diff.py`
- Uses standalone functions (`extract_tagged_lines`, `build_added_index`, `find_exact_matches`) rather than a service class — no state or dependencies needed at this layer
- `TaggedLineType` is a separate enum from `DiffLineType` since tagged lines are always ADDED or REMOVED (never CONTEXT/HEADER)
- Dataclasses use `frozen=True` since tagged lines and matches are immutable value objects
- Blank/whitespace-only lines are excluded from the index to avoid broad false matches
- One-to-one matching: each added line is consumed by the first matching removed line (greedy, ordered)
- 19 unit tests in `tests/infrastructure/effective_diff/test_line_matching.py` covering: cross-file moves, same-hunk edits, whitespace normalization, duplicate lines, blank line exclusion, distance calculation, and content preservation

### Tasks

- Create `prradar/infrastructure/effective_diff.py` with `EffectiveDiffService`
- Extract all removed lines and added lines from the `GitDiff` hunks, each tagged with:
  - File path
  - Line number (old or new)
  - Hunk index (for distance calculation)
  - Normalized content (whitespace-stripped)
- Build a dict index of added lines keyed by normalized content
- For each removed line, look up exact matches in the index
- Store matches with their distance metadata (how far apart in the diff the match is)

### Data structures

```python
@dataclass
class TaggedLine:
    content: str            # original content
    normalized: str         # whitespace-stripped
    file_path: str
    line_number: int
    hunk_index: int         # position in the overall diff
    line_type: DiffLineType # ADDED or REMOVED

@dataclass
class LineMatch:
    removed: TaggedLine
    added: TaggedLine
    distance: int           # hunk_index delta (0 = same hunk)
    similarity: float       # 1.0 for exact match
```

### Distance classification

- Distance 0 (same hunk, adjacent): likely an in-place edit, not a move
- Distance > 0 (different hunk or file): move candidate

## - [ ] Phase 2: Block Aggregation and Scoring

Group matched lines into blocks and score each block for move confidence.

**Input**: List of `LineMatch` from Phase 1
**Output**: List of `MoveCandidate` blocks with confidence scores

### Tasks

- Group matched removed lines into blocks, tolerating small gaps of unmatched lines within a block
- For each block, compute a multi-factor confidence score:

### Gap tolerance within blocks

Exact-match regions are not always contiguous. A moved method may have 1-2 stray changes (a tweaked constant, an added log line) surrounded by exact matches. These gaps should not split the block — they should be absorbed into it.

**Rule**: When grouping consecutive matched lines, allow up to N unmatched lines (start with N=3) between matched lines without splitting the block. The unmatched lines become part of the block — they represent the "real changes" within the moved code.

Example:
```
line 10: exact match     ─┐
line 11: exact match      │
line 12: NO match  ←gap   ├── single block (gap absorbed)
line 13: exact match      │
line 14: exact match     ─┘
```

If the gap exceeds N lines, split into separate blocks. The gap tolerance is a tunable parameter.

```python
@dataclass
class MoveCandidate:
    removed_lines: list[TaggedLine]  # consecutive removed lines forming the block
    added_lines: list[TaggedLine]    # corresponding added lines
    score: float                     # composite confidence score
    source_file: str                 # file the block was removed from
    target_file: str                 # file the block was added to
    source_start_line: int
    target_start_line: int
```

### Scoring factors

| Factor | Description | Effect |
|---|---|---|
| **Block size** | Number of consecutive matched lines. Minimum threshold: 3 lines. Scales as a gradient — 3 is baseline, 10+ adds strong confidence. | Low size → low score |
| **Line uniqueness** | Inverse frequency of each line in the diff. `return None` appears 20 times → low weight. A domain-specific line appears once → high weight. Computed as `1 / count_in_added_pool`. Averaged across block lines. | Generic lines → dampened score |
| **Match consistency** | Do all matched lines in the block point to the same target region? Measured as standard deviation of target line numbers — low stddev = consistent. | Scattered targets → low score |
| **Distance** | How far (in hunks) between source and target. Must be > 0 to qualify as a move (distance 0 = in-place edit, skip). | Distance 0 → disqualified |

```python
score = size_factor * avg_uniqueness * consistency * distance_factor
```

- Filter out blocks below a confidence threshold (tunable, start with empirical testing)
- Filter out blocks with distance 0 (in-place edits)

## - [ ] Phase 3: Block Extension and Re-Diff

For each high-confidence move candidate, fetch surrounding context from the provided source file contents and re-diff to capture boundary changes (e.g., renamed method signatures).

**Input**: List of `MoveCandidate` blocks + old/new file contents (as dicts)
**Output**: Effective diff hunks (git diff format) for each moved block

### Tasks

- For each `MoveCandidate`:
  1. Determine the line range of the matched block in both old and new files
  2. Extend the range by ±20 lines (clamped to file boundaries)
  3. Extract the extended regions from the provided file content dicts:
     - Old region: `old_files[source_file]` → extract lines
     - New region: `new_files[target_file]` → extract lines
  4. Write both regions to temp files (use `tempfile.mkdtemp()`)
  5. Run `git diff --no-index <old_file> <new_file>` via subprocess
  6. Parse the output — this is the effective diff for this moved block

- **Trim unrelated hunks**: The re-diff may include changes from the ±20 line extension that aren't related to the move. Filter: keep only hunks whose line range overlaps with or is adjacent to (within 3 lines of) the original matched block boundaries. Discard the rest.

- Replace the `git diff --no-index` file path headers with the actual source/target file paths so the output is meaningful.

### Subprocess call

```python
import subprocess
import tempfile

def rediff_regions(old_text: str, new_text: str, old_label: str, new_label: str) -> str:
    with tempfile.TemporaryDirectory() as tmpdir:
        old_path = Path(tmpdir) / "old.txt"
        new_path = Path(tmpdir) / "new.txt"
        old_path.write_text(old_text)
        new_path.write_text(new_text)

        result = subprocess.run(
            ["git", "diff", "--no-index", str(old_path), str(new_path)],
            capture_output=True, text=True,
        )
        # exit code 1 = differences found (not an error)
        return result.stdout
```

## - [ ] Phase 4: Diff Reconstruction

Combine the effective diffs for moved blocks with the unchanged portions of the original diff to produce the final effective `GitDiff`.

**Input**: Original `GitDiff` + effective diff hunks from Phase 3
**Output**: New `GitDiff` representing the effective diff + a move report

### Tasks

- For each hunk in the original diff, classify it:
  - **Part of a detected move (removed side)**: Replace with nothing (the move's effective diff captures any real changes)
  - **Part of a detected move (added side)**: Replace with the effective diff hunks from Phase 3
  - **Not part of any move**: Keep as-is
- Reconstruct a new `GitDiff` from the surviving/replacement hunks
- Produce a move report data structure:

### Move report structure

```python
@dataclass
class MoveReport:
    moves_detected: int
    total_lines_moved: int
    total_lines_effectively_changed: int
    moves: list[MoveDetail]

@dataclass
class MoveDetail:
    source_file: str
    target_file: str
    source_lines: tuple[int, int]
    target_lines: tuple[int, int]
    matched_lines: int
    score: float
    effective_diff_lines: int
```

## - [ ] Phase 5: Validation

Tests use diff fixture strings (raw unified diff format) as input and assert on the effective diff output. Each fixture represents a realistic scenario. The expected output for every scenario is a clean effective diff containing only the lines between (and including) the first and last meaningful change — no unrelated context above or below.

### Expected output format

For a detected move where only the signature changed, the effective diff should look like:

```diff
diff --git a/old_module.py b/new_module.py
--- a/old_module.py
+++ b/new_module.py
@@ -1,2 +1,2 @@
-def calculate_total(items):
+def calculate_total(items, tax_rate=0.0):
```

Nothing above the first changed line, nothing below the last. The diff starts at the first real change and ends at the last.

### Test fixtures and scenarios

Each fixture is a raw unified diff string simulating a specific scenario. The test calls `EffectiveDiffService.compute(git_diff, old_files, new_files)` and asserts on the resulting effective `GitDiff`. The `old_files` and `new_files` dicts are inline strings in the test — no git or filesystem access needed.

---

#### Fixture 1: Pure move, no changes

A method is moved from `utils.py` to `helpers.py` with zero modifications.

```
Old (utils.py):                    New (helpers.py):
def calculate_total(items):        def calculate_total(items):
    total = 0                          total = 0
    for item in items:                 for item in items:
        total += item.price                total += item.price
    return total                       return total
```

**Git diff shows**: Entire method deleted from `utils.py`, entire method added to `helpers.py`.
**Expected effective diff**: Empty (no real changes). The move is reported in the `MoveReport` but produces no diff hunks.

---

#### Fixture 2: Move with signature change

Method moved cross-file, signature renamed.

```
Old (utils.py):                    New (helpers.py):
def calc_total(items):             def calculate_total(items, tax=0):
    total = 0                          total = 0
    for item in items:                 for item in items:
        total += item.price                total += item.price
    return total                       return total
```

**Expected effective diff**: Only the signature line:
```diff
-def calc_total(items):
+def calculate_total(items, tax=0):
```

---

#### Fixture 3: Move with interior gap (stray changes within exact matches)

Method moved, body is mostly identical but has 1-2 changed lines in the middle.

```
Old (services.py):                 New (handlers.py):
def process_order(order):          def process_order(order):
    validate(order)                    validate(order)
    total = sum(order.items)           total = sum(order.line_items)    ← changed
    tax = total * 0.08                 tax = total * 0.08
    order.total = total + tax          order.total = total + tax
    order.save()                       order.save()
    return order                       return order
```

**Expected effective diff**: Only the changed line:
```diff
-    total = sum(order.items)
+    total = sum(order.line_items)
```

The surrounding exact-match lines form one block (with the gap absorbed). The re-diff isolates the single change.

---

#### Fixture 4: Move with added comments in new location

Method moved, someone added docstring/comments in the new location.

```
Old (utils.py):                    New (helpers.py):
def validate(order):               def validate(order):
    if not order.items:                """Validate order has items."""   ← added
        raise ValueError()             if not order.items:
    return True                            raise ValueError()
                                       return True
```

**Expected effective diff**: Only the added docstring:
```diff
+    """Validate order has items."""
```

---

#### Fixture 5: Method swap within same file

Two methods swap positions in the same file, neither is modified.

```
Old (services.py):                 New (services.py):
def method_a():                    def method_b():
    return "a"                         return "b"

def method_b():                    def method_a():
    return "b"                         return "a"
```

**Git diff shows**: A garbled interleaving of both methods.
**Expected effective diff**: Empty. The swap is purely positional — no content changed.

---

#### Fixture 6: Method swap with one method modified

Two methods swap positions, and one of them also has a real change.

```
Old (services.py):                 New (services.py):
def method_a():                    def method_b():
    return "a"                         return "b"

def method_b():                    def method_a():
    return "b"                         return "a_modified"    ← changed
```

**Expected effective diff**: Only the change in `method_a`:
```diff
-    return "a"
+    return "a_modified"
```

---

#### Fixture 7: Move with multiple interior gaps

A larger method moved with several scattered changes throughout the body.

```
Old (20 lines, processor.py):     New (20 lines, handler.py):
def process(data):                 def process(data):
    step1(data)                        step1(data)
    x = transform(data)               x = transform_v2(data)    ← changed
    validate(x)                        validate(x)
    y = compute(x)                     y = compute(x)
    log(y)                             log(y)
    z = finalize(y)                    z = finalize(y)
    if z.ready:                        if z.ready:
        emit(z)                            emit_async(z)         ← changed
    cleanup()                          cleanup()
    return z                           return z
```

**Expected effective diff**: Only the two changed lines:
```diff
-    x = transform(data)
+    x = transform_v2(data)
...
-        emit(z)
+            emit_async(z)
```

The exact-match blocks between the gaps are detected as one block (gaps absorbed at N=3 tolerance). The re-diff produces only the changed lines.

---

#### Fixture 8: Partial move (subset of methods from a file)

Three methods exist in `big_module.py`. Two are moved to `small_module.py`, one stays. The staying method also has a change.

**Expected**: The two moved methods produce effective diffs (possibly empty if no changes). The staying method's change appears in the effective diff as-is (not classified as a move).

---

#### Fixture 9: Move with indentation change

Method moves from module level into a class, gaining one level of indentation.

```
Old (utils.py):                    New (models.py):
def save(data):                    class DataManager:
    db.insert(data)                    def save(self, data):
    return True                            db.insert(data)
                                           return True
```

**Expected effective diff**: The signature change (`def save(data)` → `def save(self, data)`) and possibly indentation, but the body logic is recognized as a move. Since normalization strips leading whitespace, the exact-match engine should still find the body lines.

---

#### Fixture 10: Small block that should NOT be detected as a move

A 1-2 line block of generic code appears deleted in one place and added in another — but it's coincidence, not a move.

```
Removed from file_a.py:           Added in file_b.py:
    return None                        return None
```

**Expected**: Not classified as a move (block size < 3 lines, low uniqueness score). The lines remain in the effective diff as normal additions/removals.

---

#### Fixture 11: Moved block adjacent to genuinely new code

A method is moved to a new file, and new code is added directly above/below it in the target file.

```
New file (handlers.py):
def brand_new_function():          ← genuinely new, not a move
    do_new_stuff()

def calculate_total(items):        ← moved from utils.py (unchanged)
    total = 0
    for item in items:
        total += item.price
    return total

def another_new_function():        ← genuinely new, not a move
    do_other_stuff()
```

**Expected**: `calculate_total` is detected as a move (effective diff empty). `brand_new_function` and `another_new_function` remain in the effective diff as genuine additions. The trimming phase ensures the move detection doesn't absorb the adjacent new code.

---

#### Fixture 12: Move with whitespace-only changes

Method moved, and the only difference is trailing whitespace or blank line changes.

**Expected**: After normalization, this is detected as a pure move. Effective diff is empty (or shows only the whitespace diff if we decide whitespace changes are worth preserving — TBD, probably not).

---

#### Fixture 13: Large file reorganization

A file with 5 methods is reorganized — all methods stay in the same file but are reordered. One method has a real change.

**Expected**: The 4 unchanged methods produce no effective diff. The 1 changed method produces an effective diff showing only its change. This is the stress test for same-file move detection at scale.

### Test organization

```
tests/
├── infrastructure/
│   └── effective_diff/
│       ├── fixtures/               # Raw diff strings as .diff files
│       │   ├── pure_move.diff
│       │   ├── move_with_signature_change.diff
│       │   ├── move_with_interior_gap.diff
│       │   ├── move_with_added_comments.diff
│       │   ├── same_file_swap.diff
│       │   ├── same_file_swap_with_change.diff
│       │   ├── move_with_multiple_gaps.diff
│       │   ├── partial_move.diff
│       │   ├── move_with_indentation.diff
│       │   ├── small_block_not_a_move.diff
│       │   ├── move_adjacent_to_new_code.diff
│       │   ├── move_whitespace_only.diff
│       │   └── large_reorg.diff
│       ├── test_line_matching.py    # Phase 1 unit tests
│       ├── test_block_aggregation.py # Phase 2 unit tests (including gap tolerance)
│       ├── test_scoring.py          # Scoring factor tests
│       ├── test_rediff.py           # Phase 3 re-diff + trim tests
│       ├── test_reconstruction.py   # Phase 4 full pipeline tests
│       └── test_end_to_end.py       # Fixture-driven: raw diff in → effective diff out
```

Each fixture `.diff` file is a self-contained raw unified diff. The end-to-end tests load these fixtures, provide mock source file contents as inline dicts (for the ±20 line extension), run the full pipeline, and assert on the effective diff output. No git repository or filesystem access beyond `git diff --no-index` is required.
