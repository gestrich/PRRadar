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

    public init(
        ruleName: String,
        score: Int,
        filePath: String,
        lineNumber: Int?,
        comment: String,
        methodName: String? = nil,
        documentationLink: String? = nil,
        relevantClaudeSkill: String? = nil
    ) {
        self.ruleName = ruleName
        self.score = score
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.comment = comment
        self.methodName = methodName
        self.documentationLink = documentationLink
        self.relevantClaudeSkill = relevantClaudeSkill
    }

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

    public init(
        totalTasksEvaluated: Int,
        violationsFound: Int,
        highestSeverity: Int,
        totalCostUsd: Double,
        bySeverity: [String: Int],
        byFile: [String: Int],
        byRule: [String: Int],
        byMethod: [String: [String: [[String: AnyCodableValue]]]]? = nil
    ) {
        self.totalTasksEvaluated = totalTasksEvaluated
        self.violationsFound = violationsFound
        self.highestSeverity = highestSeverity
        self.totalCostUsd = totalCostUsd
        self.bySeverity = bySeverity
        self.byFile = byFile
        self.byRule = byRule
        self.byMethod = byMethod
    }

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

    public init(
        prNumber: Int,
        generatedAt: String,
        minScoreThreshold: Int,
        summary: ReportSummary,
        violations: [ViolationRecord]
    ) {
        self.prNumber = prNumber
        self.generatedAt = generatedAt
        self.minScoreThreshold = minScoreThreshold
        self.summary = summary
        self.violations = violations
    }

    enum CodingKeys: String, CodingKey {
        case prNumber = "pr_number"
        case generatedAt = "generated_at"
        case minScoreThreshold = "min_score_threshold"
        case summary
        case violations
    }

    // MARK: - Markdown Generation

    public func toMarkdown() -> String {
        var lines: [String] = []

        lines.append("# Code Review Report: PR #\(prNumber)")
        lines.append("")
        lines.append("Generated: \(generatedAt)")
        lines.append("Minimum Score Threshold: \(minScoreThreshold)")
        lines.append("")

        lines.append("## Summary")
        lines.append("")
        lines.append("- **Tasks Evaluated:** \(summary.totalTasksEvaluated)")
        lines.append("- **Violations Found:** \(summary.violationsFound)")
        if summary.highestSeverity > 0 {
            lines.append("- **Highest Severity:** \(summary.highestSeverity)")
        }
        if summary.totalCostUsd > 0 {
            lines.append("- **Total Cost:** $\(String(format: "%.4f", summary.totalCostUsd))")
        }
        lines.append("")

        if !summary.bySeverity.isEmpty {
            lines.append("### By Severity")
            lines.append("")
            lines.append("| Severity | Count |")
            lines.append("|----------|-------|")
            let sorted = summary.bySeverity.sorted { Self.severitySortKey($0.key) > Self.severitySortKey($1.key) }
            for (severity, count) in sorted {
                lines.append("| \(severity) | \(count) |")
            }
            lines.append("")
        }

        if !summary.byFile.isEmpty {
            lines.append("### By File")
            lines.append("")
            lines.append("| File | Violations |")
            lines.append("|------|------------|")
            for (filePath, count) in summary.byFile.sorted(by: { $0.value > $1.value }) {
                lines.append("| `\(filePath)` | \(count) |")
            }
            lines.append("")
        }

        if !summary.byRule.isEmpty {
            lines.append("### By Rule")
            lines.append("")
            lines.append("| Rule | Violations |")
            lines.append("|------|------------|")
            for (ruleName, count) in summary.byRule.sorted(by: { $0.value > $1.value }) {
                lines.append("| \(ruleName) | \(count) |")
            }
            lines.append("")
        }

        if !violations.isEmpty {
            lines.append("## Violations")
            lines.append("")

            for (i, v) in violations.enumerated() {
                let location = v.lineNumber.map { "\(v.filePath):\($0)" } ?? v.filePath
                lines.append("### \(i + 1). \(v.ruleName) (Score: \(v.score))")
                lines.append("")
                lines.append("**Location:** `\(location)`")
                if let methodName = v.methodName {
                    lines.append("**Method:** `\(methodName)`")
                }
                lines.append("")
                lines.append(v.comment)
                if let link = v.documentationLink {
                    lines.append("")
                    lines.append("[Documentation](\(link))")
                }
                if let skill = v.relevantClaudeSkill {
                    lines.append("")
                    lines.append("Related Claude Skill: `/\(skill)`")
                }
                lines.append("")
                lines.append("---")
                lines.append("")
            }
        } else {
            lines.append("## Violations")
            lines.append("")
            lines.append("No violations found meeting the score threshold.")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func severitySortKey(_ severity: String) -> Int {
        switch severity {
        case "Severe (8-10)": return 3
        case "Moderate (5-7)": return 2
        case "Minor (1-4)": return 1
        default: return 0
        }
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
