import Foundation
import PRRadarConfigService
import PRRadarModels

public enum EvaluationCacheService {

    public static let taskFilePrefix = "task-"

    /// Partition tasks into cached (reusable) results and tasks needing fresh evaluation.
    ///
    /// For each task, checks if a prior evaluation result and task snapshot exist in the
    /// evaluations directory. If both exist and the git blob hash matches, the prior result
    /// is reused instead of re-evaluating.
    public static func partitionTasks(
        tasks: [EvaluationTaskOutput],
        evalsDir: String
    ) -> (cached: [RuleEvaluationResult], toEvaluate: [EvaluationTaskOutput]) {
        let decoder = JSONDecoder()
        var cached: [RuleEvaluationResult] = []
        var toEvaluate: [EvaluationTaskOutput] = []

        for task in tasks {
            let evalPath = "\(evalsDir)/\(DataPathsService.dataFilePrefix)\(task.taskId).json"
            let taskPath = "\(evalsDir)/\(taskFilePrefix)\(task.taskId).json"

            guard
                let evalData = FileManager.default.contents(atPath: evalPath),
                let taskData = FileManager.default.contents(atPath: taskPath),
                let priorResult = try? decoder.decode(RuleEvaluationResult.self, from: evalData),
                let priorTask = try? decoder.decode(EvaluationTaskOutput.self, from: taskData),
                priorTask.gitBlobHash == task.gitBlobHash
            else {
                toEvaluate.append(task)
                continue
            }

            cached.append(priorResult)
        }

        return (cached, toEvaluate)
    }

    /// Write task snapshots to the evaluations directory for future cache checks.
    public static func writeTaskSnapshots(
        tasks: [EvaluationTaskOutput],
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
