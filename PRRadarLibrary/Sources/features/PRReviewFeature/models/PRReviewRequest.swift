import PRRadarModels

public struct PRReviewRequest: Sendable {
    public let prNumber: Int
    public let filter: RuleFilter?
    public let commitHash: String?
    public let analysisMode: AnalysisMode

    public init(prNumber: Int, filter: RuleFilter? = nil, commitHash: String? = nil, analysisMode: AnalysisMode = .all) {
        self.prNumber = prNumber
        self.filter = filter
        self.commitHash = commitHash
        self.analysisMode = analysisMode
    }
}
