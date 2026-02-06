"""Tests for diff parsing functionality.

Tests cover:
- New file hunks (@@ -0,0 +1,10 @@)
- Modified file hunks (@@ -118,98 +118,36 @@)
- Multi-file diff parsing
- Edge cases (empty diff, binary file markers, single-line hunks)
"""

from __future__ import annotations

import json
import unittest

from scripts.domain.diff import DiffLine, DiffLineType, GitDiff, Hunk
from scripts.infrastructure.git.diff_parser import (
    format_diff_as_json,
    format_diff_as_text,
    has_content,
    is_binary_file_marker,
    is_rename_operation,
)


class TestHunkParsing(unittest.TestCase):
    """Tests for Hunk.from_hunk_lines() factory method."""

    def test_new_file_hunk(self):
        """Test parsing a new file hunk (@@ -0,0 +1,10 @@)."""
        file_header = [
            "diff --git a/test-files/FFLogger.h b/test-files/FFLogger.h",
            "new file mode 100644",
            "index 0000000..abc1234",
            "--- /dev/null",
            "+++ b/test-files/FFLogger.h",
        ]
        hunk_lines = [
            "@@ -0,0 +1,10 @@",
            "+#import <Foundation/Foundation.h>",
            "+",
            "+@interface FFLogger : NSObject",
            "+",
            "+- (void)log:(NSString *)message;",
            "+",
            "+@end",
        ]

        hunk = Hunk.from_hunk_lines(file_header, hunk_lines, "test-files/FFLogger.h")

        self.assertIsNotNone(hunk)
        self.assertEqual(hunk.file_path, "test-files/FFLogger.h")
        self.assertEqual(hunk.old_start, 0)
        self.assertEqual(hunk.old_length, 0)
        self.assertEqual(hunk.new_start, 1)
        self.assertEqual(hunk.new_length, 10)

    def test_modified_file_hunk(self):
        """Test parsing a modified file hunk (@@ -118,98 +118,36 @@)."""
        file_header = [
            "diff --git a/src/App.swift b/src/App.swift",
            "index abc1234..def5678",
            "--- a/src/App.swift",
            "+++ b/src/App.swift",
        ]
        hunk_lines = [
            "@@ -118,98 +118,36 @@ class App {",
            "     func setup() {",
            "-        oldCode()",
            "+        newCode()",
            "     }",
        ]

        hunk = Hunk.from_hunk_lines(file_header, hunk_lines, "src/App.swift")

        self.assertIsNotNone(hunk)
        self.assertEqual(hunk.file_path, "src/App.swift")
        self.assertEqual(hunk.old_start, 118)
        self.assertEqual(hunk.old_length, 98)
        self.assertEqual(hunk.new_start, 118)
        self.assertEqual(hunk.new_length, 36)

    def test_single_line_hunk(self):
        """Test parsing a single-line hunk (@@ -0,0 +1 @@) without length specifier."""
        file_header = [
            "diff --git a/VERSION b/VERSION",
            "new file mode 100644",
            "index 0000000..8a3c2d1",
            "--- /dev/null",
            "+++ b/VERSION",
        ]
        hunk_lines = [
            "@@ -0,0 +1 @@",
            "+1.0.0",
        ]

        hunk = Hunk.from_hunk_lines(file_header, hunk_lines, "VERSION")

        self.assertIsNotNone(hunk)
        self.assertEqual(hunk.new_start, 1)
        self.assertEqual(hunk.new_length, 1)
        self.assertEqual(hunk.old_start, 0)
        self.assertEqual(hunk.old_length, 0)

    def test_empty_file_path_returns_none(self):
        """Test that empty file path returns None."""
        hunk = Hunk.from_hunk_lines([], ["@@ -0,0 +1 @@"], "")
        self.assertIsNone(hunk)

    def test_hunk_to_dict(self):
        """Test Hunk.to_dict() for JSON serialization."""
        hunk = Hunk(
            file_path="test.py",
            content="@@ -1,5 +1,6 @@\n context",
            old_start=1,
            old_length=5,
            new_start=1,
            new_length=6,
        )

        result = hunk.to_dict()

        self.assertEqual(result["file_path"], "test.py")
        self.assertEqual(result["new_start"], 1)
        self.assertEqual(result["new_length"], 6)
        self.assertEqual(result["old_start"], 1)
        self.assertEqual(result["old_length"], 5)
        self.assertIn("content", result)

    def test_filename_property(self):
        """Test extracting filename from file path."""
        hunk = Hunk(file_path="src/components/Button.tsx", content="")
        self.assertEqual(hunk.filename, "Button.tsx")

        hunk_no_path = Hunk(file_path="README.md", content="")
        self.assertEqual(hunk_no_path.filename, "README.md")

    def test_file_extension_property(self):
        """Test extracting file extension."""
        hunk = Hunk(file_path="src/App.swift", content="")
        self.assertEqual(hunk.file_extension, "swift")

        hunk_no_ext = Hunk(file_path="Makefile", content="")
        self.assertEqual(hunk_no_ext.file_extension, "")


