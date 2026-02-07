"""Effective diff computation — detects moved code and produces reduced diffs.

Phase 1: Line-level exact matching engine. Identifies removed lines that appear
as added lines elsewhere in the diff, tagging each with file/line/hunk metadata.

Phase 2: Block aggregation and scoring. Groups matched lines into contiguous
blocks (tolerating small gaps) and scores each for move confidence.
"""

from __future__ import annotations

import statistics
from dataclasses import dataclass, field
from enum import Enum

from prradar.domain.diff import DiffLineType, GitDiff, Hunk

DEFAULT_GAP_TOLERANCE = 3
DEFAULT_MIN_BLOCK_SIZE = 3
DEFAULT_MIN_SCORE = 0.0


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


# ------------------------------------------------------------------
# Phase 2: Block Aggregation and Scoring
# ------------------------------------------------------------------


@dataclass(frozen=True)
class MoveCandidate:
    """A block of matched lines representing a potential code move."""

    removed_lines: tuple[TaggedLine, ...]
    added_lines: tuple[TaggedLine, ...]
    score: float
    source_file: str
    target_file: str
    source_start_line: int
    target_start_line: int


@dataclass
class _BlockAccumulator:
    """Mutable accumulator for building blocks during grouping."""

    matches: list[LineMatch] = field(default_factory=list)

    @property
    def last_removed_line_number(self) -> int:
        return self.matches[-1].removed.line_number

    @property
    def source_file(self) -> str:
        return self.matches[0].removed.file_path

    @property
    def target_file(self) -> str:
        return self.matches[0].added.file_path


def _group_key(match: LineMatch) -> tuple[str, str]:
    """Group matches by (source_file, target_file) pair."""
    return (match.removed.file_path, match.added.file_path)


def group_matches_into_blocks(
    matches: list[LineMatch],
    gap_tolerance: int = DEFAULT_GAP_TOLERANCE,
) -> list[list[LineMatch]]:
    """Group matched lines into contiguous blocks, tolerating small gaps.

    Matches are grouped by (source_file, target_file) pair, then sorted by
    removed line number. Consecutive matched removed lines (with gaps of at
    most gap_tolerance unmatched lines) form a single block.

    Returns:
        List of blocks, where each block is a list of LineMatch objects.
    """
    # Filter out distance-0 matches (in-place edits, not moves)
    move_matches = [m for m in matches if m.distance > 0]

    if not move_matches:
        return []

    # Group by (source_file, target_file)
    groups: dict[tuple[str, str], list[LineMatch]] = {}
    for match in move_matches:
        key = _group_key(match)
        groups.setdefault(key, []).append(match)

    blocks: list[list[LineMatch]] = []

    for _key, group in groups.items():
        # Sort by removed line number for contiguity detection
        group.sort(key=lambda m: m.removed.line_number)

        current_block = _BlockAccumulator(matches=[group[0]])

        for match in group[1:]:
            gap = match.removed.line_number - current_block.last_removed_line_number - 1
            if gap <= gap_tolerance:
                current_block.matches.append(match)
            else:
                blocks.append(current_block.matches)
                current_block = _BlockAccumulator(matches=[match])

        blocks.append(current_block.matches)

    return blocks


def compute_size_factor(block: list[LineMatch], min_block_size: int = DEFAULT_MIN_BLOCK_SIZE) -> float:
    """Score based on block size. Below min_block_size returns 0. Scales up to 1.0 at 10+ lines."""
    size = len(block)
    if size < min_block_size:
        return 0.0
    # Linear ramp from min_block_size (baseline) to 10 (max factor)
    max_size = 10
    if size >= max_size:
        return 1.0
    return (size - min_block_size + 1) / (max_size - min_block_size + 1)


