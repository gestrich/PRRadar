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
    public let analysisMethod: AnalysisMethod
    public let durationMs: Int
    public let violations: [Violation]

    public var violatesRule: Bool { !violations.isEmpty }

    public var costUsd: Double { analysisMethod.costUsd }

    public init(
        taskId: String,
        ruleName: String,
        filePath: String,
        analysisMethod: AnalysisMethod,
        durationMs: Int,
        violations: [Violation]
    ) {
        self.taskId = taskId
        self.ruleName = ruleName
        self.filePath = filePath
        self.analysisMethod = analysisMethod
        self.durationMs = durationMs
        self.violations = violations
    }
}
