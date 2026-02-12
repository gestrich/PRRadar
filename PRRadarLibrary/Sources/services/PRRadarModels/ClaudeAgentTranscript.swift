import Foundation

/// A single streaming event from a Claude Agent SDK invocation.
public struct ClaudeAgentTranscriptEvent: Codable, Sendable {
    public let type: EventType
    public let content: String?
    public let toolName: String?
    public let timestamp: Date

    public enum EventType: String, Codable, Sendable {
        case text
        case toolUse
        case result
    }

    public init(
        type: EventType,
        content: String? = nil,
        toolName: String? = nil,
        timestamp: Date = Date()
    ) {
        self.type = type
        self.content = content
        self.toolName = toolName
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case type
        case content
        case toolName = "tool_name"
        case timestamp
    }
}

/// Complete transcript of a single Claude Agent SDK invocation.
public struct ClaudeAgentTranscript: Codable, Sendable {
    public let identifier: String
    public let model: String
    public let startedAt: String
    public let prompt: String?
    public let events: [ClaudeAgentTranscriptEvent]
    public let costUsd: Double
    public let durationMs: Int

    public init(
        identifier: String,
        model: String,
        startedAt: String,
        prompt: String? = nil,
        events: [ClaudeAgentTranscriptEvent],
        costUsd: Double,
        durationMs: Int
    ) {
        self.identifier = identifier
        self.model = model
        self.startedAt = startedAt
        self.prompt = prompt
        self.events = events
        self.costUsd = costUsd
        self.durationMs = durationMs
    }

    enum CodingKeys: String, CodingKey {
        case identifier
        case model
        case startedAt = "started_at"
        case prompt
        case events
        case costUsd = "cost_usd"
        case durationMs = "duration_ms"
    }
}
