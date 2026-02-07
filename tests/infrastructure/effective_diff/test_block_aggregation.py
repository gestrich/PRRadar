"""Tests for Phase 2: Block aggregation.

Tests cover:
- Grouping matched lines into contiguous blocks
- Gap tolerance (absorbing small gaps within blocks)
- Splitting blocks at large gaps
- Distance-0 filtering (in-place edits excluded)
- Multi-file grouping (blocks grouped by source/target file pair)
- Block properties (source/target file, start lines)
"""

from __future__ import annotations

import unittest

from prradar.domain.diff import GitDiff
from prradar.infrastructure.effective_diff import (
    LineMatch,
    MoveCandidate,
    TaggedLine,
    TaggedLineType,
    extract_tagged_lines,
    find_exact_matches,
    find_move_candidates,
    group_matches_into_blocks,
)


def _make_diff(raw: str) -> GitDiff:
    return GitDiff.from_diff_content(raw)


def _make_removed(file_path: str, line_number: int, content: str, hunk_index: int = 0) -> TaggedLine:
    return TaggedLine(
        content=content,
        normalized=content.strip(),
        file_path=file_path,
        line_number=line_number,
        hunk_index=hunk_index,
        line_type=TaggedLineType.REMOVED,
    )


def _make_added(file_path: str, line_number: int, content: str, hunk_index: int = 1) -> TaggedLine:
    return TaggedLine(
        content=content,
        normalized=content.strip(),
        file_path=file_path,
        line_number=line_number,
        hunk_index=hunk_index,
        line_type=TaggedLineType.ADDED,
    )


def _make_match(
    removed: TaggedLine,
    added: TaggedLine,
    distance: int | None = None,
) -> LineMatch:
    if distance is None:
        distance = abs(removed.hunk_index - added.hunk_index)
    return LineMatch(removed=removed, added=added, distance=distance, similarity=1.0)


# ------------------------------------------------------------------
# Diff fixtures
# ------------------------------------------------------------------

CROSS_FILE_MOVE_DIFF = """\
diff --git a/utils.py b/utils.py
index aaa..bbb 100644
--- a/utils.py
+++ b/utils.py
@@ -1,5 +1,0 @@
-def calculate_total(items):
-    total = 0
-    for item in items:
-        total += item.price
-    return total
diff --git a/helpers.py b/helpers.py
index ccc..ddd 100644
--- a/helpers.py
+++ b/helpers.py
@@ -0,0 +1,5 @@
+def calculate_total(items):
+    total = 0
+    for item in items:
+        total += item.price
+    return total
"""

MOVE_WITH_GAP_DIFF = """\
diff --git a/services.py b/services.py
index aaa..bbb 100644
--- a/services.py
+++ b/services.py
@@ -1,7 +1,0 @@
-def process_order(order):
-    validate(order)
-    total = sum(order.items)
-    tax = total * 0.08
-    order.total = total + tax
-    order.save()
-    return order
diff --git a/handlers.py b/handlers.py
index ccc..ddd 100644
--- a/handlers.py
+++ b/handlers.py
@@ -0,0 +1,7 @@
+def process_order(order):
+    validate(order)
+    total = sum(order.line_items)
+    tax = total * 0.08
+    order.total = total + tax
+    order.save()
+    return order
"""

SAME_HUNK_EDIT_DIFF = """\
diff --git a/services.py b/services.py
index aaa..bbb 100644
--- a/services.py
+++ b/services.py
@@ -10,3 +10,3 @@ class Service:
-    x = old_value
+    x = new_value
     shared_line = True
"""


# ------------------------------------------------------------------
# Tests: group_matches_into_blocks
# ------------------------------------------------------------------


