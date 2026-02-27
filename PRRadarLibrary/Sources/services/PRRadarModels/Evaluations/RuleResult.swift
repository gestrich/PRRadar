import Foundation

/// An individual violation finding within a rule evaluation.
public struct Violation: Codable, Sendable {
    public let score: Int
    public let comment: String
    public let filePath: String
    public let lineNumber: Int?

    public init(score: Int, comment: String, filePath: String, lineNumber: Int?) {
        self.score = score
        self.comment = comment
        self.filePath = filePath
        self.lineNumber = lineNumber
    }
}

/// A successful rule evaluation with metadata and findings.
public struct RuleResult: Codable, Sendable {
    public let taskId: String
    public let ruleName: String
    public let filePath: String
    public let modelUsed: String
    public let durationMs: Int
    public let costUsd: Double?
    public let violations: [Violation]

    public var violatesRule: Bool { !violations.isEmpty }

    public init(
        taskId: String,
        ruleName: String,
        filePath: String,
        modelUsed: String,
        durationMs: Int,
        costUsd: Double?,
        violations: [Violation]
    ) {
        self.taskId = taskId
        self.ruleName = ruleName
        self.filePath = filePath
        self.modelUsed = modelUsed
        self.durationMs = durationMs
        self.costUsd = costUsd
        self.violations = violations
    }
}
