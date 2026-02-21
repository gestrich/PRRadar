import Foundation

/// Either a successful evaluation or an error.
public enum RuleOutcome: Codable, Sendable {
    case success(RuleResult)
    case error(RuleError)

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

    public var violation: RuleResult? {
        switch self {
        case .success(let s) where s.violatesRule: s
        default: nil
        }
    }

    public var success: RuleResult? {
        switch self {
        case .success(let s): s
        case .error: nil
        }
    }

    public var error: RuleError? {
        switch self {
        case .error(let e): e
        case .success: nil
        }
    }

    public func violationComment(task: RuleRequest?) -> PRComment? {
        guard let violation else { return nil }
        return PRComment.from(result: violation, task: task)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case success
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.success) {
            self = .success(try container.decode(RuleResult.self, forKey: .success))
        } else {
            self = .error(try container.decode(RuleError.self, forKey: .error))
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
