"""Domain models for git diff parsing.

Parse-once pattern: Raw diff content is parsed into type-safe models at the boundary.
Provides Hunk and GitDiff models with factory methods for deterministic parsing.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from enum import Enum


# ============================================================
# Domain Models
# ============================================================


class DiffLineType(Enum):
    """Type of line in a diff."""

    ADDED = "added"
    REMOVED = "removed"
    CONTEXT = "context"
    HEADER = "header"


@dataclass
class DiffLine:
    """A single line from a diff with metadata.

    Attributes:
        content: The line content (without the +/- prefix)
        raw_line: The original line including +/- prefix
        line_type: Whether this is an added, removed, or context line
        new_line_number: Line number in the new file (None for removed lines)
        old_line_number: Line number in the old file (None for added lines)
    """

    content: str
    raw_line: str
    line_type: DiffLineType
    new_line_number: int | None = None
    old_line_number: int | None = None

    @property
    def is_changed(self) -> bool:
        """Check if this line represents a change (added or removed)."""
        return self.line_type in (DiffLineType.ADDED, DiffLineType.REMOVED)


@dataclass
class Hunk:
    """Represents a single hunk from a git diff.

    A hunk is a contiguous section of changes within a file, identified by
    its @@ header containing line number information.
    """

    file_path: str
    content: str
    raw_header: list[str] = field(default_factory=list)
    old_start: int = 0
    old_length: int = 0
    new_start: int = 0
    new_length: int = 0

    # --------------------------------------------------------
    # Factory Methods
    # --------------------------------------------------------

    @classmethod
    def from_hunk_lines(
        cls,
        file_header: list[str],
        hunk_lines: list[str],
        file_path: str,
    ) -> Hunk | None:
        """Parse a hunk from its component lines.

        Args:
            file_header: The diff header lines (diff --git, index, ---, +++)
            hunk_lines: Lines starting from @@ through the content
            file_path: The target file path (b/ path from diff)

        Returns:
            Parsed Hunk instance, or None if file_path is empty
        """
        if not file_path:
            return None

        old_start = old_length = new_start = new_length = 0

        for line in hunk_lines:
            if line.startswith("@@"):
                match = re.match(
                    r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@",
                    line,
                )
                if match:
                    old_start = int(match.group(1))
                    old_length = int(match.group(2)) if match.group(2) else 1
                    new_start = int(match.group(3))
                    new_length = int(match.group(4)) if match.group(4) else 1
                break

        return cls(
            file_path=file_path,
            content="\n".join(file_header + hunk_lines),
            raw_header=file_header,
            old_start=old_start,
            old_length=old_length,
            new_start=new_start,
            new_length=new_length,
        )

    def to_dict(self, annotate_lines: bool = False) -> dict:
        """Convert hunk to dictionary for JSON serialization.

        Args:
            annotate_lines: If True, content will have line numbers prepended

        Returns:
            Dictionary with hunk data suitable for JSON output
        """
        content = self.get_annotated_content() if annotate_lines else self.content
        return {
            "file_path": self.file_path,
            "new_start": self.new_start,
            "new_length": self.new_length,
            "old_start": self.old_start,
            "old_length": self.old_length,
            "content": content,
        }

    # --------------------------------------------------------
    # Public API
    # --------------------------------------------------------

    @property
    def filename(self) -> str:
        """Extract the filename from the file path."""
        return self.file_path.rsplit("/", 1)[-1] if "/" in self.file_path else self.file_path

    @property
    def file_extension(self) -> str:
        """Extract the file extension without leading dot."""
        if "." in self.filename:
            return self.filename.rsplit(".", 1)[-1]
        return ""

    def get_annotated_content(self) -> str:
        """Return hunk content with target file line numbers prepended.

        Each line in the diff content after the @@ header is annotated with
        its target file line number. This makes it explicit which line number
        each change corresponds to, removing ambiguity for reviewers.

        Format:
        - Added lines (+) and context lines ( ) get: "  5: +code here"
        - Deleted lines (-) get: "   -: -deleted code" (no line number)
        - Header lines are preserved as-is

        Returns:
            Content string with line numbers prepended to each diff line
        """
        lines = self.content.split("\n")
        annotated: list[str] = []
        new_line = self.new_start
        in_hunk_body = False

        for line in lines:
            if line.startswith("@@"):
                annotated.append(line)
                in_hunk_body = True
            elif not in_hunk_body:
                # Header lines (diff --git, index, ---, +++)
                annotated.append(line)
            elif line.startswith("-"):
                # Deleted line - doesn't exist in target file
                annotated.append(f"   -: {line}")
            elif line.startswith("+"):
                # Added line - exists in target file
                annotated.append(f"{new_line:4d}: {line}")
                new_line += 1
            elif line.startswith(" ") or line == "":
                # Context line - exists in target file
                if line:
                    annotated.append(f"{new_line:4d}: {line}")
                    new_line += 1
                else:
                    # Empty line at end of hunk
                    annotated.append(line)
            else:
                # Other lines (shouldn't happen in normal diffs)
                annotated.append(line)

        return "\n".join(annotated)

    def get_diff_lines(self) -> list[DiffLine]:
        """Parse hunk content into structured DiffLine objects.

        Returns:
            List of DiffLine objects with line numbers and types
        """
        lines = self.content.split("\n")
        diff_lines: list[DiffLine] = []
        new_line = self.new_start
        old_line = self.old_start
        in_hunk_body = False

        for line in lines:
            if line.startswith("@@"):
                in_hunk_body = True
                diff_lines.append(
                    DiffLine(
                        content=line,
                        raw_line=line,
                        line_type=DiffLineType.HEADER,
                    )
                )
            elif not in_hunk_body:
                diff_lines.append(
                    DiffLine(
                        content=line,
                        raw_line=line,
                        line_type=DiffLineType.HEADER,
                    )
                )
            elif line.startswith("-"):
                diff_lines.append(
                    DiffLine(
                        content=line[1:],
                        raw_line=line,
                        line_type=DiffLineType.REMOVED,
                        old_line_number=old_line,
                    )
                )
                old_line += 1
            elif line.startswith("+"):
                diff_lines.append(
                    DiffLine(
                        content=line[1:],
                        raw_line=line,
                        line_type=DiffLineType.ADDED,
                        new_line_number=new_line,
                    )
                )
                new_line += 1
            elif line.startswith(" ") or (line == "" and in_hunk_body):
                content = line[1:] if line.startswith(" ") else line
                if line:
                    diff_lines.append(
                        DiffLine(
                            content=content,
                            raw_line=line,
                            line_type=DiffLineType.CONTEXT,
                            new_line_number=new_line,
                            old_line_number=old_line,
                        )
                    )
                    new_line += 1
                    old_line += 1

        return diff_lines

    def get_added_lines(self) -> list[DiffLine]:
        """Get only added lines (lines starting with +).

        Returns:
            List of DiffLine objects for added lines only
        """
        return [
            line
            for line in self.get_diff_lines()
            if line.line_type == DiffLineType.ADDED
        ]

    def get_removed_lines(self) -> list[DiffLine]:
        """Get only removed lines (lines starting with -).

        Returns:
            List of DiffLine objects for removed lines only
        """
        return [
            line
            for line in self.get_diff_lines()
            if line.line_type == DiffLineType.REMOVED
        ]

    def get_changed_lines(self) -> list[DiffLine]:
        """Get all changed lines (both added and removed).

        This is what grep patterns should match against for rule filtering,
        as we only care about actual changes, not context lines.

        Returns:
            List of DiffLine objects for changed lines (added + removed)
        """
        return [line for line in self.get_diff_lines() if line.is_changed]

    def get_context_lines(self) -> list[DiffLine]:
        """Get only context lines (unchanged lines shown for context).

        Returns:
            List of DiffLine objects for context lines only
        """
        return [
            line
            for line in self.get_diff_lines()
            if line.line_type == DiffLineType.CONTEXT
        ]

    def get_changed_content(self) -> str:
        """Get the text content of changed lines only.

        Useful for grep pattern matching - only matches against
        actual changes, not surrounding context.

        Returns:
            Concatenated content of added and removed lines
        """
        return "\n".join(line.content for line in self.get_changed_lines())

    @staticmethod
    def extract_changed_content(diff_text: str) -> str:
        """Extract changed content from diff text.

        Static utility for extracting only added/removed lines from diff text
        without needing a full Hunk object. Useful when loading from JSON.

        Handles both raw diff format and annotated format:
        - Raw: Lines start with + or -
        - Annotated: Lines have format "123: +code" or "   -: -code"

        Args:
            diff_text: Diff content (raw or annotated)

        Returns:
            Concatenated content of changed lines (without prefixes)
        """
        changed_lines: list[str] = []
        in_hunk_body = False

        for line in diff_text.split("\n"):
            if line.startswith("@@"):
                in_hunk_body = True
            elif in_hunk_body:
                # Raw format: lines start with + or -
                if line.startswith("+") and not line.startswith("+++"):
                    changed_lines.append(line[1:])
                elif line.startswith("-") and not line.startswith("---"):
                    changed_lines.append(line[1:])
                # Annotated format: "123: +code" or "   -: -code"
                elif ": +" in line:
                    # Added line in annotated format
                    idx = line.index(": +")
                    changed_lines.append(line[idx + 3 :])
                elif ": -" in line and line.strip().startswith("-:"):
                    # Removed line in annotated format (line number is "-")
                    idx = line.index(": -")
                    changed_lines.append(line[idx + 3 :])

        return "\n".join(changed_lines)


@dataclass
class GitDiff:
    """Represents a complete git diff with all its hunks.

    Use from_diff_content() to parse raw diff output into structured hunks.
    """

    raw_content: str
    hunks: list[Hunk] = field(default_factory=list)
    commit_hash: str = ""

    # --------------------------------------------------------
    # Factory Methods
    # --------------------------------------------------------

    @classmethod
    def from_diff_content(cls, diff_content: str, commit_hash: str = "") -> GitDiff:
        """Parse raw diff content into structured hunks.

        Args:
            diff_content: Raw output from git diff or gh pr diff
            commit_hash: Optional commit hash associated with this diff

        Returns:
            GitDiff instance with parsed hunks
        """
        lines = diff_content.split("\n")
        hunks: list[Hunk] = []
        current_hunk: list[str] = []
        file_header: list[str] = []
        current_file: str = ""
        in_hunk = False

        i = 0
        while i < len(lines):
            line = lines[i]

            if line.startswith("diff --git"):
                if current_hunk and current_file:
                    hunk = Hunk.from_hunk_lines(file_header, current_hunk, current_file)
                    if hunk:
                        hunks.append(hunk)
                    current_hunk = []

                match = re.match(r'diff --git "?a/([^"]*)"? "?b/([^"]*)"?', line)
                if not match:
                    match = re.match(
                        r"diff --git a/(.*?) b/(.*?)(?:similarity index|$)",
                        line,
                    )

                if match:
                    current_file = match.group(2).strip()
                else:
                    current_file = ""

                file_header = [line]
                in_hunk = False

            elif line.startswith(("index ", "--- ", "+++ ", "new file", "deleted file", "similarity")):
                file_header.append(line)

            elif line.startswith("@@"):
                if current_hunk and current_file:
                    hunk = Hunk.from_hunk_lines(file_header, current_hunk, current_file)
                    if hunk:
                        hunks.append(hunk)
                    current_hunk = []
                in_hunk = True
                current_hunk.append(line)

            elif in_hunk:
                current_hunk.append(line)

            i += 1

        if current_hunk and current_file:
            hunk = Hunk.from_hunk_lines(file_header, current_hunk, current_file)
            if hunk:
                hunks.append(hunk)

        return cls(raw_content=diff_content, hunks=hunks, commit_hash=commit_hash)

    def to_dict(self, annotate_lines: bool = False) -> dict:
        """Convert diff to dictionary for JSON serialization.

        Args:
            annotate_lines: If True, hunk content will have line numbers prepended

        Returns:
            Dictionary with hunks suitable for JSON output
        """
        return {
            "commit_hash": self.commit_hash,
            "hunks": [hunk.to_dict(annotate_lines=annotate_lines) for hunk in self.hunks],
        }

    # --------------------------------------------------------
    # Public API
    # --------------------------------------------------------

    @property
    def is_empty(self) -> bool:
        """Check if the diff contains no hunks."""
        return not self.hunks

    def get_hunks_by_extension(self, extensions: list[str] | None = None) -> list[Hunk]:
        """Filter hunks by file extension.

        Args:
            extensions: List of extensions to include (without dots), or None for all

        Returns:
            List of hunks matching the extension filter
        """
        if extensions is None:
            return self.hunks
        return [h for h in self.hunks if h.file_extension in extensions]

    def get_hunks_by_file(self, file_path: str) -> list[Hunk]:
        """Get all hunks for a specific file.

        Args:
            file_path: The file path to filter by

        Returns:
            List of hunks for the specified file
        """
        return [h for h in self.hunks if h.file_path == file_path]

    def get_unique_files(self) -> list[str]:
        """Get list of unique file paths in this diff.

        Returns:
            Sorted list of unique file paths
        """
        return sorted(set(h.file_path for h in self.hunks))
