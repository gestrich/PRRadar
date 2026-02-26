import Foundation

public struct TaskEvaluation: Identifiable, Sendable {
    public let request: RuleRequest
    public let phase: PRRadarPhase
    public var accumulator: LiveTranscriptAccumulator?
    public var savedTranscript: ClaudeAgentTranscript?
    public var outcome: RuleOutcome?

    public var id: String { request.taskId }

    public var isStreaming: Bool { accumulator != nil && outcome == nil }
    public var isComplete: Bool { outcome != nil }
    public var isQueued: Bool { accumulator == nil && outcome == nil }

    public var transcript: ClaudeAgentTranscript? {
        if let acc = accumulator {
            return acc.toClaudeAgentTranscript()
        }
        return savedTranscript
    }

    public var violationComment: PRComment? {
        outcome?.violationComment(task: request)
    }

    public init(
        request: RuleRequest,
        phase: PRRadarPhase,
        accumulator: LiveTranscriptAccumulator? = nil,
        savedTranscript: ClaudeAgentTranscript? = nil,
        outcome: RuleOutcome? = nil
    ) {
        self.request = request
        self.phase = phase
        self.accumulator = accumulator
        self.savedTranscript = savedTranscript
        self.outcome = outcome
    }
}

// MARK: - Collection Helpers

extension [TaskEvaluation] {
    public var outcomes: [RuleOutcome] {
        compactMap(\.outcome)
    }

    public var violationComments: [PRComment] {
        compactMap(\.violationComment)
    }

    public func indexForTaskId(_ taskId: String) -> Int? {
        firstIndex(where: { $0.request.taskId == taskId })
    }
}
