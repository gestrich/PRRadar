import Foundation

// MARK: - Move Report Models (algorithm-internal versions)

/// Details about a single detected code move (algorithm output).
/// Distinct from the `MoveDetail` in `DiffOutput.swift` which is the Codable serialization model.
struct EffectiveDiffMoveDetail: Sendable, Equatable {
    let sourceFile: String
    let targetFile: String
    let sourceLines: (start: Int, end: Int)
    let targetLines: (start: Int, end: Int)
    let matchedLines: Int
    let score: Double
    let effectiveDiffLines: Int

    init(
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

    static func == (lhs: EffectiveDiffMoveDetail, rhs: EffectiveDiffMoveDetail) -> Bool {
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

    func toMoveDetail() -> MoveDetail {
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
struct EffectiveDiffMoveReport: Sendable, Equatable {
    let movesDetected: Int
    let totalLinesMoved: Int
    let totalLinesEffectivelyChanged: Int
    let moves: [EffectiveDiffMoveDetail]

    init(
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

    func toMoveReport() -> MoveReport {
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

/// Reconstruct the effective diff by filtering out verbatim moved lines.
///
/// Lines with `contentChange == .unchanged && pairing != nil` are stripped (verbatim moves).
/// Lines in a moved block with `contentChange` of `.modified`, `.added`, or `.deleted`
/// survive — they represent actual content changes within the moved block.
/// Remaining lines are split at filtered-line boundaries into sub-hunks that preserve
/// correct line numbers. Only sub-hunks containing at least one changed line are kept.
func reconstructEffectiveDiff(
    originalDiff: GitDiff,
    prHunks: [PRHunk]
) -> GitDiff {
    var survivingHunks: [Hunk] = []

    for (originalHunk, prHunk) in zip(originalDiff.hunks, prHunks) {
        let hasMovedLines = prHunk.lines.contains {
            $0.contentChange == .unchanged && $0.pairing != nil
        }

        if !hasMovedLines {
            survivingHunks.append(originalHunk)
            continue
        }

        let fileHeaderLines = originalHunk.getDiffLines()
            .filter { $0.lineType == .header && !$0.rawLine.hasPrefix("@@") }
            .map(\.rawLine)

        var segments: [[PRLine]] = []
        var current: [PRLine] = []

        for line in prHunk.lines {
            if !(line.contentChange == .unchanged && line.pairing != nil) {
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
            guard segment.contains(where: { $0.diffType == .added || $0.diffType == .removed }) else {
                continue
            }

            let oldStart = segment.compactMap(\.oldLineNumber).min() ?? originalHunk.oldStart
            let newStart = segment.compactMap(\.newLineNumber).min() ?? originalHunk.newStart
            let oldLength = segment.filter { $0.diffType == .removed || $0.diffType == .context }.count
            let newLength = segment.filter { $0.diffType == .added || $0.diffType == .context }.count

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

func buildMoveReport(
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