class TestGroupMatchesIntoBlocks(unittest.TestCase):

    def test_consecutive_matches_form_single_block(self):
        removed = [_make_removed("a.py", i, f"line {i}") for i in range(1, 6)]
        added = [_make_added("b.py", i, f"line {i}") for i in range(1, 6)]
        matches = [_make_match(r, a) for r, a in zip(removed, added)]

        blocks = group_matches_into_blocks(matches)
        self.assertEqual(len(blocks), 1)
        self.assertEqual(len(blocks[0]), 5)

    def test_small_gap_absorbed(self):
        """A gap of 1 unmatched line should not split the block."""
        removed = [
            _make_removed("a.py", 1, "line 1"),
            _make_removed("a.py", 2, "line 2"),
            # gap at line 3 (no match)
            _make_removed("a.py", 4, "line 4"),
            _make_removed("a.py", 5, "line 5"),
        ]
        added = [
            _make_added("b.py", 1, "line 1"),
            _make_added("b.py", 2, "line 2"),
            _make_added("b.py", 4, "line 4"),
            _make_added("b.py", 5, "line 5"),
        ]
        matches = [_make_match(r, a) for r, a in zip(removed, added)]

        blocks = group_matches_into_blocks(matches)
        self.assertEqual(len(blocks), 1)
        self.assertEqual(len(blocks[0]), 4)

    def test_gap_at_tolerance_limit_absorbed(self):
        """A gap of exactly gap_tolerance lines should be absorbed."""
        removed = [
            _make_removed("a.py", 1, "line 1"),
            # gap at lines 2, 3, 4 (3 lines)
            _make_removed("a.py", 5, "line 5"),
        ]
        added = [
            _make_added("b.py", 1, "line 1"),
            _make_added("b.py", 5, "line 5"),
        ]
        matches = [_make_match(r, a) for r, a in zip(removed, added)]

        blocks = group_matches_into_blocks(matches, gap_tolerance=3)
        self.assertEqual(len(blocks), 1)

    def test_gap_exceeding_tolerance_splits_block(self):
        """A gap larger than gap_tolerance splits into separate blocks."""
        removed = [
            _make_removed("a.py", 1, "line 1"),
            _make_removed("a.py", 2, "line 2"),
            # gap at lines 3, 4, 5, 6 (4 lines — exceeds tolerance of 3)
            _make_removed("a.py", 7, "line 7"),
            _make_removed("a.py", 8, "line 8"),
        ]
        added = [
            _make_added("b.py", 1, "line 1"),
            _make_added("b.py", 2, "line 2"),
            _make_added("b.py", 7, "line 7"),
            _make_added("b.py", 8, "line 8"),
        ]
        matches = [_make_match(r, a) for r, a in zip(removed, added)]

        blocks = group_matches_into_blocks(matches, gap_tolerance=3)
        self.assertEqual(len(blocks), 2)
        self.assertEqual(len(blocks[0]), 2)
        self.assertEqual(len(blocks[1]), 2)

    def test_distance_zero_filtered_out(self):
        """Matches with distance 0 (same hunk) are excluded."""
        removed = [_make_removed("a.py", i, f"line {i}", hunk_index=0) for i in range(1, 6)]
        added = [_make_added("a.py", i, f"line {i}", hunk_index=0) for i in range(1, 6)]
        matches = [_make_match(r, a, distance=0) for r, a in zip(removed, added)]

        blocks = group_matches_into_blocks(matches)
        self.assertEqual(len(blocks), 0)

    def test_different_file_pairs_separate_blocks(self):
        """Matches between different file pairs form separate blocks."""
        r1 = [_make_removed("a.py", i, f"line {i}") for i in range(1, 4)]
        a1 = [_make_added("b.py", i, f"line {i}") for i in range(1, 4)]
        r2 = [_make_removed("c.py", i, f"line {i}") for i in range(1, 4)]
        a2 = [_make_added("d.py", i, f"line {i}") for i in range(1, 4)]

        matches = [_make_match(r, a) for r, a in zip(r1, a1)] + [
            _make_match(r, a) for r, a in zip(r2, a2)
        ]

        blocks = group_matches_into_blocks(matches)
        self.assertEqual(len(blocks), 2)

    def test_empty_matches_returns_empty(self):
        blocks = group_matches_into_blocks([])
        self.assertEqual(len(blocks), 0)

    def test_custom_gap_tolerance(self):
        """gap_tolerance=1 should split on a gap of 2."""
        removed = [
            _make_removed("a.py", 1, "line 1"),
            # gap at line 2, 3
            _make_removed("a.py", 4, "line 4"),
        ]
        added = [
            _make_added("b.py", 1, "line 1"),
            _make_added("b.py", 4, "line 4"),
        ]
        matches = [_make_match(r, a) for r, a in zip(removed, added)]

        blocks = group_matches_into_blocks(matches, gap_tolerance=1)
        self.assertEqual(len(blocks), 2)

    def test_matches_sorted_by_removed_line_number(self):
        """Out-of-order matches should still form correct blocks."""
        removed = [
            _make_removed("a.py", 5, "line 5"),
            _make_removed("a.py", 3, "line 3"),
            _make_removed("a.py", 1, "line 1"),
            _make_removed("a.py", 4, "line 4"),
            _make_removed("a.py", 2, "line 2"),
        ]
        added = [
            _make_added("b.py", 5, "line 5"),
            _make_added("b.py", 3, "line 3"),
            _make_added("b.py", 1, "line 1"),
            _make_added("b.py", 4, "line 4"),
            _make_added("b.py", 2, "line 2"),
        ]
        matches = [_make_match(r, a) for r, a in zip(removed, added)]

        blocks = group_matches_into_blocks(matches)
        self.assertEqual(len(blocks), 1)
        self.assertEqual(len(blocks[0]), 5)
        # Verify sorted order
        line_numbers = [m.removed.line_number for m in blocks[0]]
        self.assertEqual(line_numbers, [1, 2, 3, 4, 5])


