import Foundation

let defaultContextLines = 3
let defaultTrimProximity = 3

// MARK: - Data Structures

struct EffectiveDiffResult: Sendable, Equatable {
    let candidate: MoveCandidate
    let hunks: [Hunk]
    let rawDiff: String
    let rediffAnalysis: RediffAnalysis

    init(candidate: MoveCandidate, hunks: [Hunk], rawDiff: String, rediffAnalysis: RediffAnalysis = RediffAnalysis()) {
        self.candidate = candidate
        self.hunks = hunks
        self.rawDiff = rawDiff
        self.rediffAnalysis = rediffAnalysis
    }
}

/// Analysis of re-diff hunks: which lines within a move are insertions, modifications, or deletions.
struct RediffAnalysis: Sendable, Equatable {
    /// Target-side lines that are new insertions inside the moved block (absolute coordinates).
    let addedInMoveLines: Set<Int>
    /// Target-side lines that are modifications of existing source content (absolute coordinates).
    let changedInMoveLines: Set<Int>
    /// Source-side lines that were modified or deleted at the destination (absolute coordinates → change kind).
    let changedSourceLines: [Int: ChangeKind]

    init(addedInMoveLines: Set<Int> = [], changedInMoveLines: Set<Int> = [], changedSourceLines: [Int: ChangeKind] = [:]) {
        self.addedInMoveLines = addedInMoveLines
        self.changedInMoveLines = changedInMoveLines
        self.changedSourceLines = changedSourceLines
    }
}

/// Analyze re-diff hunks to classify which lines within a move are insertions, modifications, or deletions.
///
/// For each hunk, uses the ratio of removed-to-added lines to determine:
/// - **Target side**: Pure insertion hunks (no `-` lines) → all `+` lines are `.added`.
///   Mixed hunks → first `min(removedCount, addedCount)` `+` lines are `.changed`, surplus are `.added`.
/// - **Source side**: `-` lines in hunks with `+` lines → `.changed`; in hunks without → `.removed`.
func analyzeRediffHunks(hunks: [Hunk], sourceRegionStart: Int, targetRegionStart: Int) -> RediffAnalysis {
    var addedInMove: Set<Int> = []
    var changedInMove: Set<Int> = []
    var changedSource: [Int: ChangeKind] = [:]

    for hunk in hunks {
        let diffLines = hunk.getDiffLines().filter { $0.lineType != .header }
        let removedCount = diffLines.filter { $0.lineType == .removed }.count
        let addedCount = diffLines.filter { $0.lineType == .added }.count

        if removedCount == 0 {
            for diffLine in diffLines where diffLine.lineType == .added {
                if let relativeLineNum = diffLine.newLineNumber {
                    addedInMove.insert(targetRegionStart + relativeLineNum - 1)
                }
            }
        } else {
            let modificationLimit = min(removedCount, addedCount)
            var addedSoFar = 0
            for diffLine in diffLines where diffLine.lineType == .added {
                if let relativeLineNum = diffLine.newLineNumber {
                    let absoluteLineNum = targetRegionStart + relativeLineNum - 1
                    if addedSoFar < modificationLimit {
                        changedInMove.insert(absoluteLineNum)
                    } else {
                        addedInMove.insert(absoluteLineNum)
                    }
                    addedSoFar += 1
                }
            }
        }

        for diffLine in diffLines where diffLine.lineType == .removed {
            if let relativeOldLineNum = diffLine.oldLineNumber {
                let absoluteLineNum = sourceRegionStart + relativeOldLineNum - 1
                changedSource[absoluteLineNum] = addedCount > 0 ? .changed : .removed
            }
        }
    }

    return RediffAnalysis(addedInMoveLines: addedInMove, changedInMoveLines: changedInMove, changedSourceLines: changedSource)
}

/// A function that re-diffs two text regions and returns raw unified diff output.
/// The algorithm needs `git diff --no-index` but `PRRadarModels` has no CLI dependency,
/// so callers inject the implementation.
public typealias RediffFunction = @Sendable (
    _ oldText: String,
    _ newText: String,
    _ oldLabel: String,
    _ newLabel: String
) async throws -> String

