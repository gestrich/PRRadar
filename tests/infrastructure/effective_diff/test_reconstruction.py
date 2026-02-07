"""Tests for Phase 4: Diff reconstruction.

Tests cover:
- Hunk classification (move_removed, move_added, unchanged)
- Diff reconstruction (replacing move hunks with effective diffs)
- Move report generation
"""

from __future__ import annotations

import unittest

from prradar.domain.diff import DiffLineType, GitDiff, Hunk
from prradar.infrastructure.effective_diff import (
    EffectiveDiffResult,
    MoveCandidate,
    MoveDetail,
    MoveReport,
    TaggedLine,
    TaggedLineType,
    _count_changed_lines_in_hunks,
    _hunk_line_range,
    _ranges_overlap,
    build_move_report,
    classify_hunk,
    reconstruct_effective_diff,
)


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------


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


def _make_hunk(
    file_path: str,
    old_start: int,
    old_length: int,
    new_start: int,
    new_length: int,
    content: str = "",
) -> Hunk:
    if not content:
        content = f"@@ -{old_start},{old_length} +{new_start},{new_length} @@\n context"
    return Hunk(
        file_path=file_path,
        content=content,
        old_start=old_start,
        old_length=old_length,
        new_start=new_start,
        new_length=new_length,
    )


def _make_effective_result(
    candidate: MoveCandidate,
    hunks: list[Hunk] | None = None,
    raw_diff: str = "",
) -> EffectiveDiffResult:
    return EffectiveDiffResult(
        candidate=candidate,
        hunks=hunks or [],
        raw_diff=raw_diff,
    )


# ------------------------------------------------------------------
# Tests: _hunk_line_range
# ------------------------------------------------------------------


class TestHunkLineRange(unittest.TestCase):

    def test_old_side_range(self):
        hunk = _make_hunk("a.py", old_start=10, old_length=5, new_start=20, new_length=5)
        start, end = _hunk_line_range(hunk, "old")
        self.assertEqual(start, 10)
        self.assertEqual(end, 14)

    def test_new_side_range(self):
        hunk = _make_hunk("a.py", old_start=10, old_length=5, new_start=20, new_length=5)
        start, end = _hunk_line_range(hunk, "new")
        self.assertEqual(start, 20)
        self.assertEqual(end, 24)

    def test_zero_length_old(self):
        hunk = _make_hunk("a.py", old_start=10, old_length=0, new_start=20, new_length=3)
        start, end = _hunk_line_range(hunk, "old")
        self.assertEqual(start, 10)
        self.assertEqual(end, 10)

    def test_single_line(self):
        hunk = _make_hunk("a.py", old_start=5, old_length=1, new_start=5, new_length=1)
        start, end = _hunk_line_range(hunk, "old")
        self.assertEqual(start, 5)
        self.assertEqual(end, 5)


# ------------------------------------------------------------------
# Tests: _ranges_overlap
# ------------------------------------------------------------------


class TestRangesOverlap(unittest.TestCase):

    def test_identical_ranges(self):
        self.assertTrue(_ranges_overlap(5, 10, 5, 10))

    def test_partial_overlap(self):
        self.assertTrue(_ranges_overlap(5, 10, 8, 15))

    def test_containment(self):
        self.assertTrue(_ranges_overlap(1, 20, 5, 10))

    def test_adjacent_no_overlap(self):
        self.assertFalse(_ranges_overlap(5, 10, 11, 15))

    def test_distant_no_overlap(self):
        self.assertFalse(_ranges_overlap(1, 5, 20, 30))

    def test_touching_boundaries(self):
        self.assertTrue(_ranges_overlap(5, 10, 10, 15))


# ------------------------------------------------------------------
# Tests: classify_hunk
# ------------------------------------------------------------------


