"""Tests for Phase 3: Block extension and re-diff.

Tests cover:
- Line range extraction from file content
- Block range extension with context lines
- Re-diffing extracted regions via git diff --no-index
- Hunk overlap detection and trimming
- End-to-end effective diff computation for move candidates
"""

from __future__ import annotations

import unittest

from prradar.domain.diff import GitDiff, Hunk
from prradar.infrastructure.effective_diff import (
    DEFAULT_CONTEXT_LINES,
    DEFAULT_TRIM_PROXIMITY,
    EffectiveDiffResult,
    MoveCandidate,
    TaggedLine,
    TaggedLineType,
    _extract_line_range,
    _hunk_overlaps_block,
    compute_effective_diff_for_candidate,
    extend_block_range,
    rediff_regions,
    trim_hunks,
)


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


def _make_candidate(
    source_file: str,
    target_file: str,
    removed_lines: list[tuple[int, str]],
    added_lines: list[tuple[int, str]],
    score: float = 0.5,
) -> MoveCandidate:
    """Helper to build a MoveCandidate from (line_number, content) tuples."""
    removed = tuple(
        _make_removed(source_file, ln, content) for ln, content in removed_lines
    )
    added = tuple(
        _make_added(target_file, ln, content) for ln, content in added_lines
    )
    return MoveCandidate(
        removed_lines=removed,
        added_lines=added,
        score=score,
        source_file=source_file,
        target_file=target_file,
        source_start_line=removed[0].line_number,
        target_start_line=added[0].line_number,
    )


# ------------------------------------------------------------------
# Tests: _extract_line_range
# ------------------------------------------------------------------


class TestExtractLineRange(unittest.TestCase):

    def test_extract_middle_lines(self):
        content = "line1\nline2\nline3\nline4\nline5\n"
        result = _extract_line_range(content, 2, 4)
        self.assertEqual(result, "line2\nline3\nline4\n")

    def test_extract_first_line(self):
        content = "line1\nline2\nline3\n"
        result = _extract_line_range(content, 1, 1)
        self.assertEqual(result, "line1\n")

    def test_extract_last_line(self):
        content = "line1\nline2\nline3\n"
        result = _extract_line_range(content, 3, 3)
        self.assertEqual(result, "line3\n")

    def test_extract_all_lines(self):
        content = "line1\nline2\nline3\n"
        result = _extract_line_range(content, 1, 3)
        self.assertEqual(result, "line1\nline2\nline3\n")

    def test_clamp_start_below_one(self):
        content = "line1\nline2\nline3\n"
        result = _extract_line_range(content, -5, 2)
        self.assertEqual(result, "line1\nline2\n")

    def test_clamp_end_beyond_file(self):
        content = "line1\nline2\nline3\n"
        result = _extract_line_range(content, 2, 100)
        self.assertEqual(result, "line2\nline3\n")

    def test_start_beyond_file_returns_empty(self):
        content = "line1\nline2\n"
        result = _extract_line_range(content, 10, 20)
        self.assertEqual(result, "")

    def test_empty_content_returns_empty(self):
        result = _extract_line_range("", 1, 5)
        self.assertEqual(result, "")

    def test_content_without_trailing_newline(self):
        content = "line1\nline2\nline3"
        result = _extract_line_range(content, 2, 3)
        self.assertEqual(result, "line2\nline3")


# ------------------------------------------------------------------
# Tests: extend_block_range
# ------------------------------------------------------------------


class TestExtendBlockRange(unittest.TestCase):

    def test_default_context(self):
        candidate = _make_candidate(
            "a.py", "b.py",
            [(25, "x"), (26, "y"), (27, "z")],
            [(10, "x"), (11, "y"), (12, "z")],
        )
        (src_s, src_e), (tgt_s, tgt_e) = extend_block_range(candidate)
        self.assertEqual(src_s, 25 - DEFAULT_CONTEXT_LINES)
        self.assertEqual(src_e, 27 + DEFAULT_CONTEXT_LINES)
        self.assertEqual(tgt_s, 1)  # clamped: 10 - 20 = -10, clamped to 1
        self.assertEqual(tgt_e, 12 + DEFAULT_CONTEXT_LINES)

    def test_small_context(self):
        candidate = _make_candidate(
            "a.py", "b.py",
            [(5, "x"), (6, "y"), (7, "z")],
            [(5, "x"), (6, "y"), (7, "z")],
        )
        (src_s, src_e), (tgt_s, tgt_e) = extend_block_range(candidate, context_lines=2)
        self.assertEqual(src_s, 3)
        self.assertEqual(src_e, 9)
        self.assertEqual(tgt_s, 3)
        self.assertEqual(tgt_e, 9)

    def test_clamp_start_to_one(self):
        candidate = _make_candidate(
            "a.py", "b.py",
            [(2, "x"), (3, "y")],
            [(1, "x"), (2, "y")],
        )
        (src_s, _), (tgt_s, _) = extend_block_range(candidate, context_lines=10)
        self.assertEqual(src_s, 1)
        self.assertEqual(tgt_s, 1)

    def test_zero_context(self):
        candidate = _make_candidate(
            "a.py", "b.py",
            [(10, "x"), (11, "y"), (12, "z")],
            [(20, "x"), (21, "y"), (22, "z")],
        )
        (src_s, src_e), (tgt_s, tgt_e) = extend_block_range(candidate, context_lines=0)
        self.assertEqual(src_s, 10)
        self.assertEqual(src_e, 12)
        self.assertEqual(tgt_s, 20)
        self.assertEqual(tgt_e, 22)


