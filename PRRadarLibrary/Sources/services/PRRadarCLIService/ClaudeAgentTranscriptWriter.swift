import Foundation
import PRRadarModels

/// Writes Claude Agent transcripts to disk as both JSON and Markdown.
public enum ClaudeAgentTranscriptWriter {

    /// Save a transcript as both `.json` and `.md` files in the given directory.
    ///
    /// Files are named `ai-transcript-{identifier}.json` and `ai-transcript-{identifier}.md`.
    public static func write(_ transcript: ClaudeAgentTranscript, to directory: String) throws {
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )

        let baseName = "ai-transcript-\(transcript.identifier)"

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(transcript)
        let jsonPath = "\(directory)/\(baseName).json"
        try jsonData.write(to: URL(fileURLWithPath: jsonPath))

        let markdown = renderMarkdown(transcript)
        let mdPath = "\(directory)/\(baseName).md"
        try markdown.write(toFile: mdPath, atomically: true, encoding: .utf8)
    }

    /// Render a transcript as human-readable Markdown.
    public static func renderMarkdown(_ transcript: ClaudeAgentTranscript) -> String {
        var lines: [String] = []

        lines.append("# AI Transcript: \(transcript.identifier)")
        lines.append("")
        lines.append("**Model:** \(displayName(forModelId: transcript.model))")
        lines.append("**Started:** \(transcript.startedAt)")
        lines.append("")
        lines.append("---")
        lines.append("")

        if let prompt = transcript.prompt {
            lines.append("## Prompt")
            lines.append("")
            lines.append("```")
            lines.append(prompt)
            lines.append("```")
            lines.append("")
            lines.append("---")
            lines.append("")
        }

        for event in transcript.events {
            switch event.type {
            case .text:
                if let content = event.content {
                    lines.append("> \(content)")
                    lines.append("")
                }
            case .toolUse:
                let name = event.toolName ?? "unknown"
                lines.append("<details>")
                lines.append("<summary>Tool: \(name)</summary>")
                lines.append("")
                if let content = event.content {
                    lines.append("```")
                    lines.append(content)
                    lines.append("```")
                    lines.append("")
                }
                lines.append("</details>")
                lines.append("")
            case .result:
                if let content = event.content {
                    lines.append("**Result:**")
                    lines.append("")
                    lines.append("```json")
                    lines.append(content)
                    lines.append("```")
                    lines.append("")
                }
            }
        }

        lines.append("---")
        lines.append("")
        lines.append("**Duration:** \(transcript.durationMs)ms")
        lines.append("**Cost:** $\(String(format: "%.4f", transcript.costUsd))")
        lines.append("**Model:** \(transcript.model)")
        lines.append("")

        return lines.joined(separator: "\n")
    }
}
