import Foundation
import Testing
@testable import PRRadarModels
@testable import PRRadarCLIService

@Suite("ClaudeAgentTranscriptWriter")
struct ClaudeAgentTranscriptWriterTests {

    // MARK: - Markdown Rendering

    @Test("renderMarkdown includes header with model display name and timestamp")
    func markdownHeader() {
        let transcript = ClaudeAgentTranscript(
            identifier: "task-1",
            model: "claude-sonnet-4-20250514",
            startedAt: "2025-06-01T10:00:00Z",
            events: [],
            costUsd: 0.005,
            durationMs: 2000
        )

        let md = ClaudeAgentTranscriptWriter.renderMarkdown(transcript)
        #expect(md.contains("# AI Transcript: task-1"))
        #expect(md.contains("**Model:** Sonnet 4"))
        #expect(md.contains("**Started:** 2025-06-01T10:00:00Z"))
    }

    @Test("renderMarkdown renders text events as blockquotes")
    func markdownTextEvents() {
        let transcript = ClaudeAgentTranscript(
            identifier: "test",
            model: "claude-haiku-4-5-20251001",
            startedAt: "2025-01-01T00:00:00Z",
            events: [
                ClaudeAgentTranscriptEvent(type: .text, content: "Analyzing the code changes"),
            ],
            costUsd: 0.001,
            durationMs: 500
        )

        let md = ClaudeAgentTranscriptWriter.renderMarkdown(transcript)
        #expect(md.contains("> Analyzing the code changes"))
    }

    @Test("renderMarkdown renders tool use events as collapsible sections")
    func markdownToolUseEvents() {
        let transcript = ClaudeAgentTranscript(
            identifier: "test",
            model: "claude-sonnet-4-20250514",
            startedAt: "2025-01-01T00:00:00Z",
            events: [
                ClaudeAgentTranscriptEvent(type: .toolUse, content: "file content here", toolName: "Read"),
            ],
            costUsd: 0.003,
            durationMs: 1000
        )

        let md = ClaudeAgentTranscriptWriter.renderMarkdown(transcript)
        #expect(md.contains("<details>"))
        #expect(md.contains("<summary>Tool: Read</summary>"))
        #expect(md.contains("file content here"))
        #expect(md.contains("</details>"))
    }

    @Test("renderMarkdown renders tool use with unknown name when toolName is nil")
    func markdownToolUseUnknownName() {
        let transcript = ClaudeAgentTranscript(
            identifier: "test",
            model: "claude-sonnet-4-20250514",
            startedAt: "2025-01-01T00:00:00Z",
            events: [
                ClaudeAgentTranscriptEvent(type: .toolUse, content: nil, toolName: nil),
            ],
            costUsd: 0.0,
            durationMs: 0
        )

        let md = ClaudeAgentTranscriptWriter.renderMarkdown(transcript)
        #expect(md.contains("<summary>Tool: unknown</summary>"))
    }

    @Test("renderMarkdown renders result events as JSON code blocks")
    func markdownResultEvents() {
        let transcript = ClaudeAgentTranscript(
            identifier: "test",
            model: "claude-sonnet-4-20250514",
            startedAt: "2025-01-01T00:00:00Z",
            events: [
                ClaudeAgentTranscriptEvent(type: .result, content: "{\"score\": 5}"),
            ],
            costUsd: 0.002,
            durationMs: 800
        )

        let md = ClaudeAgentTranscriptWriter.renderMarkdown(transcript)
        #expect(md.contains("**Result:**"))
        #expect(md.contains("```json"))
        #expect(md.contains("{\"score\": 5}"))
    }

    @Test("renderMarkdown includes footer with duration, cost, and model")
    func markdownFooter() {
        let transcript = ClaudeAgentTranscript(
            identifier: "test",
            model: "claude-sonnet-4-20250514",
            startedAt: "2025-01-01T00:00:00Z",
            events: [],
            costUsd: 0.0123,
            durationMs: 4567
        )

        let md = ClaudeAgentTranscriptWriter.renderMarkdown(transcript)
        #expect(md.contains("**Duration:** 4567ms"))
        #expect(md.contains("**Cost:** $0.0123"))
        #expect(md.contains("**Model:** claude-sonnet-4-20250514"))
    }

    @Test("renderMarkdown includes prompt section when prompt is present")
    func markdownPromptSection() {
        let transcript = ClaudeAgentTranscript(
            identifier: "prompt-test",
            model: "claude-sonnet-4-20250514",
            startedAt: "2025-01-01T00:00:00Z",
            prompt: "You are a code reviewer evaluating rule X.",
            events: [
                ClaudeAgentTranscriptEvent(type: .text, content: "Analyzing..."),
            ],
            costUsd: 0.005,
            durationMs: 2000
        )

        let md = ClaudeAgentTranscriptWriter.renderMarkdown(transcript)
        #expect(md.contains("## Prompt"))
        #expect(md.contains("You are a code reviewer evaluating rule X."))

        let promptPos = md.range(of: "## Prompt")!.lowerBound
        let eventPos = md.range(of: "> Analyzing...")!.lowerBound
        #expect(promptPos < eventPos)
    }

    @Test("renderMarkdown omits prompt section when prompt is nil")
    func markdownNoPromptSection() {
        let transcript = ClaudeAgentTranscript(
            identifier: "no-prompt",
            model: "claude-sonnet-4-20250514",
            startedAt: "2025-01-01T00:00:00Z",
            events: [],
            costUsd: 0.001,
            durationMs: 500
        )

        let md = ClaudeAgentTranscriptWriter.renderMarkdown(transcript)
        #expect(!md.contains("## Prompt"))
    }

