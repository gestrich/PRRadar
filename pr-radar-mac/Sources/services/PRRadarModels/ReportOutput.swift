import Foundation

// MARK: - Phase 6: Report Output Models

/// A single violation record in the report, matching Python's ViolationRecord.to_dict()
public struct ViolationRecord: Codable, Sendable {
    public let ruleName: String
    public let score: Int
    public let filePath: String
    public let lineNumber: Int?
    public let comment: String
    public let methodName: String?
    public let documentationLink: String?
    public let relevantClaudeSkill: String?

    enum CodingKeys: String, CodingKey {
        case ruleName = "rule_name"
        case score
        case filePath = "file_path"
        case lineNumber = "line_number"
        case comment
        case methodName = "method_name"
        case documentationLink = "documentation_link"
        case relevantClaudeSkill = "relevant_claude_skill"
    }
}

/// Summary statistics for a review report, matching Python's ReportSummary.to_dict()
public struct ReportSummary: Codable, Sendable {
    public let totalTasksEvaluated: Int
    public let violationsFound: Int
    public let highestSeverity: Int
    public let totalCostUsd: Double
    public let bySeverity: [String: Int]
    public let byFile: [String: Int]
    public let byRule: [String: Int]
    public let byMethod: [String: [String: [[String: AnyCodableValue]]]]?

    enum CodingKeys: String, CodingKey {
        case totalTasksEvaluated = "total_tasks_evaluated"
        case violationsFound = "violations_found"
        case highestSeverity = "highest_severity"
        case totalCostUsd = "total_cost_usd"
        case bySeverity = "by_severity"
        case byFile = "by_file"
        case byRule = "by_rule"
        case byMethod = "by_method"
    }
}

/// Full review report, matching Python's ReviewReport.to_dict()
public struct ReviewReport: Codable, Sendable {
    public let prNumber: Int
    public let generatedAt: String
    public let minScoreThreshold: Int
    public let summary: ReportSummary
    public let violations: [ViolationRecord]

    enum CodingKeys: String, CodingKey {
        case prNumber = "pr_number"
        case generatedAt = "generated_at"
        case minScoreThreshold = "min_score_threshold"
        case summary
        case violations
    }
}

/// Type-erased JSON value for handling heterogeneous dictionaries in `by_method`.
public enum AnyCodableValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.typeMismatch(
                AnyCodableValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
