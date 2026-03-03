public enum ChangeKind: String, Codable, Sendable, Equatable {
    case added
    case changed
    case removed
    case unchanged
}

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
    public let changeKind: ChangeKind
    public let inMovedBlock: Bool
    public let newLineNumber: Int?
    public let oldLineNumber: Int?
    public let filePath: String

    public init(
        content: String,
        rawLine: String,
        lineType: DiffLineType,
        classification: LineClassification,
        changeKind: ChangeKind,
        inMovedBlock: Bool,
        newLineNumber: Int?,
        oldLineNumber: Int?,
        filePath: String
    ) {
        self.content = content
        self.rawLine = rawLine
        self.lineType = lineType
        self.classification = classification
        self.changeKind = changeKind
        self.inMovedBlock = inMovedBlock
        self.newLineNumber = newLineNumber
        self.oldLineNumber = oldLineNumber
        self.filePath = filePath
    }

    /// Backward-compatible initializer that derives changeKind/inMovedBlock from the old classification.
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

        switch classification {
        case .new:
            self.changeKind = .added
            self.inMovedBlock = false
        case .moved:
            self.changeKind = .unchanged
            self.inMovedBlock = true
        case .changedInMove:
            self.changeKind = .changed
            self.inMovedBlock = true
        case .removed:
            self.changeKind = .removed
            self.inMovedBlock = false
        case .movedRemoval:
            self.changeKind = .unchanged
            self.inMovedBlock = true
        case .context:
            self.changeKind = .unchanged
            self.inMovedBlock = false
        }
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
        let nonContext = lines.filter { $0.lineType != .context }
        guard !nonContext.isEmpty else { return false }
        return nonContext.allSatisfy { $0.inMovedBlock && $0.changeKind == .unchanged }
    }

    public var hasNewCode: Bool {
        lines.contains { $0.changeKind == .added }
    }

    public var hasChangesInMove: Bool {
        lines.contains { $0.changeKind == .changed && $0.inMovedBlock }
    }

    public var newCodeLines: [ClassifiedDiffLine] {
        lines.filter { $0.changeKind == .added }
    }

    public var changedLines: [ClassifiedDiffLine] {
        lines.filter { $0.changeKind != .unchanged }
    }

    /// Filter classified hunks to only include lines within a focus area's file and line range.
    public static func filterForFocusArea(
        _ hunks: [ClassifiedHunk],
        focusArea: FocusArea
    ) -> [ClassifiedHunk] {
        hunks.compactMap { hunk in
            guard hunk.filePath == focusArea.filePath else { return nil }
            let filteredLines = hunk.lines.filter { line in
                guard let lineNum = line.newLineNumber ?? line.oldLineNumber else { return false }
                return lineNum >= focusArea.startLine && lineNum <= focusArea.endLine
            }
            guard !filteredLines.isEmpty else { return nil }
            return ClassifiedHunk(
                filePath: hunk.filePath,
                oldStart: hunk.oldStart,
                newStart: hunk.newStart,
                lines: filteredLines
            )
        }
    }
}

/// Extract lines with `changeKind` of `.added` or `.changed` across all hunks.
///
/// These are lines the PR author wrote — genuinely new additions and
/// modifications inside moved blocks. Excludes verbatim moves, removals, and context.
public func extractNewAndChangedInMoveLines(from hunks: [ClassifiedHunk]) -> [ClassifiedDiffLine] {
    hunks.flatMap { hunk in
        hunk.lines.filter { $0.changeKind == .added || $0.changeKind == .changed }
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
/// Builds lookup sets from the move candidates and pre-computed re-diff analysis,
/// then walks the original diff to assign each line a classification.
public func classifyLines(
    originalDiff: GitDiff,
    effectiveResults: [EffectiveDiffResult]
) -> [ClassifiedDiffLine] {
    var sourceMovedLines: [String: Set<Int>] = [:]
    var targetMovedLines: [String: Set<Int>] = [:]
    var addedInMoveLines: [String: Set<Int>] = [:]
    var changedInMoveLines: [String: Set<Int>] = [:]
    var changedSourceLines: [String: [Int: ChangeKind]] = [:]

    for result in effectiveResults {
        let candidate = result.candidate

        for line in candidate.removedLines {
            sourceMovedLines[candidate.sourceFile, default: []].insert(line.lineNumber)
        }
        for line in candidate.addedLines {
            targetMovedLines[candidate.targetFile, default: []].insert(line.lineNumber)
        }

        for lineNum in result.rediffAnalysis.addedInMoveLines {
            addedInMoveLines[candidate.targetFile, default: []].insert(lineNum)
        }
        for lineNum in result.rediffAnalysis.changedInMoveLines {
            changedInMoveLines[candidate.targetFile, default: []].insert(lineNum)
        }
        for (lineNum, kind) in result.rediffAnalysis.changedSourceLines {
            changedSourceLines[candidate.sourceFile, default: [:]][lineNum] = kind
        }
    }

    var classified: [ClassifiedDiffLine] = []

    for hunk in originalDiff.hunks {
        for diffLine in hunk.getDiffLines() {
            guard diffLine.lineType != .header else { continue }

            let classification: LineClassification
            let changeKind: ChangeKind
            let inMovedBlock: Bool

            switch diffLine.lineType {
            case .removed:
                if let oldNum = diffLine.oldLineNumber,
                   sourceMovedLines[hunk.filePath]?.contains(oldNum) == true {
                    classification = .movedRemoval
                    inMovedBlock = true
                    changeKind = changedSourceLines[hunk.filePath]?[oldNum] ?? .unchanged
                } else {
                    classification = .removed
                    changeKind = .removed
                    inMovedBlock = false
                }

            case .added:
                if let newNum = diffLine.newLineNumber,
                   addedInMoveLines[hunk.filePath]?.contains(newNum) == true {
                    classification = .changedInMove
                    changeKind = .added
                    inMovedBlock = true
                } else if let newNum = diffLine.newLineNumber,
                          changedInMoveLines[hunk.filePath]?.contains(newNum) == true {
                    classification = .changedInMove
                    changeKind = .changed
                    inMovedBlock = true
                } else if let newNum = diffLine.newLineNumber,
                          targetMovedLines[hunk.filePath]?.contains(newNum) == true {
                    classification = .moved
                    changeKind = .unchanged
                    inMovedBlock = true
                } else {
                    classification = .new
                    changeKind = .added
                    inMovedBlock = false
                }

            case .context:
                classification = .context
                changeKind = .unchanged
                inMovedBlock = false

            case .header:
                continue
            }

            classified.append(ClassifiedDiffLine(
                content: diffLine.content,
                rawLine: diffLine.rawLine,
                lineType: diffLine.lineType,
                classification: classification,
                changeKind: changeKind,
                inMovedBlock: inMovedBlock,
                newLineNumber: diffLine.newLineNumber,
                oldLineNumber: diffLine.oldLineNumber,
                filePath: hunk.filePath
            ))
        }
    }

    return classified
}
