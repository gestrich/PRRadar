import Foundation

/// An evaluation that failed due to an error (network, timeout, etc.).
public struct RuleError: Codable, Sendable {
    public let taskId: String
    public let ruleName: String
    public let filePath: String
    public let errorMessage: String
    public let analysisMethod: AnalysisMethod

    public init(
        taskId: String,
        ruleName: String,
        filePath: String,
        errorMessage: String,
        analysisMethod: AnalysisMethod
    ) {
        self.taskId = taskId
        self.ruleName = ruleName
        self.filePath = filePath
        self.errorMessage = errorMessage
        self.analysisMethod = analysisMethod
    }
}