class TestGitDiffParsing(unittest.TestCase):
    """Tests for GitDiff.from_diff_content() factory method."""

    def test_multi_file_diff(self):
        """Test parsing a diff with multiple files."""
        diff_content = """diff --git a/file1.swift b/file1.swift
index abc1234..def5678
--- a/file1.swift
+++ b/file1.swift
@@ -1,5 +1,6 @@
 import Foundation
+import UIKit

 class MyClass {
diff --git a/file2.swift b/file2.swift
new file mode 100644
index 0000000..abc1234
--- /dev/null
+++ b/file2.swift
@@ -0,0 +1,10 @@
+import Foundation
+
+class NewClass {
+}
"""
        diff = GitDiff.from_diff_content(diff_content)

        self.assertEqual(len(diff.hunks), 2)
        self.assertEqual(diff.hunks[0].file_path, "file1.swift")
        self.assertEqual(diff.hunks[0].new_start, 1)
        self.assertEqual(diff.hunks[0].new_length, 6)
        self.assertEqual(diff.hunks[1].file_path, "file2.swift")
        self.assertEqual(diff.hunks[1].new_start, 1)
        self.assertEqual(diff.hunks[1].new_length, 10)

    def test_multiple_hunks_same_file(self):
        """Test parsing a file with multiple hunks."""
        diff_content = """diff --git a/large_file.py b/large_file.py
index abc1234..def5678
--- a/large_file.py
+++ b/large_file.py
@@ -10,6 +10,7 @@ def first_function():
     pass
+    # new comment

@@ -100,4 +101,5 @@ def second_function():
     return True
+    # another comment
"""
        diff = GitDiff.from_diff_content(diff_content)

        self.assertEqual(len(diff.hunks), 2)
        self.assertEqual(diff.hunks[0].new_start, 10)
        self.assertEqual(diff.hunks[0].new_length, 7)
        self.assertEqual(diff.hunks[1].new_start, 101)
        self.assertEqual(diff.hunks[1].new_length, 5)

    def test_empty_diff(self):
        """Test parsing an empty diff."""
        diff = GitDiff.from_diff_content("")
        self.assertTrue(diff.is_empty)
        self.assertEqual(len(diff.hunks), 0)

    def test_whitespace_only_diff(self):
        """Test parsing a whitespace-only diff."""
        diff = GitDiff.from_diff_content("   \n\n  \t  ")
        self.assertTrue(diff.is_empty)

    def test_diff_with_commit_hash(self):
        """Test that commit hash is preserved."""
        diff = GitDiff.from_diff_content("diff --git a/f.py b/f.py\n", commit_hash="abc123")
        self.assertEqual(diff.commit_hash, "abc123")

    def test_diff_to_dict(self):
        """Test GitDiff.to_dict() for JSON serialization."""
        diff_content = """diff --git a/test.py b/test.py
index abc..def
--- a/test.py
+++ b/test.py
@@ -1,3 +1,4 @@
 line1
+new_line
"""
        diff = GitDiff.from_diff_content(diff_content, commit_hash="abc123")
        result = diff.to_dict()

        self.assertEqual(result["commit_hash"], "abc123")
        self.assertIsInstance(result["hunks"], list)
        self.assertEqual(len(result["hunks"]), 1)
        self.assertEqual(result["hunks"][0]["file_path"], "test.py")

    def test_get_unique_files(self):
        """Test getting unique file paths from diff."""
        diff_content = """diff --git a/file1.py b/file1.py
--- a/file1.py
+++ b/file1.py
@@ -1,3 +1,4 @@
 line
@@ -10,3 +11,4 @@
 line
diff --git a/file2.py b/file2.py
--- a/file2.py
+++ b/file2.py
@@ -1,3 +1,4 @@
 line
"""
        diff = GitDiff.from_diff_content(diff_content)
        files = diff.get_unique_files()

        self.assertEqual(len(files), 2)
        self.assertIn("file1.py", files)
        self.assertIn("file2.py", files)

    def test_get_hunks_by_extension(self):
        """Test filtering hunks by file extension."""
        diff_content = """diff --git a/app.swift b/app.swift
--- a/app.swift
+++ b/app.swift
@@ -1,3 +1,4 @@
 code
diff --git a/test.py b/test.py
--- a/test.py
+++ b/test.py
@@ -1,3 +1,4 @@
 code
diff --git a/style.css b/style.css
--- a/style.css
+++ b/style.css
@@ -1,3 +1,4 @@
 style
"""
        diff = GitDiff.from_diff_content(diff_content)

        swift_hunks = diff.get_hunks_by_extension(["swift"])
        self.assertEqual(len(swift_hunks), 1)
        self.assertEqual(swift_hunks[0].file_path, "app.swift")

        code_hunks = diff.get_hunks_by_extension(["swift", "py"])
        self.assertEqual(len(code_hunks), 2)

    def test_get_hunks_by_file(self):
        """Test filtering hunks by file path."""
        diff_content = """diff --git a/target.py b/target.py
--- a/target.py
+++ b/target.py
@@ -1,3 +1,4 @@
 first
@@ -10,3 +11,4 @@
 second
diff --git a/other.py b/other.py
--- a/other.py
+++ b/other.py
@@ -1,3 +1,4 @@
 other
"""
        diff = GitDiff.from_diff_content(diff_content)
        target_hunks = diff.get_hunks_by_file("target.py")

        self.assertEqual(len(target_hunks), 2)
        for hunk in target_hunks:
            self.assertEqual(hunk.file_path, "target.py")


