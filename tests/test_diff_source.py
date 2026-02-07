"""Tests for DiffSource enum.

Tests cover:
- Enum values and string representations
- Case-insensitive parsing from string
- Invalid value handling
"""

import unittest

from prradar.domain.diff_source import DiffSource


class TestDiffSource(unittest.TestCase):
    """Tests for DiffSource enum."""

    def test_enum_has_github_api_value(self):
        """Test that GITHUB_API enum value exists."""
        self.assertEqual(DiffSource.GITHUB_API.value, "github")

    def test_enum_has_local_git_value(self):
        """Test that LOCAL_GIT enum value exists."""
        self.assertEqual(DiffSource.LOCAL_GIT.value, "local")

    def test_from_string_parses_github(self):
        """Test that from_string correctly parses 'github'."""
        result = DiffSource.from_string("github")
        self.assertEqual(result, DiffSource.GITHUB_API)

    def test_from_string_parses_local(self):
        """Test that from_string correctly parses 'local'."""
        result = DiffSource.from_string("local")
        self.assertEqual(result, DiffSource.LOCAL_GIT)

    def test_from_string_is_case_insensitive(self):
        """Test that from_string handles uppercase input."""
        self.assertEqual(DiffSource.from_string("GITHUB"), DiffSource.GITHUB_API)
        self.assertEqual(DiffSource.from_string("LOCAL"), DiffSource.LOCAL_GIT)
        self.assertEqual(DiffSource.from_string("GiThUb"), DiffSource.GITHUB_API)

    def test_from_string_raises_on_invalid_value(self):
        """Test that from_string raises ValueError for invalid input."""
        with self.assertRaises(ValueError) as ctx:
            DiffSource.from_string("invalid")

        self.assertIn("Invalid diff source", str(ctx.exception))
        self.assertIn("invalid", str(ctx.exception))

    def test_from_string_raises_on_empty_string(self):
        """Test that from_string raises ValueError for empty string."""
        with self.assertRaises(ValueError):
            DiffSource.from_string("")

    def test_string_representation(self):
        """Test that enum values have correct string representation."""
        self.assertEqual(str(DiffSource.GITHUB_API), "DiffSource.GITHUB_API")
        self.assertEqual(str(DiffSource.LOCAL_GIT), "DiffSource.LOCAL_GIT")


if __name__ == "__main__":
    unittest.main()
