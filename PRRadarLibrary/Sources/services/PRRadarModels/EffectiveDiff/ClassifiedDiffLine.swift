// MARK: - Counterpart

public struct Counterpart: Codable, Sendable, Equatable {
    public let filePath: String
    public let lineNumber: Int?

    public init(filePath: String, lineNumber: Int?) {
        self.filePath = filePath
        self.lineNumber = lineNumber
    }
}

// MARK: - ContentChange

public enum ContentChange: String, Codable, Sendable, Equatable {
    case unchanged
    case added
    case deleted
    case modified
}

// MARK: - Pairing

public struct Pairing: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable, Equatable {
        case before  // old/removed side
        case after   // new/added side
    }
    public let role: Role
    public let counterpart: Counterpart

    public init(role: Role, counterpart: Counterpart) {
        self.role = role
        self.counterpart = counterpart
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
/// then walks the original diff to assign each line a `ContentChange` and optional `Pairing`.
func classifyLines(
    originalDiff: GitDiff,
    effectiveResults: [EffectiveDiffResult]
) -> [PRLine] {
    let pairedMods = buildPairedModifications(from: originalDiff)

    var sourceMovedLines: [String: Set<Int>] = [:]
    var targetMovedLines: [String: Set<Int>] = [:]
    var addedInMoveLines: [String: Set<Int>] = [:]
    var changedInMoveLines: [String: Set<Int>] = [:]
    var changedSourceLines: [String: [Int: ContentChange]] = [:]

    var targetFileForSourceLine: [String: [Int: String]] = [:]
    var sourceFileForTargetLine: [String: [Int: String]] = [:]

    for result in effectiveResults {
        let candidate = result.candidate

        for line in candidate.removedLines {
            sourceMovedLines[candidate.sourceFile, default: []].insert(line.lineNumber)
            targetFileForSourceLine[candidate.sourceFile, default: [:]][line.lineNumber] = candidate.targetFile
        }
        for line in candidate.addedLines {
            targetMovedLines[candidate.targetFile, default: []].insert(line.lineNumber)
            sourceFileForTargetLine[candidate.targetFile, default: [:]][line.lineNumber] = candidate.sourceFile
        }

        for lineNum in result.rediffAnalysis.addedInMoveLines {
            addedInMoveLines[candidate.targetFile, default: []].insert(lineNum)
            sourceFileForTargetLine[candidate.targetFile, default: [:]][lineNum] = candidate.sourceFile
        }
        for lineNum in result.rediffAnalysis.changedInMoveLines {
            changedInMoveLines[candidate.targetFile, default: []].insert(lineNum)
            sourceFileForTargetLine[candidate.targetFile, default: [:]][lineNum] = candidate.sourceFile
        }
        for (lineNum, contentChange) in result.rediffAnalysis.changedSourceLines {
            changedSourceLines[candidate.sourceFile, default: [:]][lineNum] = contentChange
        }
    }

    var classified: [PRLine] = []

    for hunk in originalDiff.hunks {
        for diffLine in hunk.getDiffLines() {
            guard diffLine.lineType != .header else { continue }

            let contentChange: ContentChange
            let pairing: Pairing?

            switch diffLine.lineType {
            case .removed:
                if let oldNum = diffLine.oldLineNumber,
                   sourceMovedLines[hunk.filePath]?.contains(oldNum) == true {
                    let targetFile = targetFileForSourceLine[hunk.filePath]?[oldNum] ?? hunk.filePath
                    switch changedSourceLines[hunk.filePath]?[oldNum] {
                    case .modified:
                        contentChange = .modified
                        pairing = Pairing(role: .before, counterpart: Counterpart(filePath: targetFile, lineNumber: nil))
                    case .deleted:
                        contentChange = .deleted
                        pairing = nil
                    case .added, .unchanged, nil:
                        // Verbatim move source — content unchanged, has counterpart
                        contentChange = .unchanged
                        pairing = Pairing(role: .before, counterpart: Counterpart(filePath: targetFile, lineNumber: nil))
                    }
                } else if let oldNum = diffLine.oldLineNumber,
                          let paired = pairedMods.byOldLine[hunk.filePath]?[oldNum] {
                    contentChange = .modified
                    pairing = Pairing(role: .before, counterpart: Counterpart(filePath: hunk.filePath, lineNumber: paired.counterpartLineNumber))
                } else {
                    contentChange = .deleted
                    pairing = nil
                }

            case .added:
                if let newNum = diffLine.newLineNumber,
                   addedInMoveLines[hunk.filePath]?.contains(newNum) == true {
                    contentChange = .added
                    pairing = nil
                } else if let newNum = diffLine.newLineNumber,
                          changedInMoveLines[hunk.filePath]?.contains(newNum) == true {
                    let sourceFile = sourceFileForTargetLine[hunk.filePath]?[newNum] ?? hunk.filePath
                    contentChange = .modified
                    pairing = Pairing(role: .after, counterpart: Counterpart(filePath: sourceFile, lineNumber: nil))
                } else if let newNum = diffLine.newLineNumber,
                          targetMovedLines[hunk.filePath]?.contains(newNum) == true {
                    let sourceFile = sourceFileForTargetLine[hunk.filePath]?[newNum] ?? hunk.filePath
                    contentChange = .unchanged
                    pairing = Pairing(role: .after, counterpart: Counterpart(filePath: sourceFile, lineNumber: nil))
                } else if let newNum = diffLine.newLineNumber,
                          let paired = pairedMods.byNewLine[hunk.filePath]?[newNum] {
                    contentChange = .modified
                    pairing = Pairing(role: .after, counterpart: Counterpart(filePath: hunk.filePath, lineNumber: paired.counterpartLineNumber))
                } else {
                    contentChange = .added
                    pairing = nil
                }

            case .context:
                contentChange = .unchanged
                pairing = nil

            case .header:
                continue
            }

            classified.append(PRLine(
                content: diffLine.content,
                rawLine: diffLine.rawLine,
                diffType: diffLine.lineType,
                contentChange: contentChange,
                pairing: pairing,
                oldLineNumber: diffLine.oldLineNumber,
                newLineNumber: diffLine.newLineNumber,
                filePath: hunk.filePath
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