class TestInfrastructureFunctions(unittest.TestCase):
    """Tests for infrastructure helper functions."""

    def test_is_binary_file_marker(self):
        """Test binary file detection."""
        self.assertTrue(is_binary_file_marker("Binary files a/img.png and b/img.png differ"))
        self.assertTrue(is_binary_file_marker("GIT binary patch"))
        self.assertFalse(is_binary_file_marker("+// This is not binary"))
        self.assertFalse(is_binary_file_marker("diff --git a/file.txt b/file.txt"))

    def test_is_rename_operation(self):
        """Test rename operation detection."""
        rename_diff = """diff --git a/old.py b/new.py
similarity index 100%
rename from old.py
rename to new.py
"""
        self.assertTrue(is_rename_operation(rename_diff))

        normal_diff = """diff --git a/file.py b/file.py
--- a/file.py
+++ b/file.py
@@ -1,3 +1,4 @@
"""
        self.assertFalse(is_rename_operation(normal_diff))

    def test_has_content(self):
        """Test content detection."""
        self.assertTrue(has_content("diff --git a/f.py b/f.py"))
        self.assertTrue(has_content("@@ -1,3 +1,4 @@"))
        self.assertFalse(has_content(""))
        self.assertFalse(has_content("   \n\n  "))
        self.assertFalse(has_content("random text without diff markers"))


class TestOutputFormatting(unittest.TestCase):
    """Tests for output formatting functions."""

    def test_format_diff_as_json(self):
        """Test JSON output formatting."""
        diff_content = """diff --git a/test.py b/test.py
index abc..def
--- a/test.py
+++ b/test.py
@@ -1,3 +1,4 @@
 line
"""
        diff = GitDiff.from_diff_content(diff_content)
        json_output = format_diff_as_json(diff)

        parsed = json.loads(json_output)
        self.assertIn("hunks", parsed)
        self.assertEqual(len(parsed["hunks"]), 1)
        self.assertEqual(parsed["hunks"][0]["file_path"], "test.py")
        self.assertEqual(parsed["hunks"][0]["new_start"], 1)

    def test_format_diff_as_text_empty(self):
        """Test text output for empty diff."""
        diff = GitDiff.from_diff_content("")
        text_output = format_diff_as_text(diff)
        self.assertEqual(text_output, "Empty diff (no hunks found)")

    def test_format_diff_as_text_with_hunks(self):
        """Test text output with hunks."""
        diff_content = """diff --git a/test.py b/test.py
--- a/test.py
+++ b/test.py
@@ -10,5 +10,8 @@
 code
"""
        diff = GitDiff.from_diff_content(diff_content)
        text_output = format_diff_as_text(diff)

        self.assertIn("Files changed: 1", text_output)
        self.assertIn("Total hunks: 1", text_output)
        self.assertIn("test.py", text_output)
        self.assertIn("New: lines 10", text_output)


class TestQuotedFilePaths(unittest.TestCase):
    """Tests for handling quoted file paths in diffs."""

    def test_file_path_with_spaces(self):
        """Test parsing diff with file paths containing spaces."""
        diff_content = '''diff --git "a/path with spaces/file.txt" "b/path with spaces/file.txt"
index abc..def
--- "a/path with spaces/file.txt"
+++ "b/path with spaces/file.txt"
@@ -1,3 +1,4 @@
 content
'''
        diff = GitDiff.from_diff_content(diff_content)

        self.assertEqual(len(diff.hunks), 1)
        self.assertEqual(diff.hunks[0].file_path, "path with spaces/file.txt")