class TestClassifyHunk(unittest.TestCase):

    def _setup_move(self):
        """Create a standard move from utils.py (lines 5-10) to helpers.py (lines 15-20)."""
        candidate = _make_candidate(
            "utils.py", "helpers.py",
            [(5, "a"), (6, "b"), (7, "c"), (8, "d"), (9, "e"), (10, "f")],
            [(15, "a"), (16, "b"), (17, "c"), (18, "d"), (19, "e"), (20, "f")],
        )
        result = _make_effective_result(candidate)
        return [result]

    def test_hunk_on_removed_side(self):
        results = self._setup_move()
        hunk = _make_hunk("utils.py", old_start=5, old_length=6, new_start=5, new_length=0)
        classification, matched_result = classify_hunk(hunk, results)
        self.assertEqual(classification, "move_removed")
        self.assertIs(matched_result, results[0])

    def test_hunk_on_added_side(self):
        results = self._setup_move()
        hunk = _make_hunk("helpers.py", old_start=15, old_length=0, new_start=15, new_length=6)
        classification, matched_result = classify_hunk(hunk, results)
        self.assertEqual(classification, "move_added")
        self.assertIs(matched_result, results[0])

    def test_hunk_in_different_file(self):
        results = self._setup_move()
        hunk = _make_hunk("other.py", old_start=5, old_length=3, new_start=5, new_length=3)
        classification, matched_result = classify_hunk(hunk, results)
        self.assertEqual(classification, "unchanged")
        self.assertIsNone(matched_result)

    def test_hunk_in_source_file_but_no_overlap(self):
        results = self._setup_move()
        hunk = _make_hunk("utils.py", old_start=50, old_length=3, new_start=50, new_length=3)
        classification, _ = classify_hunk(hunk, results)
        self.assertEqual(classification, "unchanged")

    def test_hunk_in_target_file_but_no_overlap(self):
        results = self._setup_move()
        hunk = _make_hunk("helpers.py", old_start=1, old_length=3, new_start=1, new_length=3)
        classification, _ = classify_hunk(hunk, results)
        self.assertEqual(classification, "unchanged")

    def test_partial_overlap_on_removed_side(self):
        results = self._setup_move()
        # Hunk covers lines 8-12 on old side, overlapping 8-10 of the move
        hunk = _make_hunk("utils.py", old_start=8, old_length=5, new_start=8, new_length=5)
        classification, _ = classify_hunk(hunk, results)
        self.assertEqual(classification, "move_removed")

    def test_no_effective_results(self):
        hunk = _make_hunk("utils.py", old_start=5, old_length=3, new_start=5, new_length=3)
        classification, matched_result = classify_hunk(hunk, [])
        self.assertEqual(classification, "unchanged")
        self.assertIsNone(matched_result)

    def test_same_file_move(self):
        """Move within the same file — added side should match by new line range."""
        candidate = _make_candidate(
            "services.py", "services.py",
            [(1, "a"), (2, "b"), (3, "c")],
            [(10, "a"), (11, "b"), (12, "c")],
        )
        result = _make_effective_result(candidate)

        # Hunk on removed side (old lines 1-3)
        removed_hunk = _make_hunk("services.py", old_start=1, old_length=3, new_start=0, new_length=0)
        classification, _ = classify_hunk(removed_hunk, [result])
        self.assertEqual(classification, "move_removed")

        # Hunk on added side (new lines 10-12)
        added_hunk = _make_hunk("services.py", old_start=0, old_length=0, new_start=10, new_length=3)
        classification, _ = classify_hunk(added_hunk, [result])
        self.assertEqual(classification, "move_added")


# ------------------------------------------------------------------
# Tests: reconstruct_effective_diff
# ------------------------------------------------------------------


