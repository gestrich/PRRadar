import Foundation
import Testing
@testable import PRRadarModels

@Suite("EvaluationOutput Encoding/Decoding")
struct EvaluationOutputTests {

    private static func makeRule(name: String = "test-rule", category: String = "safety") -> TaskRule {
        TaskRule(name: name, description: "Test rule", category: category, content: "", rulesDir: "/rules")
    }

    // MARK: - AI Source

    @Test("AI output round-trips through encode/decode")
    func aiOutputRoundTrip() throws {
        // Arrange
        let original = EvaluationOutput(
            identifier: "eval-001",
            filePath: "/tmp/output/eval-001.json",
            rule: Self.makeRule(name: "error-handling"),
            source: .ai(model: "claude-sonnet-4-20250514", prompt: "Check for errors"),
            startedAt: "2026-03-08T10:00:00Z",
            durationMs: 5000,
            costUsd: 0.003,
            entries: [
                OutputEntry(type: .text, content: "Analyzing file...", label: nil, timestamp: Date(timeIntervalSince1970: 1000)),
                OutputEntry(type: .toolUse, content: "read_file", label: "read_file", timestamp: Date(timeIntervalSince1970: 1001)),
                OutputEntry(type: .result, content: "No violations found", label: nil, timestamp: Date(timeIntervalSince1970: 1002)),
            ]
        )

        // Act
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EvaluationOutput.self, from: encoded)

