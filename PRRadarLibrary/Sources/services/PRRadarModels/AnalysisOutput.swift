import Foundation

// MARK: - Analysis Output Models

/// Result of evaluating a single rule against a focus area.
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
}

/// A successful evaluation result with metadata.
public struct EvaluationSuccess: Codable, Sendable {
    public let taskId: String
    public let ruleName: String
    public let filePath: String
    public let evaluation: RuleEvaluation
    public let modelUsed: String
    public let durationMs: Int
    public let costUsd: Double?

    public init(
        taskId: String,
        ruleName: String,
        filePath: String,
        evaluation: RuleEvaluation,
        modelUsed: String,
        durationMs: Int,
        costUsd: Double?
    ) {
        self.taskId = taskId
        self.ruleName = ruleName
        self.filePath = filePath
        self.evaluation = evaluation
        self.modelUsed = modelUsed
        self.durationMs = durationMs
        self.costUsd = costUsd
    }
}

/// An evaluation that failed due to an error (network, timeout, etc.).
public struct EvaluationError: Codable, Sendable {
    public let taskId: String
    public let ruleName: String
    public let filePath: String
    public let errorMessage: String
    public let modelUsed: String

    public init(
        taskId: String,
        ruleName: String,
        filePath: String,
        errorMessage: String,
        modelUsed: String
    ) {
        self.taskId = taskId
        self.ruleName = ruleName
        self.filePath = filePath
        self.errorMessage = errorMessage
        self.modelUsed = modelUsed
    }
}

/// Either a successful evaluation or an error.
public enum RuleEvaluationResult: Codable, Sendable {
    case success(EvaluationSuccess)
    case error(EvaluationError)

    // MARK: - Convenience Accessors

    public var taskId: String {
        switch self {
        case .success(let s): s.taskId
        case .error(let e): e.taskId
        }
    }

    public var ruleName: String {
        switch self {
        case .success(let s): s.ruleName
        case .error(let e): e.ruleName
        }
    }

    public var filePath: String {
        switch self {
        case .success(let s): s.filePath
        case .error(let e): e.filePath
        }
    }

    public var modelUsed: String {
        switch self {
        case .success(let s): s.modelUsed
        case .error(let e): e.modelUsed
        }
    }

    public var costUsd: Double? {
        switch self {
        case .success(let s): s.costUsd
        case .error: nil
        }
    }

    public var durationMs: Int {
        switch self {
        case .success(let s): s.durationMs
        case .error: 0
        }
    }

    public var isViolation: Bool {
        violation != nil
    }

    public var isError: Bool {
        error != nil
    }

    public var violation: EvaluationSuccess? {
        switch self {
        case .success(let s) where s.evaluation.violatesRule: s
        default: nil
        }
    }

    public var success: EvaluationSuccess? {
        switch self {
        case .success(let s): s
        case .error: nil
        }
    }

    public var error: EvaluationError? {
        switch self {
        case .error(let e): e
        case .success: nil
        }
    }

    public var evaluation: RuleEvaluation? {
        switch self {
        case .success(let s): s.evaluation
        case .error: nil
        }
    }

    public func violationComment(task: AnalysisTaskOutput?) -> PRComment? {
        guard let violation else { return nil }
        return PRComment.from(evaluation: violation, task: task)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case success
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.success) {
            self = .success(try container.decode(EvaluationSuccess.self, forKey: .success))
        } else {
            self = .error(try container.decode(EvaluationError.self, forKey: .error))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .success(let s):
            try container.encode(s, forKey: .success)
        case .error(let e):
            try container.encode(e, forKey: .error)
        }
    }
}

/// Summary of an evaluation run.
public struct AnalysisSummary: Codable, Sendable {
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
}
