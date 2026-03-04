public enum ChangeKind: String, Codable, Sendable, Equatable {
    case added
    case changed
    case removed
    case unchanged
}

/// Group a flat list of classified lines back into hunk-level containers.
///
/// Uses the original diff's hunk structure to determine boundaries — each original hunk's
/// non-header line count determines how many classified lines belong to it.
public func groupIntoPRHunks(
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
public func classifyLines(
    originalDiff: GitDiff,
    effectiveResults: [EffectiveDiffResult]
) -> [PRLine] {
    let whitespaceOnlyAdded = buildWhitespaceOnlySet(from: originalDiff)

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
                    changeKind = changedSourceLines[hunk.filePath]?[oldNum] ?? .unchanged
                } else {
                    changeKind = .removed
                    moveInfo = nil
                }

            case .added:
                if let newNum = diffLine.newLineNumber,
                   addedInMoveLines[hunk.filePath]?.contains(newNum) == true {
                    changeKind = .added
                    moveInfo = targetMoveInfoLookup[hunk.filePath]?[newNum]
                } else if let newNum = diffLine.newLineNumber,
                          changedInMoveLines[hunk.filePath]?.contains(newNum) == true {
                    changeKind = .changed
                    moveInfo = targetMoveInfoLookup[hunk.filePath]?[newNum]
                } else if let newNum = diffLine.newLineNumber,
                          targetMovedLines[hunk.filePath]?.contains(newNum) == true {
                    changeKind = .unchanged
                    moveInfo = targetMoveInfoLookup[hunk.filePath]?[newNum]
                } else if let newNum = diffLine.newLineNumber,
                          whitespaceOnlyAdded[hunk.filePath]?.contains(newNum) == true {
                    changeKind = .unchanged
                    moveInfo = nil
                } else {
                    changeKind = .added
                    moveInfo = nil
                }

            case .context:
                changeKind = .unchanged
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
                move: moveInfo
            ))
        }
    }

    return classified
}

// MARK: - Whitespace-Only Detection

/// Collapse all whitespace in a string so that `"* parentView"` and `"*parentView"` compare equal.
private func collapseWhitespace(_ s: String) -> String {
    s.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace).joined()
}

/// Scan each hunk for removed/added line pairs that differ only in whitespace.
///
/// Returns a per-file set of new-line numbers for added lines whose content is identical
/// to a removed line after collapsing all whitespace. These are whitespace-only modifications.
func buildWhitespaceOnlySet(from diff: GitDiff) -> [String: Set<Int>] {
    var result: [String: Set<Int>] = [:]

    for hunk in diff.hunks {
        let lines = hunk.getDiffLines()
        let removed = lines.filter { $0.lineType == .removed }
        let added = lines.filter { $0.lineType == .added }

        var removedByCollapsed: [String: [Int]] = [:]
        for r in removed {
            let key = collapseWhitespace(r.content)
            guard !key.isEmpty else { continue }
            removedByCollapsed[key, default: []].append(r.oldLineNumber ?? 0)
        }

        for a in added {
            let key = collapseWhitespace(a.content)
            guard !key.isEmpty else { continue }
            guard var indices = removedByCollapsed[key], !indices.isEmpty else { continue }
            indices.removeFirst()
            removedByCollapsed[key] = indices
            if let newNum = a.newLineNumber {
                result[hunk.filePath, default: []].insert(newNum)
            }
        }
    }

    return result
}