class TestDiffLineExtraction(unittest.TestCase):
    """Tests for Hunk line extraction methods.

    These tests verify that grep patterns only match against changed lines
    (added/removed), not context lines.
    """

    def setUp(self):
        """Create a sample hunk with mixed line types for testing."""
        self.sample_diff = """diff --git a/src/handler.py b/src/handler.py
index abc1234..def5678
--- a/src/handler.py
+++ b/src/handler.py
@@ -10,8 +10,9 @@ class Handler:
     def process(self):
         # Context line with NSArray
         existing_code()
-        old_removed_code()
-        NSArray *removedArray;
+        new_added_code()
+        NSArray *addedArray;
+        extra_line()
         more_context()
"""
        self.diff = GitDiff.from_diff_content(self.sample_diff)
        self.hunk = self.diff.hunks[0]

    def test_get_diff_lines_returns_all_line_types(self):
        """Verify get_diff_lines returns all lines with correct types."""
        diff_lines = self.hunk.get_diff_lines()

        # Should have header lines, context lines, removed lines, and added lines
        headers = [l for l in diff_lines if l.line_type == DiffLineType.HEADER]
        contexts = [l for l in diff_lines if l.line_type == DiffLineType.CONTEXT]
        added = [l for l in diff_lines if l.line_type == DiffLineType.ADDED]
        removed = [l for l in diff_lines if l.line_type == DiffLineType.REMOVED]

        self.assertGreater(len(headers), 0, "Should have header lines")
        self.assertGreater(len(contexts), 0, "Should have context lines")
        self.assertEqual(len(added), 3, "Should have 3 added lines")
        self.assertEqual(len(removed), 2, "Should have 2 removed lines")

    def test_get_added_lines_only_returns_additions(self):
        """Verify get_added_lines returns only lines starting with +."""
        added = self.hunk.get_added_lines()

        self.assertEqual(len(added), 3)
        for line in added:
            self.assertEqual(line.line_type, DiffLineType.ADDED)
            self.assertTrue(line.raw_line.startswith("+"))

    def test_get_removed_lines_only_returns_deletions(self):
        """Verify get_removed_lines returns only lines starting with -."""
        removed = self.hunk.get_removed_lines()

        self.assertEqual(len(removed), 2)
        for line in removed:
            self.assertEqual(line.line_type, DiffLineType.REMOVED)
            self.assertTrue(line.raw_line.startswith("-"))

    def test_get_changed_lines_excludes_context(self):
        """Verify get_changed_lines returns added+removed but not context."""
        changed = self.hunk.get_changed_lines()

        # Should have 3 added + 2 removed = 5 changed
        self.assertEqual(len(changed), 5)
        for line in changed:
            self.assertTrue(line.is_changed)
            self.assertIn(line.line_type, [DiffLineType.ADDED, DiffLineType.REMOVED])

    def test_get_context_lines_only_returns_context(self):
        """Verify get_context_lines returns only unchanged lines."""
        context = self.hunk.get_context_lines()

        for line in context:
            self.assertEqual(line.line_type, DiffLineType.CONTEXT)
            self.assertTrue(line.raw_line.startswith(" ") or line.raw_line == "")

    def test_added_lines_have_new_line_numbers(self):
        """Verify added lines have new_line_number but not old_line_number."""
        added = self.hunk.get_added_lines()

        for line in added:
            self.assertIsNotNone(line.new_line_number)
            self.assertIsNone(line.old_line_number)

    def test_removed_lines_have_old_line_numbers(self):
        """Verify removed lines have old_line_number but not new_line_number."""
        removed = self.hunk.get_removed_lines()

        for line in removed:
            self.assertIsNotNone(line.old_line_number)
            self.assertIsNone(line.new_line_number)

    def test_context_lines_have_both_line_numbers(self):
        """Verify context lines have both old and new line numbers."""
        context = self.hunk.get_context_lines()

        for line in context:
            self.assertIsNotNone(line.new_line_number)
            self.assertIsNotNone(line.old_line_number)

    def test_get_changed_content_excludes_context(self):
        """Verify get_changed_content only includes changed lines."""
        changed_content = self.hunk.get_changed_content()

        # Should contain the changed code
        self.assertIn("new_added_code", changed_content)
        self.assertIn("old_removed_code", changed_content)
        self.assertIn("NSArray *addedArray", changed_content)
        self.assertIn("NSArray *removedArray", changed_content)

        # Should NOT contain context lines (existing_code is context)
        self.assertNotIn("existing_code", changed_content)
        self.assertNotIn("more_context", changed_content)

    def test_extract_changed_content_static_method(self):
        """Verify static extract_changed_content works without Hunk instance."""
        diff_text = """diff --git a/test.m b/test.m
--- a/test.m
+++ b/test.m
@@ -1,5 +1,6 @@
 #import <Foundation/Foundation.h>
 NSArray *contextArray;
-NSMutableArray *oldArray;
+NSMutableArray *newArray;
+NSDictionary *addedDict;
 // end context
"""
        changed = Hunk.extract_changed_content(diff_text)

        # Should contain changed lines
        self.assertIn("NSMutableArray *oldArray", changed)
        self.assertIn("NSMutableArray *newArray", changed)
        self.assertIn("NSDictionary *addedDict", changed)

        # Should NOT contain context
        self.assertNotIn("#import", changed)
        self.assertNotIn("contextArray", changed)
        self.assertNotIn("end context", changed)

    def test_extract_changed_content_handles_annotated_format(self):
        """Verify extract_changed_content works with annotated line numbers.

        When diff content is stored with annotate_lines=True, lines have format:
        - Added: "123: +    code"
        - Removed: "   -: -    code"
        - Context: "123:      code"
        """
        annotated_diff = """diff --git a/test.mm b/test.mm
index abc..def 100644
--- a/test.mm
+++ b/test.mm
@@ -364,7 +364,13 @@ -(void)someMethod {
 364:      return @[];
 365:  }
 366:
   -: -    [self oldMethod:metadata];
 367: +    // New comment
 368: +    NSArray *items = [metadata componentsSeparatedByString:@"\\t"];
 369: +    [self newMethod:items];
 370:
 371:      return @[];
 372:  }
"""
        changed = Hunk.extract_changed_content(annotated_diff)

        # Should contain added lines (without the prefix)
        self.assertIn("// New comment", changed)
        self.assertIn('componentsSeparatedByString:@"\\t"', changed)
        self.assertIn("[self newMethod:items]", changed)

        # Should contain removed lines
        self.assertIn("[self oldMethod:metadata]", changed)

        # Should NOT contain context lines
        self.assertNotIn("return @[]", changed)
        self.assertNotIn("364:", changed)  # Line numbers should not appear


