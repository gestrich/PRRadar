import Foundation
import PRRadarConfigService
import PRRadarModels

struct TaskEvaluation: Identifiable {
    let request: RuleRequest
    let phase: PRRadarPhase
    var accumulator: PRModel.LiveTranscriptAccumulator?
    var savedTranscript: ClaudeAgentTranscript?
    var outcome: RuleOutcome?

    var id: String { request.taskId }

    var isStreaming: Bool { accumulator != nil && outcome == nil }
    var isComplete: Bool { outcome != nil }
    var isQueued: Bool { accumulator == nil && outcome == nil }

    var transcript: ClaudeAgentTranscript? {
        if let acc = accumulator {
            return acc.toClaudeAgentTranscript()
        }
        return savedTranscript
    }
}
