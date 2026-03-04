import Foundation

/// A services-layer model that bundles all diff-related data for a PR.
///
/// Combines the full diff, effective diff (with moves stripped), move report,
/// and classified hunks into a single value that can be threaded through
/// services, features, and views without passing each piece separately.
public struct AnnotatedDiff: Codable, Sendable, Equatable {
    public let fullDiff: GitDiff
    public let effectiveDiff: GitDiff?
    public let moveReport: MoveReport?
    public let classifiedHunks: [ClassifiedHunk]
    public let prDiff: PRDiff?

    public init(
        fullDiff: GitDiff,
        effectiveDiff: GitDiff? = nil,
        moveReport: MoveReport? = nil,
        classifiedHunks: [ClassifiedHunk] = [],
        prDiff: PRDiff? = nil
    ) {
        self.fullDiff = fullDiff
        self.effectiveDiff = effectiveDiff
        self.moveReport = moveReport
        self.classifiedHunks = classifiedHunks
        self.prDiff = prDiff
    }
}
