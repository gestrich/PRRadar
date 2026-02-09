import Foundation

// MARK: - Phase 4: Evaluation Task Models

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

    public init(
        name: String,
        description: String,
        category: String,
        model: String? = nil,
        content: String,
        documentationLink: String? = nil,
        relevantClaudeSkill: String? = nil,
        ruleUrl: String? = nil
    ) {
        self.name = name
        self.description = description
        self.category = category
        self.model = model
        self.content = content
        self.documentationLink = documentationLink
        self.relevantClaudeSkill = relevantClaudeSkill
        self.ruleUrl = ruleUrl
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
    }
}

/// An evaluation task pairing a rule with a focus area.
public struct EvaluationTaskOutput: Codable, Sendable, Equatable {
    public let taskId: String
    public let rule: TaskRule
    public let focusArea: FocusArea

    public init(taskId: String, rule: TaskRule, focusArea: FocusArea) {
        self.taskId = taskId
        self.rule = rule
        self.focusArea = focusArea
    }

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case rule
        case focusArea = "focus_area"
    }

    /// Create an evaluation task from a full rule and focus area.
    ///
    /// Generates a task ID from the rule name and focus ID,
    /// and extracts the subset of rule fields needed for evaluation.
    public static func from(rule: ReviewRule, focusArea: FocusArea) -> EvaluationTaskOutput {
        let taskId = "\(rule.name)_\(focusArea.focusId)"
        let taskRule = TaskRule(
            name: rule.name,
            description: rule.description,
            category: rule.category,
            model: rule.model,
            content: rule.content,
            documentationLink: rule.documentationLink,
            relevantClaudeSkill: rule.relevantClaudeSkill,
            ruleUrl: rule.ruleUrl
        )
        return EvaluationTaskOutput(taskId: taskId, rule: taskRule, focusArea: focusArea)
    }
}