# ------------------------------------------------------------------
# Tests: find_move_candidates (integration of grouping + scoring)
# ------------------------------------------------------------------


class TestFindMoveCandidates(unittest.TestCase):

    def test_cross_file_move_detected(self):
        git_diff = _make_diff(CROSS_FILE_MOVE_DIFF)
        removed, added = extract_tagged_lines(git_diff)
        matches = find_exact_matches(removed, added)

        candidates = find_move_candidates(matches, added)
        self.assertEqual(len(candidates), 1)

        c = candidates[0]
        self.assertEqual(c.source_file, "utils.py")
        self.assertEqual(c.target_file, "helpers.py")
        self.assertEqual(c.source_start_line, 1)
        self.assertEqual(c.target_start_line, 1)
        self.assertEqual(len(c.removed_lines), 5)
        self.assertEqual(len(c.added_lines), 5)
        self.assertGreater(c.score, 0)

    def test_move_with_gap_detected_as_single_block(self):
        git_diff = _make_diff(MOVE_WITH_GAP_DIFF)
        removed, added = extract_tagged_lines(git_diff)
        matches = find_exact_matches(removed, added)

        candidates = find_move_candidates(matches, added)
        self.assertEqual(len(candidates), 1)
        self.assertEqual(candidates[0].source_file, "services.py")
        self.assertEqual(candidates[0].target_file, "handlers.py")

    def test_same_hunk_edit_not_detected_as_move(self):
        git_diff = _make_diff(SAME_HUNK_EDIT_DIFF)
        removed, added = extract_tagged_lines(git_diff)
        matches = find_exact_matches(removed, added)

        candidates = find_move_candidates(matches, added)
        self.assertEqual(len(candidates), 0)

    def test_small_block_below_threshold_excluded(self):
        """Blocks with fewer lines than min_block_size are excluded."""
        removed = [
            _make_removed("a.py", 1, "line 1"),
            _make_removed("a.py", 2, "line 2"),
        ]
        added = [
            _make_added("b.py", 1, "line 1"),
            _make_added("b.py", 2, "line 2"),
        ]
        matches = [_make_match(r, a) for r, a in zip(removed, added)]

        candidates = find_move_candidates(matches, added, min_block_size=3)
        self.assertEqual(len(candidates), 0)

    def test_candidates_sorted_by_score_descending(self):
        """Multiple candidates should be sorted by score, highest first."""
        # Create two blocks — one large (10 lines), one small (3 lines)
        r_large = [_make_removed("a.py", i, f"unique_line_{i}") for i in range(1, 11)]
        a_large = [_make_added("b.py", i, f"unique_line_{i}") for i in range(1, 11)]

        r_small = [_make_removed("c.py", i, f"small_line_{i}") for i in range(1, 4)]
        a_small = [_make_added("d.py", i, f"small_line_{i}") for i in range(1, 4)]

        all_added = a_large + a_small
        matches = [_make_match(r, a) for r, a in zip(r_large, a_large)] + [
            _make_match(r, a) for r, a in zip(r_small, a_small)
        ]

        candidates = find_move_candidates(matches, all_added, min_block_size=3)
        self.assertEqual(len(candidates), 2)
        self.assertGreaterEqual(candidates[0].score, candidates[1].score)

    def test_move_candidate_lines_are_tuples(self):
        """MoveCandidate stores lines as tuples (immutable)."""
        git_diff = _make_diff(CROSS_FILE_MOVE_DIFF)
        removed, added = extract_tagged_lines(git_diff)
        matches = find_exact_matches(removed, added)

        candidates = find_move_candidates(matches, added)
        self.assertIsInstance(candidates[0].removed_lines, tuple)
        self.assertIsInstance(candidates[0].added_lines, tuple)


if __name__ == "__main__":
    unittest.main()
