import Foundation

public let defaultContextLines = 3
public let defaultTrimProximity = 3

// MARK: - Data Structures

public struct EffectiveDiffResult: Sendable, Equatable {
    public let candidate: MoveCandidate
    public let hunks: [Hunk]
    public let rawDiff: String

    public init(candidate: MoveCandidate, hunks: [Hunk], rawDiff: String) {
        self.candidate = candidate
        self.hunks = hunks
        self.rawDiff = rawDiff
    }
}

/// A function that re-diffs two text regions and returns raw unified diff output.
/// The algorithm needs `git diff --no-index` but `PRRadarModels` has no CLI dependency,
/// so callers inject the implementation.
public typealias RediffFunction = @Sendable (
    _ oldText: String,
    _ newText: String,
    _ oldLabel: String,
    _ newLabel: String
) async throws -> String

// MARK: - Functions

func extractLineRange(from fileContent: String, start: Int, end: Int) -> String {
    var lines = fileContent.components(separatedBy: "\n")
    // Drop trailing empty element from trailing newline (matches Python splitlines behavior)
    if lines.last == "" { lines.removeLast() }

    let clampedStart = max(1, start)
    let clampedEnd = min(lines.count, end)
    guard clampedStart <= clampedEnd else { return "" }

    let slice = lines[(clampedStart - 1)...(clampedEnd - 1)]
    var result = slice.joined(separator: "\n")
    if !result.isEmpty && fileContent.hasSuffix("\n") {
        result += "\n"
    }
    return result
}

public func extendBlockRange(
    _ candidate: MoveCandidate,
    contextLines: Int = defaultContextLines
) -> (source: (start: Int, end: Int), target: (start: Int, end: Int)) {
    let srcStart = candidate.removedLines.first!.lineNumber
    let srcEnd = candidate.removedLines.last!.lineNumber
    let tgtStart = candidate.addedLines.first!.lineNumber
    let tgtEnd = candidate.addedLines.last!.lineNumber

    return (
        source: (start: max(1, srcStart - contextLines), end: srcEnd + contextLines),
        target: (start: max(1, tgtStart - contextLines), end: tgtEnd + contextLines)
    )
}

func hunkOverlapsBlock(
    _ hunk: Hunk,
    blockStart: Int,
    blockEnd: Int,
    regionStart: Int,
    proximity: Int = defaultTrimProximity
) -> Bool {
    let hunkAbsStart = regionStart + hunk.newStart - 1
    let hunkAbsEnd = hunkAbsStart + max(hunk.newLength - 1, 0)

    return hunkAbsStart <= blockEnd + proximity
        && hunkAbsEnd >= blockStart - proximity
}

public func trimHunks(
    _ hunks: [Hunk],
    blockStart: Int,
    blockEnd: Int,
    regionStart: Int,
    proximity: Int = defaultTrimProximity
) -> [Hunk] {
    hunks.filter { hunkOverlapsBlock($0, blockStart: blockStart, blockEnd: blockEnd, regionStart: regionStart, proximity: proximity) }
}

public func computeEffectiveDiffForCandidate(
    _ candidate: MoveCandidate,
    oldFiles: [String: String],
    newFiles: [String: String],
    contextLines: Int = defaultContextLines,
    trimProximity: Int = defaultTrimProximity,
    rediff: RediffFunction
) async throws -> EffectiveDiffResult {
    let ranges = extendBlockRange(candidate, contextLines: contextLines)

    let oldContent = oldFiles[candidate.sourceFile] ?? ""
    let newContent = newFiles[candidate.targetFile] ?? ""

    let oldRegion = extractLineRange(from: oldContent, start: ranges.source.start, end: ranges.source.end)
    let newRegion = extractLineRange(from: newContent, start: ranges.target.start, end: ranges.target.end)

    let rawDiff = try await rediff(oldRegion, newRegion, candidate.sourceFile, candidate.targetFile)

    guard !rawDiff.isEmpty else {
        return EffectiveDiffResult(candidate: candidate, hunks: [], rawDiff: "")
    }

    let parsed = GitDiff.fromDiffContent(rawDiff, commitHash: "")

    let tgtBlockStart = candidate.addedLines.first!.lineNumber
    let tgtBlockEnd = candidate.addedLines.last!.lineNumber

    let trimmed = trimHunks(
        parsed.hunks,
        blockStart: tgtBlockStart,
        blockEnd: tgtBlockEnd,
        regionStart: ranges.target.start,
        proximity: trimProximity
    )

    return EffectiveDiffResult(
        candidate: candidate,
        hunks: trimmed,
        rawDiff: rawDiff
    )
}