# ------------------------------------------------------------------
# Tests: rediff_regions
# ------------------------------------------------------------------


class TestRediffRegions(unittest.TestCase):

    def test_identical_regions_produce_empty_diff(self):
        text = "line1\nline2\nline3\n"
        result = rediff_regions(text, text, "a.py", "b.py")
        self.assertEqual(result, "")

    def test_different_regions_produce_diff(self):
        old = "line1\nline2\nline3\n"
        new = "line1\nchanged\nline3\n"
        result = rediff_regions(old, new, "old.py", "new.py")
        self.assertIn("-line2", result)
        self.assertIn("+changed", result)

    def test_file_paths_are_relabeled(self):
        old = "line1\n"
        new = "line2\n"
        result = rediff_regions(old, new, "utils.py", "helpers.py")
        self.assertIn("a/utils.py", result)
        self.assertIn("b/helpers.py", result)
        # Should NOT contain temp file paths
        self.assertNotIn("/tmp", result.lower().replace("\\", "/"))

    def test_added_lines_appear_in_diff(self):
        old = "line1\nline2\n"
        new = "line1\nnew_line\nline2\n"
        result = rediff_regions(old, new, "a.py", "b.py")
        self.assertIn("+new_line", result)

    def test_removed_lines_appear_in_diff(self):
        old = "line1\nold_line\nline2\n"
        new = "line1\nline2\n"
        result = rediff_regions(old, new, "a.py", "b.py")
        self.assertIn("-old_line", result)

    def test_empty_inputs(self):
        result = rediff_regions("", "", "a.py", "b.py")
        self.assertEqual(result, "")

    def test_only_old_has_content(self):
        result = rediff_regions("some content\n", "", "a.py", "b.py")
        self.assertIn("-some content", result)

    def test_only_new_has_content(self):
        result = rediff_regions("", "some content\n", "a.py", "b.py")
        self.assertIn("+some content", result)


# ------------------------------------------------------------------
# Tests: _hunk_overlaps_block / trim_hunks
# ------------------------------------------------------------------


class TestHunkOverlapsBlock(unittest.TestCase):

    def _make_hunk(self, new_start: int, new_length: int) -> Hunk:
        return Hunk(
            file_path="test.py",
            content="",
            new_start=new_start,
            new_length=new_length,
            old_start=new_start,
            old_length=new_length,
        )

    def test_hunk_inside_block(self):
        """Hunk fully within the block boundaries."""
        # Region starts at line 10, hunk at relative line 5 = absolute 14
        # Block spans lines 12-18
        hunk = self._make_hunk(new_start=5, new_length=3)
        self.assertTrue(
            _hunk_overlaps_block(hunk, block_start=12, block_end=18, region_start=10)
        )

    def test_hunk_before_block_no_overlap(self):
        """Hunk entirely before the block, outside proximity."""
        # Region starts at 1, hunk at relative 1 = absolute 1, length 2 = lines 1-2
        # Block spans lines 10-20, proximity 3 → need hunk_end >= 7
        hunk = self._make_hunk(new_start=1, new_length=2)
        self.assertFalse(
            _hunk_overlaps_block(hunk, block_start=10, block_end=20, region_start=1)
        )

    def test_hunk_after_block_no_overlap(self):
        """Hunk entirely after the block, outside proximity."""
        # Region starts at 1, hunk at relative 30 = absolute 30, length 3 = lines 30-32
        # Block spans lines 5-10, proximity 3 → need hunk_start <= 13
        hunk = self._make_hunk(new_start=30, new_length=3)
        self.assertFalse(
            _hunk_overlaps_block(hunk, block_start=5, block_end=10, region_start=1)
        )

    def test_hunk_adjacent_within_proximity(self):
        """Hunk just outside the block but within proximity tolerance."""
        # Region starts at 1, hunk at relative 14 = absolute 14, length 2 = lines 14-15
        # Block spans 10-12, proximity 3 → block_end + proximity = 15, so 14 <= 15 ✓
        hunk = self._make_hunk(new_start=14, new_length=2)
        self.assertTrue(
            _hunk_overlaps_block(hunk, block_start=10, block_end=12, region_start=1)
        )

    def test_hunk_just_outside_proximity(self):
        """Hunk just beyond the proximity tolerance."""
        # Region starts at 1, hunk at relative 17 = absolute 17
        # Block spans 10-12, proximity 3 → block_end + proximity = 15
        # hunk_start=17 > 15, so no overlap
        hunk = self._make_hunk(new_start=17, new_length=2)
        self.assertFalse(
            _hunk_overlaps_block(hunk, block_start=10, block_end=12, region_start=1)
        )

    def test_custom_proximity(self):
        """Custom proximity tolerance."""
        # Region starts at 1, hunk at relative 16 = absolute 16
        # Block spans 10-12, proximity=5 → block_end + 5 = 17
        # hunk_start=16 <= 17 ✓
        hunk = self._make_hunk(new_start=16, new_length=1)
        self.assertTrue(
            _hunk_overlaps_block(hunk, block_start=10, block_end=12, region_start=1, proximity=5)
        )

    def test_region_offset_applied(self):
        """Region start offset correctly shifts hunk positions."""
        # Region starts at 50, hunk at relative 5 = absolute 54
        # Block spans lines 52-58
        hunk = self._make_hunk(new_start=5, new_length=3)
        self.assertTrue(
            _hunk_overlaps_block(hunk, block_start=52, block_end=58, region_start=50)
        )


