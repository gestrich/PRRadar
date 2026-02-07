"""Tests for FocusType enum and FocusArea focus_type field.

Tests cover:
- FocusType enum values
- FocusArea default focus_type
- Serialization round-trip (to_dict / from_dict)
- Fallback for missing/invalid focus_type in from_dict
- Focus generator tags focus areas as METHOD
- File focus area generation (single hunk, multi-hunk, mixed types)
"""

import asyncio
import unittest
from unittest.mock import AsyncMock, patch

from prradar.domain.diff import Hunk
from prradar.domain.focus_area import FocusArea, FocusType
from prradar.services.focus_generator import FocusGeneratorService


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


class TestFileFocusAreaGeneration(unittest.TestCase):
    """Tests for FocusGeneratorService.generate_file_focus_areas()."""

    def _make_hunk(self, file_path: str, new_start: int, new_length: int, content: str | None = None) -> Hunk:
        if content is None:
            content = f"@@ -{new_start},3 +{new_start},{new_length} @@\n context\n+new line"
        return Hunk(
            file_path=file_path,
            content=content,
            new_start=new_start,
            new_length=new_length,
            old_start=new_start,
            old_length=3,
        )

    def test_single_hunk_single_file(self):
        service = FocusGeneratorService()
        hunks = [self._make_hunk("src/app.py", 10, 8)]

        result = service.generate_file_focus_areas(hunks)

        self.assertEqual(len(result), 1)
        fa = result[0]
        self.assertEqual(fa.focus_type, FocusType.FILE)
        self.assertEqual(fa.file_path, "src/app.py")
        self.assertEqual(fa.description, "src/app.py")
        self.assertEqual(fa.focus_id, "src-app.py")
        self.assertEqual(fa.start_line, 10)
        self.assertEqual(fa.end_line, 17)  # 10 + 8 - 1

    def test_multi_hunk_single_file(self):
        service = FocusGeneratorService()
        hunks = [
            self._make_hunk("src/app.py", 10, 5),
            self._make_hunk("src/app.py", 50, 10),
        ]

        result = service.generate_file_focus_areas(hunks)

        self.assertEqual(len(result), 1)
        fa = result[0]
        self.assertEqual(fa.file_path, "src/app.py")
        self.assertEqual(fa.start_line, 10)
        self.assertEqual(fa.end_line, 59)  # 50 + 10 - 1
        self.assertIn("\n\n", fa.hunk_content)  # Hunks joined with double newline

    def test_multiple_files(self):
        service = FocusGeneratorService()
        hunks = [
            self._make_hunk("src/app.py", 10, 5),
            self._make_hunk("src/utils.py", 1, 3),
            self._make_hunk("src/app.py", 50, 10),
        ]

        result = service.generate_file_focus_areas(hunks)

        self.assertEqual(len(result), 2)
        paths = {fa.file_path for fa in result}
        self.assertEqual(paths, {"src/app.py", "src/utils.py"})

    def test_focus_id_is_sanitized_path(self):
        service = FocusGeneratorService()
        hunks = [self._make_hunk("src/auth/handler.py", 1, 5)]

        result = service.generate_file_focus_areas(hunks)

        self.assertEqual(result[0].focus_id, "src-auth-handler.py")

    def test_hunk_index_is_first_hunk_for_file(self):
        service = FocusGeneratorService()
        hunks = [
            self._make_hunk("src/a.py", 1, 3),
            self._make_hunk("src/b.py", 1, 3),
            self._make_hunk("src/a.py", 50, 5),
        ]

        result = service.generate_file_focus_areas(hunks)

        a_fa = next(fa for fa in result if fa.file_path == "src/a.py")
        b_fa = next(fa for fa in result if fa.file_path == "src/b.py")
        self.assertEqual(a_fa.hunk_index, 0)
        self.assertEqual(b_fa.hunk_index, 1)

    def test_empty_hunks(self):
        service = FocusGeneratorService()
        result = service.generate_file_focus_areas([])
        self.assertEqual(result, [])

    def test_hunk_content_is_annotated(self):
        service = FocusGeneratorService()
        hunks = [self._make_hunk("src/app.py", 10, 5)]

        result = service.generate_file_focus_areas(hunks)

        # Annotated content should contain line numbers
        self.assertIn("@@", result[0].hunk_content)


