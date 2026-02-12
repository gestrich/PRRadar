import PRRadarConfigService
import PRRadarModels

public struct AIPromptContext: Sendable {
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
    case aiOutput(text: String)
    case aiPrompt(AIPromptContext)
    case aiToolUse(name: String)
    case progress(current: Int, total: Int)
    case analysisResult(RuleEvaluationResult)
    case completed(output: Output)
    case failed(error: String, logs: String)
}
