import Foundation

// MARK: - Move Report Models (algorithm-internal versions)

/// Details about a single detected code move (algorithm output).
/// Distinct from the `MoveDetail` in `DiffOutput.swift` which is the Codable serialization model.
public struct EffectiveDiffMoveDetail: Sendable, Equatable {
    public let sourceFile: String
    public let targetFile: String
    public let sourceLines: (start: Int, end: Int)
    public let targetLines: (start: Int, end: Int)
    public let matchedLines: Int
    public let score: Double
    public let effectiveDiffLines: Int

    public init(
        sourceFile: String,
        targetFile: String,
        sourceLines: (start: Int, end: Int),
        targetLines: (start: Int, end: Int),
        matchedLines: Int,
        score: Double,
        effectiveDiffLines: Int
    ) {
        self.sourceFile = sourceFile
        self.targetFile = targetFile
        self.sourceLines = sourceLines
        self.targetLines = targetLines
        self.matchedLines = matchedLines
        self.score = score
        self.effectiveDiffLines = effectiveDiffLines
    }

    public static func == (lhs: EffectiveDiffMoveDetail, rhs: EffectiveDiffMoveDetail) -> Bool {
        lhs.sourceFile == rhs.sourceFile
        && lhs.targetFile == rhs.targetFile
        && lhs.sourceLines.start == rhs.sourceLines.start
        && lhs.sourceLines.end == rhs.sourceLines.end
        && lhs.targetLines.start == rhs.targetLines.start
        && lhs.targetLines.end == rhs.targetLines.end
        && lhs.matchedLines == rhs.matchedLines
        && lhs.score == rhs.score
        && lhs.effectiveDiffLines == rhs.effectiveDiffLines
    }

    public func toMoveDetail() -> MoveDetail {
        MoveDetail(
            sourceFile: sourceFile,
            targetFile: targetFile,
            sourceLines: [sourceLines.start, sourceLines.end],
            targetLines: [targetLines.start, targetLines.end],
            matchedLines: matchedLines,
            score: score,
            effectiveDiffLines: effectiveDiffLines
        )
    }
}

/// Summary of all detected code moves (algorithm output).
public struct EffectiveDiffMoveReport: Sendable, Equatable {
    public let movesDetected: Int
    public let totalLinesMoved: Int
    public let totalLinesEffectivelyChanged: Int
    public let moves: [EffectiveDiffMoveDetail]

    public init(
        movesDetected: Int,
        totalLinesMoved: Int,
        totalLinesEffectivelyChanged: Int,
        moves: [EffectiveDiffMoveDetail]
    ) {
        self.movesDetected = movesDetected
        self.totalLinesMoved = totalLinesMoved
        self.totalLinesEffectivelyChanged = totalLinesEffectivelyChanged
        self.moves = moves
    }

    public func toMoveReport() -> MoveReport {
        MoveReport(
            movesDetected: movesDetected,
            totalLinesMoved: totalLinesMoved,
            totalLinesEffectivelyChanged: totalLinesEffectivelyChanged,
            moves: moves.map { $0.toMoveDetail() }
        )
    }
}

// MARK: - Helper Functions

func countChangedLinesInHunks(_ hunks: [Hunk]) -> Int {
    var count = 0
    for hunk in hunks {
        for diffLine in hunk.getDiffLines() {
            if diffLine.lineType == .added || diffLine.lineType == .removed {
                count += 1
            }
        }
    }
    return count
}

func hunkLineRange(_ hunk: Hunk, side: String) -> (start: Int, end: Int) {
    if side == "old" {
        return (hunk.oldStart, hunk.oldStart + max(hunk.oldLength - 1, 0))
    }
    return (hunk.newStart, hunk.newStart + max(hunk.newLength - 1, 0))
}

func rangesOverlap(
    _ aStart: Int, _ aEnd: Int,
    _ bStart: Int, _ bEnd: Int
) -> Bool {
    aStart <= bEnd && bStart <= aEnd
}

// MARK: - Hunk Classification

