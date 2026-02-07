"""Tests for Phase 1: Line-level exact matching.

Tests cover:
- TaggedLine extraction from GitDiff hunks
- Added-line index construction
- Exact matching between removed and added lines
- Distance calculation (same hunk vs cross-hunk vs cross-file)
- Blank/whitespace-only line exclusion
- One-to-one match constraint (each added line matched at most once)
- Normalization (whitespace-stripped comparison)
"""

from __future__ import annotations

import unittest

from prradar.domain.diff import GitDiff
from prradar.infrastructure.effective_diff import (
    LineMatch,
    TaggedLine,
    TaggedLineType,
    build_added_index,
    extract_tagged_lines,
    find_exact_matches,
)


def _make_diff(raw: str) -> GitDiff:
    return GitDiff.from_diff_content(raw)


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

WHITESPACE_CHANGE_DIFF = """\
diff --git a/utils.py b/utils.py
index aaa..bbb 100644
--- a/utils.py
+++ b/utils.py
@@ -1,3 +1,0 @@
-def save(data):
-    db.insert(data)
-    return True
diff --git a/models.py b/models.py
index ccc..ddd 100644
--- a/models.py
+++ b/models.py
@@ -0,0 +1,3 @@
+    def save(self, data):
+        db.insert(data)
+        return True
"""

DUPLICATE_LINES_DIFF = """\
diff --git a/a.py b/a.py
index aaa..bbb 100644
--- a/a.py
+++ b/a.py
@@ -1,3 +1,0 @@
-    return None
-    return None
-    return None
diff --git a/b.py b/b.py
index ccc..ddd 100644
--- a/b.py
+++ b/b.py
@@ -0,0 +1,3 @@
+    return None
+    return None
+    return None
"""

BLANK_LINE_DIFF = """\
diff --git a/a.py b/a.py
index aaa..bbb 100644
--- a/a.py
+++ b/a.py
@@ -1,3 +1,3 @@
-content_a
-
-content_b
+content_a
+
+content_b
"""

NO_MATCH_DIFF = """\
diff --git a/a.py b/a.py
index aaa..bbb 100644
--- a/a.py
+++ b/a.py
@@ -1,2 +1,2 @@
-old_function()
-old_helper()
+new_function()
+new_helper()
"""

MULTI_HUNK_SAME_FILE_DIFF = """\
diff --git a/services.py b/services.py
index aaa..bbb 100644
--- a/services.py
+++ b/services.py
@@ -1,5 +1,0 @@
-def method_a():
-    return "a"
-
-def method_b():
-    return "b"
@@ -20,0 +15,5 @@
+def method_b():
+    return "b"
+
+def method_a():
+    return "a"
"""


# ------------------------------------------------------------------
# Tests: extract_tagged_lines
# ------------------------------------------------------------------


class TestExtractTaggedLines(unittest.TestCase):

    def test_cross_file_move_extracts_removed_and_added(self):
        git_diff = _make_diff(CROSS_FILE_MOVE_DIFF)
        removed, added = extract_tagged_lines(git_diff)

        self.assertEqual(len(removed), 5)
        self.assertEqual(len(added), 5)

        self.assertTrue(all(r.file_path == "utils.py" for r in removed))
        self.assertTrue(all(a.file_path == "helpers.py" for a in added))

    def test_tagged_line_has_correct_metadata(self):
        git_diff = _make_diff(CROSS_FILE_MOVE_DIFF)
        removed, added = extract_tagged_lines(git_diff)

        first_removed = removed[0]
        self.assertEqual(first_removed.content, "def calculate_total(items):")
        self.assertEqual(first_removed.normalized, "def calculate_total(items):")
        self.assertEqual(first_removed.file_path, "utils.py")
        self.assertEqual(first_removed.line_number, 1)
        self.assertEqual(first_removed.hunk_index, 0)
        self.assertEqual(first_removed.line_type, TaggedLineType.REMOVED)

        first_added = added[0]
        self.assertEqual(first_added.content, "def calculate_total(items):")
        self.assertEqual(first_added.file_path, "helpers.py")
        self.assertEqual(first_added.line_number, 1)
        self.assertEqual(first_added.hunk_index, 1)
        self.assertEqual(first_added.line_type, TaggedLineType.ADDED)

    def test_same_hunk_edit_has_correct_hunk_index(self):
        git_diff = _make_diff(SAME_HUNK_EDIT_DIFF)
        removed, added = extract_tagged_lines(git_diff)

        self.assertEqual(len(removed), 1)
        self.assertEqual(len(added), 1)
        self.assertEqual(removed[0].hunk_index, 0)
        self.assertEqual(added[0].hunk_index, 0)

    def test_whitespace_normalization(self):
        git_diff = _make_diff(WHITESPACE_CHANGE_DIFF)
        removed, added = extract_tagged_lines(git_diff)

        removed_norms = [r.normalized for r in removed]
        added_norms = [a.normalized for a in added]

        self.assertIn("db.insert(data)", removed_norms)
        self.assertIn("db.insert(data)", added_norms)
        self.assertIn("return True", removed_norms)
        self.assertIn("return True", added_norms)

    def test_context_lines_excluded(self):
        git_diff = _make_diff(SAME_HUNK_EDIT_DIFF)
        removed, added = extract_tagged_lines(git_diff)

        all_contents = [r.content for r in removed] + [a.content for a in added]
        self.assertNotIn("shared_line = True", all_contents)

    def test_multi_hunk_same_file_different_indices(self):
        git_diff = _make_diff(MULTI_HUNK_SAME_FILE_DIFF)
        removed, added = extract_tagged_lines(git_diff)

        self.assertTrue(len(removed) > 0)
        self.assertTrue(len(added) > 0)
        self.assertEqual(removed[0].hunk_index, 0)
        self.assertEqual(added[0].hunk_index, 1)


