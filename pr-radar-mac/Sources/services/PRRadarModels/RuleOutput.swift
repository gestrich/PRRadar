import Foundation

// MARK: - Phase 3: Rule Models

/// File pattern matching configuration for a rule.
public struct AppliesTo: Codable, Sendable {
    public let filePatterns: [String]?
    public let excludePatterns: [String]?

    enum CodingKeys: String, CodingKey {
        case filePatterns = "file_patterns"
        case excludePatterns = "exclude_patterns"
    }
}

/// Grep pattern configuration for a rule.
public struct GrepPatterns: Codable, Sendable {
    public let all: [String]?
    public let any: [String]?
}

/// A review rule, matching Python's Rule.to_dict()
public struct ReviewRule: Codable, Sendable {
    public let name: String
    public let filePath: String
    public let description: String
    public let category: String
    public let focusType: FocusType
    public let content: String
    public let model: String?
    public let documentationLink: String?
    public let relevantClaudeSkill: String?
    public let ruleUrl: String?
    public let appliesTo: AppliesTo?
    public let grep: GrepPatterns?

    enum CodingKeys: String, CodingKey {
        case name
        case filePath = "file_path"
        case description
        case category
        case focusType = "focus_type"
        case content
        case model
        case documentationLink = "documentation_link"
        case relevantClaudeSkill = "relevant_claude_skill"
        case ruleUrl = "rule_url"
        case appliesTo = "applies_to"
        case grep
    }
}

/// Container for all-rules.json output.
public struct AllRulesOutput: Codable, Sendable {
    public let rules: [ReviewRule]
}
