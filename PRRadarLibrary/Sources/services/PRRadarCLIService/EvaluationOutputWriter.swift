import Foundation
import PRRadarModels

/// Writes `EvaluationOutput` to disk as both JSON and Markdown.
public enum EvaluationOutputWriter {

    /// Save an evaluation output as both `.json` and `.md` files in the given directory.
    ///
    /// Files are named `output-{identifier}.json` and `output-{identifier}.md`.
    public static func write(_ output: EvaluationOutput, to directory: String) throws {
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )

        let baseName = "output-\(output.identifier)"

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(output)
        let jsonPath = "\(directory)/\(baseName).json"
        try jsonData.write(to: URL(fileURLWithPath: jsonPath))

        let markdown = renderMarkdown(output)
        let mdPath = "\(directory)/\(baseName).md"
        try markdown.write(toFile: mdPath, atomically: true, encoding: .utf8)
    }

    /// Render an evaluation output as human-readable Markdown.
    public static func renderMarkdown(_ output: EvaluationOutput) -> String {
        var lines: [String] = []

        let modeLabel = output.mode.rawValue.uppercased()
        lines.append("# Evaluation Output: \(output.identifier)")
        lines.append("")
        lines.append("**Mode:** \(modeLabel)")

        switch output.source {
        case .ai(let model, _):
            lines.append("**Model:** \(displayName(forModelId: model))")
        case .regex(let pattern):
            lines.append("**Pattern:** `\(pattern)`")
        case .script(let path):
            lines.append("**Script:** \(path)")
        }

        lines.append("**Started:** \(output.startedAt)")
        lines.append("")
        lines.append("---")
        lines.append("")

        if case .ai(_, let prompt) = output.source, let prompt {
            lines.append("## Prompt")
            lines.append("")
            lines.append("```")
            lines.append(prompt)
            lines.append("```")
            lines.append("")
            lines.append("---")
            lines.append("")
        }

        for entry in output.entries {
            switch entry.type {
            case .text:
                if let content = entry.content {
                    if let label = entry.label {
                        lines.append("**\(label):**")
                        lines.append("")
                    }
                    lines.append("> \(content.replacingOccurrences(of: "\n", with: "\n> "))")
                    lines.append("")
                }
            case .toolUse:
                let name = entry.label ?? "unknown"
                lines.append("<details>")
                lines.append("<summary>Tool: \(name)</summary>")
                lines.append("")
                if let content = entry.content {
                    lines.append("```")
                    lines.append(content)
                    lines.append("```")
                    lines.append("")
                }
                lines.append("</details>")
                lines.append("")
            case .result:
                if let content = entry.content {
                    lines.append("**Result:**")
                    lines.append("")
                    lines.append("```")
                    lines.append(content)
                    lines.append("```")
                    lines.append("")
                }
            case .error:
                if let content = entry.content {
                    lines.append("**Error:**")
                    lines.append("")
                    lines.append("```")
                    lines.append(content)
                    lines.append("```")
                    lines.append("")
                }
            }
        }

        lines.append("---")
        lines.append("")
        lines.append("**Duration:** \(output.durationMs)ms")
        if output.costUsd > 0 {
            lines.append("**Cost:** $\(String(format: "%.4f", output.costUsd))")
        }
        lines.append("")

        return lines.joined(separator: "\n")
    }
}
