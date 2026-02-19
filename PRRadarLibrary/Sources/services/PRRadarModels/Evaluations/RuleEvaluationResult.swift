import Foundation

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
