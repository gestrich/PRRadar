import Foundation

/// Mode-agnostic output from a single rule evaluation.
///
/// Works for AI, regex, and script evaluation modes. Unified format
/// for storing and displaying what happened during an evaluation.
public struct EvaluationOutput: Codable, Sendable {
    public let identifier: String
    public let filePath: String
    public let ruleName: String
    public let source: EvaluationSource
    public let startedAt: String
    public let durationMs: Int
    public let costUsd: Double
    public let entries: [OutputEntry]

    public var mode: RuleAnalysisType {
        switch source {
        case .ai: .ai
        case .regex: .regex
        case .script: .script
        }
    }

    public init(
        identifier: String,
        filePath: String,
        ruleName: String,
        source: EvaluationSource,
        startedAt: String,
        durationMs: Int,
        costUsd: Double,
        entries: [OutputEntry]
    ) {
        self.identifier = identifier
        self.filePath = filePath
        self.ruleName = ruleName
        self.source = source
        self.startedAt = startedAt
        self.durationMs = durationMs
        self.costUsd = costUsd
        self.entries = entries
    }

    enum CodingKeys: String, CodingKey {
        case identifier
        case filePath = "file_path"
        case ruleName = "rule_name"
        case source
        case startedAt = "started_at"
        case durationMs = "duration_ms"
        case costUsd = "cost_usd"
        case entries
    }
}

/// Mode-specific metadata for an evaluation.
public enum EvaluationSource: Codable, Sendable {
    case ai(model: String, prompt: String?)
    case regex(pattern: String)
    case script(path: String)
}

/// A single entry in an evaluation output log.
public struct OutputEntry: Codable, Sendable {
    public let type: EntryType
    public let content: String?
    public let label: String?
    public let timestamp: Date

    public enum EntryType: String, Codable, Sendable {
        case text
        case toolUse
        case result
        case error
    }

    public init(
        type: EntryType,
        content: String? = nil,
        label: String? = nil,
        timestamp: Date = Date()
    ) {
        self.type = type
        self.content = content
        self.label = label
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case type
        case content
        case label
        case timestamp
    }
}