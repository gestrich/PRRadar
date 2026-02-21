import Foundation

/// A successful evaluation result with metadata.
public struct EvaluationSuccess: Codable, Sendable {
    public let taskId: String
    public let ruleName: String
    public let filePath: String
    public let finding: RuleFinding
    public let modelUsed: String
    public let durationMs: Int
    public let costUsd: Double?

    public init(
        taskId: String,
        ruleName: String,
        filePath: String,
        finding: RuleFinding,
        modelUsed: String,
        durationMs: Int,
        costUsd: Double?
    ) {
        self.taskId = taskId
        self.ruleName = ruleName
        self.filePath = filePath
        self.finding = finding
        self.modelUsed = modelUsed
        self.durationMs = durationMs
        self.costUsd = costUsd
    }
}
