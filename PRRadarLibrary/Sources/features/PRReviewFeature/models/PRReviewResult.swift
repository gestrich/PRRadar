import Foundation
import PRRadarCLIService
import PRRadarModels

public struct PRReviewResult: Sendable {
    public var evaluations: [RuleOutcome]
    public var tasks: [RuleRequest]
    public var summary: PRReviewSummary
    public var cachedCount: Int

    public static let empty = PRReviewResult(
        evaluations: [],
        summary: PRReviewSummary(prNumber: 0, evaluatedAt: "", totalTasks: 0, violationsFound: 0, totalCostUsd: 0, totalDurationMs: 0)
    )

    public init(streaming tasks: [RuleRequest]) {
        self.evaluations = []
        self.tasks = tasks
        self.summary = PRReviewSummary(prNumber: 0, evaluatedAt: "", totalTasks: 0, violationsFound: 0, totalCostUsd: 0, totalDurationMs: 0)
        self.cachedCount = 0
    }

    public init(evaluations: [RuleOutcome], tasks: [RuleRequest] = [], summary: PRReviewSummary, cachedCount: Int = 0) {
        self.evaluations = evaluations
        self.tasks = tasks
        self.summary = summary
        self.cachedCount = cachedCount
    }

    public mutating func appendResult(_ result: RuleOutcome, prNumber: Int) {
        if let existingIndex = evaluations.firstIndex(where: { $0.taskId == result.taskId }) {
            evaluations[existingIndex] = result
        } else {
            evaluations.append(result)
        }

        let violationCount = evaluations.filter(\.isViolation).count
        summary = PRReviewSummary(
            prNumber: prNumber,
            evaluatedAt: ISO8601DateFormatter().string(from: Date()),
            totalTasks: evaluations.count,
            violationsFound: violationCount,
            totalCostUsd: evaluations.compactMap(\.costUsd).reduce(0, +),
            totalDurationMs: evaluations.map(\.durationMs).reduce(0, +)
        )
    }

    /// Build a cumulative output from a running list of evaluations, deduplicating by taskId.
    static func cumulative(evaluations: [RuleOutcome], tasks: [RuleRequest], prNumber: Int, cachedCount: Int = 0) -> PRReviewResult {
        var seen = Set<String>()
        var deduped: [RuleOutcome] = []
        for eval in evaluations.reversed() {
            if seen.insert(eval.taskId).inserted {
                deduped.append(eval)
            }
        }
        deduped.reverse()

        let violationCount = deduped.filter(\.isViolation).count
        let summary = PRReviewSummary(
            prNumber: prNumber,
            evaluatedAt: ISO8601DateFormatter().string(from: Date()),
            totalTasks: deduped.count,
            violationsFound: violationCount,
            totalCostUsd: deduped.compactMap(\.costUsd).reduce(0, +),
            totalDurationMs: deduped.map(\.durationMs).reduce(0, +)
        )

        return PRReviewResult(evaluations: deduped, tasks: tasks, summary: summary, cachedCount: cachedCount)
    }

    /// Merge evaluations with task metadata into structured comments.
    public var comments: [PRComment] {
        let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.taskId, $0) })
        return evaluations.compactMap { $0.violationComment(task: taskMap[$0.taskId]) }
    }
}