// MARK: - Functions

func extractLineRange(from fileContent: String, start: Int, end: Int) -> String {
    var lines = fileContent.components(separatedBy: "\n")
    // Drop trailing empty element from trailing newline (matches Python splitlines behavior)
    if lines.last == "" { lines.removeLast() }

    let clampedStart = max(1, start)
    let clampedEnd = min(lines.count, end)
    guard clampedStart <= clampedEnd else { return "" }

    let slice = lines[(clampedStart - 1)...(clampedEnd - 1)]
    var result = slice.joined(separator: "\n")
    if !result.isEmpty && fileContent.hasSuffix("\n") {
        result += "\n"
    }
    return result
}

func extendBlockRange(
    _ candidate: MoveCandidate,
    contextLines: Int = defaultContextLines
) -> (source: (start: Int, end: Int), target: (start: Int, end: Int)) {
    let srcStart = candidate.removedLines.first!.lineNumber
    let srcEnd = candidate.removedLines.last!.lineNumber
    let tgtStart = candidate.addedLines.first!.lineNumber
    let tgtEnd = candidate.addedLines.last!.lineNumber

    return (
        source: (start: max(1, srcStart - contextLines), end: srcEnd + contextLines),
        target: (start: max(1, tgtStart - contextLines), end: tgtEnd + contextLines)
    )
}

func hunkOverlapsBlock(
    _ hunk: Hunk,
    blockStart: Int,
    blockEnd: Int,
    regionStart: Int,
    proximity: Int = defaultTrimProximity
) -> Bool {
    let hunkAbsStart = regionStart + hunk.newStart - 1
    let hunkAbsEnd = hunkAbsStart + max(hunk.newLength - 1, 0)

    return hunkAbsStart <= blockEnd + proximity
        && hunkAbsEnd >= blockStart - proximity
}

func trimHunks(
    _ hunks: [Hunk],
    blockStart: Int,
    blockEnd: Int,
    regionStart: Int,
    proximity: Int = defaultTrimProximity
) -> [Hunk] {
    hunks.filter { hunkOverlapsBlock($0, blockStart: blockStart, blockEnd: blockEnd, regionStart: regionStart, proximity: proximity) }
}

func computeEffectiveDiffForCandidate(
    _ candidate: MoveCandidate,
    oldFiles: [String: String],
    newFiles: [String: String],
    contextLines: Int = defaultContextLines,
    trimProximity: Int = defaultTrimProximity,
    rediff: RediffFunction
) async throws -> EffectiveDiffResult {
    let ranges = extendBlockRange(candidate, contextLines: contextLines)

    let oldContent = oldFiles[candidate.sourceFile] ?? ""
    let newContent = newFiles[candidate.targetFile] ?? ""

    let oldRegion = extractLineRange(from: oldContent, start: ranges.source.start, end: ranges.source.end)
    let newRegion = extractLineRange(from: newContent, start: ranges.target.start, end: ranges.target.end)

    let rawDiff = try await rediff(oldRegion, newRegion, candidate.sourceFile, candidate.targetFile)

    guard !rawDiff.isEmpty else {
        return EffectiveDiffResult(candidate: candidate, hunks: [], rawDiff: "")
    }

    let parsed = GitDiff.fromDiffContent(rawDiff, commitHash: "")

    let tgtBlockStart = candidate.addedLines.first!.lineNumber
    let tgtBlockEnd = candidate.addedLines.last!.lineNumber

    let trimmed = trimHunks(
        parsed.hunks,
        blockStart: tgtBlockStart,
        blockEnd: tgtBlockEnd,
        regionStart: ranges.target.start,
        proximity: trimProximity
    )

    let analysis = analyzeRediffHunks(
        hunks: trimmed,
        sourceRegionStart: ranges.source.start,
        targetRegionStart: ranges.target.start
    )

    return EffectiveDiffResult(
        candidate: candidate,
        hunks: trimmed,
        rawDiff: rawDiff,
        rediffAnalysis: analysis
    )
}
