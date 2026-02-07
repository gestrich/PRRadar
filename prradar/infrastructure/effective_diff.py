"""Effective diff computation — detects moved code and produces reduced diffs.

Phase 1: Line-level exact matching engine. Identifies removed lines that appear
as added lines elsewhere in the diff, tagging each with file/line/hunk metadata.

Phase 2: Block aggregation and scoring. Groups matched lines into contiguous
blocks (tolerating small gaps) and scores each for move confidence.

Phase 3: Block extension and re-diff. Extends matched blocks by surrounding
context from source files and re-diffs to isolate meaningful changes.

Phase 4: Diff reconstruction. Combines effective diffs for moved blocks with
unchanged portions of the original diff to produce the final effective GitDiff.
"""

from __future__ import annotations

import re
import statistics
import subprocess
import tempfile
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path

from prradar.domain.diff import DiffLineType, GitDiff, Hunk

DEFAULT_GAP_TOLERANCE = 3
DEFAULT_MIN_BLOCK_SIZE = 3
DEFAULT_MIN_SCORE = 0.0
DEFAULT_CONTEXT_LINES = 20
DEFAULT_TRIM_PROXIMITY = 3


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


# ------------------------------------------------------------------
# Phase 3: Block Extension and Re-Diff
# ------------------------------------------------------------------


@dataclass(frozen=True)
class EffectiveDiffResult:
    """Result of re-diffing a single moved block."""

    candidate: MoveCandidate
    hunks: list[Hunk]
    raw_diff: str


def _extract_line_range(file_content: str, start: int, end: int) -> str:
    """Extract a 1-indexed inclusive line range from file content.

    Args:
        file_content: Full file contents as a string.
        start: First line to include (1-indexed, clamped to 1).
        end: Last line to include (1-indexed, clamped to file length).

    Returns:
        Extracted text as a string (with trailing newline if non-empty).
    """
    lines = file_content.splitlines(keepends=True)
    start = max(1, start)
    end = min(len(lines), end)
    if start > end:
        return ""
    return "".join(lines[start - 1 : end])


def extend_block_range(
    candidate: MoveCandidate,
    context_lines: int = DEFAULT_CONTEXT_LINES,
) -> tuple[tuple[int, int], tuple[int, int]]:
    """Compute extended line ranges for a move candidate's source and target.

    Returns:
        ((source_start, source_end), (target_start, target_end)) — 1-indexed inclusive.
    """
    src_start = candidate.removed_lines[0].line_number
    src_end = candidate.removed_lines[-1].line_number
    tgt_start = candidate.added_lines[0].line_number
    tgt_end = candidate.added_lines[-1].line_number

    return (
        (max(1, src_start - context_lines), src_end + context_lines),
        (max(1, tgt_start - context_lines), tgt_end + context_lines),
    )