class TestGrepFiltering(unittest.TestCase):
    """Tests for grep pattern matching on changed content only.

    Critical: Grep patterns should only match against added/removed lines,
    not context lines. This prevents false positives from unchanged code
    that happens to appear in the diff context.
    """

    def test_grep_matches_added_lines(self):
        """Pattern should match when found in added lines."""
        diff_text = """@@ -1,3 +1,4 @@
 context line
-removed NSArray
+added NSArray
"""
        changed = Hunk.extract_changed_content(diff_text)

        self.assertIn("NSArray", changed)

    def test_grep_matches_removed_lines(self):
        """Pattern should match when found in removed lines."""
        diff_text = """@@ -1,3 +1,3 @@
 context line
-removed NSMutableDictionary
+added something else
"""
        changed = Hunk.extract_changed_content(diff_text)

        self.assertIn("NSMutableDictionary", changed)

    def test_grep_does_not_match_context_only(self):
        """Pattern should NOT match when only in context lines."""
        diff_text = """@@ -1,4 +1,4 @@
 existing NSArray in context
 another context line
-removed something unrelated
+added something unrelated
"""
        changed = Hunk.extract_changed_content(diff_text)

        # NSArray is only in context, not in changed lines
        self.assertNotIn("NSArray", changed)

    def test_grep_real_world_objc_example(self):
        """Test realistic ObjC diff with collection type in context."""
        diff_text = """@@ -50,8 +50,9 @@ - (void)processData {
     NSArray<FFAirport *> *airports = self.airports;  // context - already typed
     for (FFAirport *airport in airports) {
-        [self handleAirport:airport];
+        [self handleAirport:airport withOptions:options];
+        [self logAirport:airport];
     }
 }
"""
        changed = Hunk.extract_changed_content(diff_text)

        # Changed lines do NOT contain NSArray - it's only in context
        self.assertNotIn("NSArray", changed)
        # But they do contain the actual changes
        self.assertIn("handleAirport:airport withOptions:options", changed)
        self.assertIn("logAirport:airport", changed)

    def test_grep_matches_when_pattern_in_both(self):
        """Pattern should match when in changed lines even if also in context."""
        diff_text = """@@ -1,4 +1,5 @@
 NSArray *contextArray;  // context
-NSArray *oldArray;
+NSArray *newArray;
+NSDictionary *addedDict;
 NSSet *contextSet;  // context
"""
        changed = Hunk.extract_changed_content(diff_text)

        # NSArray is in both context and changed - should still match
        self.assertIn("NSArray", changed)
        # Verify we're matching the changed lines, not context
        self.assertIn("oldArray", changed)
        self.assertIn("newArray", changed)

    def test_extract_ignores_diff_header_markers(self):
        """Ensure +++ and --- header lines are not included."""
        diff_text = """diff --git a/test.m b/test.m
--- a/test.m
+++ b/test.m
@@ -1,3 +1,4 @@
 context
+added line
"""
        changed = Hunk.extract_changed_content(diff_text)

        # Should not include the +++ header
        self.assertNotIn("b/test.m", changed)
        self.assertNotIn("a/test.m", changed)
        # Should include the actual added line
        self.assertIn("added line", changed)


