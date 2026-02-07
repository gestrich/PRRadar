"""Tests for Phase 2: Scoring factors.

Tests cover:
- Size factor (minimum threshold, gradient scaling)
- Line uniqueness (inverse frequency scoring)
- Match consistency (target region coherence)
- Distance factor (hunk distance scoring)
- Composite score_block
"""

from __future__ import annotations

import unittest

from prradar.infrastructure.effective_diff import (
    LineMatch,
    TaggedLine,
    TaggedLineType,
    compute_distance_factor,
    compute_line_uniqueness,
    compute_match_consistency,
    compute_size_factor,
    score_block,
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


def _make_match(
    removed: TaggedLine,
    added: TaggedLine,
    distance: int | None = None,
) -> LineMatch:
    if distance is None:
        distance = abs(removed.hunk_index - added.hunk_index)
    return LineMatch(removed=removed, added=added, distance=distance, similarity=1.0)


# ------------------------------------------------------------------
# Tests: compute_size_factor
# ------------------------------------------------------------------


class TestSizeFactor(unittest.TestCase):

    def test_below_minimum_returns_zero(self):
        block = [_make_match(_make_removed("a.py", i, f"l{i}"), _make_added("b.py", i, f"l{i}"))
                 for i in range(1, 3)]  # 2 lines
        self.assertEqual(compute_size_factor(block, min_block_size=3), 0.0)

    def test_at_minimum_returns_baseline(self):
        block = [_make_match(_make_removed("a.py", i, f"l{i}"), _make_added("b.py", i, f"l{i}"))
                 for i in range(1, 4)]  # 3 lines
        factor = compute_size_factor(block, min_block_size=3)
        self.assertGreater(factor, 0.0)
        self.assertLess(factor, 1.0)

    def test_large_block_returns_one(self):
        block = [_make_match(_make_removed("a.py", i, f"l{i}"), _make_added("b.py", i, f"l{i}"))
                 for i in range(1, 15)]  # 14 lines
        self.assertEqual(compute_size_factor(block, min_block_size=3), 1.0)

    def test_ten_lines_returns_one(self):
        block = [_make_match(_make_removed("a.py", i, f"l{i}"), _make_added("b.py", i, f"l{i}"))
                 for i in range(1, 11)]  # 10 lines
        self.assertEqual(compute_size_factor(block, min_block_size=3), 1.0)

    def test_monotonically_increasing(self):
        """Size factor should increase with block size."""
        factors = []
        for size in range(3, 12):
            block = [_make_match(_make_removed("a.py", i, f"l{i}"), _make_added("b.py", i, f"l{i}"))
                     for i in range(1, size + 1)]
            factors.append(compute_size_factor(block, min_block_size=3))

        for i in range(1, len(factors)):
            self.assertGreaterEqual(factors[i], factors[i - 1])

    def test_empty_block_returns_zero(self):
        self.assertEqual(compute_size_factor([], min_block_size=3), 0.0)

    def test_single_line_returns_zero(self):
        block = [_make_match(_make_removed("a.py", 1, "x"), _make_added("b.py", 1, "x"))]
        self.assertEqual(compute_size_factor(block, min_block_size=3), 0.0)


# ------------------------------------------------------------------
# Tests: compute_line_uniqueness
# ------------------------------------------------------------------


class TestLineUniqueness(unittest.TestCase):

    def test_unique_lines_score_one(self):
        """Lines appearing only once in the added pool get uniqueness 1.0."""
        added_pool = [
            _make_added("b.py", 1, "unique_line_1"),
            _make_added("b.py", 2, "unique_line_2"),
            _make_added("b.py", 3, "unique_line_3"),
        ]
        block = [
            _make_match(_make_removed("a.py", 1, "unique_line_1"), added_pool[0]),
            _make_match(_make_removed("a.py", 2, "unique_line_2"), added_pool[1]),
            _make_match(_make_removed("a.py", 3, "unique_line_3"), added_pool[2]),
        ]
        self.assertAlmostEqual(compute_line_uniqueness(block, added_pool), 1.0)

    def test_duplicate_lines_reduce_uniqueness(self):
        """Lines appearing multiple times get lower uniqueness."""
        added_pool = [
            _make_added("b.py", 1, "return None"),
            _make_added("b.py", 2, "return None"),
            _make_added("b.py", 3, "return None"),
        ]
        block = [
            _make_match(_make_removed("a.py", 1, "return None"), added_pool[0]),
        ]
        uniqueness = compute_line_uniqueness(block, added_pool)
        self.assertAlmostEqual(uniqueness, 1.0 / 3.0)

    def test_mixed_uniqueness(self):
        """Block with mix of unique and common lines gets intermediate score."""
        added_pool = [
            _make_added("b.py", 1, "unique_domain_logic"),
            _make_added("b.py", 2, "return None"),
            _make_added("b.py", 3, "return None"),
        ]
        block = [
            _make_match(_make_removed("a.py", 1, "unique_domain_logic"), added_pool[0]),
            _make_match(_make_removed("a.py", 2, "return None"), added_pool[1]),
        ]
        uniqueness = compute_line_uniqueness(block, added_pool)
        expected = (1.0 + 0.5) / 2.0  # unique=1.0, return None appears 2x so 0.5
        self.assertAlmostEqual(uniqueness, expected)

    def test_empty_block_returns_zero(self):
        self.assertEqual(compute_line_uniqueness([], []), 0.0)

    def test_large_pool_lowers_common_line_score(self):
        """A line appearing 10 times should score 0.1."""
        added_pool = [_make_added("b.py", i, "return None") for i in range(1, 11)]
        block = [
            _make_match(_make_removed("a.py", 1, "return None"), added_pool[0]),
        ]
        self.assertAlmostEqual(compute_line_uniqueness(block, added_pool), 0.1)


# ------------------------------------------------------------------
# Tests: compute_match_consistency
# ------------------------------------------------------------------


class TestMatchConsistency(unittest.TestCase):

    def test_perfectly_consecutive_targets_high_consistency(self):
        """Matches pointing to consecutive target lines should have high consistency."""
        block = [
            _make_match(_make_removed("a.py", i, f"l{i}"), _make_added("b.py", i, f"l{i}"))
            for i in range(1, 6)
        ]
        consistency = compute_match_consistency(block)
        self.assertGreaterEqual(consistency, 0.9)

    def test_single_match_returns_one(self):
        block = [_make_match(_make_removed("a.py", 1, "x"), _make_added("b.py", 1, "x"))]
        self.assertEqual(compute_match_consistency(block), 1.0)

    def test_scattered_targets_lower_consistency(self):
        """Matches pointing to wildly different target lines should have lower consistency."""
        block = [
            _make_match(_make_removed("a.py", 1, "l1"), _make_added("b.py", 1, "l1")),
            _make_match(_make_removed("a.py", 2, "l2"), _make_added("b.py", 50, "l2")),
            _make_match(_make_removed("a.py", 3, "l3"), _make_added("b.py", 100, "l3")),
        ]
        consistency = compute_match_consistency(block)
        # Scattered: target lines 1, 50, 100 — should have reduced consistency
        self.assertLess(consistency, 1.0)

    def test_consecutive_better_than_scattered(self):
        """Consecutive targets should score higher than scattered."""
        consecutive = [
            _make_match(_make_removed("a.py", i, f"l{i}"), _make_added("b.py", i + 10, f"l{i}"))
            for i in range(1, 6)
        ]
        scattered = [
            _make_match(_make_removed("a.py", 1, "l1"), _make_added("b.py", 1, "l1")),
            _make_match(_make_removed("a.py", 2, "l2"), _make_added("b.py", 20, "l2")),
            _make_match(_make_removed("a.py", 3, "l3"), _make_added("b.py", 5, "l3")),
            _make_match(_make_removed("a.py", 4, "l4"), _make_added("b.py", 40, "l4")),
            _make_match(_make_removed("a.py", 5, "l5"), _make_added("b.py", 10, "l5")),
        ]
        self.assertGreater(
            compute_match_consistency(consecutive),
            compute_match_consistency(scattered),
        )


# ------------------------------------------------------------------
# Tests: compute_distance_factor
# ------------------------------------------------------------------


class TestDistanceFactor(unittest.TestCase):

    def test_distance_zero_returns_zero(self):
        block = [
            _make_match(
                _make_removed("a.py", 1, "x", hunk_index=0),
                _make_added("a.py", 1, "x", hunk_index=0),
                distance=0,
            )
        ]
        self.assertEqual(compute_distance_factor(block), 0.0)

    def test_distance_one_returns_half(self):
        block = [
            _make_match(
                _make_removed("a.py", 1, "x", hunk_index=0),
                _make_added("b.py", 1, "x", hunk_index=1),
                distance=1,
            )
        ]
        self.assertAlmostEqual(compute_distance_factor(block), 0.5)

    def test_distance_two_returns_one(self):
        block = [
            _make_match(
                _make_removed("a.py", 1, "x", hunk_index=0),
                _make_added("b.py", 1, "x", hunk_index=2),
                distance=2,
            )
        ]
        self.assertAlmostEqual(compute_distance_factor(block), 1.0)

    def test_large_distance_capped_at_one(self):
        block = [
            _make_match(
                _make_removed("a.py", 1, "x", hunk_index=0),
                _make_added("b.py", 1, "x", hunk_index=10),
                distance=10,
            )
        ]
        self.assertEqual(compute_distance_factor(block), 1.0)


# ------------------------------------------------------------------
# Tests: score_block (composite)
# ------------------------------------------------------------------


class TestScoreBlock(unittest.TestCase):

    def test_good_block_scores_positive(self):
        """A well-formed move block with unique lines should score positively."""
        added_pool = [_make_added("b.py", i, f"unique_line_{i}") for i in range(1, 6)]
        block = [
            _make_match(_make_removed("a.py", i, f"unique_line_{i}"), added_pool[i - 1])
            for i in range(1, 6)
        ]
        score = score_block(block, added_pool)
        self.assertGreater(score, 0)

    def test_tiny_block_scores_zero(self):
        """Blocks below minimum size should score 0."""
        added_pool = [_make_added("b.py", 1, "x"), _make_added("b.py", 2, "y")]
        block = [
            _make_match(_make_removed("a.py", 1, "x"), added_pool[0]),
            _make_match(_make_removed("a.py", 2, "y"), added_pool[1]),
        ]
        self.assertEqual(score_block(block, added_pool), 0.0)

    def test_generic_lines_score_lower_than_unique(self):
        """Blocks of generic lines should score lower than unique lines."""
        # Generic: "return None" appearing many times
        generic_pool = [_make_added("b.py", i, "return None") for i in range(1, 20)]
        generic_block = [
            _make_match(_make_removed("a.py", i, "return None"), generic_pool[i - 1])
            for i in range(1, 6)
        ]

        # Unique: domain-specific lines
        unique_pool = [_make_added("d.py", i, f"domain_logic_{i}") for i in range(1, 6)]
        unique_block = [
            _make_match(_make_removed("c.py", i, f"domain_logic_{i}"), unique_pool[i - 1])
            for i in range(1, 6)
        ]

        generic_score = score_block(generic_block, generic_pool)
        unique_score = score_block(unique_block, unique_pool)
        self.assertGreater(unique_score, generic_score)

    def test_larger_block_scores_higher(self):
        """A larger block should generally score higher than a smaller one."""
        small_pool = [_make_added("b.py", i, f"line_{i}") for i in range(1, 4)]
        small_block = [
            _make_match(_make_removed("a.py", i, f"line_{i}"), small_pool[i - 1])
            for i in range(1, 4)
        ]

        large_pool = [_make_added("b.py", i, f"line_{i}") for i in range(1, 11)]
        large_block = [
            _make_match(_make_removed("a.py", i, f"line_{i}"), large_pool[i - 1])
            for i in range(1, 11)
        ]

        self.assertGreater(score_block(large_block, large_pool), score_block(small_block, small_pool))

    def test_all_factors_contribute(self):
        """Score should be product of all non-zero factors."""
        added_pool = [_make_added("b.py", i, f"unique_{i}") for i in range(1, 6)]
        block = [
            _make_match(_make_removed("a.py", i, f"unique_{i}"), added_pool[i - 1])
            for i in range(1, 6)
        ]
        score = score_block(block, added_pool)

        # Verify each factor individually
        size = compute_size_factor(block)
        uniqueness = compute_line_uniqueness(block, added_pool)
        consistency = compute_match_consistency(block)
        distance = compute_distance_factor(block)

        self.assertAlmostEqual(score, size * uniqueness * consistency * distance)


if __name__ == "__main__":
    unittest.main()
