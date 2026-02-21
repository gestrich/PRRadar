import PRRadarConfigService
import PRRadarModels

public enum PhaseProgress<Output: Sendable>: Sendable {
    case running(phase: PRRadarPhase)
    case log(text: String)
    case prepareOutput(text: String)
    case prepareToolUse(name: String)
    case taskEvent(task: RuleRequest, event: TaskProgress)
    case progress(current: Int, total: Int)
    case completed(output: Output)
    case failed(error: String, logs: String)
}
