import Foundation

/// Result of running the full effective diff pipeline.
public struct EffectiveDiffPipelineResult: Sendable, Equatable {
    public let effectiveDiff: GitDiff
    public let moveReport: EffectiveDiffMoveReport

    public init(effectiveDiff: GitDiff, moveReport: EffectiveDiffMoveReport) {
        self.effectiveDiff = effectiveDiff
        self.moveReport = moveReport
    }
}

/// Run the full effective diff pipeline: match, group, re-diff, reconstruct.
///
/// Chains the four internal stages to detect moved code blocks and produce
/// a reduced diff containing only meaningful changes.
///
/// - Parameters:
///   - gitDiff: The original parsed diff.
///   - oldFiles: File path → content for old (base) file versions.
///   - newFiles: File path → content for new (head) file versions.
///   - rediff: Function to compute a unified diff between two text regions.
/// - Returns: The reduced GitDiff and a summary of detected moves.
public func runEffectiveDiffPipeline(
    gitDiff: GitDiff,
    oldFiles: [String: String],
    newFiles: [String: String],
    rediff: RediffFunction
) async throws -> EffectiveDiffPipelineResult {
    let (removed, added) = extractTaggedLines(from: gitDiff)
    let matches = findExactMatches(removedLines: removed, addedLines: added)
    let candidates = findMoveCandidates(matches: matches, allAddedLines: added)

    var effectiveResults: [EffectiveDiffResult] = []
    for candidate in candidates {
        let result = try await computeEffectiveDiffForCandidate(
            candidate,
            oldFiles: oldFiles,
            newFiles: newFiles,
            rediff: rediff
        )
        effectiveResults.append(result)
    }

    let effectiveDiff = reconstructEffectiveDiff(
        originalDiff: gitDiff,
        effectiveResults: effectiveResults
    )
    let report = buildMoveReport(effectiveResults)

    return EffectiveDiffPipelineResult(
        effectiveDiff: effectiveDiff,
        moveReport: report
    )
}
