import Foundation

public struct TaskEvaluation: Identifiable, Sendable {
    public let request: RuleRequest
    public let phase: PRRadarPhase
    public var accumulator: LiveTranscriptAccumulator?
    public var savedOutput: EvaluationOutput?
    public var outcome: RuleOutcome?

    public var id: String { request.taskId }

    public var isStreaming: Bool { accumulator != nil && outcome == nil }
    public var isComplete: Bool { outcome != nil }
    public var isQueued: Bool { accumulator == nil && outcome == nil }

    public var evaluationOutput: EvaluationOutput? {
        if let acc = accumulator {
            return acc.toEvaluationOutput()
        }
        return savedOutput
    }

    public var violationComments: [PRComment] {
        outcome?.violationComments(task: request) ?? []
    }

    public init(
        request: RuleRequest,
        phase: PRRadarPhase,
        accumulator: LiveTranscriptAccumulator? = nil,
        savedOutput: EvaluationOutput? = nil,
        outcome: RuleOutcome? = nil
    ) {
        self.request = request
        self.phase = phase
        self.accumulator = accumulator
        self.savedOutput = savedOutput
        self.outcome = outcome
    }
}

// MARK: - Collection Helpers

extension [TaskEvaluation] {
    public var outcomes: [RuleOutcome] {
        compactMap(\.outcome)
    }

    public var violationComments: [PRComment] {
        flatMap(\.violationComments)
    }

    public func indexForTaskId(_ taskId: String) -> Int? {
        firstIndex(where: { $0.request.taskId == taskId })
    }
}
