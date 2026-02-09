import Foundation

// MARK: - Data Structures

public enum TaggedLineType: String, Sendable {
    case added
    case removed
}

public struct TaggedLine: Sendable, Equatable {
    public let content: String
    public let normalized: String
    public let filePath: String
    public let lineNumber: Int
    public let hunkIndex: Int
    public let lineType: TaggedLineType

    public init(
        content: String,
        normalized: String,
        filePath: String,
        lineNumber: Int,
        hunkIndex: Int,
        lineType: TaggedLineType
    ) {
        self.content = content
        self.normalized = normalized
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.hunkIndex = hunkIndex
        self.lineType = lineType
    }
}

public struct LineMatch: Sendable, Equatable {
    public let removed: TaggedLine
    public let added: TaggedLine
    public let distance: Int
    public let similarity: Double

    public init(removed: TaggedLine, added: TaggedLine, distance: Int, similarity: Double) {
        self.removed = removed
        self.added = added
        self.distance = distance
        self.similarity = similarity
    }
}

// MARK: - Functions

func normalize(_ line: String) -> String {
    line.trimmingCharacters(in: .whitespaces)
}

public func extractTaggedLines(from gitDiff: GitDiff) -> (removed: [TaggedLine], added: [TaggedLine]) {
    var removed: [TaggedLine] = []
    var added: [TaggedLine] = []

    for (hunkIndex, hunk) in gitDiff.hunks.enumerated() {
        for diffLine in hunk.getDiffLines() {
            if diffLine.lineType == .removed, let oldLineNumber = diffLine.oldLineNumber {
                removed.append(TaggedLine(
                    content: diffLine.content,
                    normalized: normalize(diffLine.content),
                    filePath: hunk.filePath,
                    lineNumber: oldLineNumber,
                    hunkIndex: hunkIndex,
                    lineType: .removed
                ))
            } else if diffLine.lineType == .added, let newLineNumber = diffLine.newLineNumber {
                added.append(TaggedLine(
                    content: diffLine.content,
                    normalized: normalize(diffLine.content),
                    filePath: hunk.filePath,
                    lineNumber: newLineNumber,
                    hunkIndex: hunkIndex,
                    lineType: .added
                ))
            }
        }
    }

    return (removed, added)
}

public func buildAddedIndex(_ addedLines: [TaggedLine]) -> [String: [Int]] {
    var index: [String: [Int]] = [:]
    for (i, line) in addedLines.enumerated() {
        guard !line.normalized.isEmpty else { continue }
        index[line.normalized, default: []].append(i)
    }
    return index
}

public func findExactMatches(
    removedLines: [TaggedLine],
    addedLines: [TaggedLine]
) -> [LineMatch] {
    let index = buildAddedIndex(addedLines)
    var matchedAdded: Set<Int> = []
    var matches: [LineMatch] = []

    for removed in removedLines {
        guard !removed.normalized.isEmpty else { continue }
        guard let candidateIndices = index[removed.normalized] else { continue }

        for idx in candidateIndices {
            guard !matchedAdded.contains(idx) else { continue }

            let added = addedLines[idx]
            let distance = abs(removed.hunkIndex - added.hunkIndex)
            matches.append(LineMatch(
                removed: removed,
                added: added,
                distance: distance,
                similarity: 1.0
            ))
            matchedAdded.insert(idx)
            break
        }
    }

    return matches
}
