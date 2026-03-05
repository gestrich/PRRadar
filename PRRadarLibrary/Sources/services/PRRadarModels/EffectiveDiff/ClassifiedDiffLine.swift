// MARK: - Counterpart

public struct Counterpart: Codable, Sendable, Equatable {
    public let filePath: String
    public let lineNumber: Int?

    public init(filePath: String, lineNumber: Int?) {
        self.filePath = filePath
        self.lineNumber = lineNumber
    }
}

// MARK: - ChangeKind

public enum ChangeKind: Sendable, Equatable {
    /// Genuinely new line (no counterpart on the old side).
    case new
    /// Genuinely deleted line (no counterpart on the new side).
    case deleted
    /// Old version of an in-place modification — counterpart points to the `+` side.
    case replaced(counterpart: Counterpart)
    /// New version of an in-place modification — counterpart points to the `-` side.
    case replacement(counterpart: Counterpart)
    /// No meaningful change: context line, verbatim move source/destination, or whitespace-only modification.
    case context
}

extension ChangeKind: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case counterpart
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "new":
            self = .new
        case "deleted":
            self = .deleted
        case "replaced":
            let c = try container.decode(Counterpart.self, forKey: .counterpart)
            self = .replaced(counterpart: c)
        case "replacement":
            let c = try container.decode(Counterpart.self, forKey: .counterpart)
            self = .replacement(counterpart: c)
        default:
            self = .context
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .new:
            try container.encode("new", forKey: .type)
        case .deleted:
            try container.encode("deleted", forKey: .type)
        case .replaced(let c):
            try container.encode("replaced", forKey: .type)
            try container.encode(c, forKey: .counterpart)
        case .replacement(let c):
            try container.encode("replacement", forKey: .type)
            try container.encode(c, forKey: .counterpart)
        case .context:
            try container.encode("context", forKey: .type)
        }
    }
}

extension ChangeKind {
    public var isReplaced: Bool {
        if case .replaced = self { return true }
        return false
    }

    public var isReplacement: Bool {
        if case .replacement = self { return true }
        return false
    }

    public var counterpart: Counterpart? {
        switch self {
        case .replaced(let c), .replacement(let c): return c
        default: return nil
        }
    }

    public var description: String {
        switch self {
        case .new: return "new"
        case .deleted: return "deleted"
        case .replaced: return "replaced"
        case .replacement: return "replacement"
        case .context: return "context"
        }
    }
}

