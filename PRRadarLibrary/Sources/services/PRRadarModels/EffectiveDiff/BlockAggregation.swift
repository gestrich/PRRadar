import Foundation

public let defaultGapTolerance = 3
public let defaultMinBlockSize = 3
public let defaultMinScore = 0.0

// MARK: - Data Structures

public struct MoveCandidate: Sendable, Equatable {
    public let removedLines: [TaggedLine]
    public let addedLines: [TaggedLine]
    public let score: Double
    public let sourceFile: String
    public let targetFile: String
    public let sourceStartLine: Int
    public let targetStartLine: Int

    public init(
        removedLines: [TaggedLine],
        addedLines: [TaggedLine],
        score: Double,
        sourceFile: String,
        targetFile: String,
        sourceStartLine: Int,
        targetStartLine: Int
    ) {
        self.removedLines = removedLines
        self.addedLines = addedLines
        self.score = score
        self.sourceFile = sourceFile
        self.targetFile = targetFile
        self.sourceStartLine = sourceStartLine
        self.targetStartLine = targetStartLine
    }
}

// MARK: - Block Grouping

private struct GroupKey: Hashable {
    let sourceFile: String
    let targetFile: String
}

public func groupMatchesIntoBlocks(
    _ matches: [LineMatch],
    gapTolerance: Int = defaultGapTolerance
) -> [[LineMatch]] {
    let moveMatches = matches.filter { $0.distance > 0 }
    guard !moveMatches.isEmpty else { return [] }

    var groups: [GroupKey: [LineMatch]] = [:]
    for match in moveMatches {
        let key = GroupKey(sourceFile: match.removed.filePath, targetFile: match.added.filePath)
        groups[key, default: []].append(match)
    }

    var blocks: [[LineMatch]] = []

    for (_, group) in groups {
        let sorted = group.sorted { $0.removed.lineNumber < $1.removed.lineNumber }

        var currentBlock: [LineMatch] = [sorted[0]]

        for match in sorted.dropFirst() {
            let gap = match.removed.lineNumber - currentBlock.last!.removed.lineNumber - 1
            if gap <= gapTolerance {
                currentBlock.append(match)
            } else {
                blocks.append(currentBlock)
                currentBlock = [match]
            }
        }
        blocks.append(currentBlock)
    }

    return blocks
}

// MARK: - Scoring

public func computeSizeFactor(_ block: [LineMatch], minBlockSize: Int = defaultMinBlockSize) -> Double {
    let size = block.count
    if size < minBlockSize { return 0.0 }
    let maxSize = 10
    if size >= maxSize { return 1.0 }
    return Double(size - minBlockSize + 1) / Double(maxSize - minBlockSize + 1)
}

public func computeLineUniqueness(_ block: [LineMatch], allAddedLines: [TaggedLine]) -> Double {
    var freq: [String: Int] = [:]
    for line in allAddedLines {
        guard !line.normalized.isEmpty else { continue }
        freq[line.normalized, default: 0] += 1
    }

    var scores: [Double] = []
    for match in block {
        let norm = match.removed.normalized
        guard !norm.isEmpty else { continue }
        let count = freq[norm, default: 1]
        scores.append(1.0 / Double(count))
    }

    guard !scores.isEmpty else { return 0.0 }
    return scores.reduce(0, +) / Double(scores.count)
}

public func computeMatchConsistency(_ block: [LineMatch]) -> Double {
    guard block.count > 1 else { return 1.0 }

    let targetLineNumbers = block.map { Double($0.added.lineNumber) }
    let mean = targetLineNumbers.reduce(0, +) / Double(targetLineNumbers.count)
    let variance = targetLineNumbers.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        / Double(targetLineNumbers.count - 1)
    let stddev = sqrt(variance)

    let span = Double((targetLineNumbers.map { Int($0) }.max()!) - (targetLineNumbers.map { Int($0) }.min()!) + 1)
    if span == 0 { return 1.0 }

    let expectedStddev = span / (2 * 1.732)
    if expectedStddev == 0 { return 1.0 }

    let ratio = stddev / expectedStddev
    if ratio <= 1.0 { return 1.0 }
    return 1.0 / ratio
}

public func computeDistanceFactor(_ block: [LineMatch]) -> Double {
    let avgDistance = Double(block.reduce(0) { $0 + $1.distance }) / Double(block.count)
    if avgDistance == 0 { return 0.0 }
    return min(1.0, avgDistance * 0.5)
}

public func scoreBlock(_ block: [LineMatch], allAddedLines: [TaggedLine]) -> Double {
    let size = computeSizeFactor(block)
    if size == 0.0 { return 0.0 }

    let uniqueness = computeLineUniqueness(block, allAddedLines: allAddedLines)
    let consistency = computeMatchConsistency(block)
    let distance = computeDistanceFactor(block)

    return size * uniqueness * consistency * distance
}

// MARK: - Move Candidate Discovery

public func findMoveCandidates(
    matches: [LineMatch],
    allAddedLines: [TaggedLine],
    gapTolerance: Int = defaultGapTolerance,
    minBlockSize: Int = defaultMinBlockSize,
    minScore: Double = defaultMinScore
) -> [MoveCandidate] {
    let blocks = groupMatchesIntoBlocks(matches, gapTolerance: gapTolerance)

    var candidates: [MoveCandidate] = []
    for block in blocks {
        guard block.count >= minBlockSize else { continue }

        let score = scoreBlock(block, allAddedLines: allAddedLines)
        guard score >= minScore else { continue }

        let removedLines = block.map(\.removed)
        let addedLines = block.map(\.added)

        candidates.append(MoveCandidate(
            removedLines: removedLines,
            addedLines: addedLines,
            score: score,
            sourceFile: block[0].removed.filePath,
            targetFile: block[0].added.filePath,
            sourceStartLine: removedLines[0].lineNumber,
            targetStartLine: addedLines[0].lineNumber
        ))
    }

    candidates.sort { $0.score > $1.score }
    return candidates
}
