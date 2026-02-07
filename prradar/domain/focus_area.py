"""Domain model for focus areas - reviewable units of code within hunks."""

from __future__ import annotations

from dataclasses import dataclass
from typing import ClassVar


@dataclass
class FocusArea:
    """A reviewable unit of code identified within a hunk.

    Typically represents a single method/function that was added,
    modified, or removed. References the hunk it came from.

    This is a first-class domain concept that sits between hunks
    (infrastructure) and tasks (application).
    """

    focus_id: str
    file_path: str
    start_line: int
    end_line: int
    description: str

    hunk_index: int
    hunk_content: str

    TYPE: ClassVar[str] = "focus_area"

    # --------------------------------------------------------
    # Factory Methods
    # --------------------------------------------------------

    @classmethod
    def from_dict(cls, data: dict) -> FocusArea:
        """Parse focus area from dictionary.

        Args:
            data: Dictionary with focus area data

        Returns:
            Typed FocusArea instance
        """
        return cls(
            focus_id=data.get("focus_id", ""),
            file_path=data.get("file_path", ""),
            start_line=data.get("start_line", 0),
            end_line=data.get("end_line", 0),
            description=data.get("description", ""),
            hunk_index=data.get("hunk_index", 0),
            hunk_content=data.get("hunk_content", ""),
        )

    # --------------------------------------------------------
    # Serialization
    # --------------------------------------------------------

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "focus_id": self.focus_id,
            "file_path": self.file_path,
            "start_line": self.start_line,
            "end_line": self.end_line,
            "description": self.description,
            "hunk_index": self.hunk_index,
            "hunk_content": self.hunk_content,
        }

    # --------------------------------------------------------
    # Public API
    # --------------------------------------------------------

    def get_focused_content(self) -> str:
        """Extract only the lines within focus bounds from hunk content.

        Returns:
            Annotated diff lines (with +/- markers and line numbers)
            for just the focused region.
        """
        lines = self.hunk_content.split("\n")

        # Find where diff body starts (after @@ line)
        body_start = 0
        for i, line in enumerate(lines):
            if line.startswith("@@"):
                body_start = i
                break

        # Extract lines within [start_line, end_line] range
        focused_lines = [lines[body_start]]  # Include @@ header
        for line in lines[body_start + 1:]:
            if ": " not in line:
                continue
            line_num_str = line.split(": ")[0].strip()
            if line_num_str.isdigit():
                line_num = int(line_num_str)
                if self.start_line <= line_num <= self.end_line:
                    focused_lines.append(line)

        return "\n".join(focused_lines)

    def get_context_around_line(
        self,
        line_number: int | None,
        context_lines: int = 3,
    ) -> str:
        """Extract diff context centered on a specific line number.

        Returns annotated diff lines (with +/- markers and line numbers)
        centered on the target line.

        Args:
            line_number: Target line number in the new file. If None, returns
                         the first few lines of the diff body.
            context_lines: Number of lines to show before and after target

        Returns:
            Formatted diff excerpt with line numbers and +/- markers
        """
        lines = self.hunk_content.split("\n")

        # Find where the diff body starts (after headers, at @@ line)
        body_start = 0
        for i, line in enumerate(lines):
            if line.startswith("@@"):
                body_start = i
                break

        body_lines = lines[body_start:]

        if line_number is None:
            return "\n".join(body_lines[: 1 + (context_lines * 2)])

        # Find the line matching our target line number
        target_idx = None
        for i, line in enumerate(body_lines):
            if line.startswith("@@"):
                continue
            if ": " in line:
                line_prefix = line.split(": ")[0].strip()
                if line_prefix.isdigit() and int(line_prefix) == line_number:
                    target_idx = i
                    break

        if target_idx is None:
            return "\n".join(body_lines[: 1 + (context_lines * 2)])

        start = max(0, target_idx - context_lines)
        end = min(len(body_lines), target_idx + context_lines + 1)

        return "\n".join(body_lines[start:end])

    def content_hash(self) -> str:
        """Generate a short hash of the hunk content for grouping."""
        import hashlib
        return hashlib.sha256(self.hunk_content.encode()).hexdigest()[:8]
