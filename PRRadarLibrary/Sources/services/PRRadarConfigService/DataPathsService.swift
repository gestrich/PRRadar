import Foundation

public enum PRRadarPhase: String, CaseIterable, Sendable {
    case metadata = "metadata"
    case diff = "diff"
    case prepare = "prepare"
    case analyze = "evaluate"
    case report = "report"

    /// The numeric phase number (1-5).
    public var phaseNumber: Int {
        Self.allCases.firstIndex(of: self)! + 1
    }

    /// Whether this phase operates under a commit-scoped directory.
    /// Metadata is PR-scoped; all other phases are commit-scoped.
    public var isCommitScoped: Bool {
        self != .metadata
    }

    /// The phase that must complete before this one can run, or nil if none.
    /// Metadata and diff are independent roots; prepare → analyze → report is the linear chain.
    public var requiredPredecessor: PRRadarPhase? {
        switch self {
        case .metadata: nil
        case .diff: nil
        case .prepare: .diff
        case .analyze: .prepare
        case .report: .analyze
        }
    }

    /// Human-readable display name for the phase.
    public var displayName: String {
        switch self {
        case .metadata: "Metadata"
        case .diff: "Diff"
        case .prepare: "Prepare"
        case .analyze: "Analyze"
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
    public static let dataFilePrefix = "data-"

    // Subdirectory names within the prepare phase
    public static let prepareFocusAreasSubdir = "focus-areas"
    public static let prepareRulesSubdir = "rules"
    public static let prepareTasksSubdir = "tasks"

    // Top-level directory names
    public static let metadataDirectoryName = "metadata"
    public static let analysisDirectoryName = "analysis"

    // MARK: - Metadata Phase Filenames
    public static let ghPRFilename = "gh-pr.json"
    public static let ghCommentsFilename = "gh-comments.json"
    public static let ghRepoFilename = "gh-repo.json"
    public static let imageURLMapFilename = "image-url-map.json"

    // MARK: - Diff Phase Filenames
    public static let diffRawFilename = "diff-raw.diff"
    public static let diffParsedJSONFilename = "diff-parsed.json"
    public static let diffParsedMarkdownFilename = "diff-parsed.md"
    public static let effectiveDiffParsedJSONFilename = "effective-diff-parsed.json"
    public static let effectiveDiffParsedMarkdownFilename = "effective-diff-parsed.md"
    public static let effectiveDiffMovesFilename = "effective-diff-moves.json"

    // MARK: - Prepare Phase Filenames
    public static let allRulesFilename = "all-rules.json"

    // MARK: - Analyze / Report Phase Filenames
    public static let summaryJSONFilename = "summary.json"
    public static let summaryMarkdownFilename = "summary.md"

    // MARK: - Directory Construction

    /// PR-level metadata directory: `<output>/<prNumber>/metadata/`
    public static func metadataDirectory(
        outputDir: String,
        prNumber: Int
    ) -> String {
        "\(outputDir)/\(prNumber)/\(metadataDirectoryName)"
    }

    /// Commit-level analysis root: `<output>/<prNumber>/analysis/<commitHash>/`
    public static func analysisDirectory(
        outputDir: String,
        prNumber: Int,
        commitHash: String
    ) -> String {
        "\(outputDir)/\(prNumber)/\(analysisDirectoryName)/\(commitHash)"
    }

    /// Directory for a specific phase.
    ///
    /// - For `.metadata` (PR-scoped): `<output>/<prNumber>/metadata/`
    /// - For commit-scoped phases with `commitHash`: `<output>/<prNumber>/analysis/<commitHash>/<phase>/`
    /// - For commit-scoped phases without `commitHash`: `<output>/<prNumber>/<phase>/` (legacy flat layout)
    ///
    /// The legacy flat layout is a transitional path. Once all callers provide a commit hash,
    /// the nil-commitHash branch can be removed.
    public static func phaseDirectory(
        outputDir: String,
        prNumber: Int,
        phase: PRRadarPhase,
        commitHash: String? = nil
    ) -> String {
        if phase == .metadata {
            return metadataDirectory(outputDir: outputDir, prNumber: prNumber)
        }
        guard let commitHash else {
            return "\(outputDir)/\(prNumber)/\(phase.rawValue)"
        }
        return "\(analysisDirectory(outputDir: outputDir, prNumber: prNumber, commitHash: commitHash))/\(phase.rawValue)"
    }

    /// Get a subdirectory within a phase directory (e.g., focus-areas within prepare).
    public static func phaseSubdirectory(
        outputDir: String,
        prNumber: Int,
        phase: PRRadarPhase,
        subdirectory: String,
        commitHash: String? = nil
    ) -> String {
        "\(phaseDirectory(outputDir: outputDir, prNumber: prNumber, phase: phase, commitHash: commitHash))/\(subdirectory)"
    }

    public static func ensureDirectoryExists(at path: String) throws {
        try FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true
        )
    }

    /// Check whether a phase directory exists and has content.
    public static func phaseExists(
        outputDir: String,
        prNumber: Int,
        phase: PRRadarPhase,
        commitHash: String? = nil
    ) -> Bool {
        let dir = phaseDirectory(outputDir: outputDir, prNumber: prNumber, phase: phase, commitHash: commitHash)
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
        prNumber: Int,
        commitHash: String? = nil
    ) -> Bool {
        guard let predecessor = phase.requiredPredecessor else { return true }
        return phaseExists(outputDir: outputDir, prNumber: prNumber, phase: predecessor, commitHash: commitHash)
    }

    /// Validate that a phase can run, returning an error message if not.
    public static func validateCanRun(
        _ phase: PRRadarPhase,
        outputDir: String,
        prNumber: Int,
        commitHash: String? = nil
    ) -> String? {
        guard canRunPhase(phase, outputDir: outputDir, prNumber: prNumber, commitHash: commitHash) else {
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
        prNumber: Int,
        commitHash: String? = nil
    ) -> PhaseStatus {
        let dir = phaseDirectory(outputDir: outputDir, prNumber: prNumber, phase: phase, commitHash: commitHash)

        guard let phaseResult = readPhaseResult(directory: dir, phase: phase) else {
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
        prNumber: Int,
        commitHash: String? = nil
    ) -> [PRRadarPhase: PhaseStatus] {
        var result: [PRRadarPhase: PhaseStatus] = [:]
        for phase in PRRadarPhase.allCases {
            result[phase] = phaseStatus(phase, outputDir: outputDir, prNumber: prNumber, commitHash: commitHash)
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
