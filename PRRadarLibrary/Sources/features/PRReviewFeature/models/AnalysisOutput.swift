import Foundation
import PRRadarCLIService
import PRRadarModels

public struct AnalysisOutput: Sendable {
    public var evaluations: [RuleEvaluationResult]
    public var tasks: [AnalysisTaskOutput]
    public var summary: AnalysisSummary
    public var cachedCount: Int

    public static let empty = AnalysisOutput(
        evaluations: [],
        summary: AnalysisSummary(prNumber: 0, evaluatedAt: "", totalTasks: 0, violationsFound: 0, totalCostUsd: 0, totalDurationMs: 0, results: [])
    )

    public init(streaming tasks: [AnalysisTaskOutput]) {
        self.evaluations = []
        self.tasks = tasks
        self.summary = AnalysisSummary(prNumber: 0, evaluatedAt: "", totalTasks: 0, violationsFound: 0, totalCostUsd: 0, totalDurationMs: 0, results: [])
        self.cachedCount = 0
    }

    public init(evaluations: [RuleEvaluationResult], tasks: [AnalysisTaskOutput] = [], summary: AnalysisSummary, cachedCount: Int = 0) {
        self.evaluations = evaluations
        self.tasks = tasks
        self.summary = summary
        self.cachedCount = cachedCount
    }

    public mutating func appendResult(_ result: RuleEvaluationResult, prNumber: Int) {
        if let existingIndex = evaluations.firstIndex(where: { $0.taskId == result.taskId }) {
            evaluations[existingIndex] = result
        } else {
            evaluations.append(result)
        }

        let violationCount = evaluations.filter(\.isViolation).count
        summary = AnalysisSummary(
            prNumber: prNumber,
            evaluatedAt: ISO8601DateFormatter().string(from: Date()),
            totalTasks: evaluations.count,
            violationsFound: violationCount,
            totalCostUsd: evaluations.compactMap(\.costUsd).reduce(0, +),
            totalDurationMs: evaluations.map(\.durationMs).reduce(0, +),
            results: evaluations
        )
    }

    /// Build a cumulative output from a running list of evaluations, deduplicating by taskId.
    static func cumulative(evaluations: [RuleEvaluationResult], tasks: [AnalysisTaskOutput], prNumber: Int, cachedCount: Int = 0) -> AnalysisOutput {
        var seen = Set<String>()
        var deduped: [RuleEvaluationResult] = []
        for eval in evaluations.reversed() {
            if seen.insert(eval.taskId).inserted {
                deduped.append(eval)
            }
        }
        deduped.reverse()

        let violationCount = deduped.filter(\.isViolation).count
        let summary = AnalysisSummary(
            prNumber: prNumber,
            evaluatedAt: ISO8601DateFormatter().string(from: Date()),
            totalTasks: deduped.count,
            violationsFound: violationCount,
            totalCostUsd: deduped.compactMap(\.costUsd).reduce(0, +),
            totalDurationMs: deduped.map(\.durationMs).reduce(0, +),
            results: deduped
        )

        return AnalysisOutput(evaluations: deduped, tasks: tasks, summary: summary, cachedCount: cachedCount)
    }

    /// Merge evaluations with task metadata into structured comments.
    public var comments: [PRComment] {
        let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.taskId, $0) })
        return evaluations.compactMap { $0.violationComment(task: taskMap[$0.taskId]) }
    }
}
