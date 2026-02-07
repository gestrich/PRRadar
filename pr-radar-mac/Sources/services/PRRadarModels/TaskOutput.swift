import Foundation

// MARK: - Phase 4: Evaluation Task Models

/// Subset of Rule fields included in evaluation task JSON.
public struct TaskRule: Codable, Sendable {
    public let name: String
    public let description: String
    public let category: String
    public let model: String?
    public let content: String
    public let documentationLink: String?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case category
        case model
        case content
        case documentationLink = "documentation_link"
    }
}

/// An evaluation task pairing a rule with a focus area, matching Python's EvaluationTask.to_dict()
public struct EvaluationTaskOutput: Codable, Sendable {
    public let taskId: String
    public let rule: TaskRule
    public let focusArea: FocusArea

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case rule
        case focusArea = "focus_area"
    }
}
