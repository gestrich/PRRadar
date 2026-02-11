import PRRadarConfigService
import PRRadarModels

public enum PhaseProgress<Output: Sendable>: Sendable {
    case running(phase: PRRadarPhase)
    case log(text: String)
    case aiOutput(text: String)
    case aiPrompt(text: String)
    case aiToolUse(name: String)
    case progress(current: Int, total: Int)
    case evaluationResult(RuleEvaluationResult)
    case completed(output: Output)
    case failed(error: String, logs: String)
}