class TestReconstructEffectiveDiff(unittest.TestCase):

    def test_no_moves_returns_original(self):
        """With no effective results, all hunks survive."""
        diff = GitDiff(
            raw_content="",
            hunks=[
                _make_hunk("a.py", 1, 3, 1, 3),
                _make_hunk("b.py", 1, 5, 1, 5),
            ],
        )
        result = reconstruct_effective_diff(diff, [])
        self.assertEqual(len(result.hunks), 2)

    def test_pure_move_drops_both_sides(self):
        """A pure move (no effective diff hunks) removes both sides."""
        candidate = _make_candidate(
            "utils.py", "helpers.py",
            [(5, "a"), (6, "b"), (7, "c")],
            [(10, "a"), (11, "b"), (12, "c")],
        )
        eff_result = _make_effective_result(candidate, hunks=[])

        original = GitDiff(
            raw_content="",
            hunks=[
                _make_hunk("utils.py", old_start=5, old_length=3, new_start=5, new_length=0),
                _make_hunk("helpers.py", old_start=10, old_length=0, new_start=10, new_length=3),
            ],
        )
        result = reconstruct_effective_diff(original, [eff_result])
        self.assertEqual(len(result.hunks), 0)

    def test_move_with_effective_diff_replaces_added_side(self):
        """A move with real changes replaces the added side with effective diff hunks."""
        candidate = _make_candidate(
            "utils.py", "helpers.py",
            [(5, "a"), (6, "b"), (7, "c")],
            [(10, "a"), (11, "b"), (12, "c")],
        )
        effective_hunk = _make_hunk(
            "helpers.py",
            old_start=1, old_length=1, new_start=1, new_length=1,
            content="@@ -1,1 +1,1 @@\n-def old_sig():\n+def new_sig():",
        )
        eff_result = _make_effective_result(candidate, hunks=[effective_hunk])

        original = GitDiff(
            raw_content="",
            hunks=[
                _make_hunk("utils.py", old_start=5, old_length=3, new_start=5, new_length=0),
                _make_hunk("helpers.py", old_start=10, old_length=0, new_start=10, new_length=3),
                _make_hunk("other.py", old_start=1, old_length=2, new_start=1, new_length=3),
            ],
        )
        result = reconstruct_effective_diff(original, [eff_result])
        # utils.py hunk dropped (move_removed), helpers.py replaced with effective hunk, other.py kept
        self.assertEqual(len(result.hunks), 2)
        self.assertEqual(result.hunks[0].file_path, "helpers.py")
        self.assertIn("new_sig", result.hunks[0].content)
        self.assertEqual(result.hunks[1].file_path, "other.py")

    def test_preserves_unrelated_hunks(self):
        """Hunks in files not involved in any move are kept as-is."""
        candidate = _make_candidate(
            "a.py", "b.py",
            [(1, "x"), (2, "y"), (3, "z")],
            [(1, "x"), (2, "y"), (3, "z")],
        )
        eff_result = _make_effective_result(candidate)

        original = GitDiff(
            raw_content="",
            hunks=[
                _make_hunk("a.py", old_start=1, old_length=3, new_start=1, new_length=0),
                _make_hunk("b.py", old_start=1, old_length=0, new_start=1, new_length=3),
                _make_hunk("c.py", old_start=10, old_length=5, new_start=10, new_length=5),
                _make_hunk("d.py", old_start=1, old_length=2, new_start=1, new_length=2),
            ],
        )
        result = reconstruct_effective_diff(original, [eff_result])
        self.assertEqual(len(result.hunks), 2)
        file_paths = [h.file_path for h in result.hunks]
        self.assertIn("c.py", file_paths)
        self.assertIn("d.py", file_paths)

    def test_multiple_moves(self):
        """Multiple independent moves are all handled correctly."""
        candidate1 = _make_candidate(
            "a.py", "b.py",
            [(1, "x"), (2, "y"), (3, "z")],
            [(10, "x"), (11, "y"), (12, "z")],
        )
        candidate2 = _make_candidate(
            "c.py", "d.py",
            [(5, "p"), (6, "q"), (7, "r")],
            [(20, "p"), (21, "q"), (22, "r")],
        )
        eff1 = _make_effective_result(candidate1)
        eff2 = _make_effective_result(candidate2)

        original = GitDiff(
            raw_content="",
            hunks=[
                _make_hunk("a.py", old_start=1, old_length=3, new_start=1, new_length=0),
                _make_hunk("b.py", old_start=10, old_length=0, new_start=10, new_length=3),
                _make_hunk("c.py", old_start=5, old_length=3, new_start=5, new_length=0),
                _make_hunk("d.py", old_start=20, old_length=0, new_start=20, new_length=3),
                _make_hunk("keep.py", old_start=1, old_length=2, new_start=1, new_length=2),
            ],
        )
        result = reconstruct_effective_diff(original, [eff1, eff2])
        self.assertEqual(len(result.hunks), 1)
        self.assertEqual(result.hunks[0].file_path, "keep.py")

    def test_preserves_commit_hash(self):
        original = GitDiff(raw_content="", hunks=[], commit_hash="abc123")
        result = reconstruct_effective_diff(original, [])
        self.assertEqual(result.commit_hash, "abc123")

    def test_no_duplicate_effective_hunks(self):
        """If multiple original hunks map to the same move result, effective hunks are emitted once."""
        candidate = _make_candidate(
            "utils.py", "helpers.py",
            [(5, "a"), (6, "b"), (7, "c"), (8, "d"), (9, "e")],
            [(10, "a"), (11, "b"), (12, "c"), (13, "d"), (14, "e")],
        )
        effective_hunk = _make_hunk(
            "helpers.py", old_start=1, old_length=1, new_start=1, new_length=1,
            content="@@ -1,1 +1,1 @@\n-old\n+new",
        )
        eff_result = _make_effective_result(candidate, hunks=[effective_hunk])

        # Two original hunks that both overlap the added side
        original = GitDiff(
            raw_content="",
            hunks=[
                _make_hunk("helpers.py", old_start=10, old_length=0, new_start=10, new_length=3),
                _make_hunk("helpers.py", old_start=13, old_length=0, new_start=13, new_length=2),
            ],
        )
        result = reconstruct_effective_diff(original, [eff_result])
        # Should emit effective hunk only once, not twice
        self.assertEqual(len(result.hunks), 1)
        self.assertIn("new", result.hunks[0].content)