# ------------------------------------------------------------------
# Tests: build_added_index
# ------------------------------------------------------------------


class TestBuildAddedIndex(unittest.TestCase):

    def test_index_keys_are_normalized(self):
        git_diff = _make_diff(WHITESPACE_CHANGE_DIFF)
        _, added = extract_tagged_lines(git_diff)
        index = build_added_index(added)

        self.assertIn("db.insert(data)", index)
        self.assertIn("return True", index)

    def test_blank_lines_excluded_from_index(self):
        git_diff = _make_diff(BLANK_LINE_DIFF)
        _, added = extract_tagged_lines(git_diff)
        index = build_added_index(added)

        self.assertNotIn("", index)

    def test_duplicate_lines_indexed_as_list(self):
        git_diff = _make_diff(DUPLICATE_LINES_DIFF)
        _, added = extract_tagged_lines(git_diff)
        index = build_added_index(added)

        self.assertEqual(len(index["return None"]), 3)


# ------------------------------------------------------------------
# Tests: find_exact_matches
# ------------------------------------------------------------------


class TestFindExactMatches(unittest.TestCase):

    def test_cross_file_pure_move_all_lines_match(self):
        git_diff = _make_diff(CROSS_FILE_MOVE_DIFF)
        removed, added = extract_tagged_lines(git_diff)
        matches = find_exact_matches(removed, added)

        self.assertEqual(len(matches), 5)
        for m in matches:
            self.assertEqual(m.similarity, 1.0)
            self.assertEqual(m.removed.file_path, "utils.py")
            self.assertEqual(m.added.file_path, "helpers.py")

    def test_cross_file_distance_is_positive(self):
        git_diff = _make_diff(CROSS_FILE_MOVE_DIFF)
        removed, added = extract_tagged_lines(git_diff)
        matches = find_exact_matches(removed, added)

        for m in matches:
            self.assertEqual(m.distance, 1)

    def test_same_hunk_distance_is_zero(self):
        git_diff = _make_diff(SAME_HUNK_EDIT_DIFF)
        removed, added = extract_tagged_lines(git_diff)
        matches = find_exact_matches(removed, added)

        # "x = old_value" vs "x = new_value" should NOT match
        self.assertEqual(len(matches), 0)

    def test_no_match_when_content_differs(self):
        git_diff = _make_diff(NO_MATCH_DIFF)
        removed, added = extract_tagged_lines(git_diff)
        matches = find_exact_matches(removed, added)

        self.assertEqual(len(matches), 0)

    def test_whitespace_normalized_matching(self):
        git_diff = _make_diff(WHITESPACE_CHANGE_DIFF)
        removed, added = extract_tagged_lines(git_diff)
        matches = find_exact_matches(removed, added)

        matched_norms = {m.removed.normalized for m in matches}
        self.assertIn("db.insert(data)", matched_norms)
        self.assertIn("return True", matched_norms)

    def test_one_to_one_matching(self):
        git_diff = _make_diff(DUPLICATE_LINES_DIFF)
        removed, added = extract_tagged_lines(git_diff)
        matches = find_exact_matches(removed, added)

        self.assertEqual(len(matches), 3)

        added_ids = [id(m.added) for m in matches]
        self.assertEqual(len(set(added_ids)), 3)

    def test_blank_lines_not_matched(self):
        git_diff = _make_diff(BLANK_LINE_DIFF)
        removed, added = extract_tagged_lines(git_diff)
        matches = find_exact_matches(removed, added)

        # "content_a" and "content_b" match, blank lines do not
        matched_norms = {m.removed.normalized for m in matches}
        self.assertNotIn("", matched_norms)

    def test_multi_hunk_swap_matches(self):
        git_diff = _make_diff(MULTI_HUNK_SAME_FILE_DIFF)
        removed, added = extract_tagged_lines(git_diff)
        matches = find_exact_matches(removed, added)

        # 4 non-blank lines match (blank line between methods is excluded)
        self.assertEqual(len(matches), 4)

        for m in matches:
            self.assertGreater(m.distance, 0)

    def test_match_preserves_original_content(self):
        git_diff = _make_diff(WHITESPACE_CHANGE_DIFF)
        removed, added = extract_tagged_lines(git_diff)
        matches = find_exact_matches(removed, added)

        db_match = next(m for m in matches if m.removed.normalized == "db.insert(data)")
        self.assertEqual(db_match.removed.content, "    db.insert(data)")
        self.assertEqual(db_match.added.content, "        db.insert(data)")

    def test_match_line_numbers_correct(self):
        git_diff = _make_diff(CROSS_FILE_MOVE_DIFF)
        removed, added = extract_tagged_lines(git_diff)
        matches = find_exact_matches(removed, added)

        first = matches[0]
        self.assertEqual(first.removed.line_number, 1)
        self.assertEqual(first.added.line_number, 1)

        last = matches[-1]
        self.assertEqual(last.removed.line_number, 5)
        self.assertEqual(last.added.line_number, 5)


if __name__ == "__main__":
    unittest.main()
