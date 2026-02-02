"""Domain models for git diff parsing.

Parse-once pattern: Raw diff content is parsed into type-safe models at the boundary.
Provides Hunk and GitDiff models with factory methods for deterministic parsing.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field


# ============================================================
# Domain Models
# ============================================================


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

    def to_dict(self) -> dict:
        """Convert hunk to dictionary for JSON serialization.

        Returns:
            Dictionary with hunk data suitable for JSON output
        """
        return {
            "file_path": self.file_path,
            "new_start": self.new_start,
            "new_length": self.new_length,
            "old_start": self.old_start,
            "old_length": self.old_length,
            "content": self.content,
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

    def to_dict(self) -> dict:
        """Convert diff to dictionary for JSON serialization.

        Returns:
            Dictionary with hunks suitable for JSON output
        """
        return {
            "commit_hash": self.commit_hash,
            "hunks": [hunk.to_dict() for hunk in self.hunks],
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
