import Foundation

/// A successful rule evaluation with metadata and findings merged into a single type.
public struct RuleResult: Codable, Sendable {
    public let taskId: String
    public let ruleName: String
    public let filePath: String
    public let modelUsed: String
    public let durationMs: Int
    public let costUsd: Double?
    public let violatesRule: Bool
    public let score: Int
    public let comment: String
    public let lineNumber: Int?

    public init(
        taskId: String,
        ruleName: String,
        filePath: String,
        modelUsed: String,
        durationMs: Int,
        costUsd: Double?,
        violatesRule: Bool,
        score: Int,
        comment: String,
        lineNumber: Int?
    ) {
        self.taskId = taskId
        self.ruleName = ruleName
        self.filePath = filePath
        self.modelUsed = modelUsed
        self.durationMs = durationMs
        self.costUsd = costUsd
        self.violatesRule = violatesRule
        self.score = score
        self.comment = comment
        self.lineNumber = lineNumber
    }
}
