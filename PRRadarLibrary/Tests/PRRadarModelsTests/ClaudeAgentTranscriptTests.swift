import Foundation
import Testing
@testable import PRRadarModels

@Suite("ClaudeAgentTranscript Model Encoding/Decoding")
struct ClaudeAgentTranscriptTests {

    // MARK: - ClaudeAgentTranscriptEvent

    @Test("ClaudeAgentTranscriptEvent decodes text event from JSON")
    func textEventDecode() throws {
        let json = """
        {
            "type": "text",
            "content": "Analyzing the code changes...",
            "tool_name": null,
            "timestamp": "2025-06-01T10:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(ClaudeAgentTranscriptEvent.self, from: json)
        #expect(event.type == .text)
        #expect(event.content == "Analyzing the code changes...")
        #expect(event.toolName == nil)
    }

    @Test("ClaudeAgentTranscriptEvent decodes toolUse event from JSON")
    func toolUseEventDecode() throws {
        let json = """
        {
            "type": "toolUse",
            "content": null,
            "tool_name": "Read",
            "timestamp": "2025-06-01T10:00:01Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(ClaudeAgentTranscriptEvent.self, from: json)
        #expect(event.type == .toolUse)
        #expect(event.toolName == "Read")
        #expect(event.content == nil)
    }

    @Test("ClaudeAgentTranscriptEvent decodes result event from JSON")
    func resultEventDecode() throws {
        let json = """
        {
            "type": "result",
            "content": "{\\"score\\": 5}",
            "tool_name": null,
            "timestamp": "2025-06-01T10:00:02Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(ClaudeAgentTranscriptEvent.self, from: json)
        #expect(event.type == .result)
        #expect(event.content == "{\"score\": 5}")
    }

    @Test("ClaudeAgentTranscriptEvent round-trips through encode/decode")
    func eventRoundTrip() throws {
        let original = ClaudeAgentTranscriptEvent(
            type: .text,
            content: "Hello world",
            toolName: nil,
            timestamp: Date(timeIntervalSince1970: 1717200000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ClaudeAgentTranscriptEvent.self, from: data)

        #expect(decoded.type == original.type)
        #expect(decoded.content == original.content)
        #expect(decoded.toolName == original.toolName)
    }

    @Test("ClaudeAgentTranscriptEvent encodes tool_name as snake_case")
    func eventSnakeCaseEncoding() throws {
        let event = ClaudeAgentTranscriptEvent(
            type: .toolUse,
            toolName: "Bash",
            timestamp: Date(timeIntervalSince1970: 0)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        let jsonString = String(data: data, encoding: .utf8)!

        #expect(jsonString.contains("\"tool_name\""))
        #expect(!jsonString.contains("\"toolName\""))
    }

    @Test("ClaudeAgentTranscriptEvent with missing optional fields decodes")
    func eventMissingOptionals() throws {
        let json = """
        {
            "type": "text",
            "timestamp": "2025-06-01T10:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(ClaudeAgentTranscriptEvent.self, from: json)
        #expect(event.type == .text)
        #expect(event.content == nil)
        #expect(event.toolName == nil)
    }

    // MARK: - ClaudeAgentTranscript

    @Test("ClaudeAgentTranscript decodes full transcript from JSON")
    func transcriptDecode() throws {
        let json = """
        {
            "identifier": "task-1",
            "model": "claude-sonnet-4-20250514",
            "started_at": "2025-06-01T10:00:00Z",
            "events": [
                {
                    "type": "text",
                    "content": "Analyzing code...",
                    "timestamp": "2025-06-01T10:00:01Z"
                },
                {
                    "type": "toolUse",
                    "tool_name": "Read",
                    "timestamp": "2025-06-01T10:00:02Z"
                },
                {
                    "type": "result",
                    "content": "{\\"score\\": 3}",
                    "timestamp": "2025-06-01T10:00:03Z"
                }
            ],
            "cost_usd": 0.0045,
            "duration_ms": 3000
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let transcript = try decoder.decode(ClaudeAgentTranscript.self, from: json)
        #expect(transcript.identifier == "task-1")
        #expect(transcript.model == "claude-sonnet-4-20250514")
        #expect(transcript.startedAt == "2025-06-01T10:00:00Z")
        #expect(transcript.events.count == 3)
        #expect(transcript.events[0].type == .text)
        #expect(transcript.events[1].type == .toolUse)
        #expect(transcript.events[2].type == .result)
        #expect(transcript.costUsd == 0.0045)
        #expect(transcript.durationMs == 3000)
    }

    @Test("ClaudeAgentTranscript encodes with snake_case keys")
    func transcriptSnakeCaseEncoding() throws {
        let transcript = ClaudeAgentTranscript(
            identifier: "hunk-0",
            model: "claude-haiku-4-5-20251001",
            startedAt: "2025-06-01T00:00:00Z",
            events: [],
            costUsd: 0.001,
            durationMs: 500
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(transcript)
        let jsonString = String(data: data, encoding: .utf8)!

        #expect(jsonString.contains("\"started_at\""))
        #expect(jsonString.contains("\"cost_usd\""))
        #expect(jsonString.contains("\"duration_ms\""))
        #expect(!jsonString.contains("\"startedAt\""))
        #expect(!jsonString.contains("\"costUsd\""))
        #expect(!jsonString.contains("\"durationMs\""))
    }

    @Test("ClaudeAgentTranscript round-trips through encode/decode")
    func transcriptRoundTrip() throws {
        let events = [
            ClaudeAgentTranscriptEvent(type: .text, content: "Reasoning about the code", timestamp: Date(timeIntervalSince1970: 1717200001)),
            ClaudeAgentTranscriptEvent(type: .toolUse, toolName: "Grep", timestamp: Date(timeIntervalSince1970: 1717200002)),
            ClaudeAgentTranscriptEvent(type: .result, content: "{}", timestamp: Date(timeIntervalSince1970: 1717200003)),
        ]

        let original = ClaudeAgentTranscript(
            identifier: "hunk-3",
            model: "claude-haiku-4-5-20251001",
            startedAt: "2025-06-01T10:00:00Z",
            events: events,
            costUsd: 0.002,
            durationMs: 1500
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ClaudeAgentTranscript.self, from: data)

        #expect(decoded.identifier == original.identifier)
        #expect(decoded.model == original.model)
        #expect(decoded.startedAt == original.startedAt)
        #expect(decoded.events.count == original.events.count)
        #expect(decoded.costUsd == original.costUsd)
        #expect(decoded.durationMs == original.durationMs)
    }

    @Test("ClaudeAgentTranscript with empty events array")
    func transcriptEmptyEvents() throws {
        let json = """
        {
            "identifier": "empty-test",
            "model": "claude-sonnet-4-20250514",
            "started_at": "2025-01-01T00:00:00Z",
            "events": [],
            "cost_usd": 0.0,
            "duration_ms": 0
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let transcript = try decoder.decode(ClaudeAgentTranscript.self, from: json)
        #expect(transcript.events.isEmpty)
        #expect(transcript.costUsd == 0.0)
        #expect(transcript.durationMs == 0)
    }

    // MARK: - Prompt Field

    @Test("ClaudeAgentTranscript decodes JSON without prompt field (backwards compat)")
    func transcriptDecodesWithoutPrompt() throws {
        let json = """
        {
            "identifier": "old-task",
            "model": "claude-sonnet-4-20250514",
            "started_at": "2025-06-01T10:00:00Z",
            "events": [],
            "cost_usd": 0.001,
            "duration_ms": 500
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let transcript = try decoder.decode(ClaudeAgentTranscript.self, from: json)
        #expect(transcript.prompt == nil)
        #expect(transcript.identifier == "old-task")
    }

    @Test("ClaudeAgentTranscript round-trips with prompt")
    func transcriptRoundTripWithPrompt() throws {
        let original = ClaudeAgentTranscript(
            identifier: "prompt-test",
            model: "claude-sonnet-4-20250514",
            startedAt: "2025-06-01T10:00:00Z",
            prompt: "You are a code reviewer evaluating rule X.",
            events: [
                ClaudeAgentTranscriptEvent(type: .text, content: "Analyzing...", timestamp: Date(timeIntervalSince1970: 1717200001)),
            ],
            costUsd: 0.005,
            durationMs: 2000
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ClaudeAgentTranscript.self, from: data)

        #expect(decoded.prompt == "You are a code reviewer evaluating rule X.")
        #expect(decoded.identifier == original.identifier)
        #expect(decoded.events.count == 1)
    }

    @Test("ClaudeAgentTranscript decodes JSON with prompt field")
    func transcriptDecodesWithPrompt() throws {
        let json = """
        {
            "identifier": "task-with-prompt",
            "model": "claude-sonnet-4-20250514",
            "started_at": "2025-06-01T10:00:00Z",
            "prompt": "Evaluate this code for violations.",
            "events": [],
            "cost_usd": 0.002,
            "duration_ms": 1000
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let transcript = try decoder.decode(ClaudeAgentTranscript.self, from: json)
        #expect(transcript.prompt == "Evaluate this code for violations.")
    }

    // MARK: - EventType

    @Test("EventType raw values match expected strings")
    func eventTypeRawValues() {
        #expect(ClaudeAgentTranscriptEvent.EventType.text.rawValue == "text")
        #expect(ClaudeAgentTranscriptEvent.EventType.toolUse.rawValue == "toolUse")
        #expect(ClaudeAgentTranscriptEvent.EventType.result.rawValue == "result")
    }
}
