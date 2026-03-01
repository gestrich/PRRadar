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

// MARK: - Reconstruction

/// Reconstruct the effective diff by filtering out moved lines using pre-computed classifications.
///
/// Lines classified as `.moved` or `.movedRemoval` are stripped. Remaining lines are split
/// at filtered-line boundaries into sub-hunks that preserve correct line numbers. Only
/// sub-hunks containing at least one changed line (added or removed) are kept.
public func reconstructEffectiveDiff(
    originalDiff: GitDiff,
    classifiedHunks: [ClassifiedHunk]
) -> GitDiff {
    var survivingHunks: [Hunk] = []

    for (originalHunk, classifiedHunk) in zip(originalDiff.hunks, classifiedHunks) {
        let hasMovedLines = classifiedHunk.lines.contains {
            $0.classification == .moved || $0.classification == .movedRemoval
        }

        if !hasMovedLines {
            survivingHunks.append(originalHunk)
            continue
        }

        let fileHeaderLines = originalHunk.getDiffLines()
            .filter { $0.lineType == .header && !$0.rawLine.hasPrefix("@@") }
            .map(\.rawLine)

        // Split into segments at moved-line boundaries
        var segments: [[ClassifiedDiffLine]] = []
        var current: [ClassifiedDiffLine] = []

        for line in classifiedHunk.lines {
            if line.classification != .moved && line.classification != .movedRemoval {
                current.append(line)
            } else {
                if !current.isEmpty {
                    segments.append(current)
                    current = []
                }
            }
        }
        if !current.isEmpty {
            segments.append(current)
        }

        for segment in segments {
            guard segment.contains(where: { $0.lineType == .added || $0.lineType == .removed }) else {
                continue
            }

            let oldStart = segment.compactMap(\.oldLineNumber).min() ?? originalHunk.oldStart
            let newStart = segment.compactMap(\.newLineNumber).min() ?? originalHunk.newStart
            let oldLength = segment.filter { $0.lineType == .removed || $0.lineType == .context }.count
            let newLength = segment.filter { $0.lineType == .added || $0.lineType == .context }.count

            let header = "@@ -\(oldStart),\(oldLength) +\(newStart),\(newLength) @@"
            let bodyRaw = segment.map(\.rawLine)
            let content = (fileHeaderLines + [header] + bodyRaw).joined(separator: "\n")

            survivingHunks.append(Hunk(
                filePath: originalHunk.filePath,
                content: content,
                rawHeader: originalHunk.rawHeader,
                oldStart: oldStart,
                oldLength: oldLength,
                newStart: newStart,
                newLength: newLength,
                renameFrom: originalHunk.renameFrom
            ))
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