public enum HunkClassification: Equatable {
    case moveRemoved(EffectiveDiffResult)
    case moveAdded(EffectiveDiffResult)
    case unchanged

    public static func == (lhs: HunkClassification, rhs: HunkClassification) -> Bool {
        switch (lhs, rhs) {
        case (.unchanged, .unchanged):
            return true
        case let (.moveRemoved(a), .moveRemoved(b)):
            return a == b
        case let (.moveAdded(a), .moveAdded(b)):
            return a == b
        default:
            return false
        }
    }
}

public func classifyHunk(
    _ hunk: Hunk,
    effectiveResults: [EffectiveDiffResult]
) -> HunkClassification {
    let (hunkOldStart, hunkOldEnd) = hunkLineRange(hunk, side: "old")
    let (hunkNewStart, hunkNewEnd) = hunkLineRange(hunk, side: "new")

    for result in effectiveResults {
        let candidate = result.candidate
        let srcStart = candidate.removedLines.first!.lineNumber
        let srcEnd = candidate.removedLines.last!.lineNumber
        let tgtStart = candidate.addedLines.first!.lineNumber
        let tgtEnd = candidate.addedLines.last!.lineNumber

        if hunk.filePath == candidate.sourceFile
            && hunkOldStart > 0
            && rangesOverlap(hunkOldStart, hunkOldEnd, srcStart, srcEnd) {
            return .moveRemoved(result)
        }

        if hunk.filePath == candidate.targetFile
            && hunkNewStart > 0
            && rangesOverlap(hunkNewStart, hunkNewEnd, tgtStart, tgtEnd) {
            return .moveAdded(result)
        }
    }

    return .unchanged
}

// MARK: - Reconstruction

public func reconstructEffectiveDiff(
    originalDiff: GitDiff,
    effectiveResults: [EffectiveDiffResult]
) -> GitDiff {
    var survivingHunks: [Hunk] = []
    var emittedResultIndices: Set<Int> = []

    for hunk in originalDiff.hunks {
        let classification = classifyHunk(hunk, effectiveResults: effectiveResults)

        switch classification {
        case .moveRemoved:
            continue

        case let .moveAdded(result):
            if let resultIndex = effectiveResults.firstIndex(where: { $0 == result }) {
                if !emittedResultIndices.contains(resultIndex) {
                    emittedResultIndices.insert(resultIndex)
                    survivingHunks.append(contentsOf: result.hunks)
                }
            }

        case .unchanged:
            survivingHunks.append(hunk)
        }
    }

    return GitDiff(
        rawContent: originalDiff.rawContent,
        hunks: survivingHunks,
        commitHash: originalDiff.commitHash
    )
}

// MARK: - Move Report

public func buildMoveReport(
    _ effectiveResults: [EffectiveDiffResult]
) -> EffectiveDiffMoveReport {
    var details: [EffectiveDiffMoveDetail] = []
    var totalLinesMoved = 0
    var totalEffectivelyChanged = 0

    for result in effectiveResults {
        let candidate = result.candidate
        let matched = candidate.removedLines.count
        let effLines = countChangedLinesInHunks(result.hunks)

        let srcStart = candidate.removedLines.first!.lineNumber
        let srcEnd = candidate.removedLines.last!.lineNumber
        let tgtStart = candidate.addedLines.first!.lineNumber
        let tgtEnd = candidate.addedLines.last!.lineNumber

        details.append(EffectiveDiffMoveDetail(
            sourceFile: candidate.sourceFile,
            targetFile: candidate.targetFile,
            sourceLines: (srcStart, srcEnd),
            targetLines: (tgtStart, tgtEnd),
            matchedLines: matched,
            score: candidate.score,
            effectiveDiffLines: effLines
        ))
        totalLinesMoved += matched
        totalEffectivelyChanged += effLines
    }

    return EffectiveDiffMoveReport(
        movesDetected: details.count,
        totalLinesMoved: totalLinesMoved,
        totalLinesEffectivelyChanged: totalEffectivelyChanged,
        moves: details
    )
}
