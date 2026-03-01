public enum LineClassification: String, Codable, Sendable, Equatable {
    case new
    case moved
    case changedInMove
    case removed
    case movedRemoval
    case context
}

public struct ClassifiedDiffLine: Codable, Sendable, Equatable {
    public let content: String
    public let rawLine: String
    public let lineType: DiffLineType
    public let classification: LineClassification
    public let newLineNumber: Int?
    public let oldLineNumber: Int?
    public let filePath: String

    public init(
        content: String,
        rawLine: String,
        lineType: DiffLineType,
        classification: LineClassification,
        newLineNumber: Int?,
        oldLineNumber: Int?,
        filePath: String
    ) {
        self.content = content
        self.rawLine = rawLine
        self.lineType = lineType
        self.classification = classification
        self.newLineNumber = newLineNumber
        self.oldLineNumber = oldLineNumber
        self.filePath = filePath
    }
}

// MARK: - ClassifiedHunk

public struct ClassifiedHunk: Codable, Sendable, Equatable {
    public let filePath: String
    public let oldStart: Int
    public let newStart: Int
    public let lines: [ClassifiedDiffLine]

    public init(filePath: String, oldStart: Int, newStart: Int, lines: [ClassifiedDiffLine]) {
        self.filePath = filePath
        self.oldStart = oldStart
        self.newStart = newStart
        self.lines = lines
    }

    /// True when every non-context line is part of a move (no genuinely new or removed code).
    public var isMoved: Bool {
        let changedLines = lines.filter { $0.classification != .context }
        guard !changedLines.isEmpty else { return false }
        return changedLines.allSatisfy { $0.classification == .moved || $0.classification == .movedRemoval }
    }

    public var hasNewCode: Bool {
        lines.contains { $0.classification == .new }
    }

    public var hasChangesInMove: Bool {
        lines.contains { $0.classification == .changedInMove }
    }

    public var newCodeLines: [ClassifiedDiffLine] {
        lines.filter { $0.classification == .new }
    }

    public var changedLines: [ClassifiedDiffLine] {
        lines.filter { $0.classification == .new || $0.classification == .removed || $0.classification == .changedInMove }
    }
}

/// Extract lines classified as `.new` or `.changedInMove` across all hunks.
///
/// These are lines the PR author wrote — genuinely new additions and
/// modifications inside moved blocks. Excludes verbatim moves, removals, and context.
public func extractNewAndChangedInMoveLines(from hunks: [ClassifiedHunk]) -> [ClassifiedDiffLine] {
    hunks.flatMap { hunk in
        hunk.lines.filter { $0.classification == .new || $0.classification == .changedInMove }
    }
}

/// Group a flat list of classified lines back into hunk-level containers.
///
/// Uses the original diff's hunk structure to determine boundaries — each original hunk's
/// non-header line count determines how many classified lines belong to it.
public func groupIntoClassifiedHunks(
    originalDiff: GitDiff,
    classifiedLines: [ClassifiedDiffLine]
) -> [ClassifiedHunk] {
    var result: [ClassifiedHunk] = []
    var lineIndex = 0

    for hunk in originalDiff.hunks {
        let contentLineCount = hunk.getDiffLines().filter { $0.lineType != .header }.count
        let endIndex = min(lineIndex + contentLineCount, classifiedLines.count)
        let hunkLines = Array(classifiedLines[lineIndex..<endIndex])
        lineIndex = endIndex

        result.append(ClassifiedHunk(
            filePath: hunk.filePath,
            oldStart: hunk.oldStart,
            newStart: hunk.newStart,
            lines: hunkLines
        ))
    }

    return result
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
    // Build lookup sets from effective diff results
    var sourceMovedLines: [String: Set<Int>] = [:]
    var targetMovedLines: [String: Set<Int>] = [:]
    var changedInMoveLines: [String: Set<Int>] = [:]

    for result in effectiveResults {
        let candidate = result.candidate

        for line in candidate.removedLines {
            sourceMovedLines[candidate.sourceFile, default: []].insert(line.lineNumber)
        }

        for line in candidate.addedLines {
            targetMovedLines[candidate.targetFile, default: []].insert(line.lineNumber)
        }

        // Extract added lines from re-diff hunks, mapping back to absolute target file coordinates
        let ranges = extendBlockRange(candidate)
        let regionStart = ranges.target.start

        for hunk in result.hunks {
            for diffLine in hunk.getDiffLines() {
                if diffLine.lineType == .added, let relativeLineNum = diffLine.newLineNumber {
                    let absoluteLineNum = regionStart + relativeLineNum - 1
                    changedInMoveLines[candidate.targetFile, default: []].insert(absoluteLineNum)
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

            switch diffLine.lineType {
            case .removed:
                if let oldNum = diffLine.oldLineNumber,
                   sourceMovedLines[hunk.filePath]?.contains(oldNum) == true {
                    classification = .movedRemoval
                } else {
                    classification = .removed
                }

            case .added:
                if let newNum = diffLine.newLineNumber,
                   changedInMoveLines[hunk.filePath]?.contains(newNum) == true {
                    classification = .changedInMove
                } else if let newNum = diffLine.newLineNumber,
                          targetMovedLines[hunk.filePath]?.contains(newNum) == true {
                    classification = .moved
                } else {
                    classification = .new
                }

            case .context:
                classification = .context

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
                filePath: hunk.filePath
            ))
        }
    }

    return classified
}