def rediff_regions(
    old_text: str,
    new_text: str,
    old_label: str,
    new_label: str,
) -> str:
    """Run git diff --no-index on two text regions and return raw diff output.

    The temp file paths in the diff output are replaced with the provided labels
    so the output has meaningful file paths.

    Args:
        old_text: Contents of the old (source) region.
        new_text: Contents of the new (target) region.
        old_label: Label for the old file (e.g. source file path).
        new_label: Label for the new file (e.g. target file path).

    Returns:
        Raw unified diff string with relabeled paths, or empty string if identical.
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        old_path = Path(tmpdir) / "old.txt"
        new_path = Path(tmpdir) / "new.txt"
        old_path.write_text(old_text)
        new_path.write_text(new_text)

        result = subprocess.run(
            ["git", "diff", "--no-index", "--no-color", str(old_path), str(new_path)],
            capture_output=True,
            text=True,
        )
        raw = result.stdout
        if not raw:
            return ""

        # git diff --no-index produces paths like a/<tmpdir>/old.txt.
        # Replace those with a/<label> and b/<label>.
        # Strip leading / from temp paths since git uses a/<path> format.
        old_rel = str(old_path).lstrip("/")
        new_rel = str(new_path).lstrip("/")
        raw = raw.replace(f"a/{old_rel}", f"a/{old_label}")
        raw = raw.replace(f"b/{new_rel}", f"b/{new_label}")

        return raw


def _hunk_overlaps_block(
    hunk: Hunk,
    block_start: int,
    block_end: int,
    region_start: int,
    proximity: int = DEFAULT_TRIM_PROXIMITY,
) -> bool:
    """Check if a hunk's line range overlaps or is adjacent to the block boundaries.

    The hunk line numbers are relative to the extracted region, so we offset them
    by region_start to get absolute file line numbers before comparing.

    Args:
        hunk: A parsed Hunk from the re-diff output.
        block_start: First line of the original matched block (absolute, 1-indexed).
        block_end: Last line of the original matched block (absolute, 1-indexed).
        region_start: Start line of the extracted region (absolute, 1-indexed).
        proximity: Number of lines of slack for "adjacent" matching.

    Returns:
        True if the hunk overlaps or is within proximity of the block.
    """
    # The re-diff operates on the extracted region, so hunk line numbers
    # are relative to the region. Convert to absolute file line numbers.
    # We use old_start for old side, but either side works since we're
    # checking overlap with the block which has known absolute positions.
    # Use the new side since the "target" block is the added side.
    hunk_abs_start = region_start + hunk.new_start - 1
    hunk_abs_end = hunk_abs_start + max(hunk.new_length - 1, 0)

    # Check overlap with proximity tolerance
    return (
        hunk_abs_start <= block_end + proximity
        and hunk_abs_end >= block_start - proximity
    )


def trim_hunks(
    hunks: list[Hunk],
    block_start: int,
    block_end: int,
    region_start: int,
    proximity: int = DEFAULT_TRIM_PROXIMITY,
) -> list[Hunk]:
    """Filter hunks to keep only those overlapping the original matched block.

    Args:
        hunks: Parsed hunks from the re-diff output.
        block_start: First line of the original matched block (absolute, 1-indexed).
        block_end: Last line of the original matched block (absolute, 1-indexed).
        region_start: Start line of the extracted region (absolute, 1-indexed).
        proximity: Adjacency tolerance in lines.

    Returns:
        Filtered list of hunks.
    """
    return [
        h for h in hunks
        if _hunk_overlaps_block(h, block_start, block_end, region_start, proximity)
    ]


def compute_effective_diff_for_candidate(
    candidate: MoveCandidate,
    old_files: dict[str, str],
    new_files: dict[str, str],
    context_lines: int = DEFAULT_CONTEXT_LINES,
    trim_proximity: int = DEFAULT_TRIM_PROXIMITY,
) -> EffectiveDiffResult:
    """Compute the effective diff for a single move candidate.

    Extends the matched block by ±context_lines, extracts regions from
    source file contents, re-diffs them, and trims unrelated hunks.

    Args:
        candidate: The move candidate to process.
        old_files: Dict of {file_path: content} for old file versions.
        new_files: Dict of {file_path: content} for new file versions.
        context_lines: Number of lines to extend in each direction.
        trim_proximity: Adjacency tolerance for hunk trimming.

    Returns:
        EffectiveDiffResult with the effective diff hunks for this move.
    """
    (src_start, src_end), (tgt_start, tgt_end) = extend_block_range(
        candidate, context_lines
    )

    old_content = old_files.get(candidate.source_file, "")
    new_content = new_files.get(candidate.target_file, "")

    old_region = _extract_line_range(old_content, src_start, src_end)
    new_region = _extract_line_range(new_content, tgt_start, tgt_end)

    raw_diff = rediff_regions(
        old_region,
        new_region,
        old_label=candidate.source_file,
        new_label=candidate.target_file,
    )

    if not raw_diff:
        return EffectiveDiffResult(candidate=candidate, hunks=[], raw_diff="")

    parsed = GitDiff.from_diff_content(raw_diff)

    # Trim hunks to only those overlapping the original block
    tgt_block_start = candidate.added_lines[0].line_number
    tgt_block_end = candidate.added_lines[-1].line_number

    trimmed = trim_hunks(
        parsed.hunks,
        block_start=tgt_block_start,
        block_end=tgt_block_end,
        region_start=tgt_start,
        proximity=trim_proximity,
    )

    return EffectiveDiffResult(
        candidate=candidate,
        hunks=trimmed,
        raw_diff=raw_diff,
    )


# ------------------------------------------------------------------
# Phase 4: Diff Reconstruction
# ------------------------------------------------------------------


@dataclass(frozen=True)
class MoveDetail:
    """Details about a single detected code move."""

    source_file: str
    target_file: str
    source_lines: tuple[int, int]
    target_lines: tuple[int, int]
    matched_lines: int
    score: float
    effective_diff_lines: int

    def to_dict(self) -> dict:
        return {
            "source_file": self.source_file,
            "target_file": self.target_file,
            "source_lines": list(self.source_lines),
            "target_lines": list(self.target_lines),
            "matched_lines": self.matched_lines,
            "score": self.score,
            "effective_diff_lines": self.effective_diff_lines,
        }


@dataclass(frozen=True)
class MoveReport:
    """Summary of all detected code moves."""

    moves_detected: int
    total_lines_moved: int
    total_lines_effectively_changed: int
    moves: tuple[MoveDetail, ...]

    def to_dict(self) -> dict:
        return {
            "moves_detected": self.moves_detected,
            "total_lines_moved": self.total_lines_moved,
            "total_lines_effectively_changed": self.total_lines_effectively_changed,
            "moves": [m.to_dict() for m in self.moves],
        }


def _count_changed_lines_in_hunks(hunks: list[Hunk]) -> int:
    """Count added + removed lines across a list of hunks."""
    count = 0
    for hunk in hunks:
        for diff_line in hunk.get_diff_lines():
            if diff_line.line_type in (DiffLineType.ADDED, DiffLineType.REMOVED):
                count += 1
    return count


def _hunk_line_range(hunk: Hunk, side: str) -> tuple[int, int]:
    """Get the (start, end) 1-indexed inclusive line range for a hunk side.

    Args:
        hunk: The hunk to inspect.
        side: "old" for removed side, "new" for added side.

    Returns:
        (start, end) inclusive line range. End may equal start-1 for zero-length hunks.
    """
    if side == "old":
        return (hunk.old_start, hunk.old_start + max(hunk.old_length - 1, 0))
    return (hunk.new_start, hunk.new_start + max(hunk.new_length - 1, 0))


def _ranges_overlap(
    a_start: int, a_end: int, b_start: int, b_end: int
) -> bool:
    """Check if two inclusive 1-indexed ranges overlap."""
    return a_start <= b_end and b_start <= a_end


def classify_hunk(
    hunk: Hunk,
    effective_results: list[EffectiveDiffResult],
) -> tuple[str, EffectiveDiffResult | None]:
    """Classify a hunk from the original diff relative to detected moves.

    Returns:
        A tuple of (classification, result) where classification is one of:
        - "move_removed": Hunk is on the removed side of a detected move
        - "move_added": Hunk is on the added side of a detected move
        - "unchanged": Not part of any detected move

        For move_removed/move_added, the associated EffectiveDiffResult is returned.
    """
    hunk_old_start, hunk_old_end = _hunk_line_range(hunk, "old")
    hunk_new_start, hunk_new_end = _hunk_line_range(hunk, "new")

    for result in effective_results:
        candidate = result.candidate
        src_start = candidate.removed_lines[0].line_number
        src_end = candidate.removed_lines[-1].line_number
        tgt_start = candidate.added_lines[0].line_number
        tgt_end = candidate.added_lines[-1].line_number

        # Check removed side: hunk is in the source file and overlaps the removed block
        if (
            hunk.file_path == candidate.source_file
            and hunk_old_start > 0
            and _ranges_overlap(hunk_old_start, hunk_old_end, src_start, src_end)
        ):
            return ("move_removed", result)

        # Check added side: hunk is in the target file and overlaps the added block
        if (
            hunk.file_path == candidate.target_file
            and hunk_new_start > 0
            and _ranges_overlap(hunk_new_start, hunk_new_end, tgt_start, tgt_end)
        ):
            return ("move_added", result)

    return ("unchanged", None)


def reconstruct_effective_diff(
    original_diff: GitDiff,
    effective_results: list[EffectiveDiffResult],
) -> GitDiff:
    """Reconstruct a GitDiff by replacing move hunks with their effective diffs.

    For each hunk in the original diff:
    - Part of a detected move (removed side): Drop it
    - Part of a detected move (added side): Replace with the effective diff hunks
    - Not part of any move: Keep as-is

    Args:
        original_diff: The original parsed GitDiff.
        effective_results: Results from Phase 3 (one per move candidate).

    Returns:
        A new GitDiff containing only meaningful changes.
    """
    surviving_hunks: list[Hunk] = []
    # Track which effective results we've already emitted to avoid duplicates
    emitted_results: set[int] = set()

    for hunk in original_diff.hunks:
        classification, result = classify_hunk(hunk, effective_results)

        if classification == "move_removed":
            # Drop: the effective diff on the added side captures real changes
            continue

        if classification == "move_added" and result is not None:
            result_id = id(result)
            if result_id not in emitted_results:
                emitted_results.add(result_id)
                surviving_hunks.extend(result.hunks)
            # If already emitted, skip (multiple original hunks may map to one result)
            continue

        # unchanged — keep as-is
        surviving_hunks.append(hunk)

    return GitDiff(
        raw_content=original_diff.raw_content,
        hunks=surviving_hunks,
        commit_hash=original_diff.commit_hash,
    )


def build_move_report(
    effective_results: list[EffectiveDiffResult],
) -> MoveReport:
    """Build a summary report of all detected moves.

    Args:
        effective_results: Results from Phase 3 (one per move candidate).

    Returns:
        MoveReport with aggregate statistics and per-move details.
    """
    details: list[MoveDetail] = []
    total_lines_moved = 0
    total_effectively_changed = 0

    for result in effective_results:
        candidate = result.candidate
        matched = len(candidate.removed_lines)
        eff_lines = _count_changed_lines_in_hunks(result.hunks)

        src_start = candidate.removed_lines[0].line_number
        src_end = candidate.removed_lines[-1].line_number
        tgt_start = candidate.added_lines[0].line_number
        tgt_end = candidate.added_lines[-1].line_number

        details.append(
            MoveDetail(
                source_file=candidate.source_file,
                target_file=candidate.target_file,
                source_lines=(src_start, src_end),
                target_lines=(tgt_start, tgt_end),
                matched_lines=matched,
                score=candidate.score,
                effective_diff_lines=eff_lines,
            )
        )
        total_lines_moved += matched
        total_effectively_changed += eff_lines

    return MoveReport(
        moves_detected=len(details),
        total_lines_moved=total_lines_moved,
        total_lines_effectively_changed=total_effectively_changed,
        moves=tuple(details),
    )


# ------------------------------------------------------------------
# Pipeline Entry Point
# ------------------------------------------------------------------


def run_effective_diff_pipeline(
    git_diff: GitDiff,
    old_files: dict[str, str],
    new_files: dict[str, str],
) -> tuple[GitDiff, MoveReport]:
    """Run the full effective diff pipeline: match, group, re-diff, reconstruct.

    Chains the four internal stages to detect moved code blocks and produce
    a reduced diff containing only meaningful changes.

    Args:
        git_diff: The original parsed diff.
        old_files: Dict of {file_path: content} for old (base) file versions.
        new_files: Dict of {file_path: content} for new (head) file versions.

    Returns:
        (effective_diff, move_report) — the reduced GitDiff and a summary of moves.
    """
    removed, added = extract_tagged_lines(git_diff)
    matches = find_exact_matches(removed, added)
    candidates = find_move_candidates(matches, added)

    effective_results = [
        compute_effective_diff_for_candidate(c, old_files, new_files)
        for c in candidates
    ]

    effective_diff = reconstruct_effective_diff(git_diff, effective_results)
    report = build_move_report(effective_results)
    return effective_diff, report
