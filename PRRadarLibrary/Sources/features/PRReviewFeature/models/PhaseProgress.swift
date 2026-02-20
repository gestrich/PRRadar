import PRRadarConfigService
import PRRadarModels

public struct TaskPromptContext: Sendable {
    public let text: String
    public let filePath: String?
    public let ruleName: String?

    public init(text: String, filePath: String? = nil, ruleName: String? = nil) {
        self.text = text
        self.filePath = filePath
        self.ruleName = ruleName
    }
}

public enum PhaseProgress<Output: Sendable>: Sendable {
    case running(phase: PRRadarPhase)
    case log(text: String)
    case taskOutput(text: String)
    case taskPrompt(TaskPromptContext)
    case taskToolUse(name: String)
    case progress(current: Int, total: Int)
    case taskCompleted(taskId: String, cumulative: AnalysisOutput)
    case completed(output: Output)
    case failed(error: String, logs: String)
}
