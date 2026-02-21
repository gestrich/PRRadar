import PRRadarModels

public struct PRReviewRequest: Sendable {
    public let prNumber: Int
    public let filter: RuleFilter?
    public let commitHash: String?

    public init(prNumber: Int, filter: RuleFilter? = nil, commitHash: String? = nil) {
        self.prNumber = prNumber
        self.filter = filter
        self.commitHash = commitHash
    }
}
