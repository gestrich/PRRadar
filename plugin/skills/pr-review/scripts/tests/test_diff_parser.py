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

from scripts.domain.diff import GitDiff, Hunk
from scripts.infrastructure.diff_parser import (
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


if __name__ == "__main__":
    unittest.main()