class TestFilePathFiltering(unittest.TestCase):
    """Tests for file path/extension filtering on rules."""

    def test_objc_patterns_match_header(self):
        """Test *.h pattern matches Objective-C rule."""
        from scripts.domain.rule import AppliesTo

        applies_to = AppliesTo(file_patterns=["*.h", "*.m", "*.mm"])

        self.assertTrue(applies_to.matches_file("src/FFLogger.h"))
        self.assertTrue(applies_to.matches_file("path/to/deep/File.h"))

    def test_objc_patterns_match_implementation(self):
        """Test *.m and *.mm patterns match Objective-C rule."""
        from scripts.domain.rule import AppliesTo

        applies_to = AppliesTo(file_patterns=["*.h", "*.m", "*.mm"])

        self.assertTrue(applies_to.matches_file("src/FFLogger.m"))
        self.assertTrue(applies_to.matches_file("src/FFBridge.mm"))

    def test_objc_patterns_reject_swift(self):
        """Test Swift files don't match Objective-C rule."""
        from scripts.domain.rule import AppliesTo

        applies_to = AppliesTo(file_patterns=["*.h", "*.m", "*.mm"])

        self.assertFalse(applies_to.matches_file("src/FFLogger.swift"))
        self.assertFalse(applies_to.matches_file("Package.swift"))

    def test_objc_patterns_reject_other_languages(self):
        """Test other language files don't match Objective-C rule."""
        from scripts.domain.rule import AppliesTo

        applies_to = AppliesTo(file_patterns=["*.h", "*.m", "*.mm"])

        self.assertFalse(applies_to.matches_file("src/main.py"))
        self.assertFalse(applies_to.matches_file("src/index.js"))
        self.assertFalse(applies_to.matches_file("src/Handler.java"))

    def test_empty_patterns_matches_all(self):
        """Test empty file_patterns matches all files."""
        from scripts.domain.rule import AppliesTo

        applies_to = AppliesTo(file_patterns=[])

        self.assertTrue(applies_to.matches_file("anything.txt"))
        self.assertTrue(applies_to.matches_file("src/code.py"))
        self.assertTrue(applies_to.matches_file("Makefile"))

    def test_no_extension_file(self):
        """Test files without extensions."""
        from scripts.domain.rule import AppliesTo

        applies_to = AppliesTo(file_patterns=["*.py", "*.swift"])

        self.assertFalse(applies_to.matches_file("Makefile"))
        self.assertFalse(applies_to.matches_file("Dockerfile"))

    def test_case_sensitive_pattern(self):
        """Test pattern matching is case-sensitive."""
        from scripts.domain.rule import AppliesTo

        applies_to = AppliesTo(file_patterns=["*.swift"])

        self.assertTrue(applies_to.matches_file("App.swift"))
        self.assertFalse(applies_to.matches_file("App.SWIFT"))
        self.assertFalse(applies_to.matches_file("App.Swift"))

    def test_directory_pattern(self):
        """Test directory-scoped patterns like ffm/**/*.swift."""
        from scripts.domain.rule import AppliesTo

        applies_to = AppliesTo(file_patterns=["ffm/**/*.swift"])

        self.assertTrue(applies_to.matches_file("ffm/Source/File.swift"))
        self.assertTrue(applies_to.matches_file("ffm/libraries/Deep/Path.swift"))
        self.assertFalse(applies_to.matches_file("FlightsTab/Source/File.swift"))
        self.assertFalse(applies_to.matches_file("ffm/Source/File.m"))

    def test_exclude_patterns(self):
        """Test exclude_patterns excludes matching files."""
        from scripts.domain.rule import AppliesTo

        # Match all Swift files except those under ffm/
        applies_to = AppliesTo(
            file_patterns=["*.swift"],
            exclude_patterns=["ffm/**"],
        )

        self.assertTrue(applies_to.matches_file("FlightsTab/Source/File.swift"))
        self.assertTrue(applies_to.matches_file("App.swift"))
        self.assertFalse(applies_to.matches_file("ffm/Source/File.swift"))
        self.assertFalse(applies_to.matches_file("ffm/libraries/Deep/Path.swift"))

    def test_exclude_without_include(self):
        """Test exclude_patterns works without file_patterns (matches all except excluded)."""
        from scripts.domain.rule import AppliesTo

        # Match everything except ffm/
        applies_to = AppliesTo(exclude_patterns=["ffm/**"])

        self.assertTrue(applies_to.matches_file("FlightsTab/Source/File.swift"))
        self.assertTrue(applies_to.matches_file("App.m"))
        self.assertFalse(applies_to.matches_file("ffm/Source/File.swift"))


