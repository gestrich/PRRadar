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

    /// Phase 1 required artifact filenames.
    public static let pullRequestRequiredFiles = [
        "diff-raw.diff",
        "diff-parsed.json",
        "diff-parsed.md",
        "gh-pr.json",
        "gh-comments.json",
        "gh-repo.json",
        "effective-diff-parsed.json",
        "effective-diff-parsed.md",
        "effective-diff-moves.json",
    ]

    /// Phase 6 required artifact filenames.
    public static let reportRequiredFiles = [
        "summary.json",
        "summary.md",
    ]

    /// Get detailed completion status for a single phase.
    public static func phaseStatus(
        _ phase: PRRadarPhase,
        outputDir: String,
        prNumber: String
    ) -> PhaseStatus {
        let dir = phaseDirectory(outputDir: outputDir, prNumber: prNumber, phase: phase)

        switch phase {
        case .pullRequest:
            return fixedFileStatus(phase: phase, directory: dir, requiredFiles: pullRequestRequiredFiles)
        case .focusAreas:
            return jsonFileCountStatus(phase: phase, directory: dir)
        case .rules:
            return fixedFileStatus(phase: phase, directory: dir, requiredFiles: ["all-rules.json"])
        case .tasks:
            return jsonFileCountStatus(phase: phase, directory: dir)
        case .evaluations:
            return evaluationsStatus(directory: dir, outputDir: outputDir, prNumber: prNumber)
        case .report:
            return fixedFileStatus(phase: phase, directory: dir, requiredFiles: reportRequiredFiles)
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

    private static func fixedFileStatus(
        phase: PRRadarPhase,
        directory: String,
        requiredFiles: [String]
    ) -> PhaseStatus {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory, isDirectory: &isDir), isDir.boolValue else {
            return PhaseStatus(
                phase: phase, exists: false, isComplete: false,
                completedCount: 0, totalCount: requiredFiles.count,
                missingItems: requiredFiles
            )
        }

        let missing = requiredFiles.filter { !fm.fileExists(atPath: "\(directory)/\($0)") }
        return PhaseStatus(
            phase: phase, exists: true, isComplete: missing.isEmpty,
            completedCount: requiredFiles.count - missing.count, totalCount: requiredFiles.count,
            missingItems: missing
        )
    }

    private static func jsonFileCountStatus(
        phase: PRRadarPhase,
        directory: String
    ) -> PhaseStatus {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory, isDirectory: &isDir), isDir.boolValue else {
            return PhaseStatus(
                phase: phase, exists: false, isComplete: false,
                completedCount: 0, totalCount: 1, missingItems: []
            )
        }

        let files = ((try? fm.contentsOfDirectory(atPath: directory)) ?? [])
            .filter { $0.hasSuffix(".json") }
        return PhaseStatus(
            phase: phase, exists: true, isComplete: !files.isEmpty,
            completedCount: files.count, totalCount: max(files.count, 1),
            missingItems: files.isEmpty ? ["<type>.json"] : []
        )
    }

    private static func evaluationsStatus(
        directory: String,
        outputDir: String,
        prNumber: String
    ) -> PhaseStatus {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let tasksDir = phaseDirectory(outputDir: outputDir, prNumber: prNumber, phase: .tasks)

        guard fm.fileExists(atPath: directory, isDirectory: &isDir), isDir.boolValue else {
            let taskCount = ((try? fm.contentsOfDirectory(atPath: tasksDir)) ?? [])
                .filter { $0.hasSuffix(".json") }.count
            return PhaseStatus(
                phase: .evaluations, exists: false, isComplete: false,
                completedCount: 0, totalCount: taskCount, missingItems: []
            )
        }

        // Find expected task IDs
        var expectedIds = Set<String>()
        if let taskFiles = try? fm.contentsOfDirectory(atPath: tasksDir) {
            for file in taskFiles where file.hasSuffix(".json") {
                let path = "\(tasksDir)/\(file)"
                if let data = fm.contents(atPath: path),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let taskId = json["task_id"] as? String {
                    expectedIds.insert(taskId)
                }
            }
        }

        let completedFiles = ((try? fm.contentsOfDirectory(atPath: directory)) ?? [])
            .filter { $0.hasSuffix(".json") && $0 != "summary.json" }
        let completedIds = Set(completedFiles.map { ($0 as NSString).deletingPathExtension })
        let missing = expectedIds.subtracting(completedIds).sorted()

        return PhaseStatus(
            phase: .evaluations, exists: true,
            isComplete: missing.isEmpty && !expectedIds.isEmpty,
            completedCount: completedIds.count, totalCount: expectedIds.count,
            missingItems: missing
        )
    }
}
