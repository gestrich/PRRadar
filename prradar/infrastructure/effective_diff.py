"""Effective diff computation — detects moved code and produces reduced diffs.

Phase 1: Line-level exact matching engine. Identifies removed lines that appear
as added lines elsewhere in the diff, tagging each with file/line/hunk metadata.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from prradar.domain.diff import DiffLineType, GitDiff, Hunk


class TaggedLineType(Enum):
    ADDED = "added"
    REMOVED = "removed"


@dataclass(frozen=True)
class TaggedLine:
    """A diff line tagged with its location metadata."""

    content: str
    normalized: str
    file_path: str
    line_number: int
    hunk_index: int
    line_type: TaggedLineType


@dataclass(frozen=True)
class LineMatch:
    """A matched pair of removed+added lines with distance metadata."""

    removed: TaggedLine
    added: TaggedLine
    distance: int
    similarity: float


def _normalize(line: str) -> str:
    """Strip leading/trailing whitespace for comparison."""
    return line.strip()


def extract_tagged_lines(git_diff: GitDiff) -> tuple[list[TaggedLine], list[TaggedLine]]:
    """Extract all removed and added lines from a GitDiff, tagged with metadata.

    Returns:
        (removed_lines, added_lines) — each tagged with file path, line number,
        and hunk index for distance calculation.
    """
    removed: list[TaggedLine] = []
    added: list[TaggedLine] = []

    for hunk_index, hunk in enumerate(git_diff.hunks):
        for diff_line in hunk.get_diff_lines():
            if diff_line.line_type == DiffLineType.REMOVED and diff_line.old_line_number is not None:
                removed.append(
                    TaggedLine(
                        content=diff_line.content,
                        normalized=_normalize(diff_line.content),
                        file_path=hunk.file_path,
                        line_number=diff_line.old_line_number,
                        hunk_index=hunk_index,
                        line_type=TaggedLineType.REMOVED,
                    )
                )
            elif diff_line.line_type == DiffLineType.ADDED and diff_line.new_line_number is not None:
                added.append(
                    TaggedLine(
                        content=diff_line.content,
                        normalized=_normalize(diff_line.content),
                        file_path=hunk.file_path,
                        line_number=diff_line.new_line_number,
                        hunk_index=hunk_index,
                        line_type=TaggedLineType.ADDED,
                    )
                )

    return removed, added


def build_added_index(added_lines: list[TaggedLine]) -> dict[str, list[TaggedLine]]:
    """Build a lookup index of added lines keyed by normalized content.

    Lines with empty normalized content (blank/whitespace-only) are excluded
    since they match too broadly.
    """
    index: dict[str, list[TaggedLine]] = {}
    for line in added_lines:
        if not line.normalized:
            continue
        index.setdefault(line.normalized, []).append(line)
    return index


def find_exact_matches(
    removed_lines: list[TaggedLine],
    added_lines: list[TaggedLine],
) -> list[LineMatch]:
    """Find exact content matches between removed and added lines.

    For each removed line, looks up all added lines with the same normalized
    content. Each added line can only be matched once (greedy, first-come).

    Returns:
        List of LineMatch objects with distance metadata.
    """
    index = build_added_index(added_lines)
    matched_added: set[int] = set()  # track by id() to handle duplicates
    matches: list[LineMatch] = []

    for removed in removed_lines:
        if not removed.normalized:
            continue

        candidates = index.get(removed.normalized)
        if not candidates:
            continue

        for added in candidates:
            if id(added) in matched_added:
                continue

            distance = abs(removed.hunk_index - added.hunk_index)
            matches.append(
                LineMatch(
                    removed=removed,
                    added=added,
                    distance=distance,
                    similarity=1.0,
                )
            )
            matched_added.add(id(added))
            break

    return matches