        // Assert
        #expect(decoded.identifier == "eval-001")
        #expect(decoded.filePath == "/tmp/output/eval-001.json")
        #expect(decoded.rule?.name == "error-handling")
        #expect(decoded.startedAt == "2026-03-08T10:00:00Z")
        #expect(decoded.durationMs == 5000)
        #expect(decoded.costUsd == 0.003)
        #expect(decoded.entries.count == 3)
        #expect(decoded.mode == .ai)
        if case .ai(let model, let prompt) = decoded.source {
            #expect(model == "claude-sonnet-4-20250514")
            #expect(prompt == "Check for errors")
        } else {
            Issue.record("Expected .ai source")
        }
    }

    @Test("AI output with nil prompt round-trips")
    func aiOutputNilPrompt() throws {
        // Arrange
        let original = EvaluationOutput(
            identifier: "eval-002",
            filePath: "/tmp/output/eval-002.json",
            rule: Self.makeRule(name: "naming"),
            source: .ai(model: "claude-haiku-4-5-20251001", prompt: nil),
            startedAt: "2026-03-08T11:00:00Z",
            durationMs: 1200,
            costUsd: 0.001,
            entries: []
        )

        // Act
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EvaluationOutput.self, from: encoded)

        // Assert
        if case .ai(let model, let prompt) = decoded.source {
            #expect(model == "claude-haiku-4-5-20251001")
            #expect(prompt == nil)
        } else {
            Issue.record("Expected .ai source")
        }
    }

    @Test("Output with nil rule round-trips")
    func nilRuleRoundTrip() throws {
        // Arrange
        let original = EvaluationOutput(
            identifier: "prep-1",
            filePath: "file.swift",
            rule: nil,
            source: .ai(model: "claude-haiku-4-5-20251001", prompt: "Generate focus areas"),
            startedAt: "2026-03-08T10:00:00Z",
            durationMs: 500,
            costUsd: 0.01,
            entries: []
        )

        // Act
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EvaluationOutput.self, from: encoded)

        // Assert
        #expect(decoded.rule == nil)
        #expect(decoded.identifier == "prep-1")
    }

    // MARK: - Regex Source

    @Test("Regex output round-trips through encode/decode")
    func regexOutputRoundTrip() throws {
        // Arrange
        let original = EvaluationOutput(
            identifier: "eval-regex-001",
            filePath: "/tmp/output/eval-regex-001.json",
            rule: Self.makeRule(name: "no-force-unwrap"),
            source: .regex(pattern: "!\\s*$"),
            startedAt: "2026-03-08T12:00:00Z",
            durationMs: 50,
            costUsd: 0,
            entries: [
                OutputEntry(type: .text, content: "!\\s*$", label: "pattern", timestamp: Date(timeIntervalSince1970: 2000)),
                OutputEntry(type: .text, content: "line 12: value!", label: "match", timestamp: Date(timeIntervalSince1970: 2001)),
                OutputEntry(type: .result, content: "1 violation found", label: nil, timestamp: Date(timeIntervalSince1970: 2002)),
            ]
        )

        // Act
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EvaluationOutput.self, from: encoded)

        // Assert
        #expect(decoded.mode == .regex)
        #expect(decoded.costUsd == 0)
        #expect(decoded.durationMs == 50)
        if case .regex(let pattern) = decoded.source {
            #expect(pattern == "!\\s*$")
        } else {
            Issue.record("Expected .regex source")
        }
    }

    // MARK: - Script Source

    @Test("Script output round-trips through encode/decode")
    func scriptOutputRoundTrip() throws {
        // Arrange
        let original = EvaluationOutput(
            identifier: "eval-script-001",
            filePath: "/tmp/output/eval-script-001.json",
            rule: Self.makeRule(name: "lint-check"),
            source: .script(path: "/usr/local/bin/swiftlint"),
            startedAt: "2026-03-08T13:00:00Z",
            durationMs: 3200,
            costUsd: 0,
            entries: [
                OutputEntry(type: .text, content: "/usr/local/bin/swiftlint lint", label: "command", timestamp: Date(timeIntervalSince1970: 3000)),
                OutputEntry(type: .text, content: "warning: trailing whitespace", label: "stdout", timestamp: Date(timeIntervalSince1970: 3001)),
                OutputEntry(type: .result, content: "1 violation found", label: nil, timestamp: Date(timeIntervalSince1970: 3002)),
            ]
        )

        // Act
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EvaluationOutput.self, from: encoded)

        // Assert
        #expect(decoded.mode == .script)
        if case .script(let path) = decoded.source {
            #expect(path == "/usr/local/bin/swiftlint")
        } else {
            Issue.record("Expected .script source")
        }
    }

    // MARK: - OutputEntry

    @Test("OutputEntry preserves all entry types through round-trip")
    func entryTypesRoundTrip() throws {
        // Arrange
        let entries: [OutputEntry] = [
            OutputEntry(type: .text, content: "some text", label: nil, timestamp: Date(timeIntervalSince1970: 100)),
            OutputEntry(type: .toolUse, content: "tool input", label: "read_file", timestamp: Date(timeIntervalSince1970: 200)),
            OutputEntry(type: .result, content: "final result", label: nil, timestamp: Date(timeIntervalSince1970: 300)),
            OutputEntry(type: .error, content: "something failed", label: nil, timestamp: Date(timeIntervalSince1970: 400)),
        ]

        // Act
        let encoded = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([OutputEntry].self, from: encoded)

        // Assert
        #expect(decoded.count == 4)
        #expect(decoded[0].type == .text)
        #expect(decoded[1].type == .toolUse)
        #expect(decoded[1].label == "read_file")
        #expect(decoded[2].type == .result)
        #expect(decoded[3].type == .error)
        #expect(decoded[3].content == "something failed")
    }

    @Test("OutputEntry with nil content and label")
    func entryNilFields() throws {
        // Arrange
        let entry = OutputEntry(type: .text, content: nil, label: nil, timestamp: Date(timeIntervalSince1970: 0))

        // Act
        let encoded = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(OutputEntry.self, from: encoded)

        // Assert
        #expect(decoded.content == nil)
        #expect(decoded.label == nil)
    }

    // MARK: - JSON Key Mapping

    @Test("EvaluationOutput uses snake_case keys in JSON")
    func snakeCaseKeys() throws {
        // Arrange
        let output = EvaluationOutput(
            identifier: "test",
            filePath: "/tmp/test.json",
            rule: Self.makeRule(),
            source: .regex(pattern: ".*"),
            startedAt: "2026-01-01T00:00:00Z",
            durationMs: 100,
            costUsd: 0,
            entries: []
        )

        // Act
        let data = try JSONEncoder().encode(output)
        let jsonObject = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Assert
        #expect(jsonObject["file_path"] != nil)
        #expect(jsonObject["rule"] != nil)
        #expect(jsonObject["started_at"] != nil)
        #expect(jsonObject["duration_ms"] != nil)
        #expect(jsonObject["cost_usd"] != nil)
        #expect(jsonObject["filePath"] == nil)
    }

    // MARK: - Mode Computed Property

    @Test("mode returns correct RuleAnalysisType for each source")
    func modeProperty() {
        // Arrange
        let aiOutput = EvaluationOutput(identifier: "a", filePath: "", rule: nil, source: .ai(model: "m", prompt: nil), startedAt: "", durationMs: 0, costUsd: 0, entries: [])
        let regexOutput = EvaluationOutput(identifier: "b", filePath: "", rule: nil, source: .regex(pattern: "p"), startedAt: "", durationMs: 0, costUsd: 0, entries: [])
        let scriptOutput = EvaluationOutput(identifier: "c", filePath: "", rule: nil, source: .script(path: "s"), startedAt: "", durationMs: 0, costUsd: 0, entries: [])

        // Assert
        #expect(aiOutput.mode == .ai)
        #expect(regexOutput.mode == .regex)
        #expect(scriptOutput.mode == .script)
    }
}