class TestRuleGrepPatterns(unittest.TestCase):
    """Tests for Rule grep pattern matching."""

    def test_grep_any_single_pattern_match(self):
        """Test grep.any with single matching pattern."""
        from scripts.domain.rule import GrepPatterns

        grep = GrepPatterns(any_patterns=["NSArray", "NSDictionary"])
        text = "NSArray *items;"

        self.assertTrue(grep.matches(text))

    def test_grep_any_no_patterns_match(self):
        """Test grep.any when no patterns match."""
        from scripts.domain.rule import GrepPatterns

        grep = GrepPatterns(any_patterns=["NSArray", "NSDictionary"])
        text = "NSString *name;"

        self.assertFalse(grep.matches(text))

    def test_grep_all_all_patterns_must_match(self):
        """Test grep.all requires ALL patterns to match."""
        from scripts.domain.rule import GrepPatterns

        grep = GrepPatterns(all_patterns=["import", "Foundation"])
        text_both = "@import Foundation;"
        text_one = "@import UIKit;"

        self.assertTrue(grep.matches(text_both))
        self.assertFalse(grep.matches(text_one))

    def test_grep_combined_all_and_any(self):
        """Test grep with both all and any patterns."""
        from scripts.domain.rule import GrepPatterns

        grep = GrepPatterns(
            all_patterns=["def"],
            any_patterns=["async", "await"],
        )

        # Must have 'def' AND at least one of 'async'/'await'
        self.assertTrue(grep.matches("async def foo():"))
        self.assertFalse(grep.matches("def foo():"))  # missing any pattern
        self.assertFalse(grep.matches("async function():"))  # missing all pattern

    def test_grep_empty_patterns_matches_all(self):
        """Test empty patterns matches everything."""
        from scripts.domain.rule import GrepPatterns

        grep = GrepPatterns()

        self.assertTrue(grep.matches("anything"))
        self.assertTrue(grep.matches(""))

    def test_grep_regex_patterns(self):
        """Test grep patterns support regex."""
        from scripts.domain.rule import GrepPatterns

        # Pattern with \w+ requires one or more word chars between NS and Array
        grep = GrepPatterns(any_patterns=[r"NS\w+Array"])
        self.assertTrue(grep.matches("NSMutableArray *items;"))
        self.assertFalse(grep.matches("NSArray *items;"))  # No chars between NS and Array
        self.assertFalse(grep.matches("NSString *items;"))

        # Pattern with \w* allows zero or more word chars
        grep2 = GrepPatterns(any_patterns=[r"NS\w*Array"])
        self.assertTrue(grep2.matches("NSMutableArray *items;"))
        self.assertTrue(grep2.matches("NSArray *items;"))
        self.assertFalse(grep2.matches("NSString *items;"))


class TestRuleEvaluationCombined(unittest.TestCase):
    """Integration tests for Rule.should_evaluate with file and grep filtering."""

    def test_rule_matches_file_and_grep(self):
        """Test rule matches when both file pattern and grep pattern match."""
        from scripts.domain.rule import AppliesTo, GrepPatterns, Rule

        rule = Rule(
            name="test-rule",
            file_path="test.md",
            description="Test rule",
            category="test",
            applies_to=AppliesTo(file_patterns=["*.m", "*.h"]),
            grep=GrepPatterns(any_patterns=["NSArray"]),
            content="Rule content",
        )

        # Both match
        self.assertTrue(rule.should_evaluate("src/Handler.m", "NSArray *items;"))

    def test_rule_rejects_wrong_pattern(self):
        """Test rule rejects when file pattern doesn't match."""
        from scripts.domain.rule import AppliesTo, GrepPatterns, Rule

        rule = Rule(
            name="test-rule",
            file_path="test.md",
            description="Test rule",
            category="test",
            applies_to=AppliesTo(file_patterns=["*.m", "*.h"]),
            grep=GrepPatterns(any_patterns=["NSArray"]),
            content="Rule content",
        )

        # Wrong pattern even though grep matches
        self.assertFalse(rule.should_evaluate("src/Handler.swift", "NSArray *items;"))

    def test_rule_rejects_no_grep_match(self):
        """Test rule rejects when grep pattern doesn't match."""
        from scripts.domain.rule import AppliesTo, GrepPatterns, Rule

        rule = Rule(
            name="test-rule",
            file_path="test.md",
            description="Test rule",
            category="test",
            applies_to=AppliesTo(file_patterns=["*.m", "*.h"]),
            grep=GrepPatterns(any_patterns=["NSArray"]),
            content="Rule content",
        )

        # Right pattern but no grep match
        self.assertFalse(rule.should_evaluate("src/Handler.m", "NSString *name;"))


