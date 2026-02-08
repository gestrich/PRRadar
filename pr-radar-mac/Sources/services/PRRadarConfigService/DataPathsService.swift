import Foundation

public enum PRRadarPhase: String, CaseIterable, Sendable {
    case pullRequest = "phase-1-pull-request"
    case focusAreas = "phase-2-focus-areas"
    case rules = "phase-3-rules"
    case tasks = "phase-4-tasks"
    case evaluations = "phase-5-evaluations"
    case report = "phase-6-report"

    /// The numeric phase number (1-6).
    public var phaseNumber: Int {
        Self.allCases.firstIndex(of: self)! + 1
    }

    /// The phase that must complete before this one can run, or nil for phase 1.
    public var requiredPredecessor: PRRadarPhase? {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self), idx > 0 else { return nil }
        return all[idx - 1]
    }

    /// Human-readable display name for the phase.
    public var displayName: String {
        switch self {
        case .pullRequest: "Pull Request"
        case .focusAreas: "Focus Areas"
        case .rules: "Rules"
        case .tasks: "Tasks"
        case .evaluations: "Evaluations"
        case .report: "Report"
        }
    }
}

// MARK: - Phase Status

/// Detailed status of a pipeline phase for progress tracking and resume support.
public struct PhaseStatus: Sendable {
    public let phase: PRRadarPhase
    public let exists: Bool
    public let isComplete: Bool
    public let completedCount: Int
    public let totalCount: Int
    public let missingItems: [String]

    public init(
        phase: PRRadarPhase,
        exists: Bool,
        isComplete: Bool,
        completedCount: Int,
        totalCount: Int,
        missingItems: [String]
    ) {
        self.phase = phase
        self.exists = exists
        self.isComplete = isComplete
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.missingItems = missingItems
    }

    public var completionPercentage: Double {
        if totalCount == 0 { return isComplete ? 100.0 : 0.0 }
        return (Double(completedCount) / Double(totalCount)) * 100.0
    }

    public var isPartial: Bool {
        exists && !isComplete && completedCount > 0
    }

    public var summary: String {
        if !exists { return "not started" }
        if isComplete { return "complete" }
        if isPartial { return "partial (\(completedCount)/\(totalCount))" }
        return "incomplete"
    }
}

// MARK: - DataPathsService

public enum DataPathsService {
    public static let phaseResultFilename = "phase_result.json"
    
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

    /// Check whether a phase directory exists and has content.
    public static func phaseExists(outputDir: String, prNumber: String, phase: PRRadarPhase) -> Bool {
        let dir = phaseDirectory(outputDir: outputDir, prNumber: prNumber, phase: phase)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return !contents.isEmpty
    }

    /// Check if dependencies are satisfied for running a phase.
    public static func canRunPhase(
        _ phase: PRRadarPhase,
        outputDir: String,
        prNumber: String
    ) -> Bool {
        guard let predecessor = phase.requiredPredecessor else { return true }
        return phaseExists(outputDir: outputDir, prNumber: prNumber, phase: predecessor)
    }

    /// Validate that a phase can run, returning an error message if not.
    public static func validateCanRun(
        _ phase: PRRadarPhase,
        outputDir: String,
        prNumber: String
    ) -> String? {
        guard canRunPhase(phase, outputDir: outputDir, prNumber: prNumber) else {
            let predecessor = phase.requiredPredecessor!
            return "Cannot run \(phase.rawValue): \(predecessor.rawValue) has not completed"
        }
        return nil
    }

    // MARK: - Phase Completion Checking

    /// Get detailed completion status for a single phase.
    ///
    /// Checks for phase_result.json as the source of truth for phase completion.
    /// If the file is missing, the phase is considered not started.
    public static func phaseStatus(
        _ phase: PRRadarPhase,
        outputDir: String,
        prNumber: String
    ) -> PhaseStatus {
        let dir = phaseDirectory(outputDir: outputDir, prNumber: prNumber, phase: phase)

        guard let phaseResult = readPhaseResult(directory: dir, phase: phase) else {
            // No phase_result.json means phase hasn't been run
            return PhaseStatus(
                phase: phase,
                exists: false,
                isComplete: false,
                completedCount: 0,
                totalCount: 1,
                missingItems: [phaseResultFilename]
            )
        }

        if phaseResult.status == .success {
            // Phase completed successfully - trust the result file
            let artifactCount = phaseResult.stats?.artifactsProduced ?? 0
            return PhaseStatus(
                phase: phase,
                exists: true,
                isComplete: true,
                completedCount: artifactCount,
                totalCount: artifactCount,
                missingItems: []
            )
        } else {
            // Phase failed - report the error
            return PhaseStatus(
                phase: phase,
                exists: true,
                isComplete: false,
                completedCount: 0,
                totalCount: 1,
                missingItems: [phaseResult.errorMessage ?? "Unknown error"]
            )
        }
    }

    /// Get status for all phases.
    public static func allPhaseStatuses(
        outputDir: String,
        prNumber: String
    ) -> [PRRadarPhase: PhaseStatus] {
        var result: [PRRadarPhase: PhaseStatus] = [:]
        for phase in PRRadarPhase.allCases {
            result[phase] = phaseStatus(phase, outputDir: outputDir, prNumber: prNumber)
        }
        return result
    }

    // MARK: - Private Helpers

    /// Read phase_result.json from a phase directory if it exists.
    private static func readPhaseResult(directory: String, phase: PRRadarPhase) -> PhaseResult? {
        let path = "\(directory)/\(phaseResultFilename)"
        guard let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        return try? JSONDecoder().decode(PhaseResult.self, from: data)
    }
}

// MARK: - PhaseResult Model

/// Standard result file written at the end of every phase to indicate completion status.
public struct PhaseResult: Codable, Sendable {
    public let phase: String
    public let status: PhaseResultStatus
    public let completedAt: String
    public let errorMessage: String?
    public let stats: PhaseStats?

    public init(
        phase: String,
        status: PhaseResultStatus,
        completedAt: String = ISO8601DateFormatter().string(from: Date()),
        errorMessage: String? = nil,
        stats: PhaseStats? = nil
    ) {
        self.phase = phase
        self.status = status
        self.completedAt = completedAt
        self.errorMessage = errorMessage
        self.stats = stats
    }

    enum CodingKeys: String, CodingKey {
        case phase
        case status
        case completedAt = "completed_at"
        case errorMessage = "error_message"
        case stats
    }
}

/// Phase completion status
public enum PhaseResultStatus: String, Codable, Sendable {
    case success
    case failed
}

/// Optional statistics about phase execution
public struct PhaseStats: Codable, Sendable {
    public let artifactsProduced: Int?
    public let durationMs: Int?
    public let costUsd: Double?
    public let metadata: [String: String]?

    public init(
        artifactsProduced: Int? = nil,
        durationMs: Int? = nil,
        costUsd: Double? = nil,
        metadata: [String: String]? = nil
    ) {
        self.artifactsProduced = artifactsProduced
        self.durationMs = durationMs
        self.costUsd = costUsd
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case artifactsProduced = "artifacts_produced"
        case durationMs = "duration_ms"
        case costUsd = "cost_usd"
        case metadata
    }
}
