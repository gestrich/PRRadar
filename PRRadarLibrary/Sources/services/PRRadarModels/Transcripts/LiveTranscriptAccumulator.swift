import Foundation

public struct LiveTranscriptAccumulator: Sendable {
    public let identifier: String
    public var prompt: String
    public var filePath: String?
    public var ruleName: String?
    public var textChunks: String = ""
    public var events: [OutputEntry] = []
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
            events.append(OutputEntry(type: .text, content: textChunks))
            textChunks = ""
        }
        events.append(OutputEntry(type: .toolUse, label: name))
    }

    public func toEvaluationOutput() -> EvaluationOutput {
        var finalEntries = events
        if !textChunks.isEmpty {
            finalEntries.append(OutputEntry(type: .text, content: textChunks))
        }
        let formatter = ISO8601DateFormatter()
        return EvaluationOutput(
            identifier: identifier,
            filePath: filePath ?? "",
            ruleName: ruleName ?? "",
            source: .ai(model: "streaming", prompt: prompt.isEmpty ? nil : prompt),
            startedAt: formatter.string(from: startedAt),
            durationMs: Int(Date().timeIntervalSince(startedAt) * 1000),
            costUsd: 0,
            entries: finalEntries
        )
    }
}