/// Group a flat list of classified lines back into hunk-level containers.
///
/// Uses the original diff's hunk structure to determine boundaries — each original hunk's
/// non-header line count determines how many classified lines belong to it.
func groupIntoPRHunks(
    originalDiff: GitDiff,
    classifiedLines: [PRLine]
) -> [PRHunk] {
    var result: [PRHunk] = []
    var lineIndex = 0

    for hunk in originalDiff.hunks {
        let contentLineCount = hunk.getDiffLines().filter { $0.lineType != .header }.count
        let endIndex = min(lineIndex + contentLineCount, classifiedLines.count)
        let hunkLines = Array(classifiedLines[lineIndex..<endIndex])
        lineIndex = endIndex

        result.append(PRHunk(
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
/// then walks the original diff to assign each line a classification as a `PRLine`
/// with `MoveInfo` baked in.
func classifyLines(
    originalDiff: GitDiff,
    effectiveResults: [EffectiveDiffResult]
) -> [PRLine] {
    let pairedMods = buildPairedModifications(from: originalDiff)

    var sourceMovedLines: [String: Set<Int>] = [:]
    var targetMovedLines: [String: Set<Int>] = [:]
    var addedInMoveLines: [String: Set<Int>] = [:]
    var changedInMoveLines: [String: Set<Int>] = [:]
    var changedSourceLines: [String: [Int: ChangeKind]] = [:]

    // Map (filePath, lineNumber) → MoveInfo for moved lines
    var sourceMoveInfoLookup: [String: [Int: MoveInfo]] = [:]
    var targetMoveInfoLookup: [String: [Int: MoveInfo]] = [:]

    for result in effectiveResults {
        let candidate = result.candidate
        let sourceMoveInfo = MoveInfo(sourceFile: candidate.sourceFile, targetFile: candidate.targetFile, isSource: true)
        let targetMoveInfo = MoveInfo(sourceFile: candidate.sourceFile, targetFile: candidate.targetFile, isSource: false)

        for line in candidate.removedLines {
            sourceMovedLines[candidate.sourceFile, default: []].insert(line.lineNumber)
            sourceMoveInfoLookup[candidate.sourceFile, default: [:]][line.lineNumber] = sourceMoveInfo
        }
        for line in candidate.addedLines {
            targetMovedLines[candidate.targetFile, default: []].insert(line.lineNumber)
            targetMoveInfoLookup[candidate.targetFile, default: [:]][line.lineNumber] = targetMoveInfo
        }

        for lineNum in result.rediffAnalysis.addedInMoveLines {
            addedInMoveLines[candidate.targetFile, default: []].insert(lineNum)
            targetMoveInfoLookup[candidate.targetFile, default: [:]][lineNum] = targetMoveInfo
        }
        for lineNum in result.rediffAnalysis.changedInMoveLines {
            changedInMoveLines[candidate.targetFile, default: []].insert(lineNum)
            targetMoveInfoLookup[candidate.targetFile, default: [:]][lineNum] = targetMoveInfo
        }
        for (lineNum, kind) in result.rediffAnalysis.changedSourceLines {
            changedSourceLines[candidate.sourceFile, default: [:]][lineNum] = kind
        }
    }

    var classified: [PRLine] = []

    for hunk in originalDiff.hunks {
        for diffLine in hunk.getDiffLines() {
            guard diffLine.lineType != .header else { continue }

            let changeKind: ChangeKind
            var moveInfo: MoveInfo?

            switch diffLine.lineType {
            case .removed:
                if let oldNum = diffLine.oldLineNumber,
                   sourceMovedLines[hunk.filePath]?.contains(oldNum) == true {
                    moveInfo = sourceMoveInfoLookup[hunk.filePath]?[oldNum]
                    // changedSourceLines now returns .replaced(counterpart:) or .deleted;
                    // default to .context for verbatim moves (no entry in changedSourceLines)
                    changeKind = changedSourceLines[hunk.filePath]?[oldNum] ?? .context
                } else {
                    changeKind = .deleted
                    moveInfo = nil
                }

            case .added:
                if let newNum = diffLine.newLineNumber,
                   addedInMoveLines[hunk.filePath]?.contains(newNum) == true {
                    changeKind = .new
                    moveInfo = targetMoveInfoLookup[hunk.filePath]?[newNum]
                } else if let newNum = diffLine.newLineNumber,
                          changedInMoveLines[hunk.filePath]?.contains(newNum) == true {
                    let moveInfoForLine = targetMoveInfoLookup[hunk.filePath]?[newNum]
                    moveInfo = moveInfoForLine
                    let sourceFile = moveInfoForLine?.sourceFile ?? hunk.filePath
                    changeKind = .replacement(counterpart: Counterpart(filePath: sourceFile, lineNumber: nil))
                } else if let newNum = diffLine.newLineNumber,
                          targetMovedLines[hunk.filePath]?.contains(newNum) == true {
                    changeKind = .context
                    moveInfo = targetMoveInfoLookup[hunk.filePath]?[newNum]
                } else {
                    changeKind = .new
                    moveInfo = nil
                }

            case .context:
                changeKind = .context
                moveInfo = nil

            case .header:
                continue
            }

            classified.append(PRLine(
                content: diffLine.content,
                rawLine: diffLine.rawLine,
                diffType: diffLine.lineType,
                changeKind: changeKind,
                oldLineNumber: diffLine.oldLineNumber,
                newLineNumber: diffLine.newLineNumber,
                filePath: hunk.filePath,
                move: moveInfo,
                verbatimMoveCounterpart: nil
            ))
        }
    }

    return classified
}

// MARK: - Paired Modification Detection

struct PairedModification {
    let counterpartLineNumber: Int
}

/// Detects in-place `-`/`+` pairs within each hunk via sequential positional pairing.
///
/// Scans each hunk for contiguous blocks of removed and added lines ("change groups").
/// Within each group, pairs removed[i]↔added[i] in order. Surplus lines when counts
/// differ remain unpaired and are not included in the result.
///
/// Returns two lookups:
/// - `byOldLine`: filePath → oldLineNumber → pairing info for removed lines
/// - `byNewLine`: filePath → newLineNumber → pairing info for added lines
func buildPairedModifications(from diff: GitDiff) -> (byOldLine: [String: [Int: PairedModification]], byNewLine: [String: [Int: PairedModification]]) {
    var byOldLine: [String: [Int: PairedModification]] = [:]
    var byNewLine: [String: [Int: PairedModification]] = [:]

    for hunk in diff.hunks {
        let lines = hunk.getDiffLines().filter { $0.lineType != .header }
        var i = 0
        while i < lines.count {
            guard lines[i].lineType == .removed || lines[i].lineType == .added else {
                i += 1
                continue
            }

            var removedInGroup: [DiffLine] = []
            var addedInGroup: [DiffLine] = []

            while i < lines.count && (lines[i].lineType == .removed || lines[i].lineType == .added) {
                switch lines[i].lineType {
                case .removed: removedInGroup.append(lines[i])
                case .added: addedInGroup.append(lines[i])
                default: break
                }
                i += 1
            }

            let pairCount = min(removedInGroup.count, addedInGroup.count)
            for j in 0..<pairCount {
                let removed = removedInGroup[j]
                let added = addedInGroup[j]
                guard let oldNum = removed.oldLineNumber, let newNum = added.newLineNumber else { continue }

                byOldLine[hunk.filePath, default: [:]][oldNum] = PairedModification(counterpartLineNumber: newNum)
                byNewLine[hunk.filePath, default: [:]][newNum] = PairedModification(counterpartLineNumber: oldNum)
            }
        }
    }

    return (byOldLine: byOldLine, byNewLine: byNewLine)
}
