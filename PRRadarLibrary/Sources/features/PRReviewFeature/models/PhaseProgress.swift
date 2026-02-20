import PRRadarConfigService
import PRRadarModels

public enum PhaseProgress<Output: Sendable>: Sendable {
    case running(phase: PRRadarPhase)
    case log(text: String)
    case prepareOutput(text: String)
    case prepareToolUse(name: String)
    case taskOutput(task: AnalysisTaskOutput, text: String)
    case taskPrompt(task: AnalysisTaskOutput, text: String)
    case taskToolUse(task: AnalysisTaskOutput, name: String)
    case progress(current: Int, total: Int)
    case taskCompleted(task: AnalysisTaskOutput, cumulative: AnalysisOutput)
    case completed(output: Output)
    case failed(error: String, logs: String)
}
