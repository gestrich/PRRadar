import Foundation
import PRRadarConfigService
import PRRadarModels

/// Pure transformation service for converting evaluation results into PRComment instances.
public struct ViolationService: Sendable {
    public init() {}

    /// Filter evaluation results by violation status and score, converting to PRComment instances.
    public static func filterByScore(
        results: [RuleEvaluationResult],
        tasks: [EvaluationTaskOutput],
        minScore: Int
    ) -> [PRComment] {
        let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.taskId, $0) })
        var comments: [PRComment] = []

        for result in results {
            guard result.evaluation.violatesRule else { continue }
            guard result.evaluation.score >= minScore else { continue }
            comments.append(PRComment.from(evaluation: result, task: taskMap[result.taskId]))
        }

        return comments
    }

    /// Load violations from evaluation result files on disk.
    public static func loadViolations(
        evaluationsDir: String,
        tasksDir: String,
        minScore: Int
    ) -> [PRComment] {
        let fm = FileManager.default
        var comments: [PRComment] = []

        // Load task metadata
        var taskMetadata: [String: EvaluationTaskOutput] = [:]
        if let taskFiles = try? fm.contentsOfDirectory(atPath: tasksDir) {
            for file in taskFiles where file.hasPrefix(DataPathsService.dataFilePrefix) {
                let path = "\(tasksDir)/\(file)"
                guard let data = fm.contents(atPath: path),
                      let task = try? JSONDecoder().decode(EvaluationTaskOutput.self, from: data) else { continue }
                taskMetadata[task.taskId] = task
            }
        }

        guard let evalFiles = try? fm.contentsOfDirectory(atPath: evaluationsDir) else { return comments }

        for file in evalFiles where file.hasPrefix(DataPathsService.dataFilePrefix) {
            let path = "\(evaluationsDir)/\(file)"
            guard let data = fm.contents(atPath: path),
                  let result = try? JSONDecoder().decode(RuleEvaluationResult.self, from: data) else { continue }

            guard result.evaluation.violatesRule else { continue }
            guard result.evaluation.score >= minScore else { continue }

            comments.append(PRComment.from(evaluation: result, task: taskMetadata[result.taskId]))
        }

        return comments
    }
}