# ------------------------------------------------------------------
# Tests: _count_changed_lines_in_hunks
# ------------------------------------------------------------------


class TestCountChangedLines(unittest.TestCase):

    def test_counts_added_and_removed(self):
        hunk = _make_hunk(
            "a.py", old_start=1, old_length=2, new_start=1, new_length=2,
            content="@@ -1,2 +1,2 @@\n-old1\n-old2\n+new1\n+new2",
        )
        self.assertEqual(_count_changed_lines_in_hunks([hunk]), 4)

    def test_ignores_context_lines(self):
        hunk = _make_hunk(
            "a.py", old_start=1, old_length=3, new_start=1, new_length=3,
            content="@@ -1,3 +1,3 @@\n context\n-old\n+new\n context2",
        )
        self.assertEqual(_count_changed_lines_in_hunks([hunk]), 2)

    def test_empty_hunks(self):
        self.assertEqual(_count_changed_lines_in_hunks([]), 0)


# ------------------------------------------------------------------
# Tests: build_move_report
# ------------------------------------------------------------------


class TestBuildMoveReport(unittest.TestCase):

    def test_empty_results(self):
        report = build_move_report([])
        self.assertEqual(report.moves_detected, 0)
        self.assertEqual(report.total_lines_moved, 0)
        self.assertEqual(report.total_lines_effectively_changed, 0)
        self.assertEqual(len(report.moves), 0)

    def test_single_pure_move(self):
        candidate = _make_candidate(
            "a.py", "b.py",
            [(1, "x"), (2, "y"), (3, "z")],
            [(10, "x"), (11, "y"), (12, "z")],
            score=0.8,
        )
        eff_result = _make_effective_result(candidate, hunks=[])

        report = build_move_report([eff_result])
        self.assertEqual(report.moves_detected, 1)
        self.assertEqual(report.total_lines_moved, 3)
        self.assertEqual(report.total_lines_effectively_changed, 0)
        self.assertEqual(report.moves[0].source_file, "a.py")
        self.assertEqual(report.moves[0].target_file, "b.py")
        self.assertEqual(report.moves[0].source_lines, (1, 3))
        self.assertEqual(report.moves[0].target_lines, (10, 12))
        self.assertEqual(report.moves[0].matched_lines, 3)
        self.assertEqual(report.moves[0].score, 0.8)
        self.assertEqual(report.moves[0].effective_diff_lines, 0)

    def test_move_with_effective_changes(self):
        candidate = _make_candidate(
            "old.py", "new.py",
            [(5, "a"), (6, "b"), (7, "c"), (8, "d"), (9, "e")],
            [(15, "a"), (16, "b"), (17, "c"), (18, "d"), (19, "e")],
        )
        effective_hunk = _make_hunk(
            "new.py", old_start=1, old_length=1, new_start=1, new_length=1,
            content="@@ -1,1 +1,1 @@\n-old_sig\n+new_sig",
        )
        eff_result = _make_effective_result(candidate, hunks=[effective_hunk])

        report = build_move_report([eff_result])
        self.assertEqual(report.moves_detected, 1)
        self.assertEqual(report.total_lines_moved, 5)
        self.assertEqual(report.total_lines_effectively_changed, 2)  # 1 removed + 1 added

    def test_multiple_moves(self):
        c1 = _make_candidate(
            "a.py", "b.py",
            [(1, "x"), (2, "y"), (3, "z")],
            [(10, "x"), (11, "y"), (12, "z")],
        )
        c2 = _make_candidate(
            "c.py", "d.py",
            [(1, "p"), (2, "q"), (3, "r"), (4, "s")],
            [(20, "p"), (21, "q"), (22, "r"), (23, "s")],
        )
        r1 = _make_effective_result(c1, hunks=[])
        r2 = _make_effective_result(c2, hunks=[])

        report = build_move_report([r1, r2])
        self.assertEqual(report.moves_detected, 2)
        self.assertEqual(report.total_lines_moved, 7)  # 3 + 4
        self.assertEqual(len(report.moves), 2)

    def test_report_is_frozen(self):
        report = build_move_report([])
        self.assertIsInstance(report, MoveReport)
        # Frozen dataclass — cannot set attributes
        with self.assertRaises(AttributeError):
            report.moves_detected = 99

    def test_move_detail_is_frozen(self):
        candidate = _make_candidate("a.py", "b.py", [(1, "x"), (2, "y"), (3, "z")], [(1, "x"), (2, "y"), (3, "z")])
        eff_result = _make_effective_result(candidate)
        report = build_move_report([eff_result])
        with self.assertRaises(AttributeError):
            report.moves[0].source_file = "changed.py"


if __name__ == "__main__":
    unittest.main()
