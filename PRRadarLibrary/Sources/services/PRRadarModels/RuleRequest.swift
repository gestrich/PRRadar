import Foundation

// MARK: - Analysis Task Models

/// Subset of Rule fields included in evaluation task JSON.
public struct TaskRule: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let category: String
    public let model: String?
    public let content: String
    public let documentationLink: String?
    public let relevantClaudeSkill: String?
    public let ruleUrl: String?
    public let newCodeLinesOnly: Bool
    public let violationRegex: String?
    public let violationMessage: String?

    public var isRegexOnly: Bool {
        violationRegex != nil
    }

    public init(
        name: String,
        description: String,
        category: String,
        model: String? = nil,
        content: String,
        documentationLink: String? = nil,
        relevantClaudeSkill: String? = nil,
        ruleUrl: String? = nil,
        newCodeLinesOnly: Bool = false,
        violationRegex: String? = nil,
        violationMessage: String? = nil
    ) {
        self.name = name
        self.description = description
        self.category = category
        self.model = model
        self.content = content
        self.documentationLink = documentationLink
        self.relevantClaudeSkill = relevantClaudeSkill
        self.ruleUrl = ruleUrl
        self.newCodeLinesOnly = newCodeLinesOnly
        self.violationRegex = violationRegex
        self.violationMessage = violationMessage
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case category
        case model
        case content
        case documentationLink = "documentation_link"
        case relevantClaudeSkill = "relevant_claude_skill"
        case ruleUrl = "rule_url"
        case newCodeLinesOnly = "new_code_lines_only"
        case violationRegex = "violation_regex"
        case violationMessage = "violation_message"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        category = try container.decode(String.self, forKey: .category)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        content = try container.decode(String.self, forKey: .content)
        documentationLink = try container.decodeIfPresent(String.self, forKey: .documentationLink)
        relevantClaudeSkill = try container.decodeIfPresent(String.self, forKey: .relevantClaudeSkill)
        ruleUrl = try container.decodeIfPresent(String.self, forKey: .ruleUrl)
        newCodeLinesOnly = try container.decodeIfPresent(Bool.self, forKey: .newCodeLinesOnly) ?? false
        violationRegex = try container.decodeIfPresent(String.self, forKey: .violationRegex)
        violationMessage = try container.decodeIfPresent(String.self, forKey: .violationMessage)
    }
}

/// An evaluation task pairing a rule with a focus area.
public struct RuleRequest: Codable, Sendable, Hashable, Comparable {
    public let taskId: String
    public let rule: TaskRule
    public let focusArea: FocusArea
    public let gitBlobHash: String
    public let ruleBlobHash: String?

    public init(taskId: String, rule: TaskRule, focusArea: FocusArea, gitBlobHash: String, ruleBlobHash: String? = nil) {
        self.taskId = taskId
        self.rule = rule
        self.focusArea = focusArea
        self.gitBlobHash = gitBlobHash
        self.ruleBlobHash = ruleBlobHash
    }

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case rule
        case focusArea = "focus_area"
        case gitBlobHash = "git_blob_hash"
        case ruleBlobHash = "rule_blob_hash"
    }

    public static func == (lhs: RuleRequest, rhs: RuleRequest) -> Bool {
        lhs.taskId == rhs.taskId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(taskId)
    }

    public static func < (lhs: RuleRequest, rhs: RuleRequest) -> Bool {
        if lhs.focusArea.filePath != rhs.focusArea.filePath {
            return lhs.focusArea.filePath < rhs.focusArea.filePath
        }
        return lhs.rule.name < rhs.rule.name
    }

    public static func from(rule: ReviewRule, focusArea: FocusArea, gitBlobHash: String, ruleBlobHash: String? = nil) -> RuleRequest {
        let taskId = "\(rule.name)_\(focusArea.focusId)"
        let taskRule = TaskRule(
            name: rule.name,
            description: rule.description,
            category: rule.category,
            model: rule.model,
            content: rule.content,
            documentationLink: rule.documentationLink,
            relevantClaudeSkill: rule.relevantClaudeSkill,
            ruleUrl: rule.ruleUrl,
            newCodeLinesOnly: rule.newCodeLinesOnly,
            violationRegex: rule.violationRegex,
            violationMessage: rule.violationMessage
        )
        return RuleRequest(taskId: taskId, rule: taskRule, focusArea: focusArea, gitBlobHash: gitBlobHash, ruleBlobHash: ruleBlobHash)
    }
}
