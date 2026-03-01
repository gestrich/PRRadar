public enum LineClassification: String, Codable, Sendable {
    case new
    case moved
    case changedInMove
    case removed
    case movedRemoval
    case context
}

public struct ClassifiedDiffLine: Sendable {
    public let content: String
    public let rawLine: String
    public let lineType: DiffLineType
    public let classification: LineClassification
    public let newLineNumber: Int?
    public let oldLineNumber: Int?
    public let filePath: String
    public let moveCandidate: MoveCandidate?

    public init(
        content: String,
        rawLine: String,
        lineType: DiffLineType,
        classification: LineClassification,
        newLineNumber: Int?,
        oldLineNumber: Int?,
        filePath: String,
        moveCandidate: MoveCandidate?
    ) {
        self.content = content
        self.rawLine = rawLine
        self.lineType = lineType
        self.classification = classification
        self.newLineNumber = newLineNumber
        self.oldLineNumber = oldLineNumber
        self.filePath = filePath
        self.moveCandidate = moveCandidate
    }
}

// MARK: - Line Classification

/// Classify every content line in the original diff using effective diff results.
///
/// Builds lookup sets from the move candidates and re-diff hunks, then walks the
/// original diff to assign each line a `LineClassification`:
/// - `.movedRemoval` — removed line that is the source side of a detected move
/// - `.moved` — added line that is the target side of a detected move (content unchanged)
/// - `.changedInMove` — added line inside a moved block that differs from the source
/// - `.new` — genuinely new added line, not part of any move
/// - `.removed` — genuinely deleted line, not part of any move
/// - `.context` — unchanged context line
public func classifyLines(
    originalDiff: GitDiff,
    effectiveResults: [EffectiveDiffResult]
) -> [ClassifiedDiffLine] {
    // Build lookup sets from effective diff results (same data as reconstructEffectiveDiff)
    var sourceMovedLines: [String: Set<Int>] = [:]
    var targetMovedLines: [String: Set<Int>] = [:]
    var sourceLineCandidates: [String: [Int: MoveCandidate]] = [:]
    var targetLineCandidates: [String: [Int: MoveCandidate]] = [:]

    // Lines that changed within a moved block (from re-diff added lines)
    var changedInMoveLines: [String: Set<Int>] = [:]
    var changedInMoveCandidates: [String: [Int: MoveCandidate]] = [:]

    for result in effectiveResults {
        let candidate = result.candidate

        for line in candidate.removedLines {
            sourceMovedLines[candidate.sourceFile, default: []].insert(line.lineNumber)
            sourceLineCandidates[candidate.sourceFile, default: [:]][line.lineNumber] = candidate
        }

        for line in candidate.addedLines {
            targetMovedLines[candidate.targetFile, default: []].insert(line.lineNumber)
            targetLineCandidates[candidate.targetFile, default: [:]][line.lineNumber] = candidate
        }

        // Extract added lines from re-diff hunks, mapping back to absolute target file coordinates
        let ranges = extendBlockRange(candidate)
        let regionStart = ranges.target.start

        for hunk in result.hunks {
            for diffLine in hunk.getDiffLines() {
                if diffLine.lineType == .added, let relativeLineNum = diffLine.newLineNumber {
                    let absoluteLineNum = regionStart + relativeLineNum - 1
                    changedInMoveLines[candidate.targetFile, default: []].insert(absoluteLineNum)
                    changedInMoveCandidates[candidate.targetFile, default: [:]][absoluteLineNum] = candidate
                }
            }
        }
    }

    // Classify each content line from the original diff
    var classified: [ClassifiedDiffLine] = []

    for hunk in originalDiff.hunks {
        for diffLine in hunk.getDiffLines() {
            guard diffLine.lineType != .header else { continue }

            let classification: LineClassification
            let moveCandidate: MoveCandidate?

            switch diffLine.lineType {
            case .removed:
                if let oldNum = diffLine.oldLineNumber,
                   sourceMovedLines[hunk.filePath]?.contains(oldNum) == true {
                    classification = .movedRemoval
                    moveCandidate = sourceLineCandidates[hunk.filePath]?[oldNum]
                } else {
                    classification = .removed
                    moveCandidate = nil
                }

            case .added:
                if let newNum = diffLine.newLineNumber,
                   changedInMoveLines[hunk.filePath]?.contains(newNum) == true {
                    classification = .changedInMove
                    moveCandidate = changedInMoveCandidates[hunk.filePath]?[newNum]
                } else if let newNum = diffLine.newLineNumber,
                          targetMovedLines[hunk.filePath]?.contains(newNum) == true {
                    classification = .moved
                    moveCandidate = targetLineCandidates[hunk.filePath]?[newNum]
                } else {
                    classification = .new
                    moveCandidate = nil
                }

            case .context:
                classification = .context
                moveCandidate = nil

            case .header:
                continue
            }

            classified.append(ClassifiedDiffLine(
                content: diffLine.content,
                rawLine: diffLine.rawLine,
                lineType: diffLine.lineType,
                classification: classification,
                newLineNumber: diffLine.newLineNumber,
                oldLineNumber: diffLine.oldLineNumber,
                filePath: hunk.filePath,
                moveCandidate: moveCandidate
            ))
        }
    }

    return classified
}
