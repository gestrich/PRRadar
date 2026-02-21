import Foundation

/// Summary statistics for an evaluation run.
public struct PRReviewSummary: Codable, Sendable {
    public let prNumber: Int
    public let evaluatedAt: String
    public let totalTasks: Int
    public let violationsFound: Int
    public let totalCostUsd: Double
    public let totalDurationMs: Int

    public init(
        prNumber: Int,
        evaluatedAt: String,
        totalTasks: Int,
        violationsFound: Int,
        totalCostUsd: Double,
        totalDurationMs: Int
    ) {
        self.prNumber = prNumber
        self.evaluatedAt = evaluatedAt
        self.totalTasks = totalTasks
        self.violationsFound = violationsFound
        self.totalCostUsd = totalCostUsd
        self.totalDurationMs = totalDurationMs
    }
}