def compute_line_uniqueness(block: list[LineMatch], all_added_lines: list[TaggedLine]) -> float:
    """Average uniqueness of lines in the block based on inverse frequency in the added pool.

    Lines that appear many times in the diff (e.g., `return None`) get low uniqueness.
    Unique domain-specific lines get high uniqueness.
    """
    # Count frequency of each normalized content in all added lines
    freq: dict[str, int] = {}
    for line in all_added_lines:
        if line.normalized:
            freq[line.normalized] = freq.get(line.normalized, 0) + 1

    uniqueness_scores: list[float] = []
    for match in block:
        norm = match.removed.normalized
        if not norm:
            continue
        count = freq.get(norm, 1)
        uniqueness_scores.append(1.0 / count)

    if not uniqueness_scores:
        return 0.0
    return sum(uniqueness_scores) / len(uniqueness_scores)


def compute_match_consistency(block: list[LineMatch]) -> float:
    """Measure how consistently matched lines point to the same target region.

    Low standard deviation of target line numbers = high consistency.
    Returns a value between 0 and 1, where 1 means perfectly consistent.
    """
    if len(block) <= 1:
        return 1.0

    target_line_numbers = [m.added.line_number for m in block]
    stddev = statistics.stdev(target_line_numbers)

    # Normalize: small stddev relative to block size = high consistency
    # A perfectly consecutive sequence of N numbers has stddev ~= N/sqrt(12)
    # We use the block span as reference — if stddev is small compared to span, good.
    span = max(target_line_numbers) - min(target_line_numbers) + 1
    if span == 0:
        return 1.0

    # Ratio of actual stddev to what a uniformly spread set would have
    # Perfect ordering: stddev proportional to span
    # We want consistency=1 when perfectly ordered, consistency->0 when scattered
    expected_stddev = span / (2 * 1.732)  # span / (2*sqrt(3)) for uniform distribution
    if expected_stddev == 0:
        return 1.0

    ratio = stddev / expected_stddev
    if ratio <= 1.0:
        return 1.0
    # Decay for ratio > 1 (scattered matches)
    return 1.0 / ratio


def compute_distance_factor(block: list[LineMatch]) -> float:
    """Score based on distance between source and target hunks.

    Distance 0 means in-place edit (already filtered out in grouping).
    Higher distance increases confidence that it's a real move.
    """
    avg_distance = sum(m.distance for m in block) / len(block)
    if avg_distance == 0:
        return 0.0
    # Quick ramp: distance 1 = 0.5, distance 2+ = 1.0
    return min(1.0, avg_distance * 0.5)


def score_block(block: list[LineMatch], all_added_lines: list[TaggedLine]) -> float:
    """Compute composite confidence score for a block.

    score = size_factor * avg_uniqueness * consistency * distance_factor
    """
    size = compute_size_factor(block)
    if size == 0.0:
        return 0.0

    uniqueness = compute_line_uniqueness(block, all_added_lines)
    consistency = compute_match_consistency(block)
    distance = compute_distance_factor(block)

    return size * uniqueness * consistency * distance


def find_move_candidates(
    matches: list[LineMatch],
    all_added_lines: list[TaggedLine],
    gap_tolerance: int = DEFAULT_GAP_TOLERANCE,
    min_block_size: int = DEFAULT_MIN_BLOCK_SIZE,
    min_score: float = DEFAULT_MIN_SCORE,
) -> list[MoveCandidate]:
    """Find move candidates by grouping matches into blocks and scoring them.

    Returns:
        List of MoveCandidate objects sorted by score (descending),
        filtered to blocks meeting minimum size and score thresholds.
    """
    blocks = group_matches_into_blocks(matches, gap_tolerance=gap_tolerance)

    candidates: list[MoveCandidate] = []
    for block in blocks:
        if len(block) < min_block_size:
            continue

        score = score_block(block, all_added_lines)
        if score < min_score:
            continue

        removed_lines = tuple(m.removed for m in block)
        added_lines = tuple(m.added for m in block)

        candidates.append(
            MoveCandidate(
                removed_lines=removed_lines,
                added_lines=added_lines,
                score=score,
                source_file=block[0].removed.file_path,
                target_file=block[0].added.file_path,
                source_start_line=removed_lines[0].line_number,
                target_start_line=added_lines[0].line_number,
            )
        )

    candidates.sort(key=lambda c: c.score, reverse=True)
    return candidates