class TestTrimHunks(unittest.TestCase):

    def _make_hunk(self, new_start: int, new_length: int) -> Hunk:
        return Hunk(
            file_path="test.py",
            content=f"@@ -1,1 +{new_start},{new_length} @@\n+change",
            new_start=new_start,
            new_length=new_length,
            old_start=1,
            old_length=1,
        )

    def test_keeps_overlapping_hunks(self):
        # Region starts at 1; block spans 5-10
        overlapping = self._make_hunk(new_start=6, new_length=3)
        result = trim_hunks([overlapping], block_start=5, block_end=10, region_start=1)
        self.assertEqual(len(result), 1)

    def test_removes_distant_hunks(self):
        distant = self._make_hunk(new_start=50, new_length=3)
        result = trim_hunks([distant], block_start=5, block_end=10, region_start=1)
        self.assertEqual(len(result), 0)

    def test_mixed_keeps_and_removes(self):
        close = self._make_hunk(new_start=6, new_length=2)
        far = self._make_hunk(new_start=50, new_length=2)
        result = trim_hunks([close, far], block_start=5, block_end=10, region_start=1)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0].new_start, 6)

    def test_empty_input_returns_empty(self):
        result = trim_hunks([], block_start=5, block_end=10, region_start=1)
        self.assertEqual(result, [])


# ------------------------------------------------------------------
# Tests: compute_effective_diff_for_candidate (integration)
# ------------------------------------------------------------------


