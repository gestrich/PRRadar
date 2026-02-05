"""Domain model for evaluation tasks.

An evaluation task bundles a rule with a code segment, containing everything
needed for Claude to evaluate whether the code violates the rule.

The `agent rules` command creates these tasks. The `agent evaluate` command
consumes them.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass

from scripts.domain.rule import Rule


# ============================================================
# Domain Models
# ============================================================


@dataclass
class CodeSegment:
    """A segment of code from a diff to be evaluated.

    Contains the diff hunk content along with location metadata.
    """

    file_path: str
    hunk_index: int
    start_line: int
    end_line: int
    content: str

    # --------------------------------------------------------
    # Factory Methods
    # --------------------------------------------------------

    @classmethod
    def from_dict(cls, data: dict) -> CodeSegment:
        """Parse code segment from dictionary.

        Args:
            data: Dictionary with segment data

        Returns:
            Typed CodeSegment instance
        """
        return cls(
            file_path=data.get("file_path", ""),
            hunk_index=data.get("hunk_index", 0),
            start_line=data.get("start_line", 0),
            end_line=data.get("end_line", 0),
            content=data.get("content", ""),
        )

    # --------------------------------------------------------
    # Serialization
    # --------------------------------------------------------

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "file_path": self.file_path,
            "hunk_index": self.hunk_index,
            "start_line": self.start_line,
            "end_line": self.end_line,
            "content": self.content,
        }

    # --------------------------------------------------------
    # Public API
    # --------------------------------------------------------

    def content_hash(self) -> str:
        """Generate a short hash of the segment content for unique IDs."""
        return hashlib.sha256(self.content.encode()).hexdigest()[:8]

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
        lines = self.content.split("\n")

        # Find where the diff body starts (after headers, at @@ line)
        body_start = 0
        for i, line in enumerate(lines):
            if line.startswith("@@"):
                body_start = i
                break

        body_lines = lines[body_start:]

        if line_number is None:
            # No specific line - return first few lines of diff body
            return "\n".join(body_lines[: 1 + (context_lines * 2)])

        # Find the line matching our target line number
        # Format is "1234: +code" or "   -: -code"
        target_idx = None
        for i, line in enumerate(body_lines):
            # Skip the @@ header
            if line.startswith("@@"):
                continue
            # Check if this line has our target line number
            # Format: "1234: +code" where 1234 is right-aligned in 4 chars
            if ": " in line:
                line_prefix = line.split(": ")[0].strip()
                if line_prefix.isdigit() and int(line_prefix) == line_number:
                    target_idx = i
                    break

        if target_idx is None:
            # Line not found - return first few lines
            return "\n".join(body_lines[: 1 + (context_lines * 2)])

        # Extract context around target
        start = max(0, target_idx - context_lines)
        end = min(len(body_lines), target_idx + context_lines + 1)

        return "\n".join(body_lines[start:end])


@dataclass
class EvaluationTask:
    """A self-contained evaluation task: rule + code segment.

    Each task contains everything needed for Claude to evaluate whether
    the code violates the rule—no additional file reads required.
    """

    task_id: str
    rule: Rule
    segment: CodeSegment

    # --------------------------------------------------------
    # Factory Methods
    # --------------------------------------------------------

    @classmethod
    def create(cls, rule: Rule, segment: CodeSegment) -> EvaluationTask:
        """Create an evaluation task with auto-generated ID.

        Args:
            rule: The rule to evaluate against
            segment: The code segment to evaluate

        Returns:
            EvaluationTask with generated task_id
        """
        task_id = f"{rule.name}-{segment.content_hash()}"
        return cls(task_id=task_id, rule=rule, segment=segment)

    @classmethod
    def from_dict(cls, data: dict) -> EvaluationTask:
        """Parse evaluation task from dictionary.

        Args:
            data: Dictionary with task data

        Returns:
            Typed EvaluationTask instance
        """
        return cls(
            task_id=data.get("task_id", ""),
            rule=Rule.from_dict(data.get("rule", {})),
            segment=CodeSegment.from_dict(data.get("segment", {})),
        )

    # --------------------------------------------------------
    # Serialization
    # --------------------------------------------------------

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization.

        The output is self-contained—includes full rule content and
        segment text, ready for Claude evaluation.
        """
        rule_dict = {
            "name": self.rule.name,
            "description": self.rule.description,
            "category": self.rule.category,
            "model": self.rule.model,
            "content": self.rule.content,
        }
        if self.rule.documentation_link:
            rule_dict["documentation_link"] = self.rule.documentation_link

        return {
            "task_id": self.task_id,
            "rule": rule_dict,
            "segment": self.segment.to_dict(),
        }

    # --------------------------------------------------------
    # Public API
    # --------------------------------------------------------

    def suggested_filename(self) -> str:
        """Generate a filename for storing this task."""
        return f"{self.task_id}.json"

    @property
    def model(self) -> str | None:
        """Get the Claude model to use for evaluation (from rule)."""
        return self.rule.model
