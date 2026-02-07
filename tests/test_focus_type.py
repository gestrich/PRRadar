"""Tests for FocusType enum and FocusArea focus_type field.

Tests cover:
- FocusType enum values
- FocusArea default focus_type
- Serialization round-trip (to_dict / from_dict)
- Fallback for missing/invalid focus_type in from_dict
- Focus generator tags focus areas as METHOD
"""

import unittest

from prradar.domain.focus_area import FocusArea, FocusType


class TestFocusType(unittest.TestCase):
    """Tests for FocusType enum."""

    def test_file_value(self):
        self.assertEqual(FocusType.FILE.value, "file")

    def test_method_value(self):
        self.assertEqual(FocusType.METHOD.value, "method")

    def test_construct_from_string(self):
        self.assertEqual(FocusType("file"), FocusType.FILE)
        self.assertEqual(FocusType("method"), FocusType.METHOD)

    def test_invalid_value_raises(self):
        with self.assertRaises(ValueError):
            FocusType("invalid")


class TestFocusAreaFocusType(unittest.TestCase):
    """Tests for FocusArea.focus_type field."""

    def _make_focus_area(self, **overrides) -> FocusArea:
        defaults = {
            "focus_id": "src-test.py-0",
            "file_path": "src/test.py",
            "start_line": 10,
            "end_line": 20,
            "description": "test_method()",
            "hunk_index": 0,
            "hunk_content": "+code",
        }
        defaults.update(overrides)
        return FocusArea(**defaults)

    def test_default_focus_type_is_file(self):
        fa = self._make_focus_area()
        self.assertEqual(fa.focus_type, FocusType.FILE)

    def test_explicit_method_type(self):
        fa = self._make_focus_area(focus_type=FocusType.METHOD)
        self.assertEqual(fa.focus_type, FocusType.METHOD)

    def test_explicit_file_type(self):
        fa = self._make_focus_area(focus_type=FocusType.FILE)
        self.assertEqual(fa.focus_type, FocusType.FILE)

    def test_to_dict_includes_focus_type(self):
        fa = self._make_focus_area(focus_type=FocusType.METHOD)
        data = fa.to_dict()
        self.assertEqual(data["focus_type"], "method")

    def test_to_dict_default_focus_type(self):
        fa = self._make_focus_area()
        data = fa.to_dict()
        self.assertEqual(data["focus_type"], "file")

    def test_from_dict_parses_method(self):
        data = {
            "focus_id": "src-test.py-0",
            "file_path": "src/test.py",
            "start_line": 10,
            "end_line": 20,
            "description": "test_method()",
            "hunk_index": 0,
            "hunk_content": "+code",
            "focus_type": "method",
        }
        fa = FocusArea.from_dict(data)
        self.assertEqual(fa.focus_type, FocusType.METHOD)

    def test_from_dict_parses_file(self):
        data = {
            "focus_id": "src-test.py-0",
            "file_path": "src/test.py",
            "start_line": 10,
            "end_line": 20,
            "description": "test_method()",
            "hunk_index": 0,
            "hunk_content": "+code",
            "focus_type": "file",
        }
        fa = FocusArea.from_dict(data)
        self.assertEqual(fa.focus_type, FocusType.FILE)

    def test_from_dict_missing_focus_type_defaults_to_file(self):
        data = {
            "focus_id": "src-test.py-0",
            "file_path": "src/test.py",
            "start_line": 10,
            "end_line": 20,
            "description": "test_method()",
            "hunk_index": 0,
            "hunk_content": "+code",
        }
        fa = FocusArea.from_dict(data)
        self.assertEqual(fa.focus_type, FocusType.FILE)

    def test_from_dict_invalid_focus_type_defaults_to_file(self):
        data = {
            "focus_id": "src-test.py-0",
            "file_path": "src/test.py",
            "start_line": 10,
            "end_line": 20,
            "description": "test_method()",
            "hunk_index": 0,
            "hunk_content": "+code",
            "focus_type": "invalid",
        }
        fa = FocusArea.from_dict(data)
        self.assertEqual(fa.focus_type, FocusType.FILE)

    def test_serialization_round_trip_method(self):
        original = self._make_focus_area(focus_type=FocusType.METHOD)
        data = original.to_dict()
        restored = FocusArea.from_dict(data)
        self.assertEqual(restored.focus_type, FocusType.METHOD)
        self.assertEqual(restored.focus_id, original.focus_id)
        self.assertEqual(restored.file_path, original.file_path)

    def test_serialization_round_trip_file(self):
        original = self._make_focus_area(focus_type=FocusType.FILE)
        data = original.to_dict()
        restored = FocusArea.from_dict(data)
        self.assertEqual(restored.focus_type, FocusType.FILE)


class TestFocusGeneratorTagsMethod(unittest.TestCase):
    """Tests that FocusGeneratorService tags generated focus areas as METHOD."""

    def test_fallback_focus_area_is_method_type(self):
        from prradar.domain.diff import Hunk
        from prradar.services.focus_generator import FocusGeneratorService

        hunk = Hunk(
            file_path="src/handler.py",
            content="@@ -10,5 +10,8 @@\n context\n+new line",
            new_start=10,
            new_length=8,
            old_start=10,
            old_length=5,
        )

        focus_areas = FocusGeneratorService._fallback_focus_area(
            hunk, 0, hunk.get_annotated_content()
        )

        self.assertEqual(len(focus_areas), 1)
        self.assertEqual(focus_areas[0].focus_type, FocusType.METHOD)


if __name__ == "__main__":
    unittest.main()
