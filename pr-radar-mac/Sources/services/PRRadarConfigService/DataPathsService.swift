import Foundation

public enum PRRadarPhase: String, CaseIterable, Sendable {
    case pullRequest = "phase-1-pull-request"
    case focusAreas = "phase-2-focus-areas"
    case rules = "phase-3-rules"
    case tasks = "phase-4-tasks"
    case evaluations = "phase-5-evaluations"
    case report = "phase-6-report"
}

public enum DataPathsService {
    public static func phaseDirectory(
        outputDir: String,
        prNumber: String,
        phase: PRRadarPhase
    ) -> String {
        "\(outputDir)/\(prNumber)/\(phase.rawValue)"
    }

    public static func ensureDirectoryExists(at path: String) throws {
        try FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true
        )
    }
}
