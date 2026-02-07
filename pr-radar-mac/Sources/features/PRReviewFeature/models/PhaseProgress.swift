import PRRadarConfigService

public enum PhaseProgress<Output: Sendable>: Sendable {
    case running(phase: PRRadarPhase)
    case completed(output: Output)
    case failed(error: String, logs: String)
}
