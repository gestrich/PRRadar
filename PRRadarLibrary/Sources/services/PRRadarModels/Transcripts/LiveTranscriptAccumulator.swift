import Foundation

public struct LiveTranscriptAccumulator: Sendable {
    public let identifier: String
    public var prompt: String
    public var filePath: String?
    public var ruleName: String?
    public var textChunks: String = ""
    public var events: [ClaudeAgentTranscriptEvent] = []
    public let startedAt: Date

    public init(identifier: String, prompt: String, filePath: String? = nil, ruleName: String? = nil, startedAt: Date) {
        self.identifier = identifier
        self.prompt = prompt
        self.filePath = filePath
        self.ruleName = ruleName
        self.startedAt = startedAt
    }

    public mutating func flushTextAndAppendToolUse(_ name: String) {
        if !textChunks.isEmpty {
            events.append(ClaudeAgentTranscriptEvent(type: .text, content: textChunks))
            textChunks = ""
        }
        events.append(ClaudeAgentTranscriptEvent(type: .toolUse, toolName: name))
    }

    public func toClaudeAgentTranscript() -> ClaudeAgentTranscript {
        var finalEvents = events
        if !textChunks.isEmpty {
            finalEvents.append(ClaudeAgentTranscriptEvent(type: .text, content: textChunks))
        }
        let formatter = ISO8601DateFormatter()
        return ClaudeAgentTranscript(
            identifier: identifier,
            model: "streaming",
            startedAt: formatter.string(from: startedAt),
            prompt: prompt.isEmpty ? nil : prompt,
            filePath: filePath ?? "",
            ruleName: ruleName ?? "",
            events: finalEvents,
            costUsd: 0,
            durationMs: Int(Date().timeIntervalSince(startedAt) * 1000)
        )
    }
}
