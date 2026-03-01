import Foundation
import PRRadarCLIService
import PRRadarModels

public struct PRReviewResult: Sendable {
    public var taskEvaluations: [TaskEvaluation]
    public var summary: PRReviewSummary
    public var cachedCount: Int

    public static let empty = PRReviewResult(
        taskEvaluations: [],
        summary: PRReviewSummary(prNumber: 0, evaluatedAt: "", totalTasks: 0, violationsFound: 0, totalCostUsd: 0, totalDurationMs: 0)
    )

    public init(streaming tasks: [RuleRequest]) {
        self.taskEvaluations = tasks.map { TaskEvaluation(request: $0, phase: .analyze) }
        self.summary = PRReviewSummary(prNumber: 0, evaluatedAt: "", totalTasks: 0, violationsFound: 0, totalCostUsd: 0, totalDurationMs: 0)
        self.cachedCount = 0
    }

    public init(taskEvaluations: [TaskEvaluation], summary: PRReviewSummary, cachedCount: Int = 0) {
        self.taskEvaluations = taskEvaluations
        self.summary = summary
        self.cachedCount = cachedCount
    }

    public init(tasks: [RuleRequest], outcomes: [RuleOutcome], summary: PRReviewSummary, cachedCount: Int = 0) {
        let outcomeMap = Dictionary(outcomes.map { ($0.taskId, $0) }, uniquingKeysWith: { _, latest in latest })
        self.taskEvaluations = tasks.map { task in
            TaskEvaluation(request: task, phase: .analyze, outcome: outcomeMap[task.taskId])
        }
        self.summary = summary
        self.cachedCount = cachedCount
    }

    public mutating func appendResult(_ result: RuleOutcome, prNumber: Int) {
        if let idx = taskEvaluations.indexForTaskId(result.taskId) {
            taskEvaluations[idx].outcome = result
        }

        let violationCount = taskEvaluations.violationComments.count
        let outcomes = taskEvaluations.outcomes
        summary = PRReviewSummary(
            prNumber: prNumber,
            evaluatedAt: ISO8601DateFormatter().string(from: Date()),
            totalTasks: outcomes.count,
            violationsFound: violationCount,
            totalCostUsd: outcomes.compactMap(\.costUsd).reduce(0, +),
            totalDurationMs: outcomes.map(\.durationMs).reduce(0, +)
        )
    }

    /// Build a cumulative result from task evaluations, deduplicating by taskId.
    public static func cumulative(taskEvaluations: [TaskEvaluation], prNumber: Int, cachedCount: Int = 0) -> PRReviewResult {
        var seen = Set<String>()
        var deduped: [TaskEvaluation] = []
        for eval in taskEvaluations.reversed() {
            if seen.insert(eval.request.taskId).inserted {
                deduped.append(eval)
            }
        }
        deduped.reverse()

        let violationCount = deduped.violationComments.count
        let outcomes = deduped.outcomes
        let summary = PRReviewSummary(
            prNumber: prNumber,
            evaluatedAt: ISO8601DateFormatter().string(from: Date()),
            totalTasks: outcomes.count,
            violationsFound: violationCount,
            totalCostUsd: outcomes.compactMap(\.costUsd).reduce(0, +),
            totalDurationMs: outcomes.map(\.durationMs).reduce(0, +)
        )

        return PRReviewResult(taskEvaluations: deduped, summary: summary, cachedCount: cachedCount)
    }

    public var modelsUsed: [String] {
        Array(Set(taskEvaluations.outcomes.map(\.analysisMethod.displayName))).sorted()
    }

    public var comments: [PRComment] {
        taskEvaluations.violationComments
    }
}