class TestRuleScope(unittest.TestCase):
    """Tests for RuleScope enum and scope field on Rule."""

    def test_default_scope_is_localized(self):
        from scripts.domain.rule import AppliesTo, GrepPatterns, Rule, RuleScope

        rule = Rule(
            name="test-rule",
            file_path="test.md",
            description="Test",
            category="test",
            applies_to=AppliesTo(),
            grep=GrepPatterns(),
            content="Content",
        )
        self.assertEqual(rule.scope, RuleScope.LOCALIZED)

    def test_scope_can_be_set_to_global(self):
        from scripts.domain.rule import AppliesTo, GrepPatterns, Rule, RuleScope

        rule = Rule(
            name="test-rule",
            file_path="test.md",
            description="Test",
            category="test",
            applies_to=AppliesTo(),
            grep=GrepPatterns(),
            content="Content",
            scope=RuleScope.GLOBAL,
        )
        self.assertEqual(rule.scope, RuleScope.GLOBAL)

    def test_to_dict_includes_scope(self):
        from scripts.domain.rule import AppliesTo, GrepPatterns, Rule, RuleScope

        rule = Rule(
            name="test-rule",
            file_path="test.md",
            description="Test",
            category="test",
            applies_to=AppliesTo(),
            grep=GrepPatterns(),
            content="Content",
            scope=RuleScope.GLOBAL,
        )
        result = rule.to_dict()
        self.assertEqual(result["scope"], "global")

    def test_to_dict_default_scope_is_localized(self):
        from scripts.domain.rule import AppliesTo, GrepPatterns, Rule

        rule = Rule(
            name="test-rule",
            file_path="test.md",
            description="Test",
            category="test",
            applies_to=AppliesTo(),
            grep=GrepPatterns(),
            content="Content",
        )
        result = rule.to_dict()
        self.assertEqual(result["scope"], "localized")

    def test_from_dict_parses_localized_scope(self):
        from scripts.domain.rule import Rule, RuleScope

        data = {
            "name": "test",
            "file_path": "test.md",
            "description": "Test",
            "category": "test",
            "content": "Content",
            "scope": "localized",
        }
        rule = Rule.from_dict(data)
        self.assertEqual(rule.scope, RuleScope.LOCALIZED)

    def test_from_dict_parses_global_scope(self):
        from scripts.domain.rule import Rule, RuleScope

        data = {
            "name": "test",
            "file_path": "test.md",
            "description": "Test",
            "category": "test",
            "content": "Content",
            "scope": "global",
        }
        rule = Rule.from_dict(data)
        self.assertEqual(rule.scope, RuleScope.GLOBAL)

    def test_from_dict_defaults_to_localized_when_missing(self):
        from scripts.domain.rule import Rule, RuleScope

        data = {
            "name": "test",
            "file_path": "test.md",
            "description": "Test",
            "category": "test",
            "content": "Content",
        }
        rule = Rule.from_dict(data)
        self.assertEqual(rule.scope, RuleScope.LOCALIZED)

    def test_from_dict_defaults_to_localized_for_invalid_scope(self):
        from scripts.domain.rule import Rule, RuleScope

        data = {
            "name": "test",
            "file_path": "test.md",
            "description": "Test",
            "category": "test",
            "content": "Content",
            "scope": "invalid-scope",
        }
        rule = Rule.from_dict(data)
        self.assertEqual(rule.scope, RuleScope.LOCALIZED)

    def test_from_file_parses_scope_from_frontmatter(self):
        import tempfile
        from pathlib import Path

        from scripts.domain.rule import Rule, RuleScope

        content = """---
description: Test rule
category: test
scope: global
---
Rule content here.
"""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
            f.write(content)
            f.flush()
            rule = Rule.from_file(Path(f.name))

        self.assertEqual(rule.scope, RuleScope.GLOBAL)

    def test_from_file_defaults_to_localized_when_scope_missing(self):
        import tempfile
        from pathlib import Path

        from scripts.domain.rule import Rule, RuleScope

        content = """---
description: Test rule
category: test
---
Rule content here.
"""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
            f.write(content)
            f.flush()
            rule = Rule.from_file(Path(f.name))

        self.assertEqual(rule.scope, RuleScope.LOCALIZED)

    def test_round_trip_serialization(self):
        from scripts.domain.rule import AppliesTo, GrepPatterns, Rule, RuleScope

        original = Rule(
            name="test-rule",
            file_path="test.md",
            description="Test",
            category="test",
            applies_to=AppliesTo(file_patterns=["*.py"]),
            grep=GrepPatterns(any_patterns=["pattern"]),
            content="Content",
            scope=RuleScope.GLOBAL,
        )
        restored = Rule.from_dict(original.to_dict())
        self.assertEqual(restored.scope, RuleScope.GLOBAL)
        self.assertEqual(restored.name, original.name)


if __name__ == "__main__":
    unittest.main()