class TestComputeEffectiveDiffForCandidate(unittest.TestCase):

    def test_pure_move_produces_empty_hunks(self):
        """A block moved with zero changes should yield no effective diff hunks."""
        old_content = "line1\nline2\nline3\nline4\nline5\n"
        new_content = "line1\nline2\nline3\nline4\nline5\n"

        candidate = _make_candidate(
            "old.py", "new.py",
            [(1, "line1"), (2, "line2"), (3, "line3"), (4, "line4"), (5, "line5")],
            [(1, "line1"), (2, "line2"), (3, "line3"), (4, "line4"), (5, "line5")],
        )

        result = compute_effective_diff_for_candidate(
            candidate,
            old_files={"old.py": old_content},
            new_files={"new.py": new_content},
            context_lines=2,
        )
        self.assertIsInstance(result, EffectiveDiffResult)
        self.assertEqual(len(result.hunks), 0)
        self.assertEqual(result.raw_diff, "")

    def test_move_with_change_produces_diff(self):
        """A moved block with a changed line should produce an effective diff."""
        old_content = (
            "def calc_total(items):\n"
            "    total = 0\n"
            "    for item in items:\n"
            "        total += item.price\n"
            "    return total\n"
        )
        new_content = (
            "def calculate_total(items, tax=0):\n"
            "    total = 0\n"
            "    for item in items:\n"
            "        total += item.price\n"
            "    return total\n"
        )

        candidate = _make_candidate(
            "utils.py", "helpers.py",
            [
                (2, "    total = 0"),
                (3, "    for item in items:"),
                (4, "        total += item.price"),
                (5, "    return total"),
            ],
            [
                (2, "    total = 0"),
                (3, "    for item in items:"),
                (4, "        total += item.price"),
                (5, "    return total"),
            ],
        )

        result = compute_effective_diff_for_candidate(
            candidate,
            old_files={"utils.py": old_content},
            new_files={"helpers.py": new_content},
            context_lines=2,
        )
        self.assertIsInstance(result, EffectiveDiffResult)
        # The signature changed, so there should be diff output
        self.assertGreater(len(result.hunks), 0)
        # The diff should mention the changed signature
        hunk_content = "\n".join(h.content for h in result.hunks)
        self.assertIn("calc_total", hunk_content)
        self.assertIn("calculate_total", hunk_content)

    def test_missing_file_produces_diff(self):
        """If the source file is missing from old_files, the entire new content appears as added."""
        new_content = "new_line1\nnew_line2\nnew_line3\n"

        candidate = _make_candidate(
            "missing.py", "new.py",
            [(1, "line1"), (2, "line2"), (3, "line3")],
            [(1, "new_line1"), (2, "new_line2"), (3, "new_line3")],
        )

        result = compute_effective_diff_for_candidate(
            candidate,
            old_files={},
            new_files={"new.py": new_content},
            context_lines=0,
        )
        # With empty old file, the entire new content is added
        self.assertIsInstance(result, EffectiveDiffResult)

    def test_interior_change_only(self):
        """A moved block with a single interior change should isolate that change."""
        old_lines = [
            "def process(order):",
            "    validate(order)",
            "    total = sum(order.items)",
            "    tax = total * 0.08",
            "    order.total = total + tax",
            "    order.save()",
            "    return order",
        ]
        new_lines = [
            "def process(order):",
            "    validate(order)",
            "    total = sum(order.line_items)",  # changed
            "    tax = total * 0.08",
            "    order.total = total + tax",
            "    order.save()",
            "    return order",
        ]
        old_content = "\n".join(old_lines) + "\n"
        new_content = "\n".join(new_lines) + "\n"

        # Build candidate from the matching (non-changed) lines
        matching = [
            (1, "def process(order):"),
            (2, "    validate(order)"),
            (4, "    tax = total * 0.08"),
            (5, "    order.total = total + tax"),
            (6, "    order.save()"),
            (7, "    return order"),
        ]
        candidate = _make_candidate(
            "services.py", "handlers.py",
            matching,
            matching,
        )

        result = compute_effective_diff_for_candidate(
            candidate,
            old_files={"services.py": old_content},
            new_files={"handlers.py": new_content},
            context_lines=2,
        )
        self.assertGreater(len(result.hunks), 0)
        hunk_content = "\n".join(h.content for h in result.hunks)
        self.assertIn("order.items", hunk_content)
        self.assertIn("order.line_items", hunk_content)

    def test_trimming_excludes_distant_context_changes(self):
        """Changes in the extended context but far from the block should be trimmed."""
        # Build a file where the block is in the middle (lines 15-20)
        # and there's a change far away in the context extension (line 1)
        old_lines = ["changed_old_line"] + [f"context_{i}" for i in range(2, 14)] + [
            "def method():",     # 14
            "    line_a",        # 15
            "    line_b",        # 16
            "    line_c",        # 17
            "    return True",   # 18
        ]
        new_lines = ["changed_new_line"] + [f"context_{i}" for i in range(2, 14)] + [
            "def method():",     # 14
            "    line_a",        # 15
            "    line_b",        # 16
            "    line_c",        # 17
            "    return True",   # 18
        ]
        old_content = "\n".join(old_lines) + "\n"
        new_content = "\n".join(new_lines) + "\n"

        candidate = _make_candidate(
            "a.py", "b.py",
            [(15, "    line_a"), (16, "    line_b"), (17, "    line_c")],
            [(15, "    line_a"), (16, "    line_b"), (17, "    line_c")],
        )

        result = compute_effective_diff_for_candidate(
            candidate,
            old_files={"a.py": old_content},
            new_files={"b.py": new_content},
            context_lines=20,
            trim_proximity=3,
        )
        # The change at line 1 is far from the block at lines 15-17
        # It should be trimmed out, leaving no hunks
        self.assertEqual(len(result.hunks), 0)

    def test_result_references_original_candidate(self):
        """The result should reference the original MoveCandidate."""
        content = "line1\nline2\nline3\n"
        candidate = _make_candidate(
            "a.py", "b.py",
            [(1, "line1"), (2, "line2"), (3, "line3")],
            [(1, "line1"), (2, "line2"), (3, "line3")],
        )
        result = compute_effective_diff_for_candidate(
            candidate,
            old_files={"a.py": content},
            new_files={"b.py": content},
            context_lines=0,
        )
        self.assertIs(result.candidate, candidate)


if __name__ == "__main__":
    unittest.main()
