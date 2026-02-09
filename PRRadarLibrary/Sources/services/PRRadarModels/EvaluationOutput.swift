import Foundation

// MARK: - Phase 5: Evaluation Output Models

/// Result of evaluating a single rule against a focus area, matching Python's RuleEvaluation.to_dict()
public struct RuleEvaluation: Codable, Sendable {
    public let violatesRule: Bool
    public let score: Int
    public let comment: String
    public let filePath: String
    public let lineNumber: Int?

    public init(violatesRule: Bool, score: Int, comment: String, filePath: String, lineNumber: Int?) {
        self.violatesRule = violatesRule
        self.score = score
        self.comment = comment
        self.filePath = filePath
        self.lineNumber = lineNumber
    }

    enum CodingKeys: String, CodingKey {
        case violatesRule = "violates_rule"
        case score
        case comment
        case filePath = "file_path"
        case lineNumber = "line_number"
    }
}

/// A single evaluation result with metadata, matching Python's EvaluationResult.to_dict()
public struct RuleEvaluationResult: Codable, Sendable {
    public let taskId: String
    public let ruleName: String
    public let ruleFilePath: String
    public let filePath: String
    public let evaluation: RuleEvaluation
    public let modelUsed: String
    public let durationMs: Int
    public let costUsd: Double?

    public init(
        taskId: String,
        ruleName: String,
        ruleFilePath: String,
        filePath: String,
        evaluation: RuleEvaluation,
        modelUsed: String,
        durationMs: Int,
        costUsd: Double?
    ) {
        self.taskId = taskId
        self.ruleName = ruleName
        self.ruleFilePath = ruleFilePath
        self.filePath = filePath
        self.evaluation = evaluation
        self.modelUsed = modelUsed
        self.durationMs = durationMs
        self.costUsd = costUsd
    }

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case ruleName = "rule_name"
        case ruleFilePath = "rule_file_path"
        case filePath = "file_path"
        case evaluation
        case modelUsed = "model_used"
        case durationMs = "duration_ms"
        case costUsd = "cost_usd"
    }
}

/// Summary of an evaluation run, matching Python's EvaluationSummary.to_dict()
public struct EvaluationSummary: Codable, Sendable {
    public let prNumber: Int
    public let evaluatedAt: String
    public let totalTasks: Int
    public let violationsFound: Int
    public let totalCostUsd: Double
    public let totalDurationMs: Int
    public let results: [RuleEvaluationResult]

    public init(
        prNumber: Int,
        evaluatedAt: String,
        totalTasks: Int,
        violationsFound: Int,
        totalCostUsd: Double,
        totalDurationMs: Int,
        results: [RuleEvaluationResult]
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

    enum CodingKeys: String, CodingKey {
        case prNumber = "pr_number"
        case evaluatedAt = "evaluated_at"
        case totalTasks = "total_tasks"
        case violationsFound = "violations_found"
        case totalCostUsd = "total_cost_usd"
        case totalDurationMs = "total_duration_ms"
        case results
    }
}