class TestGenerateAllFocusAreasWithTypes(unittest.TestCase):
    """Tests for generate_all_focus_areas() with requested_types parameter."""

    def _make_hunk(self, file_path: str = "src/app.py", new_start: int = 10, new_length: int = 5) -> Hunk:
        return Hunk(
            file_path=file_path,
            content=f"@@ -{new_start},3 +{new_start},{new_length} @@\n context\n+new line",
            new_start=new_start,
            new_length=new_length,
            old_start=new_start,
            old_length=3,
        )

    def test_default_generates_method_only(self):
        """Without requested_types, backward-compatible METHOD-only generation."""
        service = FocusGeneratorService()
        hunks = [self._make_hunk()]

        with patch.object(service, "generate_focus_areas_for_hunk", new_callable=AsyncMock) as mock_method:
            mock_method.return_value = (
                [FocusArea(
                    focus_id="test-0-method",
                    file_path="src/app.py",
                    start_line=10,
                    end_line=14,
                    description="method()",
                    hunk_index=0,
                    hunk_content="+code",
                    focus_type=FocusType.METHOD,
                )],
                0.001,
            )

            result = asyncio.run(service.generate_all_focus_areas(hunks, pr_number=42))

        self.assertEqual(len(result.focus_areas), 1)
        self.assertEqual(result.focus_areas[0].focus_type, FocusType.METHOD)
        mock_method.assert_called_once()

    def test_file_only_skips_method_generation(self):
        service = FocusGeneratorService()
        hunks = [self._make_hunk()]

        with patch.object(service, "generate_focus_areas_for_hunk", new_callable=AsyncMock) as mock_method:
            result = asyncio.run(
                service.generate_all_focus_areas(hunks, pr_number=42, requested_types={FocusType.FILE})
            )

        mock_method.assert_not_called()
        self.assertEqual(len(result.focus_areas), 1)
        self.assertEqual(result.focus_areas[0].focus_type, FocusType.FILE)
        self.assertEqual(result.generation_cost_usd, 0.0)

    def test_both_types_generates_mixed(self):
        service = FocusGeneratorService()
        hunks = [self._make_hunk()]

        with patch.object(service, "generate_focus_areas_for_hunk", new_callable=AsyncMock) as mock_method:
            mock_method.return_value = (
                [FocusArea(
                    focus_id="test-0-method",
                    file_path="src/app.py",
                    start_line=10,
                    end_line=14,
                    description="method()",
                    hunk_index=0,
                    hunk_content="+code",
                    focus_type=FocusType.METHOD,
                )],
                0.002,
            )

            result = asyncio.run(
                service.generate_all_focus_areas(
                    hunks, pr_number=42, requested_types={FocusType.METHOD, FocusType.FILE}
                )
            )

        self.assertEqual(len(result.focus_areas), 2)
        types = {fa.focus_type for fa in result.focus_areas}
        self.assertEqual(types, {FocusType.METHOD, FocusType.FILE})
        self.assertAlmostEqual(result.generation_cost_usd, 0.002)

    def test_file_generation_cost_is_zero(self):
        service = FocusGeneratorService()
        hunks = [self._make_hunk()]

        result = asyncio.run(
            service.generate_all_focus_areas(hunks, pr_number=42, requested_types={FocusType.FILE})
        )

        self.assertEqual(result.generation_cost_usd, 0.0)

    def test_empty_hunks_with_file_type(self):
        service = FocusGeneratorService()

        result = asyncio.run(
            service.generate_all_focus_areas([], pr_number=42, requested_types={FocusType.FILE})
        )

        self.assertEqual(len(result.focus_areas), 0)
        self.assertEqual(result.total_hunks_processed, 0)


if __name__ == "__main__":
    unittest.main()
