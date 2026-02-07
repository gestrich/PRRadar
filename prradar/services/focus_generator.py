"""Focus area generation service.

Generates focus areas (reviewable units of code) from diff hunks using Claude.
Each identified method/function becomes a FocusArea that references its source hunk.

Following Martin Fowler's Service Layer pattern with constructor-based
dependency injection.
"""

from __future__ import annotations

import json
from collections import defaultdict
from dataclasses import dataclass

from claude_agent_sdk import ClaudeAgentOptions, ResultMessage, query

from prradar.domain.diff import Hunk
from prradar.domain.focus_area import FocusArea, FocusType


# ============================================================
# Constants
# ============================================================

DEFAULT_MODEL = "claude-haiku-4-5-20251001"

FOCUS_GENERATION_PROMPT = """Analyze this diff hunk and identify all methods/functions that were added, modified, or removed.

File: {file_path}
Hunk index: {hunk_index}

```diff
{hunk_content}
```

For each method/function you identify, provide:
1. **method_name**: The function/method name and its signature (e.g., "login(username, password)")
2. **start_line**: First line number in the new file where the method starts
3. **end_line**: Last line number in the new file where the method ends

Rules:
- Only include methods/functions that have added (+) or removed (-) lines
- If the hunk contains changes outside of any method (e.g., module-level code, imports), create a single entry with method_name describing the change (e.g., "module-level imports")
- Use the line numbers from the annotated diff (the numbers before the colon)
- If no distinct methods are found, return a single entry covering the entire hunk with a descriptive name
"""

FOCUS_GENERATION_SCHEMA = {
    "type": "object",
    "properties": {
        "methods": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "method_name": {
                        "type": "string",
                        "description": "Method/function name and signature",
                    },
                    "start_line": {
                        "type": "integer",
                        "description": "First line number in new file",
                    },
                    "end_line": {
                        "type": "integer",
                        "description": "Last line number in new file",
                    },
                },
                "required": ["method_name", "start_line", "end_line"],
            },
        },
    },
    "required": ["methods"],
}


# ============================================================
# Result Model
# ============================================================


@dataclass
class FocusGenerationResult:
    """Result of focus area generation for a PR."""

    pr_number: int
    focus_areas: list[FocusArea]
    total_hunks_processed: int
    generation_cost_usd: float = 0.0

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "pr_number": self.pr_number,
            "focus_areas": [fa.to_dict() for fa in self.focus_areas],
            "total_hunks_processed": self.total_hunks_processed,
            "generation_cost_usd": self.generation_cost_usd,
        }


# ============================================================
# Service
# ============================================================


