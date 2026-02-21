import Foundation

/// Summary of an evaluation run.
public struct PRReviewSummary: Codable, Sendable {
    public let prNumber: Int
    public let evaluatedAt: String
    public let totalTasks: Int
    public let violationsFound: Int
    public let totalCostUsd: Double
    public let totalDurationMs: Int
    public let results: [RuleOutcome]

    public init(
        prNumber: Int,
        evaluatedAt: String,
        totalTasks: Int,
        violationsFound: Int,
        totalCostUsd: Double,
        totalDurationMs: Int,
        results: [RuleOutcome]
    ) {
        self.prNumber = prNumber
        self.evaluatedAt = evaluatedAt
        self.totalTasks = totalTasks
        self.violationsFound = violationsFound
        self.totalCostUsd = totalCostUsd
        self.totalDurationMs = totalDurationMs
        self.results = results
    }

    /// Distinct model IDs used across all evaluation results, sorted alphabetically.
    public var modelsUsed: [String] {
        Array(Set(results.map(\.modelUsed))).sorted()
    }
}
