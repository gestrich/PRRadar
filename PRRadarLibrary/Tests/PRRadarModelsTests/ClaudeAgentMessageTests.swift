import Foundation
import Testing
@testable import ClaudeSDK

@Suite("ClaudeAgentMessage JSON-Line Parsing")
struct ClaudeAgentMessageTests {

    // MARK: - Text Messages

    @Test("Parses text message with content")
    func textMessage() {
        let json = #"{"type": "text", "content": "Analyzing the changes..."}"#
        let message = ClaudeAgentMessage(jsonLine: json)

        if case .text(let content) = message {
            #expect(content == "Analyzing the changes...")
        } else {
            Issue.record("Expected .text, got \(String(describing: message))")
        }
    }

    @Test("Parses text message with empty content")
    func textMessageEmpty() {
        let json = #"{"type": "text", "content": ""}"#
        let message = ClaudeAgentMessage(jsonLine: json)

        if case .text(let content) = message {
            #expect(content == "")
        } else {
            Issue.record("Expected .text, got \(String(describing: message))")
        }
    }

    @Test("Parses text message with missing content as empty string")
    func textMessageMissingContent() {
        let json = #"{"type": "text"}"#
        let message = ClaudeAgentMessage(jsonLine: json)

        if case .text(let content) = message {
            #expect(content == "")
        } else {
            Issue.record("Expected .text, got \(String(describing: message))")
        }
    }

    // MARK: - Tool Use Messages

    @Test("Parses tool_use message with name")
    func toolUseMessage() {
        let json = #"{"type": "tool_use", "name": "Read"}"#
        let message = ClaudeAgentMessage(jsonLine: json)

        if case .toolUse(let name) = message {
            #expect(name == "Read")
        } else {
            Issue.record("Expected .toolUse, got \(String(describing: message))")
        }
    }

    @Test("Parses tool_use message with missing name as empty string")
    func toolUseMessageMissingName() {
        let json = #"{"type": "tool_use"}"#
        let message = ClaudeAgentMessage(jsonLine: json)

        if case .toolUse(let name) = message {
            #expect(name == "")
        } else {
            Issue.record("Expected .toolUse, got \(String(describing: message))")
        }
    }

    // MARK: - Result Messages

    @Test("Parses result message with output, cost, and duration")
    func resultMessage() {
        let json = #"{"type": "result", "output": {"score": 5, "comment": "OK"}, "cost_usd": 0.003, "duration_ms": 1500}"#
        let message = ClaudeAgentMessage(jsonLine: json)

        if case .result(let output, let cost, let duration) = message {
            #expect(output != nil)
            #expect(output?["score"] as? Int == 5)
            #expect(output?["comment"] as? String == "OK")
            #expect(cost == 0.003)
            #expect(duration == 1500)
        } else {
            Issue.record("Expected .result, got \(String(describing: message))")
        }
    }

    @Test("Parses result message with null output")
    func resultMessageNullOutput() {
        let json = #"{"type": "result", "output": null, "cost_usd": 0.001, "duration_ms": 200}"#
        let message = ClaudeAgentMessage(jsonLine: json)

        if case .result(let output, let cost, let duration) = message {
            #expect(output == nil)
            #expect(cost == 0.001)
            #expect(duration == 200)
        } else {
            Issue.record("Expected .result, got \(String(describing: message))")
        }
    }

    @Test("Parses result message with missing cost and duration")
    func resultMessageMissingMetadata() {
        let json = #"{"type": "result", "output": {}}"#
        let message = ClaudeAgentMessage(jsonLine: json)

        if case .result(_, let cost, let duration) = message {
            #expect(cost == nil)
            #expect(duration == nil)
        } else {
            Issue.record("Expected .result, got \(String(describing: message))")
        }
    }

    // MARK: - Invalid Input

    @Test("Returns nil for unknown message type")
    func unknownType() {
        let json = #"{"type": "unknown_type", "content": "hi"}"#
        let message = ClaudeAgentMessage(jsonLine: json)
        #expect(message == nil)
    }

    @Test("Returns nil for invalid JSON")
    func invalidJSON() {
        let message = ClaudeAgentMessage(jsonLine: "not json at all")
        #expect(message == nil)
    }

    @Test("Returns nil for JSON without type field")
    func missingType() {
        let json = #"{"content": "hello"}"#
        let message = ClaudeAgentMessage(jsonLine: json)
        #expect(message == nil)
    }

    @Test("Returns nil for empty string")
    func emptyString() {
        let message = ClaudeAgentMessage(jsonLine: "")
        #expect(message == nil)
    }

    // MARK: - ClaudeAgentRequest

    @Test("ClaudeAgentRequest serializes to JSON with required fields")
    func agentRequestToJSON() throws {
        let request = ClaudeAgentRequest(
            prompt: "Analyze this code",
            model: "claude-sonnet-4-20250514"
        )

        let data = try request.toJSON()
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(dict["prompt"] as? String == "Analyze this code")
        #expect(dict["model"] as? String == "claude-sonnet-4-20250514")
        #expect(dict["tools"] == nil)
        #expect(dict["cwd"] == nil)
    }

    @Test("ClaudeAgentRequest serializes optional fields when provided")
    func agentRequestWithOptionals() throws {
        let request = ClaudeAgentRequest(
            prompt: "Test",
            model: "claude-haiku-4-5-20251001",
            tools: ["Read", "Bash"],
            cwd: "/tmp/test"
        )

        let data = try request.toJSON()
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(dict["tools"] as? [String] == ["Read", "Bash"])
        #expect(dict["cwd"] as? String == "/tmp/test")
    }

    @Test("ClaudeAgentRequest serializes output_schema when provided")
    func agentRequestWithSchema() throws {
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["score": ["type": "number"]],
        ]

        let request = ClaudeAgentRequest(
            prompt: "Evaluate",
            outputSchema: schema
        )

        let data = try request.toJSON()
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let outputSchema = dict["output_schema"] as? [String: Any]
        #expect(outputSchema != nil)
        #expect(outputSchema?["type"] as? String == "object")
    }

    // MARK: - ClaudeAgentResult

    @Test("ClaudeAgentResult outputAsDictionary parses JSON data")
    func agentResultParsesOutput() {
        let jsonDict: [String: Any] = ["score": 7, "comment": "Issue found"]
        let data = try! JSONSerialization.data(withJSONObject: jsonDict)

        let result = ClaudeAgentResult(outputData: data, costUsd: 0.01, durationMs: 3000)
        let parsed = result.outputAsDictionary()

        #expect(parsed?["score"] as? Int == 7)
        #expect(parsed?["comment"] as? String == "Issue found")
    }

    @Test("ClaudeAgentResult outputAsDictionary returns nil when outputData is nil")
    func agentResultNilOutput() {
        let result = ClaudeAgentResult(outputData: nil, costUsd: 0.0, durationMs: 0)
        #expect(result.outputAsDictionary() == nil)
    }

    @Test("ClaudeAgentResult outputAsDictionary returns nil for invalid JSON")
    func agentResultInvalidJSON() {
        let data = "not json".data(using: .utf8)!
        let result = ClaudeAgentResult(outputData: data, costUsd: 0.0, durationMs: 0)
        #expect(result.outputAsDictionary() == nil)
    }
}