class FocusGeneratorService:
    """Generates focus areas (reviewable units) from diff hunks.

    Uses Claude to identify method-level changes within hunks.
    Each identified method becomes a FocusArea that references
    its source hunk.
    """

    def __init__(self, model: str = DEFAULT_MODEL):
        self.model = model

    async def generate_focus_areas_for_hunk(
        self, hunk: Hunk, hunk_index: int
    ) -> tuple[list[FocusArea], float]:
        """Generate focus areas for a single hunk.

        Args:
            hunk: The hunk to analyze
            hunk_index: Index of this hunk in the diff

        Returns:
            Tuple of (focus areas found in this hunk, cost in USD)
        """
        annotated_content = hunk.get_annotated_content()

        prompt = FOCUS_GENERATION_PROMPT.format(
            file_path=hunk.file_path,
            hunk_index=hunk_index,
            hunk_content=annotated_content,
        )

        options = ClaudeAgentOptions(
            model=self.model,
            output_format={
                "type": "json_schema",
                "schema": FOCUS_GENERATION_SCHEMA,
            },
        )

        structured_output: dict | None = None
        cost_usd: float = 0.0

        async for message in query(prompt=prompt, options=options):
            if isinstance(message, ResultMessage):
                if message.structured_output:
                    structured_output = message.structured_output
                if message.total_cost_usd:
                    cost_usd = message.total_cost_usd

        if not structured_output or "methods" not in structured_output:
            return self._fallback_focus_area(hunk, hunk_index, annotated_content), cost_usd

        methods = structured_output["methods"]
        if not methods:
            return self._fallback_focus_area(hunk, hunk_index, annotated_content), cost_usd

        focus_areas: list[FocusArea] = []
        for method in methods:
            method_name = method.get("method_name", f"hunk {hunk_index}")
            start_line = method.get("start_line", hunk.new_start)
            end_line = method.get("end_line", hunk.new_start + hunk.new_length - 1)

            safe_path = hunk.file_path.replace("/", "-").replace("\\", "-")
            safe_method = self._sanitize_for_id(method_name)
            focus_id = f"{safe_path}-{hunk_index}-{safe_method}"

            focus_areas.append(
                FocusArea(
                    focus_id=focus_id,
                    file_path=hunk.file_path,
                    start_line=start_line,
                    end_line=end_line,
                    description=method_name,
                    hunk_index=hunk_index,
                    hunk_content=annotated_content,
                    focus_type=FocusType.METHOD,
                )
            )

        return focus_areas, cost_usd

    def generate_file_focus_areas(self, hunks: list[Hunk]) -> list[FocusArea]:
        """Generate file-level focus areas by grouping hunks per file.

        No AI call needed — aggregates all hunks for each file into a single
        FocusArea with FocusType.FILE.

        Args:
            hunks: List of hunks from parsed diff

        Returns:
            List of file-level focus areas (one per unique file)
        """
        hunks_by_file: dict[str, list[tuple[int, Hunk]]] = defaultdict(list)
        for i, hunk in enumerate(hunks):
            hunks_by_file[hunk.file_path].append((i, hunk))

        focus_areas: list[FocusArea] = []
        for file_path, indexed_hunks in hunks_by_file.items():
            all_annotated = []
            min_start = None
            max_end = None

            for hunk_index, hunk in indexed_hunks:
                annotated = hunk.get_annotated_content()
                all_annotated.append(annotated)

                hunk_end = hunk.new_start + hunk.new_length - 1
                if min_start is None or hunk.new_start < min_start:
                    min_start = hunk.new_start
                if max_end is None or hunk_end > max_end:
                    max_end = hunk_end

            safe_path = file_path.replace("/", "-").replace("\\", "-")

            focus_areas.append(
                FocusArea(
                    focus_id=safe_path,
                    file_path=file_path,
                    start_line=min_start or 0,
                    end_line=max_end or 0,
                    description=file_path,
                    hunk_index=indexed_hunks[0][0],
                    hunk_content="\n\n".join(all_annotated),
                    focus_type=FocusType.FILE,
                )
            )

        return focus_areas

    async def generate_all_focus_areas(
        self,
        hunks: list[Hunk],
        pr_number: int,
        requested_types: set[FocusType] | None = None,
    ) -> FocusGenerationResult:
        """Generate focus areas for all hunks in a diff.

        Args:
            hunks: List of hunks from parsed diff
            pr_number: PR number being analyzed
            requested_types: Set of FocusType values to generate. If None,
                generates METHOD focus areas only (backward compatible).

        Returns:
            FocusGenerationResult with all focus areas
        """
        if requested_types is None:
            requested_types = {FocusType.METHOD}

        all_focus_areas: list[FocusArea] = []
        total_cost = 0.0

        if FocusType.METHOD in requested_types:
            for i, hunk in enumerate(hunks):
                focus_areas, cost = await self.generate_focus_areas_for_hunk(hunk, i)
                all_focus_areas.extend(focus_areas)
                total_cost += cost

        if FocusType.FILE in requested_types:
            file_focus_areas = self.generate_file_focus_areas(hunks)
            all_focus_areas.extend(file_focus_areas)

        return FocusGenerationResult(
            pr_number=pr_number,
            focus_areas=all_focus_areas,
            total_hunks_processed=len(hunks),
            generation_cost_usd=total_cost,
        )

    @staticmethod
    def _fallback_focus_area(
        hunk: Hunk, hunk_index: int, annotated_content: str
    ) -> list[FocusArea]:
        """Create a single focus area covering the entire hunk as fallback."""
        safe_path = hunk.file_path.replace("/", "-").replace("\\", "-")
        return [
            FocusArea(
                focus_id=f"{safe_path}-{hunk_index}",
                file_path=hunk.file_path,
                start_line=hunk.new_start,
                end_line=hunk.new_start + hunk.new_length - 1,
                description=f"hunk {hunk_index}",
                hunk_index=hunk_index,
                hunk_content=annotated_content,
                focus_type=FocusType.METHOD,
            )
        ]

    @staticmethod
    def _sanitize_for_id(name: str) -> str:
        """Sanitize a method name for use in a focus_id."""
        sanitized = name.split("(")[0].strip()
        sanitized = sanitized.replace(" ", "-").replace("/", "-").replace("\\", "-")
        sanitized = "".join(c for c in sanitized if c.isalnum() or c in "-_.")
        return sanitized[:50] if sanitized else "unknown"
