import Foundation

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
