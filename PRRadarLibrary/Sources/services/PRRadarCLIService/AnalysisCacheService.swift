import Foundation
import PRRadarConfigService
import PRRadarModels

public enum AnalysisCacheService {

    public static let taskFilePrefix = "task-"

    /// Partition tasks into cached (reusable) results and tasks needing fresh evaluation.
    ///
    /// First checks the current commit's evaluate directory for same-commit cache hits.
    /// Then, if `prOutputDir` is provided, scans prior commit directories under
    /// `analysis/*/evaluate/` for cross-commit cache hits (matching both blob hashes).
    /// Cached results from prior commits are copied into the current evaluate directory
    /// so each commit directory is self-contained.
    public static func partitionTasks(
        tasks: [RuleRequest],
        evalsDir: String,
        prOutputDir: String? = nil
    ) -> (cached: [RuleOutcome], toEvaluate: [RuleRequest]) {
        let decoder = JSONDecoder()
        var cached: [RuleOutcome] = []
        var toEvaluate: [RuleRequest] = []

        let priorEvalsDirs = prOutputDir.map { findPriorEvalsDirs(prOutputDir: $0, currentEvalsDir: evalsDir) } ?? []

        for task in tasks {
            // Try same-commit cache first
            if let result = lookupCachedResult(task: task, evalsDir: evalsDir, decoder: decoder) {
                cached.append(result)
                continue
            }

            // Try cross-commit cache from prior commit directories
            if let result = lookupCrossCommitResult(task: task, priorEvalsDirs: priorEvalsDirs, targetEvalsDir: evalsDir, decoder: decoder) {
                cached.append(result)
                continue
            }

            toEvaluate.append(task)
        }

        return (cached, toEvaluate)
    }

    // MARK: - Cache Lookup

    /// Check a single evaluate directory for a cached result matching both blob hashes.
    private static func lookupCachedResult(
        task: RuleRequest,
        evalsDir: String,
        decoder: JSONDecoder
    ) -> RuleOutcome? {
        let evalPath = "\(evalsDir)/\(DataPathsService.dataFilePrefix)\(task.taskId).json"
        let taskPath = "\(evalsDir)/\(taskFilePrefix)\(task.taskId).json"

        guard
            let evalData = FileManager.default.contents(atPath: evalPath),
            let taskData = FileManager.default.contents(atPath: taskPath),
            let priorResult = try? decoder.decode(RuleOutcome.self, from: evalData),
            let priorTask = try? decoder.decode(RuleRequest.self, from: taskData),
            blobHashesMatch(prior: priorTask, current: task)
        else {
            return nil
        }

        return priorResult
    }

    /// Scan prior commit evaluate directories for a matching cached result.
    /// When found, copies the result and task snapshot into the target evaluate directory.
    private static func lookupCrossCommitResult(
        task: RuleRequest,
        priorEvalsDirs: [String],
        targetEvalsDir: String,
        decoder: JSONDecoder
    ) -> RuleOutcome? {
        for priorDir in priorEvalsDirs {
            guard let result = lookupCachedResult(task: task, evalsDir: priorDir, decoder: decoder) else {
                continue
            }

            // Copy cached files into current commit's evaluate directory
            let evalFilename = "\(DataPathsService.dataFilePrefix)\(task.taskId).json"
            let taskFilename = "\(taskFilePrefix)\(task.taskId).json"
            copyFile(from: "\(priorDir)/\(evalFilename)", to: "\(targetEvalsDir)/\(evalFilename)")
            copyFile(from: "\(priorDir)/\(taskFilename)", to: "\(targetEvalsDir)/\(taskFilename)")

            // Copy transcript files so AI Output view can display them
            let transcriptBase = "ai-transcript-\(task.taskId)"
            copyFile(from: "\(priorDir)/\(transcriptBase).json", to: "\(targetEvalsDir)/\(transcriptBase).json")
            copyFile(from: "\(priorDir)/\(transcriptBase).md", to: "\(targetEvalsDir)/\(transcriptBase).md")

            return result
        }
        return nil
    }

