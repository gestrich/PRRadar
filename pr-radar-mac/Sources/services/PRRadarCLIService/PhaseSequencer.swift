import Foundation
import PRRadarConfigService
import PRRadarModels

/// Manages the pipeline directory layout and phase sequencing.
///
/// Provides utilities for path management, dependency validation,
/// completion status checking, and resume support.
public struct PhaseSequencer: Sendable {
    public init() {}

    // MARK: - Path Management

    /// Get the directory path for a given phase.
    public static func getPhaseDir(outputDir: String, phase: PRRadarPhase) -> String {
        "\(outputDir)/\(phase.rawValue)"
    }

    /// Get and create the directory for a phase.
    public static func ensurePhaseDir(outputDir: String, phase: PRRadarPhase) throws -> String {
        let dir = getPhaseDir(outputDir: outputDir, phase: phase)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Dependency Validation

    /// Check if a phase directory exists and has content.
    public static func phaseExists(outputDir: String, phase: PRRadarPhase) -> Bool {
        DataPathsService.phaseExists(outputDir: outputDir, prNumber: "", phase: phase)
    }

    /// Check if a phase can run (dependencies satisfied).
    public static func canRunPhase(_ phase: PRRadarPhase, outputDir: String) -> Bool {
        guard let predecessor = phase.requiredPredecessor else { return true }
        let predDir = getPhaseDir(outputDir: outputDir, phase: predecessor)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: predDir, isDirectory: &isDir), isDir.boolValue else { return false }
        let contents = (try? fm.contentsOfDirectory(atPath: predDir)) ?? []
        return !contents.isEmpty
    }

    /// Validate that a phase can run, returning an error message if not.
    public static func validateCanRun(_ phase: PRRadarPhase, outputDir: String) -> String? {
        guard canRunPhase(phase, outputDir: outputDir) else {
            guard let predecessor = phase.requiredPredecessor else { return nil }
            return "Cannot run \(phase.rawValue): \(predecessor.rawValue) has not completed"
        }
        return nil
    }

    // MARK: - Resume Support

    /// Get items that still need processing.
    ///
    /// Returns (remaining items, number skipped).
    public static func getRemainingItems(
        outputDir: String,
        phase: PRRadarPhase,
        allItems: [String]
    ) -> (remaining: [String], skipped: Int) {
        let phaseDir = getPhaseDir(outputDir: outputDir, phase: phase)
        let fm = FileManager.default

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: phaseDir, isDirectory: &isDir), isDir.boolValue else {
            return (allItems, 0)
        }

        let completedFiles = ((try? fm.contentsOfDirectory(atPath: phaseDir)) ?? [])
            .filter { $0.hasSuffix(".json") && $0 != "summary.json" }
        let completedIds = Set(completedFiles.map { ($0 as NSString).deletingPathExtension })

        guard !completedIds.isEmpty else {
            return (allItems, 0)
        }

        let remaining = allItems.filter { !completedIds.contains($0) }
        let skipped = allItems.count - remaining.count
        return (remaining, skipped)
    }

    // MARK: - Status

    /// Get detailed completion status for a phase.
    public static func getPhaseStatus(outputDir: String, phase: PRRadarPhase) -> PhaseStatus {
        let dir = getPhaseDir(outputDir: outputDir, phase: phase)

        switch phase {
        case .pullRequest:
            return fixedFileStatus(phase: phase, directory: dir, requiredFiles: DataPathsService.pullRequestRequiredFiles)
        case .focusAreas:
            return jsonFileCountStatus(phase: phase, directory: dir)
        case .rules:
            return fixedFileStatus(phase: phase, directory: dir, requiredFiles: ["all-rules.json"])
        case .tasks:
            return jsonFileCountStatus(phase: phase, directory: dir)
        case .evaluations:
            return evaluationsStatus(directory: dir, outputDir: outputDir)
        case .report:
            return fixedFileStatus(phase: phase, directory: dir, requiredFiles: DataPathsService.reportRequiredFiles)
        }
    }

    /// Get status for all phases.
    public static func getAllStatuses(outputDir: String) -> [PRRadarPhase: PhaseStatus] {
        var result: [PRRadarPhase: PhaseStatus] = [:]
        for phase in PRRadarPhase.allCases {
            result[phase] = getPhaseStatus(outputDir: outputDir, phase: phase)
        }
        return result
    }

    /// Format a pipeline status summary string.
    public static func formatPipelineStatus(outputDir: String) -> String {
        let statuses = getAllStatuses(outputDir: outputDir)
        var lines: [String] = []

        lines.append("")
        lines.append("Pipeline Status:")
        lines.append(String(repeating: "=", count: 60))

        for phase in PRRadarPhase.allCases {
            let status = statuses[phase]!

            let indicator: String
            if status.isComplete {
                indicator = "✓"
            } else if status.isPartial {
                indicator = "⚠"
            } else if status.exists {
                indicator = "✗"
            } else {
                indicator = " "
            }

            let progress: String
            if status.totalCount > 0 {
                let pct = status.completionPercentage
                progress = "\(status.completedCount)/\(status.totalCount) (\(String(format: "%.0f", pct))%)"
            } else {
                progress = status.summary
            }

            let paddedPhase = phase.rawValue.padding(toLength: 25, withPad: " ", startingAt: 0)
            lines.append("  \(indicator) \(paddedPhase) \(progress)")
        }

        return lines.joined(separator: "\n")
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
        outputDir: String
    ) -> PhaseStatus {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let tasksDir = getPhaseDir(outputDir: outputDir, phase: .tasks)

        guard fm.fileExists(atPath: directory, isDirectory: &isDir), isDir.boolValue else {
            let taskCount = ((try? fm.contentsOfDirectory(atPath: tasksDir)) ?? [])
                .filter { $0.hasSuffix(".json") }.count
            return PhaseStatus(
                phase: .evaluations, exists: false, isComplete: false,
                completedCount: 0, totalCount: taskCount, missingItems: []
            )
        }

        var expectedIds = Set<String>()
        if let taskFiles = try? fm.contentsOfDirectory(atPath: tasksDir) {
            for file in taskFiles where file.hasSuffix(".json") {
                let path = "\(tasksDir)/\(file)"
                guard let data = fm.contents(atPath: path),
                      let task = try? JSONDecoder().decode(EvaluationTaskOutput.self, from: data) else { continue }
                expectedIds.insert(task.taskId)
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
