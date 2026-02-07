import PRRadarConfigService

public enum PhaseProgress<Output: Sendable>: Sendable {
    case running(phase: PRRadarPhase)
    case log(text: String)
    case completed(output: Output)
    case failed(error: String, logs: String)
}
