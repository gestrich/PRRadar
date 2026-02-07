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

    def test_enum_has_github_value(self):
        """Test that GITHUB enum value exists."""
        self.assertEqual(DiffSource.GITHUB.value, "github")

    def test_enum_has_local_value(self):
        """Test that LOCAL enum value exists."""
        self.assertEqual(DiffSource.LOCAL.value, "local")

    def test_from_string_parses_github(self):
        """Test that from_string correctly parses 'github'."""
        result = DiffSource.from_string("github")
        self.assertEqual(result, DiffSource.GITHUB)

    def test_from_string_parses_local(self):
        """Test that from_string correctly parses 'local'."""
        result = DiffSource.from_string("local")
        self.assertEqual(result, DiffSource.LOCAL)

    def test_from_string_is_case_insensitive(self):
        """Test that from_string handles uppercase input."""
        self.assertEqual(DiffSource.from_string("GITHUB"), DiffSource.GITHUB)
        self.assertEqual(DiffSource.from_string("LOCAL"), DiffSource.LOCAL)
        self.assertEqual(DiffSource.from_string("GiThUb"), DiffSource.GITHUB)

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
        self.assertEqual(str(DiffSource.GITHUB), "DiffSource.GITHUB")
        self.assertEqual(str(DiffSource.LOCAL), "DiffSource.LOCAL")


if __name__ == "__main__":
    unittest.main()