    /// Compare both gitBlobHash and ruleBlobHash between a prior task snapshot and the current task.
    /// A nil ruleBlobHash on both sides is treated as a match (backward compatibility).
    private static func blobHashesMatch(prior: RuleRequest, current: RuleRequest) -> Bool {
        guard prior.gitBlobHash == current.gitBlobHash else { return false }
        guard prior.ruleBlobHash == current.ruleBlobHash else { return false }
        return true
    }

    // MARK: - Cross-Commit Directory Discovery

    /// Find evaluate directories from prior commits under `<prOutputDir>/analysis/*/evaluate/`.
    /// Excludes the current commit's evaluate directory. Returns directories sorted by
    /// modification date (most recent first) for optimal cache hit performance.
    static func findPriorEvalsDirs(
        prOutputDir: String,
        currentEvalsDir: String
    ) -> [String] {
        let analysisDir = "\(prOutputDir)/\(DataPathsService.analysisDirectoryName)"
        guard let commitDirs = try? FileManager.default.contentsOfDirectory(atPath: analysisDir) else {
            return []
        }

        let fm = FileManager.default
        var dirsWithDates: [(path: String, date: Date)] = []

        for commitDir in commitDirs {
            let evalsPath = "\(analysisDir)/\(commitDir)/\(PRRadarPhase.analyze.rawValue)"
            guard evalsPath != currentEvalsDir else { continue }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: evalsPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let modDate = (try? fm.attributesOfItem(atPath: evalsPath)[.modificationDate] as? Date) ?? .distantPast
            dirsWithDates.append((evalsPath, modDate))
        }

        return dirsWithDates
            .sorted { $0.date > $1.date }
            .map(\.path)
    }

    // MARK: - File Helpers

    private static func copyFile(from sourcePath: String, to destPath: String) {
        let fm = FileManager.default
        let destDir = (destPath as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
        try? fm.removeItem(atPath: destPath)
        try? fm.copyItem(atPath: sourcePath, toPath: destPath)
    }

    // MARK: - Progress Messages

    /// Start message describing cache partition results.
    public static func startMessage(cachedCount: Int, freshCount: Int, totalCount: Int) -> String {
        if cachedCount > 0 {
            return "Skipping \(cachedCount) cached evaluations, evaluating \(freshCount) new tasks"
        }
        return "Evaluating \(totalCount) tasks..."
    }

    /// Per-task progress line for a cached result.
    public static func cachedTaskMessage(index: Int, totalCount: Int, result: RuleOutcome) -> String {
        let status: String
        switch result {
        case .success(let s):
            if s.violatesRule {
                let maxScore = s.violations.map(\.score).max() ?? 0
                status = "VIOLATION (\(s.violations.count) finding\(s.violations.count == 1 ? "" : "s"), max \(maxScore)/10)"
            } else {
                status = "OK"
            }
        case .error(let e):
            status = "ERROR: \(e.errorMessage)"
        }
        return "[\(index)/\(totalCount)] \(result.ruleName) — \(status) (cached)"
    }

    /// End-of-run summary message.
    public static func completionMessage(freshCount: Int, cachedCount: Int, totalCount: Int, violationCount: Int) -> String {
        if cachedCount > 0 {
            return "Evaluation complete: \(freshCount) new, \(cachedCount) cached, \(totalCount) total — \(violationCount) violations found"
        }
        return "Evaluation complete: \(totalCount) evaluated — \(violationCount) violations found"
    }

    /// Write task snapshots to the evaluations directory for future cache checks.
    public static func writeTaskSnapshots(
        tasks: [RuleRequest],
        evalsDir: String
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try DataPathsService.ensureDirectoryExists(at: evalsDir)
        for task in tasks {
            let taskData = try encoder.encode(task)
            let taskPath = "\(evalsDir)/\(taskFilePrefix)\(task.taskId).json"
            try taskData.write(to: URL(fileURLWithPath: taskPath))
        }
    }
}