    @Test("renderMarkdown handles multiple events in order")
    func markdownMultipleEvents() {
        let transcript = ClaudeAgentTranscript(
            identifier: "multi",
            model: "claude-sonnet-4-20250514",
            startedAt: "2025-01-01T00:00:00Z",
            events: [
                ClaudeAgentTranscriptEvent(type: .text, content: "First thought"),
                ClaudeAgentTranscriptEvent(type: .toolUse, toolName: "Grep"),
                ClaudeAgentTranscriptEvent(type: .text, content: "Second thought"),
                ClaudeAgentTranscriptEvent(type: .result, content: "{\"done\": true}"),
            ],
            costUsd: 0.01,
            durationMs: 5000
        )

        let md = ClaudeAgentTranscriptWriter.renderMarkdown(transcript)

        // Verify order by checking relative positions
        let firstPos = md.range(of: "> First thought")!.lowerBound
        let toolPos = md.range(of: "Tool: Grep")!.lowerBound
        let secondPos = md.range(of: "> Second thought")!.lowerBound
        let resultPos = md.range(of: "\"done\": true")!.lowerBound

        #expect(firstPos < toolPos)
        #expect(toolPos < secondPos)
        #expect(secondPos < resultPos)
    }

    // MARK: - File Writing

    @Test("write creates both JSON and Markdown files")
    func writeCreatesBothFiles() throws {
        let tmpDir = NSTemporaryDirectory() + "prradar-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let transcript = ClaudeAgentTranscript(
            identifier: "task-42",
            model: "claude-sonnet-4-20250514",
            startedAt: "2025-06-01T10:00:00Z",
            events: [
                ClaudeAgentTranscriptEvent(type: .text, content: "Hello"),
            ],
            costUsd: 0.003,
            durationMs: 1200
        )

        try ClaudeAgentTranscriptWriter.write(transcript, to: tmpDir)

        let jsonPath = "\(tmpDir)/ai-transcript-task-42.json"
        let mdPath = "\(tmpDir)/ai-transcript-task-42.md"

        #expect(FileManager.default.fileExists(atPath: jsonPath))
        #expect(FileManager.default.fileExists(atPath: mdPath))
    }

    @Test("write produces valid JSON that can be decoded back")
    func writeProducesValidJSON() throws {
        let tmpDir = NSTemporaryDirectory() + "prradar-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let original = ClaudeAgentTranscript(
            identifier: "round-trip",
            model: "claude-haiku-4-5-20251001",
            startedAt: "2025-03-15T08:30:00Z",
            events: [
                ClaudeAgentTranscriptEvent(
                    type: .text,
                    content: "Checking for issues",
                    timestamp: Date(timeIntervalSince1970: 1717200000)
                ),
                ClaudeAgentTranscriptEvent(
                    type: .toolUse,
                    toolName: "Bash",
                    timestamp: Date(timeIntervalSince1970: 1717200001)
                ),
            ],
            costUsd: 0.0015,
            durationMs: 900
        )

        try ClaudeAgentTranscriptWriter.write(original, to: tmpDir)

        let jsonPath = "\(tmpDir)/ai-transcript-round-trip.json"
        let jsonData = try Data(contentsOf: URL(fileURLWithPath: jsonPath))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ClaudeAgentTranscript.self, from: jsonData)

        #expect(decoded.identifier == original.identifier)
        #expect(decoded.model == original.model)
        #expect(decoded.events.count == 2)
        #expect(decoded.costUsd == original.costUsd)
        #expect(decoded.durationMs == original.durationMs)
    }

    @Test("write produces Markdown file with expected content")
    func writeProducesMarkdown() throws {
        let tmpDir = NSTemporaryDirectory() + "prradar-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let transcript = ClaudeAgentTranscript(
            identifier: "md-test",
            model: "claude-sonnet-4-20250514",
            startedAt: "2025-01-01T00:00:00Z",
            events: [
                ClaudeAgentTranscriptEvent(type: .text, content: "AI reasoning here"),
            ],
            costUsd: 0.005,
            durationMs: 2000
        )

        try ClaudeAgentTranscriptWriter.write(transcript, to: tmpDir)

        let mdPath = "\(tmpDir)/ai-transcript-md-test.md"
        let mdContent = try String(contentsOfFile: mdPath, encoding: .utf8)

        #expect(mdContent.contains("# AI Transcript: md-test"))
        #expect(mdContent.contains("> AI reasoning here"))
        #expect(mdContent.contains("**Duration:** 2000ms"))
    }

    @Test("write creates intermediate directories")
    func writeCreatesDirectories() throws {
        let tmpDir = NSTemporaryDirectory() + "prradar-test-\(UUID().uuidString)/nested/deep"
        defer {
            let base = (tmpDir as NSString).deletingLastPathComponent
            let root = (base as NSString).deletingLastPathComponent
            try? FileManager.default.removeItem(atPath: root)
        }

        let transcript = ClaudeAgentTranscript(
            identifier: "nested",
            model: "claude-sonnet-4-20250514",
            startedAt: "2025-01-01T00:00:00Z",
            events: [],
            costUsd: 0.0,
            durationMs: 0
        )

        try ClaudeAgentTranscriptWriter.write(transcript, to: tmpDir)
        #expect(FileManager.default.fileExists(atPath: "\(tmpDir)/ai-transcript-nested.json"))
    }
}
