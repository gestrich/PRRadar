import Foundation
import PRRadarConfigService
import PRRadarModels

public enum AnalysisCacheService {

    public static let taskFilePrefix = "task-"

    /// Partition tasks into cached (reusable) results and tasks needing fresh evaluation.
    ///
    /// For each task, checks if a prior evaluation result and task snapshot exist in the
    /// evaluations directory. If both exist and the git blob hash matches, the prior result
    /// is reused instead of re-evaluating.
    public static func partitionTasks(
        tasks: [AnalysisTaskOutput],
        evalsDir: String
    ) -> (cached: [RuleEvaluationResult], toEvaluate: [AnalysisTaskOutput]) {
        let decoder = JSONDecoder()
        var cached: [RuleEvaluationResult] = []
        var toEvaluate: [AnalysisTaskOutput] = []

        for task in tasks {
            let evalPath = "\(evalsDir)/\(DataPathsService.dataFilePrefix)\(task.taskId).json"
            let taskPath = "\(evalsDir)/\(taskFilePrefix)\(task.taskId).json"

            guard
                let evalData = FileManager.default.contents(atPath: evalPath),
                let taskData = FileManager.default.contents(atPath: taskPath),
                let priorResult = try? decoder.decode(RuleEvaluationResult.self, from: evalData),
                let priorTask = try? decoder.decode(AnalysisTaskOutput.self, from: taskData),
                priorTask.gitBlobHash == task.gitBlobHash
            else {
                toEvaluate.append(task)
                continue
            }

            cached.append(priorResult)
        }

        return (cached, toEvaluate)
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
    public static func cachedTaskMessage(index: Int, totalCount: Int, result: RuleEvaluationResult) -> String {
        let status = result.evaluation.violatesRule ? "VIOLATION (\(result.evaluation.score)/10)" : "OK"
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
        tasks: [AnalysisTaskOutput],
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
