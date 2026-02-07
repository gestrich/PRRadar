import Foundation

// MARK: - Phase 1: Diff Output Models

/// A single hunk from a parsed diff, matching Python's Hunk.to_dict()
public struct ParsedHunk: Codable, Sendable {
    public let filePath: String
    public let content: String
    public let oldStart: Int
    public let oldLength: Int
    public let newStart: Int
    public let newLength: Int

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case content
        case oldStart = "old_start"
        case oldLength = "old_length"
        case newStart = "new_start"
        case newLength = "new_length"
    }
}

/// Top-level container parsed from diff-parsed.json, matching Python's GitDiff.to_dict()
public struct PRDiffOutput: Codable, Sendable {
    public let commitHash: String
    public let hunks: [ParsedHunk]

    enum CodingKeys: String, CodingKey {
        case commitHash = "commit_hash"
        case hunks
    }
}

/// Effective diff output — same structure as PRDiffOutput but with deduplicated hunks.
/// Parsed from effective-diff-parsed.json.
public typealias EffectiveDiffOutput = PRDiffOutput

/// A single code move detected by the effective diff algorithm.
public struct MoveDetail: Codable, Sendable {
    public let sourceFile: String
    public let targetFile: String
    public let sourceLines: [Int]
    public let targetLines: [Int]
    public let matchedLines: Int
    public let score: Double
    public let effectiveDiffLines: Int

    enum CodingKeys: String, CodingKey {
        case sourceFile = "source_file"
        case targetFile = "target_file"
        case sourceLines = "source_lines"
        case targetLines = "target_lines"
        case matchedLines = "matched_lines"
        case score
        case effectiveDiffLines = "effective_diff_lines"
    }
}

/// Move detection report parsed from effective-diff-moves.json.
public struct MoveReport: Codable, Sendable {
    public let movesDetected: Int
    public let totalLinesMoved: Int
    public let totalLinesEffectivelyChanged: Int
    public let moves: [MoveDetail]

    enum CodingKeys: String, CodingKey {
        case movesDetected = "moves_detected"
        case totalLinesMoved = "total_lines_moved"
        case totalLinesEffectivelyChanged = "total_lines_effectively_changed"
        case moves
    }
}
